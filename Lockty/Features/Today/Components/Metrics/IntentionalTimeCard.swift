import SwiftUI

struct IntentionalTimeCard: View {
    let state: IntentionalTimeCardState
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            CardView(padding: TodayMetricCardLayout.padding, interactive: true, height: TodayMetricCardLayout.height) {
                TodayMetricCardLayoutView(title: "Intentional Time", value: state.valueText, detail: state.detailText)
            }
        }
        .buttonStyle(.locktyInteractive)
        .tappable()
    }
}

struct TodayMetricCardLayoutView: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            // The same heading "Rutina" and "Tiempo de uso" carry. These two were the
            // only cards still setting their title by hand, in a heavier font and at full
            // white, so they read as a different kind of card than the ones around them.
            LocktySectionTitle(title, prominent: true)
            Spacer(minLength: 0)
            Text(value)
                .font(LocktyTypography.title)
                .foregroundStyle(LocktyColors.primaryText)
                .monospacedDigit()
                .locktyNumericTransition(trigger: value)
            Text(detail)
                .font(LocktyTypography.caption)
                .foregroundStyle(LocktyColors.secondaryText)
                .locktyNumericTransition(trigger: detail)
        }
    }
}
