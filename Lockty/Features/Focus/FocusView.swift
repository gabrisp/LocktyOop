import SwiftUI

struct FocusView: View {
    @ObservedObject var viewModel: FocusViewModel
    let rulesViewModel: RulesViewModel
    let frictionsViewModel: FrictionsViewModel
    @ObservedObject var appsViewModel: AppsLibraryViewModel
    @ObservedObject var router: AppRouter
    let frictionRepository: FrictionRepository
    let toastCenter: LocktyToastCenter
    @ObservedObject var quickTimer: QuickTimerViewModel
    /// Today's view model, for the two cards that already know how to draw a running
    /// routine. Focus is where routines live, so what is running belongs at the top of
    /// it -- and building a second copy of the blocked-apps card here would be two of
    /// them to keep in step.
    @ObservedObject var todayViewModel: TodayViewModel

    /// Which of the timer's two pickers is open. Both are screens rather than sheets on
    /// top of a sheet: Focus is a tab, so they push.
    @State private var timerSheet: QuickTimerSheet?

    private enum QuickTimerSheet: String, Identifiable {
        case apps
        case friction

        var id: String { rawValue }
    }

    private var gutter: CGFloat { LocktySpacing.tabInset }
    private var tileWidth: CGFloat { RoutineGridMetrics.tileWidth }
    private var appTileWidth: CGFloat { 110 }
    private var appFolderShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: 28, style: .continuous)
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                // What is running, first. Everything below is a library of things you
                // made earlier; this is the thing that is happening.
                if !todayViewModel.activeRoutineGroups.isEmpty {
                    activeRoutines
                }

//                // The quick timer, commented out rather than removed: the rings above
//                // occupy the same place and answer the same question, and the timer's
//                // own machinery -- a transient routine that ends on the clock with the
//                // app closed -- is worth keeping around.
//                QuickTimerCard(
//                    minutes: $quickTimer.minutes,
//                    endsAt: quickTimer.endsAt,
//                    blockedSummary: quickTimer.blockedSummary,
//                    frictionSummary: quickTimer.frictionSummary,
//                    onStart: { Task { await quickTimer.start() } },
//                    onStop: { Task { await quickTimer.stop() } },
//                    onOpenApps: { timerSheet = .apps },
//                    onOpenFriction: { timerSheet = .friction }
//                )

                section(title: "Rules") {
                    router.push(.rulesList)
                } content: {
                    rulesRow
                }

                section(title: "Frictions") {
                    router.push(.frictionsList)
                } content: {
                    frictionsRow
                }

                section(title: "Apps") {
                    router.push(.appsList)
                } content: {
                    appsRow
                }
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, LocktySpacing.lg)
        }
        // No title. The tab bar underneath already says Focus, and a large title repeating
        // it cost the top third of the screen to say a word that was never in doubt.
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    router.presentSheet(.focusCreationChoice(FocusCreationChoiceRoute()))
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(item: $timerSheet) { sheet in
            quickTimerSheet(sheet)
        }
        .alert(
            "Could not start",
            isPresented: Binding(
                get: { quickTimer.errorMessage != nil },
                set: { if !$0 { quickTimer.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { quickTimer.errorMessage = nil }
        } message: {
            Text(quickTimer.errorMessage ?? "")
        }
        .task {
            // All at once. These were five awaits in a row -- a Core Data fetch, a seed, a
            // schedule sync and two more fetches -- so the screen waited for the sum of
            // them before it could draw anything, which is the pause you feel walking into
            // Focus. They do not depend on each other, so they do not have to queue.
            async let timer: Void = quickTimer.load()
            async let seed: Void = frictionRepository.seedDefaultFrictionIfNeeded()
            async let rules: Void = rulesViewModel.load()
            async let frictions: Void = frictionsViewModel.load()
            async let apps: Void = appsViewModel.load()

            _ = await (timer, seed, rules, frictions, apps)
        }
        .onChange(of: router.sheet) { _, newValue in
            guard newValue == nil else { return }
            Task {
                async let rules: Void = rulesViewModel.load()
                async let frictions: Void = frictionsViewModel.load()
                async let apps: Void = appsViewModel.load()
                _ = await (rules, frictions, apps)
            }
        }
    }

    /// The running routines, and what they are doing.
    ///
    /// One ring is centred; several scroll sideways. A row of three that has to be
    /// swiped is still a row you can see all of at rest, and stacking them down the
    /// screen would push the library out of sight for something that is usually one item
    /// long.
    @ViewBuilder
    private var activeRoutines: some View {
        let groups = todayViewModel.activeRoutineGroups

        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            // What is running, as pills that count down. The same object as the day's
            // three scores, so the two screens read alike -- except the figure inside
            // moves every second, because that is what there is to know about a mode
            // while it is on.
            ActiveModePills(routines: todayViewModel.activeRoutineGroups.map(\.routine)) { routine in
                // A shield is a routine to the engine and to nothing else. Opening the
                // routine editor on one shows a sheet built to read a saved mode -- its
                // schedule, its tasks, its name -- against something that has none of
                // that and is not in the library at all, which is why it looked so odd.
                // It gets its own sheet back, which is where it was set up.
                if routine.routineID == QuickTimerViewModel.routineID {
                    router.presentSheet(.quickShield)
                } else {
                    // The routine's own sheet, not the live-session one: that was built
                    // for a screen that no longer exists, while the editor's read-only
                    // face shows the apps, the pause and the strict guards.
                    router.presentSheet(.routineEditor(RoutineEditorRoute(routineID: routine.routineID)))
                }
            }

            // The rings this replaced. Kept, not removed: they say the same thing at four
            // times the size, and one of the two had to go.
//          if groups.count == 1, let group = groups.first {
//              ring(for: group)
//                  .frame(maxWidth: .infinity)
//          } else {
//              ScrollView(.horizontal, showsIndicators: false) {
//                  HStack(spacing: LocktySpacing.lg) {
//                      ForEach(groups) { group in
//                          ring(for: group, side: 112)
//                      }
//                  }
//                  .padding(.vertical, 2)
//              }
//              .scrollClipDisabled()
//          }

            if let routineCardState = todayViewModel.routineCardState,
               routineCardState.phase == .active {
                ActiveModeCard(
                    state: routineCardState,
                    groups: groups,
                    activeRoutine: todayViewModel.activeRoutine,
                    allowance: todayViewModel.activePauseAllowance,
                    onUnlock: { _ in },
                    onOpenSection: {}
                )
                .transition(.blurReplace)
            }

            if let checklist = todayViewModel.state(for: Date()).activeRoutineChecklist {
                ActiveRoutineChecklistCard(state: checklist) { item in
                    Task {
                        await todayViewModel.toggleActiveRoutineTask(item.id, day: Date())
                    }
                }
                .transition(.blurReplace)
            }
        }
        // The rings and the card go with the routine that owned them, rather than
        // vanishing between one frame and the next -- and they go the moment the engine
        // says so, wherever the routine was ended from.
        .animation(.smooth(duration: 0.32), value: groups.map(\.id))
        .animation(.smooth(duration: 0.32), value: todayViewModel.routineCardState?.id)
    }

    private func ring(for group: TodayActiveRoutineGroup, side: CGFloat = 128) -> some View {
        ActiveRoutineRingView(
            routine: group.routine,
            tint: LocktyColors.routine(group.routine.colorSnapshot),
            side: side
        ) {
            router.presentSheet(
                .routineEditor(RoutineEditorRoute(routineID: group.routine.routineID))
            )
        }
    }

    @ViewBuilder
    private func quickTimerSheet(_ sheet: QuickTimerSheet) -> some View {
        switch sheet {
        case .apps:
            NavigationStack {
                LocktyActivitySelectionView(
                    title: "Selected",
                    addLabel: "Add app or category",
                    selection: Binding(
                        get: { quickTimer.selection },
                        set: { quickTimer.replaceSelection($0) }
                    ),
                    contentRestrictions: Binding(
                        get: { quickTimer.contentRestrictions },
                        set: { quickTimer.contentRestrictions = $0 }
                    ),
                    rules: .rule,
                    toastCenter: toastCenter,
                    onClose: { timerSheet = nil },
                    onDone: { timerSheet = nil }
                )
                .locktyScreenBackground()
                .navigationTitle("Blocked apps")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Done") { timerSheet = nil }
                    }
                }
            }

        case .friction:
            NavigationStack {
                QuickTimerFrictionPicker(
                    frictions: frictionsViewModel.frictions,
                    selectedID: quickTimer.frictionID,
                    onSelect: { friction in
                        quickTimer.selectFriction(friction)
                        timerSheet = nil
                    }
                )
                .navigationTitle("Friction")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        onOpen: @escaping () -> Void,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            LocktySectionTitle(title, onOpen: onOpen)
            content()
        }
    }

    private var rulesRow: some View {
        horizontalRow {
            addTile(title: "New Rule") {
                router.presentSheet(.ruleEditor(RuleEditorRoute(ruleID: nil)))
            }

            ForEach(rulesViewModel.rules) { rule in
                Group {
                    if let routine = rule.routineBridge {
                        RoutineCard(
                            routine: routine,
                            isActive: rulesViewModel.activeScheduleRuleIDs().contains(rule.id),
                            applicationTokens: rulesViewModel.tokens(for: rule.id),
                            pausedUntil: rulesViewModel.pausedUntil(for: rule.id)
                        ) {
                            router.presentSheet(.routineEditor(RoutineEditorRoute(routineID: rule.id)))
                        }
                    } else {
                        RuleCard(
                            rule: rule,
                            applicationTokens: rulesViewModel.tokens(for: rule.id),
                            pausedUntil: rulesViewModel.pausedUntil(for: rule.id)
                        ) {
                            router.presentSheet(.ruleEditor(RuleEditorRoute(ruleID: rule.id)))
                        }
                    }
                }
                .frame(width: tileWidth)
                .transition(.blurReplace.combined(with: .scale(0.88)).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.34), value: rulesViewModel.rules.map(\.id))
    }

    private var frictionsRow: some View {
        horizontalRow {
            addTile(title: "New Friction") {
                router.presentSheet(.frictionEditor(FrictionEditorRoute(frictionID: nil)))
            }

            ForEach(frictionsViewModel.frictions) { friction in
                FrictionFocusCard(friction: friction) {
                    router.presentFullScreen(.frictionRun(friction.id))
                }
                .frame(width: tileWidth)
                .transition(.blurReplace.combined(with: .scale(0.88)).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.34), value: frictionsViewModel.frictions.map(\.id))
    }

    private var appsRow: some View {
        horizontalRow {
            Button {
                router.presentSheet(.autoFocus)
            } label: {
                AppFolderCard(
                    title: "Unproductive",
                    subtitle: folderCountText(appsViewModel.distractingTokens.count),
                    tokens: appsViewModel.distractingTokens,
                    titleAlignment: .center
                )
                .frame(width: appTileWidth)
            }
            .buttonStyle(.locktyInteractive(shape: appFolderShape))

            Button {
                // Refused while a routine is running rather than opened read-only: the
                // point of the folder is that what is in it cannot be blocked, so editing
                // it mid-routine is a way out of a routine you committed to.
                guard !appsViewModel.isAlwaysAllowedLocked else {
                    toastCenter.show(.alwaysAllowedLocked())
                    return
                }
                router.presentSheet(.alwaysAllowed)
            } label: {
                AppFolderCard(
                    title: "Always Allowed",
                    subtitle: folderCountText(appsViewModel.alwaysAllowedTokens.count),
                    tokens: appsViewModel.alwaysAllowedTokens,
                    titleAlignment: .center
                )
                .frame(width: appTileWidth)
                .opacity(appsViewModel.isAlwaysAllowedLocked ? 0.45 : 1)
            }
            .buttonStyle(.locktyInteractive(shape: appFolderShape))

            ForEach(appsViewModel.appGroups) { group in
                Button {
                    router.presentSheet(.appGroupEditor(AppGroupEditorRoute(appGroupID: group.id)))
                } label: {
                    AppFolderCard(
                        title: group.name,
                        subtitle: folderCountText(appsViewModel.tokens(for: group.id).count),
                        tokens: appsViewModel.tokens(for: group.id),
                        // Centred, like the "New group" tile sitting at the end of the
                        // same row. A row is not a column: there is no left edge for the
                        // names to line up on, so leading alignment only made each name
                        // hug a different point under its own folder.
                        titleAlignment: .center
                    )
                    .frame(width: appTileWidth)
                }
                .buttonStyle(.locktyInteractive(shape: appFolderShape))
            }

            Button {
                router.presentSheet(.appGroupEditor(AppGroupEditorRoute(appGroupID: nil)))
            } label: {
                AddAppFolderCard()
                    .frame(width: appTileWidth)
            }
            .buttonStyle(.locktyInteractive(shape: appFolderShape))
        }
        .animation(.smooth(duration: 0.34), value: appsViewModel.appGroups.map(\.id))
        .animation(.smooth(duration: 0.34), value: appsViewModel.distractingTokens.count)
    }

    private func folderCountText(_ count: Int) -> String {
        count == 1 ? "1 item" : "\(count) items"
    }

    @ViewBuilder
    private func horizontalRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(alignment: .top, spacing: RoutineGridMetrics.spacing) {
                content()
            }
            .padding(.horizontal, gutter)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .padding(.horizontal, -gutter)
    }

    private func addTile(title: String, action: @escaping () -> Void) -> some View {
        LocktyAddTile(title: title, action: action)
            .frame(width: tileWidth)
    }
}

private struct FrictionFocusCard: View {
    let friction: Friction
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            CardView(
                radius: RoutineGridMetrics.tileRadius,
                interactive: true,
                height: RoutineGridMetrics.tileHeight
            ) {
                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    Image(systemName: friction.icon ?? "slider.horizontal.3")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(width: 24, height: 24)

                    Spacer(minLength: 0)

                    Text(friction.summary)
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.secondaryText)
                        .lineLimit(1)

                    Text(friction.name)
                        .font(.system(.subheadline, design: .default, weight: .bold))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(2)
                }
            }
        }
        .buttonStyle(.locktyInteractive)
        .tappable()
    }
}
