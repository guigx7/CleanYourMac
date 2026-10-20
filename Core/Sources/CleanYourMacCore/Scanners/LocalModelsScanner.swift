import Foundation

/// Modelos locais do Ollama e do LM Studio (docs/re/specs/local-models.md).
/// Uma linha por modelo, com o tamanho que a remoção de fato libera. Nada vem recomendado.
public struct LocalModelsScanner: ScopedScanner {
    public let group = GroupID.localModels
    private let apps: any AppLookup

    public init(apps: any AppLookup = WorkspaceAppLookup()) {
        self.apps = apps
    }

    public func removalScope(_ context: ScanContext) -> RemovalScope {
        let ollama = OllamaStore(root: context.resolve("~/.ollama/models"))
        return RemovalScope(roots: [ollama.manifests, ollama.blobs, context.resolve("~/.lmstudio/models")])
    }

    public func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
        let ollamaIcon = apps.application(bundleID: "com.electron.ollama").map { IconSource.app($0.url) } ?? .symbol("cpu")
        let lmIcon = apps.application(bundleID: "ai.elementlabs.lmstudio").map { IconSource.app($0.url) } ?? .symbol("cpu")
        let store = OllamaStore(root: context.resolve("~/.ollama/models"))
        report(ScanProgress(group: group, currentPath: store.root.path, bytesFound: 0))
        var items = store.rows().map { row in
            JunkItem(id: "localModels:ollama:\(row.manifest.path)", group: group, name: row.name,
                     detail: Self.detail("Ollama", "GGUF", row.date), url: row.manifest, size: row.exclusiveBytes,
                     icon: ollamaIcon, removal: .removeOllamaModel(manifest: row.manifest, store: store.root))
        }
        let lmRoot = context.resolve("~/.lmstudio/models")
        report(ScanProgress(group: group, currentPath: lmRoot.path, bytesFound: items.reduce(0) { $0 + $1.size }))
        items += LMStudioStore(root: lmRoot).rows().map { row in
            JunkItem(id: "localModels:lmstudio:\(row.id)", group: group, name: row.name,
                     detail: Self.detail("LM Studio", row.format, row.date), url: row.anchor, size: row.exclusiveBytes,
                     icon: lmIcon, removal: row.removal)
        }
        return items
    }

    static func detail(_ store: String, _ format: String, _ date: Date?) -> String {
        let when = date.map { $0.formatted(date: .abbreviated, time: .omitted) }
        return ([store, format] + (when.map { [$0] } ?? [])).joined(separator: " · ")
    }

    static func logicalSize(_ u: URL) -> Int64 {
        FileSizer(mode: .logical).allocatedSize(of: u)
    }

    static func creationDate(_ u: URL) -> Date? {
        try? u.resourceValues(forKeys: [.creationDateKey]).creationDate
    }
}

// MARK: - Ollama

struct OllamaStore {
    let root: URL
    var manifests: URL { root.appendingPathComponent("manifests") }
    var blobs: URL { root.appendingPathComponent("blobs") }

    static let maxManifestBytes = 1 << 20

    struct Manifest {
        let url: URL
        let relative: [String]
        let blobs: [String]
        let weights: String?
    }

    struct Row {
        let manifest: URL
        let name: String
        let exclusiveBytes: Int64
        let date: Date?
    }

    func blobURL(_ digest: String) -> URL {
        blobs.appendingPathComponent(digest.replacingOccurrences(of: ":", with: "-"))
    }

    /// Todos os manifestos (até 7 níveis). `nil` se algum for ilegível.
    func readManifests() -> [Manifest]? {
        let base = URL(fileURLWithPath: PathPolicy.realPath(manifests.path), isDirectory: true)
        guard FileManager.default.fileExists(atPath: base.path) else { return [] }
        let baseDepth = base.pathComponents.count
        let e = FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
                                               options: [], errorHandler: { _, _ in true })
        var out: [Manifest] = []
        while let u = e?.nextObject() as? URL {
            let depth = u.pathComponents.count - baseDepth
            if depth >= 7 { e?.skipDescendants() }
            guard let v = try? u.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]), v.isRegularFile == true else { continue }
            if (v.fileSize ?? 0) > Self.maxManifestBytes { continue }
            guard let data = try? Data(contentsOf: u),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
            let layers = (json["layers"] as? [[String: Any]]) ?? []
            var digests = layers.compactMap { $0["digest"] as? String }
            if let config = (json["config"] as? [String: Any])?["digest"] as? String { digests.insert(config, at: 0) }
            let weights = layers.first { ($0["mediaType"] as? String)?.hasSuffix(".model") == true }?["digest"] as? String
            out.append(Manifest(url: u, relative: Array(u.pathComponents.dropFirst(baseDepth)), blobs: digests, weights: weights))
        }
        return out
    }

    static func displayName(_ relative: [String]) -> String {
        guard relative.count >= 2 else { return relative.joined(separator: "/") }
        let tag = relative[relative.count - 1]
        var path = Array(relative.dropLast())
        if path.count == 3, path[0] == "registry.ollama.ai", path[1] == "library" { path = [path[2]] }
        else if path.first == "registry.ollama.ai" { path.removeFirst() }
        return path.joined(separator: "/") + ":" + tag
    }

    func rows() -> [Row] {
        guard let all = readManifests() else { return [] }
        var refs: [String: Int] = [:]
        for m in all { for d in Set(m.blobs) { refs[d, default: 0] += 1 } }
        return all.compactMap { m in
            guard let w = m.weights, FileManager.default.fileExists(atPath: blobURL(w).path) else { return nil }
            let exclusive = Set(m.blobs).filter { refs[$0] == 1 }
            let bytes = exclusive.reduce(LocalModelsScanner.logicalSize(m.url)) { $0 + LocalModelsScanner.logicalSize(blobURL($1)) }
            return Row(manifest: m.url, name: Self.displayName(m.relative), exclusiveBytes: bytes,
                       date: LocalModelsScanner.creationDate(blobURL(w)))
        }
    }

    /// Apaga o manifesto e os blobs dele que nenhum manifesto restante referencia (recalculado agora).
    func remove(manifest: URL) throws {
        let real = URL(fileURLWithPath: PathPolicy.realPath(manifest.path))
        guard let before = readManifests(), let target = before.first(where: { $0.url.path == real.path }) else {
            // Sem conseguir ler os manifestos, apaga só o manifesto pedido.
            try FileManager.default.removeItem(at: manifest)
            return
        }
        try FileManager.default.removeItem(at: manifest)
        guard let remaining = readManifests() else { return }
        let stillUsed = Set(remaining.flatMap(\.blobs))
        for digest in Set(target.blobs) where !stillUsed.contains(digest) {
            try? FileManager.default.removeItem(at: blobURL(digest))
        }
    }
}

// MARK: - LM Studio

struct LMStudioStore {
    let root: URL

    struct Row {
        let id: String
        let name: String
        let format: String
        let exclusiveBytes: Int64
        let anchor: URL
        let removal: RemovalAction
        let date: Date?
    }

    private func children(_ u: URL) -> [URL] {
        let real = URL(fileURLWithPath: PathPolicy.realPath(u.path), isDirectory: true)
        return ((try? FileManager.default.contentsOfDirectory(at: real, includingPropertiesForKeys: nil)) ?? [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func isDir(_ u: URL) -> Bool {
        (try? u.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])).map { $0.isDirectory == true && $0.isSymbolicLink != true } ?? false
    }

    private static let shard = try! NSRegularExpression(pattern: #"^(.*)-(\d+)-of-(\d+)$"#)

    static func shardBase(_ stem: String) -> String? {
        let range = NSRange(stem.startIndex..., in: stem)
        guard let m = shard.firstMatch(in: stem, range: range), let r = Range(m.range(at: 1), in: stem) else { return nil }
        return String(stem[r])
    }

    func rows() -> [Row] {
        var out: [Row] = []
        for publisher in children(root) where isDir(publisher) && !publisher.lastPathComponent.hasPrefix(".") {
            for folder in children(publisher) where isDir(folder) && !folder.lastPathComponent.hasPrefix(".") {
                out += rows(in: folder, id: "\(publisher.lastPathComponent)/\(folder.lastPathComponent)")
            }
        }
        return out
    }

    private func rows(in folder: URL, id: String) -> [Row] {
        let files = children(folder).filter { !isDir($0) }
        let size = { (u: URL) in LocalModelsScanner.logicalSize(u) }
        // GGUF: shards agrupados pela base do nome.
        var groups: [(key: String, files: [URL])] = []
        for f in files where f.pathExtension.lowercased() == "gguf" {
            let stem = f.deletingPathExtension().lastPathComponent
            let key = Self.shardBase(stem) ?? stem
            if let i = groups.firstIndex(where: { $0.key == key }) { groups[i].files.append(f) } else { groups.append((key, [f])) }
        }
        var models: [(name: String, format: String, files: [URL])] = groups.map { ($0.key, "GGUF", $0.files) }
        if models.isEmpty {
            let config = folder.appendingPathComponent("config.json")
            if let data = try? Data(contentsOf: config), data.count <= OllamaStore.maxManifestBytes,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any], json["model_type"] != nil {
                let tensors = files.filter { $0.pathExtension == "safetensors" }
                if !tensors.isEmpty { models = [(folder.lastPathComponent, "MLX", tensors)] }
            }
        }
        let modelFiles = Set(models.flatMap(\.files))
        let companion = files.filter { !modelFiles.contains($0) }.reduce(0) { $0 + size($1) }
        return models.map { m in
            let own = m.files.reduce(0) { $0 + size($1) }
            let single = models.count == 1
            return Row(id: "\(id)/\(m.name)", name: m.name, format: m.format,
                       exclusiveBytes: single ? own + companion : own, anchor: single ? folder : m.files[0],
                       removal: single ? .delete(folder) : .deleteFiles(m.files),
                       date: LocalModelsScanner.creationDate(m.files.max { size($0) < size($1) } ?? m.files[0]))
        }
    }
}
