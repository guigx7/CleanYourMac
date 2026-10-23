import CryptoKit
import Foundation
import UniformTypeIdentifiers

/// Um grupo de cópias idênticas (mesmo tamanho e mesmo SHA-256).
public struct DuplicateGroup: Hashable, Sendable, Identifiable {
    /// Na ordem em que sairiam: a última é a que fica (`keeper`).
    public let files: [ClutterFile]
    public let hash: String

    public init(files: [ClutterFile], hash: String) {
        self.files = files
        self.hash = hash
    }

    public var id: String { hash }
    public var keeper: ClutterFile { files[files.count - 1] }
    /// Marcação automática: todas menos a que fica.
    public var autoselected: [ClutterFile] { Array(files.dropLast()) }
    public var totalSize: Int64 { files.reduce(0) { $0 + $1.size } }
    /// O que dá para liberar tirando as cópias de sobra.
    public var removableSize: Int64 { autoselected.reduce(0) { $0 + $1.size } }
    /// Título: o nome da cópia que fica.
    public var name: String { keeper.url.lastPathComponent }
}

/// Duplicatas (docs/re/specs/clutter/duplicates.md): arquivos ≥ 100 KiB com o mesmo conteúdo.
public struct DuplicateFinder: Sendable {
    /// 100 KiB.
    public static let minimum: Int64 = 102_400

    public enum Kind: String, CaseIterable, Sendable { case applications, archives, audio, documents, pictures, videos, other }

    private let downloads: String

    public init(home: URL) {
        downloads = PathPolicy.lexicalPath(home.appendingPathComponent("Downloads").path) + "/"
    }

    public func groups(from files: [ClutterFile], isCancelled: @Sendable () -> Bool = { Task.isCancelled }) throws -> [DuplicateGroup] {
        let candidates = files.filter { $0.size >= Self.minimum && !ClutterRules.isInsideXcassets($0.url) }
        let bySize = Dictionary(grouping: candidates, by: \.size).values.filter { $0.count > 1 }
        let toHash = bySize.flatMap { $0 }
        // SHA-256 em paralelo (só o que tem outro arquivo do mesmo tamanho).
        let hashes = ConcurrentResults<String?>(count: toHash.count)
        let cancelled = Flag()
        DispatchQueue.concurrentPerform(iterations: toHash.count) { i in
            guard !cancelled.isSet else { return }
            if isCancelled() { cancelled.set(); return }
            hashes[i] = Self.hash(toHash[i])
        }
        if cancelled.isSet { throw CancellationError() }
        var byHash: [String: [ClutterFile]] = [:]
        for (i, f) in toHash.enumerated() {
            guard let h = hashes[i] else { continue }
            byHash["\(f.size):\(h)", default: []].append(f)
        }
        return byHash.compactMap { key, files -> DuplicateGroup? in
            guard files.count > 1 else { return nil }
            return DuplicateGroup(files: files.sorted(by: removeBefore), hash: key)
        }
        .sorted { $0.totalSize != $1.totalSize ? $0.totalSize > $1.totalSize : $0.name < $1.name }
    }

    // MARK: - Qual cópia sai

    /// Cadeia de desempate da spec (§3): Downloads → número de cópia maior → modificação mais antiga → caminho mais fundo →
    /// nome mais curto → caminho menor na ordem alfabética. `true` = `a` sai antes de `b`.
    func removeBefore(_ a: ClutterFile, _ b: ClutterFile) -> Bool {
        let da = a.url.path.hasPrefix(downloads), db = b.url.path.hasPrefix(downloads)
        if da != db { return da }
        let ca = Self.copyNumber(a.url), cb = Self.copyNumber(b.url)
        if ca != cb { return ca > cb }
        let ma = a.modified ?? .distantPast, mb = b.modified ?? .distantPast
        if ma != mb { return ma < mb }
        let pa = a.url.pathComponents.count, pb = b.url.pathComponents.count
        if pa != pb { return pa > pb }
        let na = a.url.lastPathComponent.count, nb = b.url.lastPathComponent.count
        if na != nb { return na < nb }
        return a.url.path < b.url.path
    }

    /// "x copy 3.png" → 3, "x copy.png" / "x cópia.png" → 1, "x.png" → 0. "x (2).png" e "x 2.png" não contam (paridade: o
    /// CleanMyMac deixa a cópia "(N)" mais nova).
    static func copyNumber(_ url: URL) -> Int {
        let base = url.deletingPathExtension().lastPathComponent
        func match(_ pattern: String) -> String? {
            guard let r = base.range(of: pattern, options: [.regularExpression, .caseInsensitive]) else { return nil }
            return String(base[r])
        }
        if let m = match(#" (copy|cópia) (\d+)$"#) { return Int(m.filter(\.isNumber)) ?? 1 }
        if match(#" (copy|cópia)$"#) != nil { return 1 }
        return 0
    }

    // MARK: - Tipos

    public static func kind(_ file: ClutterFile) -> Kind {
        if file.isPackage, file.url.pathExtension.lowercased() == "app" { return .applications }
        guard let type = file.type else { return .other }
        if type.conforms(to: .application) { return .applications }
        if type.conforms(to: .archive) { return .archives }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .text) { return .documents }
        if type.conforms(to: .image) { return .pictures }
        if type.conforms(to: .movie) { return .videos }
        return .other
    }

    // MARK: - Hash

    /// SHA-256 do arquivo inteiro em blocos de 1 MiB; pacotes: dos caminhos internos + hash de cada arquivo.
    static func hash(_ file: ClutterFile) -> String? {
        if file.isPackage {
            guard let e = FileManager.default.enumerator(at: file.url, includingPropertiesForKeys: [.isRegularFileKey]) else { return nil }
            var parts: [String] = []
            let base = file.url.path.count + 1
            while let u = e.nextObject() as? URL {
                guard (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
                // Arquivo ilegível: sem hash do pacote (dois pacotes com partes ilegíveis não viram "iguais").
                guard let h = hashFile(u) else { return nil }
                parts.append(String(u.path.dropFirst(base)) + ":" + h)
            }
            return hex(SHA256.hash(data: Data(parts.sorted().joined(separator: "\n").utf8)))
        }
        return hashFile(file.url)
    }

    static func hashFile(_ url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var sha = SHA256()
        while true {
            // `nil` ou vazio = fim do arquivo; erro de leitura = sem hash. Um pool por bloco (senão arquivos de GBs ficam na memória).
            let more: Bool? = autoreleasepool {
                let chunk: Data?
                do { chunk = try handle.read(upToCount: 1 << 20) } catch { return nil }
                guard let chunk, !chunk.isEmpty else { return false }
                sha.update(data: chunk)
                return true
            }
            guard let more else { return nil }
            if !more { break }
        }
        return hex(sha.finalize())
    }

    private static func hex(_ digest: SHA256.Digest) -> String { digest.map { String(format: "%02x", $0) }.joined() }
}

/// Vetor escrito por várias threads em posições diferentes.
final class ConcurrentResults<T>: @unchecked Sendable {
    private var values: [T?]
    private let lock = NSLock()
    init(count: Int) { values = Array(repeating: nil, count: count) }
    subscript(i: Int) -> T? {
        get { lock.withLock { values[i] } }
        set { lock.withLock { values[i] = newValue } }
    }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    func set() { lock.withLock { value = true } }
    var isSet: Bool { lock.withLock { value } }
}
