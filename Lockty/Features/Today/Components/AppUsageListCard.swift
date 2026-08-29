import SwiftUI

struct AppUsageListCard: View {
    let state: TodayDayState

    /// Whether the numbers in this card are placeholders. Used per value, never on the
    /// card as a whole: the labels, the divider and the layout are real from the start.
    private var isPlaceholder: Bool {
        state.loadingState != .loaded
    }
    let onClassificationChange: (AppUsageState, AppClassification) -> Void
    let onAppSelected: ((AppUsageState) -> Void)? = nil

    @State private var showAllApps = false

    private var visibleAppUsages: [AppUsageState] {
        Array(state.appUsages.prefix(5))
    }

    private var totalDuration: TimeInterval {
        state.appUsages.reduce(0) { $0 + $1.duration }
    }

    private var largestVisibleDuration: TimeInterval {
        visibleAppUsages.map(\.duration).max() ?? 0
    }

    var body: some View {
        Button {
            withAnimation(.smooth(duration: 0.24)) {
                showAllApps = true
            }
        } label: {
            CardView(
                radius: LocktyRadius.medium,
                padding: LocktySpacing.xl,
                interactive: true,
                tint: Color(red: 0.82, green: 0.98, blue: 0.88)
            ) {
                VStack(alignment: .leading, spacing: 0) {
                    header

                    if state.appUsages.isEmpty {
                        EmptyStateView(
                            title: "No apps yet",
                            message: "Lockty will show the applications used on this day as soon as Screen Time data is available.",
                            systemImage: "app.badge"
                        )
                        .padding(.top, LocktySpacing.xl)
                    } else {
                        Divider()
                            .overlay(Color.white.opacity(0.12))
                            .padding(.top, 18)
                            .padding(.bottom, 26)

                        VStack(alignment: .leading, spacing: 14) {
                            ForEach(visibleAppUsages) { appUsage in
                                AppUsageSummaryRow(
                                    state: appUsage,
                                    largestDuration: largestVisibleDuration,
                                    isPlaceholder: isPlaceholder
                                )
                            }
                        }
                    }
                }
            }
        }
        .buttonStyle(.locktyInteractive)
        .tappable()
        .sheet(isPresented: $showAllApps) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(state.appUsages.enumerated()), id: \.element.id) { index, appUsage in
                        AppUsageListItem(
                            state: appUsage,
                            showsDivider: index < state.appUsages.count - 1,
                            onClassificationChange: { classification in
                                onClassificationChange(appUsage, classification)
                            },
                            onSelected: {
                                onAppSelected?(appUsage)
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

    private var header: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .center, spacing: LocktySpacing.sm) {
                Text("Tiempo de uso")
                    .font(.system(.headline, design: .default, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.72))
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(.subheadline, design: .default, weight: .medium))
                    .foregroundStyle(Color.white.opacity(0.58))

                Spacer(minLength: 0)
            }

            Text(totalDurationText)
                .font(.system(.largeTitle, design: .default, weight: .semibold))
                // The transition goes directly on the Text, before any layout modifier:
                // applied after padding it was decorating the padded container instead.
                // minimumScaleFactor is gone with it -- a text that is allowed to rescale
                // itself gets redrawn whole rather than animated digit by digit.
                .monospacedDigit()
                .locktyNumericTransition(trigger: totalDurationText)
                .foregroundStyle(LocktyColors.primaryText)
                .lineLimit(1)
                .locktyPlaceholder(isPlaceholder)
                .padding(.top, 4)

//            Text("Hoy")
//                .font(.system(.callout, design: .default, weight: .regular))
//                .foregroundStyle(Color.white.opacity(0.56))
//                .padding(.top, 18)
        }
    }

    private var totalDurationText: String {
        guard totalDuration > 0 else { return "--" }
        return LocktyDurationFormatter.abbreviated(totalDuration)
            .replacingOccurrences(of: "h", with: " h")
            .replacingOccurrences(of: "m", with: " min")
            .replacingOccurrences(of: "  ", with: " ")
            .trimmingCharacters(in: .whitespaces)
    }
}

private struct AppUsageSummaryRow: View {
    let state: AppUsageState
    let largestDuration: TimeInterval
    var isPlaceholder = false

    /// Room kept for the duration so the longest bar still leaves space for it.
    private let durationColumnWidth: CGFloat = 64

    private var progress: CGFloat {
        guard largestDuration > 0 else { return 0 }
        return max(0.18, min(CGFloat(state.duration / largestDuration), 1))
    }

    private var barColor: Color {
        switch state.classification {
        case .productive:
            Color(red: 0.78, green: 0.98, blue: 0.64)
        case .neutral:
            Color(red: 0.60, green: 0.93, blue: 0.89)
        case .unproductive:
            Color(red: 0.97, green: 0.43, blue: 0.56)
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: LocktySpacing.md) {
            AppIconView(
                source: state.app.iconSource,
                applicationToken: state.app.applicationToken,
                fallbackSystemImage: state.app.iconSystemName,
                size: 50,
                chrome: .plain
            )
            .locktyPlaceholder(isPlaceholder)

            VStack(alignment: .leading, spacing: 0) {
                LocktyAppNameText(app: state.app, scale: 0.86)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)
                    .locktyPlaceholder(isPlaceholder)

                // The duration sits right after the bar ends, not pinned to the far
                // right: the bar used to take all the remaining width, which pushed the
                // number away from the thing it labels. The bar is measured against the
                // width left over once room for the number is set aside, so a full-length
                // bar still has somewhere to put it.
                GeometryReader { geometry in
                    let available = max(0, geometry.size.width - durationColumnWidth)

                    HStack(alignment: .center, spacing: LocktySpacing.sm) {
                        Capsule(style: .continuous)
                            .fill(barColor)
                            .frame(width: max(22, available * progress), height: 4)
                            .locktyPlaceholder(isPlaceholder)

                        Text(state.durationText)
                            .font(.system(.subheadline, design: .default, weight: .regular))
                            .foregroundStyle(barColor)
                            .monospacedDigit()
                            .lineLimit(1)
                            .fixedSize(horizontal: true, vertical: false)
                            .locktyNumericTransition(trigger: state.durationText)
                            .locktyPlaceholder(isPlaceholder)

                        Spacer(minLength: 0)
                    }
                    .frame(width: geometry.size.width, alignment: .leading)
                }
                // Just tall enough for the duration text. It used to be 22 around a 6pt
                // bar, so the extra slack was centred as another ~8pt of gap above it.
                .frame(height: 18)
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
