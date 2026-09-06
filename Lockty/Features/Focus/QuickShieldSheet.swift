import SwiftUI

/// A shield put up on the spot.
///
/// The one thing you cannot write down as a rule: how long, what it holds, and it starts
/// now. It runs as a transient routine that ends on the clock with the app closed, so
/// nothing is added to the library and nothing has to be cleaned up afterwards.
///
/// No name is asked for. A session is not a thing you keep -- it is called after the
/// moment it was made, and asking someone to name a five-minute block is asking a question
/// that outlives its answer.
///
/// The restrictions live on a screen of this sheet rather than in a sheet of their own:
/// the fake navigation bar is what the rest of the app uses for a next question, and a
/// second real sheet stacked on this one is a card on a card.
struct QuickShieldSheet: View {
    @ObservedObject var viewModel: QuickTimerViewModel
    @ObservedObject var frictionsViewModel: FrictionsViewModel
    let toastCenter: LocktyToastCenter
    var onClose: () -> Void

    /// Which question is on screen. One value, so there is no arrangement of flags that
    /// can put the sheet on two screens at once.
    enum Screen: String, Hashable {
        case shield
        case apps
        case friction
    }

    @State private var screen: Screen = .shield
    @State private var isGoingBack = false

    /// The lengths the dial steps through, and then no end at all.
    ///
    /// Not a range: five to thirty in fives and then in quarter hours is what people pick,
    /// where a step of one would take forty presses to reach an hour. Past the last of
    /// them is Infinite, which is the same decision carried to its end rather than a
    /// switch asking it again.
    private let lengths = [5, 10, 15, 20, 25, 30, 45, 60, 90, 120, 180, 240]

    private var isRunning: Bool { viewModel.endsAt != nil || viewModel.isInfinite && viewModel.isSessionRunning }

    var body: some View {
        LocktyDynamicSheet {
            ZStack {
                switch screen {
                case .shield: shieldScreen.transition(screenTransition)
                case .apps: appsScreen.transition(screenTransition)
                case .friction: frictionScreen.transition(screenTransition)
                }
            }
            .geometryGroup()
            .locktyDynamicSheetChrome(id: "quick-shield-\(screen.rawValue)-\(viewModel.isInfinite)") {
                Text(title)
                    .font(.system(.title3, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
            } leading: {
                leading
            } trailing: {
                Color.clear.frame(width: 44, height: 44)
            }
        }
        .task {
            await viewModel.load()
            await frictionsViewModel.load()
        }
    }

    private var title: String {
        switch screen {
        case .shield: "Shield"
        case .apps: "Blocked apps"
        case .friction: "Friction"
        }
    }

    @ViewBuilder
    private var leading: some View {
        if screen == .shield {
            LocktyDynamicSheetBarButton(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
            }
        } else {
            LocktyDynamicSheetBarButton(action: { move(to: .shield, back: true) }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .medium))
            }
        }
    }

    private var screenTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isGoingBack ? .leading : .trailing)
                .combined(with: AnyTransition(.blurReplace)),
            removal: .move(edge: isGoingBack ? .trailing : .leading)
                .combined(with: AnyTransition(.blurReplace))
        )
    }

    private func move(to next: Screen, back: Bool = false) {
        isGoingBack = back
        withAnimation(.smooth(duration: 0.32)) { screen = next }
    }

    // MARK: - The shield itself

    private var shieldScreen: some View {
        VStack(spacing: LocktySpacing.lg) {
            // Running, this is a countdown; idle, it is the dial that sets one. The same
            // place on the screen either way, because it is the same fact -- how long.
            if isRunning {
                countdown
            } else {
                dial
            }

            VStack(spacing: 0) {
                row(title: "Apps", value: viewModel.blockedSummary, isEnabled: !isRunning) { move(to: .apps) }

                divider

                row(title: "Friction", value: viewModel.frictionSummary, isEnabled: !isRunning) { move(to: .friction) }
            }
            .padding(.horizontal, LocktySpacing.cardInset)
            .locktyCardBackground(cornerRadius: 26)
            // Nothing is changed mid-session. What it holds was decided when it started,
            // and editing it now would leave the live shield and this screen describing
            // two different things.
            .opacity(isRunning ? 0.55 : 1)

            LocktyHoldButton(
                title: isRunning ? "Hold to finish" : "Hold to start",
                systemImage: isRunning ? "stop.circle" : "shield",
                tint: isRunning ? LocktyColors.unproductive : LocktyColors.productive
            ) {
                Task {
                    if isRunning {
                        await viewModel.stop()
                    } else {
                        await viewModel.start()
                        if viewModel.errorMessage == nil { onClose() }
                    }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.error)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.lg)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.lg))
    }

    /// What is left, ticking.
    private var countdown: some View {
        VStack(spacing: LocktySpacing.sm) {
            TimelineView(.periodic(from: Date(), by: 1)) { context in
                let seconds = remainingSeconds(at: context.date)

                Text(seconds == nil ? "∞" : clock(seconds!))
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .monospacedDigit()
                    .locktyNumericTransition(trigger: seconds ?? -1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }

            Text(viewModel.endsAt == nil ? "Until you stop it" : "Left of this shield")
                .font(.system(.footnote, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
        }
        .frame(maxWidth: .infinity)
    }

    private func remainingSeconds(at date: Date) -> Int? {
        guard let endsAt = viewModel.endsAt else { return nil }
        return max(Int(endsAt.timeIntervalSince(date)), 0)
    }

    private func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d:%02d", seconds / 3600, (seconds % 3600) / 60, seconds % 60)
    }

    /// Minus, the length, plus -- and one step past the end is no end.
    private var dial: some View {
        VStack(spacing: LocktySpacing.sm) {
            HStack(spacing: LocktySpacing.xl) {
                dialButton("minus", isDisabled: !viewModel.isInfinite && viewModel.minutes <= lengths.first!) {
                    step(by: -1)
                }

                Text(viewModel.isInfinite ? "∞" : lengthText)
                    .font(.system(size: 44, weight: .bold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.22), value: viewModel.minutes)
                    .animation(.snappy(duration: 0.22), value: viewModel.isInfinite)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity)

                dialButton("plus", isDisabled: viewModel.isInfinite) {
                    step(by: 1)
                }
            }

            Text(viewModel.isInfinite ? "Until you stop it" : "Then it lets go on its own")
                .font(.system(.footnote, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .contentTransition(.numericText())
        }
        .frame(maxWidth: .infinity)
        .sensoryFeedback(.selection, trigger: viewModel.minutes)
        .sensoryFeedback(.selection, trigger: viewModel.isInfinite)
    }

    private var lengthText: String {
        let minutes = viewModel.minutes
        guard minutes >= 60 else { return "\(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "\(hours)h" : "\(hours)h \(rest)m"
    }

    /// Walks the dial. Past the last length it turns infinite; one step back from infinite
    /// returns to that last length.
    private func step(by offset: Int) {
        if viewModel.isInfinite {
            guard offset < 0 else { return }
            withAnimation(.smooth(duration: 0.25)) {
                viewModel.isInfinite = false
                viewModel.minutes = lengths.last ?? 120
            }
            return
        }

        let index = lengths.firstIndex(of: viewModel.minutes) ?? 0
        let next = index + offset

        guard next < lengths.count else {
            withAnimation(.smooth(duration: 0.25)) {
                viewModel.isInfinite = true
                // Strict cannot survive the crossing: a block with no end that nothing can
                // stop is a phone you do not get back.
                viewModel.isStrict = false
            }
            return
        }

        guard next >= 0 else { return }
        viewModel.minutes = lengths[next]
    }

    private func dialButton(_ systemImage: String, isDisabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(LocktyColors.primaryText)

                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(LocktyColors.onPrimary)
            }
            .frame(width: 52, height: 52)
            .contentShape(Circle())
        }
        .buttonStyle(.locktyInteractive(shape: Circle()))
        .tappable()
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
    }

    // Strict as a row of its own on this screen. Moved into the selection screen with
    // everything else the session restricts -- strict mode *is* a restriction, and asking
    // for it in a different place than the apps, the categories and the adult content was
    // the one question in the wrong room. Kept below.
    //
//    private var strictRow: some View {
//        HStack(spacing: LocktySpacing.md) {
//            VStack(alignment: .leading, spacing: 2) {
//                Text("Strict")
//                    .font(.system(.body, design: .default, weight: .regular))
//                    .foregroundStyle(LocktyColors.primaryText)
//
//                Text(viewModel.isInfinite
//                     ? "Not while it has no end."
//                     : "Nothing can finish it early.")
//                    .font(.system(.footnote, design: .default, weight: .regular))
//                    .foregroundStyle(LocktyColors.tertiaryText)
//                    .contentTransition(.numericText())
//            }
//
//            Spacer(minLength: LocktySpacing.sm)
//
//            LocktySwitch(
//                isOn: Binding(
//                    get: { viewModel.isStrict && !viewModel.isInfinite },
//                    set: { viewModel.isStrict = $0 }
//                ),
//                isDisabled: viewModel.isInfinite
//            )
//        }
//        .frame(minHeight: 56)
//        .opacity(viewModel.isInfinite ? 0.5 : 1)
//    }

    private func row(
        title: String,
        value: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: { if isEnabled { action() } }) {
            HStack(spacing: LocktySpacing.md) {
                Text(title)
                    .font(.system(.body, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Spacer(minLength: LocktySpacing.sm)

                Text(value)
                    .font(.system(.body, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LocktyColors.tertiaryText)
            }
            .frame(minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
        .disabled(!isEnabled)
    }

    private var divider: some View {
        Divider().overlay(LocktyColors.separator.opacity(0.45))
    }

    // MARK: - The questions behind it

    private var appsScreen: some View {
        LocktyActivitySelectionView(
            title: "Selected",
            addLabel: "Add app or category",
            selection: Binding(
                get: { viewModel.selection },
                set: { viewModel.replaceSelection($0) }
            ),
            contentRestrictions: Binding(
                get: { viewModel.contentRestrictions },
                set: { viewModel.contentRestrictions = $0 }
            ),
            // Strict here, with the rest of what a session holds -- and refused outright
            // while it has no end: a block that cannot be stopped and does not expire is a
            // phone you do not get back.
            isStrict: viewModel.isInfinite ? nil : Binding(
                get: { viewModel.isStrict },
                set: { viewModel.isStrict = $0 }
            ),
            strictGuards: viewModel.isInfinite ? nil : Binding(
                get: { viewModel.strictGuards },
                set: { viewModel.strictGuards = $0 }
            ),
            // The whole sheet: apps, categories, groups, websites and the adult switches.
            // A session restricts exactly what a routine does; it simply does not outlive
            // the afternoon.
            rules: .routine,
            toastCenter: toastCenter,
            onClose: { move(to: .shield, back: true) },
            onDone: { move(to: .shield, back: true) }
        )
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.lg))
        // A tall sheet with the list scrolling inside it, which is what every other screen
        // of this kind asks for. Left to measure itself, the selection view is a whole
        // screen's worth of content and the sheet grew past the top of the display.
        .locktyDynamicSheetSizes([.large])
    }

    private var frictionScreen: some View {
        QuickTimerFrictionPicker(
            frictions: frictionsViewModel.frictions,
            selectedID: viewModel.frictionID,
            onSelect: { friction in
                viewModel.selectFriction(friction)
                move(to: .shield, back: true)
            }
        )
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.lg))
        .locktyDynamicSheetSizes([.large])
    }
}
