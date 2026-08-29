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
        0
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
        }
        .animation(.smooth(duration: 0.32), value: router.pendingUnlock?.id)
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
                    UnlockRequestCard(context: pendingUnlock) {
                        withAnimation(.smooth(duration: 0.28)) {
                            router.pendingUnlock = nil
                        }
                        router.presentFullScreen(.pause(pendingUnlock))
                    }
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
//
//                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
//                    LocktySectionTitle(
//                        "Breakdown",
//                        info: "Headline numbers for the day. Tap any card to see what went into it.",
//                        showsSeparator: false
//                    )
//                    .padding(.top, 16)
//                    TodayMetricGrid(state: state) { metric in
//                        switch metric {
//                        case .screenTime: router.presentSheet(.screenTimeDetail(day))
//                        case .bestDetox: router.presentSheet(.detoxDetail(day))
//                        case .routines: router.presentSheet(.routineDaySummary(day))
//                        case .pauseSuccess: router.presentSheet(.pauseDaySummary(day))
//                        case .distractions: router.presentSheet(.distractionsDetail(day))
//                        case .intentionalTime: router.presentSheet(.intentionalTimeDetail(day))
//                        }
//                    }
//                }

                // Order on Today: checklist, the running mode, then usage. The mode card
                // only exists while something is actually running.
                if let activeRoutine = viewModel.activeRoutine {
                    ActiveModeCard(
                        routine: activeRoutine,
                        tokens: viewModel.activeRoutineTokens,
                        allowance: viewModel.activePauseAllowance,
                        onOpenApps: {
                            router.presentFullScreen(.unlockFlow(nil))
                        },
                        onUnlock: { token in
                            router.presentFullScreen(.unlockFlow(token))
                        }
                    )
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
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Not wired up yet.
                } label: {
                    Image(systemName: "gearshape")
                        .fontWeight(.light)
                }
            }
        }
    }
}
