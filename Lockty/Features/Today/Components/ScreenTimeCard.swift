import SwiftUI

struct ScreenTimeCard: View {
    let state: ScreenTimeCardState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CardView(padding: TodayMetricCardLayout.padding, interactive: true, height: TodayMetricCardLayout.height) {
                TodayMetricCardLayoutView(
                    title: "Screen Time",
                    value: state.durationText,
                    detail: state.comparisonText
                )
            }
        }
        .buttonStyle(.plain)
        .tappable()
    }
}
