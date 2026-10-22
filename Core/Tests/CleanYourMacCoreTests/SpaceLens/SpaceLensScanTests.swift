import Foundation
import Testing
@testable import CleanYourMacCore

struct FakeVolume: SpaceVolumeInfo {
    var used: Int64 = 225_000_000_000
    var capacity: Int64 = 494_000_000_000
    var name = "Macintosh HD"
    var purgeable: Int64 = 3_900_000_000
    func usage(of url: URL) -> (name: String, used: Int64, capacity: Int64) { (name, used, capacity) }
    func purgeableBytes() -> Int64 { purgeable }
}

@Suite struct SpaceLensScanTests {
    func run(_ scan: SpaceLensScan, _ target: SpaceLensTarget) async throws -> (SpaceLensReport?, [Int]) {
        var report: SpaceLensReport?, progress: [Int] = []
        for try await e in scan.run(target) {
            switch e {
            case .progress(let n): progress.append(n)
            case .finished(let r): report = r
            }
        }
        return (report, progress)
    }

    @Test func folderTargetHasNoPurgeable() async throws {
        let t = FixtureTree()
        t.file("a/x", bytes: 10_000)
        let (r, _) = try await run(SpaceLensScan(volume: FakeVolume()), .folder(t.root))
        let report = try #require(r)
        #expect(!report.isDisk && report.purgeable == nil)
        #expect(report.root.child("a") != nil)
        #expect(report.volumeName == "Macintosh HD" && report.used == 225_000_000_000)
    }

    @Test func diskTargetAddsPurgeableAndUsesExclusion() async throws {
        let t = FixtureTree()
        t.file("Users/me/a", bytes: 10_000)
        t.file("System/Volumes/Data/Users/me/a", bytes: 10_000)
        let excluded = t.url("System/Volumes").path
        let scan = SpaceLensScan(volume: FakeVolume(), diskRoot: t.root, diskExclusion: { path, _ in path == excluded })
        let report = try #require(try await run(scan, .disk).0)
        #expect(report.isDisk && report.purgeable == 3_900_000_000)
        #expect(report.root.child("System")?.child("Volumes") == nil)
    }

    @Test func cancelEndsTheStream() async {
        let t = FixtureTree()
        for i in 0..<200 { t.file("d\(i % 10)/f\(i)", bytes: 10) }
        let scan = SpaceLensScan(volume: FakeVolume())
        let task = Task { try await run(scan, .folder(t.root)) }
        task.cancel()
        let result = try? await task.value
        #expect(result?.0 == nil)
    }

    /// /System/Volumes inteiro fica fora (o volume de dados já aparece pelos firmlinks; VM, Preboot e afins não são
    /// arquivos do usuário): /System soma 19,93 GB nesta máquina, os 19,9 GB do CleanMyMac.
    @Test func defaultDiskExclusionSkipsSystemVolumes() {
        var st = stat()
        lstat("/", &st)
        let exclude = SpaceLensScan.defaultDiskExclusion()
        #expect(exclude("/System/Volumes", st.st_dev))
        #expect(exclude("/Volumes", st.st_dev))
        #expect(!exclude("/System/Library", st.st_dev))
        // Outro dispositivo (um disco externo montado dentro da árvore) também fica fora.
        #expect(exclude("/Users/me/montado", st.st_dev &+ 12345))
    }
}
