#if DEBUG
import Foundation
import CleanYourMacCore

/// Dados fictícios para revisar a interface (`CYM_DEMO=1`). Nada aponta para arquivos reais.
enum DemoData {
    struct Scanner: GroupScanner {
        let group: GroupID
        let items: [JunkItem]

        func scan(_ context: ScanContext, report: @Sendable (ScanProgress) -> Void) async throws -> [JunkItem] {
            var found: Int64 = 0
            for item in items {
                try await Task.sleep(for: .milliseconds(400))
                found += item.totalSize
                report(ScanProgress(group: group, currentPath: "/Users/demo/Library/\(item.name)", bytesFound: found))
            }
            return items
        }
    }

    private static func item(_ g: GroupID, _ name: String, _ mb: Double, rec: Bool = true, symbol: String = "folder",
                             children: [JunkItem] = []) -> JunkItem {
        let url = URL(fileURLWithPath: "/nonexistent/cym-demo/\(g.rawValue)/\(name)")
        return JunkItem(group: g, name: name, url: url, size: Int64(mb * 1_000_000), isRecommended: rec,
                        icon: .symbol(symbol), removal: children.isEmpty ? .delete(url) : nil, children: children)
    }

    static var scanners: [any GroupScanner] {
        [
            Scanner(group: .userCache, items: [item(.userCache, "Google", 1600), item(.userCache, "Homebrew", 592),
                                               item(.userCache, "pnpm", 352), item(.userCache, "node-gyp", 67.6)]),
            Scanner(group: .systemCache, items: [item(.systemCache, "com.apple.helpd", 37.6)]),
            Scanner(group: .userLogs, items: [item(.userLogs, "DiagnosticReports", 16.1)]),
            Scanner(group: .universalBinaries, items: [item(.universalBinaries, "Demo.app", 32, rec: false, symbol: "app")]),
            Scanner(group: .aiAgentsJunk, items: [
                item(.aiAgentsJunk, "Claude Code", 0, rec: false, symbol: "terminal", children: [
                    item(.aiAgentsJunk, "2.1.302", 280, rec: false), item(.aiAgentsJunk, "Caches", 280, rec: false)]),
                item(.aiAgentsJunk, "Codex", 37.7, rec: false, symbol: "chevron.left.forwardslash.chevron.right"),
            ]),
            Scanner(group: .trash, items: [item(.trash, "Old project.zip", 120)]),
        ]
    }
}
#endif
