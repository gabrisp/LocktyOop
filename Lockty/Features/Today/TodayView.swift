import SwiftUI

struct TodayView: View {
    let day: Date
    let viewModel: TodayViewModel
    @Bindable var router: AppRouter

    @State private var scrollOffset: CGFloat = 0
    /// Routines/Pauses hide on a downward scroll and come back the moment the finger
    /// goes the other way, independently of how collapsed the rings are.
    @State private var areShortcutsHidden = false

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

    private var shortcutRowHeight: CGFloat { 52 }

    private var metricsGeometry: MetricsHeaderGeometry {
        MetricsHeaderGeometry(progress: collapseProgress)
    }

    private var shortcutHideProgress: CGFloat {
        areShortcutsHidden ? 1 : 0
    }

    /// The vertical space the shortcut row occupies, which collapses to nothing as it
    /// hides so everything below it rides up.
    private var shortcutBlockHeight: CGFloat {
        (shortcutRowHeight + topChromeSpacing) * (1 - shortcutHideProgress)
    }

    private var dateSliderBlockHeight: CGFloat {
        (DayPageSliderMetrics.barHeight + topChromeSpacing) * (1 - dateSliderHideProgress)
    }

    /// Routines/Pauses sit above the rings now, pinned between the date slider and them.
    private var shortcutRowOffsetY: CGFloat {
        dateSliderBlockHeight + headerTopInset
    }

    private var topChromeExpandedHeight: CGFloat {
        DayPageSliderMetrics.barHeight + topChromeSpacing + headerTopInset
            + shortcutRowHeight + topChromeSpacing + MetricsHeaderGeometry.expandedHeight
    }

    private var metricsHeaderOffsetY: CGFloat {
        dateSliderBlockHeight + shortcutBlockHeight
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
                backdropTopOverhang: shortcutBlockHeight,
                onMetricSelected: { metric in
                    switch metric.kind {
                    case .productivity: router.presentSheet(.productivityDetail(day))
                    case .control: router.presentSheet(.controlDetail(day))
                    case .detox: router.presentSheet(.detoxDetail(day))
                    }
                }
            )
            .offset(y: metricsHeaderOffsetY)

            // Above the rings and pinned with them. They fade out on a downward scroll
            // and the rings ride up into the space; a scroll up brings them straight
            // back, even while the rings stay collapsed.
            HStack(spacing: LocktySpacing.sm) {
                TodaySectionShortcut(title: "Routines", systemImage: "repeat") {
                    router.push(.routinesList)
                }
                TodaySectionShortcut(title: "Pauses", systemImage: "pause.circle") {
                    router.push(.pausesList)
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .frame(height: shortcutRowHeight)
            .opacity(1 - shortcutHideProgress)
            .offset(y: shortcutRowOffsetY)
            .allowsHitTesting(!areShortcutsHidden)
        }
        .offset(y: overscrollPullDistance)
    }

    /// Hides the shortcut row while the content is being pulled up, and reveals it on
    /// any upward movement. Direction, not absolute offset, so it comes back without
    /// having to scroll all the way to the top.
    private func updateShortcutVisibility(from oldValue: CGFloat, to newValue: CGFloat) {
        let delta = newValue - oldValue
        // Small deltas are bounce and rubber-banding, not a deliberate scroll.
        guard abs(delta) > 2 else { return }

        let shouldHide = delta > 0 && newValue > MetricsHeaderGeometry.collapseDistance
        guard shouldHide != areShortcutsHidden else { return }
        withAnimation(.smooth(duration: 0.3)) {
            areShortcutsHidden = shouldHide
        }
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
                    LocktySectionTitle(
                        "Breakdown",
                        info: "Headline numbers for the day. Tap any card to see what went into it.",
                        showsSeparator: false
                    )
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
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { oldValue, newValue in
            scrollOffset = newValue
            updateShortcutVisibility(from: oldValue, to: newValue)
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
    }
}
