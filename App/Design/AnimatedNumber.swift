import SwiftUI
import CleanYourMacCore

/// Tamanho em bytes que anima ao mudar.
struct AnimatedBytes: View {
    var bytes: Int64
    @Environment(\.locale) private var locale

    var body: some View {
        Text(SizeFormatter.string(bytes, locale: locale))
            .contentTransition(.numericText(value: Double(bytes)))
            .animation(.snappy(duration: 0.35), value: bytes)
            .monospacedDigit()
    }
}
