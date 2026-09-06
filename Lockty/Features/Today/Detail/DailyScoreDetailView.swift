import FamilyControls
import SwiftUI

/// One score, in full: the rock again, what the number is made of, and what it means.
///
/// No cards. A card is a summary you glance at on a page of other summaries; this page
/// has one subject, and boxing its parts would say they were separate things when they
/// are the parts of one number. Headings, a chart, and prose.
struct DailyScoreDetailView: View {
    let day: Date
    @ObservedObject var viewModel: TodayViewModel

    /// Which score the page is reading.
    ///
    /// One page for all three rather than three pages. They are the same shape of
    /// question -- what is this, what is it made of, what were today's figures -- and
    /// three screens meant going back out to the list to compare two of them.
    @State private var kind: PrimaryMetricKind

    /// Holds the sections in place while their contents change. What is the same between
    /// two scores should stay where it is; only what differs should be replaced.
    @Namespace private var sectionNamespace

    // The day chart's three tabs, and which one was showing. Kept with the pulse card
    // itself: nothing on this page has tabs any more, so there is nothing to remember.
//    @State private var pulseMetric: HourlyActivityMetric = .reduction

    init(day: Date, kind: PrimaryMetricKind, viewModel: TodayViewModel) {
        self.day = day
        self.viewModel = viewModel
        _kind = State(initialValue: kind)
    }

    /// How far the rock has collapsed, 0 at rest and 1 once the page has been scrolled
    /// past the distance. The same behaviour Today's badge has, for the same reason: the
    /// number is what the page is about, and it should still be there when you are three
    /// screens into the explanation of it.
    @State private var scrollOffset: CGFloat = 0

    private var collapseProgress: CGFloat {
        min(max(scrollOffset / 120, 0), 1)
    }

    private var state: TodayDayState {
        viewModel.state(for: day)
    }

    private var metric: PrimaryMetric? {
        state.primaryMetrics.metrics.first { $0.kind == kind }
    }

    private func tint(for metric: PrimaryMetric) -> Color {
        switch metric.tone {
        case .weak: LocktyColors.unproductive
        case .balanced: LocktyColors.warning
        case .strong: LocktyColors.productive
        }
    }

    private var tint: Color {
        guard let metric else { return LocktyColors.secondaryText }
        return tint(for: metric)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            // Generous between sections. Each one is a different question about the same
            // score -- what it is, what it counts, when it happened -- and at 24 they
            // read as one long block where the headings are the only thing separating
            // them. The heading has to arrive after a gap to be a heading.
            VStack(alignment: .leading, spacing: LocktySpacing.xxl) {
                badge

                // Only the first is shared. What a score is made of, and which figures
                // are worth showing beside it, are different questions for each of the
                // three -- so the sections below are the metric's own rather than one
                // template filled in three ways.
                section("explanation", "What is \(kind.title)?", showsDivider: false) {
                    Text(explanation)
                        .font(.system(.body, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .id("explanation-\(kind.rawValue)")
                        .transition(.blurReplace)
                }

                switch kind {
                case .focus:
                    section("focus-weights", "What a minute is worth") { componentBars.id("componentBars-\(kind.rawValue)").transition(.blurReplace) }

                    if state.hourlyActivity.hasAnyActivity {
                        section("focus-hours", "How your time was distributed") {
                            // The chart, without the card around it and without the three
                            // tabs. Only one of the three was worth a picture: how the
                            // hours divided. Unlocks and notifications are counts, said
                            // exactly in a line further down the same page, and drawing
                            // eighty-two of something as bars adds nothing to knowing it
                            // was eighty-two.
                            //
                            // `DailyPulseCard` is untouched and still compiles -- it is
                            // simply not reached from here any more.
                            DailyDistributionChart(state: state.hourlyActivity, day: day)
                                .id("distribution-\(kind.rawValue)")
                                .transition(.blurReplace)
                        }
                    }

                    if !distractingApps.isEmpty {
                        section("focus-apps", "What took the most") { appList.id("appList-\(kind.rawValue)").transition(.blurReplace) }
                    }

                    section("focus-figures", "Where the time went") { gauges.id("gauges-\(kind.rawValue)").transition(.blurReplace) }

                case .detox:
                    section("detox-parts", "How the score is weighed") { componentBars.id("componentBars-\(kind.rawValue)").transition(.blurReplace) }

                    if !quietStretches.isEmpty {
                        section("detox-stretches", "When you were off it") {
                            stretchList.id("stretchList-\(kind.rawValue)").transition(.blurReplace)
                        }
                    }

                    if viewModel.trend.count >= 3 {
                        section("detox-trend", "Time off the phone") {
                            LocktyTrendChart(
                                points: untouchedPoints,
                                tint: LocktyColors.productive,
                                format: { "\(Int($0.rounded()))h" }
                            )
                            .id("detoxTrend-\(kind.rawValue)")
                            .transition(.blurReplace)
                        }
                    }

                    if state.hourlyActivity.hasAnyActivity {
                        section("detox-hours", "How your time was distributed") {
                            DailyDistributionChart(state: state.hourlyActivity, day: day)
                                .id("distribution-\(kind.rawValue)")
                                .transition(.blurReplace)
                        }
                    }

                    section("detox-figures", "Today's gaps") { gauges.id("gauges-\(kind.rawValue)").transition(.blurReplace) }

                case .checks:
                    // No weights section. Checks has no formula to take apart -- the ring
                    // is a comparison with your own fortnight, which the paragraph above
                    // already says. Bars labelled "Half your usual day -- 100%" were the
                    // weights component wearing a scale's clothes, and read as nonsense.
                    if !busiestPickupHours.isEmpty {
                        section("checks-hours-list", "When you reached for it") {
                            pickupList.id("pickupList-\(kind.rawValue)").transition(.blurReplace)
                        }
                    }

                    if viewModel.trend.count >= 3 {
                        section("checks-trend", "Pickups over the fortnight") {
                            LocktyTrendChart(
                                points: pickupPoints,
                                tint: LocktyColors.warning,
                                format: { "\(Int($0.rounded()))" }
                            )
                            .id("checksTrend-\(kind.rawValue)")
                            .transition(.blurReplace)
                        }
                    }

                    section("checks-figures", "Around the count") { gauges.id("gauges-\(kind.rawValue)").transition(.blurReplace) }
                }
            }
            .padding(.horizontal, LocktySpacing.tabInset)
            .padding(.bottom, LocktySpacing.lg)
            .animation(.smooth(duration: 0.38), value: kind)
            .onGeometryChange(for: CGFloat.self) { proxy in
                -proxy.frame(in: .named("score-scroll")).minY
            } action: { newValue in
                scrollOffset = newValue
            }
        }
        .coordinateSpace(name: "score-scroll")
//        // Above the scroll, not in it, so it shrinks in place instead of leaving with
//        // the content. Commented out rather than removed: the pills sit in the scroll
//        // for now, and the sticky behaviour is worth keeping to hand.
//        .overlay(alignment: .top) { badge }
        .locktyScreenBackground()
        // No title in the bar. The rock above says the name at full size, and a smaller
        // copy of it sitting directly on top is the same word twice.
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(day: day) }
    }

    /// All three, with the one being read in focus and the others behind glass.
    ///
    /// Blurred rather than hidden: the page is about one of them but the other two are
    /// the comparison, and a number you can half-see is an invitation to look properly.
    /// They stay tappable at full size -- a target you can see but not hit is worse than
    /// one you cannot see at all.
    /// The same row Today has, singling one out.
    ///
    /// One component, not a copy: they have to sit at the same spacing and the same size
    /// in both places, and two arrangements of the same three pills is two things to keep
    /// in step.
    private var badge: some View {
        DailyScoreRocksView(
            metrics: state.primaryMetrics.metrics,
            focusedKind: kind
        ) { picked in
            guard picked != kind else { return }
            withAnimation(.smooth(duration: 0.38)) { kind = picked }
        }
        .frame(maxWidth: .infinity)
    }

    /// What the collapsed badge has to climb to sit on the toolbar's line rather than
    /// under it. The bar has no background of its own here, so there is nothing for it to
    /// hide behind on the way.
    private var navigationBarHeight: CGFloat { 44 }

    private func section<Content: View>(
        _ id: String,
        _ title: String,
        showsDivider: Bool = true,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            // A rule above each section rather than below it, so the last one on the page
            // does not end on a line with nothing under it. Space alone was not enough:
            // the weight bars run to the bottom of their section and the next heading
            // arrived looking like another row of the same list.
            if showsDivider {
                Divider()
                    .overlay(LocktyColors.separator.opacity(0.45))
            }

            LocktySectionTitle(title, prominent: true)
                // The heading is the same object across all three scores, so it slides
                // rather than being torn down and rebuilt when the page grows or shrinks
                // around it.
                .matchedGeometryEffect(id: "heading-\(id)", in: sectionNamespace)

            content()
        }
        // On the whole section, not only on what is inside it.
        //
        // Half the sections belong to one score alone -- the app list to Focus, the quiet
        // stretches to Detox -- so switching pill inserts and removes them outright, and
        // an insertion with no transition of its own gets SwiftUI's default, which is a
        // plain fade. That was the opacity left in the change: the contents were blurring
        // and the sections holding them were dissolving.
        .transition(.blurReplace)
    }

    // MARK: - Explanation

    /// Written from what the calculator actually does, so the page cannot drift from the
    /// number it is explaining.
    private var explanation: String {
        switch kind {
        case .focus:
            "Every minute on screen counts for what the app it went to is called. Productive time counts in full, neutral time counts half, and time in apps you called unproductive counts for nothing. The score is that weighted total as a share of everything you used -- so it says how the time was spent, not how much of it there was."
        case .detox:
            "Time away from the phone, weighted towards long stretches. The single longest gap counts for the most, then the total time you were not on it, then how few times you were interrupted. Twenty short breaks do not add up to one long one, which is the whole point of measuring it this way."
        case .checks:
            "How many times the phone was picked up, counted by Screen Time rather than by us. The ring is not the count: a count has no natural hundred, so it compares the day with your own last fortnight -- full when you are well under your usual, empty when you are well over. An ordinary day sits in the middle, because an ordinary day is not a failure."
        }
    }

    // MARK: - Components

    /// The parts of the number, at the weights the calculator gives them.
    ///
    /// The weights are the explanation: a score you cannot take apart is a number you are
    /// asked to trust, and this is the app telling you what it decided and by how much.
    /// The parts of the number, as rings.
    ///
    /// One ring per part, filled to the share it carries. See `LocktyWeightRings` for why
    /// these are not bars any more.
    private var componentBars: some View {
        LocktyWeightRings(items: componentItems, tint: tint)
    }

    private var componentItems: [LocktyWeightRings.Item] {
        components.map { component in
            LocktyWeightRings.Item(
                title: component.title,
                weight: component.weight,
                // Focus names its parts after what the app is called, so each ring wears
                // that classification's own colour. The other scores have no such
                // vocabulary and take the score's.
                tint: kind == .focus ? Self.classificationTint(for: component.title) : nil
            )
        }
    }

    /// The colour a Focus component is already called elsewhere on the page.
    private static func classificationTint(for title: String) -> Color? {
        switch title {
        case "Productive time": LocktyColors.productive
        case "Neutral time": LocktyColors.neutral
        case "Unproductive time": LocktyColors.unproductive
        default: nil
        }
    }

    // The same weights as bars, which is what they were until they became rings. A bar
    // says how much of something there is; these are shares of one number, and three of
    // them side by side are read against each other rather than measured off a left edge.
    private var componentBarsLegacy: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            ForEach(components, id: \.title) { component in
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text(component.title)
                            .font(.system(.subheadline, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.primaryText)

                        Spacer(minLength: LocktySpacing.sm)

                        Text("\(component.weight)%")
                            .font(.system(.subheadline, design: .default, weight: .semibold))
                            .foregroundStyle(LocktyColors.secondaryText)
                            .monospacedDigit()
                    }

                    GeometryReader { proxy in
                        // The same bar the figures and the breakdown draw: solid where it
                        // starts, dissolving where it ends. A weight is a proportion, not
                        // a measurement of anything, so a hard edge on it is the most
                        // misleading of the three.
                        Capsule()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        tint.opacity(0.85),
                                        tint.opacity(0.7),
                                        tint.opacity(0.2),
                                        tint.opacity(0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: proxy.size.width * CGFloat(component.weight) / 100, height: 5)
                            .blur(radius: 1.2)
                    }
                    .frame(height: 5)
                }
            }
        }
    }

    /// What each minute or each event is worth. Not weights of a formula for Held and
    /// Checks -- those two have no parts -- so the bars say what counts instead.
    private var components: [(title: String, weight: Int)] {
        switch kind {
        case .focus:
            [("Productive time", 100), ("Neutral time", 50), ("Unproductive time", 0)]
        case .detox:
            [("Longest stretch away", 45), ("Total time away", 40), ("Few interruptions", 15)]
        case .checks:
            // Nothing: the ring is a comparison, not a sum of parts. Kept as an empty
            // case rather than removed so the switch still names all three.
            []
        }
    }

    // MARK: - Trends

    /// Hours off the phone, one point per day with data.
    private var untouchedPoints: [LocktyTrendChart.Point] {
        trendPoints { Double($0.untouchedHours) }
    }

    private var pickupPoints: [LocktyTrendChart.Point] {
        trendPoints { Double($0.pickups) }
    }

    /// The fortnight as chart points, with the ends and the middle named.
    ///
    /// Three labels, not fourteen: a strip this wide cannot carry a name per day without
    /// them touching, and the useful thing about a trend line is the shape rather than
    /// which Tuesday was which.
    private func trendPoints(_ value: (DailyTrendPoint) -> Double) -> [LocktyTrendChart.Point] {
        let days = viewModel.trend
        let named = Set([0, days.count / 2, days.count - 1])

        return days.enumerated().map { index, day in
            LocktyTrendChart.Point(
                id: index,
                value: value(day),
                label: named.contains(index) ? Self.weekdayFormatter.string(from: day.date) : nil,
                caption: Self.captionFormatter.string(from: day.date)
            )
        }
    }

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

    // MARK: - Lists

    /// The day's longest runs of hours with the screen dark.
    ///
    /// Read at the hour, because that is the resolution Screen Time reports in -- an hour
    /// with under a minute in it counts as one you were off the phone. Three of them, not
    /// all: the point is the shape of the day, and a list of every quiet hour is the day
    /// again in a longer form.
    private var quietStretches: [(id: Int, range: String, duration: String)] {
        var runs: [(start: Int, length: Int)] = []
        var current: (start: Int, length: Int)?

        for hour in state.hourlyActivity.hours {
            if hour.usage < 60 {
                if var open = current {
                    open.length += 1
                    current = open
                } else {
                    current = (hour.hour, 1)
                }
            } else if let open = current {
                runs.append(open)
                current = nil
            }
        }
        if let open = current { runs.append(open) }

        return runs
            .filter { $0.length >= 2 }
            .sorted { $0.length > $1.length }
            .prefix(3)
            .map { run in
                (
                    id: run.start,
                    range: String(format: "%d:00 – %d:00", run.start, (run.start + run.length) % 24),
                    duration: run.length == 1 ? "1 h" : "\(run.length) h"
                )
            }
    }

    private var stretchList: some View {
        VStack(spacing: 0) {
            ForEach(Array(quietStretches.enumerated()), id: \.element.id) { index, stretch in
                if index > 0 {
                    Divider().overlay(LocktyColors.separator.opacity(0.45))
                }
                listRow(title: stretch.range, value: stretch.duration)
            }
        }
        .padding(.horizontal, LocktySpacing.cardInset)
        .locktyCardBackground(cornerRadius: 26)
    }

    /// The three hours with the most pickups in them. The count on its own says how much;
    /// this says when, which is the half of it a total can never carry.
    private var busiestPickupHours: [(id: Int, hour: String, count: Int)] {
        state.hourlyActivity.hours
            .filter { $0.unlocks > 0 }
            .sorted { $0.unlocks > $1.unlocks }
            .prefix(3)
            .map { (id: $0.hour, hour: String(format: "%d:00", $0.hour), count: $0.unlocks) }
    }

    private var pickupList: some View {
        VStack(spacing: 0) {
            ForEach(Array(busiestPickupHours.enumerated()), id: \.element.id) { index, entry in
                if index > 0 {
                    Divider().overlay(LocktyColors.separator.opacity(0.45))
                }
                listRow(
                    title: entry.hour,
                    value: entry.count == 1 ? "1 pickup" : "\(entry.count) pickups"
                )
            }
        }
        .padding(.horizontal, LocktySpacing.cardInset)
        .locktyCardBackground(cornerRadius: 26)
    }

    private func listRow(title: String, value: String) -> some View {
        HStack(spacing: LocktySpacing.md) {
            Text(title)
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)
                .monospacedDigit()

            Spacer(minLength: LocktySpacing.sm)

            Text(value)
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(minHeight: 52)
    }

    // MARK: - Chart

    /// The day's hours, split the way the score splits them. Only for productivity: it is
    /// the one of the three whose number is a share of the time, so an hour of it means
    /// the same thing the score does.
    private var hourlyChart: some View {
        GeometryReader { proxy in
            let width = proxy.size.width / 24
            let peak = state.hourlyActivity.hours.map(\.classifiedTotal).max() ?? 1

            HStack(alignment: .bottom, spacing: 0) {
                ForEach(state.hourlyActivity.hours) { hour in
                    VStack(spacing: 0) {
                        Spacer(minLength: 0)

                        if hour.classifiedTotal > 0 {
                            let height = 120 * CGFloat(hour.classifiedTotal / max(peak, 1))

                            VStack(spacing: 0) {
                                piece(hour.unproductive, of: hour.classifiedTotal, height: height, color: LocktyColors.unproductive)
                                piece(hour.neutral, of: hour.classifiedTotal, height: height, color: LocktyColors.neutral)
                                piece(hour.productive, of: hour.classifiedTotal, height: height, color: LocktyColors.productive)
                            }
                            .frame(width: 6, height: height)
                            .mask { Capsule().frame(height: height) }
                        }
                    }
                    .frame(width: width, height: 120, alignment: .bottom)
                }
            }
        }
        .frame(height: 120)
    }

    @ViewBuilder
    private func piece(
        _ value: TimeInterval,
        of total: TimeInterval,
        height: CGFloat,
        color: Color
    ) -> some View {
        if value > 0, total > 0 {
            color.frame(height: height * CGFloat(value / total))
        }
    }

    // MARK: - Apps

    /// The apps that took the most, with their own icons.
    ///
    /// A score is an average of a day, and an average never says which app it was about.
    /// Three rows with the real icons answer the question the number provokes.
    private var distractingApps: [AppUsageState] {
        Array(
            state.appUsages
                .filter { $0.classification == .unproductive && $0.duration >= 60 }
                .prefix(3)
        )
    }

    @ViewBuilder
    private func appName(_ app: AppIdentity) -> some View {
        if let token = app.applicationToken {
            Label(token).labelStyle(.locktyAppName(LocktyColors.primaryText))
        } else {
            Text(app.displayName).foregroundStyle(LocktyColors.primaryText)
        }
    }

    private var appList: some View {
        VStack(spacing: 0) {
            ForEach(Array(distractingApps.enumerated()), id: \.element.id) { index, usage in
                if index > 0 {
                    Divider().overlay(LocktyColors.separator.opacity(0.45))
                }

                HStack(spacing: LocktySpacing.md) {
                    AppIconView(
                        source: usage.app.iconSource,
                        applicationToken: usage.app.applicationToken,
                        fallbackSystemImage: usage.app.iconSystemName,
                        size: 34,
                        chrome: .plain
                    )

                    // From the token. `displayName` falls back to the bundle identifier,
                    // and no one recognises "com.burbn.instagram" as Instagram.
                    appName(usage.app)
                        .font(.system(.body, design: .default, weight: .regular))
                        .lineLimit(1)

                    Spacer(minLength: LocktySpacing.sm)

                    Text(usage.durationText)
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(LocktyColors.unproductive)
                        .monospacedDigit()
                }
                .frame(minHeight: 48)
            }
        }
    }

    // MARK: - Gauges

    /// The day's figures as gauges rather than as a list of values.
    ///
    /// A number on its own is not a reading: "40 unlocks" means nothing until you know
    /// whether forty is a lot, and the only honest answer to that is your own usual.
    private var gauges: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.xl) {
            ForEach(gaugeRows, id: \.title) { row in
                LocktyGaugeRow(
                    title: row.title,
                    value: row.value,
                    position: row.position,
                    verdicts: row.verdicts
                )
            }
        }
    }

    /// Every row carries a placed reading, not just the ones that were easy.
    ///
    /// A row with no position draws an empty track, and a page of empty tracks with one
    /// coloured bar in it reads as broken rather than as honest. Each of these is placed
    /// against something real -- the day's own composition, the fortnight behind it, or
    /// the clock -- and where a figure genuinely has no better or worse (which hour was
    /// busiest, say) it is not on this list at all rather than given an invented verdict.
    private var gaugeRows: [GaugeRow] {
        let hourly = state.hourlyActivity

        switch kind {
        case .focus:
            return [
                GaugeRow("Screen time", LocktyDurationFormatter.abbreviated(hourly.totalUsage), usagePosition,
                         .init("Light day", "An ordinary day", "A heavy one")),
                GaugeRow("Unproductive time", LocktyDurationFormatter.abbreviated(unproductiveUsage), sharePosition(unproductiveUsage),
                         .init("Barely any", "A fair chunk", "Most of the day")),
                GaugeRow("Productive time", LocktyDurationFormatter.abbreviated(productiveUsage), sharePosition(productiveUsage, inverted: true),
                         .init("Most of the day", "A fair chunk", "Barely any")),
                GaugeRow("Intentional time", state.metrics.intentionalTime.valueText, sharePosition(intentionalUsage, inverted: true),
                         .init("Nearly all on purpose", "Half by choice", "Mostly drift"))
            ]
        case .detox:
            return [
                GaugeRow("Longest stretch away", state.metrics.bestDetox.durationText, detoxStretchPosition,
                         .init("A real break", "A short break", "No real break")),
                GaugeRow("Screen time", LocktyDurationFormatter.abbreviated(hourly.totalUsage), usagePosition,
                         .init("Light day", "An ordinary day", "A heavy one")),
                GaugeRow("Hours untouched", "\(untouchedHours) of 24", untouchedPosition,
                         .init("Down most of the day", "Down half the day", "Rarely down")),
                GaugeRow("First look", firstLookText, firstLookPosition,
                         .init("A late start", "A normal start", "Straight away"))
            ]
        case .checks:
            return [
                GaugeRow("Phone unlocks", "\(hourly.totalUnlocks)", checksPosition,
                         .init("Few pickups", "About as usual", "Picked up constantly")),
                GaugeRow("Notifications", "\(hourly.totalNotifications)", notificationsPosition,
                         .init("A quiet day", "About as usual", "A noisy one")),
                GaugeRow("Average visit", averageVisitText, averageVisitPosition,
                         .init("Glances", "Short visits", "Long sittings")),
                GaugeRow("First look", firstLookText, firstLookPosition,
                         .init("A late start", "A normal start", "Straight away"))
            ]
        }
    }

    /// One line of the figures block.
    private struct GaugeRow {
        let title: String
        let value: String
        let position: Double?
        let verdicts: LocktyGaugeRow.Verdicts

        init(
            _ title: String,
            _ value: String,
            _ position: Double?,
            _ verdicts: LocktyGaugeRow.Verdicts
        ) {
            self.title = title
            self.value = value
            self.position = position
            self.verdicts = verdicts
        }
    }

    /// Time in apps called productive, and time the user said they meant to spend.
    private var productiveUsage: TimeInterval {
        state.appUsages
            .filter { $0.classification == .productive }
            .reduce(0) { $0 + $1.duration }
    }

    private var intentionalUsage: TimeInterval {
        state.metrics.intentionalTime.duration
    }

    /// The longest unbroken stretch away from the screen, against four hours.
    ///
    /// Four because that is roughly a working morning: long enough that reaching it is
    /// something, short enough that an ordinary day gets somewhere near. Not a baseline
    /// from history -- this is the one figure people are actively trying to grow, and a
    /// gauge that quietly moves its own goalposts every time you beat it never lets you.
    private var detoxStretchPosition: Double? {
        guard let duration = state.metrics.bestDetox.duration, duration > 0 else { return nil }
        return 1 - min(duration / (4 * 3600), 1)
    }

    /// Hours with the screen dark, out of a whole day. Two thirds of the day untouched is
    /// as far left as the bar goes -- the remaining third is sleep and a normal evening.
    private var untouchedPosition: Double? {
        guard state.hourlyActivity.hasAnyActivity else { return nil }
        return 1 - min(Double(untouchedHours) / 16, 1)
    }

    /// When the phone was first properly picked up, on the clock. Six in the morning is
    /// the far right and midday the far left: this is the one figure where the reading is
    /// simply how long you left it.
    private var firstLookPosition: Double? {
        guard let first = state.hourlyActivity.hours.first(where: { $0.usage >= 5 * 60 }) else {
            return nil
        }
        return 1 - min(max(Double(first.hour) - 6, 0) / 6, 1)
    }

    /// Notifications against an ordinary earlier day's, on the same scale as everything
    /// else: half the usual is the far left, twice it the far right.
    private var notificationsPosition: Double? {
        guard let baseline = state.hourlyActivity.baselineNotifications, baseline > 0 else { return nil }
        return placed(ratio: Double(state.hourlyActivity.totalNotifications) / baseline)
    }

    /// How long a pickup lasted, against five minutes.
    ///
    /// Longer is worse here, which surprises people: a day of long visits is a day spent
    /// in apps, where the same hours across short ones is a day of glances. Both are on
    /// the page, which is the point -- neither number means much without the other.
    private var averageVisitPosition: Double? {
        let unlocks = state.hourlyActivity.totalUnlocks
        guard unlocks > 0, state.hourlyActivity.totalUsage > 0 else { return nil }
        let average = state.hourlyActivity.totalUsage / Double(unlocks)
        return min(max(average / (10 * 60), 0), 1)
    }

    /// Time in apps called unproductive. The figure Focus is really about: the score
    /// falls because of these minutes and no others.
    private var unproductiveUsage: TimeInterval {
        state.appUsages
            .filter { $0.classification == .unproductive }
            .reduce(0) { $0 + $1.duration }
    }

    /// A share of the day, placed on the gauge directly: a third of your time in
    /// unproductive apps is the middle, none of it the far left, two thirds the far
    /// right. No history needed -- a proportion is already comparable to itself.
    private func sharePosition(_ duration: TimeInterval, inverted: Bool = false) -> Double? {
        let total = state.hourlyActivity.totalUsage
        guard total > 0 else { return nil }
        let placed = min(max((duration / total) / 0.66, 0), 1)
        // A share that is good to have runs the other way: two thirds of the day spent
        // on purpose is the far *left*, where two thirds of it wasted is the far right.
        return inverted ? 1 - placed : placed
    }

    /// When the day was heaviest, which an average of it can never say.
    private var busiestHourText: String {
        guard let peak = state.hourlyActivity.hours.max(by: { $0.usage < $1.usage }),
              peak.usage > 0
        else { return "--" }
        return String(format: "%d:00", peak.hour)
    }

    /// Hours with nothing on the screen at all. A blunter reading of the same thing Detox
    /// scores, and one nobody has to be told how to interpret.
    private var untouchedHours: Int {
        state.hourlyActivity.hours.filter { $0.usage < 60 }.count
    }

    /// The first hour with real use in it. People are almost always surprised by this
    /// one, which is the mark of a figure worth showing.
    private var firstLookText: String {
        guard let first = state.hourlyActivity.hours.first(where: { $0.usage >= 5 * 60 }) else {
            return "--"
        }
        return String(format: "%d:00", first.hour)
    }

    /// How long a pickup lasted on average. Two hours across ten visits and two hours
    /// across ninety are different days, and this is the only line that separates them.
    private var averageVisitText: String {
        let unlocks = state.hourlyActivity.totalUnlocks
        guard unlocks > 0, state.hourlyActivity.totalUsage > 0 else { return "--" }
        return LocktyDurationFormatter.abbreviated(state.hourlyActivity.totalUsage / Double(unlocks))
    }

    /// Where today's screen time sits against the fortnight behind it, on the same scale
    /// the gauge reads: half the usual is the far left, twice it the far right.
    private var usagePosition: Double? {
        guard let reduction = state.hourlyActivity.reductionVersusBaseline else { return nil }
        let baseline = state.hourlyActivity.totalUsage + reduction
        guard baseline > 0 else { return nil }
        return placed(ratio: state.hourlyActivity.totalUsage / baseline)
    }

    /// The pickup ring already knows this, so the gauge reads the same figure the pill
    /// does rather than working it out a second way.
    private var checksPosition: Double? {
        guard let metric = state.primaryMetrics.metrics.first(where: { $0.kind == .checks }) else {
            return nil
        }
        // The ring is full when the day is good; the gauge runs the other way.
        return 1 - metric.progress
    }

    private func placed(ratio: Double) -> Double {
        min(max((ratio - 0.5) / 1.5, 0), 1)
    }

    // MARK: - Figures

    /// The day's own numbers behind the score. Real ones only: every line here is
    /// something the pipeline measured, which is why the set differs per score rather
    /// than being the same four rows with different labels.
    private var figures: some View {
        VStack(spacing: 0) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Divider().overlay(LocktyColors.separator.opacity(0.45))
                }

                HStack {
                    Text(row.title)
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)

                    Spacer(minLength: LocktySpacing.sm)

                    Text(row.value)
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .frame(minHeight: 52)
            }
        }
    }

    private var rows: [(title: String, value: String)] {
        switch kind {
        case .focus:
            [
                ("Screen time", LocktyDurationFormatter.abbreviated(state.hourlyActivity.totalUsage)),
                // Intentional time is productivity's other half: productive minutes plus
                // half the neutral ones, plus the time a routine was running and three
                // minutes for every unlock you talked yourself out of.
                ("Intentional time", state.metrics.intentionalTime.valueText),
                ("Pickups", "\(state.hourlyActivity.totalUnlocks)")
            ]
        case .detox:
            [
                ("Longest stretch away", state.metrics.bestDetox.durationText),
                ("Screen time", LocktyDurationFormatter.abbreviated(state.hourlyActivity.totalUsage)),
                ("Shields", state.metrics.pauseSuccess.detailText)
            ]
        case .checks:
            [
                ("Notifications", "\(state.hourlyActivity.totalNotifications)"),
                ("Longest stretch away", state.metrics.bestDetox.durationText),
                ("Screen time", LocktyDurationFormatter.abbreviated(state.hourlyActivity.totalUsage))
            ]
        }
    }
}
