import SwiftUI

struct ProductivityDetailView: View {
    let day: Date
    let viewModel: TodayViewModel

    private var state: TodayDayState { viewModel.state(for: day) }
    private var metric: PrimaryMetric? {
        state.primaryMetrics.metrics.first(where: { $0.kind == .productivity })
    }

    var body: some View {
        TodayMetricDetailScaffold(day: day, title: "Productivity", viewModel: viewModel) { state in
            if let metric = metric {
                PrimaryMetricSummaryCard(metric: metric, subtitle: "Derived from app classifications for this day.")
            }

            DetailTextCard(
                title: "What drove it",
                message: state.perspective.body
            )

            DetailAppsCard(
                title: "Applications",
                apps: state.appUsages.filter { $0.classification != .unproductive }
            )
        }
    }
}

struct ControlDetailView: View {
    let day: Date
    let viewModel: TodayViewModel

    private var state: TodayDayState { viewModel.state(for: day) }
    private var metric: PrimaryMetric? {
        state.primaryMetrics.metrics.first(where: { $0.kind == .control })
    }

    var body: some View {
        TodayMetricDetailScaffold(day: day, title: "Control", viewModel: viewModel) { state in
            if let metric = metric {
                PrimaryMetricSummaryCard(metric: metric, subtitle: "Control reflects Pause behavior, routine adherence and distraction pressure.")
            }

            DetailTextCard(
                title: "Pause behavior",
                message: state.metrics.pauseSuccess.detailText
            )

            DetailTextCard(
                title: "Distraction pressure",
                message: state.metrics.distractions.comparisonText
            )

            DetailActivityListCard(
                title: "Signals",
                activities: state.activities.filter { $0.type == .focus || $0.type == .distraction || $0.type == .routine }
            )
        }
    }
}

struct ScreenTimeDetailView: View {
    let day: Date
    let viewModel: TodayViewModel

    var body: some View {
        TodayMetricDetailScaffold(day: day, title: "Screen Time", viewModel: viewModel) { state in
            DetailValueCard(
                title: "Total usage",
                value: state.metrics.screenTime.durationText,
                detail: state.metrics.screenTime.comparisonText
            )

            DetailAppsCard(title: "Applications", apps: state.appUsages)
        }
    }
}

struct RoutineDaySummaryView: View {
    let day: Date
    let viewModel: TodayViewModel

    var body: some View {
        TodayMetricDetailScaffold(day: day, title: "Routines", viewModel: viewModel) { state in
            DetailValueCard(
                title: "Completion",
                value: state.metrics.routines.valueText,
                detail: state.metrics.routines.detailText
            )

            DetailActivityListCard(
                title: "Routine timeline",
                activities: state.activities.filter { $0.type == .routine || $0.type == .breakPeriod }
            )
        }
    }
}

struct PauseDaySummaryView: View {
    let day: Date
    let viewModel: TodayViewModel

    var body: some View {
        TodayMetricDetailScaffold(day: day, title: "Pause Success", viewModel: viewModel) { state in
            DetailValueCard(
                title: "Success",
                value: state.metrics.pauseSuccess.valueText,
                detail: state.metrics.pauseSuccess.detailText
            )

            DetailActivityListCard(
                title: "Pause events",
                activities: state.activities.filter {
                    $0.title.localizedCaseInsensitiveContains("Pause")
                        || $0.title.localizedCaseInsensitiveContains("Distraction")
                }
            )
        }
    }
}

struct DistractionsDetailView: View {
    let day: Date
    let viewModel: TodayViewModel

    var body: some View {
        TodayMetricDetailScaffold(day: day, title: "Distractions", viewModel: viewModel) { state in
            DetailValueCard(
                title: "Count",
                value: state.metrics.distractions.valueText,
                detail: state.metrics.distractions.comparisonText
            )

            DetailActivityListCard(
                title: "Distraction windows",
                activities: state.activities.filter { $0.type == .distraction }
            )
        }
    }
}

struct IntentionalTimeDetailView: View {
    let day: Date
    let viewModel: TodayViewModel

    var body: some View {
        TodayMetricDetailScaffold(day: day, title: "Intentional Time", viewModel: viewModel) { state in
            DetailValueCard(
                title: "Intentional usage",
                value: state.metrics.intentionalTime.valueText,
                detail: state.metrics.intentionalTime.detailText
            )

            DetailActivityListCard(
                title: "Meaningful periods",
                activities: state.activities.filter { $0.type == .routine || $0.type == .focus || $0.type == .detox }
            )
        }
    }
}

struct DigitalBalanceDetailView: View {
    let day: Date
    let viewModel: TodayViewModel

    var body: some View {
        TodayMetricDetailScaffold(day: day, title: "Digital Balance", viewModel: viewModel) { state in
            CardView {
                VStack(alignment: .leading, spacing: LocktySpacing.md) {
                    UsageTimelineChart(state: state.timeline)
                        .frame(height: 240)

                    if !state.timeline.overlays.isEmpty {
                        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                            Text("Timeline markers")
                                .font(LocktyTypography.headline)

                            ForEach(state.timeline.overlays) { overlay in
                                HStack(alignment: .firstTextBaseline) {
                                    Text(overlay.title)
                                        .font(LocktyTypography.callout)
                                    Spacer()
                                    Text(timeRangeText(start: overlay.startDate, end: overlay.endDate))
                                        .font(LocktyTypography.caption)
                                        .foregroundStyle(LocktyColors.secondaryText)
                                }
                            }
                        }
                    }
                }
            }

            DetailAppsCard(title: "Top applications", apps: Array(state.appUsages.prefix(8)))
        }
    }
}

@MainActor
@Observable
final class ApplicationDetailViewModel {
    let appID: AppIdentity.ID
    let day: Date

    private let todayViewModel: TodayViewModel
    private let routineRepository: RoutineRepository
    private let pauseRuleRepository: PauseRuleRepository

    private(set) var appUsage: AppUsageState?
    private(set) var relatedRoutines: [Routine] = []
    private(set) var pauseRule: PauseRule?

    init(
        appID: AppIdentity.ID,
        day: Date,
        todayViewModel: TodayViewModel,
        routineRepository: RoutineRepository,
        pauseRuleRepository: PauseRuleRepository
    ) {
        self.appID = appID
        self.day = day
        self.todayViewModel = todayViewModel
        self.routineRepository = routineRepository
        self.pauseRuleRepository = pauseRuleRepository
    }

    func load() async {
        await todayViewModel.load(day: day)
        let state = todayViewModel.state(for: day)
        appUsage = state.appUsages.first(where: { $0.app.id == appID })
        pauseRule = await pauseRuleRepository.rule(for: appID)
        relatedRoutines = ((try? await routineRepository.routines()) ?? [])
            .filter { $0.blockedApplications.contains(appID) }
    }

    func updateClassification(_ classification: AppClassification) {
        todayViewModel.updateClassification(appID: appID, classification: classification, day: day)
        appUsage?.classification = classification
    }
}

struct ApplicationDetailView: View {
    @Bindable var viewModel: ApplicationDetailViewModel
    let router: AppRouter

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                if let appUsage = viewModel.appUsage {
                    CardView {
                        VStack(alignment: .leading, spacing: LocktySpacing.md) {
                            HStack(spacing: LocktySpacing.md) {
                                AppIconView(
                                    source: appUsage.app.iconSource,
                                    applicationToken: appUsage.app.applicationToken,
                                    fallbackSystemImage: appUsage.app.iconSystemName
                                )
                                VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                                    Text(appUsage.app.displayName)
                                        .font(LocktyTypography.title)
                                    Text(appUsage.durationText)
                                        .font(LocktyTypography.callout)
                                        .foregroundStyle(LocktyColors.secondaryText)
                                }
                                Spacer()
                            }

                            ClassificationPickerRow(
                                selected: appUsage.classification,
                                onChange: { viewModel.updateClassification($0) }
                            )

                            if let comparisonText = appUsage.comparisonText {
                                Text(comparisonText)
                                    .font(LocktyTypography.caption)
                                    .foregroundStyle(LocktyColors.secondaryText)
                            }
                        }
                    }

                    if let pauseRule = viewModel.pauseRule {
                        CardView(interactive: true) {
                            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                                HStack {
                                    Text("Pause")
                                        .font(LocktyTypography.headline)
                                    Spacer()
                                    Text(pauseRule.isEnabled ? "Enabled" : "Disabled")
                                        .font(LocktyTypography.caption)
                                        .foregroundStyle(LocktyColors.secondaryText)
                                }
                                Text(pauseRule.steps.map(\.title).joined(separator: " -> "))
                                    .font(LocktyTypography.callout)
                                    .foregroundStyle(LocktyColors.secondaryText)
                            }
                        }
                        .tappable()
                        .onTapGesture {
                            router.push(.pauseDetail(pauseRule.id))
                        }
                    }

                    if !viewModel.relatedRoutines.isEmpty {
                        CardView {
                            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                                Text("Protected by Routines")
                                    .font(LocktyTypography.headline)
                                ForEach(viewModel.relatedRoutines) { routine in
                                    Button {
                                        router.push(.routineDetail(routine.id))
                                    } label: {
                                        HStack {
                                            Text(routine.name)
                                                .font(LocktyTypography.callout)
                                            Spacer()
                                            Text(routine.mode == .strict ? "Strict" : "Normal")
                                                .font(LocktyTypography.caption)
                                                .foregroundStyle(LocktyColors.secondaryText)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                } else {
                    CardView {
                        Text("No usage was recorded for this app on the selected day.")
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.secondaryText)
                    }
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.lg)
        }
        .navigationTitle(viewModel.appUsage?.app.displayName ?? "Application")
        .locktyScreenBackground()
        .task {
            await viewModel.load()
        }
    }
}

private struct TodayMetricDetailScaffold<Content: View>: View {
    let day: Date
    let title: String
    let viewModel: TodayViewModel
    let content: (TodayDayState) -> Content

    init(
        day: Date,
        title: String,
        viewModel: TodayViewModel,
        @ViewBuilder content: @escaping (TodayDayState) -> Content
    ) {
        self.day = day
        self.title = title
        self.viewModel = viewModel
        self.content = content
    }

    private var state: TodayDayState { viewModel.state(for: day) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                content(state)
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.lg)
        }
        .navigationTitle(title)
        .task {
            await viewModel.load(day: day)
        }
        .locktyScreenBackground()
    }
}

private struct PrimaryMetricSummaryCard: View {
    let metric: PrimaryMetric
    let subtitle: String

    var body: some View {
        CardView {
            HStack(spacing: LocktySpacing.md) {
                MetricRingView(metric: metric, collapseProgress: 0)
                    .frame(width: 120, height: 120)

                VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                    Text(metric.kind.title)
                        .font(LocktyTypography.headline)
                    Text(metric.displayValue)
                        .font(LocktyTypography.largeTitle)
                        .foregroundStyle(LocktyColors.primaryText)
                        .locktyNumericTransition(trigger: metric.displayValue)
                    Text(subtitle)
                        .font(LocktyTypography.callout)
                        .foregroundStyle(LocktyColors.secondaryText)
                }
            }
        }
    }
}

private struct DetailValueCard: View {
    let title: String
    let value: String
    let detail: String

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                Text(title)
                    .font(LocktyTypography.headline)
                Text(value)
                    .font(LocktyTypography.largeTitle)
                    .foregroundStyle(LocktyColors.primaryText)
                    .locktyNumericTransition(trigger: value)
                Text(detail)
                    .font(LocktyTypography.callout)
                    .foregroundStyle(LocktyColors.secondaryText)
                    .locktyNumericTransition(trigger: detail)
            }
        }
    }
}

private struct DetailTextCard: View {
    let title: String
    let message: String

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                Text(title)
                    .font(LocktyTypography.headline)
                Text(message)
                    .font(LocktyTypography.callout)
                    .foregroundStyle(LocktyColors.secondaryText)
            }
        }
    }
}

private struct DetailActivityListCard: View {
    let title: String
    let activities: [DigitalActivity]

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                Text(title)
                    .font(LocktyTypography.headline)

                if activities.isEmpty {
                    Text("No matching activity was recorded for this day.")
                        .font(LocktyTypography.callout)
                        .foregroundStyle(LocktyColors.secondaryText)
                } else {
                    ForEach(activities) { activity in
                        HStack(alignment: .firstTextBaseline) {
                            VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                                Text(activity.title)
                                    .font(LocktyTypography.callout)
                                Text(activity.type.title)
                                    .font(LocktyTypography.caption)
                                    .foregroundStyle(LocktyColors.secondaryText)
                            }
                            Spacer()
                            Text(timeRangeText(start: activity.startDate, end: activity.endDate))
                                .font(LocktyTypography.caption)
                                .foregroundStyle(LocktyColors.secondaryText)
                        }
                    }
                }
            }
        }
    }
}

private struct DetailAppsCard: View {
    let title: String
    let apps: [AppUsageState]

    var body: some View {
        CardView {
            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                Text(title)
                    .font(LocktyTypography.headline)

                if apps.isEmpty {
                    Text("No applications are available for this section.")
                        .font(LocktyTypography.callout)
                        .foregroundStyle(LocktyColors.secondaryText)
                } else {
                    ForEach(apps) { app in
                        HStack(spacing: LocktySpacing.md) {
                            AppIconView(
                                source: app.app.iconSource,
                                applicationToken: app.app.applicationToken,
                                fallbackSystemImage: app.app.iconSystemName
                            )
                            VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                                Text(app.app.displayName)
                                    .font(LocktyTypography.callout)
                                Text(app.classification.title)
                                    .font(LocktyTypography.caption)
                                    .foregroundStyle(LocktyColors.classification(app.classification))
                            }
                            Spacer()
                            Text(app.durationText)
                                .font(LocktyTypography.callout)
                                .monospacedDigit()
                        }
                    }
                }
            }
        }
    }
}

private struct ClassificationPickerRow: View {
    let selected: AppClassification
    let onChange: (AppClassification) -> Void

    var body: some View {
        HStack(spacing: LocktySpacing.sm) {
            ForEach(AppClassification.allCases) { classification in
                Button {
                    onChange(classification)
                } label: {
                    Text(classification.title)
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.classification(classification))
                        .padding(.horizontal, LocktySpacing.sm)
                        .padding(.vertical, LocktySpacing.xs)
                        .background(
                            RoundedRectangle(cornerRadius: LocktyRadius.small, style: .continuous)
                                .fill(
                                    classification == selected
                                    ? LocktyColors.classification(classification).opacity(0.16)
                                    : LocktyColors.elevatedBackground
                                )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private func timeRangeText(start: Date?, end: Date?) -> String {
    guard let start, let end, end > start else {
        return "--"
    }
    return "\(start.formatted(date: .omitted, time: .shortened))-\(end.formatted(date: .omitted, time: .shortened))"
}
