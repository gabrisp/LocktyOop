import SwiftUI

struct RoutinesView: View {
    let viewModel: RoutinesViewModel
    let router: AppRouter

    private let columns = [
        GridItem(.flexible(), spacing: RoutineGridMetrics.spacing),
        GridItem(.flexible(), spacing: RoutineGridMetrics.spacing)
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            // "Add" sits in the grid as another tile rather than as a separate button
            // below it, so the whole section reads as one block.
            LazyVGrid(columns: columns, spacing: RoutineGridMetrics.spacing) {
                ForEach(viewModel.routines) { routine in
                    RoutineCard(
                        routine: routine,
                        isActive: viewModel.activeRoutineIDs().contains(routine.id),
                        applicationTokens: viewModel.tokens(for: routine.id),
                        pausedUntil: viewModel.pausedUntil(for: routine.id),
                        onOpen: {
                            router.presentSheet(.routineEditor(RoutineEditorRoute(routineID: routine.id)))
                        }
                    )
                }

                addRoutineTile
            }

            #if DEBUG
            SecondaryButton("Unblock Everything", systemImage: "lock.open") {
                Task {
                    await viewModel.debugUnblockEverything()
                }
            }
            #endif
        }
        .onAppear {
            Task {
                await viewModel.load()
            }
        }
        .onChange(of: router.sheet) { _, newValue in
            guard newValue == nil else { return }
            Task {
                await viewModel.load()
            }
        }
        .alert(
            "Routine action failed",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.clearError() } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.clearError()
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private var addRoutineTile: some View {
        LocktyAddTile(title: "New Mode") {
            router.presentSheet(.routineEditor(RoutineEditorRoute(routineID: nil)))
        }
    }
}
