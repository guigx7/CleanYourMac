import SwiftUI

enum AppInfo {
    static let name = "CleanYourMac"
}

@main
struct CleanYourMacApp: App {
    var body: some Scene {
        WindowGroup {
            Text(AppInfo.name)
                .frame(minWidth: 900, minHeight: 600)
        }
    }
}
