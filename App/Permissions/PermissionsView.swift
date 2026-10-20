import SwiftUI
import AppKit
import CleanYourMacCore

/// Aviso compacto de Acesso Total ao Disco; some quando a permissão é concedida.
struct FullDiskAccessBanner: View {
    @State private var granted = PermissionsService.hasFullDiskAccess()

    var body: some View {
        Group {
            if !granted {
                Button { PermissionsService.openSettings(.fullDiskAccess) } label: {
                    Label("permissions.fda.short", systemImage: "lock.shield")
                        .font(.system(size: 12, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.25)))
                        .overlay(Capsule().strokeBorder(Theme.glassStroke))
                }
                .buttonStyle(.plain)
                .help(Text("permissions.fda.message"))
                .transition(.opacity)
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
