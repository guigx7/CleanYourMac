import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct DuplicateFinderTests {
    func write(_ t: FixtureTree, _ rel: String, _ byte: UInt8, _ count: Int = 200_000, modified: Date? = nil) -> URL {
        let u = t.url("Users/me/" + rel)
        try? FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(repeating: byte, count: count).write(to: u)
        if let modified { try! FileManager.default.setAttributes([.modificationDate: modified], ofItemAtPath: u.path) }
        return u
    }

    func groups(_ t: FixtureTree) throws -> [DuplicateGroup] {
        let home = t.url("Users/me")
        return try DuplicateFinder(home: home).groups(from: ClutterWalker(home: home).files(in: home))
    }

    @Test func sameContentGroupedDifferentContentNot() throws {
        let t = FixtureTree()
        _ = write(t, "Documents/a.png", 1)
        _ = write(t, "Pictures/a copy.png", 1)
        _ = write(t, "Desktop/b.png", 2)          // mesmo tamanho, outro conteúdo
        _ = write(t, "Desktop/small.png", 1, 102_399) // abaixo de 100 KiB
        _ = write(t, "Desktop/small2.png", 1, 102_399)
        let g = try groups(t)
        #expect(g.count == 1)
        #expect(g[0].files.count == 2 && g[0].totalSize == 400_000)
    }

    @Test func keeperFollowsTieBreakChain() throws {
        let t = FixtureTree()
        let old = Date(timeIntervalSince1970: 1_600_000_000), new = Date(timeIntervalSince1970: 1_700_000_000)
        // 1) a de Downloads sai
        _ = write(t, "Downloads/x.zip", 3)
        let keep1 = write(t, "Documents/x.zip", 3)
        // 2) número de cópia maior sai
        let keep2 = write(t, "Documents/y.mov", 4)
        _ = write(t, "Documents/y copy 2.mov", 4)
        // 4) modificação mais antiga sai
        _ = write(t, "Pictures/z.png", 5, modified: old)
        let keep4 = write(t, "Movies/z.png", 5, modified: new)
        // 5) caminho mais fundo sai
        _ = write(t, "Documents/deep/er/w.pdf", 6, modified: old)
        let keep5 = write(t, "Documents/w.pdf", 6, modified: old)
        let g = try groups(t)
        let keepers = Set(g.map { $0.keeper.url.path })
        #expect(keepers == [keep1.path, keep2.path, keep4.path, keep5.path])
        for group in g { #expect(group.autoselected.count == group.files.count - 1) }
    }

    @Test func packagesComparedByContent() throws {
        let t = FixtureTree()
        t.app("Users/me/Applications/A.app", bundleID: "com.example.same")
        _ = write(t, "Applications/A.app/Contents/MacOS/app", 7)
        // Cópia idêntica com outro nome (o Info.plist é o mesmo).
        t.dir("Users/me/Documents")
        try FileManager.default.copyItem(at: t.url("Users/me/Applications/A.app"), to: t.url("Users/me/Documents/B.app"))
        let g = try groups(t)
        try #require(g.count == 1)
        #expect(g[0].files.allSatisfy { $0.isPackage })
        #expect(DuplicateFinder.kind(g[0].files[0]) == .applications)
    }

    @Test func kindsBySpec() {
        func f(_ type: String) -> ClutterFile { ClutterFile(url: URL(fileURLWithPath: "/x"), size: 1, contentType: type) }
        #expect(DuplicateFinder.kind(f("public.zip-archive")) == .archives)
        #expect(DuplicateFinder.kind(f("public.mp3")) == .audio)
        #expect(DuplicateFinder.kind(f("public.png")) == .pictures)
        #expect(DuplicateFinder.kind(f("public.mpeg-4")) == .videos)
        #expect(DuplicateFinder.kind(f("public.plain-text")) == .documents)
        #expect(DuplicateFinder.kind(f("com.adobe.pdf")) == .other)
    }

    @Test func groupsSortedByTotalSize() throws {
        let t = FixtureTree()
        _ = write(t, "Documents/s1.bin", 8, 150_000); _ = write(t, "Pictures/s2.bin", 8, 150_000)
        _ = write(t, "Documents/b1.bin", 9, 900_000); _ = write(t, "Pictures/b2.bin", 9, 900_000)
        #expect(try groups(t).map(\.totalSize) == [1_800_000, 300_000])
    }

    @Test func filesInsideXcassetsIgnored() throws {
        let t = FixtureTree()
        _ = write(t, "Projects/web/icon.png", 10)
        _ = write(t, "Projects/App/Assets.xcassets/AppIcon.appiconset/icon_1024.png", 10)
        _ = write(t, "Projects/a.png", 11); _ = write(t, "Projects/b.png", 11)
        let g = try groups(t)
        try #require(g.count == 1)
        #expect(g[0].files.allSatisfy { !$0.url.path.contains(".xcassets/") })
    }

    @Test func titleIsTheKeeperAndParenthesisIsNotACopyNumber() throws {
        let t = FixtureTree()
        let old = Date(timeIntervalSince1970: 1_600_000_000), new = Date(timeIntervalSince1970: 1_700_000_000)
        _ = write(t, "Downloads/FISIOLOGIA.png", 12, modified: old)
        _ = write(t, "Downloads/FISIOLOGIA (2).png", 12, modified: new)
        // Mesma data, mesma profundidade, mesmo tamanho de nome: o caminho menor na ordem alfabética sai.
        _ = write(t, "Documents/111.png", 13, modified: old)
        _ = write(t, "Documents/222.png", 13, modified: old)
        let g = try groups(t)
        try #require(g.count == 2)
        #expect(Set(g.map(\.name)) == ["FISIOLOGIA (2).png", "222.png"])
        #expect(DuplicateFinder.copyNumber(URL(fileURLWithPath: "/a/x (2).png")) == 0)
        #expect(DuplicateFinder.copyNumber(URL(fileURLWithPath: "/a/x copy 3.png")) == 3)
    }
}
