import AppKit

public struct RunningApp: Hashable, Sendable {
    public let bundleID: String
    public let name: String
    public let pid: pid_t

    public init(bundleID: String, name: String, pid: pid_t) {
        self.bundleID = bundleID
        self.name = name
        self.pid = pid
    }
}

/// Quais apps estão abertos e como fechá-los (docs/re/specs/apps/removal.md §Apps abertos).
public protocol RunningApps: Sendable {
    func running(bundleIDs: Set<String>) -> [RunningApp]
    /// Pede para fechar (ou força); espera até 10 s pelo fim do processo.
    func quit(_ app: RunningApp, force: Bool) async -> Bool
}

public struct WorkspaceRunningApps: RunningApps {
    public init() {}

    public func running(bundleIDs: Set<String>) -> [RunningApp] {
        NSWorkspace.shared.runningApplications.compactMap { a in
            guard let id = a.bundleIdentifier, bundleIDs.contains(id) else { return nil }
            return RunningApp(bundleID: id, name: a.localizedName ?? id, pid: a.processIdentifier)
        }
    }

    public func quit(_ app: RunningApp, force: Bool) async -> Bool {
        guard let running = NSRunningApplication(processIdentifier: app.pid) else { return true }
        _ = force ? running.forceTerminate() : running.terminate()
        for _ in 0..<50 {
            if running.isTerminated { return true }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return running.isTerminated
    }
}

/// Manda um item para o Lixo do volume dele.
public protocol Trasher: Sendable {
    func trash(_ url: URL) throws
}

public struct FileTrasher: Trasher {
    public init() {}

    public func trash(_ url: URL) throws {
        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
    }
}
