import Foundation

public enum ProcessOutcome: Equatable, Sendable {
    case exited(Int32)
    case timedOut
    case cancelled
}

/// Roda um programa com tempo-limite; no tempo esgotado ou no cancelamento da Task, encerra o processo e espera ele sair.
public protocol ProcessRunner: Sendable {
    func run(_ executable: String, _ arguments: [String], timeout: Duration) async -> ProcessOutcome
}

public struct SystemProcessRunner: ProcessRunner {
    public init() {}

    private final class Box: @unchecked Sendable {
        let process = Process()
    }

    public func run(_ executable: String, _ arguments: [String], timeout: Duration) async -> ProcessOutcome {
        let box = Box()
        let p = box.process
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.standardInput = FileHandle.nullDevice
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        let exited = AsyncStream<Int32> { c in
            p.terminationHandler = { c.yield($0.terminationStatus); c.finish() }
        }
        guard (try? p.run()) != nil else { return .exited(-1) }
        let first: ProcessOutcome? = await withTaskGroup(of: ProcessOutcome?.self) { group in
            group.addTask {
                for await status in exited { return .exited(status) }
                return nil
            }
            group.addTask {
                do {
                    try await Task.sleep(for: timeout)
                    return .timedOut
                } catch {
                    return nil
                }
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        if case .exited = first { return first! }
        Self.stop(box.process)
        return first ?? .cancelled
    }

    /// SIGTERM, até 2 s de espera, depois SIGKILL; só volta com o processo encerrado.
    private static func stop(_ p: Process) {
        guard p.isRunning else { return }
        p.terminate()
        for _ in 0..<40 where p.isRunning { usleep(50_000) }
        if p.isRunning { kill(p.processIdentifier, SIGKILL) }
        p.waitUntilExit()
    }
}
