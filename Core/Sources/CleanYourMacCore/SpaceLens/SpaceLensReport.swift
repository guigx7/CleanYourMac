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

    public init(root: SpaceNode, isDisk: Bool, volumeName: String, used: Int64, capacity: Int64, purgeable: Int64?) {
        self.root = root
        self.isDisk = isDisk
        self.volumeName = volumeName
        self.used = used
        self.capacity = capacity
        self.purgeable = purgeable
    }
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
    private let blocked: @Sendable () -> Set<String>

    /// Pastas em que o macOS pede permissão (Arquivos e Pastas) a um app sem Acesso Total ao Disco.
    public static func privacyFolders(home: URL = FileManager.default.homeDirectoryForCurrentUser) -> Set<String> {
        let h = PathPolicy.lexicalPath(home.path)
        return Set(["Desktop", "Documents", "Downloads", "Library/Mobile Documents"].map { h + "/" + $0 })
    }

    /// `blocked`: pastas que não são abertas, avaliado a cada análise (o app devolve `privacyFolders()` quando não tem
    /// Acesso Total ao Disco).
    public init(volume: any SpaceVolumeInfo = SystemVolumeInfo(), diskRoot: URL = URL(fileURLWithPath: "/"),
                diskExclusion: @escaping @Sendable (String, dev_t) -> Bool = SpaceLensScan.defaultDiskExclusion(),
                workers: Int = max(2, ProcessInfo.processInfo.activeProcessorCount),
                blocked: @escaping @Sendable () -> Set<String> = { [] }) {
        self.blocked = blocked
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
            let thread = Thread { [volume, diskRoot, diskExclusion, workers, blocked] in
                do {
                    let url: URL, exclusion: @Sendable (String, dev_t) -> Bool
                    switch target {
                    case .disk: (url, exclusion) = (diskRoot, diskExclusion)
                    case .folder(let u): (url, exclusion) = (u, { _, _ in false })
                    }
                    let skip = blocked()
                    let scanner = SpaceScanner(options: .init(workers: workers, isExcluded: exclusion, isBlocked: { skip.contains($0) }))
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

extension SpaceLensReport {
    /// Mesmo formato de docs/re/parity/spacelens-baseline-*.json. `folders`: chave → caminho relativo à raiz analisada.
    public func parityJSON(folders: [String: String]) -> [String: Any] {
        var out: [String: Any] = [:]
        for (key, rel) in folders {
            var node: SpaceNode? = root
            for part in rel.split(separator: "/") { node = node?.child(String(part)) }
            guard let node else { continue }
            let split = SpaceGrouping.split(node.children.map(\.size), total: node.size)
            let isRoot = node === root
            out[key] = [
                "size": node.size + (isRoot && isDisk ? (purgeable ?? 0) : 0),
                "items": node.items,
                "children": node.children.prefix(split.visible).map { [$0.name, $0.size] as [Any] },
                "others": split.visible < node.children.count ? split.others as Any : NSNull(),
                "purgeable": isRoot && isDisk ? (purgeable ?? 0) as Any : NSNull(),
            ] as [String: Any]
        }
        return ["volume": ["used": used, "capacity": capacity], "folders": out]
    }
}
