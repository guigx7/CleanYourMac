import Foundation
import Testing
@testable import CleanYourMacCore

private func container(_ t: FixtureTree, _ id: String, bundle: String?, legacy: Bool = false, bytes: Int = 4096) {
    t.file("Users/tester/Library/Containers/\(id)/Data/Library/Caches/x", bytes: bytes)
    guard let bundle else { return }
    let meta: [String: Any] = ["MCMMetadataIdentifier": id, "MCMMetadataInfo": ["SandboxProfileDataValidationInfo": [
        "SandboxProfileDataValidationParametersKey": ["application_bundle": bundle]]]]
    let name = legacy ? "Container.plist" : ".com.apple.containermanagerd.metadata.plist"
    try! PropertyListSerialization.data(fromPropertyList: meta, format: .binary, options: 0)
        .write(to: t.url("Users/tester/Library/Containers/\(id)/\(name)"))
}

private func scanner(_ t: FixtureTree, registered: Set<String> = []) -> LeftoversScanner {
    LeftoversScanner(catalog: AppCatalog(query: FakeAppQuery(), usage: FakeUsage()),
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

    @Test func appleAndUnreadableExcluded() async throws {
        let t = FixtureTree()
        container(t, "com.apple.Notes", bundle: "/nowhere/Notes.app")
        container(t, "com.example.nometa", bundle: nil)
        #expect(try await scanner(t).scan(t.context()) { _ in }.isEmpty)
    }

    @Test func symlinkedContainerIgnored() async throws {
        let t = FixtureTree()
        container(t, "com.example.real", bundle: "/nowhere/R.app")
        t.symlink("Users/tester/Library/Containers/com.example.link", to: t.url("Users/tester/Library/Containers/com.example.real"))
        let items = try await scanner(t).scan(t.context()) { _ in }
        #expect(items.count == 1)
    }
}
