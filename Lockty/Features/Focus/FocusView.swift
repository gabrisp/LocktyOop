import SwiftUI

struct FocusView: View {
    @ObservedObject var viewModel: FocusViewModel
    let routinesViewModel: RoutinesViewModel
    let pausesViewModel: PausesViewModel
    @ObservedObject var router: AppRouter
    let pauseFlowRepository: PauseFlowRepository

    @State private var flows: [PauseFlow] = []

    /// The page gutter. Each horizontal row cancels it and re-applies it inside its own
    /// content, so cards scroll all the way to the screen edge instead of being clipped
    /// at the column, while still starting and ending flush with the titles above them.
    private var gutter: CGFloat { LocktySpacing.lg }
    private var tileWidth: CGFloat { RoutineGridMetrics.tileWidth }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                section(title: "Routines") {
                    router.push(.routinesList)
                } content: {
                    routinesRow
                }

                section(title: "Pauses") {
                    router.push(.pausesList)
                } content: {
                    flowsRow
                }
            }
            .padding(.horizontal, gutter)
            .padding(.vertical, LocktySpacing.lg)
        }
        .scrollIndicators(.hidden)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task {
            await routinesViewModel.load()
            await pausesViewModel.load()
        }
        .task { await loadFlows() }
        .onChange(of: router.sheet) { _, newValue in
            guard newValue == nil else { return }
            Task {
                await routinesViewModel.load()
                await pausesViewModel.load()
                await loadFlows()
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

    private var routinesRow: some View {
        horizontalRow {
            addTile(title: "New Routine") {
                router.presentSheet(.routineEditor(RoutineEditorRoute(routineID: nil)))
            }

            ForEach(routinesViewModel.routines) { routine in
                RoutineCard(
                    routine: routine,
                    isActive: routinesViewModel.activeRoutineID() == routine.id,
                    applicationTokens: routinesViewModel.tokens(for: routine.id),
                    onOpen: {
                        router.presentSheet(.routineEditor(RoutineEditorRoute(routineID: routine.id)))
                    }
                )
                .frame(width: tileWidth)
                // A ForEach insertion has no transition of its own, so a new routine
                // appeared fully formed and shoved the row along. It arrives instead.
                .transition(.blurReplace.combined(with: .scale(0.88)).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.34), value: routinesViewModel.routines.map(\.id))
    }

    private func loadFlows() async {
        let loaded = await pauseFlowRepository.flows()
        withAnimation(.smooth(duration: 0.28)) {
            flows = loaded
        }
    }

    /// Saved ways of pausing. No app on any of them -- a flow is picked up by a routine,
    /// and covers whatever that routine blocks.
    private var flowsRow: some View {
        horizontalRow {
            addTile(title: "New Pause") {
                router.presentSheet(.pauseFlowEditor(PauseFlowEditorRoute(flowID: nil)))
            }

            ForEach(flows) { flow in
                PauseFlowCard(flow: flow) {
                    router.presentSheet(.pauseFlowEditor(PauseFlowEditorRoute(flowID: flow.id)))
                }
                .frame(width: tileWidth)
                .transition(.blurReplace.combined(with: .scale(0.88)).combined(with: .opacity))
            }
        }
        .animation(.smooth(duration: 0.34), value: flows.map(\.id))
    }

    @available(*, deprecated, message: "The per-app pause list, kept while flows take over.")
    private var pausesRow: some View {
        horizontalRow {
            // No way in to creating one while a routine is running.
            if !pausesViewModel.isLockedByActiveRoutine {
                addTile(title: "New Pause") {
                    router.presentSheet(.pauseEditor(PauseEditorRoute(pauseID: nil)))
                }
            }

            ForEach(pausesViewModel.state.rules) { rule in
                PauseCard(rule: rule) {
                    router.presentSheet(.pauseEditor(PauseEditorRoute(pauseID: rule.id)))
                }
                .frame(width: tileWidth)
            }
        }
    }

    @ViewBuilder
    private func horizontalRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: RoutineGridMetrics.spacing) {
                content()
            }
            .padding(.horizontal, gutter)
        }
        .scrollIndicators(.hidden)
        // The cards grow under a press, and a scroll view clips its content by default,
        // so without this the grow was cut off at the row's own bounds.
        .scrollClipDisabled()
        .padding(.horizontal, -gutter)
    }

    /// Centred circle and label rather than the corner icon the other tiles use: this is
    /// the action, not one more item in the row.
    private func addTile(title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CardView(radius: RoutineGridMetrics.tileRadius, interactive: true, height: RoutineGridMetrics.tileHeight) {
                VStack(spacing: LocktySpacing.sm) {
                    Spacer(minLength: 0)

                    Image(systemName: "plus")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color(uiColor: .systemBackground))
                        .frame(width: 44, height: 44)
                        .background(Circle().fill(LocktyColors.primaryText))

                    Text(title)
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.locktyInteractive)
        .tappable()
        .frame(width: tileWidth)
    }
}


/// Grid tile for a pause flow: what it is called and what it puts you through.
private struct PauseFlowCard: View {
    let flow: PauseFlow
    let onOpen: () -> Void

    var body: some View {
        Button(action: onOpen) {
            CardView(
                radius: RoutineGridMetrics.tileRadius,
                interactive: true,
                height: RoutineGridMetrics.tileHeight
            ) {
                VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                    Image(systemName: flow.icon?.isEmpty == false ? flow.icon! : "hourglass")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(width: 24, height: 24)

                    Spacer(minLength: 0)

                    Text(flow.summary)
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.secondaryText)
                        .lineLimit(1)

                    Text(flow.name)
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
