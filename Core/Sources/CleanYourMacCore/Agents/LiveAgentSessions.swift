import Foundation

/// Sessões do Claude Code abertas agora: `~/.claude/sessions/<pid>.json` (`{"pid":…,"sessionId":"…","cwd":"…",…}`)
/// cujo processo ainda existe. Um pid reaproveitado por outro processo conta como vivo: é o lado seguro.
public struct LiveAgentSession: Hashable, Sendable {
    public let pid: Int32
    public let sessionID: String?
    public let cwd: String?
}

public enum LiveAgentSessions {
    /// Limite de arquivos lidos e de tamanho de cada um.
    static let maxFiles = 10_000
    static let maxFileSize = 1_048_576

    /// Sessões com o processo vivo. Arquivo ilegível ou sem `pid` é ignorado.
    public static func current(home: URL, isAlive: (Int32) -> Bool = isAlive) -> [LiveAgentSession] {
        let dir = home.path + "/.claude/sessions"
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
        var out: [LiveAgentSession] = []
        for name in names.prefix(maxFiles) {
            let path = dir + "/" + name
            guard let attrs = try? FileManager.default.attributesOfItem(atPath: path),
                  attrs[.type] as? FileAttributeType == .typeRegular, (attrs[.size] as? Int ?? .max) < maxFileSize,
                  let data = FileManager.default.contents(atPath: path),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let number = obj["pid"] as? NSNumber else { continue }
            let raw = number.int64Value
            guard raw > 0, raw <= Int64(Int32.max) else { continue }
            let pid = Int32(raw)
            guard isAlive(pid) else { continue }
            out.append(LiveAgentSession(pid: pid, sessionID: obj["sessionId"] as? String, cwd: obj["cwd"] as? String))
        }
        return out
    }

    /// `kill(pid, 0)`: 0 quando o processo existe; `EPERM` também quer dizer que existe (de outro usuário).
    /// `pid` 0 ou negativo nunca é vivo (`kill(0, 0)` falaria do grupo de processos inteiro).
    public static func isAlive(_ pid: Int32) -> Bool {
        guard pid > 0 else { return false }
        if kill(pid, 0) == 0 { return true }
        return errno == EPERM
    }

    /// Verdadeiro quando alguma sessão viva tem o `cwd` igual à pasta ou dentro dela (caminho como está e o real).
    static func anyInside(_ root: String, sessions: [LiveAgentSession]) -> Bool {
        let roots = Set([root, PathPolicy.realPath(root)])
        for s in sessions {
            guard let cwd = s.cwd, cwd.hasPrefix("/") else { continue }
            for c in Set([PathPolicy.lexicalPath(cwd), PathPolicy.realPath(cwd)]) {
                if roots.contains(where: { c == $0 || c.hasPrefix($0 + "/") }) { return true }
            }
        }
        return false
    }
}
