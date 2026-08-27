import SwiftUI

struct AppUsageListCard: View {
    let state: TodayDayState
    let onClassificationChange: (AppUsageState, AppClassification) -> Void
    let onAppSelected: (AppUsageState) -> Void

    var body: some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("Apps")
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)

                    Spacer()

                    Text("\(state.appUsages.count)")
                        .font(LocktyTypography.caption)
                        .foregroundStyle(LocktyColors.tertiaryText)
                        .locktyNumericTransition(trigger: state.appUsages.count)
                }
                .padding(.bottom, LocktySpacing.xs)

                ForEach(Array(state.appUsages.enumerated()), id: \.element.id) { index, appUsage in
                    AppUsageListItem(
                        state: appUsage,
                        showsDivider: index < state.appUsages.count - 1,
                        onClassificationChange: { classification in
                            onClassificationChange(appUsage, classification)
                        },
                        onSelected: { onAppSelected(appUsage) }
                    )
                }
            }
        }
    }
}

private struct AppUsageListItem: View {
    let state: AppUsageState
    let showsDivider: Bool
    let onClassificationChange: (AppClassification) -> Void
    let onSelected: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            AppUsageRow(
                state: state,
                onClassificationChange: onClassificationChange,
                onSelected: onSelected
            )
            .padding(.vertical, LocktySpacing.sm)

            if showsDivider {
                Divider()
                    .overlay(LocktyColors.cardStroke.opacity(0.6))
            }
        }
    }
}
