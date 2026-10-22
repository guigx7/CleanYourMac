import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct SpaceRemovalTests {
    func node(_ root: SpaceNode, _ rel: String) -> SpaceNode? {
        var n: SpaceNode? = root
        for part in rel.split(separator: "/") { n = n?.child(String(part)) }
        return n
    }

    @Test func essentialsNeverRemovable() throws {
        let p = SpaceProtection(home: URL(fileURLWithPath: "/Users/me"))
        #expect(p.level(path: "/") == .essential)
        for path in ["/System", "/usr", "/bin", "/System/Volumes", "/Users/me", "/Users/me/Library", "/Users/me/Documents", "/Applications", "/opt"] {
            #expect(p.level(path: path) != .none, "\(path)")
        }
        #expect(p.level(path: "/System") == .essential)
        #expect(p.level(path: "/Users/me/Projetos") == .none)
        #expect(p.level(path: "/Users/me/Library/Caches/com.example") == .none)
    }

    @Test func systemFolderShowsNoCheckboxButContentDoes() {
        let p = SpaceProtection(home: URL(fileURLWithPath: "/Users/me"))
        #expect(p.level(path: "/Users/me/Downloads") == .systemFolder)
        #expect(p.level(path: "/Users/me/Downloads/big.dmg") == .none)
        #expect(p.level(path: "/Users/me/Library/Application Support") == .systemFolder)
    }

    @Test func restrictedFlagIsEssential() {
        // /System tem SF_RESTRICTED em todo Mac com SIP.
        #expect(SpaceProtection.isRestricted("/System"))
        #expect(!SpaceProtection.isRestricted(FileManager.default.temporaryDirectory.path))
    }

    @Test func removalTrashesAndRevalidates() async throws {
        let t = FixtureTree()
        t.file("keep/a.bin", bytes: 1000)
        t.file("go/b.bin", bytes: 1000)
        t.file("swap.bin", bytes: 1000)
        let root = try SpaceScanner().scan(t.root)
        let trasher = FixtureTrasher(t.url("Users/me/.Trash"))
        let remover = SpaceRemover(trasher: trasher, protection: SpaceProtection(home: t.url("Users/me")), dryRun: false,
                                   log: CleanupLog(directory: t.url("logs")))
        // Trocado depois da análise: virou link → recusado sem tocar.
        try FileManager.default.removeItem(at: t.url("swap.bin"))
        _ = t.symlink("swap.bin", to: t.url("keep/a.bin"))
        let go = try #require(node(root, "go")), swap = try #require(node(root, "swap.bin"))
        let r = await remover.remove([go, swap])
        #expect((try? r[go.path]?.get()) != nil)
        if case .failure(let f) = r[swap.path] { #expect(f.reason == "item changed") } else { Issue.record("deveria recusar") }
        #expect(trasher.trashed.map(\.lastPathComponent) == ["go"])
        #expect(FileManager.default.fileExists(atPath: t.url("keep/a.bin").path))
    }

    @Test func protectedNeverRemovedEvenIfAsked() async throws {
        let t = FixtureTree()
        t.file("Users/me/Downloads/x", bytes: 10)
        let root = try SpaceScanner().scan(t.root)
        let trasher = FixtureTrasher(t.url("trash"))
        let remover = SpaceRemover(trasher: trasher, protection: SpaceProtection(home: t.url("Users/me")), dryRun: false,
                                   log: CleanupLog(directory: t.url("logs")))
        let downloads = try #require(node(root, "Users/me/Downloads"))
        let home = try #require(node(root, "Users/me"))
        let r = await remover.remove([downloads, home])
        #expect(r.values.allSatisfy { (try? $0.get()) == nil })
        #expect(trasher.trashed.isEmpty)
    }

    @Test func dryRunTouchesNothing() async throws {
        let t = FixtureTree()
        let f = t.file("a.bin", bytes: 10)
        let root = try SpaceScanner().scan(t.root)
        let trasher = FixtureTrasher(t.url("trash"))
        let remover = SpaceRemover(trasher: trasher, protection: SpaceProtection(home: t.url("Users/me")), dryRun: true,
                                   log: CleanupLog(directory: t.url("logs")))
        let r = await remover.remove([try #require(root.child("a.bin"))])
        #expect((try? r[f.path]?.get()) != nil)
        #expect(trasher.trashed.isEmpty && FileManager.default.fileExists(atPath: f.path))
    }
}

@Test func localFilesAreNotCloudOnly() {
    #expect(!SpaceProtection.isCloudOnly(FileManager.default.temporaryDirectory.path))
}

/// Um nó que já saiu da árvore tem caminho relativo: nunca é removido (o cwd do app resolveria outro item).
@Test func detachedNodeIsRefused() async throws {
    let t = FixtureTree()
    t.file("a/b/c.bin", bytes: 10)
    let root = try SpaceScanner().scan(t.root)
    let a = try #require(root.child("a")), b = try #require(a.child("b"))
    a.detach()
    let trasher = FixtureTrasher(t.url("trash"))
    let r = await SpaceRemover(trasher: trasher, protection: SpaceProtection(home: t.url("Users/me")), dryRun: false,
                               log: CleanupLog(directory: t.url("logs"))).remove([b])
    // Recusado por estar fora da árvore (não por acaso de o caminho relativo não existir no diretório atual).
    #expect(r.values.allSatisfy { if case .failure(let f) = $0 { f.reason == "detached" } else { false } })
    #expect(trasher.trashed.isEmpty)
}

/// Dados pessoais que quebram o Mac ou somem com o histórico se forem para o Lixo.
@Test func personalDataInLibraryIsEssential() {
    let p = SpaceProtection(home: URL(fileURLWithPath: "/Users/me"))
    for rel in ["Keychains", "Messages", "Accounts", "Safari", "Calendars", "Cookies", "IdentityServices",
                "Application Support/AddressBook", "Mail"] {
        #expect(p.level(path: "/Users/me/Library/" + rel) == .essential, "\(rel)")
    }
    // O conteúdo de pastas comuns continua marcável.
    #expect(p.level(path: "/Users/me/Library/Caches/com.example") == .none)
}

/// Trocado por outro com o mesmo nome, ou com um link no meio do caminho: recusado sem tocar em nada.
@Test func removalChecksIdentityAndParentPath() async throws {
    let t = FixtureTree()
    t.file("p/same.bin", bytes: 1000)
    t.file("q/inner/big.bin", bytes: 1000)
    t.file("elsewhere/inner/big.bin", bytes: 1000)
    let root = try SpaceScanner().scan(t.root)
    let same = try #require(root.child("p")?.child("same.bin"))
    let big = try #require(root.child("q")?.child("inner")?.child("big.bin"))
    // Mesmo nome, outro arquivo.
    try FileManager.default.removeItem(at: t.url("p/same.bin"))
    t.file("p/same.bin", bytes: 1000)
    // "q" vira um link para outra pasta com o mesmo conteúdo.
    try FileManager.default.moveItem(at: t.url("q"), to: t.url("q-old"))
    _ = t.symlink("q", to: t.url("elsewhere"))
    let trasher = FixtureTrasher(t.url("trash"))
    let r = await SpaceRemover(trasher: trasher, protection: SpaceProtection(home: t.url("Users/me")), dryRun: false,
                               log: CleanupLog(directory: t.url("logs"))).remove([same, big])
    #expect(r.values.allSatisfy { if case .failure(let f) = $0 { f.reason == "item changed" } else { false } })
    #expect(trasher.trashed.isEmpty)
}

/// Pasta analisada por um caminho com link (ex.: /tmp → /private/tmp): a remoção funciona pelo caminho real.
@Test func scanThroughSymlinkedRootStillRemoves() async throws {
    let t = FixtureTree()
    t.file("real/x.bin", bytes: 1000)
    let alias = t.symlink("alias", to: t.url("real"))
    let root = try SpaceScanner().scan(alias)
    let x = try #require(root.child("x.bin"))
    let trasher = FixtureTrasher(t.url("trash"))
    let r = await SpaceRemover(trasher: trasher, protection: SpaceProtection(home: t.url("Users/me")), dryRun: false,
                               log: CleanupLog(directory: t.url("logs"))).remove([x])
    #expect(r.values.allSatisfy { (try? $0.get()) != nil })
    #expect(trasher.trashed.map(\.lastPathComponent) == ["x.bin"])
}
