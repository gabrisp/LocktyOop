import SwiftUI

/// What you meant to do today, under where the time actually went.
///
/// Built like the Screen Time card above it, because it is the same kind of thing: a
/// figure, a rule under it, and a few rows saying what went into it. The whole card is
/// one button to the objectives page -- not the heading alone, which left most of the
/// card looking pressable and doing nothing.
///
/// The rows are a picture, not controls. Logging a glass of water happens on the page
/// this opens, where the pills are; a row here that quietly added one on a mis-tap would
/// be a card that changes your day while you are reading it.
struct ObjectivesCard: View {
    @ObservedObject var viewModel: ObjectivesViewModel
    /// The day on screen, which is not always today.
    ///
    /// Everything here used to be read from the objectives' current values, so turning
    /// Today back to Tuesday showed Tuesday's screen time beside this morning's
    /// objectives -- a day where everything was done came up empty.
    var day: Date = Date()
    var onOpen: (() -> Void)?

    /// How many fit on the face before it becomes a list of its own.
    private let maximumShown = 4

    private var isToday: Bool { Calendar.current.isDateInToday(day) }

    /// Only the ones counted by the day, and only the ones that existed on it. A weekly
    /// objective on a card about one day would be answering a question nobody asked of it.
    private var today: [Objective] {
        viewModel.dailyObjectives(on: day)
    }

    private var shown: [Objective] {
        // Outstanding first: the ones still to do are the reason to look at this.
        let outstanding = today.filter { !isComplete($0) }
        let done = today.filter { isComplete($0) }
        return Array((outstanding + done).prefix(maximumShown))
    }

    private func isComplete(_ objective: Objective) -> Bool {
        viewModel.isComplete(objective, on: day)
    }

    private func fraction(_ objective: Objective) -> Double {
        viewModel.fraction(of: objective, on: day)
    }

    private var completedToday: Int {
        today.filter { isComplete($0) }.count
    }

    private var isAllDone: Bool {
        !today.isEmpty && completedToday == today.count
    }

    /// How much of the day has gone, as a share. A day already behind us is a whole day.
    private var elapsedShare: Double {
        guard isToday else { return 1 }
        let calendar = Calendar.current
        let start = calendar.startOfDay(for: day)
        let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return 1 }
        return min(max(Date().timeIntervalSince(start) / length, 0), 1)
    }

    private var completedShare: Double {
        guard !today.isEmpty else { return 0 }
        return Double(completedToday) / Double(today.count)
    }

    /// Ahead of the day or behind it, and by how far.
    ///
    /// One fifth of the objectives done by nine in the morning is a good morning; one
    /// fifth done at bedtime is not, and the figure is the same. So what is read is the
    /// difference between how much of the day has gone and how much of the list has: green
    /// when the list is ahead, red when the day is, and mixed towards the middle rather
    /// than snapping between three fixed colours at a threshold.
    private var pace: Double {
        guard !today.isEmpty else { return 0 }
        return completedShare - elapsedShare
    }

    private var tint: Color {
        guard !today.isEmpty else { return LocktyColors.neutral }

        // Everything done is green whatever the hour and whatever the day. Read through
        // the pace alone, a finished past day came out level -- the whole list done and
        // the whole day gone cancel each other -- so "3 of 3" on Tuesday sat there in
        // amber as though it had been a middling day.
        guard !isAllDone else { return LocktyColors.productive }

        // A tenth either way is level: the list moves in whole objectives, so with four of
        // them nothing lands exactly on the hour of the day.
        let neutral = LocktyColors.warning
        let magnitude = min(abs(pace) / 0.35, 1)
        guard magnitude > 0.05 else { return neutral }

        return neutral.mix(
            with: pace > 0 ? LocktyColors.productive : LocktyColors.unproductive,
            by: magnitude
        )
    }

    var body: some View {
        Button {
            onOpen?()
        } label: {
            CardView(
                radius: LocktyRadius.medium,
                padding: LocktySpacing.xl,
                interactive: true,
                tint: tint
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if today.isEmpty {
                        Text("Eight glasses a day, three sessions a week. A friction can ask whether you kept it.")
                            .font(.system(.footnote, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.top, LocktySpacing.md)
                    } else {
                        Divider()
                            .overlay(LocktyColors.ink(0.12))
                            .padding(.top, 18)
                            .padding(.bottom, 26)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(shown) { objective in
                                row(objective)
                            }
                        }
                        // A picture of the day, not controls -- the same reason the app
                        // rows on the Screen Time card are inert: the card is one button,
                        // and anything inside it that takes a tap takes it from the card.
                        .allowsHitTesting(false)
                    }
                }
            }
            // The whole card, corner to corner: without it the button is only where
            // something was drawn, so the gaps between the rows were dead.
            .contentShape(Rectangle())
        }
        .buttonStyle(.locktyInteractive)
        .tappable()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The chevron-only form: this card is a button in its entirety, so the title
            // must not take the tap for itself.
            LocktySectionTitle("Objectives", showsChevron: true)

            HStack(alignment: .firstTextBaseline, spacing: LocktySpacing.sm) {
                Text(today.isEmpty ? "--" : "\(completedToday) of \(today.count)")
                    .font(.system(.largeTitle, design: .default, weight: .semibold))
                    .foregroundStyle(today.isEmpty ? LocktyColors.primaryText : tint)
                    .monospacedDigit()
                    .locktyNumericTransition(trigger: completedToday)
                    .blur(radius: 1.2)
                    .lineLimit(1)

                Text(isAllDone ? "all done" : (isToday ? "done today" : "done that day"))
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)

                Spacer(minLength: 0)
            }
            .padding(.top, 4)
        }
    }

    /// One objective, read the way an app is read on the Screen Time card: its glyph, its
    /// name, a bar of how far along, and the figure in its own units -- "1,242 of 8,000
    /// steps" rather than a percentage or a duration.
    private func row(_ objective: Objective) -> some View {
        HStack(alignment: .top, spacing: LocktySpacing.md) {
            ObjectiveRing(
                symbolName: objective.symbolName,
                fraction: fraction(objective),
                isComplete: isComplete(objective),
                color: objective.color,
                side: 44,
                lineWidth: 3
            )

            VStack(alignment: .leading, spacing: 0) {
                Text(objective.name)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)

                // The target, said once, under the name -- so the figure at the end of the
                // bar is the number and nothing else.
                if !objective.goalCaption.isEmpty {
                    Text(objective.goalCaption)
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.tertiaryText)
                        .lineLimit(1)
                }

                // The bar ends where the figure begins, rather than the figure being
                // pinned to the far right away from the thing it labels.
                GeometryReader { geometry in
                    let available = max(0, geometry.size.width - valueColumnWidth)
                    let colour = LocktyColors.routine(objective.color)

                    HStack(alignment: .center, spacing: LocktySpacing.sm) {
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [colour, colour.opacity(0.85), colour.opacity(0.25), colour.opacity(0)],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(
                                width: max(22, available * fraction(objective)),
                                height: 4
                            )
                            .blur(radius: 1.2)

                        Text(valueText(objective))
                            .font(.system(.subheadline, design: .default, weight: .regular))
                            .foregroundStyle(colour)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .contentTransition(.numericText())

                        Spacer(minLength: 0)
                    }
                    .frame(width: geometry.size.width, alignment: .leading)
                }
                .frame(height: 18)
            }
        }
        .animation(.smooth(duration: 0.4), value: fraction(objective))
    }

    /// "1,242", or "Yes" for the ones that are simply done or not. What it is counting
    /// towards is in the caption under the name.
    private func valueText(_ objective: Objective) -> String {
        guard !objective.isYesNo else {
            return isComplete(objective) ? "Yes" : "Not yet"
        }
        return objective.formatNumber(viewModel.value(of: objective, on: day))
    }

    /// Room kept for the figure so the longest bar still leaves space for it. Less than
    /// it was: the figure is now the number alone, not the whole sentence.
    private var valueColumnWidth: CGFloat { 86 }
}
