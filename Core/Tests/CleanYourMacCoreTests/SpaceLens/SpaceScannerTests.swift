import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct SpaceScannerTests {
    func scan(_ t: FixtureTree, _ options: SpaceScanner.Options = .init()) throws -> SpaceNode {
        try SpaceScanner(options: options).scan(t.root)
    }

    func alloc(_ u: URL) -> Int64 { FixtureTree.allocated(u) }

    @Test func sizesAreAllocatedAndAggregated() throws {
        let t = FixtureTree()
        let a = t.file("a/x.bin", bytes: 10_000)
        let b = t.file("a/b/y.bin", bytes: 300_000)
        let c = t.file("c.bin", bytes: 5_000)
        let root = try scan(t)
        let expected = alloc(a) + alloc(b) + alloc(c)
        #expect(root.size >= expected && root.size - expected < 64 * 1024)
        // Filhos por tamanho, maior primeiro.
        #expect(root.children.map(\.name) == ["a", "c.bin"])
        let folderA = try #require(root.child("a"))
        #expect(folderA.isDirectory)
        #expect(folderA.child("b")?.child("y.bin")?.size == alloc(b))
    }

    @Test func itemCountIncludesFolders() throws {
        let t = FixtureTree()
        t.file("a/x", bytes: 1)
        t.file("a/b/y", bytes: 1)
        // a, x, b, y abaixo da raiz.
        #expect(try scan(t).items == 4)
    }

    @Test func hiddenFilesIncluded() throws {
        let t = FixtureTree()
        t.file(".hidden/z", bytes: 4096)
        #expect(try scan(t).child(".hidden") != nil)
    }

    @Test func hardLinksCountedPerPath() throws {
        let t = FixtureTree()
        let a = t.file("a.bin", bytes: 100_000)
        try FileManager.default.linkItem(at: a, to: t.url("b.bin"))
        let root = try scan(t)
        #expect(root.child("b.bin")?.size == alloc(a))
        #expect(root.size >= 2 * alloc(a))
    }

    @Test func symlinksNotFollowed() throws {
        let t = FixtureTree()
        let big = t.file("outside/big.bin", bytes: 1_000_000)
        let inner = t.dir("inner")
        _ = t.symlink("inner/link", to: big.deletingLastPathComponent())
        let root = try SpaceScanner().scan(inner)
        #expect(root.size < 100_000)
        #expect(root.child("link")?.isDirectory == false)
    }

    @Test func staysOnVolume() throws {
        let t = FixtureTree()
        t.file("mine/a", bytes: 50_000)
        t.file("mounted/b", bytes: 500_000)
        let mounted = t.url("mounted").path
        let root = try scan(t, .init(isExcluded: { path, _ in path == mounted }))
        #expect(root.child("mounted") == nil)
        #expect(root.child("mine") != nil)
    }

    @Test func unreadableFoldersMarked() throws {
        let t = FixtureTree()
        t.file("locked/secret", bytes: 1000)
        t.chmod("locked", 0o000)
        defer { t.chmod("locked", 0o755) }
        let root = try scan(t)
        #expect(root.child("locked")?.isUnreadable == true)
        #expect(root.hasUnreadable)
    }

    @Test func cancelStopsQuickly() async throws {
        let t = FixtureTree()
        for i in 0..<400 { t.file("d\(i % 20)/f\(i)", bytes: 10) }
        let scanner = SpaceScanner()
        let task = Task { try scanner.scan(t.root, isCancelled: { true }) }
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func parallelSplitMatchesSerial() throws {
        let t = FixtureTree()
        for i in 0..<300 { t.file("p\(i % 7)/q\(i % 13)/f\(i)", bytes: 1000 + i) }
        let serial = try scan(t, .init(workers: 1))
        let parallel = try scan(t, .init(workers: 8))
        #expect(serial.size == parallel.size && serial.items == parallel.items)
        #expect(serial.children.map(\.name) == parallel.children.map(\.name))
    }

    @Test func detachSubtractsFromAncestors() throws {
        let t = FixtureTree()
        t.file("a/b/x.bin", bytes: 100_000)
        t.file("a/y.bin", bytes: 10_000)
        let root = try scan(t)
        let a = try #require(root.child("a")), b = try #require(a.child("b"))
        let (rootSize, aSize, bSize) = (root.size, a.size, b.size)
        let (rootItems, bItems) = (root.items, b.items)
        b.detach()
        #expect(a.child("b") == nil && b.parent == nil)
        #expect(a.size == aSize - bSize && root.size == rootSize - bSize)
        #expect(root.items == rootItems - bItems - 1)
    }
}

/// Um volume montado dentro da pasta analisada (imagem de disco, SMB, AppTranslocation) não entra na conta.
@Suite(.serialized) struct SpaceScannerMountTests {
    func hdiutil(_ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        try? p.run()
        p.waitUntilExit()
        return p.terminationStatus
    }

    @Test func mountPointsAreSkipped() throws {
        let t = FixtureTree()
        t.file("outer/own.bin", bytes: 100_000)
        let image = t.url("img.dmg"), mountPoint = t.dir("outer/mp")
        try #require(hdiutil(["create", "-size", "20m", "-fs", "HFS+", "-volname", "cymtest", image.path]) == 0)
        try #require(hdiutil(["attach", "-nobrowse", "-mountpoint", mountPoint.path, image.path]) == 0)
        defer { _ = hdiutil(["detach", mountPoint.path, "-force"]) }
        try Data(count: 5_000_000).write(to: mountPoint.appendingPathComponent("inside.bin"))
        let root = try SpaceScanner().scan(t.url("outer"))
        #expect(root.child("mp") == nil)
        #expect(root.size < 1_000_000)
    }
}

/// Sem Acesso Total ao Disco, pastas que fazem o macOS pedir permissão não são abertas: ficam "sem acesso".
@Test func privacyFoldersSkippedWhenBlocked() throws {
    let t = FixtureTree()
    t.file("home/Desktop/a.bin", bytes: 300_000)
    t.file("home/Projetos/b.bin", bytes: 10_000)
    let blocked = t.url("home/Desktop").path
    let root = try SpaceScanner(options: .init(isBlocked: { $0 == blocked })).scan(t.url("home"))
    let desktop = try #require(root.child("Desktop"))
    #expect(desktop.isUnreadable && desktop.children.isEmpty && desktop.size == 0)
    #expect(root.child("Projetos")?.size ?? 0 > 0)
}

@Test func privacyFolderListCoversPromptingFolders() {
    let list = SpaceLensScan.privacyFolders(home: URL(fileURLWithPath: "/Users/me"))
    for rel in ["Desktop", "Documents", "Downloads", "Library/Mobile Documents"] { #expect(list.contains("/Users/me/" + rel)) }
}
