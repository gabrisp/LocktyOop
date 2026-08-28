import SwiftUI

@MainActor
@Observable
final class ActiveRoutineViewModel {
    let routineID: UUID
    private let routineEngine: RoutineEngine

    init(
        routineID: UUID,
        routineEngine: RoutineEngine
    ) {
        self.routineID = routineID
        self.routineEngine = routineEngine
    }

    var activeRoutine: ActiveRoutine? {
        routineEngine.activeRoutine()
    }

    var activeBreak: ActiveBreak? {
        if case .onBreak(_, let activeBreak) = routineEngine.state {
            return activeBreak
        }
        return nil
    }

    var errorMessage: String? {
        if case .failed(let message) = routineEngine.state {
            return message
        }
        return nil
    }

    var canStartManualBreak: Bool {
        guard let activeRoutine else { return false }
        return activeBreak == nil
            && activeRoutine.breakPolicySnapshot.maximumBreaks > 0
            && activeRoutine.breakPolicySnapshot.allowedTriggers.contains(.manual)
    }

    func toggleTaskCompletion(_ completion: RoutineTaskCompletion) async {
        guard completion.completedAt == nil else { return }
        await routineEngine.completeTask(completion.taskID)
    }

    func stopRoutine() async {
        await routineEngine.stop()
    }

    func startBreak() async {
        await routineEngine.startBreak(trigger: .manual)
    }

    func endBreak() async {
        await routineEngine.endBreakIfNeeded()
    }
}

struct ActiveRoutineView: View {
    @Bindable var viewModel: ActiveRoutineViewModel
    let router: AppRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Active Routine")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Image(systemName: "xmark")
                                .fontWeight(.ultraLight)
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("Open") {
                            router.push(.routineDetail(viewModel.routineID))
                        }
                    }
                }
        }
    }

    private var content: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                if let activeRoutine = viewModel.activeRoutine {
                    CardView {
                        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                            Text(activeRoutine.nameSnapshot)
                                .font(LocktyTypography.largeTitle)
                            Text(activeRoutine.modeSnapshot == .strict ? "Strict routine" : "Normal routine")
                                .font(LocktyTypography.callout)
                                .foregroundStyle(LocktyColors.secondaryText)
                            Text("Started \(activeRoutine.startedAt.formatted(date: .omitted, time: .shortened))")
                                .font(LocktyTypography.caption)
                                .foregroundStyle(LocktyColors.secondaryText)
                        }
                    }

                    if let activeBreak = viewModel.activeBreak {
                        CardView {
                            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                                Text("Break Active")
                                    .font(LocktyTypography.headline)
                                Text("Ends \(activeBreak.endsAt.formatted(date: .omitted, time: .shortened))")
                                    .font(LocktyTypography.callout)
                                    .foregroundStyle(LocktyColors.secondaryText)
                                PrimaryButton("End Break", systemImage: "play.fill") {
                                    Task {
                                        await viewModel.endBreak()
                                    }
                                }
                            }
                        }
                    } else if viewModel.canStartManualBreak {
                        CardView {
                            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                                Text("Breaks")
                                    .font(LocktyTypography.headline)
                                Text("Manual breaks are available for this routine.")
                                    .font(LocktyTypography.callout)
                                    .foregroundStyle(LocktyColors.secondaryText)
                                SecondaryButton("Start Break", systemImage: "pause.fill") {
                                    Task {
                                        await viewModel.startBreak()
                                    }
                                }
                            }
                        }
                    }

                    CardView {
                        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                            Text("Checklist")
                                .font(LocktyTypography.headline)

                            ForEach(activeRoutine.taskCompletions.sorted { $0.orderSnapshot < $1.orderSnapshot }) { completion in
                                Button {
                                    Task {
                                        await viewModel.toggleTaskCompletion(completion)
                                    }
                                } label: {
                                    HStack {
                                        Image(systemName: completion.completedAt == nil ? "circle" : "checkmark.circle.fill")
                                            .foregroundStyle(completion.completedAt == nil ? LocktyColors.tertiaryText : LocktyColors.productive)
                                        Text(completion.titleSnapshot)
                                            .font(LocktyTypography.callout)
                                            .foregroundStyle(LocktyColors.primaryText)
                                        Spacer()
                                        if let completedAt = completion.completedAt {
                                            Text(completedAt.formatted(date: .omitted, time: .shortened))
                                                .font(LocktyTypography.caption)
                                                .foregroundStyle(LocktyColors.secondaryText)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        CardView {
                            Text(errorMessage)
                                .font(LocktyTypography.callout)
                                .foregroundStyle(LocktyColors.unproductive)
                        }
                    }
                } else {
                    CardView {
                        Text("No active routine is available.")
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.secondaryText)
                    }
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.lg)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Button(role: .destructive) {
                Task {
                    await viewModel.stopRoutine()
                    dismiss()
                }
            } label: {
                Text("Stop Routine")
            }
            .buttonStyle(.plain)
            .locktySecondaryActionStyle()
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.sm)
        }
    }
}
