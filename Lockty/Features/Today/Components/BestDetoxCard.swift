import SwiftUI

struct BestDetoxCard: View {
    let state: BestDetoxCardState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CardView(padding: TodayMetricCardLayout.padding, interactive: true, height: TodayMetricCardLayout.height) {
                TodayMetricCardLayoutView(
                    title: "Best Detox",
                    value: state.durationText,
                    detail: state.comparisonText
                )
            }
        }
        .buttonStyle(.plain)
        .tappable()
    }
}
