import Foundation

/// Quantos filhos de uma pasta aparecem um a um; o resto vira "Outros itens"
/// (regra nossa, que reproduz as telas do CleanMyMac: docs/re/specs/spacelens/ui-and-removal.md §"Outros itens").
public enum SpaceGrouping {
    public static let maxVisible = 12

    /// `sizes` em ordem decrescente (como os filhos de um `SpaceNode`).
    public static func split(_ sizes: [Int64], total: Int64) -> (visible: Int, others: Int64) {
        let count = sizes.count
        var visible: Int
        if count <= 3 {
            visible = count
        } else if sizes.filter({ $0 > 0 }).count <= 10 {
            // Até 10 itens com tamanho: todos eles; os vazios vão para "Outros".
            visible = sizes.filter { $0 > 0 }.count
        } else {
            // Itens com pelo menos 1/75 (≈ 1,33%) da pasta, no máximo 12.
            visible = min(maxVisible, sizes.prefix { $0 * 75 >= total }.count)
        }
        // "Outros itens" só com 2 ou mais itens.
        if count - visible == 1 { visible = count }
        return (visible, sizes.dropFirst(visible).reduce(0, +))
    }
}
