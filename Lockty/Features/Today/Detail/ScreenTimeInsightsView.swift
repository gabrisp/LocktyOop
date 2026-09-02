import SwiftUI

/// The day's screen time in full: the badge again, the values behind it, and what they
/// add up to.
///
/// Today shows one figure because one figure is what a home screen should show. This is
/// where the rest of it lives -- the other scores, when the day actually happened, which
/// apps took it, and a few sentences saying what stands out. It is a place you go and
/// come back from, which is why it is pushed rather than presented.
struct ScreenTimeInsightsView: View {
    let day: Date
    @ObservedObject var viewModel: TodayViewModel

    private let insightBuilder = ScreenTimeInsightBuilder()

    private var state: TodayDayState {
        viewModel.state(for: day)
    }

    /// The fortnight behind the day, derived the same way Today derives it.
    private var baseline: TimeInterval? {
        guard let reduction = state.hourlyActivity.reductionVersusBaseline else { return nil }
        return state.hourlyActivity.totalUsage + reduction
    }

    var body: some View {
        // Its own scroll view rather than `LocktySectionScreen`, for one reason: the
        // scores are a pinned section header, so they stay at the top as the cards go
        // past. They are the summary of everything below them, and a summary that
        // scrolls away is a summary you have to scroll back for.
        ScrollView(.vertical, showsIndicators: false) {
            LazyVStack(spacing: LocktySpacing.lg, pinnedViews: [.sectionHeaders]) {
                ProductivityAuraView.screenTime(
                    usage: state.hourlyActivity.totalUsage,
                    baseline: baseline
                )
                .frame(maxWidth: .infinity)

                Section {
                    if !insights.isEmpty {
                        insightsCard
                    }

                    if !state.timeline.buckets.isEmpty {
                        timelineCard
                    }

                    if !state.appUsages.isEmpty {
                        appsCard
                    }

                    countsCard
                } header: {
                    scores
                }
            }
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.vertical, LocktySpacing.lg)
        }
        .locktyScreenBackground()
        .navigationTitle("Screen time")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            await viewModel.load(day: day)
        }
    }

    // MARK: - Scores

    /// The three scores as pills under the badge, in the app's own colours.
    ///
    /// Productivity is one of them rather than the headline. It is a judgement the app
    /// made about the time; the time itself is the fact, and the fact belongs on top.
    private var scores: some View {
        HStack(spacing: LocktySpacing.sm) {
            ForEach(state.primaryMetrics.metrics, id: \.kind) { metric in
                scorePill(metric)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, LocktySpacing.sm)
        // The screen's own ground, and only while pinned it matters: a card sliding
        // under a transparent header shows through it.
        .background {
            LocktyColors.background
                .padding(.horizontal, -LocktySpacing.lg)
        }
    }

    private func scorePill(_ metric: PrimaryMetric) -> some View {
        let value = Int(metric.value.rounded())
        let tint = tone(for: metric.value)

        return VStack(spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: metric.kind.systemImage)
                    .font(.system(size: 15, weight: .medium))

                Text("\(value)")
                    .font(.system(size: 22, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
            .foregroundStyle(LocktyColors.primaryText)
            .padding(.horizontal, LocktySpacing.md)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            // Glass, like every other pill in the app. A flat fill under a lit rim was
            // two materials on one control, and the rim is what carries the value -- the
            // body under it should be something you look through, not at.
            .safeGlass(radius: 999, interactive: true)
            // The rim carries the value: a full lap is a full score, and the arc is the
            // only part of the pill that says how far along it is without a second
            // number.
            //
            // No rotation. A trimmed capsule already starts its path at the top; turning
            // it ninety degrees turns the *shape*, and a capsule rotated inside a frame
            // that is not square comes out as a stroke that no longer follows the pill it
            // is drawn on -- which is what the borders were doing.
            .overlay {
                Capsule(style: .continuous)
                    .stroke(tint.opacity(0.55), lineWidth: 1.5)
                    .animation(.smooth(duration: 0.5), value: tint)
            }

            Text(metric.kind.title)
                .font(.system(.caption, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.secondaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
    }

    private func tone(for value: Double) -> Color {
        switch DailyScoreTone.tone(for: value) {
        case .weak: LocktyColors.unproductive
        case .balanced: LocktyColors.warning
        case .strong: LocktyColors.productive
        }
    }

    // MARK: - Insights

    private var insights: [ScreenTimeInsight] {
        insightBuilder.insights(
            apps: state.appUsages,
            hourly: state.hourlyActivity,
            totalUsage: state.hourlyActivity.totalUsage
        )
    }

    private var insightsCard: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.lg) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                LocktySectionTitle("What stood out")

                ForEach(insights) { insight in
                    insightRow(insight)
                }
            }
        }
    }

    private func insightRow(_ insight: ScreenTimeInsight) -> some View {
        HStack(alignment: .top, spacing: LocktySpacing.md) {
            Image(systemName: insight.systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(accent(for: insight.tone))
                .frame(width: 30, height: 30)
                .background {
                    Circle().fill(accent(for: insight.tone).opacity(0.14))
                }

            Text(attributed(insight))
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The figures inside the sentence, lit. A number buried in a line of grey text is a
    /// number nobody reads, and the number is the entire reason the sentence exists.
    private func attributed(_ insight: ScreenTimeInsight) -> AttributedString {
        var string = AttributedString(insight.text)
        for fragment in insight.emphasis {
            var searchRange = string.startIndex..<string.endIndex
            while let found = string[searchRange].range(of: fragment) {
                string[found].foregroundColor = accent(for: insight.tone)
                string[found].font = .system(.subheadline, design: .default, weight: .semibold)
                searchRange = found.upperBound..<string.endIndex
            }
        }
        return string
    }

    private func accent(for tone: ScreenTimeInsight.Tone) -> Color {
        switch tone {
        case .good: LocktyColors.productive
        case .neutral: LocktyColors.neutral
        case .warning: LocktyColors.warning
        }
    }

    // MARK: - Timeline

    /// When the day actually happened, rather than how much of it there was.
    ///
    /// The chart existed and was commented out of every screen. It is the only view in
    /// the app that shows productive and unproductive time against the clock, which is a
    /// different question from either of the numbers above it.
    private var timelineCard: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.lg) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                LocktySectionTitle("Through the day")

                UsageTimelineChart(state: state.timeline)
                    .frame(height: 200)
            }
        }
    }

    // MARK: - Apps

    private var appsCard: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.lg) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                LocktySectionTitle("Where it went")

                ForEach(Array(state.appUsages.prefix(6).enumerated()), id: \.element.id) { index, usage in
                    if index > 0 {
                        Divider().overlay(LocktyColors.separator.opacity(0.45))
                    }

                    appRow(usage)
                }
            }
        }
    }

    private func appRow(_ usage: AppUsageState) -> some View {
        HStack(spacing: LocktySpacing.md) {
            AppIconView(
                source: usage.app.iconSource,
                applicationToken: usage.app.applicationToken,
                fallbackSystemImage: usage.app.iconSystemName,
                size: 34,
                chrome: .plain
            )

            VStack(alignment: .leading, spacing: 1) {
                Text(usage.app.displayName)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)

                // Only when it is known. Screen Time delivers pickups late and unevenly,
                // and "0 opens" beside two hours of use is plainly wrong.
                if usage.opens > 0 {
                    Text(usage.opens == 1 ? "1 open" : "\(usage.opens) opens")
                        .font(.system(.caption, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.tertiaryText)
                }
            }

            Spacer(minLength: LocktySpacing.sm)

            Text(usage.durationText)
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.classification(usage.classification))
                .monospacedDigit()
        }
        .frame(minHeight: 46)
    }

    // MARK: - Counts

    private var countsCard: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.lg) {
            HStack(spacing: 0) {
                countCell(
                    title: "Pickups",
                    value: "\(state.hourlyActivity.totalUnlocks)",
                    systemImage: "iphone.gen3"
                )

                Rectangle()
                    .fill(LocktyColors.separator.opacity(0.5))
                    .frame(width: 1, height: 34)

                countCell(
                    title: "Notifications",
                    value: "\(state.hourlyActivity.totalNotifications)",
                    systemImage: "bell.badge"
                )

                Rectangle()
                    .fill(LocktyColors.separator.opacity(0.5))
                    .frame(width: 1, height: 34)

                countCell(
                    title: "Longest hour",
                    value: LocktyDurationFormatter.abbreviated(
                        state.hourlyActivity.hours.map(\.usage).max() ?? 0
                    ),
                    systemImage: "hourglass"
                )
            }
        }
    }

    private func countCell(title: String, value: String, systemImage: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: systemImage)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(LocktyColors.secondaryText)

            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(LocktyColors.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(title)
                .font(.system(.caption2, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.tertiaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}
