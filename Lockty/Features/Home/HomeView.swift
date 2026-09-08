import SwiftUI

struct HomeView: View {
    @ObservedObject var router: AppRouter
    let featureFactory: FeatureFactory
    let destinationFactory: DestinationFactory

    /// Shared namespace so the bottom bar zooms into the live session sheet.
    @Namespace private var liveSessionZoom

    @State private var selectedBarTab: HomeBarTab = .today
    @State private var isPanelOpen = false
    @State private var quickActionsFeedback = 0
    @State private var quickActions = QuickActionSet.default
    /// The objectives the panel can log, cached. Read when the panel opens and when a
    /// sheet closes -- never from a body, which is what made the shell crawl.
    @State private var objectives: [Objective] = []
    /// The modes the panel can start, cached with the objectives and for the same reason.
    @State private var routines: [Routine] = []

    private let appGroupStore = AppGroupStore()

    var body: some View {
        shell
            .tint(LocktyColors.primaryText)
            .sensoryFeedback(.selection, trigger: quickActionsFeedback)
            .task {
                selectedBarTab = HomeBarTab(router.selectedTab)
                reloadPanel()
            }
            .onChange(of: router.selectedTab) { _, newValue in
                let barTab = HomeBarTab(newValue)
                guard selectedBarTab != barTab else { return }
                selectedBarTab = barTab
            }
            .onChange(of: router.sheet) { _, newValue in
                guard newValue == nil else { return }
                reloadPanel()
            }
            .sheet(item: $router.sheet) { route in
                if route == .liveSession {
                    destinationFactory.sheet(for: route)
                        .navigationTransition(.zoom(sourceID: SheetRoute.liveSession.id, in: liveSessionZoom))
                } else {
                    destinationFactory.sheet(for: route)
                }
            }
            .fullScreenCover(item: $router.fullScreen) { route in
                destinationFactory.fullScreen(for: route)
            }
    }

    @ViewBuilder
    private var shell: some View {
        if #available(iOS 26.0, *) {
            morphingShell
        } else {
            fallbackShell
        }
    }

    @available(iOS 26.0, *)
    private var morphingShell: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $router.selectedTab) {
                Tab(AppTab.today.title, systemImage: AppTab.today.systemImage, value: AppTab.today) {
                    tabContent(.today, usesOverlay: false)
                }

                Tab(AppTab.focus.title, systemImage: AppTab.focus.systemImage, value: AppTab.focus) {
                    tabContent(.focus, usesOverlay: false)
                }
            }
            .toolbar(.hidden, for: .tabBar)
            .toolbarVisibility(.hidden, for: .tabBar)
            .safeAreaPadding(.bottom, isPanelOpen ? 0 : 74)

            morphingBottomBar
        }
        .ignoresSafeArea(.all, edges: .bottom)
        .onChange(of: selectedBarTab) { _, newValue in
            closePanel()
            router.selectedTab = newValue.appTab
        }
    }

    private var fallbackShell: some View {
        TabView(selection: $router.selectedTab) {
            Tab(AppTab.today.title, systemImage: AppTab.today.systemImage, value: AppTab.today) {
                tabContent(.today, usesOverlay: true)
            }

            Tab(AppTab.focus.title, systemImage: AppTab.focus.systemImage, value: AppTab.focus) {
                tabContent(.focus, usesOverlay: true)
            }
        }
        .modifier(LocktyTabBarChrome())
        .toolbar {
            ToolbarItem(placement: .bottomBar) {
                Spacer()
            }

            ToolbarItem(placement: .bottomBar) {
                Button {
                    tapQuickActionsButton()
                } label: {
                    fallbackPlusLabel
                }
            }
        }
    }

    @available(iOS 26.0, *)
    private var morphingBottomBar: some View {
        HStack(alignment: .bottom, spacing: 12) {
            MorphingTabBar(
                activeTab: $selectedBarTab,
                isExpanded: $isPanelOpen,
                collapsedWidth: 132,
                // The tab bar's own gesture: pressing the tab you are on takes everything
                // pushed on top of it away and leaves you on the screen it starts from.
                onReselect: { tab in
                    closePanel()
                    router.popToRoot(for: tab.appTab)
                }
            ) {
                panel
            }

            Button {
                tapQuickActionsButton()
            } label: {
                glassPlusLabel
            }
            .buttonStyle(PlainGlassButtonEffect(shape: Circle()))
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 25)
        .animation(.smooth(duration: 0.28), value: isPanelOpen)
    }

    private var plusRotation: Angle {
        .degrees(isPanelOpen ? 45 : 0)
    }

    private var fallbackPlusLabel: some View {
        Image(systemName: "plus")
            .font(.body.weight(.light))
            .rotationEffect(plusRotation)
            .frame(width: 44, height: 40)
            .contentShape(Rectangle())
    }

    private var glassPlusLabel: some View {
        Image(systemName: "plus")
            .font(.body.weight(.light))
            .rotationEffect(plusRotation)
            .frame(width: 52, height: 52)
            .contentShape(Circle())
    }

    @ViewBuilder
    private func tabContent(_ tab: AppTab, usesOverlay: Bool) -> some View {
        switch tab {
        case .today:
            let stack = NavigationStack(path: $router.todayPath) {
                featureFactory.makeTodayView(day: router.selectedDay)
                    .locktyScreenBackground()
                    .navigationDestination(for: AppRoute.self) { route in
                        destinationFactory.destination(for: route)
                    }
            }

            if usesOverlay {
                stack.tabOverlay(isPresented: isPanelOpen) { panel } onDismiss: { closePanel() }
            } else {
                stack
                    .toolbar(.hidden, for: .tabBar)
                    .toolbarVisibility(.hidden, for: .tabBar)
            }

        case .focus:
            let stack = NavigationStack(path: $router.focusPath) {
                featureFactory.makeFocusView()
                    .locktyScreenBackground()
                    .navigationDestination(for: AppRoute.self) { route in
                        destinationFactory.destination(for: route)
                    }
            }

            if usesOverlay {
                stack.tabOverlay(isPresented: isPanelOpen) { panel } onDismiss: { closePanel() }
            } else {
                stack
                    .toolbar(.hidden, for: .tabBar)
                    .toolbarVisibility(.hidden, for: .tabBar)
            }

        case .lifetime:
            EmptyView()
        }
    }

    private var panel: some View {
        QuickActionsPanel(
            set: $quickActions,
            objectives: objectives,
            routines: routines,
            isComplete: { featureFactory.objectivesViewModel.isComplete($0) },
            onRun: run,
            onSave: { try? appGroupStore.saveQuickActions($0) }
        )
    }

    /// What the panel offers, read when it opens rather than while it draws.
    private func reloadPanel() {
        quickActions = appGroupStore.loadQuickActions()
        featureFactory.objectivesViewModel.load()
        // Only the ones you count yourself. Steps and sleep are read from Health, and a
        // tile that added to your step count would be writing down a walk you did not
        // take -- there is nothing for a press to mean.
        objectives = featureFactory.objectivesViewModel.dailyObjectives
            .filter { !$0.source.isMeasured }

        Task {
            routines = (try? await featureFactory.routineRepository.routines()) ?? []
        }
    }

    private func togglePanel() {
        if isPanelOpen {
            closePanel()
        } else {
            reloadPanel()
            withAnimation(.smooth(duration: 0.28)) { isPanelOpen = true }
        }
    }

    private func tapQuickActionsButton() {
        quickActionsFeedback += 1
        togglePanel()
    }

    private func closePanel() {
        withAnimation(.smooth(duration: 0.28)) { isPanelOpen = false }
    }

    /// Closes the panel and then opens the sheet, rather than both at once.
    private func open(_ route: SheetRoute) {
        closePanel()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
            router.presentSheet(route)
        }
    }

    private func run(_ action: QuickAction) {
        switch action.kind {
        case .newRoutine:
            open(.routineEditor(RoutineEditorRoute(routineID: nil, startsEditing: true)))

        case .newLimit:
            // Straight to which sort of limit. The tile already said "limit", and landing
            // on "Create Rule" asked that again and offered a schedule as one of the
            // answers -- which is not a limit at all.
            open(.ruleEditor(RuleEditorRoute(ruleID: nil, startsAtLimitKind: true)))

        case .newObjective:
            open(.objectiveEditor(nil))

        case .newFriction:
            open(.frictionEditor(FrictionEditorRoute(frictionID: nil)))

        case .quickBlock:
            open(.quickShield)

        case .startRoutine:
            closePanel()
            Task { await start(action) }

        case .logObjective:
            log(action)
        }
    }

    /// Starts the mode a tile is about, or opens the screen with all of them when the tile
    /// is not about one in particular.
    private func start(_ action: QuickAction) async {
        guard let id = action.routineID,
              let routine = (try? await featureFactory.routineRepository.routines())?
                  .first(where: { $0.id == id })
        else {
            router.selectedTab = .focus
            return
        }

        _ = await featureFactory.routineEngine.start(routine)
    }

    private func log(_ action: QuickAction) {
        guard let id = action.objectiveID,
              let objective = featureFactory.objectivesViewModel.objectives.first(where: { $0.id == id })
        else { return }

        let model = featureFactory.objectivesViewModel
        if objective.isYesNo {
            if model.isComplete(objective) {
                model.reset(objective)
            } else {
                model.complete(objective)
            }
        } else {
            model.advance(objective)
        }
    }
}

private enum HomeBarTab: CaseIterable, Hashable, MorphingTabProtocol {
    case today
    case focus

    init(_ tab: AppTab) {
        self = tab == .focus ? .focus : .today
    }

    var appTab: AppTab {
        switch self {
        case .today: .today
        case .focus: .focus
        }
    }

    var symbolImage: String { appTab.systemImage }
}

/// No-op wrapper kept so the older shell keeps the same call site.
struct LocktyTabBarChrome: ViewModifier {
    func body(content: Content) -> some View {
        content
    }
}
