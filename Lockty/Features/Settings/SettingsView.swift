import Combine
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    private let healthService: HealthServicing
    private let appGroupStore: AppGroupStore

    @Published private(set) var healthState: HealthAuthorizationState = .notRequested
    @Published private(set) var isRequestingHealth = false
    @Published private(set) var shieldScreen: ShieldScreenPreferences = .default
    @Published var errorMessage: String?

    init(healthService: HealthServicing, appGroupStore: AppGroupStore = AppGroupStore()) {
        self.healthService = healthService
        self.appGroupStore = appGroupStore
    }

    func refresh() {
        healthState = healthService.authorizationState()
        shieldScreen = appGroupStore.loadShieldScreenPreferences()
    }

    /// Written through on every change rather than on leaving the screen. The shield
    /// extension reads this file whenever a blocked app is opened, which can be before
    /// the person has gone anywhere.
    func setShieldStyle(_ style: ShieldScreenStyle) {
        shieldScreen.style = style
        persistShieldScreen()
    }

    func setShieldIntention(_ intention: String) {
        shieldScreen.intention = intention
        persistShieldScreen()
    }

    private func persistShieldScreen() {
        do {
            try appGroupStore.saveShieldScreenPreferences(shieldScreen)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// What the Personalize row says the shield is set to, without opening it.
    var shieldScreenSummary: String { shieldScreen.style.title }

    func connectHealth() async {
        guard !isRequestingHealth else { return }
        isRequestingHealth = true
        defer { isRequestingHealth = false }

        do {
            healthState = try await healthService.requestAuthorization()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

/// The app's own settings, as a list of cards rather than a system Form.
///
/// Less rounded than the cards on Today: these are rows in a list, and a list of pills
/// reads as a set of separate objects rather than as one menu.
struct SettingsView: View {
    @StateObject private var viewModel: SettingsViewModel
    @ObservedObject var access: SystemAccessViewModel
    @ObservedObject var router: AppRouter

    init(
        viewModel: SettingsViewModel,
        access: SystemAccessViewModel,
        router: AppRouter
    ) {
        _viewModel = StateObject(wrappedValue: viewModel)
        self.access = access
        self.router = router
    }

    private var cardRadius: CGFloat { 18 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                // What you can change, before what the system has allowed. One of these
                // is a decision and the other is a status, and a screen that opens on
                // statuses reads as a diagnostics page.
                section(title: "Personalize") {
                    navigationRow(
                        systemImage: "bell",
                        title: "Notifications",
                        subtitle: access.notificationState.detail
                    ) {
                        Task { await access.requestNotifications() }
                    }

                    navigationRow(
                        systemImage: "shield.lefthalf.filled",
                        title: "Block screens",
                        subtitle: "What the shield says when it stops you.",
                        value: viewModel.shieldScreenSummary
                    ) {
                        router.push(.blockScreens)
                    }

                    // No waiting room. A timed screen you sit through before an app opens
                    // teaches you to sit through it, and the thing worth interrupting is
                    // the scroll that has already started -- which is what Autofocus does.
                    navigationRow(
                        systemImage: "sparkles",
                        title: "Autofocus",
                        subtitle: "Steps in when a scroll runs long."
                    ) {
                        router.push(.distractingGroup)
                    }
                }

                section(title: "Permissions") {
                    accessRow(access.screenTimeState, systemImage: "hourglass") {
                        Task { await access.requestScreenTime() }
                    }

                    accessRow(access.notificationState, systemImage: "bell.badge") {
                        Task { await access.requestNotifications() }
                    }

                    accessRow(access.locationState, systemImage: "location") {
                        Task { await access.requestLocation() }
                    }

                    accessRow(access.alarmState, systemImage: "alarm") {
                        Task { await access.requestAlarms() }
                    }

                    healthRow
                }
            }
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.vertical, LocktySpacing.xl)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .task {
            viewModel.refresh()
            await access.refresh()
        }
        .alert("Health", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { viewModel.errorMessage = nil }
        } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            LocktySectionTitle(title, prominent: true)

            VStack(spacing: LocktySpacing.sm) {
                content()
            }
        }
    }

    /// A row that opens something, or asks for something. The chevron is the promise
    /// that there is more behind it, so a row with no screen behind it does not get one.
    private func navigationRow(
        systemImage: String,
        title: String,
        subtitle: String,
        value: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: LocktySpacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)

                    Text(subtitle)
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: LocktySpacing.sm)

                if let value {
                    Text(value)
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .lineLimit(1)
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LocktyColors.secondaryText)
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.md)
            .background(
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .fill(LocktyColors.ink(0.055))
            )
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: cardRadius, style: .continuous)))
        .tappable()
    }

    /// One permission: what it is, where it stands, and the button to ask for it when
    /// asking would still do something. Granted rows carry a tick and nothing to press --
    /// a button that reopens a system prompt iOS will never show again is a dead end.
    private func accessRow(
        _ state: SystemAccessItemState,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: LocktySpacing.md) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Text(state.detail)
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: LocktySpacing.sm)

            if state.isLoading {
                ProgressView()
            } else if let actionTitle = state.actionTitle {
                Button(actionTitle, action: action)
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.onPrimary)
                    .padding(.horizontal, LocktySpacing.md)
                    .frame(height: 34)
                    .background(Capsule(style: .continuous).fill(LocktyColors.primaryText))
                    .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
                    .tappable()
            } else {
                Image(systemName: "checkmark")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(LocktyColors.productive)
            }
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.md)
        .background(
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(LocktyColors.ink(0.055))
        )
    }

    /// Connecting Health, and what that connection can honestly claim.
    ///
    /// It says "Connected" once the sheet has been answered, never "Allowed": HealthKit
    /// deliberately refuses to tell an app whether a *read* was granted, so claiming
    /// access we may not have would be inventing a status.
    private var healthRow: some View {
        Button {
            Task { await viewModel.connectHealth() }
        } label: {
            HStack(spacing: LocktySpacing.md) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 2) {
                    Text("Steps")
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)

                    Text(viewModel.healthState.title)
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                }

                Spacer(minLength: 0)

                if viewModel.isRequestingHealth {
                    ProgressView()
                } else if viewModel.healthState == .requested {
                    Image(systemName: "checkmark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LocktyColors.productive)
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LocktyColors.secondaryText)
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.vertical, LocktySpacing.md)
            .background(
                RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                    .fill(LocktyColors.ink(0.055))
            )
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: cardRadius, style: .continuous)))
        .tappable()
        .disabled(viewModel.healthState == .unavailable)
        .opacity(viewModel.healthState == .unavailable ? 0.4 : 1)
    }

    private func statusRow(title: String, value: String) -> some View {
        HStack(spacing: LocktySpacing.md) {
            Text(title)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            Spacer(minLength: 0)

            Text(value)
                .font(.system(.footnote, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
        }
        .padding(.horizontal, LocktySpacing.md)
        .padding(.vertical, LocktySpacing.md)
        .background(
            RoundedRectangle(cornerRadius: cardRadius, style: .continuous)
                .fill(LocktyColors.ink(0.055))
        )
    }
}
