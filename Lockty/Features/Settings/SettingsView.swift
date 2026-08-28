import SwiftUI

struct SettingsView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                CardView {
                    VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                        SectionHeader(title: "System Services")

                        SettingsStatusRow(title: "Screen Time", value: "Managed in System Access")
                        SettingsStatusRow(title: "Notifications", value: "Managed in System Access")
                        SettingsStatusRow(title: "Location", value: "Managed in System Access")
                        SettingsStatusRow(title: "NFC", value: "Available on supported devices")
                        SettingsStatusRow(title: "Appwrite", value: "Offline-first boundary")
                    }
                }
            }
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.vertical, LocktySpacing.xl)
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }
}

private struct SettingsStatusRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(LocktyTypography.body)
                .foregroundStyle(LocktyColors.primaryText)

            Spacer()

            Text(value)
                .font(LocktyTypography.caption)
                .foregroundStyle(LocktyColors.secondaryText)
        }
    }
}
