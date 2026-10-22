import SwiftUI

/// Abas fixas embaixo da barra lateral.
enum SidebarPage: String, CaseIterable {
    case settings, about

    var title: LocalizedStringKey { self == .settings ? "sidebar.settings" : "sidebar.about" }
    var symbol: String { self == .settings ? "gearshape.fill" : "info.circle.fill" }
}

struct SidebarView: View {
    @Binding var selection: AppModule
    /// Configurações ou Sobre abertos no lugar do módulo.
    @Binding var page: SidebarPage?
    /// Só ícones (como nas telas de resultado do CleanMyMac).
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(AppModule.allCases) { module in
                row(module)
            }
            Spacer()
            ForEach(SidebarPage.allCases, id: \.self) { p in
                pageRow(p)
            }
        }
        .padding(.bottom, 16)
        .padding(.top, 52)
        .padding(.horizontal, compact ? 10 : 12)
        .frame(width: compact ? 76 : 240)
        .background(Color.black.opacity(0.12))
    }

    private func pageRow(_ p: SidebarPage) -> some View {
        Button {
            withAnimation(.smooth(duration: 0.3)) { page = p }
        } label: {
            label(symbol: p.symbol, title: p.title, subtitle: nil, selected: page == p, enabled: true)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(p.title))
        .help(Text(p.title))
    }

    private func label(symbol: String, title: LocalizedStringKey, subtitle: LocalizedStringKey?, selected: Bool, enabled: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .frame(width: 22)
            if !compact {
                VStack(alignment: .leading, spacing: 1) {
                    Text(title).font(.system(size: 14, weight: .medium)).lineLimit(1)
                    if let subtitle { Text(subtitle).font(.system(size: 11)).opacity(0.8) }
                }
                Spacer(minLength: 0)
            }
        }
        .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
        .foregroundStyle(.white.opacity(enabled ? 1 : 0.5))
        .padding(.horizontal, compact ? 15 : 12)
        .padding(.vertical, compact ? 14 : 11)
        .background {
            if selected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.glassFill)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.glassStroke))
            }
        }
        .contentShape(Rectangle())
    }

    private func row(_ module: AppModule) -> some View {
        let selected = module == selection && page == nil
        return Button {
            if module.isAvailable {
                withAnimation(.smooth(duration: 0.3)) {
                    selection = module
                    page = nil
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: module.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                if !compact {
                    VStack(alignment: .leading, spacing: 1) {
                        Text(module.title)
                            .font(.system(size: 14, weight: .medium))
                            .lineLimit(1)
                        if !module.isAvailable {
                            Text("module.soon")
                                .font(.system(size: 11))
                                .opacity(0.8)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: compact ? nil : .infinity, alignment: .leading)
            .foregroundStyle(.white.opacity(module.isAvailable ? 1 : 0.5))
            .padding(.horizontal, compact ? 15 : 12)
            .padding(.vertical, compact ? 14 : 11)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Theme.glassFill)
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.glassStroke))
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!module.isAvailable)
        .accessibilityLabel(Text(module.title))
        .help(Text(module.title))
    }
}
