/// As categorias dos módulos: as quatro da Limpeza e a dos Aplicativos.
public enum CategoryID: String, CaseIterable, Codable, Sendable {
    case systemJunk, aiClutter, mailAttachments, trashBins
    case applications

    /// As categorias exibidas pelo módulo Limpeza.
    public static let cleanupCases: [CategoryID] = [.systemJunk, .aiClutter, .mailAttachments, .trashBins]
}
