import SwiftUI

struct RoutineSummaryCard: View {
    let state: RoutineSummaryCardState
    let action: () -> Void

    var body: some View {
        Button(action: action) { CardView(padding: TodayMetricCardLayout.padding, interactive: true, height: TodayMetricCardLayout.height) {
            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                MetricTitle(title: "Routines")

                Spacer(minLength: 0)

                Text(state.valueText)
                    .font(LocktyTypography.title)
                    .foregroundStyle(LocktyColors.primaryText)
                    .monospacedDigit()
                    .locktyNumericTransition(trigger: state.valueText)

                Text(state.detailText)
                    .font(LocktyTypography.caption)
                    .foregroundStyle(LocktyColors.secondaryText)
                    .locktyNumericTransition(trigger: state.detailText)
            }
        } }.buttonStyle(.plain).tappable()
    }
}
