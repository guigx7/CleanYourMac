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

// Tabela de docs/re/specs/common.md §2.
@Test(arguments: [
    (Int64(0), "0 KB", "0 KB"),
    (Int64(30), "0 KB", "0 KB"),
    (Int64(4096), "4,1 KB", "4.1 KB"),
    (Int64(12_288), "12,3 KB", "12.3 KB"),
    (Int64(139_264), "139 KB", "139 KB"),
    (Int64(213_000), "213 KB", "213 KB"),
    (Int64(16_100_000), "16,1 MB", "16.1 MB"),
    (Int64(23_000_000), "23 MB", "23 MB"),
    (Int64(597_700_000), "598 MB", "598 MB"),
    (Int64(824_000_000), "824 MB", "824 MB"),
    (Int64(1_600_000_000), "1,6 GB", "1.6 GB"),
    (Int64(2_670_000_000), "2,7 GB", "2.7 GB"),
    (Int64(4_500_000_000), "4,5 GB", "4.5 GB"),
    (Int64(999_960), "1 MB", "1 MB"),
    (Int64(2_000_000_000_000), "2 TB", "2 TB"),
])
func sizeFormatting(bytes: Int64, pt: String, en: String) {
    #expect(SizeFormatter.string(bytes, locale: Locale(identifier: "pt-BR")) == pt)
    #expect(SizeFormatter.string(bytes, locale: Locale(identifier: "en")) == en)
}
