import SwiftUI

struct RoutinesView: View {
    let viewModel: RoutinesViewModel
    let router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                    Text("Routines")
                        .font(LocktyTypography.largeTitle)
                        .foregroundStyle(LocktyColors.primaryText)

                    Text("Repeatable focus flows, not a task inbox.")
                        .font(LocktyTypography.callout)
                        .foregroundStyle(LocktyColors.secondaryText)
                }

                Spacer()

                IconButton(systemImage: "plus", accessibilityLabel: "Create Routine") {
                    router.push(.routineEditor(RoutineEditorRoute(routineID: nil)))
                }
            }

            VStack(spacing: LocktySpacing.md) {
                if viewModel.routines.isEmpty {
                    CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                        VStack(alignment: .leading, spacing: LocktySpacing.md) {
                            EmptyStateView(
                                title: "No Routines Yet",
                                message: "Create your first routine and attach real app or website restrictions.",
                                systemImage: "repeat"
                            )

                            PrimaryButton("Create Routine", systemImage: "plus") {
                                router.push(.routineEditor(RoutineEditorRoute(routineID: nil)))
                            }
                        }
                    }
                } else {
                    ForEach(viewModel.routines) { routine in
                        RoutineCard(
                            routine: routine,
                            isActive: viewModel.activeRoutineID() == routine.id,
                            onStart: {
                                Task {
                                    await viewModel.start(routine)
                                    await viewModel.load()
                                }
                            },
                            onOpen: {
                                router.push(.routineDetail(routine.id))
                            }
                        )
                    }
                }
            }
        }
        .onAppear {
            Task {
                await viewModel.load()
            }
        }
        .onChange(of: router.path) { _, _ in
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
}
