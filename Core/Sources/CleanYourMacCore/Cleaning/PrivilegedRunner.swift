import Foundation

public struct CleanFailure: Error, Hashable, Sendable {
    public let reason: String
    public init(reason: String) { self.reason = reason }
    public static let cancelled = CleanFailure(reason: "cancelled")
}

public enum PrivilegedError: Error, Sendable {
    case userCancelled
    case failed(String)
}

/// Operações que podem rodar como root, num único lote por limpeza.
public enum PrivilegedCommand: Hashable, Sendable, Codable {
    case remove(URL)
    case removeContents(URL)
    case lipoThin(URL, keepArch: String)
    case codesignAdhoc(URL)
}

public protocol PrivilegedRunner: Sendable {
    func run(_ commands: [PrivilegedCommand]) async throws(PrivilegedError) -> [Result<Void, CleanFailure>]
    /// Mede (`du -sk`) caminhos ilegíveis para o usuário; `nil` onde não deu.
    func measure(_ urls: [URL]) async throws(PrivilegedError) -> [Int64?]
}

extension PrivilegedRunner {
    public func measure(_ urls: [URL]) async throws(PrivilegedError) -> [Int64?] { urls.map { _ in nil } }
}

/// Pede a senha de administrador uma vez e roda o lote via `do shell script … with administrator privileges`.
public struct AppleScriptPrivilegedRunner: PrivilegedRunner {
    public struct Tools: Sendable {
        public var rm = "/bin/rm"
        public var find = "/usr/bin/find"
        public var lipo = "/usr/bin/lipo"
        public var mv = "/bin/mv"
        public var codesign = "/usr/bin/codesign"
        public init(rm: String = "/bin/rm") { self.rm = rm }
    }

    public init() {}

    public func run(_ commands: [PrivilegedCommand]) async throws(PrivilegedError) -> [Result<Void, CleanFailure>] {
        guard !commands.isEmpty else { return [] }
        return Self.parse(try await execute(Self.makeScript(commands)), count: commands.count)
    }

    public func measure(_ urls: [URL]) async throws(PrivilegedError) -> [Int64?] {
        guard !urls.isEmpty else { return [] }
        return Self.parseSizes(try await execute(Self.makeMeasureScript(urls)), count: urls.count)
    }

    /// Script que imprime `CYM:<i>:ok:<KB>` por caminho.
    public static func makeMeasureScript(_ urls: [URL]) -> String {
        var lines = ["#!/bin/sh", "set -u"]
        for (i, u) in urls.enumerated() {
            lines.append("s=$(/usr/bin/du -sk -- \(quote(u.path)) 2>/dev/null | /usr/bin/cut -f1) && [ -n \"$s\" ] && echo \"CYM:\(i):ok:$s\" || echo 'CYM:\(i):fail'")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func parseSizes(_ output: String, count: Int) -> [Int64?] {
        var out = [Int64?](repeating: nil, count: count)
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":")
            guard parts.count == 4, parts[0] == "CYM", parts[2] == "ok", let i = Int(parts[1]), out.indices.contains(i),
                  let kb = Int64(parts[3]) else { continue }
            out[i] = kb * 1024
        }
        return out
    }

    /// Fonte AppleScript com o script inteiro embutido (nada é lido de arquivo gravável pelo usuário).
    public static func appleScriptSource(for script: String) -> String {
        "do shell script " + appleScriptString(script) + " with administrator privileges"
    }

    /// Roda um script sh como root (uma senha) e devolve a saída.
    private func execute(_ script: String) async throws(PrivilegedError) -> String {
        let source = Self.appleScriptSource(for: script)
        let result: (Int32, String, String) = await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
                p.arguments = ["-e", source]
                let out = Pipe(), err = Pipe()
                p.standardOutput = out
                p.standardError = err
                guard (try? p.run()) != nil else { cont.resume(returning: (-1, "", "osascript failed to start")); return }
                let o = out.fileHandleForReading.readDataToEndOfFile()
                let e = err.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                cont.resume(returning: (p.terminationStatus, String(decoding: o, as: UTF8.self), String(decoding: e, as: UTF8.self)))
            }
        }
        if result.0 != 0 {
            if result.2.contains("-128") { throw .userCancelled }
            throw .failed(result.2)
        }
        // `do shell script` troca \n por \r na saída.
        return result.1.replacingOccurrences(of: "\r", with: "\n")
    }

    /// Script sh com cada caminho entre aspas simples; cada comando imprime `CYM:<i>:ok|fail`.
    public static func makeScript(_ commands: [PrivilegedCommand], tools: Tools = Tools()) -> String {
        var lines = ["#!/bin/sh", "set -u"]
        for (i, cmd) in commands.enumerated() {
            let body: String
            switch cmd {
            case .remove(let u):
                body = "\(tools.rm) -rf -- \(quote(u.path))"
            case .removeContents(let u):
                body = "\(tools.find) \(quote(u.path)) -mindepth 1 -maxdepth 1 -exec \(tools.rm) -rf -- {} +"
            case .lipoThin(let u, let arch):
                let tmp = quote(u.path + ".cymthin")
                body = "\(tools.lipo) \(quote(u.path)) -thin \(quote(arch)) -output \(tmp) && \(tools.mv) -f \(tmp) \(quote(u.path))"
            case .codesignAdhoc(let u):
                body = "\(tools.codesign) --force --deep --sign - \(quote(u.path))"
            }
            lines.append("if \(body); then echo 'CYM:\(i):ok'; else echo 'CYM:\(i):fail'; fi")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    static func parse(_ output: String, count: Int) -> [Result<Void, CleanFailure>] {
        var results = [Result<Void, CleanFailure>](repeating: .failure(CleanFailure(reason: "no result")), count: count)
        for line in output.split(separator: "\n") {
            let parts = line.split(separator: ":")
            guard parts.count == 3, parts[0] == "CYM", let i = Int(parts[1]), results.indices.contains(i) else { continue }
            results[i] = parts[2] == "ok" ? .success(()) : .failure(CleanFailure(reason: "privileged command failed"))
        }
        return results
    }

    static func quote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func appleScriptString(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }
}
