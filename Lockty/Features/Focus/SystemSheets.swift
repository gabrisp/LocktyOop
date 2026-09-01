import Combine
import SwiftUI

@MainActor
final class AppClassificationSheetViewModel: ObservableObject {
    let appID: AppIdentity.ID
    private let repository: AppClassificationRepository

    @Published private(set) var selection: AppClassification = .neutral

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
    @ObservedObject var viewModel: AppClassificationSheetViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LocktyDynamicSheet {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                EditorTopBar(title: "Classification", onClose: { dismiss() })

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
        }
        .task {
            await viewModel.load()
        }
    }
}

struct RoutineBreakSheet: View {
    @ObservedObject var viewModel: RoutineBreakSheetViewModel
    let router: AppRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LocktyDynamicSheet {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                EditorTopBar(title: "Routine Break", onClose: { dismiss() })

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
        }
        .task {
            viewModel.refresh()
        }
    }
}

/// The time left on an app that is already open.
///
/// Tapping a released app used to reopen the unlock flow, which had nothing to ask: the
/// app is out, and the only thing worth knowing is how long for. So this shows exactly
/// that -- the app, the clock, and the way out.
struct AllowanceTimerSheet: View {
    let route: AllowanceTimerRoute
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LocktyDynamicSheet {
            VStack(spacing: LocktySpacing.lg) {
                LocktyAppLockBadge(
                    token: route.token,
                    scale: 2.2,
                    showsBorder: false
                )

                TimelineView(.periodic(from: .now, by: 1)) { context in
                    countdown(remaining: route.expiresAt.timeIntervalSince(context.date))
                }

                PrimaryButton("Cerrar", systemImage: "xmark") {
                    dismiss()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LocktySpacing.md)
            .padding(.top, LocktySpacing.lg)
            .padding(.bottom, LocktySpacing.lg)
        }
        .locktyDynamicSheetSizes([.fit])
    }

    private func countdown(remaining: TimeInterval) -> some View {
        let clamped = max(remaining, 0)
        let minutes = Int(clamped) / 60
        let seconds = Int(clamped) % 60

        return Text(String(format: "%d:%02d", minutes, seconds))
            .font(.system(size: 64, weight: .semibold, design: .rounded))
            .foregroundStyle(LocktyColors.primaryText)
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: true))
            .animation(.snappy(duration: 0.3), value: seconds)
    }
}

/// The wait, and the way out. There is no title bar: the sheet says one thing, and a
/// heading on the left would only name what the countdown underneath already is.
struct BreakStatusSheet: View {
    let state: BreakUnavailableState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LocktyDynamicSheet {
            VStack(spacing: LocktySpacing.lg) {
                // Two different answers, and they must not be dressed as one: a
                // cooldown is a wait with an end, a spent limit is not a wait at all.
                Text(state.retryAt == nil ? "No unlocks left" : "Please wait for the next unlock")
                    .font(.footnote)
                    .foregroundStyle(LocktyColors.tertiaryText)
                    .multilineTextAlignment(.center)

                if let retryAt = state.retryAt {
                    // Redrawn every second against the retry date, so the digits actually
                    // run down instead of showing the minute count the sheet opened with.
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        countdown(remaining: retryAt.timeIntervalSince(context.date))
                    }
                } else {
                    Text(state.message)
                        .font(LocktyTypography.body)
                        .foregroundStyle(LocktyColors.primaryText)
                        .multilineTextAlignment(.center)
                }

                PrimaryButton("Cerrar", systemImage: "xmark") {
                    dismiss()
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, LocktySpacing.md)
            .padding(.top, LocktySpacing.lg)
            .padding(.bottom, LocktySpacing.lg)
        }
        .locktyDynamicSheetSizes([.fit])
    }

    private func countdown(remaining: TimeInterval) -> some View {
        let clamped = max(remaining, 0)
        let minutes = Int(clamped) / 60
        let seconds = Int(clamped) % 60

        return Text(String(format: "%d:%02d", minutes, seconds))
            .font(.system(size: 56, weight: .semibold, design: .rounded))
            .foregroundStyle(LocktyColors.primaryText)
            .monospacedDigit()
            .contentTransition(.numericText(countsDown: true))
            .animation(.snappy(duration: 0.3), value: seconds)
    }
}

@MainActor
final class RoutineBreakSheetViewModel: ObservableObject {
    let routineID: UUID
    private let routineEngine: RoutineEngine

    @Published private(set) var activeRoutine: ActiveRoutine?
    @Published private(set) var errorMessage: String?

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
