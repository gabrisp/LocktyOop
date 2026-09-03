import SwiftUI

/// One score, in full: the rock again, what the number is made of, and what it means.
///
/// No cards. A card is a summary you glance at on a page of other summaries; this page
/// has one subject, and boxing its parts would say they were separate things when they
/// are the parts of one number. Headings, a chart, and prose.
struct DailyScoreDetailView: View {
    let day: Date
    let kind: PrimaryMetricKind
    @ObservedObject var viewModel: TodayViewModel

    private var state: TodayDayState {
        viewModel.state(for: day)
    }

    private var metric: PrimaryMetric? {
        state.primaryMetrics.metrics.first { $0.kind == kind }
    }

    private var tint: Color {
        guard let metric else { return LocktyColors.secondaryText }
        return switch metric.tone {
        case .weak: LocktyColors.unproductive
        case .balanced: LocktyColors.warning
        case .strong: LocktyColors.productive
        }
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                badge

                section("What this is") {
                    Text(explanation)
                        .font(.system(.body, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                section("What it is made of") {
                    componentBars
                }

                if kind == .productivity, state.hourlyActivity.hasAnyActivity {
                    section("Through the day") {
                        hourlyChart
                    }
                }

                section("Today's figures") {
                    figures
                }
            }
            .padding(.horizontal, LocktySpacing.screenInset)
            .padding(.vertical, LocktySpacing.lg)
        }
        .locktyScreenBackground()
        .navigationTitle(kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.load(day: day) }
    }

    private var badge: some View {
        ProductivityAuraView(
            title: kind.title,
            value: metric.map(\.value),
            tint: tint,
            format: { "\(Int($0))" }
        )
        .frame(maxWidth: .infinity)
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            LocktySectionTitle(title)
            content()
        }
    }

    // MARK: - Explanation

    /// Written from what the calculator actually does, so the page cannot drift from the
    /// number it is explaining.
    private var explanation: String {
        switch kind {
        case .productivity:
            "Every minute on screen counts for what the app it went to is called. Productive time counts in full, neutral time counts half, and time in apps you called distracting counts for nothing. The score is that weighted total as a share of everything you used -- so it says how the time was spent, not how much of it there was."
        case .control:
            "How much of what you set up actually held. Finishing the routines you started is the largest part of it, then unlocks you began and did not see through, then blocks that stayed up. Time spent hopping in and out of apps takes points off: the score is about staying with a decision, and the shape of the day says as much as the totals."
        case .detox:
            "Time away from the phone, weighted towards long stretches. The single longest gap is worth the most, then the total time you were not on it, then how few times you were interrupted. Twenty short breaks do not add up to one long one, which is the whole point of the measure."
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

    private var components: [(title: String, weight: Int)] {
        switch kind {
        case .productivity:
            [("Productive time", 100), ("Neutral time", 50), ("Distracting time", 0)]
        case .control:
            [("Routines finished", 55), ("Blocks that held", 25), ("Unlocks seen through", 20)]
        case .detox:
            [("Longest stretch away", 45), ("Total time away", 40), ("Few interruptions", 15)]
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
        case .productivity:
            [
                ("Screen time", LocktyDurationFormatter.abbreviated(state.hourlyActivity.totalUsage)),
                // Intentional time is productivity's other half: productive minutes plus
                // half the neutral ones, plus the time a routine was running and three
                // minutes for every unlock you talked yourself out of.
                ("Intentional time", state.metrics.intentionalTime.valueText),
                ("Pickups", "\(state.hourlyActivity.totalUnlocks)")
            ]
        case .control:
            [
                ("Routines", state.metrics.routines.valueText),
                ("Unlocks", state.metrics.pauseSuccess.valueText),
                // Distractions is a count, not a duration: blocked apps you tried to
                // open, stretches of distracting use, and the times you tried again.
                ("Distractions", state.metrics.distractions.valueText)
            ]
        case .detox:
            [
                ("Longest stretch away", state.metrics.bestDetox.durationText),
                ("Screen time", LocktyDurationFormatter.abbreviated(state.hourlyActivity.totalUsage)),
                ("Notifications", "\(state.hourlyActivity.totalNotifications)")
            ]
        }
    }
}
