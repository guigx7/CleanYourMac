import Foundation
import Testing
@testable import CleanYourMacCore

private func container(_ t: FixtureTree, _ id: String, bundle: String?, legacy: Bool = false, bytes: Int = 4096, emptyMeta: Bool = false) {
    t.file("Users/tester/Library/Containers/\(id)/Data/Library/Caches/x", bytes: bytes)
    guard bundle != nil || emptyMeta else { return }
    let meta: [String: Any] = bundle.map { ["MCMMetadataIdentifier": id, "MCMMetadataInfo": ["SandboxProfileDataValidationInfo": [
        "SandboxProfileDataValidationParametersKey": ["application_bundle": $0]]]] }
        ?? ["MCMMetadataIdentifier": id, "MCMMetadataInfo": ["com.apple.MobileInstallation.ContentProtectionClass": 0]]
    let name = legacy ? "Container.plist" : ".com.apple.containermanagerd.metadata.plist"
    try! PropertyListSerialization.data(fromPropertyList: meta, format: .binary, options: 0)
        .write(to: t.url("Users/tester/Library/Containers/\(id)/\(name)"))
}

private func scanner(_ t: FixtureTree, registered: Set<String> = []) -> LeftoversScanner {
    LeftoversScanner(catalog: AppCatalog(query: FakeAppQuery(), usage: FakeUsage(), displayName: { $0.lastPathComponent }),
                     finder: RelatedFilesFinder(loginItems: FakeLoginItems(entries: []), receipts: FakeReceipts()),
                     appExists: { registered.contains($0) })
}

@Suite struct LeftoversTests {
    @Test func leftoverOfRemovedAppFromContainerMetadata() async throws {
        let t = FixtureTree()
        container(t, "com.canva.affinity.thumbnail", bundle: "/Applications/Affinity.app/Contents/PlugIns/Thumbnail Extension.appex")
        t.file("Users/tester/Library/Preferences/com.canva.affinity.thumbnail.plist", bytes: 10)
        let items = try await scanner(t).scan(t.context()) { _ in }
        let item = try #require(items.first)
        #expect(items.count == 1)
        #expect(item.name == "Thumbnail Extension")
        #expect(item.group == .appLeftovers)
        #expect(Set(item.children.compactMap(\.detail)) == ["container", "preferences"])
        #expect(item.leaves.allSatisfy { $0.isRecommended && AppItemID.owner(of: $0.id) == "com.canva.affinity.thumbnail" })
        #expect(item.leaves.allSatisfy { if case .moveToTrash = $0.removal { true } else { false } })
    }

    /// Formato real do containermanagerd: `SandboxProfileDataValidationInfo/Parameters/application_bundle`.
    @Test func readsParametersKeyOfRealMetadata() throws {
        let t = FixtureTree()
        let dir = t.dir("Users/tester/Library/Containers/com.canva.affinity.thumbnail")
        let meta: [String: Any] = ["MCMMetadataInfo": ["SandboxProfileDataValidationInfo": ["Parameters": [
            "application_bundle": "/Applications/Affinity.app/Contents/PlugIns/ThumbnailShareExtension (Global).appex"]]]]
        try PropertyListSerialization.data(fromPropertyList: meta, format: .binary, options: 0)
            .write(to: dir.appendingPathComponent(".com.apple.containermanagerd.metadata.plist"))
        #expect(LeftoversScanner.owner(of: dir) == .path("/Applications/Affinity.app/Contents/PlugIns/ThumbnailShareExtension (Global).appex"))
    }

    @Test func containerWithoutAppPathNamedByBundleID() async throws {
        let t = FixtureTree()
        container(t, "com.example.Gone.Extension", bundle: "/Applications/Setapp/Gone.app/Contents/PlugIns/Ext.appex", legacy: true)
        let items = try await scanner(t).scan(t.context()) { _ in }
        #expect(items.map(\.name) == ["Ext"])
    }

    @Test func installedSiblingIsNotLeftover() async throws {
        let t = FixtureTree()
        let app = AppFixture.makeApp(t, "Applications/Code.app", bundleID: "com.example.code")
        container(t, "com.example.code", bundle: "/Applications/Moved/Code.app")          // instalado (bundle ID no inventário)
        container(t, "com.example.code.helper", bundle: app.path)                          // o app existe no caminho
        container(t, "com.example.registered", bundle: "/nowhere/R.app")                   // o sistema conhece o app
        let items = try await scanner(t, registered: ["com.example.registered"]).scan(t.context()) { _ in }
        #expect(items.isEmpty)
    }

    @Test func appleExcluded() async throws {
        let t = FixtureTree()
        container(t, "com.apple.Notes", bundle: "/nowhere/Notes.app")
        #expect(try await scanner(t).scan(t.context()) { _ in }.isEmpty)
    }

    /// Sem `application_bundle` nos metadados (extensões): é sobra se nenhum app instalado for "pai" do bundle ID.
    @Test func containerWithoutAppPathIsLeftoverUnlessParentInstalled() async throws {
        let t = FixtureTree()
        AppFixture.makeApp(t, "Applications/WhatsApp.app", bundleID: "net.whatsapp.WhatsApp")
        container(t, "com.getcleanshot.app-setapp.PinShareExtension", bundle: nil, emptyMeta: true)
        container(t, "net.whatsapp.WhatsApp.ServiceExtension", bundle: nil, emptyMeta: true)
        container(t, "com.example.nometa", bundle: nil)
        let items = try await scanner(t).scan(t.context()) { _ in }
        #expect(items.map(\.name) == ["com.getcleanshot.app-setapp.PinShareExtension"])
    }

    @Test func bundlesInsideInstalledAppsAndSameVendorAreNotLeftovers() async throws {
        let t = FixtureTree()
        let utm = AppFixture.makeApp(t, "Applications/UTM.app", bundleID: "com.utmapp.UTM")
        let xpc = t.dir("Applications/UTM.app/Contents/XPCServices/QEMUHelper.xpc/Contents")
        try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": "com.utmapp.QEMUHelper"], format: .xml, options: 0)
            .write(to: xpc.appendingPathComponent("Info.plist"))
        _ = utm
        AppFixture.makeApp(t, "Applications/Chrome.app", bundleID: "com.google.Chrome")
        container(t, "com.utmapp.QEMUHelper", bundle: nil, emptyMeta: true)
        container(t, "com.google.GeminiMacOS.FinderSync", bundle: nil, emptyMeta: true)
        container(t, "com.getcleanshot.app-setapp.QuickLookExtension", bundle: nil, emptyMeta: true)
        let items = try await scanner(t).scan(t.context()) { _ in }
        #expect(items.map(\.name) == ["com.getcleanshot.app-setapp.QuickLookExtension"])
    }

    /// O fantasma casa só pelo bundle ID: um nome genérico ("Google") não leva pastas compartilhadas do fornecedor.
    @Test func ghostMatchesByIDOnly() async throws {
        let t = FixtureTree()
        container(t, "com.example.ghost", bundle: "/Applications/Google.app")
        t.dir("Users/tester/Library/Application Support/Google/shared")
        t.file("Users/tester/Library/Preferences/com.example.ghost.plist", bytes: 10)
        let item = try #require(try await scanner(t).scan(t.context()) { _ in }.first)
        #expect(!item.leaves.contains { $0.url?.path.hasSuffix("Application Support/Google") == true })
        #expect(item.leaves.contains { $0.url?.lastPathComponent == "com.example.ghost.plist" })
    }

    @Test func symlinkedContainerIgnored() async throws {
        let t = FixtureTree()
        container(t, "com.example.real", bundle: "/nowhere/R.app")
        t.symlink("Users/tester/Library/Containers/com.example.link", to: t.url("Users/tester/Library/Containers/com.example.real"))
        let items = try await scanner(t).scan(t.context()) { _ in }
        #expect(items.count == 1)
    }
}
