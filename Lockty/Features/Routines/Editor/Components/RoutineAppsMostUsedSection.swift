import SwiftUI

struct RoutineAppsMostUsedSection: View {
    @Bindable var viewModel: RoutineEditorViewModel

    var body: some View {
        if !viewModel.mostUsedApplications.isEmpty {
            VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                Text("Most used")
                    .font(LocktyTypography.headline)
                    .foregroundStyle(LocktyColors.primaryText)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: LocktySpacing.sm) {
                        ForEach(viewModel.mostUsedApplications) { usage in
                            MostUsedAppChip(
                                usage: usage,
                                isSelected: viewModel.isMostUsedApplicationSelected(usage)
                            ) {
                                Task { await viewModel.toggleMostUsedApplication(usage) }
                            }
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }
}

private struct MostUsedAppChip: View {
    let usage: ApplicationUsage
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: LocktySpacing.sm) {
                AppIconView(
                    source: usage.app.iconSource,
                    applicationToken: usage.app.applicationToken,
                    fallbackSystemImage: usage.app.iconSystemName,
                    size: 28,
                    chrome: .plain
                )

                VStack(alignment: .leading, spacing: 2) {
                    Text(usage.app.displayName)
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)

                    Text(LocktyDurationFormatter.abbreviated(usage.duration))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .lineLimit(1)
                }

                if isSelected {
                    Text("Added")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(LocktyColors.productive)
                } else {
                    Text("Add")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(LocktyColors.secondaryText)
                }
            }
            .padding(.horizontal, LocktySpacing.sm)
            .padding(.vertical, LocktySpacing.sm)
            .safeGlass(
                radius: 14,
                interactive: true,
                tint: isSelected ? LocktyColors.productive.opacity(0.16) : nil
            )
        }
        .buttonStyle(.plain)
        .tappable()
    }
}
