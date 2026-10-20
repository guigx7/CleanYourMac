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
public enum PrivilegedCommand: Hashable, Sendable {
    case remove(URL)
    case removeContents(URL)
    case lipoThin(URL, keepArch: String)
    case codesignAdhoc(URL)
}

public protocol PrivilegedRunner: Sendable {
    func run(_ commands: [PrivilegedCommand]) async throws(PrivilegedError) -> [Result<Void, CleanFailure>]
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
        let dir: URL
        do {
            dir = FileManager.default.temporaryDirectory.appendingPathComponent("cym-priv-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: false,
                                                    attributes: [.posixPermissions: 0o700])
        } catch { throw .failed("\(error)") }
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("batch.sh")
        do {
            try Self.makeScript(commands).write(to: file, atomically: true, encoding: .utf8)
        } catch { throw .failed("\(error)") }

        let source = "do shell script \"/bin/sh \" & quoted form of \(Self.appleScriptString(file.path)) with administrator privileges"
        let output: String = await withCheckedContinuation { cont in
            DispatchQueue.global().async {
                var error: NSDictionary?
                let result = NSAppleScript(source: source)?.executeAndReturnError(&error)
                if let error {
                    let code = (error[NSAppleScript.errorNumber] as? Int) ?? 0
                    cont.resume(returning: code == -128 ? "\u{0}cancel" : "\u{0}fail:\(error)")
                } else {
                    cont.resume(returning: result?.stringValue ?? "")
                }
            }
        }
        if output == "\u{0}cancel" { throw .userCancelled }
        if output.hasPrefix("\u{0}fail:") { throw .failed(String(output.dropFirst(6))) }
        // `do shell script` troca \n por \r na saída.
        return Self.parse(output.replacingOccurrences(of: "\r", with: "\n"), count: commands.count)
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
