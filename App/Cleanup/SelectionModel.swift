import Foundation
import Observation
import CleanYourMacCore

/// Seleção de itens do Gerenciador de Limpeza. Só folhas removíveis são guardadas;
/// o estado de pais e grupos é derivado delas.
@MainActor @Observable
final class SelectionModel {
    enum State: Equatable { case off, mixed, on }
    enum Preset: CaseIterable { case none, recommended, all }

    private(set) var selectedIDs: Set<String> = []
    private var leavesByID: [String: JunkItem] = [:]
    private var itemsByGroup: [GroupID: [JunkItem]] = [:]

    func load(_ report: ScanReport) {
        selectedIDs = []
        leavesByID = [:]
        itemsByGroup = [:]
        for (group, result) in report.groups {
            itemsByGroup[group] = result.items
            for leaf in result.items.flatMap(\.leaves) where leaf.removal != nil {
                leavesByID[leaf.id] = leaf
            }
        }
    }

    /// Seleção inicial ao abrir o Gerenciador: os itens recomendados.
    func applyInitialSelection() {
        selectedIDs = Set(leavesByID.values.filter(\.isRecommended).map(\.id))
    }

    func state(of item: JunkItem) -> State {
        state(of: removableLeaves(item))
    }

    func state(of group: GroupID) -> State {
        state(of: (itemsByGroup[group] ?? []).flatMap(removableLeaves))
    }

    func toggle(_ item: JunkItem) {
        set(removableLeaves(item), on: state(of: item) != .on)
    }

    func toggle(group: GroupID) {
        set((itemsByGroup[group] ?? []).flatMap(removableLeaves), on: state(of: group) != .on)
    }

    func select(_ preset: Preset, in group: GroupID) {
        let leaves = (itemsByGroup[group] ?? []).flatMap(removableLeaves)
        set(leaves, on: false)
        switch preset {
        case .none: break
        case .recommended: set(leaves.filter(\.isRecommended), on: true)
        case .all: set(leaves, on: true)
        }
    }

    var selectedItems: [JunkItem] {
        selectedIDs.compactMap { leavesByID[$0] }.sorted { $0.id < $1.id }
    }

    var selectedBytes: Int64 { selectedItems.reduce(0) { $0 + $1.totalSize } }
    var selectedCount: Int { selectedIDs.count }

    func selectedBytes(in group: GroupID) -> Int64 {
        selectedItems.filter { $0.group == group }.reduce(0) { $0 + $1.totalSize }
    }

    // MARK: - Privado

    private func removableLeaves(_ item: JunkItem) -> [JunkItem] {
        item.leaves.filter { $0.removal != nil }
    }

    private func set(_ leaves: [JunkItem], on: Bool) {
        for leaf in leaves {
            if leavesByID[leaf.id] == nil { leavesByID[leaf.id] = leaf }
            if on { selectedIDs.insert(leaf.id) } else { selectedIDs.remove(leaf.id) }
        }
    }

    private func state(of leaves: [JunkItem]) -> State {
        guard !leaves.isEmpty else { return .off }
        let count = leaves.filter { selectedIDs.contains($0.id) }.count
        return count == 0 ? .off : (count == leaves.count ? .on : .mixed)
    }
}
