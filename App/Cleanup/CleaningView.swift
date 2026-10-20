import SwiftUI
import AppKit
import CleanYourMacCore

/// Motivos técnicos de falha → texto da interface.
enum FailureText {
    static func key(for reason: String) -> String {
        let r = reason.lowercased()
        if r == "cancelled" { return "reason.cancelled" }
        if r == "in use" { return "reason.inUse" }
        if r.hasPrefix("signature") { return "reason.signature" }
        if r.contains("operation not permitted") && r.contains(".app") { return "reason.appManagement" }
        if r.hasPrefix("path not allowed") || r.contains("permission") || r.contains("not permitted") { return "reason.permission" }
        return "reason.unknown"
    }
}

struct CleaningView: View {
    var model: CleanupFlowModel
    @State private var confirmStop = false

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .cleanup, isAnimating: true)
        } side: {
            VStack(alignment: .leading, spacing: 16) {
                Text("cleaning.title").font(Theme.display(34))
                Text(String(format: NSLocalizedString("cleaning.current", comment: ""), model.cleaningItem?.name ?? "…"))
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(Theme.secondaryText)
                    .lineLimit(1).truncationMode(.middle)
                    .contentTransition(.opacity)
                ProgressView(value: model.cleaningFraction)
                    .tint(Theme.accent(for: .cleanup))
                    .animation(.smooth, value: model.cleaningFraction)
                VStack(alignment: .leading, spacing: 2) {
                    AnimatedBytes(bytes: model.freedBytes).font(Theme.display(40, weight: .bold))
                    Text("cleaning.freed").font(.system(size: 13)).foregroundStyle(Theme.secondaryText)
                }
            }
        } action: {
            PrimaryRoundButton(title: "cleanup.action.stop") { confirmStop = true }
        }
        .alert("cleaning.stop.confirm.title", isPresented: $confirmStop) {
            Button("cleaning.stop.continue", role: .cancel) {}
            Button("cleanup.action.stop", role: .destructive) { model.stopCleaning() }
        } message: {
            Text("cleaning.stop.confirm.message")
        }
    }
}

struct DoneView: View {
    var model: CleanupFlowModel
    var report: CleanReport
    @State private var showLog = false
    @Environment(\.locale) private var locale

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .cleanup, isAnimating: false)
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: model.hasFailures ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                        .font(.system(size: 64))
                        .foregroundStyle(.white, model.hasFailures ? Color.orange : Theme.accent(for: .cleanup))
                        .transition(.scale.combined(with: .opacity))
                }
        } side: {
            VStack(alignment: .leading, spacing: 14) {
                Text(model.hasFailures ? "failure.title" : "done.title").font(Theme.display(34))
                if model.hasFailures {
                    Text("failure.message").foregroundStyle(Theme.secondaryText)
                }
                ForEach(totals, id: \.0) { key, bytes in
                    Text(String(format: NSLocalizedString(key, comment: ""), SizeFormatter.string(bytes, locale: locale)))
                        .font(.system(size: 17, weight: .semibold))
                }
                if report.dryRun {
                    Label("done.simulated", systemImage: "info.circle").font(.callout).foregroundStyle(Theme.secondaryText)
                }
                if model.hasFailures {
                    HStack {
                        Button(showLog ? "failure.hideLog" : "failure.showLog") { withAnimation(.snappy) { showLog.toggle() } }
                        Button("failure.reviewRemaining") { model.reviewRemaining() }
                    }
                    .buttonStyle(GlassButtonStyle())
                    if showLog { CleanupLogView(model: model).transition(.opacity.combined(with: .move(edge: .top))) }
                }
            }
        } action: {
            PrimaryRoundButton(title: "done.ok", action: model.acknowledgeDone)
        }
    }

    private var totals: [(String, Int64)] {
        let kinds = model.freedByKind
        return [("done.junk", kinds[.junk] ?? 0), ("done.mail", kinds[.mail] ?? 0), ("done.trash", kinds[.trash] ?? 0)]
            .filter { $0.1 > 0 }
    }
}

/// Registro de Limpeza: itens que falharam ou foram parados, com o motivo.
struct CleanupLogView: View {
    var model: CleanupFlowModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(model.failedItems, id: \.0.id) { item, reason in
                        row(item, status: "log.failed", reason: FailureText.key(for: reason))
                    }
                    ForEach(model.stoppedItems) { item in
                        row(item, status: "log.stopped", reason: nil)
                    }
                }
            }
            .frame(maxHeight: 160)
            Button("log.copy") {
                let text = model.failedItems.map { "\($0.0.url?.path ?? $0.0.name): \($0.1)" }.joined(separator: "\n")
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
            .buttonStyle(GlassButtonStyle())
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.glassFill))
    }

    private func row(_ item: JunkItem, status: LocalizedStringKey, reason: String?) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(status).font(.caption.weight(.semibold)).foregroundStyle(.orange).frame(width: 60, alignment: .leading)
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.callout).lineLimit(1).truncationMode(.middle)
                if let reason { Text(LocalizedStringKey(stringLiteral: reason)).font(.caption).foregroundStyle(Theme.secondaryText) }
            }
            Spacer()
            if let url = item.url {
                Button { NSWorkspace.shared.activateFileViewerSelecting([url]) } label: { Image(systemName: "magnifyingglass") }
                    .buttonStyle(.plain)
                    .help(Text("log.reveal"))
            }
        }
    }
}
