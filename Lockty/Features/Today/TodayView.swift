import SwiftUI

struct TodayView: View {
    let day: Date
    let viewModel: TodayViewModel
    let router: AppRouter

    @State private var scrollOffset: CGFloat = 0

    private var state: TodayDayState {
        viewModel.state(for: day)
    }

    private var collapseProgress: CGFloat {
    //     Sticky header collapse animation paused.

        MetricsHeaderGeometry.collapseProgress(for: scrollOffset)
    }

    private var overscrollPullDistance: CGFloat {
        max(0, -scrollOffset)
    }

    private var headerTopInset: CGFloat {
        LocktySpacing.sm
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                Color.clear
                    .frame(height: headerTopInset + MetricsHeaderGeometry.expandedHeight + LocktySpacing.sm)

                if case .loading = state.loadingState {
                    VStack(spacing: LocktySpacing.md) {
                        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                                Text("Loading Screen Time data")
                                    .font(LocktyTypography.title)
                                    .foregroundStyle(LocktyColors.primaryText)
                                Text("Lockty is requesting the Device Activity report for this day.")
                                    .font(LocktyTypography.callout)
                                    .foregroundStyle(LocktyColors.secondaryText)
                                LoadingView()
                                    .frame(height: 88)
                            }
                        }
                        LiveScreenTimeReportCard(day: day)
                    }
                } else if case .unavailable(let message) = state.loadingState {
                    CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                            Text("Screen Time data not ready")
                                .font(LocktyTypography.title)
                                .foregroundStyle(LocktyColors.primaryText)
                            Text(message)
                                .font(LocktyTypography.callout)
                                .foregroundStyle(LocktyColors.secondaryText)
                            Text("Lockty is retrying direct usage access and any cached Screen Time report available for this day.")
                                .font(LocktyTypography.caption)
                                .foregroundStyle(LocktyColors.tertiaryText)
                        }
                    }

                    LiveScreenTimeReportCard(day: day)
                }

//                TodayDebugCard(rawText: state.rawDebugText)

//                DailyPerspectiveCard(perspective: state.perspective)

                MyDaySection(activities: state.activities)

                DigitalBalanceCard(state: state.timeline) {
                    router.push(.digitalBalanceDetail(day))
                }

                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    Text("BREAKDOWN")
                        .locktyEyebrow()
                        .padding(.top, 16)
                TodayMetricGrid(state: state) { metric in
                    switch metric {
                    case .screenTime: router.push(.screenTimeDetail(day))
                    case .bestDetox: router.push(.detoxDetail(day))
                    case .routines: router.push(.routineDaySummary(day))
                    case .pauseSuccess: router.push(.pauseDaySummary(day))
                    case .distractions: router.push(.distractionsDetail(day))
                    case .intentionalTime: router.push(.intentionalTimeDetail(day))
                    }
                }
                }

                AppUsageListCard(state: state) { appUsage, classification in
                    viewModel.updateClassification(
                        appID: appUsage.id,
                        classification: classification,
                        day: day
                    )
                }

//                PatternsSection(patterns: state.patterns)

                ScreenTimeReportLoaderView(day: day)
                    .frame(width: 1, height: 1)
                    .opacity(0.01)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.top, LocktySpacing.sm)
            .padding(.bottom, LocktySpacing.xl)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newValue in
            scrollOffset = newValue
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            TodayMetricsHeader(
                metrics: state.primaryMetrics.metrics,
                collapseProgress: collapseProgress,
                onMetricSelected: { metric in
                    switch metric.kind {
                    case .productivity: router.push(.productivityDetail(day))
                    case .control: router.push(.controlDetail(day))
                    case .detox: router.push(.detoxDetail(day))
                    }
                }
            )
            .padding(.horizontal, LocktySpacing.md)
            .padding(.top, headerTopInset)
            .offset(y: overscrollPullDistance)
        }
        .task(id: DayKey(date: day)) {
            await viewModel.load(day: day)
        }
        // Sticky header / calendar-hide animation paused.
        .onChange(of: collapseProgress, initial: true) { _, newValue in
            router.todayChromeCollapseProgress = newValue
        }
        .onDisappear {
            router.todayChromeCollapseProgress = 0
        }
    }
}
