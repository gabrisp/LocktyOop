import SwiftUI

struct DistractionsCard: View {
    let state: DistractionsCardState
    let action: () -> Void

    var body: some View {
        Button(action: action) { CardView(padding: TodayMetricCardLayout.padding, interactive: true, height: TodayMetricCardLayout.height) {
            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                MetricTitle(title: "Distractions")

                Spacer(minLength: 0)

                Text(state.valueText)
                    .font(LocktyTypography.title)
                    .foregroundStyle(LocktyColors.primaryText)
                    .monospacedDigit()
                    .locktyNumericTransition(trigger: state.valueText)

                Text(state.comparisonText)
                    .font(LocktyTypography.caption)
                    .foregroundStyle(LocktyColors.secondaryText)
                    .locktyNumericTransition(trigger: state.comparisonText)
            }
        } }.buttonStyle(.plain).tappable()
    }
}
