import Foundation
import Observation
import CleanYourMacCore

/// Seleção do Gerenciador de Aplicativos, por folha removível.
@MainActor @Observable
final class AppsSelection {
    typealias State = SelectionModel.State

    private(set) var selectedIDs: Set<String> = []
    private var leavesByID: [String: JunkItem] = [:]

    /// Folhas que podem ser marcadas (sem trava e com remoção).
    static func selectable(_ item: JunkItem) -> [JunkItem] {
        item.leaves.filter { $0.removal != nil && $0.badge != .locked && $0.badge != .mounted }
    }

    var selectedLeaves: [JunkItem] { selectedIDs.compactMap { leavesByID[$0] }.sorted { $0.id < $1.id } }
    var selectedBytes: Int64 { selectedLeaves.reduce(0) { $0 + $1.size } }
    var isEmpty: Bool { selectedIDs.isEmpty }

    func clear() { selectedIDs.removeAll() }

    func state(of item: JunkItem) -> State {
        let leaves = Self.selectable(item)
        let on = leaves.filter { selectedIDs.contains($0.id) }.count
        return on == 0 ? .off : on == leaves.count ? .on : .mixed
    }

    /// App inteiro: marca os recomendados (ou desmarca tudo). Tipo ou folha: marca/desmarca todos.
    func toggle(_ item: JunkItem) {
        let leaves = Self.selectable(item)
        let isApp = item.children.contains { !$0.children.isEmpty }
        if isApp {
            if state(of: item) != .off { set(leaves, on: false) } else { set(leaves.filter(\.isRecommended), on: true) }
        } else {
            set(leaves, on: state(of: item) != .on)
        }
    }

    func set(_ leaves: [JunkItem], on: Bool) {
        for l in leaves {
            leavesByID[l.id] = l
            if on { selectedIDs.insert(l.id) } else { selectedIDs.remove(l.id) }
        }
    }

    /// Ids dos apps (AppRecord.id) com alguma folha marcada.
    var selectedAppIDs: Set<String> { Set(selectedIDs.compactMap(AppItemID.appID(of:))) }
}
