import ActivityKit
import SwiftUI
import WidgetKit

/// Lock Screen / Dynamic Island countdown for an active Pause allowance.
///
/// Every timer here is rendered with `.timer` against `expiresAt` rather than a value
/// the app pushes: the system ticks those itself, so the countdown stays live without
/// the app updating the activity once a second.
struct PauseAllowanceLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PauseAllowanceActivityAttributes.self) { context in
            lockScreenView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        Text(context.attributes.appDisplayName)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)

                        Text(timerInterval: range(for: context), countsDown: true)
                            .font(.system(size: 26, weight: .light, design: .rounded))
                            .monospacedDigit()
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.white)
                    }
                }

                DynamicIslandExpandedRegion(.bottom) {
                    ProgressView(timerInterval: range(for: context), countsDown: true) {
                        EmptyView()
                    } currentValueLabel: {
                        EmptyView()
                    }
                    .tint(.white)
                }
            } compactLeading: {
                Image(systemName: "hourglass")
                    .foregroundStyle(.white)
            } compactTrailing: {
                Text(timerInterval: range(for: context), countsDown: true)
                    .monospacedDigit()
                    .frame(maxWidth: 44)
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: "hourglass")
                    .foregroundStyle(.white)
            }
        }
    }

    private func range(for context: ActivityViewContext<PauseAllowanceActivityAttributes>) -> ClosedRange<Date> {
        let start = context.state.startedAt
        let end = context.state.expiresAt
        // A closed range must not be empty, which it would be if the allowance already
        // elapsed by the time this renders.
        return start <= end ? start...end : end...end.addingTimeInterval(1)
    }

    private func lockScreenView(context: ActivityViewContext<PauseAllowanceActivityAttributes>) -> some View {
        runningLockScreenView(context: context)
    }

    private func runningLockScreenView(context: ActivityViewContext<PauseAllowanceActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "hourglass")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 6) {
                Text(context.attributes.appDisplayName)
                    .font(.subheadline.weight(.light))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                ProgressView(timerInterval: range(for: context), countsDown: true) {
                    EmptyView()
                } currentValueLabel: {
                    EmptyView()
                }
                .tint(.white)
            }

            Spacer(minLength: 0)

            Text(timerInterval: range(for: context), countsDown: true)
                .font(.system(size: 30, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .frame(maxWidth: 96, alignment: .trailing)
        }
        .padding(16)
    }
}
