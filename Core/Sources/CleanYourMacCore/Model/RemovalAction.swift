import Foundation

/// Como um item é removido pelo CleanEngine.
public enum RemovalAction: Hashable, Sendable {
    /// Apagar definitivamente.
    case delete(URL)
    case moveToTrash(URL)
    /// Esvaziar a pasta, mantendo a pasta em si.
    case deleteContents(of: URL)
    case thinBinary(executable: URL, keepArch: String, bundle: URL)
    case removeLocalizations(bundle: URL, lprojs: [URL])
    /// Plist do launchd quebrado: `launchctl unload`, apagar o helper homônimo e o plist.
    case removeLaunchdItem(plist: URL, helper: URL?)
    /// Entrada da lista de Itens de Início da sessão (não apaga arquivos).
    case removeSessionLoginItem(name: String?, url: URL?)
    /// Plist de preferências defeituoso: `defaults delete`, apagar e reiniciar o cfprefsd no fim.
    case removePreference(URL)
    case deleteDocumentVersions(volume: URL, fileID: String)
    /// Versão defasada: antes de apagar, confere se `activeLink` não passou a apontar para ela.
    case deleteStaleVersion(URL, activeLink: URL)
    /// Pasta temporária de uma ferramenta: pulada se o processo estiver rodando.
    case deleteUnlessRunning(URL, process: String)
    /// Vários arquivos de um mesmo item (ex.: shards de um modelo).
    case deleteFiles([URL])
    /// Manifesto do Ollama + blobs que ficarem sem referência (recalculado na hora).
    case removeOllamaModel(manifest: URL, store: URL)
}
