import Testing
import Foundation
@testable import CleanYourMacCore

@Test func sumsTree() {
    let t = FixtureTree()
    let a = t.file("d/a", bytes: 4096)
    let b = t.file("d/sub/b", bytes: 10_000)
    let c = t.file("d/c", bytes: 1)
    let expected = [a, b, c].map(FixtureTree.allocated).reduce(0, +)
    #expect(FileSizer().allocatedSize(of: t.url("d")) == expected)
}

@Test func sizeOfSingleFile() {
    let t = FixtureTree()
    let a = t.file("a", bytes: 5000)
    #expect(FileSizer().allocatedSize(of: a) == FixtureTree.allocated(a))
}

@Test func doesNotFollowSymlinks() {
    let t = FixtureTree()
    let outside = FixtureTree()
    outside.file("big/x", bytes: 1_000_000)
    let a = t.file("d/a", bytes: 4096)
    t.symlink("d/link", to: outside.url("big"))
    #expect(FileSizer().allocatedSize(of: t.url("d")) == FixtureTree.allocated(a))
}

@Test func hardLinkCountedOnce() {
    let t = FixtureTree()
    let a = t.file("d/a", bytes: 100_000)
    t.hardlink("d/b", to: a)
    #expect(FileSizer().allocatedSize(of: t.url("d")) == FixtureTree.allocated(a))
}

@Test func unreadableSubtreeSkipped() {
    let t = FixtureTree()
    let a = t.file("d/a", bytes: 4096)
    t.file("d/locked/x", bytes: 50_000)
    t.chmod("d/locked", 0o000)
    #expect(FileSizer().allocatedSize(of: t.url("d")) == FixtureTree.allocated(a))
}

@Test func missingPathIsZero() {
    #expect(FileSizer().allocatedSize(of: URL(fileURLWithPath: "/nonexistent-\(UUID())")) == 0)
}

@Test(arguments: [
    (Int64(4_500_000_000), "pt-BR", "4,5 GB"),
    (Int64(4_500_000_000), "en", "4.5 GB"),
    (Int64(824_000_000), "pt-BR", "824 MB"),
    (Int64(67_600_000), "pt-BR", "67,6 MB"),
    (Int64(213_000), "pt-BR", "213 KB"),
    (Int64(0), "pt-BR", "0 KB"),
])
func sizeFormatting(bytes: Int64, locale: String, expected: String) {
    #expect(SizeFormatter.string(bytes, locale: Locale(identifier: locale)) == expected)
}
