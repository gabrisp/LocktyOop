import SwiftUI

struct PauseView: View {
    @Bindable var viewModel: PauseViewModel
    let router: AppRouter

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
                    PrimaryButton(viewModel.continueButtonTitle, systemImage: "checkmark") {
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
        .locktyScreenBackground()
        .onAppear {
            viewModel.startIfNeeded()
        }
    }
}
