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
        .frame(width: 250)
        .background(Color.black.opacity(0.12))
    }

    private func row(_ module: AppModule) -> some View {
        let selected = module == selection
        return Button {
            if module.isAvailable {
                withAnimation(.smooth(duration: 0.3)) { selection = module }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: module.symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .frame(width: 22)
                Text(module.title)
                    .font(.system(size: 14, weight: .medium))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if !module.isAvailable {
                    Text("module.soon")
                        .font(.system(size: 10, weight: .semibold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.white.opacity(0.14)))
                        .fixedSize()
                }
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
