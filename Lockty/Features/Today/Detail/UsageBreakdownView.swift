import FamilyControls
import ManagedSettings
import SwiftUI

/// Where the time went, as a list rather than a set of cards.
///
/// The cards elsewhere are right for a summary you glance at; this is a thing you read
/// down, and a card around every section turns a list into a stack of panels with the
/// content squeezed inside them. Sections here are a heading, a total, and rows.
struct UsageBreakdownView: View {
    let day: Date
    /// Owned, not observed.
    ///
    /// The destination factory builds a fresh view model every time the navigation stack
    /// re-evaluates its destinations, and an `@ObservedObject` would take the new one --
    /// which starts empty. That is the screen that "sometimes opens at zero": nothing had
    /// failed to load, the loaded object had just been replaced by a blank one.
    @StateObject private var viewModel: UsageBreakdownViewModel

    init(day: Date, viewModel: UsageBreakdownViewModel) {
        self.day = day
        _viewModel = StateObject(wrappedValue: viewModel)
    }

    /// Which row has its menu open. One id rather than a flag per row: two menus open at
    /// once is not a state this screen has.
    @State private var menuAppID: AppIdentity.ID?

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.xl) {
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
        // The app's own helper, which falls back to a safeAreaInset before 26. The
        // segmented control decides what the list *is*, so it stays put while the list
        // scrolls under it.
        .customSafeAreaBar(edge: .top, spacing: 0) {
            periodPicker
                .padding(.horizontal, LocktySpacing.screenInset)
                .padding(.bottom, LocktySpacing.md)
        }
        .locktyScreenBackground()
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // The period lives in the bar, in place of the two chevrons a month-at-a-time
            // stepper would need. Stepping is the wrong gesture for "show me March": it
            // takes as many presses as there are months in between.
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    withAnimation(.smooth(duration: 0.32)) { viewModel.isEditing.toggle() }
                } label: {
                    Image(systemName: viewModel.isEditing ? "checkmark" : "pencil")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(width: 36, height: 36)
                        .contentShape(Circle())
                }
                .buttonStyle(.locktyInteractive(shape: Circle()))
                .tappable()
            }

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
                if viewModel.isEditing {
                    editableRow(app)
                } else {
                    appRow(app, longest: viewModel.longestDuration)
                }
            }

            if !section.foldedApps.isEmpty {
                foldedRow(section)
            }
        }
    }

    /// A row while the list is being sorted: it looks exactly as it does when read, and
    /// opens the app's own menu.
    ///
    /// A menu rather than a tap that cycles. Cycling is fine for two values and a guess
    /// for three -- you press it and find out where you landed -- where a menu names all
    /// three and ticks the one that is true, which is the question being asked.
    private func editableRow(_ app: UsageBreakdownApp) -> some View {
        Button {
            menuAppID = app.id
        } label: {
            appRow(app, longest: viewModel.longestDuration)
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)))
        .tappable()
        .locktyMenu(
            isPresented: Binding(
                get: { menuAppID == app.id },
                set: { if !$0 { menuAppID = nil } }
            )
        ) {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(AppClassification.allCases, id: \.self) { classification in
                    LocktyMenuItem(
                        title: classification.title,
                        isSelected: app.classification == classification
                    ) {
                        menuAppID = nil
                        Task { await viewModel.setClassification(classification, of: app) }
                    }
                }
            }
            .padding(.vertical, LocktySpacing.sm)
            .padding(.horizontal, LocktySpacing.xs)
            .frame(width: 210)
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
                appName(app.app)
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

    /// The app's own name, from its token where there is one.
    ///
    /// `displayName` falls back to the bundle identifier for anything the app has not
    /// been told about, and the token is the only thing that carries the real, localized
    /// name Apple shows everywhere else.
    @ViewBuilder
    private func appName(_ app: AppIdentity) -> some View {
        if let token = app.applicationToken {
            Label(token).labelStyle(.titleOnly)
        } else {
            Text(app.displayName)
        }
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
