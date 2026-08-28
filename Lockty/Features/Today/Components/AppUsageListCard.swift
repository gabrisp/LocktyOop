import SwiftUI

struct AppUsageListCard: View {
    let state: TodayDayState
    let onClassificationChange: (AppUsageState, AppClassification) -> Void
    let onAppSelected: ((AppUsageState) -> Void)? = nil

    @State private var showAllApps = false

    private var visibleAppUsages: [AppUsageState] {
        Array(state.appUsages.prefix(4))
    }

    private var collapsedAppUsages: [AppUsageState] {
        Array(state.appUsages.dropFirst(4))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            HStack {
                Text("APPS")
                    .locktyEyebrow()

                Spacer()

                Text("\(state.appUsages.count)")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(LocktyColors.tertiaryText)
                    .locktyNumericTransition(trigger: state.appUsages.count)
            }
            .padding(.top, 16)

            CardView(radius: LocktyRadius.medium, padding: LocktySpacing.md) {
                VStack(alignment: .leading, spacing: 0) {
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
                        Button {
                            showAllApps = true
                        } label: {
                            MoreAppsRow(appUsages: collapsedAppUsages)
                                .padding(.vertical, LocktySpacing.sm)
                        }
                        .buttonStyle(.plain)
                    }
                }
                }
            }
        }
        .sheet(isPresented: $showAllApps) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(state.appUsages.enumerated()), id: \.element.id) { index, appUsage in
                        AppUsageListItem(
                            state: appUsage,
                            showsDivider: index < state.appUsages.count - 1,
                            onClassificationChange: { classification in
                                onClassificationChange(appUsage, classification)
                            }
                        )
                    }
                }
                .padding(LocktySpacing.md)
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
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
            HStack(spacing: -26) {
                ForEach(previewApps) { appUsage in
                    AppIconView(
                        source: appUsage.app.iconSource,
                        applicationToken: appUsage.app.applicationToken,
                        fallbackSystemImage: appUsage.app.iconSystemName,
                        size: 56,
                        chrome: .plain
                    )
                    .frame(width: 56, height: 56)
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
