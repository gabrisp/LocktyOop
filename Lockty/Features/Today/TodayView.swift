import SwiftUI

struct TodayView: View {
    let day: Date
    let viewModel: TodayViewModel
    @Bindable var router: AppRouter

    @State private var scrollOffset: CGFloat = 0
    @State private var showTodoInfo = false

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

    private var dateSliderHideProgress: CGFloat {
        MetricsHeaderGeometry.rangedProgress(collapseProgress, from: 0.08, to: 0.34)
    }

    private var topChromeSpacing: CGFloat {
        6
    }

    private var topChromeExpandedHeight: CGFloat {
        DayPageSliderMetrics.barHeight + topChromeSpacing + headerTopInset + MetricsHeaderGeometry.expandedHeight
    }

    private var metricsHeaderOffsetY: CGFloat {
        (DayPageSliderMetrics.barHeight + topChromeSpacing) * (1 - dateSliderHideProgress)
    }

    private var headerTopInset: CGFloat {
        LocktySpacing.sm
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                Color.clear
                    .frame(height: topChromeExpandedHeight + LocktySpacing.sm)

                if let checklist = state.activeRoutineChecklist {
                    VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                        HStack(spacing: LocktySpacing.xs) {
                            Text("TO DO")
                                .locktyEyebrow()
                                .padding(.top, 16)

                            Button {
                                showTodoInfo = true
                            } label: {
                                Image(systemName: "info.circle")
                                    .font(.system(size: 14, weight: .regular))
                                    .foregroundStyle(LocktyColors.tertiaryText)
                            }
                            .buttonStyle(.plain)
                            .tappable()
                            .popover(isPresented: $showTodoInfo) {
                                CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                                    Text("Tasks from the active routine. Completing them updates this session only and resets on the next routine run.")
                                        .font(LocktyTypography.callout)
                                        .foregroundStyle(LocktyColors.primaryText)
                                        .frame(width: 220, alignment: .leading)
                                }
                                .presentationCompactAdaptation(.popover)
                            }

                            Spacer(minLength: 0)
                        }

                        ActiveRoutineChecklistCard(
                            state: checklist,
                            onToggle: { item in
                                Task {
                                    await viewModel.toggleActiveRoutineTask(item.id, day: day)
                                }
                            }
                        )
                    }
                }

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

                DailyPerspectiveStackSection(
                    perspectives: viewModel.visiblePerspectives(for: day),
                    onDismiss: { perspective in
                        viewModel.dismissPerspective(perspective.id, day: day)
                    }
                )

                MyDaySection(activities: state.activities)

                DigitalBalanceCard(state: state.timeline) {
                    router.presentSheet(.digitalBalanceDetail(day))
                }

                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    Text("BREAKDOWN")
                        .locktyEyebrow()
                        .padding(.top, 16)
                TodayMetricGrid(state: state) { metric in
                    switch metric {
                    case .screenTime: router.presentSheet(.screenTimeDetail(day))
                    case .bestDetox: router.presentSheet(.detoxDetail(day))
                    case .routines: router.presentSheet(.routineDaySummary(day))
                    case .pauseSuccess: router.presentSheet(.pauseDaySummary(day))
                    case .distractions: router.presentSheet(.distractionsDetail(day))
                    case .intentionalTime: router.presentSheet(.intentionalTimeDetail(day))
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
        .adoptForIGTabBar($router.tabBarProgress)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newValue in
            scrollOffset = newValue
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .overlay(alignment: .top) {
            ZStack(alignment: .top) {
                DateSliderView(
                    dates: router.dayNavigationDays,
                    selectedDate: Binding(
                        get: { router.selectedDay },
                        set: { router.selectedDay = Calendar.current.startOfDay(for: $0) }
                    ),
                    scrollOffset: Binding(
                        get: { router.daySliderOffset },
                        set: { router.daySliderOffset = $0 }
                    ),
                    onDateChanged: { newDate in
                        router.selectedDay = Calendar.current.startOfDay(for: newDate)
                    },
                    onSelectionChanged: {}
                )
                .opacity(1 - dateSliderHideProgress)
                .offset(y: -dateSliderHideProgress * 12)

                TodayMetricsHeader(
                    metrics: state.primaryMetrics.metrics,
                    collapseProgress: collapseProgress,
                    topInset: headerTopInset,
                    onMetricSelected: { metric in
                        switch metric.kind {
                        case .productivity: router.presentSheet(.productivityDetail(day))
                        case .control: router.presentSheet(.controlDetail(day))
                        case .detox: router.presentSheet(.detoxDetail(day))
                        }
                    }
                )
                .offset(y: metricsHeaderOffsetY)
            }
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
