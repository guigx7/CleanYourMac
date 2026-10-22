import SwiftUI
import AppKit
import CleanYourMacCore

/// Progresso da ação (desinstalar, redefinir, remover sobras).
struct AppsActingView: View {
    var model: AppsFlowModel

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .applications, isAnimating: true)
        } side: {
            VStack(alignment: .leading, spacing: 16) {
                Text("apps.acting.title").font(Theme.display(34))
                Text(model.actingItem?.name ?? " ")
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.middle)
                ProgressView(value: Double(model.processed), total: Double(max(model.toProcess, 1)))
                    .tint(.white)
                Text(String(format: NSLocalizedString("apps.acting.progress", comment: ""), model.processed, model.toProcess))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondaryText)
            }
        } action: {
            EmptyView()
        }
    }
}

/// Fim da ação: o que foi para o Lixo, o que foi apagado e o que falhou.
struct AppsDoneView: View {
    var model: AppsFlowModel
    var report: CleanReport

    private var failed: Bool { !report.failed.isEmpty }

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .applications, isAnimating: false)
        } side: {
            VStack(alignment: .leading, spacing: 14) {
                Text(LocalizedStringKey(failed ? "apps.done.partial.title" : "apps.done.title")).font(Theme.display(38))
                Text(report.dryRun ? String(format: NSLocalizedString("apps.done.dryRun", comment: ""), report.removed.count)
                     : AppsFlowModel.doneKeys(trashed: model.lastCounts.trashed, deleted: model.lastCounts.deleted)
                        .map { String(format: NSLocalizedString($0, comment: ""), report.removed.count) }.joined(separator: " "))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondaryText)
                if failed {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(report.failed.sorted { $0.key < $1.key }, id: \.key) { id, reason in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(verbatim: (id.split(separator: "\u{1E}").last.map(String.init) ?? id))
                                        .font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                                    Text(FailureText.describe(reason)).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
                if model.needsAppManagement {
                    Label("apps.done.appManagement", systemImage: "lock.shield")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondaryText)
                    Button("apps.done.allowAppManagement") { PermissionsService.openSettings(.appManagement) }
                        .buttonStyle(GlassButtonStyle(prominent: true, size: .large))
                }
                HStack(spacing: 10) {
                    Button("apps.done.openTrash") {
                        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
                    }
                    .buttonStyle(GlassButtonStyle(size: .large))
                    Button("apps.done.log") {
                        NSWorkspace.shared.open(CleanupLog.standard.directory)
                    }
                    .buttonStyle(GlassButtonStyle(size: .large))
                }
                .padding(.top, 6)
            }
        } action: {
            PrimaryRoundButton(title: "results.restart", module: .applications, action: model.restart)
        }
    }
}
