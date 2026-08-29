import SwiftUI

struct PauseView: View {
    @Bindable var viewModel: PauseViewModel
    let router: AppRouter
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        VStack(spacing: LocktySpacing.xl) {
            Spacer()

            VStack(spacing: LocktySpacing.md) {
                Text(viewModel.titleText)
                    .font(LocktyTypography.title)
                    .foregroundStyle(LocktyColors.secondaryText)

                Text(viewModel.primaryText)
                    .font(.system(size: viewModel.showsIntentionField ? 34 : 72, weight: .bold, design: .default))
                    .monospacedDigit()
                    .contentTransition(.numericText(countsDown: true))
                    .animation(.snappy(duration: 0.25), value: viewModel.primaryText)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(LocktyColors.primaryText)

                Text(viewModel.secondaryText)
                    .font(LocktyTypography.body)
                    .foregroundStyle(LocktyColors.secondaryText)
                    .multilineTextAlignment(.center)

                if viewModel.showsIntentionField {
                    TextField("Why are you opening this app?", text: $viewModel.intentionText, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(3...6)
                        .textInputAutocapitalization(.sentences)
                        .autocorrectionDisabled(false)
                }
            }
            .frame(maxWidth: .infinity)

            Spacer()

            VStack(spacing: LocktySpacing.md) {
                if case .breathing = viewModel.currentStep {
                    PrimaryButton("Complete Breath", systemImage: "wind") {
                        viewModel.registerBreath()
                    }
                } else {
                    PrimaryButton(
                        viewModel.continueButtonTitle,
                        systemImage: "checkmark",
                        isGated: !viewModel.canAdvance
                    ) {
                        Task {
                            let shouldDismiss = await viewModel.advance()
                            if shouldDismiss {
                                router.dismissFullScreen()
                            }
                        }
                    }
                    .disabled(!viewModel.canAdvance)
                }

                SecondaryButton("Stay locked", systemImage: "lock.fill") {
                    Task {
                        if await viewModel.stayLocked() {
                            router.dismissFullScreen()
                        }
                    }
                }
            }
        }
        .padding(LocktySpacing.xl)
        // Each tick gets a tap, and they firm up as the wait runs out, so the countdown
        // is felt getting closer rather than only watched.
        .sensoryFeedback(trigger: viewModel.remainingSeconds) { _, new in
            guard viewModel.isCountingDown, new > 0 else { return nil }
            let total = viewModel.countdownTotalSeconds
            let elapsed = total > 0 ? 1 - Double(new) / Double(total) : 0
            return .impact(weight: .light, intensity: 0.25 + 0.75 * elapsed)
        }
        // The one that lands when the gate opens.
        .sensoryFeedback(trigger: viewModel.canAdvance) { _, new in
            new ? .impact(weight: .medium, intensity: 1) : nil
        }
        .onAppear {
            viewModel.startIfNeeded()
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                viewModel.resume()
            } else {
                viewModel.pause()
            }
        }
    }
}
