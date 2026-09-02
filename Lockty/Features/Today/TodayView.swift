import ManagedSettings
import SwiftUI
import UIKit

struct TodayView: View {
    let day: Date
    @ObservedObject var viewModel: TodayViewModel
    @ObservedObject var router: AppRouter

    @State private var scrollOffset: CGFloat = 0
    /// Routines/Pauses hide on a downward scroll and come back the moment the finger
    /// goes the other way, independently of how collapsed the rings are.
    @State private var areShortcutsHidden = false
    /// Which of the pulse card's three the chart is showing. Kept here rather than in the
    /// card so the choice survives the card being rebuilt as the day's data lands.
    @State private var pulseMetric: HourlyActivityMetric = .reduction

    private var state: TodayDayState {
        viewModel.state(for: day)
    }

    /// The day's productivity, rounded. Nil while it is still unknown, so the rock waits
    /// rather than animating up to a zero it would then have to correct.
    private var productivityScore: Int? {
        guard case .loaded = state.loadingState else { return nil }
        guard let metric = state.primaryMetrics.metrics.first(where: { $0.kind == .productivity }) else {
            return nil
        }
        return Int(metric.value.rounded())
    }

    /// The fortnight the day is being judged against, derived from the same reduction
    /// figure the pulse card shows: today's usage plus how much less it was than usual is
    /// what usual was. Nil when there is not enough history to say, which leaves the rock
    /// uncoloured rather than guessing.
    private var screenTimeBaseline: TimeInterval? {
        guard let reduction = state.hourlyActivity.reductionVersusBaseline else { return nil }
        return state.hourlyActivity.totalUsage + reduction
    }

    /// Both routine headings lead to the same place: routines are configured on Focus,
    /// and these cards are a window onto them rather than a place to manage them.
    private func openFocus() {
        withAnimation(.smooth(duration: 0.3)) {
            router.select(.focus)
        }
    }

    /// The only way this screen opens the friction flow.
    ///
    /// Refuses before presenting anything rather than at the end of the flow: a cooldown
    /// or a spent break limit means the answer is already no, and walking the friction
    /// first would be asking for work that cannot be accepted. The sheet says which of
    /// the two it is, and how long is left when there is a wait to sit out.
    @MainActor
    private func openUnlockFlow(for token: ApplicationToken?, context: PauseContext?) {
        Task { @MainActor in
            let appID = token.map(AppIdentity.ID.init(token:))
            switch await viewModel.unlockAvailability(for: context, appID: appID) {
            case .available:
                if context != nil {
                    withAnimation(.smooth(duration: 0.28)) {
                        router.pendingUnlock = nil
                    }
                }
                router.presentFullScreen(.unlockFlow(token))

            case .unavailable(let unavailable):
                router.presentSheet(.breakStatus(unavailable))
            }
        }
    }

    /// What the day button says. "Today" only while today is what is on screen -- a
    /// button that read "Today" over a different day's numbers would be lying about
    /// which day you were looking at.
    private var dayButtonTitle: String {
        guard !Calendar.current.isDateInToday(day) else { return "Today" }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.dateFormat = "d MMM"
        return formatter.string(from: day)
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

    /// An inline navigation bar's height. The chrome travels exactly this far up as it
    /// collapses, which is what lands the ring inside the bar rather than below it.
    private var navigationBarHeight: CGFloat { 44 }

    private var metricsGeometry: MetricsHeaderGeometry {
        MetricsHeaderGeometry(progress: collapseProgress)
    }

    private var shortcutHideProgress: CGFloat {
        areShortcutsHidden ? 1 : 0
    }

    /// The vertical space the shortcut row occupies, which collapses to nothing as it
    /// hides so everything below it rides up.
    ///
    /// Zero while the row itself is commented out above, so it doesn't hold a gap the
    /// rings would sit below.
    private var shortcutBlockHeight: CGFloat {
        0
//        (shortcutRowHeight + topChromeSpacing) * (1 - shortcutHideProgress)
    }

    /// Zero while the date slider is commented out above, same reason.
    private var dateSliderBlockHeight: CGFloat {
        0
//        (DayPageSliderMetrics.barHeight + topChromeSpacing) * (1 - dateSliderHideProgress)
    }

    /// Routines/Pauses sit above the rings now, pinned between the date slider and them.
    private var shortcutRowOffsetY: CGFloat {
        dateSliderBlockHeight + headerTopInset
    }

    /// Zero while nothing is pinned at the top: the ring is commented out along with the
    /// date slider and the shortcut row, so the content must not be pushed down to clear
    /// chrome that isn't there.
    private var topChromeExpandedHeight: CGFloat {
        // Interpolated, not fixed: the badge is pinned above the content, so the content
        // has to start below where it is drawn *and* ride up as it shrinks -- otherwise
        // it would leave the full-size gap behind.
        ProductivityAuraView.reservedHeight(collapseProgress: collapseProgress)
//        headerTopInset + MetricsHeaderGeometry.expandedHeight
//        DayPageSliderMetrics.barHeight + topChromeSpacing + headerTopInset
//            + shortcutRowHeight + topChromeSpacing + MetricsHeaderGeometry.expandedHeight
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
            // No backdrop behind the collapsed chrome: the ring sits on the screen's own
            // background now rather than on a black gradient masked in behind it.
//            topChromeBackdrop
            topChrome
        }
        .task(id: DayKey(date: day)) {
            await viewModel.load(day: day)
            viewModel.announceScoreIfRisen(day: day)
        }
        .animation(.smooth(duration: 0.32), value: router.pendingUnlock?.id)
        // Ending a routine takes its cards off the screen rather than having them
        // disappear between one frame and the next: the mode card and the checklist both
        // belong to the routine that was running.
        .animation(.smooth(duration: 0.34), value: viewModel.routineCardState?.id)
        .animation(.smooth(duration: 0.34), value: state.activeRoutineChecklist?.id)
        .onChange(of: collapseProgress, initial: true) { _, newValue in
            router.todayChromeCollapseProgress = newValue
        }
        .onDisappear {
            router.todayChromeCollapseProgress = 0
        }
    }

    /// The status bar / notch inset. Read from the window rather than a GeometryReader
    /// because this sits inside a ZStack that already starts below it.
    private var safeAreaTop: CGFloat {
        let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene
        return scene?.keyWindow?.safeAreaInsets.top ?? 0
    }

    /// From the top of the screen down to just below the rings, counting only what is
    /// actually pinned in between: it grows when the shortcut row drops in and shrinks
    /// back to the rings alone when the row hides.
    private var topChromeBackdropHeight: CGFloat {
        safeAreaTop
            + dateSliderBlockHeight
            + headerTopInset
            + shortcutBlockHeight
            + metricsGeometry.height
            + 6
    }

    /// The bottom fade is a fixed distance rather than a share of the height, so the
    /// short version (rings only) ends tight under them instead of fading over a
    /// proportionally long stretch the way the tall version does.
    private var topChromeBackdropFadeStart: CGFloat {
        let height = topChromeBackdropHeight
        guard height > 0 else { return 1 }
        return max(0, 1 - (18 / height))
    }

    /// Fades in across the collapse rather than tracking it from the first pixel, so a
    /// small scroll doesn't already paint a bar over the content.
    private var topChromeBackdropOpacity: CGFloat {
        MetricsHeaderGeometry.rangedProgress(collapseProgress, from: 0.12, to: 0.72)
    }

    /// A separate top-anchored layer rather than a background on the metrics header:
    /// as a background it was tied to a frame that shifts when the shortcut row is
    /// added or removed, so the gradient moved with it and no longer covered the safe
    /// area. Anchored here it never moves -- only its height changes.
    private var topChromeBackdrop: some View {
        LinearGradient(
            stops: [
                .init(color: LocktyColors.background, location: 0),
                .init(color: LocktyColors.background, location: topChromeBackdropFadeStart),
                .init(color: LocktyColors.background.opacity(0), location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .frame(maxWidth: .infinity)
        .frame(height: topChromeBackdropHeight)
        // Invisible while expanded, fading in as the header collapses.
        .opacity(topChromeBackdropOpacity)
        .allowsHitTesting(false)
        .ignoresSafeArea(edges: .top)
    }

    private var topChrome: some View {
        ZStack(alignment: .top) {
//            DateSliderView(
//                dates: router.dayNavigationDays,
//                selectedDate: Binding(
//                    get: { router.selectedDay },
//                    set: { router.selectedDay = Calendar.current.startOfDay(for: $0) }
//                ),
//                scrollOffset: Binding(
//                    get: { router.daySliderOffset },
//                    set: { router.daySliderOffset = $0 }
//                ),
//                onDateChanged: { newDate in
//                    router.selectedDay = Calendar.current.startOfDay(for: newDate)
//                },
//                onSelectionChanged: {}
//            )
//            .opacity(1 - dateSliderHideProgress)
//            .offset(y: -dateSliderHideProgress * 12)

//            TodayMetricsHeader(
//                metrics: state.primaryMetrics.metrics,
//                collapseProgress: collapseProgress,
//                topInset: headerTopInset,
//                onMetricSelected: { metric in
//                    switch metric.kind {
//                    case .productivity: router.presentSheet(.productivityDetail(day))
//                    case .control: router.presentSheet(.controlDetail(day))
//                    case .detox: router.presentSheet(.detoxDetail(day))
//                    }
//                }
//            )
//            .offset(y: metricsHeaderOffsetY)
            EmptyView()

            // Above the rings and pinned with them. They fade out on a downward scroll
            // and the rings ride up into the space; a scroll up brings them straight
            // back, even while the rings stay collapsed.
//            HStack(spacing: LocktySpacing.sm) {
//                TodaySectionShortcut(title: "Routines", systemImage: "repeat") {
//                    router.push(.routinesList)
//                }
//                TodaySectionShortcut(title: "Pauses", systemImage: "pause.circle") {
//                    router.push(.pausesList)
//                }
//            }
//            .padding(.horizontal, LocktySpacing.md)
//            .frame(height: shortcutRowHeight)
//            .opacity(1 - shortcutHideProgress)
//            .offset(y: shortcutRowOffsetY)
//            .allowsHitTesting(!areShortcutsHidden)

            // The day's headline. Pinned here rather than inside the scroll view,
            // because what it collapses into is the navigation bar's own line -- and the
            // offset below is what carries it there. No background of its own: the
            // screen's ground is already behind it, and a second one would show as a
            // panel sliding up with it.
            // Screen time rather than the productivity score. The score is a judgement
            // the app made; the time is the fact it was made from, and it is the thing
            // people open this app to look at. Productivity has not gone anywhere -- it
            // is one of the values on the screen this opens.
            Button {
                router.push(.usageBreakdown(day: day))
            } label: {
                ProductivityAuraView.screenTime(
                    usage: state.hourlyActivity.totalUsage,
                    baseline: screenTimeBaseline,
                    collapseProgress: collapseProgress
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.locktyInteractive(brighten: true))
            // Tap and hold do the same thing. They were two answers to one question --
            // the day with its charts, or where the time went -- and the second turned
            // out to be the one worth arriving at, so both lead there. The other screen
            // is still in the app, just not reached from here.
            .simultaneousGesture(
                LongPressGesture(minimumDuration: 0.4).onEnded { _ in
                    router.push(.usageBreakdown(day: day))
                }
            )
        }
        // Rides up into the navigation bar as it collapses, so what is left at the end
        // sits on the toolbar's own line, beside Settings, rather than parked under it.
        // The bar has no background of its own, so there is nothing for it to hide
        // behind on the way.
        .offset(y: overscrollPullDistance - navigationBarHeight * collapseProgress)
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

                // Above everything else: an unlock the shield asked for is the one thing
                // on this screen that is waiting on an answer.
                if let pendingUnlock = router.pendingUnlock {
                    UnlockRequestCard(
                        context: pendingUnlock,
                        availability: viewModel.badgeAvailability(forApp: pendingUnlock.appID)
                    ) {
                        Task { @MainActor in
                            openUnlockFlow(
                                for: pendingUnlock.applicationToken,
                                context: pendingUnlock
                            )
                        }
                    }
                    .transition(.blurReplace.combined(with: .opacity))
                }

                // The day itself, before anything Lockty is doing about it. It is the
                // one card that is true every day whether or not a routine ran, and the
                // question people open the app to ask.
                if state.hourlyActivity.hasAnyActivity {
                    DailyPulseCard(
                        state: state.hourlyActivity,
                        metric: $pulseMetric
                    )
                    .transition(.blurReplace.combined(with: .opacity))
                }

                // Then the running routine, which comes before everything else. An
                // unlock request, when there is one, sits even above both because it is
                // waiting on immediate action.
                if let routineCardState = viewModel.routineCardState,
                   routineCardState.phase == .active {
                    ActiveModeCard(
                        state: routineCardState,
                        groups: viewModel.activeRoutineGroups,
                        activeRoutine: viewModel.activeRoutine,
                        allowance: viewModel.activePauseAllowance,
                        onUnlock: { token in
                            openUnlockFlow(for: token, context: nil)
                        },
                        onOpenSection: { openFocus() },
                        onShowAllowance: { token in
                            guard let allowance = viewModel.activePauseAllowance else { return }
                            router.presentSheet(
                                .allowanceTimer(
                                    AllowanceTimerRoute(
                                        appID: AppIdentity.ID(token: token),
                                        token: token,
                                        expiresAt: allowance.expiresAt
                                    )
                                )
                            )
                        }
                    )
                    .transition(.blurReplace.combined(with: .opacity))
                }

                // Its own card, not a mode of the one above: nothing here is blocking
                // anything yet, so it lists when things start rather than which apps are
                // shut.
                if !viewModel.upcomingRoutines.isEmpty {
                    ScheduledRoutinesCard(
                        routines: viewModel.upcomingRoutines,
                        onSelect: { routineID in
                            router.presentSheet(.routineEditor(RoutineEditorRoute(routineID: routineID)))
                        },
                        onOpenSection: { openFocus() }
                    )
                    .transition(.blurReplace.combined(with: .opacity))
                }

                if let checklist = state.activeRoutineChecklist {
                    ActiveRoutineChecklistCard(
                        state: checklist,
                        onToggle: { item in
                            Task {
                                await viewModel.toggleActiveRoutineTask(item.id, day: day)
                            }
                        }
                    )
                    .transition(.blurReplace.combined(with: .opacity))
                }

                // There is no loading layout at all. The screen used to swap itself for a
                // spinner card, so everything mounted and jumped into place once the
                // report landed. The real cards are on screen from the first frame; each
                // individual unknown value inside them blurs itself until it is known.

//                DailyPerspectiveStackSection(
//                    perspectives: viewModel.visiblePerspectives(for: day),
//                    onDismiss: { perspective in
//                        viewModel.dismissPerspective(perspective.id, day: day)
//                    }
//                )
//
//                MyDaySection(activities: state.activities)
//
//                DigitalBalanceCard(state: state.timeline) {
//                    router.presentSheet(.digitalBalanceDetail(day))
//                }

                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
//                    LocktySectionTitle(
//                        "Breakdown",
//                        info: "Headline numbers for the day. Tap any card to see what went into it.",
//                        showsSeparator: false
//                    )
//                    .padding(.top, 16)
                    TodayMetricGrid(state: state) { metric in
                        switch metric {
                        // Pushed, not presented: it goes to the same place the badge
                        // does, and that is a screen you go to and come back from rather
                        // than something asking to be answered.
                        case .screenTime: router.push(.usageBreakdown(day: day))
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
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.top, LocktySpacing.sm)
            .padding(.bottom, LocktySpacing.xl)
        }
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { oldValue, newValue in
            scrollOffset = newValue
            updateShortcutVisibility(from: oldValue, to: newValue)
        }
        // The bar is shown, without a title: the only thing in it is Settings, and the
        // ring below it stays pinned to the safe area, which the bar now sets.
        .navigationBarTitleDisplayMode(.inline)
        // No material behind the bar. The ring pins itself right under it and would
        // otherwise be scrolling beneath the bar's own backdrop -- one more surface over
        // the content, and the black one was just taken out for the same reason.
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    router.presentSheet(.dayPicker)
                } label: {
                    Text(dayButtonTitle)
                        .font(.system(.subheadline, design: .default, weight: .medium))
                        .foregroundStyle(LocktyColors.primaryText)
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.push(.settings)
                } label: {
                    Image(systemName: "gearshape")
                        .fontWeight(.light)
                }
            }
        }
    }
}
