import SwiftUI

struct FocusView: View {
    @ObservedObject var viewModel: FocusViewModel
    let routinesViewModel: RoutinesViewModel
    let pausesViewModel: PausesViewModel
    @ObservedObject var router: AppRouter

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

                // Pauses are moving inside each routine rather than living as their own
                // list, so the section is out of the tab for now.
//                section(title: "Pauses") {
//                    router.push(.pausesList)
//                } content: {
//                    pausesRow
//                }
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
        .onChange(of: router.sheet) { _, newValue in
            guard newValue == nil else { return }
            Task {
                await routinesViewModel.load()
                await pausesViewModel.load()
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
            }
        }
    }

    @available(*, deprecated, message: "Kept while Pauses move inside the routine editor.")
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
