import SwiftUI
import CleanYourMacCore

enum AppInfo {
    static let name = "CleanYourMac"
}

@main
struct CleanYourMacApp: App {
    init() {
        ParityExport.runIfRequested()
        #if DEBUG
        DebugSnapshot.scheduleIfRequested()
        #endif
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
    }
}

/// Debug: `CYM_APPS_PARITY=<arquivo>.json` roda só a análise do módulo Aplicativos (somente leitura), grava o JSON de
/// paridade em ~/Library/Logs/CleanYourMac e encerra. Fica fora do Release: outro processo não pode usar o Acesso Total
/// ao Disco do app para gravar o resultado onde quiser.
enum ParityExport {
    static func isAllowedOutput(_ path: String) -> Bool {
        let dir = PathPolicy.realPath(CleanupLog.standard.directory.path)
        let target = PathPolicy.realPath((path as NSString).standardizingPath)
        return target.hasPrefix(dir + "/") && target.hasSuffix(".json")
    }

    static func runIfRequested() {
        #if DEBUG
        guard let name = ProcessInfo.processInfo.environment["CYM_APPS_PARITY"] else { return }
        try? FileManager.default.createDirectory(at: CleanupLog.standard.directory, withIntermediateDirectories: true)
        let path = name.hasPrefix("/") ? name : CleanupLog.standard.directory.appendingPathComponent(name).path
        guard isAllowedOutput(path) else { exit(2) }
        let done = DispatchSemaphore(value: 0)
        Task.detached {
            var report: AppsReport?
            let stream = Registry.appsScan(privilegedAvailable: HelperManager.isActive).run(ScanContext.current())
            do {
                for try await event in stream { if case .finished(let r) = event { report = r } }
            } catch {
                report = nil
            }
            var json = report?.parityJSON() ?? [:]
            json["fullDiskAccess"] = PermissionsService.hasFullDiskAccess()
            if report != nil, let data = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: URL(fileURLWithPath: path))
            }
            done.signal()
        }
        done.wait()
        exit(0)
        #endif
    }
}
