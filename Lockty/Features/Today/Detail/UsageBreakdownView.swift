import SwiftUI

/// Where the time went, as a list rather than a set of cards.
///
/// The cards elsewhere are right for a summary you glance at; this is a thing you read
/// down, and a card around every section turns a list into a stack of panels with the
/// content squeezed inside them. Sections here are a heading, a total, and rows.
struct UsageBreakdownView: View {
    let day: Date
    @ObservedObject var viewModel: UsageBreakdownViewModel

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                periodPicker

                headline

                if viewModel.breakdown.hasData {
                    ForEach(viewModel.breakdown.sections) { section in
                        sectionView(section)
                    }
                } else {
                    emptyState
                }
            }
            .padding(.horizontal, LocktySpacing.screenInset)
            .padding(.vertical, LocktySpacing.lg)
        }
        .locktyScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The period lives in the bar, in place of the two chevrons a month-at-a-time
            // stepper would need. Stepping is the wrong gesture for "show me March": it
            // takes as many presses as there are months in between.
            ToolbarItem(placement: .principal) {
                Button {
                    viewModel.isChoosingPeriod = true
                } label: {
                    HStack(spacing: LocktySpacing.xs) {
                        Text(viewModel.periodTitle)
                            .font(.system(.headline, design: .default, weight: .semibold))
                            .foregroundStyle(LocktyColors.primaryText)
                            .contentTransition(.numericText())

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(LocktyColors.secondaryText)
                    }
                    .padding(.horizontal, LocktySpacing.md)
                    .frame(height: 36)
                    .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
                .tappable()
            }
        }
        .sheet(isPresented: $viewModel.isChoosingPeriod) {
            UsagePeriodPickerSheet(
                period: viewModel.period,
                selection: $viewModel.anchorDay
            )
        }
        .task(id: viewModel.period) { await viewModel.reload() }
        .task(id: viewModel.anchorDay) { await viewModel.reload() }
    }

    // MARK: - Period

    private var periodPicker: some View {
        HStack(spacing: 0) {
            ForEach(UsagePeriod.allCases) { period in
                Button {
                    withAnimation(.snappy(duration: 0.28)) { viewModel.period = period }
                } label: {
                    Text(period.title)
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(
                            viewModel.period == period
                            ? LocktyColors.primaryText
                            : LocktyColors.secondaryText
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: 44)
                        .contentShape(Capsule(style: .continuous))
                }
                .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
                .tappable()
                .background {
                    if viewModel.period == period {
                        Capsule(style: .continuous)
                            .fill(LocktyColors.ink(0.08))
                    }
                }
            }
        }
        .padding(3)
        .safeGlass(radius: 999, interactive: true)
    }

    // MARK: - Headline

    private var headline: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(LocktyDurationFormatter.abbreviated(viewModel.breakdown.headlineDuration))
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(LocktyColors.primaryText)
                .monospacedDigit()
                .contentTransition(.numericText())

            Text(viewModel.totalCaption)
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)

            if let delta = viewModel.breakdown.deltaVersusPrevious, abs(delta) >= 60 {
                HStack(spacing: 5) {
                    Image(systemName: delta >= 0 ? "arrowtriangle.down.fill" : "arrowtriangle.up.fill")
                        .font(.system(size: 11, weight: .bold))

                    Text("\(LocktyDurationFormatter.abbreviated(abs(delta))) \(viewModel.deltaCaption)")
                        .font(.system(.body, design: .default, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                }
                .foregroundStyle(delta >= 0 ? LocktyColors.productive : LocktyColors.unproductive)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            Text("Nothing recorded yet")
                .font(.system(.headline, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)

            Text("Screen Time delivers a day at a time, and this period has none of it yet.")
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, LocktySpacing.lg)
    }

    // MARK: - Sections

    private func sectionView(_ section: UsageBreakdownSection) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            HStack {
                Text(section.title)
                    .font(.system(.headline, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)

                Spacer(minLength: LocktySpacing.sm)

                Text(LocktyDurationFormatter.abbreviated(section.total))
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            ForEach(section.apps) { app in
                appRow(app, longest: viewModel.longestDuration)
            }

            if !section.foldedApps.isEmpty {
                foldedRow(section)
            }
        }
    }

    /// The bar is the row's whole point. A column of durations tells you the order; a
    /// column of bars tells you the *difference*, which is the thing that makes an hour
    /// on one app look like what it is next to eight minutes on another.
    private func appRow(_ app: UsageBreakdownApp, longest: TimeInterval) -> some View {
        HStack(spacing: LocktySpacing.md) {
            AppIconView(
                source: app.app.iconSource,
                applicationToken: app.app.applicationToken,
                fallbackSystemImage: app.app.iconSystemName,
                size: 38,
                chrome: .plain
            )

            VStack(alignment: .leading, spacing: 6) {
                Text(app.app.displayName)
                    .font(.system(.body, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)

                HStack(spacing: LocktySpacing.sm) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(LocktyColors.classification(app.classification))
                            .frame(
                                width: longest > 0
                                    ? max(proxy.size.width * CGFloat(app.duration / longest), 6)
                                    : 6,
                                height: 4
                            )
                            .animation(.smooth(duration: 0.5), value: app.duration)
                    }
                    .frame(height: 4)

                    Text(LocktyDurationFormatter.abbreviated(app.duration))
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(LocktyColors.classification(app.classification))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .fixedSize()
                }
            }
        }
        .frame(minHeight: 52)
    }

    /// The tail, as one row. The icons overlap so the row says how many without counting
    /// them out, which is all anyone wants to know about forty apps they opened once.
    private func foldedRow(_ section: UsageBreakdownSection) -> some View {
        HStack(spacing: LocktySpacing.md) {
            LocktyStackedAppTokens(
                tokens: section.foldedApps.compactMap(\.app.applicationToken)
            )

            VStack(alignment: .leading, spacing: 2) {
                Text(section.foldedApps.count == 1
                     ? "1 more app"
                     : "\(section.foldedApps.count) more apps")
                    .font(.system(.body, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .contentTransition(.numericText())

                Text("Under 5 min each")
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.tertiaryText)
            }

            Spacer(minLength: LocktySpacing.sm)

            Text(LocktyDurationFormatter.abbreviated(section.foldedTotal))
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.secondaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(minHeight: 52)
    }
}
