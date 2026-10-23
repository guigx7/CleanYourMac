import Foundation

/// Localiza e usa o git das Command Line Tools / Xcode. Nunca chama `/usr/bin/git`,
/// que abre o instalador das ferramentas quando elas não existem.
public struct GitTool: Sendable {
    public let executable: String
    let runner: any CommandRunner

    static let commandLineToolsGit = "/Library/Developer/CommandLineTools/usr/bin/git"
    static let batchSize = 200

    public static func locate(runner: any CommandRunner, fileExists: (String) -> Bool) -> GitTool? {
        if fileExists(commandLineToolsGit) {
            return GitTool(executable: commandLineToolsGit, runner: runner)
        }
        let result = runner.run("/usr/bin/xcode-select", ["-p"])
        guard result.status == 0 else { return nil }
        let dev = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dev.isEmpty else { return nil }
        let git = dev + "/usr/bin/git"
        return fileExists(git) ? GitTool(executable: git, runner: runner) : nil
    }

    /// Dos caminhos relativos dados, os que o git ignora (`check-ignore`), em lotes de 200. Os caminhos precisam existir:
    /// padrões como `dist/` só casam com diretórios presentes no disco.
    public func ignored(_ relPaths: [String], in worktree: URL) -> Set<String> {
        var found = Set<String>()
        var start = 0
        while start < relPaths.count {
            let batch = Array(relPaths[start..<min(start + Self.batchSize, relPaths.count)])
            start += Self.batchSize
            let batchSet = Set(batch)
            // `-z` só vale com `--stdin` (sem ele o git sai com "fatal"), e o runner não tem entrada padrão.
            // `core.quotePath=false` mantém acentos como estão; nomes que o git ainda põe entre aspas
            // (com quebra de linha, aspas ou controle) não casam com o lote e ficam como não ignorados.
            let result = runner.run(executable, ["-C", worktree.path, "-c", "core.quotePath=false", "check-ignore", "--"] + batch)
            guard result.status == 0 else { continue }
            for path in result.output.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
            where batchSet.contains(path) {
                found.insert(path)
            }
        }
        return found
    }

    /// Verdadeiro quando há arquivo versionado sob o caminho. Falha fechado: se o git não conseguir
    /// responder (safe.directory, repositório corrompido, lock), devolve `true` para não liberar remoção.
    /// O pathspec `:(icase,literal)` não diferencia caixa (o APFS também não; `build` acha `Build/` versionada)
    /// e não interpreta `*`, `?` ou `[` no nome.
    public func hasTracked(_ relPath: String, in worktree: URL) -> Bool {
        let result = runner.run(executable, ["-C", worktree.path, "ls-files", "--", ":(icase,literal)" + relPath])
        guard result.status == 0 else { return true }
        return !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
