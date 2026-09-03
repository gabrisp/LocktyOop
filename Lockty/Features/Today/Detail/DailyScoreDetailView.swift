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
            VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                badge

                // Only the first is shared. What a score is made of, and which figures
                // are worth showing beside it, are different questions for each of the
                // three -- so the sections below are the metric's own rather than one
                // template filled in three ways.
                section("explanation", "What is \(kind.title)?") {
                    Text(explanation)
                        .font(.system(.body, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .id("explanation-\(kind.rawValue)")
                        .transition(.blurReplace.combined(with: .opacity))
                }

                switch kind {
                case .focus:
                    section("focus-weights", "How a minute counts") { componentBars }

                    if state.hourlyActivity.hasAnyActivity {
                        section("focus-hours", "Through the day") { hourlyChart }
                    }

                    section("focus-figures", "Where the time went") { figures }

                case .detox:
                    section("detox-parts", "What counts as time away") { componentBars }
                    section("detox-figures", "Today's gaps") { figures }

                case .checks:
                    section("checks-ring", "How the ring reads") { componentBars }
                    section("checks-figures", "Around the count") { figures }
                }
            }
            .padding(.horizontal, LocktySpacing.screenInset)
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
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            LocktySectionTitle(title, prominent: true)
                // The heading is the same object across all three scores, so it slides
                // rather than being torn down and rebuilt when the page grows or shrinks
                // around it.
                .matchedGeometryEffect(id: "heading-\(id)", in: sectionNamespace)

            content()
        }
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
    private var componentBars: some View {
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
                        Capsule()
                            .fill(tint.opacity(0.7))
                            .frame(width: proxy.size.width * CGFloat(component.weight) / 100, height: 5)
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
            [("Half your usual day", 100), ("Your usual day", 50), ("Twice your usual", 0)]
        }
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
