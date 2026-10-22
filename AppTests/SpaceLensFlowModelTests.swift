import Testing
import Foundation
import CleanYourMacCore
@testable import CleanYourMac

/// Análise falsa: varre uma pasta de fixture de verdade (o SpaceNode só nasce do scanner).
struct FixtureSpaceScan: SpaceLensScanning {
    var root: URL
    var delay: Duration = .zero
    func run(_ target: SpaceLensTarget) -> AsyncThrowingStream<SpaceLensScanEvent, Error> {
        let root = root, delay = delay
        return AsyncThrowingStream { cont in
            let task = Task {
                do {
                    cont.yield(.progress(10))
                    if delay > .zero { try await Task.sleep(for: delay) }
                    let node = try SpaceScanner().scan(root)
                    cont.yield(.finished(SpaceLensReport(root: node, isDisk: target == .disk, volumeName: "Macintosh HD",
                                                         used: 225_000_000_000, capacity: 494_000_000_000,
                                                         purgeable: target == .disk ? 3_900_000_000 : nil)))
                    cont.finish()
                } catch { cont.finish(throwing: error) }
            }
            cont.onTermination = { _ in task.cancel() }
        }
    }
}

final class RecordingSpaceRemover: SpaceRemoving, @unchecked Sendable {
    private(set) var removed: [[String]] = []
    var failing: Set<String> = []
    func remove(_ nodes: [SpaceNode]) async -> [String: Result<Void, CleanFailure>] {
        removed.append(nodes.map(\.path))
        return Dictionary(uniqueKeysWithValues: nodes.map { ($0.path, failing.contains($0.path) ? .failure(CleanFailure(reason: "denied")) : .success(())) })
    }
}

/// Pasta temporária com arquivos de tamanho conhecido (apagada no fim do processo de teste pelo sistema).
final class TempTree: @unchecked Sendable {
    let root: URL
    init() {
        let raw = FileManager.default.temporaryDirectory.appendingPathComponent("cym-lens-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: raw, withIntermediateDirectories: true)
        root = URL(fileURLWithPath: PathPolicy.realPath(raw.path))
    }
    deinit { try? FileManager.default.removeItem(at: root) }
    func url(_ rel: String) -> URL { root.appendingPathComponent(rel) }
    func file(_ rel: String, bytes: Int) {
        let u = url(rel)
        try! FileManager.default.createDirectory(at: u.deletingLastPathComponent(), withIntermediateDirectories: true)
        try! Data(count: bytes).write(to: u)
    }
}

@MainActor
struct LensSetup {
    let t = TempTree()
    let remover = RecordingSpaceRemover()
    let model: SpaceLensFlowModel

    init(delay: Duration = .zero, protected: Set<String> = []) {
        t.file("big/a.bin", bytes: 400_000)
        t.file("big/inner/b.bin", bytes: 200_000)
        t.file("small/c.bin", bytes: 10_000)
        t.file("d.bin", bytes: 50_000)
        let tree = t
        let protectedPaths = protected.map { tree.url($0).path }
        model = SpaceLensFlowModel(scan: FixtureSpaceScan(root: tree.root, delay: delay), remover: remover,
                                   isProtected: { protectedPaths.contains($0.path) })
    }

    func scanned() async -> SpaceLensFlowModel {
        model.start()
        while model.phase == .scanning { await Task.yield() }
        return model
    }
}

@MainActor
@Suite struct SpaceLensFlowModelTests {
    @Test func scanShowsRootAndNavigation() async {
        let s = LensSetup()
        let m = await s.scanned()
        #expect(m.phase == .results)
        #expect(m.current?.children.first?.name == "big")
        let big = m.current!.child("big")!
        m.open(big)
        #expect(m.current === big)
        #expect(m.canGoBack && !m.canGoForward)
        m.goBack()
        #expect(m.current === m.report?.root)
        #expect(m.canGoForward)
        m.goForward()
        #expect(m.current === big)
        m.open(big.child("inner")!)
        m.jump(to: m.report!.root)
        #expect(m.current === m.report?.root && m.canGoBack)
        // Arquivo não abre.
        m.open(m.current!.child("d.bin")!)
        #expect(m.current === m.report?.root)
    }

    @Test func stopAndBackReturnToIntro() async {
        let s = LensSetup(delay: .seconds(5))
        s.model.start()
        s.model.stop()
        #expect(s.model.phase == .intro)
        let m = await LensSetup().scanned()
        m.back()
        #expect(m.phase == .intro && m.report == nil)
    }

    @Test func selectingFolderCoversDescendantsWithoutDoubleCounting() async {
        let s = LensSetup()
        let m = await s.scanned()
        let big = m.current!.child("big")!, a = big.child("a.bin")!, d = m.current!.child("d.bin")!
        m.toggle(a)
        #expect(m.isSelected(a))
        m.toggle(big)
        // A pasta absorve o filho marcado antes.
        #expect(m.selection.map(\.path) == [big.path])
        #expect(m.isSelected(a) && !m.canToggle(a))
        m.toggle(d)
        #expect(m.selectionSize == big.size + d.size)
        m.toggle(big)
        #expect(m.selection.map(\.path) == [d.path])
    }

    @Test func protectedItemsCannotBeSelected() async {
        let s = LensSetup(protected: ["small"])
        let m = await s.scanned()
        let small = m.current!.child("small")!
        #expect(!m.canToggle(small))
        m.toggle(small)
        #expect(m.selection.isEmpty)
    }

    @Test func reviewThenRemoveUpdatesTree() async {
        let s = LensSetup()
        let m = await s.scanned()
        let root = m.report!.root
        let before = root.size
        let d = root.child("d.bin")!, big = root.child("big")!
        let bigSize = big.size
        let paths = [big.path, d.path].sorted()
        m.toggle(d)
        m.toggle(big)
        m.review()
        #expect(m.phase == .reviewing)
        m.cancelReview()
        #expect(m.phase == .results && m.selection.count == 2)
        m.review()
        m.confirmRemoval()
        while m.phase == .removing { await Task.yield() }
        guard case .done(let outcome) = m.phase else { Issue.record("sem conclusão"); return }
        #expect(outcome.removed == 2 && outcome.failed.isEmpty && outcome.freed == bigSize + d.size)
        #expect(s.remover.removed.first?.sorted() == paths)
        // A árvore já não tem os itens removidos e o total caiu.
        #expect(root.child("d.bin") == nil && root.child("big") == nil)
        #expect(root.size == before - bigSize - d.size)
    }

    @Test func failedRemovalKeepsItem() async {
        let s = LensSetup()
        let m = await s.scanned()
        let d = m.report!.root.child("d.bin")!
        s.remover.failing = [d.path]
        m.toggle(d)
        m.review()
        m.confirmRemoval()
        while m.phase == .removing { await Task.yield() }
        guard case .done(let outcome) = m.phase else { return }
        #expect(outcome.failed[d.name] == "denied")
        #expect(m.report!.root.child("d.bin") != nil)
    }

    /// Mover para o Lixo algo do iCloud Drive também apaga da nuvem: a revisão avisa.
    @Test func cloudItemsNeedWarning() async {
        let s = LensSetup()
        let m = await s.scanned()
        let d = m.report!.root.child("d.bin")!
        m.toggle(d)
        #expect(!m.selectionTouchesCloud)
        #expect(SpaceLensFlowModel.isCloudPath(NSHomeDirectory() + "/Library/Mobile Documents/com~apple~CloudDocs/x.pdf"))
    }
}
