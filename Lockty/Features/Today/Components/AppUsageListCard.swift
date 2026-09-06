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
    /// Where the card leads. The breakdown answers everything this sheet did and more --
    /// the whole list, split by classification, over a day, a week or a month -- and it
    /// carries the pencil that changes what an app is called, so opening a sheet of the
    /// same rows here was a second, smaller version of a screen we already have.
    var onOpen: (() -> Void)?

    @State private var showAllApps = false

    private var visibleAppUsages: [AppUsageState] {
        Array(state.appUsages.prefix(5))
    }

    /// The day's screen time as Screen Time reports it, which is the figure the
    /// breakdown screen shows.
    ///
    /// Not the sum of the rows below. The report's total includes time it will not put a
    /// name to, so adding up the apps always came out short -- and the same day read two
    /// numbers depending on which screen you were on. The rows are still what they are;
    /// this heading is the day.
    private var totalDuration: TimeInterval {
        state.metrics.screenTime.duration > 0
            ? state.metrics.screenTime.duration
            : state.appUsages.reduce(0) { $0 + $1.duration }
    }

    private var largestVisibleDuration: TimeInterval {
        visibleAppUsages.map(\.duration).max() ?? 0
    }

    var body: some View {
        Button {
            guard let onOpen else {
                withAnimation(.smooth(duration: 0.24)) { showAllApps = true }
                return
            }
            onOpen()
        } label: {
            CardView(
                radius: LocktyRadius.medium,
                padding: LocktySpacing.xl,
                interactive: true,
                // The card wears the day's colour rather than a fixed mint. It was green
                // on the worst day anybody has ever had.
                tint: totalTint
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
                            .overlay(LocktyColors.ink(0.12))
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
                        // The rows are a picture of the day, not controls. Left
                        // hit-testable they took the tap for themselves -- an app icon
                        // drawn from a token especially -- so the bottom two thirds of a
                        // card that is one big button did nothing when pressed.
                        .allowsHitTesting(false)
                    }
                }
            }
            // The whole card, corner to corner. Without it the button is only where
            // something was actually drawn, so the gaps between the rows and the space
            // beside the heading were dead.
            .contentShape(Rectangle())
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
            // The same heading component the active mode card uses, in its chevron-only
            // form: this card is a button in its entirety, so the title must not take
            // the tap for itself.
            LocktySectionTitle("Screen Time", showsChevron: true)

            HStack(alignment: .firstTextBaseline, spacing: LocktySpacing.sm) {
                total

                // The arrow only. The sentence that used to go with it -- "24m more than
                // the other day" -- lives on the breakdown screen, where there is room
                // to say which day and over what period; here it is one mark saying
                // which way today went, in the colour of the answer.
                if let delta {
                    Image(systemName: delta >= 0 ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(totalTint)
                        .locktyPlaceholder(isPlaceholder)
                        .transition(.blurReplace)
                }
            }
            .animation(.smooth(duration: 0.3), value: state.metrics.screenTime.deltaVersusPreviousDay)
            .padding(.top, 4)

//            Text("Today")
//                .font(.system(.callout, design: .default, weight: .regular))
//                .foregroundStyle(LocktyColors.ink(0.56))
//                .padding(.top, 18)
        }
    }

    /// Which way today went against yesterday, if it went anywhere worth saying.
    private var delta: TimeInterval? {
        guard let delta = state.metrics.screenTime.deltaVersusPreviousDay, abs(delta) >= 60 else {
            return nil
        }
        return delta
    }

    /// The day's colour, on the same three bands everything else in the app is judged
    /// by: lighter than yesterday is green, heavier is red, and much the same is amber.
    ///
    /// Not two colours. A day fourteen minutes under yesterday is not a good day, it is
    /// yesterday again, and painting it green for being a minute on the right side of the
    /// line makes the colour mean nothing. Grey when there is no yesterday to compare
    /// with -- a first day has not gone any way yet.
    ///
    /// The number, the arrow beside it and the card's own tint all read this, because
    /// they are one answer: it looked like decoration when only the arrow carried it.
    private var totalTint: Color {
        guard let raw = state.metrics.screenTime.deltaVersusPreviousDay else {
            return LocktyColors.neutral
        }

        // A quarter of an hour either way. Below that the difference is noise, and the
        // day is an ordinary one.
        if raw >= 15 * 60 { return LocktyColors.productive }
        if raw <= -15 * 60 { return LocktyColors.unproductive }
        return LocktyColors.warning
    }

    private var total: some View {
        Text(totalDurationText)
            .font(.system(.largeTitle, design: .default, weight: .semibold))
            // The transition goes directly on the Text, before any layout modifier:
            // applied after padding it was decorating the padded container instead.
            // minimumScaleFactor is gone with it -- a text that is allowed to rescale
            // itself gets redrawn whole rather than animated digit by digit.
            .monospacedDigit()
            .locktyNumericTransition(trigger: totalDurationText)
            .foregroundStyle(totalTint)
            // A breath of softness, and no more than that: the figure is a total of
            // minutes Screen Time rounds on its own, and a number drawn razor-sharp
            // claims a precision it does not have.
            .blur(radius: 1.2)
            .animation(.smooth(duration: 0.3), value: totalTint)
            .lineLimit(1)
            .locktyPlaceholder(isPlaceholder)
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
                        // The same soft end the breakdown's bars and the gauges have.
                        Capsule(style: .continuous)
                            .fill(
                                LinearGradient(
                                    colors: [
                                        barColor,
                                        barColor.opacity(0.85),
                                        barColor.opacity(0.25),
                                        barColor.opacity(0)
                                    ],
                                    startPoint: .leading,
                                    endPoint: .trailing
                                )
                            )
                            .frame(width: max(22, available * progress), height: 4)
                            .blur(radius: 1.2)
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
