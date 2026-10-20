import SwiftUI
import AppKit
import CleanYourMacCore

/// Guia para conceder Acesso Total ao Disco; verifica de novo quando o app volta ao primeiro plano.
struct FullDiskAccessBanner: View {
    @State private var granted = PermissionsService.hasFullDiskAccess()

    var body: some View {
        Group {
            if !granted {
                HStack(spacing: 14) {
                    Image(systemName: "lock.shield").font(.system(size: 26))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("permissions.fda.title").font(.system(size: 14, weight: .semibold))
                        Text("permissions.fda.message").font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("permissions.openSettings") { PermissionsService.openSettings(.fullDiskAccess) }
                        .buttonStyle(GlassButtonStyle(prominent: true))
                }
                .padding(16)
                .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(Color.black.opacity(0.25)))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Theme.glassStroke))
                .padding(.horizontal, 28)
                .padding(.top, 16)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            withAnimation(.smooth) { granted = PermissionsService.hasFullDiskAccess() }
        }
    }
}

/// Confirmações antes de limpar: senha de administrador e Gerenciamento de Apps.
struct CleanConfirmation: ViewModifier {
    var model: CleanupFlowModel
    @Binding var pending: [JunkItem]?

    func body(content: Content) -> some View {
        let req = pending.map(model.cleanRequirements) ?? []
        content.alert(req.contains(.appManagement) ? "permissions.apps.title" : "permissions.admin.title",
                      isPresented: Binding(get: { pending != nil && !req.isEmpty }, set: { if !$0 { pending = nil } })) {
            Button("common.cancel", role: .cancel) { pending = nil }
            if req.contains(.appManagement) {
                Button("permissions.openSettings") { PermissionsService.openSettings(.appManagement); pending = nil }
            }
            Button("permissions.continue") {
                if let items = pending { model.clean(items: items) }
                pending = nil
            }
        } message: {
            Text(req.contains(.appManagement) ? "permissions.apps.message" : "permissions.admin.message")
        }
        .onChange(of: pending?.map(\.id)) { _, ids in
            // Sem exigências: limpa direto.
            if ids != nil, let items = pending, model.cleanRequirements(items).isEmpty {
                model.clean(items: items)
                pending = nil
            }
        }
    }
}
