import Foundation

/// Scanners de produção e as políticas de remoção derivadas deles.
public enum Registry {
    /// Um scanner por grupo: os especializados (adicionados pelas tasks de cada grupo)
    /// e, para os demais, as regras empacotadas em `rules/<grupo>.json`.
    public static func productionScanners(apps: any AppLookup = WorkspaceAppLookup()) -> [any GroupScanner] {
        let specialized: [any GroupScanner] = []
        let covered = Set(specialized.map(\.group))
        let ruleBased = GroupID.allCases
            .filter { !covered.contains($0) && RuleBasedScanner.hasBundledRules($0) }
            .compactMap { try? RuleBasedScanner.bundled($0, apps: apps) }
        return specialized + ruleBased
    }

    public static func policies(for scanners: [any GroupScanner], context: ScanContext) -> [GroupID: PathPolicy] {
        var result: [GroupID: PathPolicy] = [:]
        for scanner in scanners {
            guard let scoped = scanner as? any ScopedScanner else { continue }
            let scope = scoped.removalScope(context)
            result[scanner.group] = PathPolicy(allowedRoots: scope.roots, allowedItems: scope.items)
        }
        return result
    }
}
