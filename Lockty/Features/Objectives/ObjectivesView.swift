import SwiftUI

/// Everything you meant to do, and how far along each one is.
///
/// A page rather than a sheet: it is a list you come back to through the day, and the way
/// you add to an objective is by tapping it here.
struct ObjectivesView: View {
    @ObservedObject var viewModel: ObjectivesViewModel
    @ObservedObject var router: AppRouter
    /// One to open singled out, when the screen was reached by tapping its name on Today.
    ///
    /// Read once, on the way in. It seeds the focus rather than holding it, so tapping the
    /// pill again still puts the page back to all of them.
    var initialFocus: UUID?

    /// Which period is being read. The same control the usage screen has, for the same
    /// reason: "eight glasses a day" and "three sessions a week" are two different
    /// questions, and a single list mixes an afternoon's work with a fortnight's.
    @State private var period: ObjectivePeriod = .daily
    /// The objective being read on its own, if one is.
    ///
    /// The same gesture the score pills have: tapping one singles it out, the others go
    /// behind a blur, and everything under them becomes about the one you picked. Tapping
    /// it again puts the page back.
    @State private var focusedID: UUID?
    /// How far back the charts look.
    ///
    /// Its own control, deliberately. The segment at the top of the screen says *which
    /// objectives* -- the ones counted by the day, the week, the month -- and a chart's
    /// range is a different question entirely: how much of the past you want to see. They
    /// were the same control until now, which is why neither of them read as anything.
    @State private var chartRange: ChartRange = .week
    /// Which day, week or month is on screen.
    ///
    /// The same control the usage screen has, for the same reason: this page was fixed to
    /// now, so there was no way to look at how last week went. Marking is only ever
    /// possible on the current one -- you cannot go back and drink Tuesday's water.
    @State private var anchorDay: Date = Date()
    @State private var isChoosingDate = false

    private enum ChartRange: String, CaseIterable, Identifiable {
        case week
        case month
        case all

        var id: String { rawValue }

        var title: String {
            switch self {
            case .week: "Week"
            case .month: "Month"
            case .all: "All"
            }
        }

        /// How many days it draws. "All" is the whole history there is -- ninety days,
        /// which is as far back as the progress file keeps.
        var days: Int {
            switch self {
            case .week: 7
            case .month: 30
            case .all: 90
            }
        }
    }
    @Environment(\.colorScheme) private var colorScheme

    private var focused: Objective? {
        focusedID.flatMap { id in viewModel.objectives.first { $0.id == id } }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                header

                if viewModel.objectives.isEmpty {
                    empty
                } else if inPeriod.isEmpty {
                    Text("Nothing counted \(period.pickerTitle.lowercased()).")
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, LocktySpacing.lg)
                } else {
                    // Outside the branch below, and deliberately. The row used to be
                    // written once inside each side of the `if`, which makes it two
                    // different rows as far as the view is concerned: singling one out
                    // tore the pills down and built them again, so they faded out and in,
                    // lost the blur they were meant to animate, and forgot how far along
                    // the row you had scrolled. Written once, they stay put and only the
                    // dimming moves.
                    pills

                    // What changes is underneath: the whole period, or the one objective.
                    if let focused {
                        focusedDetail(focused)
                            .transition(.blurReplace)
                    } else {
                        VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                            // How it has actually been going, one column per period. On
                            // every segment: the figure at the top of the screen is today,
                            // and this is the fortnight behind it.
                            completionsChart

                            // Still to do first, done underneath: the same shape the usage
                            // screen uses for its apps, because it answers the same kind of
                            // question -- what is left, and what is already behind you.
                            // "Still to do" only while there is still time to do it. On a
                            // day, week or month that is over, nothing is pending -- it
                            // was not done, and saying otherwise invites you to go and
                            // tick something you cannot tick.
                            section(
                                isCurrentPeriod ? "Still to do" : "Not done",
                                objectives: inPeriod.filter { !viewModel.isComplete($0, on: anchorDay) }
                            )
                            section("Done", objectives: inPeriod.filter { viewModel.isComplete($0, on: anchorDay) })
                        }
                        .transition(.blurReplace)
                    }
                }

            }
            .padding(.horizontal, LocktySpacing.tabInset)
            .padding(.vertical, LocktySpacing.lg)
        }
        // Pinned above the content, exactly as the usage screen pins its own: the
        // segment decides what the list *is*, so it stays put while the list scrolls
        // under it rather than scrolling away with the thing it is choosing.
        .customSafeAreaBar(edge: .top, spacing: 0) {
            if !viewModel.objectives.isEmpty {
                periodPicker
                    .padding(.horizontal, LocktySpacing.tabInset)
                    .padding(.bottom, LocktySpacing.md)
            }
        }
        .locktyScreenBackground()
        // No title. The bar carries which day, week or month is being read -- the same
        // control the usage screen has, because it answers the same question and the word
        // "Objectives" was the one thing on this screen nobody needed telling.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Button {
                    isChoosingDate = true
                } label: {
                    HStack(spacing: LocktySpacing.xs) {
                        Text(dateTitle)
                            .font(.system(.headline, design: .default, weight: .semibold))
                            .foregroundStyle(LocktyColors.primaryText)
                            .contentTransition(.numericText())

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(LocktyColors.secondaryText)
                    }
                    .padding(.horizontal, LocktySpacing.md)
                    .frame(height: 36)
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
                .tappable()
            }
        }
        .sheet(isPresented: $isChoosingDate) {
            UsagePeriodPickerSheet(period: usagePeriod, selection: $anchorDay)
        }
        // In the bar rather than as a tile at the foot of the list. A new objective is
        // an action on this screen, not the last item of what is on it -- and the tile
        // moved further down every time an objective was added.
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                // A pencil while one objective is singled out, a plus otherwise: the bar
                // acts on whatever the screen is currently about.
                Button {
                    router.presentSheet(.objectiveEditor(focusedID))
                } label: {
                    Image(systemName: focusedID == nil ? "plus" : "pencil")
                        .fontWeight(.light)
                        .foregroundStyle(LocktyColors.primaryText)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
            }
        }
        .task {
            viewModel.load()

            // The one that was tapped on Today, singled out on arrival -- and the period
            // moved to the one it is counted in, so a weekly objective is not opened onto
            // a list it is not in.
            if let initialFocus, let objective = viewModel.objectives.first(where: { $0.id == initialFocus }) {
                period = objective.period
                focusedID = objective.id
            }
        }
        // Anything saved or deleted in the sheet lands here when it closes.
        .onChange(of: router.sheet) { _, newValue in
            guard newValue == nil else { return }

            // What was there before the sheet opened, so a new one can be told from an
            // edit: the list has not been reloaded while the sheet was up, so this is
            // still the set the screen was showing when it was opened.
            let existing = Set(viewModel.objectives.map(\.id))
            viewModel.load()

            guard let created = viewModel.objectives.first(where: { !existing.contains($0.id) }) else { return }

            // Straight to the one just made: the period it is counted in, then the
            // objective itself singled out, which the row above scrolls to. Making
            // something and being returned to a list where it is off-screen -- or not in
            // the segment you are looking at -- is being made to go and find your own work.
            period = created.period

            Task { @MainActor in
                // A beat for the row to be rebuilt around the new period. Asking the
                // scroll for a pill that is not laid out yet is asking for nothing.
                try? await Task.sleep(for: .milliseconds(60))
                withAnimation(.smooth(duration: 0.38)) {
                    focusedID = created.id
                }
            }
        }

    }

    /// The big figure. "Yes" once it is done, "Not yet" while the period is still running,
    /// and "No" for one that ended without it -- a period that is over cannot be "not yet".
    private func headlineValue(_ objective: Objective) -> String {
        guard objective.isYesNo else {
            return objective.format(viewModel.value(of: objective, on: anchorDay))
        }

        if viewModel.isComplete(objective, on: anchorDay) { return "Yes" }
        return isCurrentPeriod ? "Not yet" : "No"
    }

    /// The period as the picker understands it. The two enums say the same three things.
    private var usagePeriod: UsagePeriod {
        switch period {
        case .daily: .day
        case .weekly: .week
        case .monthly: .month
        }
    }

    /// "Today", "This week", "September" -- what is being read, in the bar.
    private var dateTitle: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current

        switch period {
        case .daily:
            if calendar.isDateInToday(anchorDay) { return "Today" }
            if calendar.isDateInYesterday(anchorDay) { return "Yesterday" }
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
            return formatter.string(from: anchorDay)

        case .weekly:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: anchorDay) else { return "This week" }
            if interval.contains(Date()) { return "This week" }
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
            let end = calendar.date(byAdding: .day, value: 6, to: interval.start) ?? interval.end
            return "\(formatter.string(from: interval.start)) – \(formatter.string(from: end))"

        case .monthly:
            if calendar.isDate(anchorDay, equalTo: Date(), toGranularity: .month) { return "This month" }
            formatter.setLocalizedDateFormatFromTemplate("MMMM")
            return formatter.string(from: anchorDay)
        }
    }

    /// Whether the screen is on the period we are actually living in.
    ///
    /// Everything that writes is off unless it is: an objective is kept in its period, and
    /// marking last Tuesday's water today would be writing down something that did not
    /// happen when it says it did.
    private var isCurrentPeriod: Bool {
        let calendar = Calendar.current
        return switch period {
        case .daily: calendar.isDateInToday(anchorDay)
        case .weekly: calendar.isDate(anchorDay, equalTo: Date(), toGranularity: .weekOfYear)
        case .monthly: calendar.isDate(anchorDay, equalTo: Date(), toGranularity: .month)
        }
    }

    /// The objectives counted in the period on screen.
    private var inPeriod: [Objective] {
        viewModel.objectives.filter { $0.period == period }
    }

    private var completedInPeriod: Int {
        inPeriod.filter { viewModel.isComplete($0, on: anchorDay) }.count
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.xs) {
            Text(inPeriod.isEmpty ? "--" : "\(completedInPeriod) of \(inPeriod.count)")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(
                    !inPeriod.isEmpty && completedInPeriod == inPeriod.count
                        ? LocktyColors.productive
                        : LocktyColors.primaryText
                )
                .monospacedDigit()
                .locktyNumericTransition(trigger: completedInPeriod)

            Text("done \(period.currentTitle)")
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .id(period)
                .transition(.blurReplace)
        }
    }

    /// Day, week, month -- the periods an objective can be counted in.
    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(ObjectivePeriod.allCases) { option in
                Button {
                    withAnimation(.snappy(duration: 0.28)) {
                        period = option
                        // And nothing singled out. The focus belongs to an objective in
                        // the list you were reading; carrying it into another segment left
                        // the pills blurred behind an objective that is not even in them.
                        focusedID = nil
                    }
                } label: {
                    Text(option.pickerTitle)
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(period == option ? LocktyColors.primaryText : LocktyColors.secondaryText)
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
                .tappable()
                .background {
                    if period == option {
                        Capsule(style: .continuous)
                            .fill(LocktyColors.ink(0.08))
                    }
                }
            }
        }
        .padding(3)
        .safeGlass(radius: 999, interactive: true)
    }

    /// How many of these were finished in each period behind us.
    ///
    /// The same chart the usage screen draws for screen time, from the same component --
    /// a run of columns with a scale, which is what "how has it been going" looks like.
    ///
    /// It follows the segment above it. It used to be drawn only on the weekly and
    /// monthly tabs and always from the *daily* objectives, so the one place it appeared
    /// was the one place it was answering a different question than the one being asked.
    @ViewBuilder
    private var completionsChart: some View {
        let values = viewModel.completions(period: period, days: chartRange.days, endingOn: anchorDay)

        if values.contains(where: { $0.value > 0 }) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                HStack(spacing: LocktySpacing.sm) {
                    Text(completionsChartTitle)
                        .locktyEyebrow()

                    Spacer(minLength: LocktySpacing.sm)

                    rangePicker
                }

                // What the chart is counting, said once. It is the only figure on this
                // screen that is about all the objectives at once rather than one of them,
                // and a bare column of numbers under a heading of two words was leaving
                // people to work that out.
                Text(completionsChartSubtitle)
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                LocktyTrendChart(
                    points: points(from: values, period: period),
                    tint: LocktyColors.productive,
                    format: { "\(Int($0.rounded()))" },
                    height: 150
                )

                // A line under it: what follows is about single objectives again, and
                // without it the first row read as part of the chart.
                Divider()
                    .overlay(LocktyColors.separator.opacity(0.45))
                    .padding(.top, LocktySpacing.sm)
            }
            .transition(.blurReplace)
        }
    }

    /// What the chart counts, in a sentence.
    private var completionsChartSubtitle: String {
        let total = inPeriod.count
        let noun = total == 1 ? "objective" : "objectives"

        return switch period {
        case .daily: "How many of your \(total) daily \(noun) you finished on each day."
        case .weekly: "How many of your \(total) weekly \(noun) you finished in each week."
        case .monthly: "How many of your \(total) monthly \(noun) you finished in each month."
        }
    }

    private var completionsChartTitle: String {
        switch period {
        case .daily: "DONE EACH DAY"
        case .weekly: "DONE EACH WEEK"
        case .monthly: "DONE EACH MONTH"
        }
    }

    /// A run of daily figures as chart points, with the ends and the middle named.
    private func points(
        from values: [(date: Date, value: Double)],
        period: ObjectivePeriod = .daily
    ) -> [LocktyTrendChart.Point] {
        let named = Set([0, values.count / 2, values.count - 1])

        return values.enumerated().map { index, entry in
            LocktyTrendChart.Point(
                id: index,
                value: entry.value,
                label: named.contains(index) ? Self.label(entry.date, period: period) : nil,
                caption: Self.caption(entry.date, period: period)
            )
        }
    }

    /// What a column is called. A weekday for a day, the date it starts for a week, the
    /// month's name for a month -- "Mon" over a column standing for September would be a
    /// label about the wrong thing entirely.
    private static func label(_ date: Date, period: ObjectivePeriod) -> String {
        switch period {
        case .daily: weekdayFormatter.string(from: date)
        case .weekly: weekStartFormatter.string(from: date)
        case .monthly: monthFormatter.string(from: date)
        }
    }

    private static func caption(_ date: Date, period: ObjectivePeriod) -> String {
        switch period {
        case .daily: captionFormatter.string(from: date)
        case .weekly: "Week of \(captionFormatter.string(from: date))"
        case .monthly: monthCaptionFormatter.string(from: date)
        }
    }

    private static let weekStartFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()

    private static let monthFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMM")
        return formatter
    }()

    private static let monthCaptionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("MMMM yyyy")
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private static let captionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
    }()

    /// Everything about the one objective being read.
    ///
    /// It replaces the list rather than being added under it, which is the point of the
    /// gesture: the page is about one thing now, and the pills above are how you get back.
    @ViewBuilder
    private func focusedDetail(_ objective: Objective) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.xl) {
            VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                Text(headlineValue(objective))
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(tint(objective))
                    .monospacedDigit()
                    .locktyNumericTransition(trigger: viewModel.value(of: objective, on: anchorDay))

                // A yes or a no has no target to be "of", and no period to be said either
                // -- the bar above already says which day is being read. The figure is the
                // answer and the line under it is the question; "Not yet of Yes this
                // month" was neither.
                Text(
                    objective.isYesNo
                        ? objective.name
                        : "of \(objective.format(objective.target)) · \(objective.name)"
                )
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            markControl(objective)

            let values = viewModel.dailyValues(of: objective, days: chartRange.days, endingOn: anchorDay)

            if values.contains(where: { $0.value > 0 }) {
                VStack(alignment: .leading, spacing: LocktySpacing.md) {
                    HStack(spacing: LocktySpacing.sm) {
                        Text("DAY BY DAY")
                            .locktyEyebrow()

                        Spacer(minLength: LocktySpacing.sm)

                        rangePicker
                    }

                    LocktyTrendChart(
                        points: points(from: values),
                        tint: tint(objective),
                        format: { objective.format($0) },
                        height: 160
                    )
                }
            }

            let streaks = viewModel.streaks(of: objective)

            VStack(spacing: 0) {
                figureRow(
                    "Kept",
                    value: "\(keptDays(objective, in: values)) of \(values.count) days"
                )

                Divider().overlay(LocktyColors.separator.opacity(0.45))

                figureRow(
                    "Streak",
                    value: streaks.current == 1 ? "1 day" : "\(streaks.current) days"
                )

                Divider().overlay(LocktyColors.separator.opacity(0.45))

                figureRow(
                    "Longest streak",
                    value: streaks.longest == 1 ? "1 day" : "\(streaks.longest) days"
                )

                Divider().overlay(LocktyColors.separator.opacity(0.45))

                figureRow("Counted", value: objective.source.title)

                Divider().overlay(LocktyColors.separator.opacity(0.45))

                figureRow("Repeats", value: objective.period.title)
            }
            .padding(.horizontal, LocktySpacing.cardInset)
            .locktyCardBackground(cornerRadius: 26)
        }
        .transition(.blurReplace)
    }

    /// How many of the days on the chart reached the target.
    private func keptDays(_ objective: Objective, in values: [(date: Date, value: Double)]) -> Int {
        values.filter { $0.value >= objective.target }.count
    }

    private func figureRow(_ title: String, value: String) -> some View {
        HStack(spacing: LocktySpacing.md) {
            Text(title)
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            Spacer(minLength: LocktySpacing.sm)

            Text(value)
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(minHeight: 56)
    }

    /// Week, month, or everything there is -- for whichever chart is on screen.
    ///
    /// Small and beside the heading rather than a bar of its own: it belongs to the chart
    /// under it, not to the page.
    private var rangePicker: some View {
        HStack(spacing: 2) {
            ForEach(ChartRange.allCases) { range in
                Button {
                    withAnimation(.snappy(duration: 0.28)) { chartRange = range }
                } label: {
                    Text(range.title)
                        .font(.system(.caption, design: .default, weight: .semibold))
                        .foregroundStyle(chartRange == range ? LocktyColors.primaryText : LocktyColors.tertiaryText)
                        .padding(.horizontal, LocktySpacing.sm)
                        .frame(height: 28)
                        .background {
                            if chartRange == range {
                                Capsule(style: .continuous).fill(LocktyColors.ink(0.08))
                            }
                        }
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
                .tappable()
            }
        }
    }

    /// One heading and the objectives under it.
    @ViewBuilder
    private func section(_ title: String, objectives: [Objective]) -> some View {
        if !objectives.isEmpty {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                Text(title.uppercased())
                    .locktyEyebrow()

                VStack(spacing: 0) {
                    ForEach(Array(objectives.enumerated()), id: \.element.id) { index, objective in
                        if index > 0 {
                            Divider().overlay(LocktyColors.separator.opacity(0.45))
                        }

                        row(objective)
                    }
                }
            }
            .transition(.blurReplace)
        }
    }

    private var empty: some View {
        Text("Nothing set yet. Eight glasses a day, three sessions a week -- and a friction can ask whether you kept it.")
            .font(.system(.subheadline, design: .default, weight: .regular))
            .foregroundStyle(LocktyColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(LocktySpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .locktyCardBackground(cornerRadius: 26)
    }

    /// The objectives as pills, the way the day's three scores are.
    ///
    /// A tap adds a step -- that is the whole of logging a glass of water -- and a press
    /// and hold opens the objective itself. Not cards: a card is a thing you read, and
    /// these are things you press.
    private var pills: some View {
        // A reader around the row so singling one out can bring it into view. The pill you
        // pressed is usually on screen already, but the one arriving focused from Today --
        // or the sixth in a row of eight -- is not, and a screen that is entirely about an
        // objective you cannot see is a screen you have to go looking through.
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LocktySpacing.md) {
                    ForEach(inPeriod) { objective in
                        let isDimmed = focusedID != nil && focusedID != objective.id

                        Button {
                            withAnimation(.smooth(duration: 0.38)) {
                                focusedID = focusedID == objective.id ? nil : objective.id
                            }
                        } label: {
                            HStack(spacing: LocktySpacing.sm) {
                                Image(systemName: objective.symbolName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(tint(objective))

                                // A yes-or-no pill carries its name, not the word "Yes":
                                // whether it is lit is already the answer, and a pill reading
                                // "Not yet" says nothing about which objective it is.
                                Text(objective.isYesNo ? objective.name : objective.format(viewModel.value(of: objective, on: anchorDay)))
                                    .font(.system(size: 20, weight: .bold))
                                    .foregroundStyle(LocktyColors.primaryText)
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .contentTransition(.numericText())
                            }
                            .padding(.horizontal, LocktySpacing.lg)
                            .frame(height: 48)
                            .background { pillSurface(objective) }
                            .compositingGroup()
                            .contentShape(Capsule(style: .continuous))
                        }
                        // Blur and size, not opacity: a faded pill looks switched off, where
                        // a blurred one looks behind -- which is what it is, since it is still
                        // there and still tappable.
                        //
                        // The animation is attached only while something is singled out. With
                        // nothing focused these are just pills in a row, and an animation
                        // hanging off them made the first draw of the screen arrive in a
                        // little jump of its own.
                        .blur(radius: isDimmed ? 4.5 : 0)
                        .scaleEffect(isDimmed ? 0.9 : 1)
                        .animation(focusedID == nil ? nil : .smooth(duration: 0.38), value: focusedID)
                        .buttonStyle(.locktyInteractive(brighten: true))
                        .tappable()
                        // Hold to open it. Simultaneous, because a `Button` claims the press:
                        // a long-press modifier wrapped around one never fires.
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.35)
                                .onEnded { _ in router.presentSheet(.objectiveEditor(objective.id)) }
                        )
                        // Its place in the row, for the reader above: scrolling to a
                        // pill needs the pill findable by the objective's own id.
                        .id(objective.id)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            .animation(.smooth(duration: 0.3), value: completedInPeriod)
            // Centred, not merely made visible: the one being read belongs in the middle
            // of the row, with the ones behind the blur either side of it.
            .onChange(of: focusedID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.smooth(duration: 0.38)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
            // Arriving already focused, from a name tapped on Today: in place from the
            // first frame rather than sliding there once the screen has settled.
            .onAppear {
                guard let focusedID else { return }
                proxy.scrollTo(focusedID, anchor: .center)
            }
        }
    }

    private func tint(_ objective: Objective) -> Color {
        // A ceiling that has been gone past is the one objective that turns red: it is
        // the only one that can be lost rather than simply not yet won.
        if objective.staysUnder, !viewModel.isComplete(objective, on: anchorDay) {
            return LocktyColors.unproductive
        }
        return LocktyColors.routine(objective.color)
    }

    /// "1,242 of 8,000 steps", and for a ceiling the same shape read the other way --
    /// "18 of 30 min" is how much of the allowance is gone.
    /// The figure alone. What it is measured in, and what it is measured against, are
    /// said once in the caption under the name.
    private func rowValue(_ objective: Objective) -> String {
        objective.formatNumber(viewModel.value(of: objective, on: anchorDay))
    }

    /// The pill's body, built the way the day's three scores are: a blurred copy of the
    /// shape behind it so the light comes off the pill rather than sitting behind it as a
    /// square of colour, the ground pressed in at the rim, and the rim itself drawn to
    /// how far along the objective is.
    ///
    /// The rim is the reading. A pill that is a quarter drawn is a quarter done, which is
    /// the same sentence the score pills make -- and it is why these are pills at all.
    private func pillSurface(_ objective: Objective) -> some View {
        let shape = Capsule(style: .continuous)
        let colour = tint(objective)
        let isDark = colorScheme == .dark
        let progress = max(viewModel.fraction(of: objective, on: anchorDay), 0.02)

        return ZStack {
            // Outside: the bloom.
            if isDark {
                shape
                    .fill(colour)
                    .blur(radius: 14)
                    .opacity(0.55)
                    .blendMode(.plusLighter)
                    .padding(-2)
            } else {
                ZStack {
                    shape.fill(.white).blur(radius: 12)
                    shape.fill(colour).blur(radius: 16).opacity(0.18)
                }
                .padding(-2)
            }

            // The body: nearly the ground it sits on, lifted a little in the middle.
            shape
                .fill(colour.opacity(isDark ? 0.14 : 0.10))
                .background {
                    shape.fill(isDark ? LocktyColors.background : LocktyColors.cardSurface)
                }
                .overlay {
                    shape
                        .stroke(LocktyColors.background, lineWidth: 10)
                        .blur(radius: 6)
                        .mask { shape }
                }

            // The rim: the track, the light coming off what is earned, and the arc.
            shape
                .stroke(LocktyColors.ink(0.10), lineWidth: 2)

            shape
                .trim(from: 0, to: progress)
                .stroke(colour, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .blur(radius: 4)
                .opacity(isDark ? 1 : 0.55)
                .blendMode(isDark ? .plusLighter : .normal)

            shape
                .trim(from: 0, to: progress)
                .stroke(colour, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
        .animation(.smooth(duration: 0.6), value: progress)
    }

//  /// One objective, the way an app reads on the usage screen: glyph, name, a bar of how
//  /// far along, and the figure in its own units -- 3,000 steps rather than minutes.
//  ///
//  /// Tapping a row opens the objective. The pills above are where a glass of water gets
//  /// logged -- they are small, they are at the top, and that is all they do -- so the
//  /// list underneath is free to behave like every other list in the app, where tapping
//  /// a thing shows you the thing.
//  private func row(_ objective: Objective) -> some View {
//      // The row and the mark are two controls, not one. A button inside a button is a
//      // tap the outer one takes, which is why marking something used to mean opening
//      // the sheet first -- the same reason a menu on a rule hangs off the element at the
//      // end of the row rather than off the row itself.
//      HStack(spacing: LocktySpacing.sm) {
//          rowBody(objective)
//
//          markButton(objective)
//      }
//  }
//
//  private func rowBody(_ objective: Objective) -> some View {
//      Button {
//          router.presentSheet(.objectiveEditor(objective.id))
//      } label: {
//          HStack(alignment: .top, spacing: LocktySpacing.md) {
//              ObjectiveRing(
//                  symbolName: objective.symbolName,
//                  fraction: viewModel.fraction(of: objective, on: anchorDay),
//                  isComplete: viewModel.isComplete(objective, on: anchorDay),
//                  color: objective.color,
//                  side: 38,
//                  lineWidth: 3
//              )
//
//              VStack(alignment: .leading, spacing: 4) {
//                  Text(objective.name)
//                      .font(.system(.subheadline, design: .default, weight: .regular))
//                      .foregroundStyle(LocktyColors.primaryText)
//                      .lineLimit(1)
//
//                  // What is being aimed at, under the name. The target used to be said
//                  // beside the figure -- "11,840 steps of 10,000 steps" -- which is the
//                  // unit twice and a line too long to read at a glance. Here it is the
//                  // half that does not change, and the figure beside the bar is the half
//                  // that does.
//                  if !objective.goalCaption.isEmpty {
//                      Text(objective.goalCaption)
//                          .font(.system(.footnote, design: .default, weight: .regular))
//                          .foregroundStyle(LocktyColors.tertiaryText)
//                          .lineLimit(1)
//                  }
//
//                  // A yes or a no has nothing to fill, and now nothing to say either:
//                  // the check at the end of the row is lit or it is not, which is the
//                  // whole answer. Where the bar would be there is space, so the ring
//                  // stays at the left and the check at the right, level with every
//                  // other row. The word it used to carry is kept below, not deleted.
//                  //
//                  //  Text(viewModel.isComplete(objective, on: anchorDay) ? "Yes" : "Not yet")
//                  //      .font(.system(.footnote, design: .default, weight: .semibold))
//                  //      .foregroundStyle(
//                  //          viewModel.isComplete(objective, on: anchorDay)
//                  //              ? LocktyColors.productive
//                  //              : LocktyColors.tertiaryText
//                  //      )
//                  //      .padding(.horizontal, LocktySpacing.md)
//                  //      .frame(height: 26)
//                  //      .background {
//                  //          Capsule(style: .continuous)
//                  //              .fill(
//                  //                  viewModel.isComplete(objective, on: anchorDay)
//                  //                      ? LocktyColors.productive.opacity(0.14)
//                  //                      : LocktyColors.ink(0.06)
//                  //              )
//                  //      }
//                  //      .frame(height: 18, alignment: .leading)
//                  //      .padding(.top, 4)
//                  if objective.isYesNo {
//                      Spacer(minLength: 0)
//                          .frame(height: 18)
//                  } else {
//                  HStack(spacing: LocktySpacing.sm) {
//                      GeometryReader { proxy in
//                          let colour = tint(objective)
//
//                          Capsule(style: .continuous)
//                              .fill(
//                                  LinearGradient(
//                                      colors: [colour, colour.opacity(0.85), colour.opacity(0.25), colour.opacity(0)],
//                                      startPoint: .leading,
//                                      endPoint: .trailing
//                                  )
//                              )
//                              .frame(
//                                  width: max(proxy.size.width * viewModel.fraction(of: objective, on: anchorDay), 6),
//                                  height: 4
//                              )
//                              .blur(radius: 1.2)
//                              .animation(.smooth(duration: 0.5), value: viewModel.fraction(of: objective, on: anchorDay))
//                      }
//                      .frame(height: 4)
//
//                      Text(rowValue(objective))
//                          .font(.system(.subheadline, design: .default, weight: .regular))
//                          .foregroundStyle(tint(objective))
//                          .monospacedDigit()
//                          .contentTransition(.numericText())
//                          .fixedSize()
//                  }
//                  .frame(height: 18)
//                  }
//              }
//              .frame(maxWidth: .infinity, alignment: .leading)
//          }
//          .frame(minHeight: 52)
//          .contentShape(Rectangle())
//      }
//      .buttonStyle(.locktyInteractive(brighten: true))
//      .tappable()
//      // Holding a row adds a step, for the times you are already looking at the list
//      // and do not want the sheet for one glass.
//      .simultaneousGesture(
//          LongPressGesture(minimumDuration: 0.35)
//              .onEnded { _ in viewModel.advance(objective) }
//      )
//  }

    /// One objective: what it is on the first line, how far along on the second.
    ///
    /// The mark button used to sit at the end of the bar, which is where the figure goes
    /// -- so the two of them shared one short line with a bar squeezed between them, and
    /// the button read as something stuck on the end rather than part of the row. Here the
    /// row is two lines: the ring, the name and the button, and under them the bar with
    /// the figure at its end. The button is level with the whole row instead of with one
    /// line of it, and the bar gets the width back.
    ///
    /// Tapping the row opens the objective; the button beside it logs. Two controls, not
    /// one: a button inside a button is a tap the outer one takes.
    ///
    /// The previous version is kept above, commented.
    private func row(_ objective: Objective) -> some View {
        HStack(alignment: .center, spacing: LocktySpacing.sm) {
            rowBody(objective)

            markButton(objective)
        }
        // Room of its own between one objective and the next, with the divider the list
        // draws between them sitting in the middle of it.
        .padding(.vertical, LocktySpacing.sm)
    }

    private func rowBody(_ objective: Objective) -> some View {
        Button {
            router.presentSheet(.objectiveEditor(objective.id))
        } label: {
            HStack(alignment: .center, spacing: LocktySpacing.md) {
                ObjectiveRing(
                    symbolName: objective.symbolName,
                    fraction: viewModel.fraction(of: objective, on: anchorDay),
                    isComplete: viewModel.isComplete(objective, on: anchorDay),
                    color: objective.color,
                    side: 44,
                    lineWidth: 3
                )

                VStack(alignment: .leading, spacing: 4) {
                    Text(objective.name)
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)

                    // What is being aimed at, under the name. The target used to be said
                    // beside the figure -- "11,840 steps of 10,000 steps" -- which is the
                    // unit twice and a line too long to read at a glance. Here it is the
                    // half that does not change, and the figure at the end of the bar is
                    // the half that does.
                    if !objective.goalCaption.isEmpty {
                        Text(objective.goalCaption)
                            .font(.system(.footnote, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.tertiaryText)
                            .lineLimit(1)
                    }

                    // A yes or a no has nothing to fill: the check at the end of the row
                    // is lit or it is not, which is the whole answer.
                    if !objective.isYesNo {
                        progressLine(objective)
                            .padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
        // Holding a row adds a step, for the times you are already looking at the list
        // and do not want the sheet for one glass.
        .simultaneousGesture(
            LongPressGesture(minimumDuration: 0.35)
                .onEnded { _ in
                    guard isCurrentPeriod else { return }
                    viewModel.advance(objective)
                }
        )
    }

    /// The bar and the figure at the end of it, on a line of their own.
    private func progressLine(_ objective: Objective) -> some View {
        HStack(spacing: LocktySpacing.sm) {
            GeometryReader { proxy in
                let colour = tint(objective)

                ZStack(alignment: .leading) {
                    // A track under it, the full width of the line. Without one the bar
                    // stopped wherever the objective had got to and the figure sat on its
                    // own at the far right with nothing between them -- two things on one
                    // line rather than the two ends of one reading.
                    Capsule(style: .continuous)
                        .fill(LocktyColors.ink(0.08))
                        .frame(height: 4)

                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [colour, colour.opacity(0.85), colour.opacity(0.25), colour.opacity(0)],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(
                            width: max(proxy.size.width * viewModel.fraction(of: objective, on: anchorDay), 6),
                            height: 4
                        )
                        .blur(radius: 1.2)
                        .animation(.smooth(duration: 0.5), value: viewModel.fraction(of: objective, on: anchorDay))
                }
                .frame(height: proxy.size.height, alignment: .center)
            }
            .frame(height: 10)

            Text(rowValue(objective))
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(tint(objective))
                .monospacedDigit()
                .contentTransition(.numericText())
                .fixedSize()
        }
        .frame(height: 18)
    }

    /// Logging it here, on the objective's own screen.
    ///
    /// The screen you reach by tapping its pill is where you are already looking at the
    /// one objective, and having to open the editing sheet from there to add a glass of
    /// water is being sent somewhere else to do the thing you came for.
    ///
    /// A minus and a plus either side of the step, or a single switch for a yes and a no.
    /// Nothing for steps and sleep: those are read, not written.
    @ViewBuilder
    private func markControl(_ objective: Objective) -> some View {
        if !objective.source.isMeasured, isCurrentPeriod {
            let isDone = viewModel.isComplete(objective, on: anchorDay)
            let colour = tint(objective)

            if objective.isYesNo {
                HStack(spacing: LocktySpacing.md) {
                    // The switch and nothing beside it. It reads "Yes" or "No" on its own
                    // face, and the figure above it already says which -- a caption saying
                    // it a third time was the same answer three times over.
                    LocktySwitch(
                        isOn: Binding(
                            get: { isDone },
                            set: { isOn in
                                if isOn { viewModel.complete(objective) } else { viewModel.reset(objective) }
                            }
                        )
                    )

                    Spacer(minLength: 0)
                }
            } else {
                HStack(spacing: LocktySpacing.md) {
                    stepButton("minus", tint: colour) { viewModel.stepBack(objective) }

                    stepButton("plus", tint: colour) { viewModel.advance(objective) }

                    Spacer(minLength: 0)

                    // The whole thing at once, for the objective you did not tap out one
                    // at a time. Held rather than tapped: it is a claim about the period.
                    LocktyHoldButton(
                        title: isDone ? "Hold to clear" : "Hold to mark as done",
                        systemImage: isDone ? "arrow.uturn.backward" : "checkmark",
                        tint: colour
                    ) {
                        if isDone { viewModel.reset(objective) } else { viewModel.complete(objective) }
                    }
                    .frame(maxWidth: 220)
                }
            }
        }
    }

    /// The height everything on the marking row stands at.
    ///
    /// `LocktyHoldButton`'s own height. The circles are square, so this is their side as
    /// well -- they were 48 beside a 60 and read as two rows of controls that happened to
    /// be on one line.
    private var markControlHeight: CGFloat { 60 }

    private func stepButton(
        _ systemImage: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 19, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)
                .frame(width: markControlHeight, height: markControlHeight)
                .background { Circle().fill(tint.opacity(0.16)) }
                .contentShape(Circle())
        }
        .buttonStyle(.locktyInteractive(shape: Circle()))
        .tappable()
    }

    /// Marking it, from the list.
    ///
    /// A plus for the ones you count -- one press, one glass -- and a check for the ones
    /// that are simply done, which fills or empties. Nothing at all for steps and sleep:
    /// Health counts those, and a button that writes down a number you did not walk is a
    /// button that lies.
    ///
    /// Held rather than tapped for the whole thing: a press adds a step, a press and hold
    /// fills it to the target, which is the objective you did all at once and are not
    /// going to tap out eight times.
    @ViewBuilder
    private func markButton(_ objective: Objective) -> some View {
        if !objective.source.isMeasured, isCurrentPeriod {
            let isDone = viewModel.isComplete(objective, on: anchorDay)
            let colour = tint(objective)

            Button {
                if objective.isYesNo {
                    if isDone { viewModel.reset(objective) } else { viewModel.complete(objective) }
                } else {
                    // A plus goes on being a plus after the target is met. Fifteen glasses
                    // is what you meant to drink, and the twentieth still happened -- a
                    // button that turned into an undo the moment you got there had no way
                    // to say so.
                    viewModel.advance(objective)
                }
            } label: {
                // Built as the ring across from it is built, and at the same size: a thin
                // circle with a glyph inside, lit in the objective's colour once it is
                // done. It used to be a filled disc of colour, which is a heavier object
                // than anything else in the row -- a button dropped on the end rather than
                // the other end of the same row.
                Image(systemName: objective.isYesNo ? "checkmark" : "plus")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(isDone ? colour : LocktyColors.secondaryText)
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 44, height: 44)
                    .background {
                        ZStack {
                            Circle().stroke(LocktyColors.ink(0.10), lineWidth: 3)

                            // Once it is done the circle closes in the objective's colour,
                            // exactly as the ring beside it does.
                            if isDone {
                                Circle()
                                    .stroke(colour, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .blur(radius: 3.5)
                                    .opacity(colorScheme == .dark ? 1 : 0.5)
                                    .blendMode(colorScheme == .dark ? .plusLighter : .normal)

                                Circle()
                                    .stroke(colour, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            }
                        }
                    }
                    .contentShape(Circle())
            }
            .buttonStyle(.locktyInteractive(shape: Circle()))
            .tappable()
            // Held: straight to the target, or back to nothing if it is already there.
            // Undoing has to live somewhere, and it is not the tap that logs.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4)
                    .onEnded { _ in
                        guard !objective.isYesNo else { return }
                        if isDone { viewModel.reset(objective) } else { viewModel.complete(objective) }
                    }
            )
            .animation(.smooth(duration: 0.3), value: isDone)
        }
    }
}

/// An objective's glyph inside a ring that fills as it is met.
struct ObjectiveRing: View {
    let symbolName: String
    let fraction: Double
    let isComplete: Bool
    /// The objective's own colour. The ring wears it whether or not it is finished --
    /// what says "done" is the ring being closed.
    var color: RoutineColor = .mint

    var side: CGFloat = 38
    var lineWidth: CGFloat = 3

    @Environment(\.colorScheme) private var colorScheme

    private var tint: Color {
        LocktyColors.routine(color)
    }

    var body: some View {
        let isDark = colorScheme == .dark

        return ZStack {
            Circle()
                .stroke(LocktyColors.ink(0.10), lineWidth: lineWidth)

            Circle()
                .trim(from: 0, to: max(fraction, 0.01))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .blur(radius: 3.5)
                .opacity(isDark ? 1 : 0.5)
                .blendMode(isDark ? .plusLighter : .normal)

            Circle()
                .trim(from: 0, to: max(fraction, 0.01))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
        }
        .rotationEffect(.degrees(-90))
        .frame(width: side, height: side)
        // The objective's glyph, finished or not. A tick in its place said "done" twice
        // -- the ring is already closed -- and took away the one mark that says *which*
        // objective this is.
        .overlay {
            Image(systemName: symbolName)
                .font(.system(size: side * 0.36, weight: .medium))
                .foregroundStyle(tint)
        }
        .animation(.smooth(duration: 0.45), value: fraction)
    }
}
