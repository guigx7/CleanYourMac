import CoreServices
import Foundation

public enum SpaceLensTarget: Hashable, Sendable {
    /// O volume de inicialização inteiro (a partir de "/").
    case disk
    case folder(URL)
}

/// Uso do volume e espaço purgável (leitura).
public protocol SpaceVolumeInfo: Sendable {
    func usage(of url: URL) -> (name: String, used: Int64, capacity: Int64)
    func purgeableBytes() -> Int64
}

public struct SystemVolumeInfo: SpaceVolumeInfo {
    public init() {}

    /// "Usados" = capacidade − espaço disponível para uso importante (o que o macOS mostra nos Ajustes).
    public func usage(of url: URL) -> (name: String, used: Int64, capacity: Int64) {
        let keys: Set<URLResourceKey> = [.volumeLocalizedNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey]
        guard let v = try? url.resourceValues(forKeys: keys), let total = v.volumeTotalCapacity else { return ("", 0, 0) }
        let free = v.volumeAvailableCapacityForImportantUsage ?? 0
        return (v.volumeLocalizedName ?? "", Int64(total) - free, Int64(total))
    }

    public func purgeableBytes() -> Int64 {
        Int64(clamping: CSDiskSpaceGetRecoveryEstimate(URL(fileURLWithPath: "/") as CFURL))
    }
}

public struct SpaceLensReport: @unchecked Sendable {
    public let root: SpaceNode
    public let isDisk: Bool
    public let volumeName: String
    public let used: Int64
    public let capacity: Int64
    /// Só na análise do disco.
    public let purgeable: Int64?
}

public enum SpaceLensScanEvent: Sendable {
    /// Itens lidos até agora.
    case progress(Int)
    case finished(SpaceLensReport)
}

public final class SpaceLensScan: Sendable {
    private let volume: any SpaceVolumeInfo
    private let diskRoot: URL
    private let diskExclusion: @Sendable (String, dev_t) -> Bool
    private let workers: Int

    public init(volume: any SpaceVolumeInfo = SystemVolumeInfo(), diskRoot: URL = URL(fileURLWithPath: "/"),
                diskExclusion: @escaping @Sendable (String, dev_t) -> Bool = SpaceLensScan.defaultDiskExclusion(),
                workers: Int = max(2, ProcessInfo.processInfo.activeProcessorCount)) {
        self.volume = volume
        self.diskRoot = diskRoot
        self.diskExclusion = diskExclusion
        self.workers = workers
    }

    /// Fora da análise do disco: outros volumes e `/System/Volumes` inteiro (o volume de dados já aparece pelos
    /// firmlinks; VM, Preboot e afins não são arquivos de ninguém).
    public static func defaultDiskExclusion() -> @Sendable (String, dev_t) -> Bool {
        var root = stat(), data = stat()
        let rootDev = lstat("/", &root) == 0 ? root.st_dev : 0
        let dataDev = lstat("/System/Volumes/Data", &data) == 0 ? data.st_dev : rootDev
        return { path, dev in
            if dev != rootDev && dev != dataDev { return true }
            return path == "/System/Volumes" || path == "/Volumes" || path == "/dev"
        }
    }

    public func run(_ target: SpaceLensTarget) -> AsyncThrowingStream<SpaceLensScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let flag = CancelFlag()
            let thread = Thread { [volume, diskRoot, diskExclusion, workers] in
                do {
                    let url: URL, exclusion: @Sendable (String, dev_t) -> Bool
                    switch target {
                    case .disk: (url, exclusion) = (diskRoot, diskExclusion)
                    case .folder(let u): (url, exclusion) = (u, { _, _ in false })
                    }
                    let scanner = SpaceScanner(options: .init(workers: workers, isExcluded: exclusion))
                    let root = try scanner.scan(url, isCancelled: { flag.isSet }) { continuation.yield(.progress($0)) }
                    let usage = volume.usage(of: url)
                    let isDisk = target == .disk
                    continuation.yield(.finished(SpaceLensReport(root: root, isDisk: isDisk, volumeName: usage.name, used: usage.used,
                                                                 capacity: usage.capacity, purgeable: isDisk ? volume.purgeableBytes() : nil)))
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            thread.stackSize = 8 << 20
            continuation.onTermination = { _ in flag.set() }
            thread.start()
        }
    }

    private final class CancelFlag: @unchecked Sendable {
        private let lock = NSLock()
        private var value = false
        func set() { lock.withLock { value = true } }
        var isSet: Bool { lock.withLock { value } }
    }
}
