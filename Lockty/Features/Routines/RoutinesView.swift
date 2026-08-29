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
                        isActive: viewModel.activeRoutineID() == routine.id,
                        applicationTokens: viewModel.tokens(for: routine.id),
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
        Button {
            router.presentSheet(.routineEditor(RoutineEditorRoute(routineID: nil)))
        } label: {
            CardView(interactive: true, height: RoutineGridMetrics.tileHeight) {
                VStack(alignment: .leading, spacing: LocktySpacing.md) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .light))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(width: 24, height: 24)

                    Spacer(minLength: 0)

                    Text("Add Routine")
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .tappable()
    }
}
