import SwiftUI

struct SidebarView: View {
    @Binding var selection: AppModule

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(AppModule.allCases) { module in
                row(module)
            }
            Spacer()
        }
        .padding(.top, 52)
        .padding(.horizontal, 12)
        .frame(width: 240)
        .background(Color.black.opacity(0.12))
    }

    private func row(_ module: AppModule) -> some View {
        let selected = module == selection
        return Button {
            if module.isAvailable {
                withAnimation(.smooth(duration: 0.3)) { selection = module }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: module.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
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
            .foregroundStyle(.white.opacity(module.isAvailable ? 1 : 0.5))
            .padding(.horizontal, 12)
            .padding(.vertical, 11)
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
    }
}
