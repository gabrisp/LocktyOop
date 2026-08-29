import SwiftUI

struct RoutineSummaryCard: View {
    let state: RoutineSummaryCardState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CardView(padding: TodayMetricCardLayout.padding, interactive: true, height: TodayMetricCardLayout.height) {
                TodayMetricCardLayoutView(
                    title: "Routines",
                    value: state.valueText,
                    detail: state.detailText
                )
            }
        }
        .buttonStyle(.plain)
        .tappable()
    }
}
