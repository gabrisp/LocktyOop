import SwiftUI

/// What is coming up this week, as a list.
///
/// A sibling of `ActiveModeCard` rather than a mode of it. The two look alike on purpose,
/// but they are answering different questions: the active card is about one routine you
/// are inside right now, and this is about several you are not. It carries no row of app
/// icons for that reason -- nothing here is blocking anything yet, and a row of locked
/// apps would say the opposite.
struct ScheduledRoutinesCard: View {
    let routines: [TodayScheduledRoutine]
    var onSelect: ((UUID) -> Void)?
    /// The heading's chevron. Opens the whole list on Focus; tapping one row instead
    /// opens that routine, which is the more specific answer and so takes precedence.
    let onOpenSection: () -> Void

    private var radius: CGFloat { LocktyRadius.medium }

    /// Enough to read the week without the card becoming the screen. Anything past this
    /// is counted rather than listed.
    private let visibleLimit = 4

    private var visible: [TodayScheduledRoutine] {
        Array(routines.prefix(visibleLimit))
    }

    private var overflow: Int {
        max(routines.count - visible.count, 0)
    }

    var body: some View {
        CardView(radius: radius, padding: LocktySpacing.lg) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                LocktySectionTitle("Programadas", onOpen: onOpenSection)

                VStack(spacing: 0) {
                    ForEach(visible) { routine in
                        row(routine)

                        if routine.id != visible.last?.id {
                            Divider()
                                .overlay(LocktyColors.separator.opacity(0.45))
                        }
                    }
                }

                if overflow > 0 {
                    Text(overflow == 1 ? "1 más esta semana" : "\(overflow) más esta semana")
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.tertiaryText)
                }
            }
        }
    }

    private func row(_ routine: TodayScheduledRoutine) -> some View {
        Button {
            onSelect?(routine.routineID)
        } label: {
            HStack(spacing: LocktySpacing.md) {
                Image(systemName: routine.icon?.isEmpty == false ? routine.icon! : "repeat")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .frame(width: 26)

                Text(routine.name)
                    .font(.system(.subheadline, design: .default, weight: .medium))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)

                Spacer(minLength: LocktySpacing.sm)

                // Day and time together, the day first: "when" is the question this card
                // exists to answer, and on a week's list the day is the part that varies.
                Text("\(routine.dayText) · \(routine.timeText)")
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.vertical, LocktySpacing.md)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .tappable()
    }
}
