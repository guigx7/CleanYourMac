import Testing
@testable import CleanYourMacCore

@Suite struct AppModelTests {
    @Test func appGroupsBelongToApplications() {
        for g in [GroupID.appUninstall, .appLeftovers, .appInstallers] {
            #expect(g.category == .applications)
            #expect(!g.requiresAdmin)
            #expect(!g.requiresAdminToScan)
        }
    }

    @Test func cleanupCasesExcludeApplications() {
        #expect(CategoryID.cleanupCases == [.systemJunk, .aiClutter, .mailAttachments, .trashBins])
    }

    /// Os 14 tipos que o CleanMyMac usa para agrupar os arquivos de um app (sem um tipo próprio para caches).
    @Test func resourceKindsMatchReference() {
        #expect(Set(ResourceKind.allCases.map(\.rawValue)) == [
            "applications", "binaries", "container", "crashes", "dockIcon", "help", "installers",
            "loginItems", "logs", "other", "plugins", "preferences", "supportingFiles", "userData",
        ])
    }
}
