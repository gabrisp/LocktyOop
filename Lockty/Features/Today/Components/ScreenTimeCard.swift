import SwiftUI

struct ScreenTimeCard: View {
    let state: ScreenTimeCardState
    let action: () -> Void

    var body: some View {
        Button(action: action) { CardView(padding: TodayMetricCardLayout.padding, interactive: true, height: TodayMetricCardLayout.height) {
            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                MetricTitle(title: "Screen Time")

                VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                    Text(state.durationText)
                        .font(LocktyTypography.title)
                        .foregroundStyle(LocktyColors.primaryText)
                        .locktyNumericTransition(trigger: state.durationText)

                    Text(state.comparisonText)
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.secondaryText)
                        .locktyNumericTransition(trigger: state.comparisonText)
                }
            }
        } }.buttonStyle(.plain).tappable()
    }
}
