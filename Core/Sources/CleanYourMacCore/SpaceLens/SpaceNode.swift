import Foundation

/// Um nó da árvore da Lupa de Espaço. Montado pelo `SpaceScanner` e imutável depois (por isso `@unchecked Sendable`).
public final class SpaceNode: @unchecked Sendable, Identifiable {
    public let name: String
    public let isDirectory: Bool
    /// Tamanho alocado (`st_blocks × 512`), somando os descendentes.
    public internal(set) var size: Int64
    /// Quantos itens há abaixo (arquivos e pastas, sem contar o próprio nó).
    public internal(set) var items: Int = 0
    /// Por tamanho, maior primeiro.
    public internal(set) var children: [SpaceNode] = []
    /// A pasta (ou algo abaixo dela) não pôde ser lida.
    public internal(set) var isUnreadable = false
    public internal(set) weak var parent: SpaceNode?
    /// Identidade no disco (dispositivo + número do arquivo) vista na análise: a remoção confere que ainda é o mesmo item.
    public internal(set) var device: Int32 = 0
    public internal(set) var fileID: UInt64 = 0
    /// Caminho absoluto, só na raiz da análise.
    let rootPath: String?

    init(name: String, isDirectory: Bool, size: Int64, rootPath: String? = nil) {
        self.name = name
        self.isDirectory = isDirectory
        self.size = size
        self.rootPath = rootPath
    }

    public var id: ObjectIdentifier { ObjectIdentifier(self) }

    public var path: String {
        if let rootPath { return rootPath }
        guard let parent else { return name }
        let base = parent.path
        return base == "/" ? "/" + name : base + "/" + name
    }

    public var url: URL { URL(fileURLWithPath: path) }

    public func child(_ name: String) -> SpaceNode? { children.first { $0.name == name } }

    /// Algum nó desta subárvore não pôde ser lido.
    public var hasUnreadable: Bool { isUnreadable || children.contains { $0.isDirectory && $0.hasUnreadable } }

    /// Caminho de nós da raiz até este (inclusive).
    public var ancestry: [SpaceNode] {
        var out: [SpaceNode] = [self]
        var p = parent
        while let n = p { out.insert(n, at: 0); p = n.parent }
        return out
    }

    /// Tira o nó da árvore (depois de removido do disco) e desconta tamanho e itens dos ancestrais.
    public func detach() {
        guard let parent else { return }
        parent.children.removeAll { $0 === self }
        var p: SpaceNode? = parent
        while let n = p {
            n.size -= size
            n.items -= items + 1
            p = n.parent
        }
        self.parent = nil
    }

    func append(_ child: SpaceNode) {
        child.parent = self
        children.append(child)
    }

    /// Soma tamanhos e contagens de baixo para cima e ordena os filhos.
    func finalize() {
        guard isDirectory else { return }
        var size = self.size, items = 0
        for c in children {
            c.finalize()
            size += c.size
            items += 1 + c.items
        }
        self.size = size
        self.items = items
        children.sort { $0.size != $1.size ? $0.size > $1.size : $0.name < $1.name }
    }
}
