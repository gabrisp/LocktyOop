import SwiftUI

struct AppUsageListCard: View {
    let state: TodayDayState
    let onClassificationChange: (AppUsageState, AppClassification) -> Void
    let onAppSelected: ((AppUsageState) -> Void)? = nil

    private var visibleAppUsages: [AppUsageState] {
        state.appUsages.filter { $0.duration >= 60 }
    }

    private var collapsedAppUsages: [AppUsageState] {
        state.appUsages.filter { $0.duration < 60 }
    }

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

                if state.appUsages.isEmpty {
                    EmptyStateView(
                        title: "No apps yet",
                        message: "Lockty will list the applications used on this day as soon as Screen Time data is available.",
                        systemImage: "app.badge"
                    )
                    .padding(.vertical, LocktySpacing.md)
                } else {
                    ForEach(Array(visibleAppUsages.enumerated()), id: \.element.id) { index, appUsage in
                        AppUsageListItem(
                            state: appUsage,
                            showsDivider: index < visibleAppUsages.count - 1 || !collapsedAppUsages.isEmpty,
                            onClassificationChange: { classification in
                                onClassificationChange(appUsage, classification)
                            },
                            onSelected: {
                                onAppSelected?(appUsage)
                            }
                        )
                    }

                    if !collapsedAppUsages.isEmpty {
                        MoreAppsRow(appUsages: collapsedAppUsages)
                            .padding(.vertical, LocktySpacing.sm)
                    }
                }
            }
        }
    }
}

private struct AppUsageListItem: View {
    let state: AppUsageState
    let showsDivider: Bool
    let onClassificationChange: (AppClassification) -> Void
    let onSelected: (() -> Void)?

    init(
        state: AppUsageState,
        showsDivider: Bool,
        onClassificationChange: @escaping (AppClassification) -> Void,
        onSelected: (() -> Void)? = nil
    ) {
        self.state = state
        self.showsDivider = showsDivider
        self.onClassificationChange = onClassificationChange
        self.onSelected = onSelected
    }

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

private struct MoreAppsRow: View {
    let appUsages: [AppUsageState]

    private var previewApps: [AppUsageState] {
        Array(appUsages.prefix(3))
    }

    private var totalDuration: TimeInterval {
        appUsages.reduce(0) { $0 + $1.duration }
    }

    var body: some View {
        HStack(spacing: LocktySpacing.sm) {
            HStack(spacing: -8) {
                ForEach(Array(previewApps.enumerated()), id: \.element.id) { index, appUsage in
                    ZStack {
                        AppIconView(
                            source: appUsage.app.iconSource,
                            applicationToken: appUsage.app.applicationToken,
                            fallbackSystemImage: appUsage.app.iconSystemName,
                            size: 46,
                            chrome: .plain
                        )
                        .frame(width: 46, height: 46)

                        if index == previewApps.count - 1, appUsages.count > previewApps.count {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(.black.opacity(0.55))
                                .frame(width: 46, height: 46)
                                .overlay {
                                    Text("+\(appUsages.count - previewApps.count)")
                                        .font(.system(size: 12, weight: .bold, design: .default))
                                        .foregroundStyle(.white)
                                        .monospacedDigit()
                                        .minimumScaleFactor(0.7)
                                }
                        }
                    }
                    .frame(width: 46, height: 46)
                }
            }

            Text("More apps +\(appUsages.count)")
                .font(LocktyTypography.caption)
                .foregroundStyle(LocktyColors.secondaryText)

            Spacer()

            Text(LocktyDurationFormatter.abbreviated(totalDuration))
                .font(LocktyTypography.headline)
                .monospacedDigit()
                .foregroundStyle(LocktyColors.primaryText)
        }
    }
}
