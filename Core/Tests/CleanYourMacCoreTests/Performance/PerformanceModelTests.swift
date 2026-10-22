import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct PerformanceModelTests {
    @Test func taskIDsMatchSpec() {
        #expect(MaintenanceTaskID.allCases.map(\.rawValue) == [
            "speedUpMail", "flushDNS", "freeUpPurgeable", "reindexSpotlight", "repairPermissions",
            "freeUpRAM", "periodicScripts", "thinSnapshots",
        ])
    }

    @Test func startupItemIDIsStable() {
        let plist = URL(fileURLWithPath: "/Library/LaunchAgents/com.example.agent.plist")
        let agent = StartupItem(kind: .systemAgent, name: "Example.app", label: "com.example.agent", plist: plist)
        #expect(agent.id == "systemAgent:/Library/LaunchAgents/com.example.agent.plist")
        let byLabel = StartupItem(kind: .modern, name: "Example", label: "com.example.helper", isBackground: true)
        #expect(byLabel.id == "modern:com.example.helper")
        let session = StartupItem(kind: .sessionLoginItem, name: "Warp.app",
                                  program: URL(fileURLWithPath: "/Applications/Warp.app"))
        #expect(session.id == "sessionLoginItem:/Applications/Warp.app")
    }

    @Test func backgroundVsLogin() {
        #expect(!StartupItem(kind: .sessionLoginItem, name: "A").isBackground)
        #expect(!StartupItem(kind: .modern, name: "A").isBackground)
        for kind in [StartupItemKind.userAgent, .systemAgent, .systemDaemon] {
            #expect(StartupItem(kind: kind, name: "A").isBackground)
        }
        #expect(StartupItem(kind: .modern, name: "A", isBackground: true).isBackground)
    }
}
