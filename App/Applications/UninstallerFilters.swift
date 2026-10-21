import SwiftUI
import CleanYourMacCore

/// Ordenação do Desinstalador (inventory.md §Ordenação): Nome, Tamanho e Última Abertura, crescente ou decrescente.
struct UninstallerSort: Equatable {
    enum Key: String, CaseIterable { case name, size, lastOpened }
    var key: Key = .name
    var ascending = true

    mutating func choose(_ k: Key) {
        if key == k { ascending.toggle() } else { key = k; ascending = k == .name }
    }

    /// `sizes`: tamanho da linha por AppRecord.id. Sem data de abertura vai para o fim nas duas direções; desempate pelo nome.
    func sort(_ apps: [AppRecord], sizes: [String: Int64]) -> [AppRecord] {
        apps.sorted { a, b in
            let byName = a.name.localizedStandardCompare(b.name) == .orderedAscending
            switch key {
            case .name:
                return ascending ? byName : !byName
            case .size:
                let sa = sizes[a.id] ?? a.bundleSize, sb = sizes[b.id] ?? b.bundleSize
                if sa == sb { return byName }
                return ascending ? sa < sb : sa > sb
            case .lastOpened:
                switch (a.lastOpened, b.lastOpened) {
                case (nil, nil): return byName
                case (nil, _): return false
                case (_, nil): return true
                case (let da?, let db?):
                    if da == db { return byName }
                    return ascending ? da < db : da > db
                }
            }
        }
    }

    static func search(_ apps: [AppRecord], _ text: String) -> [AppRecord] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        return apps.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var title: LocalizedStringKey { LocalizedStringKey.dynamic("apps.sort.\(key.rawValue)") }
}

extension AppFilter {
    var title: LocalizedStringKey {
        switch self {
        case .all: "apps.filter.all"
        case .unused: "apps.filter.unused"
        case .suspicious: "apps.filter.suspicious"
        case .selected: "apps.filter.selected"
        case .store(let s): LocalizedStringKey.dynamic("apps.store.\(s.rawValue)")
        case .vendor(let v): LocalizedStringKey.dynamic("apps.vendor.\(v.rawValue)")
        case .audioPlugins: "apps.filter.audioPlugins"
        }
    }
}
