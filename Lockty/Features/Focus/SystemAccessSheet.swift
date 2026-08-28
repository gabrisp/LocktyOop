import SwiftUI

struct SystemAccessSheet: View {
    @Bindable var viewModel: SystemAccessViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        LocktyDynamicSheet {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                EditorTopBar(
                    title: "System Access",
                    confirmTitle: "Done",
                    onClose: { dismiss() },
                    onConfirm: { dismiss() }
                )

                PrimaryButton("Request available access", systemImage: "checkmark.shield") {
                    Task { await viewModel.requestAllAvailable() }
                }
                SystemAccessRow(state: viewModel.screenTimeState, systemImage: "hourglass") { Task { await viewModel.requestScreenTime() } }
                SystemAccessRow(state: viewModel.notificationState, systemImage: "bell") { Task { await viewModel.requestNotifications() } }
                SystemAccessRow(state: viewModel.locationState, systemImage: "location") { Task { await viewModel.requestLocation() } }
                SystemAccessRow(state: viewModel.alarmState, systemImage: "alarm") { Task { await viewModel.requestAlarms() } }

                CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                    VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                        Text("Restrictions")
                            .font(LocktyTypography.headline)
                            .foregroundStyle(LocktyColors.primaryText)
                        Text("Apps are selected inside each Routine or Pause. Websites are entered directly in the routine editor.")
                            .font(LocktyTypography.caption)
                            .foregroundStyle(LocktyColors.secondaryText)
                    }
                }
                CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                    HStack {
                        Label("NFC", systemImage: "wave.3.right")
                        Spacer()
                        Text(SystemCapabilities.current.supportsNFC ? "Ready to scan" : "Unavailable")
                            .font(LocktyTypography.caption)
                            .foregroundStyle(LocktyColors.secondaryText)
                    }
                }
            }
            .padding(.horizontal, LocktySpacing.md)
            .padding(.top, LocktySpacing.sm)
            .padding(.bottom, LocktySpacing.lg)
            .locktyScreenBackground()
            .toolbarVisibility(.hidden, for: .navigationBar)
            .task { await viewModel.refresh() }
        }
    }
}

private struct SystemAccessRow: View {
    let state: SystemAccessItemState
    let systemImage: String
    let action: () -> Void

    var body: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
            HStack(spacing: LocktySpacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .frame(width: 36, height: 36)
                    .foregroundStyle(LocktyColors.primaryText)
                    .safeGlass(radius: 18)
                VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                    Text(state.title)
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)
                    Text(state.detail)
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.secondaryText)
                }
                Spacer()
                if state.isLoading {
                    ProgressView()
                        .tint(LocktyColors.primaryText)
                } else if let actionTitle = state.actionTitle {
                    Button(action: action) {
                        Text(actionTitle)
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, LocktySpacing.md)
                    .frame(height: 36)
                    .safeGlass(radius: 18, interactive: true)
                } else if state.detail.contains("Authorized") || state.detail == "Wheninuse" || state.detail == "Always" {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(LocktyColors.productive)
                }
            }
        }
    }
}
