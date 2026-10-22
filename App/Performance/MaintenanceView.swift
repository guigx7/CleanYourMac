import SwiftUI
import CleanYourMacCore

/// Lista de tarefas: checkbox, ícone, nome, "Até X GB", descrição e última execução.
struct MaintenanceView: View {
    var model: PerformanceFlowModel
    var search: String
    @Environment(\.locale) private var locale

    private var tasks: [MaintenanceTask] {
        let all = model.report?.tasks ?? []
        guard !search.isEmpty else { return all }
        return all.filter { $0.id.localizedTitle.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(spacing: 0) {
            PerformanceSectionHeader(section: .maintenance)
            List(tasks) { task in row(task) }
                .listStyle(.inset)
        }
    }

    private func row(_ task: MaintenanceTask) -> some View {
        let title = task.id.localizedTitle
        let on = Binding(get: { model.selectedTasks.contains(task.id) },
                         set: { if $0 { model.selectedTasks.insert(task.id) } else { model.selectedTasks.remove(task.id) } })
        return HStack(alignment: .top, spacing: 12) {
            Toggle(isOn: on) { EmptyView() }
                .toggleStyle(.checkbox)
                .accessibilityLabel(Text(title))
            Image(systemName: task.id.symbol)
                .font(.system(size: 18))
                .foregroundStyle(Theme.perfTint)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 8) {
                    Text(title).font(.body.weight(.semibold))
                    if let detail = task.detail {
                        Text(String(format: NSLocalizedString("perf.task.upTo", comment: ""), SizeFormatter.string(detail, locale: locale)))
                            .foregroundStyle(.secondary)
                    }
                    if task.requiresAdmin {
                        Image(systemName: "lock.fill").font(.caption).foregroundStyle(.secondary).help(Text("perf.task.admin"))
                    }
                }
                Text(LocalizedStringKey.dynamic("perf.task.\(task.id.rawValue).description"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let date = model.lastRun(task.id) {
                    Text(String(format: NSLocalizedString("perf.task.lastRun", comment: ""),
                                date.formatted(.dateTime.day().month().year().locale(locale))))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                if task.id == .speedUpMail, !PermissionsService.hasFullDiskAccess() {
                    HStack(spacing: 8) {
                        Label("perf.task.speedUpMail.fda", systemImage: "lock.shield").font(.caption)
                        Button("perf.task.speedUpMail.grant") { PermissionsService.openSettings(.fullDiskAccess) }
                            .controlSize(.small)
                    }
                    .padding(.top, 2)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }
}
