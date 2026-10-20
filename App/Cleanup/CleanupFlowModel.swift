import Foundation
import Observation
import CleanYourMacCore

/// Máquina de estados do módulo Limpeza: Intro → Análise → Resultados ⇄ Revisão → Limpeza → Concluído.
@MainActor @Observable
final class CleanupFlowModel {
    enum Phase: Equatable {
        case intro, scanning, results, review, cleaning, nothingFound
        case done(CleanReport)
    }

    private(set) var phase: Phase = .intro
    private(set) var currentPath = ""
    private(set) var currentGroup: GroupID?
    private(set) var bytesFound: Int64 = 0
    private(set) var report: ScanReport?
    private(set) var reviewCategory: CategoryID?
    let selection = SelectionModel()

    // Limpeza
    private(set) var cleaningItem: JunkItem?
    private(set) var freedBytes: Int64 = 0
    private(set) var bytesToClean: Int64 = 0
    private(set) var failures: [JunkItem: String] = [:]

    private let scanEngine: ScanEngine
    private let cleanEngine: CleanEngine
    private let context: ScanContext
    private let groups: Set<GroupID>
    private var task: Task<Void, Never>?
    private var bytesByGroup: [GroupID: Int64] = [:]

    init(scanEngine: ScanEngine, cleanEngine: CleanEngine, context: ScanContext, groups: Set<GroupID>) {
        self.scanEngine = scanEngine
        self.cleanEngine = cleanEngine
        self.context = context
        self.groups = groups
    }

    var cleaningFraction: Double {
        bytesToClean > 0 ? min(1, Double(freedBytes) / Double(bytesToClean)) : 0
    }

    func startScan() {
        task?.cancel()
        resetScan()
        phase = .scanning
        let stream = scanEngine.scan(groups, context: context)
        task = Task { [weak self] in
            do {
                for try await event in stream {
                    guard let self, !Task.isCancelled else { return }
                    self.handle(event)
                }
            } catch {
                // Cancelamento: stopScan já levou o fluxo de volta à Intro.
            }
        }
    }

    func stopScan() {
        task?.cancel()
        task = nil
        resetScan()
        phase = .intro
    }

    func restart() {
        stopScan()
        resetCleaning()
    }

    func openReview(category: CategoryID? = nil) {
        guard report != nil else { return }
        reviewCategory = category ?? CategoryID.allCases.first { (report?.totalSize(of: $0) ?? 0) > 0 }
        phase = .review
    }

    func closeReview() {
        phase = report?.isEmpty == false ? .results : .nothingFound
    }

    func cleanRecommended(in category: CategoryID) {
        let items = report?.recommendedItems().filter { $0.group.category == category } ?? []
        clean(items: items)
    }

    func clean(items: [JunkItem]) {
        let leaves = items.flatMap(\.leaves).filter { $0.removal != nil }
        guard !leaves.isEmpty else { return }
        task?.cancel()
        resetCleaning()
        bytesToClean = leaves.reduce(0) { $0 + $1.totalSize }
        phase = .cleaning
        let stream = cleanEngine.clean(leaves)
        task = Task { [weak self] in
            for await event in stream {
                guard let self else { return }
                switch event {
                case .started(let item):
                    self.cleaningItem = item
                case .finished(let item, .success(let bytes)):
                    _ = item
                    self.freedBytes += bytes
                case .finished(let item, .failure(let failure)):
                    self.failures[item] = failure.reason
                case .completed(let report):
                    self.cleaningItem = nil
                    self.phase = .done(report)
                }
            }
        }
    }

    // MARK: - Privado

    private func handle(_ event: ScanEvent) {
        switch event {
        case .progress(let p):
            currentGroup = p.group
            currentPath = p.currentPath
            bytesByGroup[p.group] = max(bytesByGroup[p.group] ?? 0, p.bytesFound)
            updateBytesFound()
        case .groupFinished(let result):
            bytesByGroup[result.group] = result.totalSize
            updateBytesFound()
        case .finished(let report):
            self.report = report
            selection.load(report)
            bytesFound = max(bytesFound, report.totalSize)
            currentPath = ""
            currentGroup = nil
            phase = report.isEmpty ? .nothingFound : .results
        }
    }

    private func updateBytesFound() {
        bytesFound = max(bytesFound, bytesByGroup.values.reduce(0, +))
    }

    private func resetScan() {
        report = nil
        bytesFound = 0
        bytesByGroup = [:]
        currentPath = ""
        currentGroup = nil
        reviewCategory = nil
    }

    private func resetCleaning() {
        cleaningItem = nil
        freedBytes = 0
        bytesToClean = 0
        failures = [:]
    }
}
