import Foundation

/// Filtros do Desinstalador (docs/re/specs/apps/inventory.md §Lojas, §Fornecedores, §Não Usados, §Plug-ins de Áudio).
public enum AppFilter: Hashable, Sendable {
    case all, unused, suspicious, selected
    case store(AppStore)
    case vendor(AppVendor)
    case audioPlugins

    /// Contagens; lojas, fornecedores e plug-ins com 0 ficam de fora (como no CleanMyMac).
    public static func counts(apps: [AppRecord], selected: Set<String>, now: Date) -> [AppFilter: Int] {
        let applications = apps.filter { $0.kind == .application }
        var out: [AppFilter: Int] = [.all: applications.count, .unused: applications.filter { $0.isUnused(now: now) }.count,
                                     .suspicious: 0, .selected: applications.filter { selected.contains($0.id) }.count]
        for a in applications {
            out[.store(a.store), default: 0] += 1
            out[.vendor(a.vendor), default: 0] += 1
        }
        let plugins = apps.count - applications.count
        if plugins > 0 { out[.audioPlugins] = plugins }
        return out
    }

    public static func apply(_ filter: AppFilter, to apps: [AppRecord], selected: Set<String>, now: Date) -> [AppRecord] {
        let applications = apps.filter { $0.kind == .application }
        switch filter {
        case .all: return applications
        case .unused: return applications.filter { $0.isUnused(now: now) }
        case .suspicious: return []
        case .selected: return applications.filter { selected.contains($0.id) }
        case .store(let s): return applications.filter { $0.store == s }
        case .vendor(let v): return applications.filter { $0.vendor == v }
        case .audioPlugins: return apps.filter { $0.kind == .audioPlugin }
        }
    }

    /// Chave usada na baseline de paridade.
    public var parityKey: String {
        switch self {
        case .all: "all"
        case .unused: "unused"
        case .suspicious: "suspicious"
        case .selected: "selected"
        case .store(.other): "storeOther"
        case .store(let s): s.rawValue
        case .vendor(.other): "vendorOther"
        case .vendor(let v): v.rawValue
        case .audioPlugins: "audioPlugins"
        }
    }
}
