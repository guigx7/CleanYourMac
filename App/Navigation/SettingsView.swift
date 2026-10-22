import SwiftUI
import AppKit
import CleanYourMacCore

/// Configurações: permissões (com o estado de cada uma), o ajudante, os registros e o idioma.
struct SettingsView: View {
    @State private var fullDiskAccess = PermissionsService.hasFullDiskAccess()
    @State private var confirmRemoveHelper = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("sidebar.settings").font(Theme.display(38))
                section("settings.section.permissions") {
                    row(icon: "lock.shield", title: "settings.fda.title", detail: "settings.fda.detail",
                        status: fullDiskAccess ? "settings.status.granted" : "settings.status.missing", ok: fullDiskAccess) {
                        Button("permissions.openSettings") { PermissionsService.openSettings(.fullDiskAccess) }
                            .buttonStyle(GlassButtonStyle())
                    }
                    Divider().opacity(0.25)
                    row(icon: "app.badge.checkmark", title: "settings.apps.title", detail: "settings.apps.detail", status: nil, ok: true) {
                        Button("permissions.openSettings") { PermissionsService.openSettings(.appManagement) }
                            .buttonStyle(GlassButtonStyle())
                    }
                    Divider().opacity(0.25)
                    helperRow
                }
                section("settings.section.logs") {
                    row(icon: "doc.text.magnifyingglass", title: "settings.logs.title", detail: "settings.logs.detail", status: nil, ok: true) {
                        Button("settings.logs.open") {
                            try? FileManager.default.createDirectory(at: CleanupLog.standard.directory, withIntermediateDirectories: true)
                            NSWorkspace.shared.open(CleanupLog.standard.directory)
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                }
                section("settings.section.language") {
                    row(icon: "globe", title: "settings.language.title", detail: "settings.language.detail", status: nil, ok: true) {
                        Button("permissions.openSettings") {
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Localization-Settings.extension")!)
                        }
                        .buttonStyle(GlassButtonStyle())
                    }
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(.horizontal, 40)
            .padding(.top, 56)
            .padding(.bottom, 32)
        }
        .scrollIndicators(.never)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            fullDiskAccess = PermissionsService.hasFullDiskAccess()
            HelperManager.shared.refresh()
        }
        .alert("settings.helper.remove.confirm", isPresented: $confirmRemoveHelper) {
            Button("common.cancel", role: .cancel) {}
            Button("settings.helper.remove", role: .destructive) { HelperManager.shared.uninstall() }
        } message: {
            Text("settings.helper.remove.message")
        }
    }

    private var helperRow: some View {
        let state = HelperManager.shared.state
        return row(icon: "shield.lefthalf.filled", title: "settings.helper.title", detail: "helper.install.hint",
                   status: Self.helperStatusKey(state), ok: state == .active) {
            if let key = Self.helperActionKey(state) {
                Button(LocalizedStringKey(key)) {
                    switch state {
                    case .active: confirmRemoveHelper = true
                    case .outdated: HelperManager.shared.update()
                    default: HelperManager.shared.install()
                    }
                }
                .buttonStyle(GlassButtonStyle(prominent: state != .active))
            }
        }
    }

    static func helperStatusKey(_ state: HelperManager.State) -> String {
        switch state {
        case .notInstalled: "settings.helper.status.none"
        case .needsApproval: "settings.helper.status.approval"
        case .active: "settings.helper.status.active"
        case .outdated: "settings.helper.status.outdated"
        case .unavailable: "settings.helper.status.unavailable"
        }
    }

    /// Ação do botão para cada estado (nil quando não há o que fazer).
    static func helperActionKey(_ state: HelperManager.State) -> String? {
        switch state {
        case .notInstalled: "helper.install"
        case .needsApproval: "helper.approve"
        case .outdated: "helper.update"
        case .active: "settings.helper.remove"
        case .unavailable: nil
        }
    }

    private func section(_ title: LocalizedStringKey, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.secondaryText)
            GlassCard { VStack(alignment: .leading, spacing: 14) { content() } }
        }
    }

    private func row(icon: String, title: LocalizedStringKey, detail: LocalizedStringKey, status: String?, ok: Bool,
                     @ViewBuilder action: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon).font(.system(size: 20)).frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 15, weight: .semibold))
                    if let status {
                        Label(LocalizedStringKey(status), systemImage: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(ok ? Color(hex: 0xA6F0B8) : Color(hex: 0xFFD2A0))
                    }
                }
                Text(detail).font(.system(size: 13)).foregroundStyle(Theme.secondaryText).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            action()
        }
    }
}
