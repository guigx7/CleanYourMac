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

    /// Dos caminhos relativos dados, os que o git ignora (`check-ignore`), em lotes de 200.
    public func ignored(_ relPaths: [String], in worktree: URL) -> Set<String> {
        var found = Set<String>()
        var start = 0
        while start < relPaths.count {
            let batch = Array(relPaths[start..<min(start + Self.batchSize, relPaths.count)])
            start += Self.batchSize
            let batchSet = Set(batch)
            // `-z`: saída separada por NUL, sem aspas nem escapes em nomes com acento ou caracteres especiais.
            let result = runner.run(executable, ["-C", worktree.path, "check-ignore", "-z", "--"] + batch)
            guard result.status == 0 else { continue }
            for path in result.output.split(separator: "\0", omittingEmptySubsequences: true).map(String.init)
            where batchSet.contains(path) {
                found.insert(path)
            }
        }
        return found
    }

    /// Verdadeiro quando há arquivo versionado sob o caminho. Falha fechado: se o git não conseguir
    /// responder (safe.directory, repositório corrompido, lock), devolve `true` para não liberar remoção.
    public func hasTracked(_ relPath: String, in worktree: URL) -> Bool {
        let result = runner.run(executable, ["-C", worktree.path, "ls-files", "--", relPath])
        guard result.status == 0 else { return true }
        return !result.output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}
