import Combine
import SwiftUI

@MainActor
final class SettingsViewModel: ObservableObject {
    private let healthService: HealthServicing

    @Published private(set) var healthState: HealthAuthorizationState = .notRequested
    @Published private(set) var isRequestingHealth = false
    @Published var errorMessage: String?

    init(healthService: HealthServicing) {
        self.healthService = healthService
    }

    func refresh() {
        healthState = healthService.authorizationState()
    }

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

    init(viewModel: SettingsViewModel) {
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    private var cardRadius: CGFloat { 18 }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                section(title: "Health") {
                    healthRow
                }

                section(title: "System Services") {
                    statusRow(title: "Screen Time", value: "Managed in System Access")
                    statusRow(title: "Notifications", value: "Managed in System Access")
                    statusRow(title: "Location", value: "Managed in System Access")
                    statusRow(title: "NFC", value: "Available on supported devices")
                }
            }
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.vertical, LocktySpacing.xl)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .task {
            viewModel.refresh()
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
                    .fill(Color.white.opacity(0.055))
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
                .fill(Color.white.opacity(0.055))
        )
    }
}
