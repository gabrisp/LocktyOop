import SwiftUI

struct RoutinesView: View {
    let viewModel: RoutinesViewModel
    let router: AppRouter

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            VStack(spacing: LocktySpacing.md) {
                if viewModel.routines.isEmpty {
                    CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                        EmptyStateView(
                            title: "No Routines Yet",
                            message: "Create your first routine and attach app or website restrictions.",
                            systemImage: "repeat"
                        )
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

                PrimaryButton("Create Routine", systemImage: "plus") {
                    router.presentSheet(.routineEditor(RoutineEditorRoute(routineID: nil)))
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
