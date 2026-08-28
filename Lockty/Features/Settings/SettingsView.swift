import SwiftUI

struct SettingsView: View {
    let theme: ThemeManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                CardView {
                    VStack(alignment: .leading, spacing: LocktySpacing.md) {
                        SectionHeader(title: "Accent")

                        GlassContainerCompat(spacing: LocktySpacing.sm) {
                            HStack(spacing: LocktySpacing.sm) {
                                ForEach(LocktyAccent.allCases) { accent in
                                    Button {
                                        theme.selectAccent(accent)
                                    } label: {
                                        HStack(spacing: LocktySpacing.sm) {
                                            Circle()
                                                .fill(accent.color)
                                                .frame(width: 14, height: 14)

                                            Text(accent.title)
                                                .font(LocktyTypography.callout)
                                        }
                                        .padding(.horizontal, LocktySpacing.md)
                                        .padding(.vertical, LocktySpacing.sm)
                                        .safeGlass(
                                            radius: LocktyRadius.medium,
                                            interactive: true,
                                            tint: theme.accent == accent ? accent.color.opacity(0.22) : nil
                                        )
                                    }
                                    .buttonStyle(.plain)
                                    .tappable()
                                }
                            }
                        }
                    }
                }

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
        .locktyScreenBackground()
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
