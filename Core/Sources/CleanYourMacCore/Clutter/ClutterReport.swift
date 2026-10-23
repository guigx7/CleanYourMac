import Foundation

public enum ClutterTarget: Hashable, Sendable {
    /// A pasta pessoal (inclui Downloads por app).
    case home
    case folder(URL)
}

/// Cartão dos Resultados (docs/re/specs/clutter/results-and-manager.md §2.2): a primeira regra de cada categoria que casa.
public struct ClutterTile: Hashable, Sendable {
    public enum Kind: String, Sendable {
        case similarRecent, similarPhotos, similarGeneric
        case duplicatesDesktop, duplicatesDocuments, duplicatesFresh, duplicatesGeneric
        case largeOld, downloads
    }

    public let kind: Kind
    /// Itens que o cartão conta.
    public let count: Int
    /// Espaço que o cartão mostra.
    public let size: Int64
    /// App, no cartão de Downloads.
    public let app: DownloadsFinder.App?
}

public enum ClutterTiles {
    public static func make(home: URL, now: Date, largeOld: [ClutterFile], duplicates: [DuplicateGroup], similar: [SimilarGroup],
                            downloads: [DownloadsFinder.Group], photosPrefix: String? = nil) -> [ClutterTile] {
        var out: [ClutterTile] = []
        // Similares: últimos 30 dias → fototeca → genérico.
        if !similar.isEmpty {
            let monthAgo = now.addingTimeInterval(-30 * 86_400)
            let recent = similar.flatMap(\.images).filter { ($0.date ?? .distantPast) > monthAgo }
            let photos = similar.flatMap(\.images).filter { $0.url == nil }
            if !recent.isEmpty {
                out.append(ClutterTile(kind: .similarRecent, count: recent.count, size: recent.reduce(0) { $0 + $1.size }, app: nil))
            } else if !photos.isEmpty {
                let removable = similar.flatMap(\.autoselected).filter { $0.url == nil }
                out.append(ClutterTile(kind: .similarPhotos, count: photos.count, size: removable.reduce(0) { $0 + $1.size }, app: nil))
            } else {
                let all = similar.flatMap(\.images)
                out.append(ClutterTile(kind: .similarGeneric, count: all.count, size: all.reduce(0) { $0 + $1.size }, app: nil))
            }
        }
        // Duplicatas: Mesa → Documentos → últimos 3 meses → genérico.
        if !duplicates.isEmpty {
            func inside(_ folder: String) -> [DuplicateGroup] {
                let prefix = PathPolicy.lexicalPath(home.appendingPathComponent(folder).path) + "/"
                return duplicates.filter { $0.files.contains { $0.url.path.hasPrefix(prefix) } }
            }
            func tile(_ kind: ClutterTile.Kind, _ groups: [DuplicateGroup]) -> ClutterTile {
                ClutterTile(kind: kind, count: groups.reduce(0) { $0 + $1.files.count },
                            size: groups.reduce(0) { $0 + $1.removableSize }, app: nil)
            }
            let threeMonths = now.addingTimeInterval(-90 * 86_400)
            let fresh = duplicates.filter { $0.files.contains { ($0.created ?? .distantPast) > threeMonths } }
            if !inside("Desktop").isEmpty { out.append(tile(.duplicatesDesktop, inside("Desktop"))) }
            else if !inside("Documents").isEmpty { out.append(tile(.duplicatesDocuments, inside("Documents"))) }
            else if !fresh.isEmpty { out.append(tile(.duplicatesFresh, fresh)) }
            else { out.append(tile(.duplicatesGeneric, duplicates)) }
        }
        let old = LargeOldFiles.tileFiles(largeOld, now: now)
        if !old.isEmpty { out.append(ClutterTile(kind: .largeOld, count: old.count, size: old.reduce(0) { $0 + $1.size }, app: nil)) }
        if let top = downloads.first(where: { $0.totalSize > 0 }) {
            out.append(ClutterTile(kind: .downloads, count: top.files.count, size: top.totalSize, app: top.app))
        }
        return out
    }
}

public struct ClutterReport: Sendable {
    public let home: URL
    public let largeOld: [ClutterFile]
    public let duplicates: [DuplicateGroup]
    public let similar: [SimilarGroup]
    public let downloads: [DownloadsFinder.Group]
    public let tiles: [ClutterTile]
    /// Algumas imagens não puderam ser lidas (ex.: fotos só no iCloud) ou a fototeca ficou de fora.
    public var isPartial = false

    public init(home: URL, largeOld: [ClutterFile], duplicates: [DuplicateGroup], similar: [SimilarGroup],
                downloads: [DownloadsFinder.Group], tiles: [ClutterTile], isPartial: Bool = false) {
        self.home = home
        self.largeOld = largeOld
        self.duplicates = duplicates
        self.similar = similar
        self.downloads = downloads
        self.tiles = tiles
        self.isPartial = isPartial
    }

    /// "Você tem N arquivos para revisar": tudo o que as quatro seções listam.
    public var total: Int {
        largeOld.count + duplicates.reduce(0) { $0 + $1.files.count } + similar.reduce(0) { $0 + $1.images.count }
            + downloads.reduce(0) { $0 + $1.files.count }
    }

    public var isEmpty: Bool { total == 0 }

    /// Mesmas chaves de docs/re/parity/clutter-baseline-*.json.
    public func parityJSON() -> [String: Any] {
        let day: (Date?) -> Any = { d in
            guard let d else { return NSNull() }
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US_POSIX")
            f.dateFormat = "yyyy-MM-dd"
            return f.string(from: d)
        }
        let homePath = PathPolicy.lexicalPath(home.path)
        return [
            "total": total,
            "tiles": tiles.map { ["kind": $0.kind.rawValue, "count": $0.count, "size": $0.size, "app": $0.app?.title ?? NSNull()] as [String: Any] },
            "largeOld": largeOld.map { f -> [String: Any] in
                let folder = f.url.deletingLastPathComponent().path
                let rel = folder.hasPrefix(homePath) ? home.lastPathComponent + folder.dropFirst(homePath.count) : folder
                return ["name": f.url.lastPathComponent, "folder": rel, "lastOpened": day(f.accessed), "size": f.size]
            },
            "duplicates": duplicates.map { ["name": $0.name, "size": $0.totalSize, "count": $0.files.count] as [String: Any] },
            "similar": similar.map { ["date": day($0.date), "size": $0.totalSize, "count": $0.images.count] as [String: Any] },
            "downloads": ["groups": Dictionary(uniqueKeysWithValues: downloads.map { ($0.app.title, $0.totalSize) }),
                          "files": downloads.flatMap(\.files).map { ["name": $0.url.lastPathComponent, "size": $0.size] as [String: Any] }],
        ]
    }
}

public enum ClutterScanEvent: Sendable {
    case progress(String)
    case finished(ClutterReport)
}

/// Orquestra a análise: uma varredura da pasta, depois as quatro partes.
public final class ClutterScan: Sendable {
    private let home: URL
    /// Fotos da fototeca (o app fornece pelo PhotoKit); `nil` = sem fototeca.
    private let photoCandidates: (@Sendable () -> [SimilarCandidate])?
    private let now: @Sendable () -> Date
    private let similarThreshold: Int

    public init(home: URL = FileManager.default.homeDirectoryForCurrentUser,
                photoCandidates: (@Sendable () -> [SimilarCandidate])? = nil, now: @escaping @Sendable () -> Date = { Date() },
                similarThreshold: Int = SimilarImageFinder.defaultThreshold) {
        self.similarThreshold = similarThreshold
        self.home = home
        self.photoCandidates = photoCandidates
        self.now = now
    }

    public func run(_ target: ClutterTarget) -> AsyncThrowingStream<ClutterScanEvent, Error> {
        AsyncThrowingStream { continuation in
            let flag = Flag()
            let thread = Thread { [home, photoCandidates, now, similarThreshold] in
                do {
                    let root: URL
                    switch target {
                    case .home: root = home
                    case .folder(let u): root = u
                    }
                    let cancelled: @Sendable () -> Bool = { flag.isSet }
                    continuation.yield(.progress("files"))
                    let files = try ClutterWalker(home: home).files(in: root, isCancelled: cancelled)
                    continuation.yield(.progress("largeOld"))
                    let largeOld = LargeOldFiles.items(from: files)
                    continuation.yield(.progress("duplicates"))
                    let duplicates = try DuplicateFinder(home: home).groups(from: files, isCancelled: cancelled)
                    continuation.yield(.progress("similar"))
                    var candidates = files.filter(SimilarImageFinder.accepts).map(SimilarCandidate.file)
                    if target == .home, let photoCandidates { candidates += photoCandidates() }
                    let similar = try SimilarImageFinder(threshold: similarThreshold).groups(from: candidates, isCancelled: cancelled)
                    continuation.yield(.progress("downloads"))
                    let downloads = target == .home ? DownloadsFinder(home: home).groups(now: now()) : []
                    let tiles = ClutterTiles.make(home: home, now: now(), largeOld: largeOld, duplicates: duplicates, similar: similar,
                                                  downloads: downloads)
                    continuation.yield(.finished(ClutterReport(home: home, largeOld: largeOld, duplicates: duplicates, similar: similar,
                                                               downloads: downloads, tiles: tiles)))
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
}
