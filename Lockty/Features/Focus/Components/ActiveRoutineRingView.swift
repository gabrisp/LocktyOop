import SwiftUI

/// A running routine, as a circle you can read at arm's length.
///
/// The same three layers the score circles have -- a bloom outside, the ground pressed in
/// from the rim, a rim that carries a value -- because a routine in progress is the same
/// kind of thing: a number about right now, and how far through it you are.
///
/// It counts down when the routine has an end and up when it does not. A routine started
/// by hand outside its hours has no end to count towards, and a countdown to a moment
/// nobody chose would be inventing one; time elapsed is the honest reading, and it is
/// also the more useful one -- what you want to know about an open-ended block is how
/// long you have kept it.
struct ActiveRoutineRingView: View {
    let routine: ActiveRoutine
    let tint: Color
    var side: CGFloat = 128
    let onSelect: () -> Void

    /// Ticks the clock. One timer per ring, running only while the ring is on screen.
    @State private var now = Date()
    @Environment(\.colorScheme) private var colorScheme

    /// When the routine is due to end, if anything says so.
    ///
    /// `expectedEndAt` first -- a quick timer sets it outright -- and then the schedule
    /// it started from, whose end hour is a real answer for a routine that began on time.
    private var endsAt: Date? {
        if let expected = routine.expectedEndAt { return expected }

        guard case .schedule(let schedule) = routine.trigger else { return nil }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? .current

        var components = calendar.dateComponents([.year, .month, .day], from: routine.startedAt)
        components.hour = schedule.endHour
        components.minute = schedule.endMinute
        components.second = 0

        guard let end = calendar.date(from: components) else { return nil }
        // A window that ends before it starts runs past midnight.
        return end > routine.startedAt ? end : calendar.date(byAdding: .day, value: 1, to: end)
    }

    private var elapsed: TimeInterval {
        max(now.timeIntervalSince(routine.startedAt), 0)
    }

    private var remaining: TimeInterval? {
        endsAt.map { max($0.timeIntervalSince(now), 0) }
    }

    /// Full at the start and empty at the end, so the ring drains as the routine runs.
    /// With no end there is nothing to drain towards, and it simply stays whole.
    private var progress: Double {
        guard let endsAt else { return 1 }
        let total = endsAt.timeIntervalSince(routine.startedAt)
        guard total > 0 else { return 1 }
        return min(max((endsAt.timeIntervalSince(now)) / total, 0), 1)
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(spacing: LocktySpacing.sm) {
                ZStack {
                    bloom
                    face
                    label
                }
                .frame(width: side, height: side)
                .compositingGroup()
                .locktyInteractiveSurface(shape: Circle(), pressedScale: 0.96)

                Text(routine.nameSnapshot)
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(width: side)
            }
        }
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
        .task(id: routine.id) {
            while !Task.isCancelled {
                now = Date()
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }

    // MARK: - Layers

    private var bloom: some View {
        Circle()
            .fill(tint)
            .frame(width: side * 0.92, height: side * 0.92)
            .blur(radius: 24)
            .opacity(0.7)
            .locktyGlow(lightScale: 0.6)
    }

    private var face: some View {
        Circle()
            .fill(tint.opacity(0.14))
            .background { Circle().fill(LocktyColors.background) }
            .overlay {
                RadialGradient(
                    colors: [tint.opacity(0.20), .clear],
                    center: .center,
                    startRadius: 0,
                    endRadius: side * 0.42
                )
                .locktyGlow(lightScale: 0.7)
                .mask { Circle() }
            }
            .overlay {
                Circle()
                    .stroke(LocktyColors.background, lineWidth: 18)
                    .blur(radius: 10)
                    .mask { Circle() }
            }
            .overlay { rim }
    }

    private var rim: some View {
        ZStack {
            Circle()
                .stroke(LocktyColors.ink(0.10), lineWidth: 3)

            Circle()
                .trim(from: 0, to: max(progress, 0.02))
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .blur(radius: 6)
                .locktyGlow(lightScale: 0.7)

            Circle()
                .trim(from: 0, to: max(progress, 0.02))
                .stroke(tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
        }
        .rotationEffect(.degrees(-90))
        .animation(.smooth(duration: 0.9), value: progress)
    }

    private var label: some View {
        VStack(spacing: 1) {
            Image(systemName: routine.iconSnapshot?.isEmpty == false ? routine.iconSnapshot! : "bolt.fill")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)

            Text(clockText)
                .font(.system(size: 26, weight: .bold))
                .monospacedDigit()
                .contentTransition(.numericText())
                .foregroundStyle(colorScheme == .dark ? .white : LocktyColors.deep(tint))

            // Which way the number is going, because the same figure means opposite
            // things: eighteen minutes left, or eighteen minutes in.
            Text(remaining == nil ? "elapsed" : "left")
                .font(.system(.caption2, design: .default, weight: .medium))
                .foregroundStyle(LocktyColors.secondaryText)
        }
    }

    private var clockText: String {
        let value = remaining ?? elapsed
        let total = Int(value.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60

        return hours > 0
            ? String(format: "%d:%02d", hours, minutes)
            : String(format: "%d:%02d", minutes, seconds)
    }
}
