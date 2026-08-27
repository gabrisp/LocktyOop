import SwiftUI

enum TodayMetricCardLayout {
    static let height: CGFloat = 132
    static let padding: CGFloat = LocktySpacing.md
}

extension View {
    @ViewBuilder
    func locktyNumericTransition<Value: Equatable>(trigger: Value) -> some View {
        self
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.24), value: trigger)
    }
}
