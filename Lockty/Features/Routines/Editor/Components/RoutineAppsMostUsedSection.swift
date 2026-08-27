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
                Text(usage.app.displayName)
                    .font(LocktyTypography.caption)
                    .foregroundStyle(LocktyColors.primaryText)
                Text(LocktyDurationFormatter.abbreviated(usage.duration))
                    .font(LocktyTypography.caption)
                    .foregroundStyle(LocktyColors.secondaryText)
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .foregroundStyle(isSelected ? LocktyColors.productive : LocktyColors.secondaryText)
            }
            .padding(.horizontal, LocktySpacing.sm)
            .padding(.vertical, LocktySpacing.sm)
            .safeGlass(radius: 12, interactive: true, tint: isSelected ? LocktyColors.productive.opacity(0.18) : nil)
        }
        .buttonStyle(.plain)
        .tappable()
    }
}
