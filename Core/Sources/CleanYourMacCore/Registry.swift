import Foundation

/// Scanners de produção e as políticas de remoção derivadas deles.
public enum Registry {
    /// Um scanner por grupo: os especializados (adicionados pelas tasks de cada grupo)
    /// e, para os demais, as regras empacotadas em `rules/<grupo>.json`.
    public static func productionScanners(apps: any AppLookup = WorkspaceAppLookup()) -> [any GroupScanner] {
        let specialized: [any GroupScanner] = [
            CacheScanner.userCache(apps: apps),
            CacheScanner.systemCache(apps: apps),
            LogsScanner.userLogs(apps: apps),
            LogsScanner.systemLogs(apps: apps),
            AIToolsScanner(apps: apps),
            LocalModelsScanner(apps: apps),
            MailAttachmentsScanner(),
            TrashScanner(),
            MailTrashScanner(),
            BrokenLoginItemsScanner(),
            BrokenPreferencesScanner(),
            DeletedUsersScanner(),
            IOSBackupsScanner(),
            DocumentVersionsScanner(apps: apps),
            XcodeJunkScanner(),
            UniversalBinariesScanner(),
            LanguageFilesScanner(),
        ]
        let covered = Set(specialized.map(\.group))
        let ruleBased = GroupID.allCases
            .filter { !covered.contains($0) && RuleBasedScanner.hasBundledRules($0) }
            .compactMap { try? RuleBasedScanner.bundled($0, apps: apps) }
        return specialized + ruleBased
    }

    /// Análise do módulo Aplicativos (produção). `privilegedAvailable`: o ajudante está aprovado.
    public static func appsScan(fetcher: any HTTPFetcher = URLSessionFetcher(), privilegedAvailable: Bool = false,
                                updates: UpdateChecker? = nil) -> AppsScan {
        let catalog = AppCatalog()
        let finder = RelatedFilesFinder(privilegedAvailable: privilegedAvailable)
        return AppsScan(catalog: catalog, uninstaller: UninstallerScanner(catalog: catalog, finder: finder),
                        leftovers: LeftoversScanner(catalog: catalog, finder: finder), installers: InstallersScanner(),
                        updates: updates ?? UpdateChecker(sources: [AppStoreSource(), SparkleSource(), HomebrewSource()], fetcher: fetcher))
    }

    /// Onde a remoção do módulo Aplicativos pode tocar.
    public static func performanceScan() -> PerformanceScan { PerformanceScan() }

    public static func appsPolicies(context: ScanContext) -> [GroupID: PathPolicy] {
        let scanners: [any ScopedScanner] = [UninstallerScanner(), LeftoversScanner(), InstallersScanner()]
        var out: [GroupID: PathPolicy] = [:]
        for s in scanners {
            let scope = s.removalScope(context)
            out[s.group] = PathPolicy(allowedRoots: scope.roots, allowedItems: scope.items)
        }
        return out
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
