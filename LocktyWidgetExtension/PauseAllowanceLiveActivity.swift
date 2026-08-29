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
                    Image(systemName: context.isStale ? "lock.fill" : "hourglass")
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
                Image(systemName: context.isStale ? "lock.fill" : "hourglass")
                    .foregroundStyle(.white)
            } compactTrailing: {
                if !context.isStale {
                    Text(timerInterval: range(for: context), countsDown: true)
                        .monospacedDigit()
                        .frame(maxWidth: 44)
                        .foregroundStyle(.white)
                }
            } minimal: {
                Image(systemName: context.isStale ? "lock.fill" : "hourglass")
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

    /// What the activity shows once the allowance is spent.
    ///
    /// The content is given a stale date of the expiry, so the system re-renders here on
    /// the second it runs out without the app having to be running. It cannot dismiss
    /// itself -- only code can end an activity -- but it stops claiming there is time
    /// left, which is what a countdown frozen at 0:00 was doing.
    private func expiredView(context: ActivityViewContext<PauseAllowanceActivityAttributes>) -> some View {
        HStack(spacing: 16) {
            Image(systemName: "lock.fill")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(context.attributes.appDisplayName)
                    .font(.subheadline.weight(.light))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text("Se acabó el descanso")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(16)
    }

    @ViewBuilder
    private func lockScreenView(context: ActivityViewContext<PauseAllowanceActivityAttributes>) -> some View {
        if context.isStale {
            expiredView(context: context)
        } else {
            runningLockScreenView(context: context)
        }
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
