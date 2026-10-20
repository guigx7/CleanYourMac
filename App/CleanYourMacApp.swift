import SwiftUI

enum AppInfo {
    static let name = "CleanYourMac"
}

@main
struct CleanYourMacApp: App {
    init() {
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
