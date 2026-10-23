import Foundation
import CleanYourMacCore

/// Filtros do Fundo do Baú (docs/re/specs/clutter/results-and-manager.md §3.2): todos, marcados, por tipo, tamanho e
/// data de acesso. Só aparecem os que têm itens.
enum LargeOldFilter: Hashable {
    case all, selected
    case kind(LargeOldFiles.Kind)
    case size(LargeOldFiles.SizeBucket)
    case age(LargeOldFiles.AccessAge)

    func matches(_ f: ClutterFile, selected: Set<String>, now: Date) -> Bool {
        switch self {
        case .all: true
        case .selected: selected.contains(f.url.path)
        case .kind(let k): LargeOldFiles.kind(f) == k
        case .size(let b): LargeOldFiles.sizeBucket(f.size) == b
        case .age(let a): LargeOldFiles.age(of: f.accessed, now: now) == a
        }
    }

    /// Soma por filtro (os sem itens ficam de fora).
    static func totals(_ items: [ClutterFile], selected: Set<String>, now: Date) -> [LargeOldFilter: Int64] {
        var out: [LargeOldFilter: Int64] = [.all: items.reduce(0) { $0 + $1.size }]
        out[.selected] = items.filter { selected.contains($0.url.path) }.reduce(0) { $0 + $1.size }
        for f in items {
            out[.kind(LargeOldFiles.kind(f)), default: 0] += f.size
            out[.size(LargeOldFiles.sizeBucket(f.size)), default: 0] += f.size
            out[.age(LargeOldFiles.age(of: f.accessed, now: now)), default: 0] += f.size
        }
        return out
    }

    var title: String {
        switch self {
        case .all: NSLocalizedString("clutter.filter.all", comment: "")
        case .selected: NSLocalizedString("clutter.filter.selected", comment: "")
        case .kind(let k): NSLocalizedString("clutter.kind.\(k.rawValue)", comment: "")
        case .size(let b): NSLocalizedString("clutter.size.\(b.rawValue)", comment: "")
        case .age(let a): NSLocalizedString("clutter.age.\(a.rawValue)", comment: "")
        }
    }
}

/// Filtro "Mostrar:" das Duplicatas.
enum DuplicateFilter: Hashable {
    case all, selected
    case kind(DuplicateFinder.Kind)

    static var menu: [DuplicateFilter] { [.all, .selected] + DuplicateFinder.Kind.allCases.map(DuplicateFilter.kind) }

    func matches(_ g: DuplicateGroup, selected: Set<String>) -> Bool {
        switch self {
        case .all: true
        case .selected: g.files.contains { selected.contains($0.url.path) }
        case .kind(let k): DuplicateFinder.kind(g.files[0]) == k
        }
    }

    var title: String {
        switch self {
        case .all: NSLocalizedString("clutter.filter.all", comment: "")
        case .selected: NSLocalizedString("clutter.filter.selected", comment: "")
        case .kind(let k): NSLocalizedString("clutter.dupKind.\(k.rawValue)", comment: "")
        }
    }
}

/// "Ordenar por:" do Gerenciador.
enum ClutterSort: String, CaseIterable, Hashable {
    case size, name, date

    var title: String { NSLocalizedString("clutter.sort.\(rawValue)", comment: "") }

    /// Tamanho e data: do maior/mais recente; nome: alfabética.
    func sorted<T>(_ items: [T], name: (T) -> String, size: (T) -> Int64, date: (T) -> Date?) -> [T] {
        items.sorted { a, b in
            switch self {
            case .size: size(a) != size(b) ? size(a) > size(b) : name(a).localizedStandardCompare(name(b)) == .orderedAscending
            case .name: name(a).localizedStandardCompare(name(b)) == .orderedAscending
            case .date: (date(a) ?? .distantPast) > (date(b) ?? .distantPast)
            }
        }
    }
}

enum ClutterSearch {
    static func matches(_ name: String, _ query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        return q.isEmpty || name.localizedCaseInsensitiveContains(q)
    }
}
