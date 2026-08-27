import SwiftUI

struct SystemAccessSheet: View {
    @Bindable var viewModel: SystemAccessViewModel
    let router: AppRouter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: LocktySpacing.sm) {
                PrimaryButton("Request available access", systemImage: "checkmark.shield") {
                    Task { await viewModel.requestAllAvailable() }
                }
                SystemAccessRow(state: viewModel.screenTimeState) { Task { await viewModel.requestScreenTime() } }
                SystemAccessRow(state: viewModel.notificationState) { Task { await viewModel.requestNotifications() } }
                SystemAccessRow(state: viewModel.locationState) { Task { await viewModel.requestLocation() } }
                SystemAccessRow(state: viewModel.alarmState) { Task { await viewModel.requestAlarms() } }
                CardView {
                    VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                        Text("Restrictions")
                            .font(LocktyTypography.headline)
                            .foregroundStyle(LocktyColors.primaryText)
                        Text("Apps are selected inside each Routine or Pause. Websites are entered directly in the routine editor.")
                            .font(LocktyTypography.caption)
                            .foregroundStyle(LocktyColors.secondaryText)
                    }
                }
                CardView {
                    HStack {
                        Label("NFC", systemImage: "wave.3.right")
                        Spacer()
                        Text(SystemCapabilities.current.supportsNFC ? "Ready to scan" : "Unavailable")
                            .font(LocktyTypography.caption)
                            .foregroundStyle(LocktyColors.secondaryText)
                    }
                }
                Spacer()
            }
            .padding(LocktySpacing.md)
            .navigationTitle("System Access")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { await viewModel.refresh() }
        }
    }
}

private struct SystemAccessRow: View {
    let state: SystemAccessItemState
    let action: () -> Void

    var body: some View {
        CardView {
            HStack(spacing: LocktySpacing.md) {
                Image(systemName: state.title == "Screen Time" ? "hourglass" : state.title == "Location" ? "location" : "bell")
                    .frame(width: 28)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: LocktySpacing.xs) {
                    Text(state.title).font(LocktyTypography.headline)
                    Text(state.detail).font(LocktyTypography.caption).foregroundStyle(LocktyColors.secondaryText)
                }
                Spacer()
                if let actionTitle = state.actionTitle { Button(actionTitle, action: action).buttonStyle(.bordered) }
                else if state.detail.contains("Authorized") || state.detail == "Wheninuse" || state.detail == "Always" { Image(systemName: "checkmark.circle.fill").foregroundStyle(LocktyColors.productive) }
            }
        }
    }
}
