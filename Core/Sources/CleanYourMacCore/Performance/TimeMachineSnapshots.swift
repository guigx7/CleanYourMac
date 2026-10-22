import Foundation

/// Captura local do Time Machine; `id` = data `AAAA-MM-DD-HHMMSS`.
public struct LocalSnapshot: Identifiable, Hashable, Sendable {
    public let id: String
    public let volume: URL

    public init(id: String, volume: URL) {
        self.id = id
        self.volume = volume
    }

    public var name: String { "com.apple.TimeMachine.\(id).local" }
}

/// Lista e remove capturas locais do volume de inicialização (time-machine.md), como o usuário.
/// Só capturas `com.apple.TimeMachine.*`; nunca `deletelocalsnapshots /` (todas de uma vez).
public struct TimeMachineSnapshots: Sendable {
    private let commands: any CommandRunner

    public init(commands: any CommandRunner = SystemCommandRunner()) { self.commands = commands }

    public func list() -> [LocalSnapshot] {
        let r = commands.run("/usr/bin/tmutil", ["listlocalsnapshots", "/"])
        guard r.status == 0 else { return [] }
        return r.output.split(separator: "\n").compactMap { line in
            let s = line.trimmingCharacters(in: .whitespaces)
            guard s.hasPrefix("com.apple.TimeMachine."), s.hasSuffix(".local") else { return nil }
            let date = String(s.dropFirst("com.apple.TimeMachine.".count).dropLast(".local".count))
            return Self.isDate(date) ? LocalSnapshot(id: date, volume: URL(fileURLWithPath: "/")) : nil
        }
    }

    /// Remove as capturas pedidas que ainda existem (revalidadas pela lista atual).
    public func delete(_ snapshots: [LocalSnapshot], dryRun: Bool) -> [String: Result<Void, CleanFailure>] {
        let current = Set(list().map(\.id))
        var out: [String: Result<Void, CleanFailure>] = [:]
        for s in snapshots {
            guard Self.isDate(s.id), current.contains(s.id) else {
                out[s.id] = .failure(CleanFailure(reason: "item changed"))
                continue
            }
            if dryRun {
                out[s.id] = .success(())
                continue
            }
            let r = commands.run("/usr/bin/tmutil", ["deletelocalsnapshots", s.id])
            out[s.id] = r.status == 0 ? .success(()) : .failure(CleanFailure(reason: "tmutil: \(r.status)"))
        }
        return out
    }

    static func isDate(_ s: String) -> Bool {
        s.range(of: #"^\d{4}-\d{2}-\d{2}-\d{6}$"#, options: .regularExpression) != nil
    }
}
