import SwiftUI

@MainActor
@Observable
final class AppClassificationSheetViewModel {
    let appID: AppIdentity.ID
    private let repository: AppClassificationRepository

    private(set) var selection: AppClassification = .neutral

    init(
        appID: AppIdentity.ID,
        repository: AppClassificationRepository
    ) {
        self.appID = appID
        self.repository = repository
    }

    func load() async {
        selection = await repository.classification(for: appID) ?? .neutral
    }

    func update(_ classification: AppClassification) async {
        selection = classification
        await repository.saveClassification(classification, for: appID)
    }
}

struct AppClassificationSheet: View {
    @Bindable var viewModel: AppClassificationSheetViewModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(AppClassification.allCases) { classification in
                        Button {
                            Task {
                                await viewModel.update(classification)
                            }
                        } label: {
                            HStack {
                                Text(classification.title)
                                    .foregroundStyle(LocktyColors.classification(classification))
                                Spacer()
                                if classification == viewModel.selection {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(LocktyColors.primaryText)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: {
                    Text(viewModel.appID.rawValue)
                }
            }
            .navigationTitle("Classification")
        }
        .task {
            await viewModel.load()
        }
    }
}

@MainActor
@Observable
final class RoutineBreakSheetViewModel {
    let routineID: UUID
    private let routineEngine: RoutineEngine

    private(set) var activeRoutine: ActiveRoutine?
    private(set) var errorMessage: String?

    init(
        routineID: UUID,
        routineEngine: RoutineEngine
    ) {
        self.routineID = routineID
        self.routineEngine = routineEngine
    }

    func refresh() {
        activeRoutine = routineEngine.activeRoutine()
        if case .failed(let message) = routineEngine.state {
            errorMessage = message
        } else {
            errorMessage = nil
        }
    }

    func startBreak() async {
        await routineEngine.startBreak(trigger: .manual)
        refresh()
    }

    var canStartBreak: Bool {
        guard let activeRoutine, activeRoutine.routineID == routineID else { return false }
        return activeRoutine.breakPolicySnapshot.maximumBreaks > 0
            && activeRoutine.breakPolicySnapshot.allowedTriggers.contains(.manual)
    }
}

struct RoutineBreakSheet: View {
    @Bindable var viewModel: RoutineBreakSheetViewModel
    let router: AppRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                if let activeRoutine = viewModel.activeRoutine, activeRoutine.routineID == viewModel.routineID {
                    CardView {
                        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                            Text(activeRoutine.nameSnapshot)
                                .font(LocktyTypography.title)
                            Text("Manual breaks are controlled by the routine policy.")
                                .font(LocktyTypography.callout)
                                .foregroundStyle(LocktyColors.secondaryText)
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        CardView {
                            Text(errorMessage)
                                .font(LocktyTypography.callout)
                                .foregroundStyle(LocktyColors.unproductive)
                        }
                    }

                    PrimaryButton("Start Break", systemImage: "pause.fill") {
                        Task {
                            await viewModel.startBreak()
                            dismiss()
                        }
                    }
                    .disabled(!viewModel.canStartBreak)
                } else {
                    CardView {
                        Text("This routine is not currently active.")
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.secondaryText)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(LocktySpacing.md)
            .navigationTitle("Routine Break")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        dismiss()
                    }
                }
            }
        }
        .task {
            viewModel.refresh()
        }
    }
}
