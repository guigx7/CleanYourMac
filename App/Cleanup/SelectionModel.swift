import Foundation
import Observation
import CleanYourMacCore

/// Seleção de itens do Gerenciador de Limpeza. Só folhas removíveis são guardadas;
/// o estado de pais e grupos é derivado delas. Começa vazia (results-screen §2.3).
@MainActor @Observable
final class SelectionModel {
    enum State: Equatable { case off, mixed, on }
    /// Ações do menu Selecionar.
    enum Preset: CaseIterable { case none, smart, all }
    /// Rótulo do menu Selecionar.
    enum PresetState: Equatable { case none, all, smart, manual }
    /// Confirmações exigidas ao marcar certos itens (results-screen §4).
    enum Alert: Equatable { case iosLatestBackup, localModels }

    private(set) var selectedIDs: Set<String> = []
    private(set) var pendingAlert: Alert?
    private var pendingLeaves: [JunkItem] = []
    private var leavesByID: [String: JunkItem] = [:]
    private var itemsByGroup: [GroupID: [JunkItem]] = [:]

    func load(_ report: ScanReport) {
        selectedIDs = []
        pendingAlert = nil
        pendingLeaves = []
        leavesByID = [:]
        itemsByGroup = [:]
        for (group, result) in report.groups {
            itemsByGroup[group] = result.items
            for leaf in result.items.flatMap(\.leaves) where leaf.removal != nil {
                leavesByID[leaf.id] = leaf
            }
        }
    }

    func clear() {
        selectedIDs = []
        pendingAlert = nil
        pendingLeaves = []
    }

    /// Marca exatamente estas folhas (ex.: os itens que falharam numa limpeza).
    func replaceSelection(with items: [JunkItem]) {
        clear()
        set(items.flatMap(removableLeaves), on: true)
    }

    var hasChanges: Bool { !selectedIDs.isEmpty }

    // MARK: Estado

    func state(of item: JunkItem) -> State {
        state(of: removableLeaves(item))
    }

    func state(of group: GroupID) -> State {
        state(of: leaves(in: group))
    }

    func presetState(in group: GroupID) -> PresetState {
        let all = leaves(in: group)
        let selected = Set(all.map(\.id)).intersection(selectedIDs)
        let recommended = Set(all.filter(\.isRecommended).map(\.id))
        if selected.isEmpty { return .none }
        if !recommended.isEmpty, selected == recommended { return .smart }
        if selected.count == all.count { return .all }
        return .manual
    }

    func canSmartSelect(_ group: GroupID) -> Bool {
        leaves(in: group).contains(where: \.isRecommended)
    }

    // MARK: Ações

    func toggle(_ item: JunkItem) {
        let leaves = removableLeaves(item)
        if state(of: item) == .on { set(leaves, on: false) } else { request(leaves) }
    }

    func toggle(group: GroupID) {
        let leaves = leaves(in: group)
        if state(of: group) == .on { set(leaves, on: false) } else { request(leaves) }
    }

    func select(_ preset: Preset, in group: GroupID) {
        let leaves = leaves(in: group)
        switch preset {
        case .none:
            set(leaves, on: false)
        case .smart:
            set(leaves.filter { !$0.isRecommended }, on: false)
            request(leaves.filter(\.isRecommended))
        case .all:
            request(leaves)
        }
    }

    func confirmPending() {
        set(pendingLeaves, on: true)
        pendingLeaves = []
        pendingAlert = nil
    }

    func cancelPending() {
        pendingLeaves = []
        pendingAlert = nil
    }

    // MARK: Totais

    var selectedItems: [JunkItem] {
        selectedIDs.compactMap { leavesByID[$0] }.sorted { $0.id < $1.id }
    }

    var selectedCount: Int { selectedIDs.count }

    /// Soma sem contar o mesmo caminho duas vezes.
    var selectedBytes: Int64 { bytes(of: selectedItems) }

    func selectedBytes(in group: GroupID) -> Int64 {
        bytes(of: selectedItems.filter { $0.group == group })
    }

    // MARK: Privado

    private func request(_ leaves: [JunkItem]) {
        let newOnes = leaves.filter { !selectedIDs.contains($0.id) }
        if let alert = Self.alert(for: newOnes) {
            pendingLeaves = leaves
            pendingAlert = alert
        } else {
            set(leaves, on: true)
        }
    }

    private static func alert(for leaves: [JunkItem]) -> Alert? {
        if leaves.contains(where: { $0.badge == .latest }) { return .iosLatestBackup }
        if leaves.contains(where: { $0.group == .localModels }) { return .localModels }
        return nil
    }

    private func leaves(in group: GroupID) -> [JunkItem] {
        (itemsByGroup[group] ?? []).flatMap(removableLeaves)
    }

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

    private func bytes(of items: [JunkItem]) -> Int64 {
        var seen = Set<String>()
        return items.reduce(0) { total, item in
            let key = item.url?.path ?? item.id
            return seen.insert(key).inserted ? total + item.totalSize : total
        }
    }
}
