import SwiftUI
import AppKit
import CleanYourMacCore

// Peças das listas dos Gerenciadores claros (Acúmulos, Agentes de IA): a tinta vem de quem usa.

/// Cabeçalho de uma seção: nome e frase de descrição.
struct ModuleSectionHeader<Trailing: View>: View {
    var title: LocalizedStringKey
    var description: LocalizedStringKey
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.semibold))
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            trailing
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }
}

/// Uma linha de arquivo: caixa, ícone, nome, pasta (ou `subtitle`), data e tamanho; lupa para mostrar no Finder.
struct ModuleFileRow: View {
    var url: URL
    var size: Int64
    var date: Date?
    var dateHelp: LocalizedStringKey
    var selected: Bool
    var tint: Color
    /// Texto da segunda linha; sem ele, a pasta do arquivo abreviada com `~`.
    var subtitle: String? = nil
    var onToggle: () -> Void
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 10) {
            TriStateCheckbox(state: selected ? .on : .off, tint: tint, label: url.lastPathComponent, action: onToggle)
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high).frame(width: 26, height: 26)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                Text(verbatim: subtitle ?? (url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
            }
            .help(Text(verbatim: url.path))
            Spacer()
            if let date {
                Text(verbatim: date.formatted(.dateTime.day().month(.abbreviated).year().locale(locale)))
                    .font(.callout).foregroundStyle(.secondary).help(Text(dateHelp))
            }
            Text(verbatim: SizeFormatter.string(size, locale: locale)).foregroundStyle(.secondary).monospacedDigit()
                .frame(minWidth: 70, alignment: .trailing)
            Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "magnifyingglass") }
                .buttonStyle(.borderless)
                .help(Text("apps.reveal"))
        }
        .padding(.vertical, 3)
        .contentShape(Rectangle())
    }
}

/// Linha de um grupo: caixa opcional, seta, ícone, título, marcados, número de itens e total.
struct ModuleGroupRow<Icon: View>: View {
    var title: String
    var size: Int64
    var count: Int
    var selectedCount: Int
    var expanded: Bool
    var tint: Color
    /// Com estado, a linha ganha uma caixa que marca ou desmarca o grupo inteiro (`onCheck`).
    var checkState: SelectionModel.State? = nil
    var onCheck: () -> Void = {}
    var onExpand: () -> Void
    @ViewBuilder var icon: Icon
    @Environment(\.locale) private var locale

    var body: some View {
        HStack(spacing: 10) {
            if let checkState {
                TriStateCheckbox(state: checkState, tint: tint, label: title, action: onCheck)
            }
            Button(action: onExpand) {
                HStack(spacing: 10) {
                    Image(systemName: expanded ? "chevron.down" : "chevron.right").frame(width: 14).foregroundStyle(.secondary)
                    icon.frame(width: 30, height: 30)
                    Text(verbatim: title).lineLimit(1).truncationMode(.middle)
                    Spacer()
                    if selectedCount > 0 {
                        Text(verbatim: "\(selectedCount)")
                            .font(.caption.weight(.semibold)).foregroundStyle(.white)
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(Capsule().fill(tint))
                            .help(Text("clutter.group.selectedHelp"))
                    }
                    Text(verbatim: "\(count)")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(Capsule().fill(Color.secondary.opacity(0.15)))
                        .help(Text("clutter.group.countHelp"))
                    Text(verbatim: SizeFormatter.string(size, locale: locale)).foregroundStyle(.secondary).monospacedDigit()
                        .frame(minWidth: 70, alignment: .trailing)
                }
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(String(format: NSLocalizedString(expanded ? "apps.hide" : "apps.show", comment: ""), title)))
        }
    }
}

extension SelectionModel.State {
    /// Estado da caixa de um grupo com `ids`, dada a função que diz se um id está marcado.
    static func of(_ ids: [String], selected: (String) -> Bool) -> Self {
        let n = ids.filter(selected).count
        return n == 0 ? .off : n == ids.count ? .on : .mixed
    }
}
