import SwiftUI
import AppKit
import CleanYourMacCore

/// Progresso: tarefas uma a uma (com Parar) ou a ação nos itens.
struct PerformanceActingView: View {
    var model: PerformanceFlowModel

    private var tasks: [MaintenanceTask] { (model.report?.tasks ?? []).filter { model.taskStatus[$0.id] != nil } }

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .performance, isAnimating: true)
        } side: {
            VStack(alignment: .leading, spacing: 16) {
                Text(LocalizedStringKey(tasks.isEmpty ? "perf.acting.items" : "perf.acting.tasks")).font(Theme.display(34))
                if tasks.isEmpty {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(tasks) { t in
                            HStack(spacing: 10) {
                                TaskStatusIcon(status: model.taskStatus[t.id] ?? .waiting)
                                Text(LocalizedStringKey.dynamic("perf.task.\(t.id.rawValue).title")).font(.system(size: 15, weight: .semibold))
                            }
                        }
                    }
                }
            }
        } action: {
            if tasks.isEmpty {
                EmptyView()
            } else {
                PrimaryRoundButton(title: "cleanup.action.stop", module: .performance, action: model.stopActing)
            }
        }
    }
}

struct TaskStatusIcon: View {
    var status: PerformanceFlowModel.TaskStatus

    var body: some View {
        switch status {
        case .waiting: Image(systemName: "circle").foregroundStyle(Theme.secondaryText)
        case .running: ProgressView().controlSize(.small).tint(.white)
        case .succeeded: Image(systemName: "checkmark.circle.fill").foregroundStyle(.white)
        case .failed: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color(hex: 0xFFD2A0))
        }
    }
}

/// Fim da ação: quantos deram certo, o que falhou e por quê, e o registro.
struct PerformanceDoneView: View {
    var model: PerformanceFlowModel
    var outcome: PerformanceFlowModel.Outcome

    private var failed: Bool { !outcome.failed.isEmpty }

    private var kindKey: String {
        switch outcome.kind {
        case .maintenance: "tasks"
        case .startup(.disable): "disable"
        case .startup(.enable): "enable"
        case .startup(.remove): "remove"
        case .snapshots: "snapshots"
        }
    }

    var body: some View {
        ModuleStage {
            ModuleArtwork(module: .performance, isAnimating: false)
        } side: {
            VStack(alignment: .leading, spacing: 14) {
                Text(LocalizedStringKey.dynamic(failed ? "perf.done.\(kindKey).partial" : "perf.done.\(kindKey).title")).font(Theme.display(38))
                Text(String(format: NSLocalizedString("perf.done.count", comment: ""), outcome.succeeded))
                    .font(.system(size: 16))
                    .foregroundStyle(Theme.secondaryText)
                if failed {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(outcome.failed.sorted { $0.key < $1.key }, id: \.key) { name, reason in
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(displayName(name)).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text(FailureText.describe(reason)).font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
                                }
                            }
                        }
                    }
                    .frame(maxHeight: 180)
                }
                HStack(spacing: 10) {
                    if outcome.kind == .startup(.remove) {
                        Button("apps.done.openTrash") {
                            NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash"))
                        }
                        .buttonStyle(GlassButtonStyle(size: .large))
                    }
                    Button("apps.done.log") { NSWorkspace.shared.open(CleanupLog.standard.directory) }
                        .buttonStyle(GlassButtonStyle(size: .large))
                }
                .padding(.top, 6)
            }
        } action: {
            PrimaryRoundButton(title: "results.restart", module: .performance, action: model.restart)
        }
    }

    /// Tarefas aparecem pelo título; itens e capturas, pelo nome.
    private func displayName(_ name: String) -> String {
        MaintenanceTaskID(rawValue: name).map { NSLocalizedString("perf.task.\($0.rawValue).title", comment: "") } ?? name
    }
}
