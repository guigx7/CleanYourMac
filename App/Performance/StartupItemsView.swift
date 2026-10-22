import SwiftUI
import CleanYourMacCore

struct StartupItemsView: View {
    var model: PerformanceFlowModel
    var search: String

    var body: some View {
        PerformanceSectionHeader(section: model.section)
    }
}

struct StartupFooterButtons: View {
    var model: PerformanceFlowModel

    var body: some View {
        EmptyView()
    }
}
