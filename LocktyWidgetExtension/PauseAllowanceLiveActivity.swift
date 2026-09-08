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
                // The glyph on one side and how long is left on the other, with the bar
                // under both. Leading and trailing sit either side of the camera cutout,
                // which is where those two belong; the bar is the widest thing here and
                // goes in the bottom region, the only one that spans the whole island.
                // Nothing asks for a width here. Each region is sized to its content and
                // the island balances the two: making one of them claim `.infinity` made
                // that side win the argument, which is the lopsided island -- stretched
                // right, cramped left. A glyph and a countdown are small things and are
                // allowed to be.
                DynamicIslandExpandedRegion(.leading) {
                    Image(systemName: context.attributes.symbolName)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(timerInterval: range(for: context), countsDown: true)
                        .font(.system(size: 22, weight: .light, design: .rounded))
                        .monospacedDigit()
                        .lineLimit(1)
                        .foregroundStyle(.white)
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
                // Both compact sides ask for as much as they can get. The system clamps
                // them to whatever the island has spare, so a generous number is a request
                // for the maximum rather than a size: the old 44 on the trailing side was
                // a real cap, and it cut "59:59" short.
                Image(systemName: context.attributes.symbolName)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 100)
            } compactTrailing: {
                Text(timerInterval: range(for: context), countsDown: true)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(maxWidth: 100)
                    .foregroundStyle(.white)
            } minimal: {
                Image(systemName: context.attributes.symbolName)
                    .foregroundStyle(.white)
            }
        }
    }

    /// The Lock Screen row: the glyph, the bar, and how long is left. One line, nothing
    /// else on it.
    ///
    /// The app's name used to be here and in the island both, and it is the one thing the
    /// person looking already knows -- they are holding the phone that is showing them the
    /// app. What they cannot know is how much of the allowance is left, which is what the
    /// bar and the figure are for.
    ///
    /// The bar is the only thing that grows; the glyph and the figure are their own size,
    /// so the middle takes whatever is left over on any width of screen.
    private func row(context: ActivityViewContext<PauseAllowanceActivityAttributes>) -> some View {
        HStack(spacing: 14) {
            Image(systemName: context.attributes.symbolName)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(.white)

            ProgressView(timerInterval: range(for: context), countsDown: true) {
                EmptyView()
            } currentValueLabel: {
                EmptyView()
            }
            .tint(.white)
            .frame(maxWidth: .infinity)

            Text(timerInterval: range(for: context), countsDown: true)
                .font(.system(size: 30, weight: .light, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .fixedSize()
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
        row(context: context)
            .padding(16)
    }
}
