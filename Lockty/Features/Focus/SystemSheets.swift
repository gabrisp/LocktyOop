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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LocktyDynamicSheet {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                EditorTopBar(
                    title: "Classification",
                    confirmTitle: "Done",
                    onClose: { dismiss() },
                    onConfirm: { dismiss() }
                )

                CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                    VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                        Text(
                            AppIdentity.preferredDisplayName(
                                localizedDisplayName: nil,
                                bundleIdentifier: viewModel.appID.rawValue
                            )
                        )
                            .font(LocktyTypography.headline)
                            .foregroundStyle(LocktyColors.primaryText)

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
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, LocktySpacing.sm)
                                .frame(height: 44)
                                .safeGlass(
                                    radius: 14,
                                    interactive: classification != viewModel.selection,
                                    tint: classification == viewModel.selection ? LocktyColors.elevatedBackground : nil
                                )
                            }
                            .buttonStyle(.plain)
                            .tappable()
                        }
                    }
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.top, LocktySpacing.sm)
            .padding(.bottom, LocktySpacing.lg)
            .locktyScreenBackground()
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .task {
            await viewModel.load()
        }
    }
}

struct RoutineBreakSheet: View {
    @Bindable var viewModel: RoutineBreakSheetViewModel
    let router: AppRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LocktyDynamicSheet {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                EditorTopBar(
                    title: "Routine Break",
                    confirmTitle: "Done",
                    onClose: { dismiss() },
                    onConfirm: { dismiss() }
                )

                if let activeRoutine = viewModel.activeRoutine, activeRoutine.routineID == viewModel.routineID {
                    CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                            Text(activeRoutine.nameSnapshot)
                                .font(LocktyTypography.title)
                            Text("Manual breaks are controlled by the routine policy.")
                                .font(LocktyTypography.callout)
                                .foregroundStyle(LocktyColors.secondaryText)
                        }
                    }

                    if let errorMessage = viewModel.errorMessage {
                        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
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
                    CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                        Text("This routine is not currently active.")
                            .font(LocktyTypography.callout)
                            .foregroundStyle(LocktyColors.secondaryText)
                    }
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.top, LocktySpacing.sm)
            .padding(.bottom, LocktySpacing.lg)
            .locktyScreenBackground()
            .toolbarVisibility(.hidden, for: .navigationBar)
        }
        .task {
            viewModel.refresh()
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
