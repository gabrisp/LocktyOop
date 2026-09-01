import SwiftUI

/// Picking the day Today is showing.
///
/// Laid out by hand rather than with a `DatePicker`: the graphical style brings its own
/// chrome, its own type and its own idea of a selection colour, none of which can be
/// made to match the rest of the app -- and none of which can be animated the way moving
/// between months should be.
struct DayPickerSheet: View {
    @Binding var selectedDay: Date

    /// The month on screen. Separate from the selection, because paging through months
    /// to look around should not change which day is chosen.
    ///
    /// Owned by the pager: it is the scroll position, so swiping and the chevrons move
    /// the same value and cannot disagree about where you are.
    @State private var visibleMonth: Date?

    private let calendar: Calendar
    private let today: Date

    init(selectedDay: Binding<Date>) {
        _selectedDay = selectedDay

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_US")
        // Monday first, as the rest of the app's schedule UI reads.
        calendar.firstWeekday = 2
        self.calendar = calendar

        today = calendar.startOfDay(for: Date())
        _visibleMonth = State(
            initialValue: calendar.startOfMonth(for: selectedDay.wrappedValue)
        )
    }

    var body: some View {
        LocktyDynamicSheet {
            VStack(spacing: LocktySpacing.lg) {
                monthHeader

                weekdayHeader

                // Clipped so a month sliding in from off-screen does not paint over the
                // header while it travels.
                monthGrid
                    .frame(maxWidth: .infinity)
                    .clipped()
            }
            .padding(.horizontal, LocktySpacing.md)
            // Twice the bottom's: the grabber sits above this one, and the month name is
            // the first thing on the sheet, so it needs the room to read as a heading
            // rather than as something pushed up against the edge.
            .padding(.top, 48)
            // No close button under the grid: picking a day is the answer, and the sheet
            // is dismissed the way every other one is.
            .padding(.bottom, 24)
        }
        .locktyDynamicSheetSizes([.fit])
    }

    // MARK: - Header

    /// The month between its two arrows: back on the left, forward on the right, and the
    /// name centred between them so it sits over the column of days it belongs to.
    private var monthHeader: some View {
        HStack(spacing: LocktySpacing.md) {
            monthStepButton(systemImage: "chevron.left", offset: -1, isDisabled: !canMoveBack)

            Text(monthTitle)
                .font(.system(.title3, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)
                .multilineTextAlignment(.center)
                .lineLimit(1)
                // The name swaps rather than cross-fading in place, which would read as
                // the same word flickering when only the month changes.
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.28), value: monthTitle)
                .frame(maxWidth: .infinity)

            monthStepButton(
                systemImage: "chevron.right",
                offset: 1,
                // Nothing to see past the current month: there is no usage recorded for
                // a day that has not happened.
                isDisabled: !canMoveForward
            )
        }
    }

    private func monthStepButton(
        systemImage: String,
        offset: Int,
        isDisabled: Bool = false
    ) -> some View {
        Button {
            move(by: offset)
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(LocktyColors.primaryText)
                .frame(width: 44, height: 44)
                .background(Circle().fill(LocktyColors.elevatedBackground))
        }
        .buttonStyle(.locktyInteractive(shape: Circle()))
        .tappable()
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.3 : 1)
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

    // MARK: - Grid

    /// Every month laid side by side, one page each.
    ///
    /// A pager rather than one grid swapped out on a transition: months are a line you
    /// move along, and being able to drag between them is how a calendar is expected to
    /// behave. The chevrons write the same scroll position the gesture does, so the two
    /// can never disagree about which month you are on.
    private var monthGrid: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 0) {
                    ForEach(months, id: \.self) { month in
                        grid(for: month)
                            .frame(width: proxy.size.width)
                            .id(month)
                    }
                }
                .scrollTargetLayout()
            }
            // .viewAligned, not .paging: paging snaps by the viewport's width and knows
            // nothing about the ids, so it fought `scrollPosition` -- a month could come
            // to rest between two pages, and a chevron writing the id landed off centre.
            // View alignment snaps to the pages themselves, which is what the id means.
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $visibleMonth, anchor: .center)
        }
        // Every month is padded to the same number of weeks, so this height holds for all
        // of them. Without it the sheet would grow and shrink mid-drag as a 5-week month
        // slid past a 6-week one.
        .frame(height: gridHeight)
    }

    private func grid(for month: Date) -> some View {
        VStack(spacing: LocktySpacing.xs) {
            ForEach(Array(weeks(of: month).enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, date in
                        dayCell(for: date)
                    }
                }
            }
        }
    }

    /// Six rows of cells plus the gaps between them. Fixed so the pager does not resize.
    private var gridHeight: CGFloat {
        CGFloat(Self.weekRows) * 38 + CGFloat(Self.weekRows - 1) * LocktySpacing.xs
    }

    @ViewBuilder
    private func dayCell(for date: Date?) -> some View {
        if let date {
            let isSelected = calendar.isDate(date, inSameDayAs: selectedDay)
            let isToday = calendar.isDate(date, inSameDayAs: today)
            let isFuture = date > today

            Button {
                withAnimation(.smooth(duration: 0.24)) {
                    selectedDay = date
                }
            } label: {
                Text("\(calendar.component(.day, from: date))")
                    .font(.system(.subheadline, design: .default, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(dayForeground(isSelected: isSelected, isToday: isToday))
                    .monospacedDigit()
                    .frame(width: 38, height: 38)
                    .background {
                        if isSelected {
                            // The day being shown: a filled circle.
                            Circle().fill(LocktyColors.primaryText)
                        } else if isToday {
                            // Today, when it is not the day being shown: the same white,
                            // but only as a ring. Filled versus outlined is what tells
                            // the two apart at a glance -- it used to be drawn at 0.35
                            // opacity, which read as no marker at all.
                            Circle().stroke(LocktyColors.primaryText.opacity(0.9), lineWidth: 1.5)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tappable()
            .disabled(isFuture)
            .opacity(isFuture ? 0.25 : 1)
        } else {
            // A day belonging to a neighbouring month. Drawn as space rather than as a
            // greyed-out number, so the weeks line up under the right columns without
            // offering anything to tap.
            Color.clear
                .frame(width: 38, height: 38)
                .frame(maxWidth: .infinity)
        }
    }

    private func dayForeground(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return Color(uiColor: .systemBackground) }
        if isToday { return LocktyColors.primaryText }
        return LocktyColors.secondaryText
    }

    // MARK: - Month arithmetic

    private func move(by offset: Int) {
        guard let current = resolvedVisibleMonth,
              let index = months.firstIndex(of: current)
        else { return }

        let target = index + offset
        guard months.indices.contains(target) else { return }

        // The same value the gesture sets, so a chevron and a swipe are the one movement.
        withAnimation(.smooth(duration: 0.32)) {
            visibleMonth = months[target]
        }
    }

    private var canMoveForward: Bool {
        guard let current = resolvedVisibleMonth, let index = months.firstIndex(of: current) else {
            return false
        }
        return index < months.count - 1
    }

    private var canMoveBack: Bool {
        guard let current = resolvedVisibleMonth, let index = months.firstIndex(of: current) else {
            return false
        }
        return index > 0
    }

    /// The month the pager is on, falling back to the current one before the first layout
    /// has reported a scroll position.
    private var resolvedVisibleMonth: Date? {
        visibleMonth ?? calendar.startOfMonth(for: today)
    }

    /// The months you can page through: a year back, up to this one.
    ///
    /// It stops at the current month because there is no usage recorded for a day that
    /// has not happened, so paging into the future would only ever show empty grids.
    private var months: [Date] {
        guard let thisMonth = calendar.startOfMonth(for: today) else { return [] }
        return (0...12)
            .reversed()
            .compactMap { calendar.date(byAdding: .month, value: -$0, to: thisMonth) }
    }

    private var monthTitle: String {
        guard let month = resolvedVisibleMonth else { return "" }
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: month).capitalized
    }

    private var weekdaySymbols: [String] {
        let symbols = calendar.veryShortStandaloneWeekdaySymbols
        // Rotated to start on the calendar's own first weekday rather than on Sunday,
        // which is the order the grid below is built in.
        let offset = calendar.firstWeekday - 1
        return Array(symbols[offset...] + symbols[..<offset]).map { $0.uppercased() }
    }

    /// The month laid out in weeks, with nil for the cells before the first and after the
    /// last day. Nils rather than the neighbouring month's dates: those days are not part
    /// of this month and tapping one would silently move the whole grid.
    /// Always six, so every page is the same height and the pager does not resize as it
    /// scrolls. A month needing five gets a blank row rather than a shorter grid.
    static let weekRows = 6

    private func weeks(of month: Date) -> [[Date?]] {
        guard let range = calendar.range(of: .day, in: .month, for: month),
              let firstOfMonth = calendar.startOfMonth(for: month)
        else { return [] }

        let leadingBlanks = (calendar.component(.weekday, from: firstOfMonth)
            - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for dayOffset in 0..<range.count {
            cells.append(calendar.date(byAdding: .day, value: dayOffset, to: firstOfMonth))
        }
        while cells.count < Self.weekRows * 7 {
            cells.append(nil)
        }

        return stride(from: 0, to: cells.count, by: 7).map {
            Array(cells[$0..<min($0 + 7, cells.count)])
        }
    }
}

private extension Calendar {
    func startOfMonth(for date: Date) -> Date? {
        self.date(from: dateComponents([.year, .month], from: date))
    }
}
