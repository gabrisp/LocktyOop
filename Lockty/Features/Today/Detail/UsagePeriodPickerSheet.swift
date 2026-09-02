import SwiftUI

/// Choosing which day, week or month the screen is showing.
///
/// One sheet with three faces rather than three sheets, because it answers one question.
/// A week is picked by touching any day in it -- there is no such thing as tapping "a
/// week", and asking someone to find the Monday is asking them to do the calendar's job.
/// The whole week lights up under the finger so the answer is visible before it is taken.
struct UsagePeriodPickerSheet: View {
    let period: UsagePeriod
    @Binding var selection: Date

    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = .current
        // Monday first, as the rest of the app's schedule reads.
        calendar.firstWeekday = 2
        return calendar
    }

    var body: some View {
        LocktyDynamicSheet {
            // No heading. The sheet shows a calendar or a row of months -- there is
            // nothing to explain, and a line saying "pick a day" above a calendar is the
            // screen narrating itself.
            VStack(spacing: LocktySpacing.lg) {
                switch period {
                case .day, .week:
                    UsageCalendarPicker(
                        selection: $selection,
                        highlightsWholeWeek: period == .week,
                        calendar: calendar
                    )

                case .month:
                    monthGrid
                }
            }
            .padding(.horizontal, LocktySpacing.screenInset)
            .padding(.top, LocktySpacing.lg)
            .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.lg))
        }
    }

    // MARK: - Months

    /// The last twelve months as pills. A grid rather than a calendar: a month has no
    /// inside worth showing when the month itself is what is being chosen.
    private var monthGrid: some View {
        let months = recentMonths

        return LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: LocktySpacing.sm), count: 3),
            spacing: LocktySpacing.sm
        ) {
            ForEach(months, id: \.self) { month in
                let isSelected = calendar.isDate(month, equalTo: selection, toGranularity: .month)

                Button {
                    selection = month
                } label: {
                    Text(monthLabel(month))
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(isSelected ? LocktyColors.onPrimary : LocktyColors.primaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 46)
                        .background {
                            Capsule(style: .continuous)
                                .fill(isSelected ? LocktyColors.primaryText : LocktyColors.ink(0.06))
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
                .tappable()
            }
        }
    }

    /// Twelve back from this one. Screen Time keeps far less than a year, so offering
    /// more would be offering empty months.
    private var recentMonths: [Date] {
        let start = calendar.dateInterval(of: .month, for: Date())?.start ?? Date()
        return (0..<12)
            .compactMap { calendar.date(byAdding: .month, value: -$0, to: start) }
            .reversed()
    }

    private func monthLabel(_ month: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate(
            calendar.isDate(month, equalTo: Date(), toGranularity: .year) ? "MMM" : "MMM yy"
        )
        return formatter.string(from: month)
    }
}

/// A month of days, with either one of them selected or the whole week around it.
private struct UsageCalendarPicker: View {
    @Binding var selection: Date
    let highlightsWholeWeek: Bool
    let calendar: Calendar

    @State private var visibleMonth: Date

    init(
        selection: Binding<Date>,
        highlightsWholeWeek: Bool,
        calendar: Calendar
    ) {
        _selection = selection
        self.highlightsWholeWeek = highlightsWholeWeek
        self.calendar = calendar
        _visibleMonth = State(
            initialValue: calendar.dateInterval(of: .month, for: selection.wrappedValue)?.start ?? Date()
        )
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

    var body: some View {
        VStack(spacing: LocktySpacing.md) {
            header
            weekdayHeader

            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(Array(days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(height: 42)
                    }
                }
            }
        }
    }

    private var header: some View {
        HStack {
            stepButton(systemImage: "chevron.left", offset: -1)

            Text(monthTitle)
                .font(.system(.headline, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)
                .contentTransition(.numericText())
                .frame(maxWidth: .infinity)

            stepButton(systemImage: "chevron.right", offset: 1, isDisabled: !canMoveForward)
        }
    }

    private func stepButton(systemImage: String, offset: Int, isDisabled: Bool = false) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.28)) {
                visibleMonth = calendar.date(byAdding: .month, value: offset, to: visibleMonth) ?? visibleMonth
            }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)
                .frame(width: 40, height: 40)
                .safeGlass(radius: 20, interactive: true)
        }
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.3 : 1)
    }

    private var canMoveForward: Bool {
        guard let next = calendar.date(byAdding: .month, value: 1, to: visibleMonth) else { return false }
        return next <= Date()
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter.string(from: visibleMonth)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 0) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.system(.caption, design: .default, weight: .medium))
                    .foregroundStyle(LocktyColors.tertiaryText)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current
        let symbols = formatter.veryShortStandaloneWeekdaySymbols ?? ["S", "M", "T", "W", "T", "F", "S"]
        // Rotated to the calendar's own first weekday rather than assuming Sunday.
        let first = calendar.firstWeekday - 1
        return Array(symbols[first...] + symbols[..<first])
    }

    /// The month's days, padded at the front so the first lands under its weekday.
    private var days: [Date?] {
        guard let interval = calendar.dateInterval(of: .month, for: visibleMonth),
              let count = calendar.dateComponents([.day], from: interval.start, to: interval.end).day
        else { return [] }

        let weekday = calendar.component(.weekday, from: interval.start)
        let leading = (weekday - calendar.firstWeekday + 7) % 7

        return Array(repeating: nil, count: leading)
            + (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: interval.start) }
    }

    /// Which days the current selection covers. One for a day, the whole Monday-to-Sunday
    /// week for a week -- so touching a Wednesday shows the week that Wednesday is in
    /// rather than the seven days ending on it.
    private var selectedInterval: DateInterval? {
        highlightsWholeWeek
            ? calendar.dateInterval(of: .weekOfYear, for: selection)
            : DateInterval(start: calendar.startOfDay(for: selection), duration: 1)
    }

    private func dayCell(_ day: Date) -> some View {
        let isSelected = selectedInterval.map { $0.contains(calendar.startOfDay(for: day)) } ?? false
        let isToday = calendar.isDateInToday(day)
        let isFuture = calendar.startOfDay(for: day) > calendar.startOfDay(for: Date())

        return Button {
            selection = calendar.startOfDay(for: day)
        } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(.subheadline, design: .default, weight: isSelected ? .bold : .regular))
                .foregroundStyle(
                    isFuture
                    ? LocktyColors.tertiaryText
                    : (isSelected ? LocktyColors.onPrimary : LocktyColors.primaryText)
                )
                .monospacedDigit()
                .frame(maxWidth: .infinity)
                .frame(height: 42)
                .background {
                    // A week is one continuous block, not seven separate marks. Square
                    // ends inside it and rounded ones at the edges is what makes it read
                    // as a span rather than as a row of chosen days.
                    if isSelected {
                        weekBackground(for: day)
                    }
                }
                .overlay {
                    if isToday, !isSelected {
                        Capsule(style: .continuous)
                            .stroke(LocktyColors.primaryText.opacity(0.5), lineWidth: 1)
                    }
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 12, style: .continuous)))
        .tappable()
        .disabled(isFuture)
    }

    @ViewBuilder
    private func weekBackground(for day: Date) -> some View {
        if highlightsWholeWeek {
            let isStart = isEdge(day, leading: true)
            let isEnd = isEdge(day, leading: false)

            UnevenRoundedRectangle(
                topLeadingRadius: isStart ? 12 : 0,
                bottomLeadingRadius: isStart ? 12 : 0,
                bottomTrailingRadius: isEnd ? 12 : 0,
                topTrailingRadius: isEnd ? 12 : 0,
                style: .continuous
            )
            .fill(LocktyColors.primaryText)
        } else {
            Capsule(style: .continuous)
                .fill(LocktyColors.primaryText)
        }
    }

    /// Whether a day sits at an end of the block being drawn -- either an end of the week
    /// itself, or an end of the row, since a week that wraps has two of each.
    private func isEdge(_ day: Date, leading: Bool) -> Bool {
        guard let interval = calendar.dateInterval(of: .weekOfYear, for: selection) else { return true }
        let start = calendar.startOfDay(for: day)

        if leading {
            let weekStart = calendar.startOfDay(for: interval.start)
            return start == weekStart || calendar.component(.weekday, from: day) == calendar.firstWeekday
        }

        let weekEnd = calendar.date(byAdding: .day, value: -1, to: interval.end).map(calendar.startOfDay(for:))
        let lastWeekday = (calendar.firstWeekday + 5) % 7 + 1
        return start == weekEnd || calendar.component(.weekday, from: day) == lastWeekday
    }
}
