import Foundation
import CleanYourMacCore

/// Regras de ordem, visibilidade, ordenação e busca do Gerenciador (results-screen §2).
enum ReviewLogic {
    enum SortKey: CaseIterable { case size, name }

    struct SortState: Equatable {
        var key: SortKey = .size
        var ascending = false

        /// Escolher o critério atual inverte a direção; um critério novo começa na direção padrão.
        mutating func choose(_ new: SortKey) {
            if new == key {
                ascending.toggle()
            } else {
                key = new
                ascending = new == .name
            }
        }
    }

    /// Desempate entre grupos de mesmo tamanho (observado no CleanMyMac); o resto segue `GroupID`.
    private static let tieOrder: [GroupID] = [.brokenLoginItems, .documentVersions, .deletedUsers, .brokenPreferences, .iosBackups]

    private static func tieRank(_ g: GroupID) -> Int {
        if let i = tieOrder.firstIndex(of: g) { return 1000 + i }
        return GroupID.allCases.firstIndex(of: g) ?? 0
    }

    /// Grupos da categoria que foram analisados, do maior para o menor.
    /// Grupos de 0 KB aparecem; Detritos do Xcode some quando não tem itens.
    static func groups(in category: CategoryID, report: ScanReport?) -> [GroupID] {
        guard let report else { return [] }
        var present: [(group: GroupID, size: Int64)] = []
        for g in GroupID.allCases where g.category == category {
            guard let result = report.groups[g] else { continue }
            if g == .xcodeJunk && result.items.isEmpty { continue }
            present.append((g, result.totalSize))
        }
        present.sort { a, b in
            if a.size != b.size { return a.size > b.size }
            return tieRank(a.group) < tieRank(b.group)
        }
        return present.map(\.group)
    }

    /// Categoria sem nenhum item em nenhum grupo.
    static func isEmpty(_ category: CategoryID, report: ScanReport?) -> Bool {
        guard let report else { return true }
        return report.groups.values.filter { $0.group.category == category }.allSatisfy { $0.items.isEmpty }
    }

    static func sorted(_ items: [JunkItem], by key: SortKey, ascending: Bool) -> [JunkItem] {
        let up: [JunkItem] = switch key {
        case .size: items.sorted { $0.totalSize < $1.totalSize }
        case .name: items.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
        return ascending ? up : up.reversed()
    }

    /// Itens cujo nome (ou o de algum filho) contém o texto, sem diferenciar caixa nem acentos.
    static func filter(_ items: [JunkItem], query: String) -> [JunkItem] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return items }
        func matches(_ item: JunkItem) -> Bool {
            item.name.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil || item.children.contains(where: matches)
        }
        return items.filter(matches)
    }
}
