import SwiftUI

/// How the rules have actually been going.
///
/// The objectives screen, for rules: a date in the bar, a segment for the period, the
/// rules as pills, and whichever one you single out explained underneath. It is built the
/// same way on purpose -- the two answer the same kind of question, and a second screen
/// that answered it in a different shape would be a second thing to learn.
///
/// The headings are the kinds, not a state: a rule is not done or undone, it is a
/// schedule, a sitting, or a cap on the day.
struct RuleStatsView: View {
    @ObservedObject var viewModel: RuleStatsViewModel
    @ObservedObject var router: AppRouter

    @State private var period: UsagePeriod = .day
    @State private var focusedID: UUID?
    @State private var anchorDay: Date = Date()
    @State private var isChoosingDate = false
    /// Which kinds are being shown. Empty means all of them, which is what the screen is
    /// about by default -- a filter you have to switch off to see everything is a filter
    /// that hides things without saying so.
    @State private var kinds: Set<RuleStatSection> = []

    @Environment(\.colorScheme) private var colorScheme

    private var focused: RuleStat? {
        focusedID.flatMap { id in viewModel.stats.first { $0.id == id } }
    }

    /// What is on screen, after the filter.
    private var visible: [RuleStat] {
        guard !kinds.isEmpty else { return viewModel.stats }
        return viewModel.stats.filter { stat in kinds.contains { $0.contains(stat.kind) } }
    }

    private var visibleSections: [RuleStatSection] {
        kinds.isEmpty ? RuleStatSection.allCases : RuleStatSection.allCases.filter { kinds.contains($0) }
    }

    /// How many days the chart under a focused rule looks back.
    private var chartDays: Int {
        switch period {
        case .day: 7
        case .week: 28
        case .month: 90
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                header

                if visible.isEmpty {
                    empty
                } else {
                    pills

                    if let focused {
                        detail(focused)
                            .transition(.blurReplace)
                    } else {
                        VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                            ForEach(visibleSections) { section in
                                self.section(section)
                            }
                        }
                        .transition(.blurReplace)
                    }
                }
            }
            .padding(.horizontal, LocktySpacing.tabInset)
            .padding(.vertical, LocktySpacing.lg)
        }
        .customSafeAreaBar(edge: .top, spacing: 0) {
            if !viewModel.stats.isEmpty {
                periodPicker
                    .padding(.horizontal, LocktySpacing.tabInset)
                    .padding(.bottom, LocktySpacing.md)
            }
        }
        .locktyScreenBackground()
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

            ToolbarItem(placement: .topBarLeading) {
                // Only while nothing is singled out. With one rule on screen there is
                // nothing to filter -- the filter would be about a list that is not there.
                //
                // The system's menu, not the app's. A custom menu is a popover anchored to
                // a view, and a toolbar item is not a view the app places: it belongs to
                // the navigation bar, which puts it where it likes and moves it as titles
                // collapse. `Menu` is what the bar knows how to hang a list from.
                if focusedID == nil {
                    Menu {
                        Button {
                            withAnimation(.smooth(duration: 0.3)) { kinds = [] }
                        } label: {
                            Label("All", systemImage: kinds.isEmpty ? "checkmark" : "")
                        }

                        Divider()

                        ForEach(RuleStatSection.allCases) { section in
                            Button {
                                withAnimation(.smooth(duration: 0.3)) {
                                    if kinds.contains(section) {
                                        kinds.remove(section)
                                    } else {
                                        kinds.insert(section)
                                    }
                                }
                            } label: {
                                Label(
                                    section.title,
                                    systemImage: kinds.contains(section) ? "checkmark" : ""
                                )
                            }
                        }
                    } label: {
                        Image(systemName: kinds.isEmpty
                            ? "line.3.horizontal.decrease"
                            : "line.3.horizontal.decrease.circle.fill")
                            .fontWeight(.light)
                            .foregroundStyle(LocktyColors.primaryText)
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .transition(.blurReplace)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                // A pencil while one rule is singled out, a plus otherwise: the bar acts
                // on whatever the screen is currently about.
                Button {
                    if let focusedID {
                        router.presentSheet(.ruleEditor(RuleEditorRoute(ruleID: focusedID)))
                    } else {
                        router.presentSheet(.ruleEditor(RuleEditorRoute(ruleID: nil)))
                    }
                } label: {
                    Image(systemName: focusedID == nil ? "plus" : "pencil")
                        .fontWeight(.light)
                        .foregroundStyle(LocktyColors.primaryText)
                        .contentTransition(.symbolEffect(.replace))
                }
                .buttonStyle(.plain)
            }
        }
        .sheet(isPresented: $isChoosingDate) {
            UsagePeriodPickerSheet(period: period, selection: $anchorDay)
        }
        .task(id: reloadKey) {
            await viewModel.load(period: period, anchor: anchorDay, days: chartDays, force: true)
        }
        .onChange(of: router.sheet) { _, newValue in
            guard newValue == nil else { return }
            Task { await viewModel.load(period: period, anchor: anchorDay, days: chartDays, force: true) }
        }
    }

    /// One id for everything a reload depends on: three tasks watching three values would
    /// all fire on the first appear and build the same answer three times.
    private var reloadKey: String {
        "\(period.rawValue)-\(DayKey(date: anchorDay).id)-\(chartDays)"
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.xs) {
            HStack(alignment: .firstTextBaseline, spacing: LocktySpacing.sm) {
                Text("\(viewModel.ranCount)")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                Text(viewModel.ranCount == 1 ? "rule ran" : "rules ran")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)

                Spacer(minLength: 0)
            }

            Text(subtitle)
                .font(.system(.footnote, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.tertiaryText)
        }
        .animation(.smooth(duration: 0.3), value: viewModel.ranCount)
    }

    private var subtitle: String {
        guard viewModel.runningNow > 0 else {
            return "Of \(viewModel.stats.count) set up."
        }
        return viewModel.runningNow == 1
            ? "One running right now."
            : "\(viewModel.runningNow) running right now."
    }

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(UsagePeriod.allCases) { option in
                Button {
                    withAnimation(.snappy(duration: 0.28)) {
                        period = option
                        focusedID = nil
                    }
                } label: {
                    Text(option.title)
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
                        Capsule(style: .continuous).fill(LocktyColors.ink(0.08))
                    }
                }
            }
        }
        .padding(3)
        .safeGlass(radius: 999, interactive: true)
    }

    // MARK: - Pills

    private var pills: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LocktySpacing.md) {
                    ForEach(visible) { stat in
                        let isDimmed = focusedID != nil && focusedID != stat.id

                        Button {
                            withAnimation(.smooth(duration: 0.38)) {
                                focusedID = focusedID == stat.id ? nil : stat.id
                            }
                        } label: {
                            HStack(spacing: LocktySpacing.sm) {
                                Image(systemName: stat.symbolName)
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(stat.tint)

                                // Its name, not its count. A row of bare numbers says how
                                // much happened without saying what it happened to, and
                                // there is no label under these pills to fill that in --
                                // the figure is what the screen underneath is for.
                                Text(stat.name)
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(LocktyColors.primaryText)
                                    .lineLimit(1)
                            }
                            .padding(.horizontal, LocktySpacing.lg)
                            .frame(height: 48)
                            .background { pillSurface(stat) }
                            .compositingGroup()
                            .contentShape(Capsule(style: .continuous))
                        }
                        .blur(radius: isDimmed ? 4.5 : 0)
                        .scaleEffect(isDimmed ? 0.9 : 1)
                        .animation(focusedID == nil ? nil : .smooth(duration: 0.38), value: focusedID)
                        .buttonStyle(.locktyInteractive(brighten: true))
                        .tappable()
                        .simultaneousGesture(
                            LongPressGesture(minimumDuration: 0.35)
                                .onEnded { _ in router.presentSheet(.ruleEditor(RuleEditorRoute(ruleID: stat.id))) }
                        )
                        .id(stat.id)
                    }
                }
                .padding(.horizontal, 2)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
            .onChange(of: focusedID) { _, newValue in
                guard let newValue else { return }
                withAnimation(.smooth(duration: 0.38)) {
                    proxy.scrollTo(newValue, anchor: .center)
                }
            }
        }
    }

    /// The pill's body, built as the day's scores are: a bloom behind it, the ground
    /// pressed in at the rim, and the rim itself drawn to how much of the period it ran in.
    ///
    /// A fraction rather than a lamp. Lit-or-nothing said only "this did something", which
    /// is the same thing said by the number inside it; the arc says how much of the period
    /// it was actually part of, which nothing else on the screen does.
    private func pillSurface(_ stat: RuleStat) -> some View {
        let shape = Capsule(style: .continuous)
        let colour = stat.tint
        let isDark = colorScheme == .dark
        let progress = max(min(Double(stat.runs) / Double(max(chartDays, 1)), 1), 0.02)

        return ZStack {
            if isDark {
                shape
                    .fill(colour)
                    .blur(radius: 14)
                    .opacity(0.5)
                    .blendMode(.plusLighter)
                    .padding(-2)
            } else if stat.hasOwnColor {
                ZStack {
                    shape.fill(.white).blur(radius: 12)
                    shape.fill(colour).blur(radius: 16).opacity(0.18)
                }
                .padding(-2)
            } else {
                // Nothing to bloom with.
                //
                // A pill's aura is light, and light is only visible against something
                // darker: on black, a white glow reads at once, which is why the dark side
                // of this looks right. On a pale page a white glow around a grey pill is
                // white on white -- the limits and the schedules simply had no edge at all.
                // What stands in for it is the opposite gesture: a soft shadow under the
                // pill, so it sits above the page rather than being lit from behind it.
                ZStack {
                    shape.fill(LocktyColors.ink(0.20)).blur(radius: 10)
                    shape.fill(LocktyColors.ink(0.10)).blur(radius: 18)
                }
                .padding(-1)
            }

            shape
                .fill(colour.opacity(isDark ? 0.14 : 0.10))
                .background { shape.fill(isDark ? LocktyColors.background : LocktyColors.cardSurface) }
                .overlay {
                    shape
                        .stroke(LocktyColors.background, lineWidth: 10)
                        .blur(radius: 6)
                        .mask { shape }
                }

            shape.stroke(LocktyColors.ink(0.10), lineWidth: 2)

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
        .animation(.smooth(duration: 0.45), value: progress)
    }

    // MARK: - One rule, read on its own

    private func detail(_ stat: RuleStat) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.xl) {
            VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                Text("\(stat.runs)")
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(stat.tint)
                    .monospacedDigit()
                    .contentTransition(.numericText())

                // No name. The pill above is lit and says it, and repeating it here made
                // the one line under the figure a label for something already labelled.
                Text(stat.kind == .schedule
                     ? (stat.runs == 1 ? "run" : "runs")
                     : (stat.runs == 1 ? "day reached" : "days reached"))
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if stat.runsByDay.contains(where: { $0.value > 0 }) {
                VStack(alignment: .leading, spacing: LocktySpacing.md) {
                    Text("DAY BY DAY")
                        .locktyEyebrow()

                    Text(stat.chartCaption)
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)

                    LocktyTrendChart(
                        points: points(stat.runsByDay),
                        tint: stat.tint,
                        format: { "\(Int($0.rounded()))" },
                        height: 150
                    )
                }
            } else {
                // Nothing behind it yet. The history starts the first time the app reads
                // the day, so a rule made this morning has one day in it and no chart --
                // which is a fact about the rule's age, not about the day.
                Text("Nothing recorded yet. This fills in from the day it was made.")
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.tertiaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 0) {
                figureRow("Kind", value: stat.kind.title)

                Divider().overlay(LocktyColors.separator.opacity(0.45))

                figureRow("Time on", value: stat.duration >= 60 ? LocktyDurationFormatter.abbreviated(stat.duration) : "--")

                Divider().overlay(LocktyColors.separator.opacity(0.45))

                figureRow("Right now", value: stat.isRunning ? "Running" : (stat.pausedUntil == nil ? "Idle" : "On hold"))
            }
            .padding(.horizontal, LocktySpacing.cardInset)
            .locktyCardBackground(cornerRadius: 26)
        }
    }

    private func figureRow(_ title: String, value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            Spacer(minLength: LocktySpacing.sm)

            Text(value)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(minHeight: 52)
    }

    private func points(_ values: [RuleStat.ChartDay]) -> [LocktyTrendChart.Point] {
        let named = Set([0, values.count / 2, values.count - 1])

        return values.enumerated().map { index, entry in
            LocktyTrendChart.Point(
                id: index,
                value: entry.value,
                label: named.contains(index) ? Self.weekdayFormatter.string(from: entry.date) : nil,
                caption: Self.captionFormatter.string(from: entry.date)
            )
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private func section(_ section: RuleStatSection) -> some View {
        let rules = visible.filter { section.contains($0.kind) }

        if !rules.isEmpty {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                Text(section.title.uppercased())
                    .locktyEyebrow()

                VStack(spacing: 0) {
                    ForEach(Array(rules.enumerated()), id: \.element.id) { index, stat in
                        if index > 0 {
                            Divider().overlay(LocktyColors.separator.opacity(0.45))
                        }

                        row(stat)
                    }
                }
            }
        }
    }

    private func row(_ stat: RuleStat) -> some View {
        Button {
            router.presentSheet(.ruleEditor(RuleEditorRoute(ruleID: stat.id)))
        } label: {
            HStack(spacing: LocktySpacing.md) {
                Image(systemName: stat.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(stat.tint)
                    .frame(width: 38, height: 38)
                    .background { Circle().fill(stat.tint.opacity(0.14)) }

                VStack(alignment: .leading, spacing: 2) {
                    Text(stat.name)
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)

                    Text(stat.detail)
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.tertiaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if stat.isRunning {
                    Text("On")
                        .font(.system(.footnote, design: .default, weight: .semibold))
                        .foregroundStyle(stat.tint)
                        .padding(.horizontal, LocktySpacing.md)
                        .frame(height: 26)
                        .background {
                            Capsule(style: .continuous)
                                .fill(stat.tint.opacity(0.14))
                        }
                }
            }
            .padding(.vertical, LocktySpacing.sm)
            .frame(minHeight: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
    }

    private var empty: some View {
        Text("No rules yet. A schedule shuts things at a time; a limit shuts them once they have had their share.")
            .font(.system(.subheadline, design: .default, weight: .regular))
            .foregroundStyle(LocktyColors.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
            .padding(LocktySpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .locktyCardBackground(cornerRadius: 26)
    }

    // MARK: - The date in the bar

    private var dateTitle: String {
        let calendar = Calendar.current
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = .current

        switch period {
        case .day:
            if calendar.isDateInToday(anchorDay) { return "Today" }
            if calendar.isDateInYesterday(anchorDay) { return "Yesterday" }
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
            return formatter.string(from: anchorDay)

        case .week:
            guard let interval = calendar.dateInterval(of: .weekOfYear, for: anchorDay) else { return "This week" }
            if interval.contains(Date()) { return "This week" }
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
            let end = calendar.date(byAdding: .day, value: 6, to: interval.start) ?? interval.end
            return "\(formatter.string(from: interval.start)) – \(formatter.string(from: end))"

        case .month:
            if calendar.isDate(anchorDay, equalTo: Date(), toGranularity: .month) { return "This month" }
            formatter.setLocalizedDateFormatFromTemplate("MMMM")
            return formatter.string(from: anchorDay)
        }
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private static let captionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM")
        return formatter
    }()
}
