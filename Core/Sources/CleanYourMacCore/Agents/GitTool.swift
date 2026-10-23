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

    /// Caminhos que o `git status` dá como mudados, novos (pastas novas vêm com `/` no fim) ou apagados, relativos à
    /// worktree; nas renomeações, o novo e o antigo. `--no-optional-locks` impede que o status regrave o índice (senão
    /// qualquer consulta faria a worktree parecer "em uso"). `nil` quando o git falha ou a saída sai do formato
    /// (o runner junta o stderr: um aviso no meio tornaria a lista incerta).
    public func changedPaths(in worktree: URL) -> [String]? {
        let result = runner.run(executable, ["--no-optional-locks", "-C", worktree.path, "status", "--porcelain=v1", "-z",
                                             "--untracked-files=normal"])
        guard result.status == 0 else { return nil }
        var records = result.output.split(separator: "\u{0}", omittingEmptySubsequences: false).map(String.init)
        // A saída termina em NUL: o último pedaço é vazio.
        if records.last == "" { records.removeLast() }
        var paths: [String] = []
        var i = 0
        while i < records.count {
            let r = Array(records[i])
            // "XY caminho": dois códigos de estado e um espaço.
            let codes = "MTADRCU?! "
            guard r.count > 3, codes.contains(r[0]), codes.contains(r[1]), r[2] == " " else { return nil }
            paths.append(String(r[3...]))
            if r[0] == "R" || r[0] == "C" {
                // Renomeação ou cópia: o caminho de origem vem no registro seguinte.
                i += 1
                guard i < records.count, !records[i].isEmpty else { return nil }
                paths.append(records[i])
            }
            i += 1
        }
        return paths
    }
}
