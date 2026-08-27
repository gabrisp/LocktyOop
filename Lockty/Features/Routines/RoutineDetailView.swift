import SwiftUI

@MainActor
@Observable
final class RoutineDetailViewModel {
    private let routineID: UUID
    private let repository: RoutineRepository
    private let executionRepository: RoutineExecutionRepository
    private let routineEngine: RoutineEngine

    private(set) var routine: Routine?
    private(set) var recentExecutions: [RoutineExecution] = []
    var errorMessage: String?

    init(
        routineID: UUID,
        repository: RoutineRepository,
        executionRepository: RoutineExecutionRepository,
        routineEngine: RoutineEngine
    ) {
        self.routineID = routineID
        self.repository = repository
        self.executionRepository = executionRepository
        self.routineEngine = routineEngine
    }

    func load() async {
        let routines = try? await repository.routines()
        routine = routines?.first(where: { $0.id == routineID })
        recentExecutions = ((try? await executionRepository.executions(from: nil, to: nil)) ?? [])
            .filter { $0.routineID == routineID }
            .sorted { $0.startedAt > $1.startedAt }
    }

    func start() async {
        guard let routine else { return }
        await routineEngine.start(routine)
        if case .failed(let message) = routineEngine.state {
            errorMessage = message
        } else {
            errorMessage = nil
        }
        await load()
    }

    func delete() async {
        do {
            try await repository.delete(id: routineID)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct RoutineDetailView: View {
    @Bindable var viewModel: RoutineDetailViewModel
    let router: AppRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                if let routine = viewModel.routine {
                    CardView {
                        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                            Text(routine.name).font(LocktyTypography.title)
                            Text(routine.mode == .strict ? "Strict routine" : "Normal routine")
                                .font(LocktyTypography.callout)
                                .foregroundStyle(LocktyColors.secondaryText)
                            Text("\(routine.blockedApplications.count) apps · \(routine.blockedDomains.count) websites blocked")
                                .font(LocktyTypography.caption)
                                .foregroundStyle(LocktyColors.secondaryText)
                        }
                    }

                    if !routine.tasks.isEmpty {
                        CardView {
                            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                                Text("Checklist").font(LocktyTypography.headline)
                                ForEach(routine.tasks.sorted { $0.order < $1.order }) { task in
                                    HStack {
                                        Text(task.title)
                                        Spacer()
                                        if task.isOptional {
                                            Text("Optional").font(LocktyTypography.caption).foregroundStyle(LocktyColors.tertiaryText)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    CardView {
                        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                            Text("Recent Runs").font(LocktyTypography.headline)
                            if viewModel.recentExecutions.isEmpty {
                                Text("No executions recorded yet.")
                                    .font(LocktyTypography.callout)
                                    .foregroundStyle(LocktyColors.secondaryText)
                            } else {
                                ForEach(viewModel.recentExecutions.prefix(10)) { execution in
                                    HStack {
                                        Text(execution.startedAt.formatted(date: .abbreviated, time: .shortened))
                                        Spacer()
                                        Text(execution.endedAt.map { LocktyDurationFormatter.abbreviated($0.timeIntervalSince(execution.startedAt)) } ?? "Active")
                                            .foregroundStyle(LocktyColors.secondaryText)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.lg)
        }
        .navigationTitle(viewModel.routine?.name ?? "Routine")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                if let routine = viewModel.routine {
                    Button("Edit") {
                        router.push(.routineEditor(RoutineEditorRoute(routineID: routine.id)))
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Start") {
                    Task { await viewModel.start() }
                }
            }
            ToolbarItem(placement: .bottomBar) {
                Button("Delete", role: .destructive) {
                    Task {
                        await viewModel.delete()
                        dismiss()
                    }
                }
            }
        }
        .locktyScreenBackground()
        .task {
            await viewModel.load()
        }
        .alert(
            "Routine action failed",
            isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.errorMessage = nil
            }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }
}
