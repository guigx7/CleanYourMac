import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct ClutterWalkerTests {
    func names(_ t: FixtureTree) throws -> Set<String> {
        let home = t.url("Users/me")
        let files = try ClutterWalker(home: home).files(in: home)
        return Set(files.map { $0.url.path.replacingOccurrences(of: home.path + "/", with: "") })
    }

    @Test func commonExclusionsFromSpec() throws {
        let t = FixtureTree()
        for rel in ["Documents/report.pdf", "Pictures/photo.jpg", "Movies/clip.mov"] { t.file("Users/me/" + rel, bytes: 10) }
        // Nomes (13 padrões), extensões de código/build, ~/Library, ~/Music/Music, ocultos, fototeca.
        for rel in ["Projetos/app/node_modules/x.bin", "Projetos/app/.git/objects/y", "Projetos/app/main.swift", "Projetos/app/data.json",
                    "Projetos/app/LICENSE.txt", "Library/Caches/z.bin", "Music/Music/Media/song.m4a", ".hidden/file.bin",
                    "Documents/.secret.bin", "Pictures/Photos Library.photoslibrary/originals/a.jpg", "Projetos/app/bower_components/x.js.bin",
                    "Documents/Credits.rtf"] {
            t.file("Users/me/" + rel, bytes: 10)
        }
        #expect(try names(t) == ["Documents/report.pdf", "Pictures/photo.jpg", "Movies/clip.mov"])
    }

    @Test func packagesAreOneItem() throws {
        let t = FixtureTree()
        t.app("Users/me/Applications/Tool.app", bundleID: "com.example.tool")
        t.file("Users/me/Applications/Tool.app/Contents/MacOS/app", bytes: 200_000)
        let home = t.url("Users/me")
        let files = try ClutterWalker(home: home).files(in: home)
        let tool = try #require(files.first { $0.url.lastPathComponent == "Tool.app" })
        #expect(tool.isPackage && tool.size >= 200_000)
        #expect(!files.contains { $0.url.path.contains("Tool.app/") })
    }

    @Test func attributesRead() throws {
        let t = FixtureTree()
        let f = t.file("Users/me/Downloads/big.mov", bytes: 300_000)
        let file = try #require(try ClutterWalker(home: t.url("Users/me")).files(in: t.url("Users/me")).first)
        #expect(file.url.path == f.path)
        #expect(file.size == 300_000)
        #expect(file.contentType == "com.apple.quicktime-movie")
        #expect(file.accessed != nil && file.modified != nil)
    }

    @Test func cancelStops() {
        let t = FixtureTree()
        for i in 0..<50 { t.file("Users/me/d/f\(i).bin", bytes: 10) }
        #expect(throws: CancellationError.self) {
            try ClutterWalker(home: t.url("Users/me")).files(in: t.url("Users/me"), isCancelled: { true })
        }
    }
}
