import SwiftUI

struct DistractionsCard: View {
    let state: DistractionsCardState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CardView(padding: TodayMetricCardLayout.padding, interactive: true, height: TodayMetricCardLayout.height) {
                TodayMetricCardLayoutView(
                    title: "Distractions",
                    value: state.valueText,
                    detail: state.comparisonText
                )
            }
        }
        .buttonStyle(.plain)
        .tappable()
    }
}
