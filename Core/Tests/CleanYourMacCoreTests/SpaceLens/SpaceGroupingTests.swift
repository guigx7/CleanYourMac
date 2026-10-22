import Foundation
import Testing
@testable import CleanYourMacCore

@Suite struct SpaceGroupingTests {
    /// Tamanhos em GB → bytes.
    func gb(_ v: Double) -> Int64 { Int64(v * 1e9) }

    /// Pasta pessoal desta máquina vista pelo CleanMyMac: 7 itens e "Outros itens" com o resto.
    @Test func homeShowsUntil95Percent() {
        let sizes: [(String, Double)] = [("Library", 69.9), ("Projetos", 65.4), (".colima", 14.6), (".npm", 10.1), (".claude", 8.6),
                                         ("Downloads", 2.6), (".cache", 2.44), ("Pictures", 2.42), (".local", 2.0), (".vscode", 1.9),
                                         (".codex", 1.7), ("Documents", 0.9), (".nvm", 0.24)]
        let children = sizes.map { (name: $0.0, size: gb($0.1)) }
        let total = gb(182.9)
        let split = SpaceGrouping.split(children.map(\.size), total: total)
        #expect(split.visible == 7)
    }

    /// Raiz do disco: 9 itens com tamanho e só itens vazios em "Outros itens".
    @Test func fewChildrenShowAllNonEmpty() {
        let sizes = [183, 19.9, 15.8, 8.2, 6.3, 3.8, 0.831, 0.0049, 0.0025, 0, 0, 0, 0].map { gb($0) }
        let split = SpaceGrouping.split(sizes, total: gb(242))
        #expect(split.visible == 9)
    }

    @Test func usersFolderShowsSmallItems() {
        // Users: guigx 183 GB, Shared 123 KB, .localized 0 KB — todos aparecem.
        let split = SpaceGrouping.split([gb(183), 123_000, 0], total: gb(183))
        #expect(split.visible == 3)
    }

    /// "Outros itens" só com 2 ou mais itens: um só aparece normal.
    @Test func singleLeftoverIsShown() {
        let sizes = (0..<12).map { gb(Double(20 - $0)) } + [gb(0.001)]
        let split = SpaceGrouping.split(sizes, total: sizes.reduce(0, +))
        #expect(split.visible == 13)
    }

    @Test func atMostTwelve() {
        let sizes = Array(repeating: gb(5), count: 20)
        #expect(SpaceGrouping.split(sizes, total: gb(100)).visible == 12)
    }

    @Test func emptyFolder() {
        #expect(SpaceGrouping.split([], total: 0).visible == 0)
    }
}
