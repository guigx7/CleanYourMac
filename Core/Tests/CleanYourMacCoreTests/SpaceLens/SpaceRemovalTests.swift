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
