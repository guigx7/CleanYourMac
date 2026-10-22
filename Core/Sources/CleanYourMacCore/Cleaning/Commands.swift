import Foundation
@preconcurrency import CoreServices

/// Executa ferramentas do sistema (launchctl, defaults, killall). Injetável nos testes.
public protocol CommandRunner: Sendable {
    func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String)
    /// Com tempo-limite: `nil` quando o tempo esgotou (o processo é encerrado antes de voltar).
    func run(_ executable: String, _ arguments: [String], timeout: Duration) -> (status: Int32, output: String)?
}

extension CommandRunner {
    public func run(_ executable: String, _ arguments: [String], timeout: Duration) -> (status: Int32, output: String)? {
        run(executable, arguments)
    }
}

public struct SystemCommandRunner: CommandRunner {
    public init() {}

    public func run(_ executable: String, _ arguments: [String]) -> (status: Int32, output: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        guard (try? p.run()) != nil else { return (-1, "") }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: data, as: UTF8.self))
    }

    private final class Output: @unchecked Sendable {
        var data = Data()
    }

    public func run(_ executable: String, _ arguments: [String], timeout: Duration) -> (status: Int32, output: String)? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: executable)
        p.arguments = arguments
        p.standardInput = FileHandle.nullDevice
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        let exited = DispatchSemaphore(value: 0), drained = DispatchSemaphore(value: 0)
        p.terminationHandler = { _ in exited.signal() }
        guard (try? p.run()) != nil else { return (-1, "") }
        let out = Output()
        DispatchQueue.global().async {
            out.data = pipe.fileHandleForReading.readDataToEndOfFile()
            drained.signal()
        }
        let seconds = Double(timeout.components.seconds) + Double(timeout.components.attoseconds) / 1e18
        guard exited.wait(timeout: .now() + seconds) == .success else {
            p.terminate()
            if exited.wait(timeout: .now() + 2) == .timedOut {
                kill(p.processIdentifier, SIGKILL)
                exited.wait()
            }
            // Filhos que herdaram o pipe podem segurá-lo; não esperar por eles.
            _ = drained.wait(timeout: .now() + 1)
            return nil
        }
        drained.wait()
        return (p.terminationStatus, String(decoding: out.data, as: UTF8.self))
    }
}

// MARK: - Itens de início da sessão

public struct LoginItemEntry: Sendable, Hashable {
    public let name: String?
    public let url: URL?

    public init(name: String?, url: URL?) {
        self.name = name
        self.url = url
    }
}

/// Lista de Itens de Início da sessão (docs/re/specs/broken-login-items.md, sub-análise 1).
public protocol LoginItemsSource: Sendable {
    func entries(_ context: ScanContext) -> [LoginItemEntry]
    func remove(_ entry: LoginItemEntry) -> Bool
    /// Põe um app no fim da lista (reativar um item desativado por nós).
    func add(_ app: URL) -> Bool
}

extension LoginItemsSource {
    public func remove(_ entry: LoginItemEntry) -> Bool { false }
    public func add(_ app: URL) -> Bool { false }
}

/// `LSSharedFileList` (obsoleta, mas é a que o CleanMyMac usa; não enxerga itens de SMAppService).
public struct SystemLoginItems: LoginItemsSource {
    public init() {}

    private func list() -> LSSharedFileList? {
        LSSharedFileListCreate(nil, kLSSharedFileListSessionLoginItems.takeUnretainedValue(), nil)?.takeRetainedValue()
    }

    private func snapshot(_ list: LSSharedFileList) -> [LSSharedFileListItem] {
        var seed: UInt32 = 0
        return (LSSharedFileListCopySnapshot(list, &seed)?.takeRetainedValue() as? [LSSharedFileListItem]) ?? []
    }

    private func entry(_ item: LSSharedFileListItem) -> LoginItemEntry {
        let name = LSSharedFileListItemCopyDisplayName(item).takeRetainedValue() as String
        let url = LSSharedFileListItemCopyResolvedURL(item, UInt32(kLSSharedFileListNoUserInteraction | kLSSharedFileListDoNotMountVolumes), nil)?
            .takeRetainedValue() as URL?
        return LoginItemEntry(name: name, url: url?.isFileURL == true ? url : nil)
    }

    public func entries(_ context: ScanContext) -> [LoginItemEntry] {
        guard let list = list() else { return [] }
        return snapshot(list).map(entry)
    }

    public func remove(_ entry: LoginItemEntry) -> Bool {
        guard let list = list(),
              let item = snapshot(list).first(where: { self.entry($0) == entry }) else { return false }
        return LSSharedFileListItemRemove(list, item) == noErr
    }

    public func add(_ app: URL) -> Bool {
        guard let list = list() else { return false }
        return LSSharedFileListInsertItemURL(list, kLSSharedFileListItemLast.takeUnretainedValue(), nil, nil, app as CFURL, nil, nil) != nil
    }
}
