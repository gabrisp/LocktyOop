import SwiftUI

struct TodayView: View {
    let day: Date
    let viewModel: TodayViewModel
    @Bindable var router: AppRouter

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

    /// Shrinks away as the header collapses. This used to lerp and was flattened to a
    /// constant when the date-slider spacing was removed, which left the collapsed
    /// header sitting lower than it should.
    private var headerTopInset: CGFloat {
        MetricsHeaderGeometry.lerp(LocktySpacing.sm, 0, progress: dateSliderHideProgress)
    }

    var body: some View {
        // Root ZStack rather than an .overlay on the ScrollView: an overlay is laid out
        // (and clipped) to the scroll view's frame, which starts below the safe area, so
        // the header's backdrop could never reach up into the status bar.
        ZStack(alignment: .top) {
            // An explicit bottom layer rather than .background: applied as a background
            // it sat behind the TabView/NavigationStack chrome, which paints over it, so
            // neither the base colour nor the aura ever showed.
            LocktyScreenBackground()
                .ignoresSafeArea()

            scrollContent
            topChrome
        }
        .task(id: DayKey(date: day)) {
            await viewModel.load(day: day)
        }
        .onChange(of: collapseProgress, initial: true) { _, newValue in
            router.todayChromeCollapseProgress = newValue
        }
        .onDisappear {
            router.todayChromeCollapseProgress = 0
        }
    }

    private var topChrome: some View {
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

    private var scrollContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                Color.clear
                    .frame(height: topChromeExpandedHeight + LocktySpacing.sm)

                if let checklist = state.activeRoutineChecklist {
                    // Just the card on Today — the label and its explanation live in the
                    // routine editor's Checklist section instead.
                    ActiveRoutineChecklistCard(
                        state: checklist,
                        onToggle: { item in
                            Task {
                                await viewModel.toggleActiveRoutineTask(item.id, day: day)
                            }
                        }
                    )
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

                // Routines and Pauses replaced the tabs, so they're reached from here.
                HStack(spacing: LocktySpacing.sm) {
                    TodaySectionShortcut(title: "Routines", systemImage: "repeat") {
                        router.presentSheet(.routinesList)
                    }
                    TodaySectionShortcut(title: "Pauses", systemImage: "pause.circle") {
                        router.presentSheet(.pausesList)
                    }
                }

                DailyPerspectiveStackSection(
                    perspectives: viewModel.visiblePerspectives(for: day),
                    onDismiss: { perspective in
                        viewModel.dismissPerspective(perspective.id, day: day)
                    }
                )
                // Cancel the column's horizontal padding and re-apply it inside the
                // section, so the swipe-out is clipped at the screen edge rather than
                // at the padding inset (which looked cut off mid-card).
                .padding(.horizontal, -LocktySpacing.md)

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
    }
}
