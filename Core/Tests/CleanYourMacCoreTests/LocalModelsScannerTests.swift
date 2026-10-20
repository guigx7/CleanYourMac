import Testing
import Foundation
@testable import CleanYourMacCore

private func scan(_ ctx: ScanContext) async throws -> [JunkItem] {
    try await LocalModelsScanner(apps: FakeApps()).scan(ctx) { _ in }
}

private let models = "Users/tester/.ollama/models"

/// Cria um blob e devolve o digest.
@discardableResult
private func blob(_ t: FixtureTree, _ name: String, bytes: Int) -> String {
    t.file("\(models)/blobs/sha256-\(name)", bytes: bytes)
    return "sha256:\(name)"
}

private func manifest(_ t: FixtureTree, _ path: String, config: String, layers: [(String, String)]) {
    let json: [String: Any] = [
        "schemaVersion": 2,
        "config": ["digest": config, "mediaType": "application/vnd.docker.container.image.v1+json"],
        "layers": layers.map { ["digest": $0.0, "mediaType": $0.1] },
    ]
    let u = t.url("\(models)/manifests/\(path)")
    t.dir((("\(models)/manifests/\(path)") as NSString).deletingLastPathComponent)
    try! JSONSerialization.data(withJSONObject: json).write(to: u)
}

private let modelType = "application/vnd.ollama.image.model"
private let paramsType = "application/vnd.ollama.image.params"

private func logical(_ u: URL) -> Int64 { Int64((try? u.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }

@Test func models_emptyWhenNoStores() async throws {
    let t = FixtureTree()
    #expect(try await scan(t.context()).isEmpty)
}

@Test func models_singleOllamaModel() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let c = blob(t, "c1", bytes: 100), w = blob(t, "w1", bytes: 5000), p = blob(t, "p1", bytes: 50)
    manifest(t, "registry.ollama.ai/library/m/latest", config: c, layers: [(w, modelType), (p, paramsType)])
    let items = try await scan(ctx)
    #expect(items.map(\.name) == ["m:latest"])
    let mf = t.url("\(models)/manifests/registry.ollama.ai/library/m/latest")
    #expect(items[0].size == 100 + 5000 + 50 + logical(mf))
    #expect(!items[0].isRecommended)
}

@Test func models_sharedBlobNotExclusive() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let w = blob(t, "w1", bytes: 5000)
    let c1 = blob(t, "c1", bytes: 100), c2 = blob(t, "c2", bytes: 200)
    manifest(t, "registry.ollama.ai/library/m/latest", config: c1, layers: [(w, modelType)])
    manifest(t, "registry.ollama.ai/library/m/q4", config: c2, layers: [(w, modelType)])
    let items = try await scan(ctx).sorted { $0.name < $1.name }
    #expect(items.map(\.name) == ["m:latest", "m:q4"])
    #expect(items.allSatisfy { $0.size < 5000 })
}

private func cleanModels(_ t: FixtureTree, _ ctx: ScanContext, _ items: [JunkItem]) async {
    let s = LocalModelsScanner(apps: FakeApps())
    let engine = CleanEngine(policies: Registry.policies(for: [s], context: ctx), privileged: FakePrivilegedRunner(),
                             dryRun: false, log: CleanupLog(directory: t.dir("logs")))
    for await _ in engine.clean(items) {}
}

@Test func models_removeOneKeepsSharedBlob() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let w = blob(t, "w1", bytes: 5000)
    let c1 = blob(t, "c1", bytes: 100), c2 = blob(t, "c2", bytes: 200)
    manifest(t, "registry.ollama.ai/library/m/latest", config: c1, layers: [(w, modelType)])
    manifest(t, "registry.ollama.ai/library/m/q4", config: c2, layers: [(w, modelType)])
    let q4 = try await scan(ctx).filter { $0.name == "m:q4" }
    await cleanModels(t, ctx, q4)
    #expect(!FileManager.default.fileExists(atPath: t.url("\(models)/manifests/registry.ollama.ai/library/m/q4").path))
    #expect(!FileManager.default.fileExists(atPath: t.url("\(models)/blobs/sha256-c2").path))
    #expect(FileManager.default.fileExists(atPath: t.url("\(models)/blobs/sha256-w1").path))
    #expect(FileManager.default.fileExists(atPath: t.url("\(models)/blobs/sha256-c1").path))
}

@Test func models_removeBothDeletesOrphan() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let w = blob(t, "w1", bytes: 5000)
    manifest(t, "registry.ollama.ai/library/m/latest", config: blob(t, "c1", bytes: 100), layers: [(w, modelType)])
    manifest(t, "registry.ollama.ai/library/m/q4", config: blob(t, "c2", bytes: 200), layers: [(w, modelType)])
    await cleanModels(t, ctx, try await scan(ctx))
    let left = try FileManager.default.contentsOfDirectory(atPath: t.url("\(models)/blobs").path)
    #expect(left.isEmpty)
}

@Test func models_manifestWithoutModelLayerCountsReferences() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let w = blob(t, "w1", bytes: 5000)
    manifest(t, "registry.ollama.ai/library/m/latest", config: blob(t, "c1", bytes: 100), layers: [(w, modelType)])
    manifest(t, "registry.ollama.ai/library/other/x", config: blob(t, "c9", bytes: 100), layers: [(w, paramsType)])
    let items = try await scan(ctx)
    #expect(items.map(\.name) == ["m:latest"])
    #expect(items[0].size < 5000)
}

@Test func models_invalidManifestBlocksOllama() async throws {
    let t = FixtureTree(); let ctx = t.context()
    manifest(t, "registry.ollama.ai/library/m/latest", config: blob(t, "c1", bytes: 100), layers: [(blob(t, "w1", bytes: 10), modelType)])
    t.file("\(models)/manifests/registry.ollama.ai/library/bad/latest", bytes: 30)
    #expect(try await scan(ctx).isEmpty)
}

@Test func models_hugeManifestSkipped() async throws {
    let t = FixtureTree(); let ctx = t.context()
    manifest(t, "registry.ollama.ai/library/m/latest", config: blob(t, "c1", bytes: 100), layers: [(blob(t, "w1", bytes: 10), modelType)])
    let big = t.url("\(models)/manifests/registry.ollama.ai/library/big/latest")
    var json = Data("{\"layers\":[],\"pad\":\"".utf8)
    json.append(Data(repeating: 0x61, count: 1_100_000))
    json.append(Data("\"}".utf8))
    t.dir("\(models)/manifests/registry.ollama.ai/library/big")
    try json.write(to: big)
    #expect(try await scan(ctx).map(\.name) == ["m:latest"])
}

@Test func models_missingWeightsBlob() async throws {
    let t = FixtureTree(); let ctx = t.context()
    manifest(t, "registry.ollama.ai/library/m/latest", config: blob(t, "c1", bytes: 100), layers: [("sha256:gone", modelType)])
    #expect(try await scan(ctx).isEmpty)
}

@Test func models_nonDefaultRegistryName() async throws {
    let t = FixtureTree(); let ctx = t.context()
    manifest(t, "hf.co/user/repo/Q4_K_M", config: blob(t, "c1", bytes: 100), layers: [(blob(t, "w1", bytes: 10), modelType)])
    #expect(try await scan(ctx).map(\.name) == ["hf.co/user/repo:Q4_K_M"])
}

private let lms = "Users/tester/.lmstudio/models"

@Test func models_lmStudioSingleModelFolder() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("\(lms)/pub/Model-GGUF/model-Q4.gguf", bytes: 100_000)
    t.file("\(lms)/pub/Model-GGUF/README.md", bytes: 1000)
    let items = try await scan(ctx)
    #expect(items.map(\.name) == ["model-Q4"])
    #expect(items[0].size == 101_000)
    #expect(items[0].removal == .delete(t.url("\(lms)/pub/Model-GGUF")))
}

@Test func models_lmStudioTwoQuantsInFolder() async throws {
    let t = FixtureTree(); let ctx = t.context()
    let q4 = t.file("\(lms)/pub/Model-GGUF/model-Q4.gguf", bytes: 1000)
    t.file("\(lms)/pub/Model-GGUF/model-Q8.gguf", bytes: 2000)
    t.file("\(lms)/pub/Model-GGUF/README.md", bytes: 10)
    let items = try await scan(ctx).sorted { $0.name < $1.name }
    #expect(items.map(\.name) == ["model-Q4", "model-Q8"])
    #expect(items[0].removal == .deleteFiles([q4]))
}

@Test func models_lmStudioShards() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("\(lms)/pub/X/x-00001-of-00002.gguf", bytes: 1000)
    t.file("\(lms)/pub/X/x-00002-of-00002.gguf", bytes: 2000)
    t.file("\(lms)/pub/X/x-1-of-two.gguf", bytes: 10)
    let items = try await scan(ctx).sorted { $0.name < $1.name }
    #expect(items.map(\.name) == ["x", "x-1-of-two"])
    #expect(items[0].size == 3000)
}

@Test func models_lmStudioMLX() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.dir("\(lms)/pub/M")
    try JSONSerialization.data(withJSONObject: ["model_type": "qwen"]).write(to: t.url("\(lms)/pub/M/config.json"))
    t.file("\(lms)/pub/M/a.safetensors", bytes: 1000)
    t.file("\(lms)/pub/M/b.safetensors", bytes: 2000)
    t.dir("\(lms)/pub/N")
    try JSONSerialization.data(withJSONObject: ["x": 1]).write(to: t.url("\(lms)/pub/N/config.json"))
    t.file("\(lms)/pub/N/a.safetensors", bytes: 1000)
    let items = try await scan(ctx)
    #expect(items.map(\.name) == ["M"])
    #expect(items[0].size >= 3000)
}

@Test func models_lmStudioInternalIgnored() async throws {
    let t = FixtureTree(); let ctx = t.context()
    t.file("\(lms)/.internal/pub/x.gguf", bytes: 1000)
    #expect(try await scan(ctx).isEmpty)
}
