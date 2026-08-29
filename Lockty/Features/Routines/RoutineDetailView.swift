import FamilyControls
import SwiftUI

@MainActor
@Observable
final class RoutineDetailViewModel {
    private let routineID: UUID
    private let repository: RoutineRepository
    private let executionRepository: RoutineExecutionRepository
    private let routineEngine: RoutineEngine
    private let selectionStore: ScreenTimeSelectionStore

    private(set) var routine: Routine?
    private(set) var recentExecutions: [RoutineExecution] = []
    private(set) var selection = FamilyActivitySelection()
    var errorMessage: String?

    init(
        routineID: UUID,
        repository: RoutineRepository,
        executionRepository: RoutineExecutionRepository,
        routineEngine: RoutineEngine,
        selectionStore: ScreenTimeSelectionStore
    ) {
        self.routineID = routineID
        self.repository = repository
        self.executionRepository = executionRepository
        self.routineEngine = routineEngine
        self.selectionStore = selectionStore
    }

    func load() async {
        let routines = try? await repository.routines()
        routine = routines?.first(where: { $0.id == routineID })
        selection = (try? selectionStore.load(scope: .routine(routineID))) ?? FamilyActivitySelection()
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

    var schedule: RoutineSchedule? {
        guard let routine else { return nil }
        for trigger in routine.triggers {
            if case .schedule(let schedule) = trigger { return schedule }
        }
        return nil
    }

    var lastUsedText: String {
        guard let last = recentExecutions.first else { return "Never run yet" }
        return "Last run \(last.startedAt.formatted(date: .abbreviated, time: .shortened))"
    }
}

private func timeText(hour: Int, minute: Int) -> String {
    String(format: "%02d:%02d", hour, minute)
}

struct RoutineDetailView: View {
    @Bindable var viewModel: RoutineDetailViewModel
    let router: AppRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                if let routine = viewModel.routine {
                    VStack(spacing: LocktySpacing.sm) {
                        Text(viewModel.lastUsedText)
                            .font(.footnote)
                            .foregroundStyle(LocktyColors.tertiaryText)

                        Image(systemName: (routine.icon?.isEmpty == false ? routine.icon! : "repeat"))
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(LocktyColors.primaryText)
                            .frame(width: 50, height: 50)
                            .safeGlass(radius: 12)

                        Text(routine.name)
                            .font(LocktyTypography.body)
                            .foregroundStyle(LocktyColors.primaryText)

                        Text(routine.mode == .strict ? "Strict routine" : "Normal routine")
                            .font(LocktyTypography.caption)
                            .foregroundStyle(LocktyColors.secondaryText)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, LocktySpacing.lg)

                    VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                        Rectangle()
                            .fill(LocktyColors.separator)
                            .frame(height: 0.5)
                        Text("RESTRICTIONS")
                            .locktyEyebrow()

                        VStack(spacing: LocktySpacing.sm) {
                            RestrictionRow(
                                label: "Apps",
                                summary: RestrictionSummary.appsAndCategories(
                                    apps: viewModel.selection.applicationTokens.count,
                                    categories: viewModel.selection.categoryTokens.count
                                ),
                                tokens: viewModel.selection.applicationTokens.stablePrefix(3)
                            )
                            RestrictionRow(
                                label: "Domains",
                                summary: RestrictionSummary.domains(routine.blockedDomains.count)
                            )
                        }
                    }

                    VStack(alignment: .leading, spacing: LocktySpacing.md) {
                        Rectangle()
                            .fill(LocktyColors.separator)
                            .frame(height: 0.5)
                        Text("SCHEDULE")
                            .locktyEyebrow()

                        if let schedule = viewModel.schedule {
                            ScheduleDaysPicker(selectedWeekdays: .constant(schedule.weekdays))
                                .disabled(true)

                            VStack(spacing: LocktySpacing.sm) {
                                HStack {
                                    Text("Start :")
                                    Spacer()
                                    Text(timeText(hour: schedule.hour, minute: schedule.minute))
                                        .foregroundStyle(LocktyColors.primaryText)
                                }
                                HStack {
                                    Text("Finish :")
                                    Spacer()
                                    Text(timeText(hour: schedule.endHour, minute: schedule.endMinute))
                                        .foregroundStyle(LocktyColors.primaryText)
                                }
                            }
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.secondaryText)
                            .padding(.vertical, LocktySpacing.sm)
                        } else {
                            Text("Manual start only")
                                .font(LocktyTypography.callout)
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let routine = viewModel.routine {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Edit") {
                        router.presentSheet(.routineEditor(RoutineEditorRoute(routineID: routine.id)))
                    }
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Start") {
                    Task { await viewModel.start() }
                }
            }
        }
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(role: .destructive) {
                Task {
                    await viewModel.delete()
                    dismiss()
                }
            } label: {
                Text("Delete Routine")
            }
            .buttonStyle(.plain)
            .locktySecondaryActionStyle()
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.sm)
        }
    }
}
