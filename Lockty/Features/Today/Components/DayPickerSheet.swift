import SwiftUI

/// Picking the day Today is showing.
///
/// Laid out by hand rather than with a `DatePicker`: the graphical style brings its own
/// chrome, its own type and its own idea of a selection colour, none of which can be
/// made to match the rest of the app -- and none of which can be animated the way moving
/// between months should be.
struct DayPickerSheet: View {
    @Binding var selectedDay: Date
    @Environment(\.dismiss) private var dismiss

    /// The month on screen. Separate from the selection, because paging through months
    /// to look around should not change which day is chosen.
    @State private var visibleMonth: Date
    /// Which way the last move went, so the outgoing month leaves on the side the
    /// incoming one came from.
    @State private var travelDirection = 1

    private let calendar: Calendar
    private let today: Date

    init(selectedDay: Binding<Date>) {
        _selectedDay = selectedDay

        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "es_ES")
        // Monday first, as the rest of the app's schedule UI reads.
        calendar.firstWeekday = 2
        self.calendar = calendar

        today = calendar.startOfDay(for: Date())
        _visibleMonth = State(
            initialValue: calendar.startOfMonth(for: selectedDay.wrappedValue) ?? Date()
        )
    }

    var body: some View {
        LocktyDynamicSheet {
            VStack(spacing: LocktySpacing.lg) {
                monthHeader

                weekdayHeader

                // Clipped so a month sliding in from off-screen does not paint over the
                // header and the button while it travels.
                monthGrid
                    .frame(maxWidth: .infinity)
                    .clipped()

                PrimaryButton("Cerrar", systemImage: "xmark") {
                    dismiss()
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.top, LocktySpacing.md)
            .padding(.bottom, LocktySpacing.lg)
        }
        .locktyDynamicSheetSizes([.fit])
    }

    // MARK: - Header

    private var monthHeader: some View {
        HStack(spacing: LocktySpacing.md) {
            Text(monthTitle)
                .font(.system(.title3, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)
                // The name swaps rather than cross-fading in place, which would read as
                // the same word flickering when only the month changes.
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.28), value: monthTitle)

            Spacer(minLength: 0)

            monthStepButton(systemImage: "chevron.left", offset: -1)
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
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(LocktyColors.primaryText)
                .frame(width: 36, height: 36)
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

    private var monthGrid: some View {
        VStack(spacing: LocktySpacing.xs) {
            ForEach(weeks, id: \.first) { week in
                HStack(spacing: 0) {
                    ForEach(week, id: \.self) { date in
                        dayCell(for: date)
                    }
                }
            }
        }
        // Rebuilt as a whole when the month changes, so the transition below has
        // something to move rather than animating each cell's number in place.
        .id(visibleMonth)
        .transition(
            .asymmetric(
                insertion: .move(edge: travelDirection >= 0 ? .trailing : .leading)
                    .combined(with: .opacity),
                removal: .move(edge: travelDirection >= 0 ? .leading : .trailing)
                    .combined(with: .opacity)
            )
        )
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
                            Circle().fill(LocktyColors.primaryText)
                        } else if isToday {
                            Circle().stroke(LocktyColors.primaryText.opacity(0.35), lineWidth: 1)
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
        guard let next = calendar.date(byAdding: .month, value: offset, to: visibleMonth) else {
            return
        }

        travelDirection = offset
        withAnimation(.smooth(duration: 0.32)) {
            visibleMonth = next
        }
    }

    private var canMoveForward: Bool {
        guard let currentMonth = calendar.startOfMonth(for: today) else { return false }
        return visibleMonth < currentMonth
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale
        formatter.dateFormat = "LLLL yyyy"
        return formatter.string(from: visibleMonth).capitalized
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
    private var weeks: [[Date?]] {
        guard let range = calendar.range(of: .day, in: .month, for: visibleMonth),
              let firstOfMonth = calendar.startOfMonth(for: visibleMonth)
        else { return [] }

        let leadingBlanks = (calendar.component(.weekday, from: firstOfMonth)
            - calendar.firstWeekday + 7) % 7

        var cells: [Date?] = Array(repeating: nil, count: leadingBlanks)
        for dayOffset in 0..<range.count {
            cells.append(calendar.date(byAdding: .day, value: dayOffset, to: firstOfMonth))
        }
        while cells.count % 7 != 0 {
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
