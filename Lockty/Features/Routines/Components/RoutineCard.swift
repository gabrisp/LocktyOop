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

    private var accent: Color {
        LocktyColors.routine(routine.color)
    }

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
        if isActive {
            return "Active"
        }

        guard let schedule else { return nil }
        let window = String(
            format: "%02d:%02d – %02d:%02d",
            schedule.hour, schedule.minute, schedule.endHour, schedule.endMinute
        )

        guard let days = daysUntilNextStart(of: schedule) else { return window }
        switch days {
        case 0: return "Empieza hoy"
        case 1: return "Starts tomorrow"
        case 2: return "Starts in 2 d"
        default: return window
        }
    }

    private func activeScheduleProgress(at date: Date) -> CGFloat? {
        guard isActive, let schedule else { return nil }

        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: schedule.timeZoneIdentifier) ?? .current

        let startMinutes = schedule.hour * 60 + schedule.minute
        let endMinutes = schedule.endHour * 60 + schedule.endMinute
        let nowComponents = calendar.dateComponents([.hour, .minute], from: date)
        let nowMinutes = (nowComponents.hour ?? 0) * 60 + (nowComponents.minute ?? 0)

        var startDay = calendar.startOfDay(for: date)
        if endMinutes <= startMinutes, nowMinutes < endMinutes,
           let previousDay = calendar.date(byAdding: .day, value: -1, to: startDay) {
            startDay = previousDay
        }

        guard let startDate = calendar.date(byAdding: .minute, value: startMinutes, to: startDay) else {
            return nil
        }

        let endOffset = endMinutes <= startMinutes ? endMinutes + 24 * 60 : endMinutes
        guard let endDate = calendar.date(byAdding: .minute, value: endOffset, to: startDay) else {
            return nil
        }

        let total = endDate.timeIntervalSince(startDate)
        guard total > 0 else { return nil }

        let elapsed = date.timeIntervalSince(startDate)
        return CGFloat(min(max(elapsed / total, 0), 1))
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
                height: RoutineGridMetrics.tileHeight,
                tint: accent
            ) {
                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    HStack {
                        Image(systemName: routine.icon?.isEmpty == false ? routine.icon! : "repeat")
                            .font(.system(size: 16, weight: .light))
                            .foregroundStyle(LocktyColors.primaryText)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(accent.opacity(0.22)))

                        Spacer(minLength: 0)
                    }

                    Spacer(minLength: 0)

                    if let pillText {
                        TimelineView(.animation) { context in
                            RoutineSchedulePill(
                                text: pillText,
                                accent: accent,
                                progress: activeScheduleProgress(at: context.date)
                            )
                        }
                    }

                    Text(routine.name)
                        .font(.system(.subheadline, design: .default, weight: .bold))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)

                    HStack(spacing: LocktySpacing.xs) {
                        Text("Block")
                            .font(.system(.caption, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.secondaryText)
                            .lineLimit(1)

                        LocktyStackedAppTokens(tokens: applicationTokens)

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .buttonStyle(.locktyInteractive)
        .tappable()
    }
}

private struct RoutineSchedulePill: View {
    let text: String
    let accent: Color
    let progress: CGFloat?

    var body: some View {
        Text(text)
            .font(.system(.caption, design: .default, weight: .medium))
            .foregroundStyle(LocktyColors.primaryText)
            .lineLimit(1)
            .padding(.horizontal, LocktySpacing.sm)
            .padding(.vertical, 5)
            .background {
                GeometryReader { proxy in
                    if let progress {
                        Capsule(style: .continuous)
                            .fill(accent.opacity(0.28))
                            .frame(width: max(proxy.size.width * progress, 0), alignment: .leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .blur(radius: 8)
                            .mask(alignment: .leading) {
                                Capsule(style: .continuous)
                                    .frame(width: max(proxy.size.width * progress, 0))
                            }
                    }
                }
            }
            .overlay {
                Capsule(style: .continuous)
                    .stroke(accent.opacity(0.34), lineWidth: 1)
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
