import SwiftUI
import CleanYourMacCore

struct SnapshotsView: View {
    var model: PerformanceFlowModel

    var body: some View {
        PerformanceSectionHeader(section: .snapshots)
    }
}
