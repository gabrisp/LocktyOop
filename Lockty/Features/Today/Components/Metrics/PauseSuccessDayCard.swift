import SwiftUI

struct PauseSuccessDayCard: View {
    let state: PauseSuccessDayCardState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CardView(padding: TodayMetricCardLayout.padding, interactive: true, height: TodayMetricCardLayout.height) {
                TodayMetricCardLayoutView(title: "Pause Success", value: state.valueText, detail: state.detailText)
            }
        }
        .buttonStyle(.locktyInteractive)
        .tappable()
    }
}
