import Foundation
import CleanYourMacCore

#if DEBUG
/// Relatório fixo para capturas (`CYM_DEMO=1`). Completado na Task 16/20.
enum AppsDemoData {
    static var scan: any AppsScanning { DemoScan() }

    struct DemoScan: AppsScanning {
        func run(_ context: ScanContext) -> AsyncThrowingStream<AppsScanEvent, Error> {
            AsyncThrowingStream { cont in
                cont.yield(.finished(AppsReport(apps: [], uninstaller: [], leftovers: [], installers: [],
                                                updates: UpdateCheckResult(updates: [], offline: false))))
                cont.finish()
            }
        }
    }
}
#endif
