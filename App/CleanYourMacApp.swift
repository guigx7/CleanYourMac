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

/// `CYM_APPS_PARITY=/caminho.json`: roda só a análise do módulo Aplicativos (somente leitura), grava o JSON
/// de paridade e encerra. Existe também no Release porque só a cópia com Acesso Total ao Disco lê as sobras.
enum ParityExport {
    static func runIfRequested() {
        guard let path = ProcessInfo.processInfo.environment["CYM_APPS_PARITY"] else { return }
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
    }
}
