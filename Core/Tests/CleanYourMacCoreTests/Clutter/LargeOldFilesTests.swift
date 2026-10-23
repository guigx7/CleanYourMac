import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct LargeOldFilesTests {
    let now = Date(timeIntervalSince1970: 1_792_000_000)
    func file(_ name: String, _ size: Int64, type: String = "public.data", accessedDaysAgo: Double? = 0) -> ClutterFile {
        ClutterFile(url: URL(fileURLWithPath: "/Users/me/Downloads/" + name), size: size,
                    accessed: accessedDaysAgo.map { now.addingTimeInterval(-$0 * 86_400) }, contentType: type)
    }

    @Test func minimumIs50MiBAndSortedBySize() {
        let files = [file("a", 52_428_799), file("b", 52_428_800), file("c", 1_000_000_000)]
        #expect(LargeOldFiles.items(from: files).map(\.url.lastPathComponent) == ["c", "b"])
    }

    @Test func kindsBySpec() {
        #expect(LargeOldFiles.kind(file("x.zip", 1, type: "public.zip-archive")) == .archives)
        #expect(LargeOldFiles.kind(file("x.mov", 1, type: "com.apple.quicktime-movie")) == .videos)
        #expect(LargeOldFiles.kind(file("x.jpg", 1, type: "public.jpeg")) == .pictures)
        #expect(LargeOldFiles.kind(file("x.txt", 1, type: "public.plain-text")) == .documents)
        // PDF não conforma com public.text: "Outro", como no CleanMyMac (Livro…pdf em "Outro 60,8 MB").
        #expect(LargeOldFiles.kind(file("x.pdf", 1, type: "com.adobe.pdf")) == .other)
    }

    @Test func sizeBucketsDecimal() {
        #expect(LargeOldFiles.sizeBucket(52_428_800) == .small)
        #expect(LargeOldFiles.sizeBucket(499_999_999) == .small)
        #expect(LargeOldFiles.sizeBucket(500_000_000) == .average)
        #expect(LargeOldFiles.sizeBucket(999_999_999) == .average)
        #expect(LargeOldFiles.sizeBucket(1_000_000_000) == .huge)
    }

    @Test func accessAgeBucketsExclusive() {
        let cal = Calendar(identifier: .gregorian)
        func age(_ days: Double?) -> LargeOldFiles.AccessAge {
            LargeOldFiles.age(of: days.map { now.addingTimeInterval(-$0 * 86_400) }, now: now, calendar: cal)
        }
        #expect(age(1) == .lastWeek)
        #expect(age(10) == .oneWeekAgo)
        #expect(age(60) == .oneMonthAgo)
        #expect(age(200) == .sixMonthsAgo)
        #expect(age(400) == .oneYearAgo)
        #expect(age(nil) == .oneYearAgo)
    }

    @Test func tileCountsOnlyOlderThanAYear() {
        let files = [file("old.zip", 60_000_000, accessedDaysAgo: 366), file("new.zip", 60_000_000, accessedDaysAgo: 364)]
        #expect(LargeOldFiles.tileFiles(LargeOldFiles.items(from: files), now: now).map(\.url.lastPathComponent) == ["old.zip"])
    }
}
