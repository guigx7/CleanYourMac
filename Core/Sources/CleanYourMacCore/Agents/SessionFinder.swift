import Foundation

/// Sessão antiga de um agente: uma conversa, um job ou um arquivo de sessão, com os restos ligados a ela.
public struct AgentSession: Hashable, Sendable, Identifiable {
    /// `"<agente>:<sessão>"`.
    public let id: String
    /// Id do agente no `AgentsCatalog`.
    public let agent: String
    /// Claude Code: nome cru da pasta do projeto (por exemplo `-Users-x-Projetos-Y`); Gemini: o hash. Senão `nil`.
    public let project: String?
    public let urls: [URL]
    /// Tamanho alocado somado de todas as urls.
    public let size: Int64
    /// Data mais nova entre todas as urls, descendo nas pastas.
    public let lastModified: Date
    /// Só restos (`file-history`, `session-env`, `todos`) sem o `.jsonl` da conversa.
    public let isOrphanRemains: Bool
    /// Claude Code: o primeiro `cwd` do `.jsonl` (a pasta onde a conversa rodou). Senão `nil`.
    public let workingDirectory: String?

    init(id: String, agent: String, project: String?, urls: [URL], size: Int64, lastModified: Date, isOrphanRemains: Bool,
         workingDirectory: String? = nil) {
        self.id = id
        self.agent = agent
        self.project = project
        self.urls = urls
        self.size = size
        self.lastModified = lastModified
        self.isOrphanRemains = isOrphanRemains
        self.workingDirectory = workingDirectory
    }
}

/// Acha sessões com mais de 7 dias. Regras (o que sai daqui vai para o Lixo; na dúvida, fica de fora):
/// - nunca segue links: um link nunca vira url nem é percorrido;
/// - nunca inclui nada que case com `AgentsCatalog.neverTouch` (memória, histórico, ajustes, `*.sqlite`...);
/// - uma sessão do Claude Code é um item só: o `.jsonl`, a pasta ao lado e os restos de mesmo id;
/// - a data da sessão é a mais nova entre todas as urls, descendo nas pastas; a descida é limitada a
///   `maxWalkEntries` entradas por url e, ao estourar, a sessão conta como recém-modificada (fica de fora);
/// - job do Claude Code só quando o estado é conhecido e terminal (`done`, `completed`, `failed`, `cancelled`),
///   sem `backup/` e sem worktree dentro;
/// - conversa de agente vivo (`activeClaudeSessionIDs`: job não terminal ou sessão com o pid vivo) nunca entra, nem os restos.
public struct SessionFinder: Sendable {
    public let home: URL
    public let now: Date
    public let worktrees: Set<URL>

    /// Idade mínima: 7 dias.
    static let minAge: TimeInterval = 604_800
    static let maxWalkEntries = 20_000
    static let releasingJobStates: Set<String> = ["done", "completed", "failed", "cancelled"]

    private let homePath: String
    private let sizer = FileSizer(mode: .allocated)

    public init(home: URL, now: Date, worktrees: Set<URL>) {
        self.home = home
        self.now = now
        self.worktrees = worktrees
        homePath = home.path
    }

    public func sessions() -> [AgentSession] {
        var out: [AgentSession] = []
        for agent in AgentsCatalog.agents {
            switch agent.sessions {
            case .claudeCode: out += claude(agent.id)
            case .codex: out += codex(agent.id)
            case .gemini: out += gemini(agent.id)
            }
        }
        let order = AgentsCatalog.agents.map(\.id)
        return out.sorted {
            let a = order.firstIndex(of: $0.agent) ?? .max, b = order.firstIndex(of: $1.agent) ?? .max
            if a != b { return a < b }
            if $0.lastModified != $1.lastModified { return $0.lastModified < $1.lastModified }
            return $0.id < $1.id
        }
    }

    // MARK: - Claude Code

    private func claude(_ agent: String) -> [AgentSession] {
        let base = homePath + "/.claude"
        var out: [AgentSession] = []

        // Conversas: `projects/<projeto>/<id>.jsonl` + pasta `<id>/` ao lado.
        var projectOf: [String: String] = [:]
        var urlsOf: [String: [String]] = [:]
        for proj in entries(base + "/projects") {
            let pdir = base + "/projects/" + proj
            guard isRealDirectory(pdir), !isNeverTouch(pdir) else { continue }
            for name in entries(pdir) {
                let p = pdir + "/" + name
                if isNeverTouch(p) || isSymlink(p) { continue }
                if name.hasSuffix(".jsonl"), !isDirectory(p) {
                    let id = String(name.dropLast(".jsonl".count))
                    guard Self.isUUID(id) else { continue }
                    projectOf[id] = proj
                    urlsOf[id, default: []].append(p)
                } else if Self.isUUID(name), isRealDirectory(p) {
                    urlsOf[name, default: []].append(p)
                }
            }
        }
        let withTranscript = Set(projectOf.keys)

        // Restos de mesmo id: só nomes em formato de UUID (em `todos`, o UUID do começo do nome).
        for dirName in ["file-history", "session-env", "todos"] {
            for name in entries(base + "/" + dirName) {
                let p = base + "/" + dirName + "/" + name
                if isNeverTouch(p) || isSymlink(p) { continue }
                let id = dirName == "todos" ? String(name.prefix(36)) : name
                guard Self.isUUID(id), dirName != "todos" || name.count == 36 || "-.".contains(name[name.index(name.startIndex, offsetBy: 36)])
                else { continue }
                urlsOf[id, default: []].append(p)
            }
        }

        let active = Self.activeClaudeSessionIDs(home: home)
        for (id, paths) in urlsOf where !active.contains(id.lowercased()) {
            let isOrphan = !withTranscript.contains(id)
            let transcript = paths.first { $0.hasSuffix("/" + id + ".jsonl") }
            if let s = session(id: "\(agent):\(id)", agent: agent, project: projectOf[id], paths: paths.sorted(), orphan: isOrphan,
                               workingDirectory: transcript.flatMap(Self.workingDirectory(ofTranscript:))) {
                out.append(s)
            }
        }

        // Jobs.
        for name in entries(base + "/jobs") {
            let job = base + "/jobs/" + name
            guard isRealDirectory(job), !isNeverTouch(job), isJobReleasable(job),
                  let s = session(id: "\(agent):job-\(name)", agent: agent, project: nil, paths: [job], orphan: false) else { continue }
            out.append(s)
        }
        return out
    }

    /// Primeiro `"cwd"` de uma linha JSON nos primeiros 64 KB do `.jsonl` (a linha cortada no fim é ignorada).
    static func workingDirectory(ofTranscript path: String) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let data = try? handle.read(upToCount: 65_536) else { return nil }
        for line in data.split(separator: UInt8(ascii: "\n")) {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line)) as? [String: Any],
                  let cwd = obj["cwd"] as? String, cwd.hasPrefix("/") else { continue }
            return cwd
        }
        return nil
    }

    /// Nome de sessão do Claude Code: UUID.
    static func isUUID(_ s: String) -> Bool {
        s.range(of: "^[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}$", options: .regularExpression) != nil
    }

    private func isJobReleasable(_ job: String) -> Bool {
        guard let data = FileManager.default.contents(atPath: job + "/state.json"), data.count < 1_048_576,
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let state = (obj["state"] as? String)?.lowercased(), Self.releasingJobStates.contains(state) else { return false }
        if exists(job + "/backup") { return false }
        // Worktree dentro: conjunto recebido ou `.git` no job, em `tmp` ou em `tmp/*`.
        let realJob = PathPolicy.realPath(job)
        if worktrees.contains(where: { let w = PathPolicy.realPath($0.path); return w == realJob || w.hasPrefix(realJob + "/") }) { return false }
        // `.git` (arquivo ou pasta) em qualquer nível do job; estourou o limite de entradas, o job fica de fora.
        let e = FileManager.default.enumerator(at: URL(fileURLWithPath: job, isDirectory: true), includingPropertiesForKeys: nil,
                                               options: [], errorHandler: { _, _ in true })
        var n = 0
        while let u = e?.nextObject() as? URL {
            n += 1
            if n > Self.maxWalkEntries || u.lastPathComponent == ".git" { return false }
        }
        return true
    }

    /// `state.json` de um job, se legível.
    static func jobState(_ job: String) -> [String: Any]? {
        guard let data = FileManager.default.contents(atPath: job + "/state.json"), data.count < 1_048_576 else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func isActive(_ state: [String: Any]?) -> Bool {
        guard let s = (state?["state"] as? String)?.lowercased() else { return true }
        return !releasingJobStates.contains(s)
    }

    /// O job ainda não terminou (estado não terminal, desconhecido ou `state.json` ilegível): na dúvida, ativo.
    public static func isJobActive(_ job: String) -> Bool { isActive(jobState(job)) }

    /// Conversas de agentes que ainda estão de pé: o `sessionId` e o `resumeSessionId` de todo job cujo estado não é
    /// terminal (sem estado conhecido também conta) e o `sessionId` de cada `~/.claude/sessions/<pid>.json` com o
    /// processo vivo. Essas conversas e os restos delas nunca entram, seja qual for a idade.
    public static func activeClaudeSessionIDs(home: URL) -> Set<String> {
        var ids = Set<String>()
        let jobs = home.path + "/.claude/jobs"
        for name in (try? FileManager.default.contentsOfDirectory(atPath: jobs)) ?? [] {
            guard let obj = jobState(jobs + "/" + name), isActive(obj) else { continue }
            for key in ["sessionId", "resumeSessionId"] { if let id = obj[key] as? String, !id.isEmpty { ids.insert(id.lowercased()) } }
        }
        for s in LiveAgentSessions.current(home: home) { if let id = s.sessionID, !id.isEmpty { ids.insert(id.lowercased()) } }
        return ids
    }

    // MARK: - Codex

    private func codex(_ agent: String) -> [AgentSession] {
        let root = homePath + "/.codex/sessions"
        var out: [AgentSession] = []
        guard isRealDirectory(root) else { return out }
        var stack = [root]
        var visited = 0
        while let dir = stack.popLast() {
            visited += 1
            if visited > Self.maxWalkEntries { break }
            for name in entries(dir) {
                let p = dir + "/" + name
                if isNeverTouch(p) || isSymlink(p) { continue }
                if isDirectory(p) { stack.append(p); continue }
                guard name.hasPrefix("rollout-"), name.hasSuffix(".jsonl") else { continue }
                let id = String(name.dropLast(".jsonl".count))
                if let s = session(id: "\(agent):\(id)", agent: agent, project: nil, paths: [p], orphan: false) { out.append(s) }
            }
        }
        return out
    }

    // MARK: - Gemini

    private func gemini(_ agent: String) -> [AgentSession] {
        let root = homePath + "/.gemini/tmp"
        var out: [AgentSession] = []
        for hash in entries(root) {
            let chats = root + "/" + hash + "/chats"
            guard isRealDirectory(root + "/" + hash), isRealDirectory(chats) else { continue }
            for name in entries(chats) where name.hasSuffix(".json") {
                let p = chats + "/" + name
                if isNeverTouch(p) || isSymlink(p) || isDirectory(p) { continue }
                let id = "\(hash)/" + String(name.dropLast(".json".count))
                if let s = session(id: "\(agent):\(id)", agent: agent, project: hash, paths: [p], orphan: false) { out.append(s) }
            }
        }
        return out
    }

    // MARK: - Montagem

    /// `nil` quando a sessão é recente demais (ou a descida estourou o limite).
    private func session(id: String, agent: String, project: String?, paths: [String], orphan: Bool,
                         workingDirectory: String? = nil) -> AgentSession? {
        var newest = Date.distantPast
        for p in paths {
            guard let d = newestDate(p) else { return nil }
            newest = max(newest, d)
        }
        guard now.timeIntervalSince(newest) > Self.minAge else { return nil }
        let urls = paths.map { URL(fileURLWithPath: $0, isDirectory: isDirectory($0)) }
        return AgentSession(id: id, agent: agent, project: project, urls: urls,
                            size: urls.reduce(0) { $0 + sizer.allocatedSize(of: $1) },
                            lastModified: newest, isOrphanRemains: orphan, workingDirectory: workingDirectory)
    }

    /// Data mais nova de um caminho, descendo nas pastas sem seguir links; `nil` ao passar do limite de entradas.
    private func newestDate(_ path: String) -> Date? {
        var newest = modDate(path) ?? .distantPast
        guard isRealDirectory(path) else { return newest }
        var n = 0
        let e = FileManager.default.enumerator(at: URL(fileURLWithPath: path, isDirectory: true),
                                               includingPropertiesForKeys: [.contentModificationDateKey], options: [],
                                               errorHandler: { _, _ in true })
        while let u = e?.nextObject() as? URL {
            n += 1
            if n > Self.maxWalkEntries { return nil }
            if let d = modDate(u.path) { newest = max(newest, d) }
        }
        return newest
    }

    // MARK: - Utilitários

    private func isNeverTouch(_ path: String) -> Bool { AgentsCatalog.isNeverTouch(path, home: home) }

    private func entries(_ dir: String) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).sorted()
    }

    private func modDate(_ path: String) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.modificationDate] as? Date
    }

    private func isSymlink(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeSymbolicLink
    }

    private func exists(_ path: String) -> Bool { (try? FileManager.default.attributesOfItem(atPath: path)) != nil }

    private func isDirectory(_ path: String) -> Bool {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeDirectory
    }

    private func isRealDirectory(_ path: String) -> Bool { isDirectory(path) && !isSymlink(path) }
}
