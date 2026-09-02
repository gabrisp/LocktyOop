import SwiftUI

/// A session you can start without making anything first.
///
/// Everything else on Focus is a thing you build and keep: a routine, a rule, a friction.
/// This is the other half of the app -- twenty minutes, these apps, now -- and it used to
/// require creating a routine you would never use again to get it. Nothing here is saved.
///
/// Written as a component rather than as part of the screen so the same control can be
/// dropped anywhere the same offer makes sense; everything it shows comes from the
/// binding it is given.
struct QuickTimerCard: View {
    @Binding var minutes: Int
    /// Nil when nothing is running, otherwise when the session ends. The card becomes
    /// the countdown rather than being replaced by one: it is the same session either
    /// way, and swapping views would lose the connection between the two.
    let endsAt: Date?
    /// The lengths the row steps through. Not a range: fifteen to thirty in fives and
    /// then in quarter hours is what people actually pick, where a plain step of one
    /// would take forty presses to reach an hour.
    var lengths: [Int] = [5, 10, 15, 20, 25, 30, 45, 60, 90, 120]
    let blockedSummary: String
    let frictionSummary: String
    let onStart: () -> Void
    let onStop: () -> Void
    let onOpenApps: () -> Void
    let onOpenFriction: () -> Void

    /// Ticks the countdown. One timer, running only while there is something to count.
    @State private var now = Date()

    private var isRunning: Bool { endsAt != nil }

    private var remaining: TimeInterval {
        guard let endsAt else { return TimeInterval(minutes * 60) }
        return max(endsAt.timeIntervalSince(now), 0)
    }

    var body: some View {
        VStack(spacing: LocktySpacing.lg) {
            display

            if isRunning {
                LocktyHoldButton(
                    title: "Hold to finish",
                    systemImage: "stop.circle",
                    tint: LocktyColors.unproductive,
                    action: onStop
                )
            } else {
                lengthRow

                LocktyHoldButton(
                    title: "Hold to start",
                    systemImage: "play.fill",
                    action: onStart
                )
            }

            chips
        }
        .padding(.horizontal, LocktySpacing.cardInset)
        .padding(.vertical, LocktySpacing.lg)
        .locktyCardBackground(cornerRadius: 30)
        .animation(.snappy(duration: 0.32), value: isRunning)
        .task(id: endsAt) {
            guard endsAt != nil else { return }
            // A second is the smallest thing the readout shows, so it is the fastest this
            // needs to wake. Anything finer is work nobody can see.
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Display

    /// The countdown, large. `mm:ss` rather than a duration phrase: this is a clock, and
    /// a clock that says "1 h 4 m" is a summary of a clock.
    private var display: some View {
        Text(clockText)
            .font(.system(size: 64, weight: .heavy, design: .rounded))
            .monospacedDigit()
            .foregroundStyle(LocktyColors.primaryText)
            .contentTransition(.numericText())
            .animation(.smooth(duration: 0.3), value: clockText)
            .frame(maxWidth: .infinity)
            .padding(.vertical, LocktySpacing.lg)
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LocktyColors.ink(0.05))
            }
            // Lit from behind while it runs, in the colour a running session wears
            // everywhere else in the app. At rest it is an unlit panel, which is the
            // difference between a timer counting and a timer waiting.
            .background {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .fill(LocktyColors.productive)
                    .blur(radius: 30)
                    .opacity(isRunning ? 0.28 : 0)
                    .blendMode(.plusLighter)
                    .animation(.smooth(duration: 0.5), value: isRunning)
            }
            .locktyImperfectBorder(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private var clockText: String {
        let total = Int(remaining.rounded(.up))
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
            : String(format: "%02d:%02d", minutes, seconds)
    }

    // MARK: - Length

    private var lengthRow: some View {
        HStack(spacing: LocktySpacing.md) {
            stepButton(systemImage: "minus", isDisabled: currentIndex <= 0) {
                move(by: -1)
            }

            Text(lengthText)
                .font(.system(.title3, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.22), value: minutes)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background {
                    Capsule(style: .continuous)
                        .fill(LocktyColors.ink(0.05))
                }

            stepButton(systemImage: "plus", isDisabled: currentIndex >= lengths.count - 1) {
                move(by: 1)
            }
        }
    }

    private var lengthText: String {
        minutes < 60 ? "\(minutes) min" : LocktyDurationFormatter.abbreviated(TimeInterval(minutes * 60))
    }

    private var currentIndex: Int {
        lengths.firstIndex(of: minutes) ?? 0
    }

    private func move(by offset: Int) {
        let next = currentIndex + offset
        guard lengths.indices.contains(next) else { return }
        minutes = lengths[next]
    }

    private func stepButton(
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)
                .frame(width: 52, height: 52)
                .background { Circle().fill(LocktyColors.ink(0.05)) }
        }
        .buttonStyle(.locktyInteractive(shape: Circle()))
        .tappable()
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
    }

    // MARK: - Chips

    /// What it will shut and what it will ask of you, side by side. Both open their own
    /// picker; neither is a number, so neither belongs in the row above.
    private var chips: some View {
        HStack(spacing: LocktySpacing.sm) {
            chip(
                systemImage: "lock.shield",
                title: "Blocked apps",
                value: blockedSummary,
                action: onOpenApps
            )

            chip(
                systemImage: "sparkles",
                title: "Friction",
                value: frictionSummary,
                action: onOpenFriction
            )
        }
        // Locked while it runs, like everything else about a running session: changing
        // what a timer blocks halfway through is how a timer stops meaning anything.
        .disabled(isRunning)
        .opacity(isRunning ? 0.45 : 1)
    }

    private func chip(
        systemImage: String,
        title: String,
        value: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: LocktySpacing.sm) {
                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LocktyColors.secondaryText)

                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(.caption, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.tertiaryText)

                    Text(value)
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(LocktyColors.tertiaryText)
            }
            .padding(.horizontal, LocktySpacing.md)
            .frame(height: 56)
            .frame(maxWidth: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(LocktyColors.ink(0.05))
            }
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 20, style: .continuous)))
        .tappable()
    }
}
