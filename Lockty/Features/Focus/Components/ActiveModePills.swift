import SwiftUI

/// The modes running right now, as pills that count down.
///
/// The same object as the three score pills: a rim drawn to how far along it is, a bloom
/// of its own colour behind it, the ground pressed in at the edge. The difference is what
/// is inside -- not a score that changes a few times a day, but the time this mode has
/// left, moving every second.
///
/// The colour is the mode's own rather than a tone from a threshold: a running mode is not
/// good or bad, it is Deep Work, and the colour is how you recognise which one it is.
struct ActiveModePills: View {
    let routines: [ActiveRoutine]
    var onSelect: ((ActiveRoutine) -> Void)?

    @Environment(\.colorScheme) private var colorScheme

    private var height: CGFloat { 52 }

    var body: some View {
        // Scrolled rather than wrapped: two modes at once is normal, five is not, and a
        // row that stays a row keeps them all at the same size.
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: LocktySpacing.xl) {
                ForEach(routines) { routine in
                    pill(routine)
                }
            }
            .padding(.horizontal, 2)
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func pill(_ routine: ActiveRoutine) -> some View {
        Button {
            onSelect?(routine)
        } label: {
            VStack(spacing: 6) {
                // One clock for the whole pill: the figure and the rim are the same fact,
                // and reading the date twice would let them disagree by a second.
                TimelineView(.periodic(from: routine.startedAt, by: 1)) { context in
                    // The second itself, not the string: `contentTransition` rolls digits
                    // only when the change is inside an animation, and a `TimelineView`
                    // hands out a new date with no animation around it -- so the numbers
                    // were being replaced outright, which is the one thing they should not
                    // do. This gives the change something to be animated against.
                    let seconds = secondsShown(routine, at: context.date)

                    ZStack {
                        bloom(routine)
                        face(routine, progress: progress(routine, at: context.date))

                        HStack(spacing: 5) {
                            Image(systemName: routine.iconSnapshot?.isEmpty == false ? routine.iconSnapshot! : "moon.zzz")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(LocktyColors.routine(routine.colorSnapshot))

                            Text(clock(seconds))
                                .font(.system(size: 20, weight: .bold))
                                .foregroundStyle(LocktyColors.primaryText)
                                .monospacedDigit()
                                .locktyNumericTransition(trigger: seconds)
                                .lineLimit(1)
                        }
                        .padding(.horizontal, LocktySpacing.lg)
                    }
                    .frame(height: height)
                    .fixedSize(horizontal: true, vertical: false)
                    .compositingGroup()
                    .locktyInteractiveSurface(shape: Capsule(style: .continuous), pressedScale: 0.95)
                }

                Text(routine.nameSnapshot)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
        }
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
    }

    // MARK: - What the clock says

    /// What is left, as hours, minutes and seconds.
    ///
    /// Counting down, because a mode with an end is a thing you are inside of and what you
    /// want to know is when it lets you out. A mode with no end has nothing to count down
    /// to, so it counts up instead -- the same figure, read the other way.
    private func secondsShown(_ routine: ActiveRoutine, at date: Date) -> Int {
        if let end = endsAt(for: routine) {
            return max(Int(end.timeIntervalSince(date)), 0)
        }
        return max(Int(date.timeIntervalSince(routine.startedAt)), 0)
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    /// How much of the rim is drawn: what is left of the mode, as a share of the whole of
    /// it. A mode with no end keeps a full rim -- there is no fraction of forever.
    private func progress(_ routine: ActiveRoutine, at date: Date) -> Double {
        guard let end = endsAt(for: routine) else { return 1 }

        let total = end.timeIntervalSince(routine.startedAt)
        guard total > 0 else { return 1 }
        return min(max(end.timeIntervalSince(date) / total, 0.02), 1)
    }

    private func endsAt(for routine: ActiveRoutine) -> Date? {
        if let expected = routine.expectedEndAt { return expected }
        guard case .schedule(let schedule) = routine.trigger else { return nil }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? .current

        var components = calendar.dateComponents([.year, .month, .day], from: routine.startedAt)
        components.hour = schedule.endHour
        components.minute = schedule.endMinute
        components.second = 0

        guard let end = calendar.date(from: components) else { return nil }
        return end > routine.startedAt ? end : calendar.date(byAdding: .day, value: 1, to: end)
    }

    // MARK: - The pill's body

    private func tint(_ routine: ActiveRoutine) -> Color {
        LocktyColors.routine(routine.colorSnapshot)
    }

    @ViewBuilder
    private func bloom(_ routine: ActiveRoutine) -> some View {
        let shape = Capsule(style: .continuous)

        if colorScheme == .dark {
            shape
                .fill(tint(routine))
                .blur(radius: 14)
                .opacity(0.65)
                .blendMode(.plusLighter)
                .padding(-2)
        } else {
            ZStack {
                shape.fill(.white).blur(radius: 12)
                shape.fill(tint(routine)).blur(radius: 16).opacity(0.18)
            }
            .padding(-2)
        }
    }

    private func face(_ routine: ActiveRoutine, progress: Double) -> some View {
        let shape = Capsule(style: .continuous)
        let colour = tint(routine)
        let isDark = colorScheme == .dark
        let wash = RadialGradient(
            colors: [colour.opacity(isDark ? 0.20 : 0.16), Color.clear],
            center: .center,
            startRadius: 0,
            endRadius: height * 0.7
        )

        return shape
            .fill(colour.opacity(isDark ? 0.14 : 0.10))
            .background { shape.fill(isDark ? LocktyColors.background : LocktyColors.cardSurface) }
            .overlay {
                wash
                    .blendMode(isDark ? .plusLighter : .normal)
                    .opacity(isDark ? 1 : 0.7)
                    .mask { shape }
            }
            .overlay { innerShadow(shape) }
            .overlay { rim(routine, progress: progress) }
    }

    private func innerShadow(_ shape: Capsule) -> some View {
        shape
            .stroke(LocktyColors.background, lineWidth: 10)
            .blur(radius: 6)
            .mask { shape }
    }

    /// The track, what is left of the mode drawn on it, and that same arc blurred behind
    /// itself for its light.
    private func rim(_ routine: ActiveRoutine, progress: Double) -> some View {
        ZStack {
            Capsule(style: .continuous)
                .stroke(LocktyColors.ink(0.10), lineWidth: 2)

            Capsule(style: .continuous)
                .trim(from: 0, to: progress)
                .stroke(tint(routine), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .blur(radius: 4)
                .opacity(colorScheme == .dark ? 1 : 0.55)
                .blendMode(colorScheme == .dark ? .plusLighter : .normal)

            Capsule(style: .continuous)
                .trim(from: 0, to: progress)
                .stroke(tint(routine), style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}
