import SwiftUI
import AppKit

/// Sobre: o app, a versão, os links do projeto e o aviso de projeto independente.
struct AboutView: View {
    static let repo = URL(string: "https://github.com/guigx7/CleanYourMac")!

    static func versionLine(short: String, build: String) -> String {
        String(format: NSLocalizedString("about.version", comment: ""), short, build)
    }

    private var version: String {
        let info = Bundle.main.infoDictionary ?? [:]
        return Self.versionLine(short: info["CFBundleShortVersionString"] as? String ?? "?", build: info["CFBundleVersion"] as? String ?? "?")
    }

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 128, height: 128)
                .shadow(color: .black.opacity(0.3), radius: 16, y: 8)
            Text(verbatim: "CleanYourMac").font(Theme.display(40))
            Text(verbatim: version).font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.secondaryText)
                .textSelection(.enabled)
            Text("about.description")
                .font(.system(size: 16))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            HStack(spacing: 12) {
                Button { NSWorkspace.shared.open(Self.repo) } label: { Label("about.github", systemImage: "chevron.left.forwardslash.chevron.right") }
                    .buttonStyle(GlassButtonStyle(size: .large))
                Button { NSWorkspace.shared.open(Self.repo.appendingPathComponent("releases")) } label: {
                    Label("about.releases", systemImage: "arrow.down.circle")
                }
                .buttonStyle(GlassButtonStyle(size: .large))
                Button { NSWorkspace.shared.open(Self.repo.appendingPathComponent("blob/main/LICENSE")) } label: {
                    Label("about.license", systemImage: "doc.text")
                }
                .buttonStyle(GlassButtonStyle(size: .large))
            }
            .padding(.top, 6)
            Spacer()
            Text("about.disclaimer")
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 620)
                .padding(.bottom, 28)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 40)
    }
}
