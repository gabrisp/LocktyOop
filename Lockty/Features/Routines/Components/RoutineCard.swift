import FamilyControls
import ManagedSettings
import SwiftUI

/// Grid tile for a routine: icon on top, then when it next runs, its name, and what it
/// blocks shown as the apps themselves.
struct RoutineCard: View {
    let routine: Routine
    let isActive: Bool
    var applicationTokens: [ApplicationToken] = []
    let onOpen: () -> Void

    private var schedule: RoutineSchedule? {
        routine.triggers.compactMap { trigger -> RoutineSchedule? in
            guard case .schedule(let schedule) = trigger else { return nil }
            return schedule
        }
        .first { !$0.weekdays.isEmpty }
    }

    /// What the pill says. A countdown only while the start is close enough to matter —
    /// "starts in 27 d" is noise, so past three days it shows the window instead.
    private var pillText: String? {
        guard let schedule else { return nil }
        let window = String(
            format: "%02d:%02d – %02d:%02d",
            schedule.hour, schedule.minute, schedule.endHour, schedule.endMinute
        )

        guard let days = daysUntilNextStart(of: schedule) else { return window }
        switch days {
        case 0: return "Empieza hoy"
        case 1: return "Empieza mañana"
        case 2: return "Empieza en 2 d"
        default: return window
        }
    }

    /// Whole days between today and the next weekday the routine runs on.
    private func daysUntilNextStart(of schedule: RoutineSchedule) -> Int? {
        let calendar = Calendar.current
        let today = calendar.component(.weekday, from: Date())

        return (0...7).first { offset in
            let weekdayNumber = ((today - 1 + offset) % 7) + 1
            guard let weekday = Weekday(rawValue: weekdayNumber) else { return false }
            guard schedule.weekdays.contains(weekday) else { return false }
            // Today only counts if the start time hasn't already gone by.
            guard offset == 0 else { return true }
            let now = calendar.dateComponents([.hour, .minute], from: Date())
            let minutesNow = (now.hour ?? 0) * 60 + (now.minute ?? 0)
            return minutesNow < schedule.hour * 60 + schedule.minute
        }
    }

    var body: some View {
        Button(action: onOpen) {
            CardView(
                radius: RoutineGridMetrics.tileRadius,
                interactive: true,
                height: RoutineGridMetrics.tileHeight
            ) {
                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    HStack {
                        Image(systemName: routine.icon?.isEmpty == false ? routine.icon! : "repeat")
                            .font(.system(size: 16, weight: .light))
                            .foregroundStyle(LocktyColors.primaryText)
                            .frame(width: 24, height: 24)

                        Spacer(minLength: 0)

                        if isActive {
                            Text("ACTIVE")
                                .locktyEyebrow()
                                .foregroundStyle(LocktyColors.productive)
                        }
                    }

                    Spacer(minLength: 0)

                    if let pillText {
                        Text(pillText)
                            .font(.system(.caption, design: .default, weight: .medium))
                            .foregroundStyle(LocktyColors.primaryText)
                            .lineLimit(1)
                            .padding(.horizontal, LocktySpacing.sm)
                            .padding(.vertical, 5)
                            .overlay {
                                Capsule(style: .continuous)
                                    .stroke(LocktyColors.cardStroke, lineWidth: 1)
                            }
                    }

                    Text(routine.name)
                        .font(.system(.subheadline, design: .default, weight: .bold))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)

                    HStack(spacing: LocktySpacing.xs) {
                        Text("Bloquear")
                            .font(.system(.caption, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.secondaryText)
                            .lineLimit(1)

                        StackedAppTokens(tokens: applicationTokens)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .buttonStyle(.locktyInteractive)
        .tappable()
    }
}

/// Up to three app icons overlapping, with the count of whatever didn't fit carried on a
/// tile at the end rather than as separate text.
private struct StackedAppTokens: View {
    let tokens: [ApplicationToken]

    private let iconSize: CGFloat = 22
    private let overlap: CGFloat = 7

    private var visible: [ApplicationToken] {
        Array(tokens.prefix(3))
    }

    private var overflow: Int {
        max(0, tokens.count - visible.count)
    }

    var body: some View {
        HStack(spacing: -overlap) {
            ForEach(Array(visible.enumerated()), id: \.element) { index, token in
                Label(token)
                    .labelStyle(.iconOnly)
                    .id(token)
                    .frame(width: iconSize, height: iconSize)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .zIndex(Double(visible.count - index))
            }

            if overflow > 0 {
                Text("+\(overflow)")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(width: iconSize + overlap, height: iconSize, alignment: .trailing)
                    .padding(.trailing, 4)
                    .background(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(LocktyColors.elevatedBackground)
                    )
                    .zIndex(0)
            }
        }
    }
}

enum RoutineGridMetrics {
    static let tileHeight: CGFloat = 150
    static let tileWidth: CGFloat = 168
    static let spacing = LocktySpacing.sm

    /// The full-width card's radius scaled to tile width, so the curvature reads the
    /// same at both sizes. A radius is only "the same" relative to what it is rounding:
    /// 52 on a ~360pt card is a soft corner, 52 on a 168pt tile is nearly a pill.
    static let tileRadius: CGFloat = LocktyRadius.medium * (tileWidth / 360)
}
