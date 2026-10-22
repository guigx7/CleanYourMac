import SwiftUI
import CleanYourMacCore

struct PerformanceManagerView: View {
    var model: PerformanceFlowModel

    var body: some View {
        Button("review.back") { model.closeManager() }
    }
}
