import SwiftUI
import CleanYourMacCore

/// Capturas locais do Time Machine: lista com data, seleção e Apagar (com confirmação).
struct SnapshotsView: View {
    var model: PerformanceFlowModel
    @Environment(\.locale) private var locale

    private static let parser: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd-HHmmss"
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            PerformanceSectionHeader(section: .snapshots)
            List(model.report?.snapshots ?? []) { snap in
                let on = Binding(get: { model.selectedSnapshots.contains(snap.id) },
                                 set: { if $0 { model.selectedSnapshots.insert(snap.id) } else { model.selectedSnapshots.remove(snap.id) } })
                let title = Self.parser.date(from: snap.id).map { $0.formatted(.dateTime.day().month().year().hour().minute().locale(locale)) } ?? snap.id
                HStack(spacing: 12) {
                    Toggle(isOn: on) { EmptyView() }
                        .toggleStyle(.checkbox)
                        .accessibilityLabel(Text(title))
                    Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.perfTint).frame(width: 24)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                        Text(verbatim: snap.name).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 3)
            }
            .listStyle(.inset)
        }
    }
}
