import SwiftUI

/// The first screen: what Lockty needs, and why, before anything else happens.
///
/// Every permission is asked for here rather than at the moment it is first needed. That
/// is usually bad practice, and here it is the right thing: all four are asked for by
/// *background* code -- a shield going up with the app closed, a notification from an
/// extension, an alarm booked for tomorrow morning -- so a permission not granted does
/// not fail visibly at a moment anyone can connect to a prompt. It simply never happens.
///
/// Screen Time and Notifications are the two the app cannot work without: one is the
/// blocking itself, the other is the only route back into Lockty from a blocked app.
/// Alarms and Location are offered, said plainly to be optional, and skipped without
/// argument.
struct OnboardingView: View {
    @ObservedObject var viewModel: SystemAccessViewModel
    let onContinue: () -> Void

    /// Whether the two that matter are in place.
    private var canContinue: Bool {
        viewModel.screenTimeState.isGranted && viewModel.notificationState.isGranted
    }

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                header

                VStack(spacing: LocktySpacing.md) {
                    row(
                        state: viewModel.screenTimeState,
                        systemImage: "hourglass",
                        why: "The blocking itself. Without it Lockty can show you numbers and nothing else.",
                        isRequired: true
                    ) {
                        Task { await viewModel.requestScreenTime() }
                    }

                    row(
                        state: viewModel.notificationState,
                        systemImage: "bell",
                        why: "How a blocked app gets you back here, and how anything that happens while the app is closed reaches you.",
                        isRequired: true
                    ) {
                        Task { await viewModel.requestNotifications() }
                    }

                    row(
                        state: viewModel.alarmState,
                        systemImage: "alarm",
                        why: "Rings a few minutes before a scheduled routine starts, so it never begins without warning.",
                        isRequired: false
                    ) {
                        Task { await viewModel.requestAlarms() }
                    }

                    row(
                        state: viewModel.locationState,
                        systemImage: "location",
                        why: "Only for routines you set to start somewhere -- at the office, at the gym.",
                        isRequired: false
                    ) {
                        Task { await viewModel.requestLocation() }
                    }
                }

                VStack(spacing: LocktySpacing.sm) {
                    LocktyHoldButton(
                        title: canContinue ? "Hold to continue" : "Grant the two above",
                        systemImage: canContinue ? "arrow.right" : "lock",
                        tint: canContinue ? LocktyColors.productive : LocktyColors.neutral
                    ) {
                        guard canContinue else { return }
                        onContinue()
                    }
                    .disabled(!canContinue)
                    .opacity(canContinue ? 1 : 0.55)
                    .animation(.smooth(duration: 0.3), value: canContinue)

                    Text("Everything here is asked for by iOS. Lockty never sees your data -- it only asks the system to hold things shut.")
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.tertiaryText)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, LocktySpacing.sm)
            }
            .padding(.horizontal, LocktySpacing.screenInset)
            .padding(.top, LocktySpacing.xxl)
            .padding(.bottom, LocktySpacing.xl)
        }
        .task { await viewModel.refresh() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.md) {
            Image(systemName: "lock.shield")
                .font(.system(size: 38, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            Text("A few things first")
                .font(.system(size: 34, weight: .bold))
                .foregroundStyle(LocktyColors.primaryText)

            Text("Lockty holds apps shut while it is closed, which means iOS has to be asked first. Here is everything it will ask for, and what each one is for.")
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func row(
        state: SystemAccessItemState,
        systemImage: String,
        why: String,
        isRequired: Bool,
        action: @escaping () -> Void
    ) -> some View {
        CardView(radius: LocktyRadius.medium, padding: LocktySpacing.lg) {
            HStack(alignment: .top, spacing: LocktySpacing.md) {
                Image(systemName: systemImage)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(state.isGranted ? LocktyColors.productive : LocktyColors.primaryText)
                    .frame(width: 36, height: 36)
                    .background {
                        Circle().fill(
                            state.isGranted
                                ? LocktyColors.productive.opacity(0.14)
                                : LocktyColors.ink(0.07)
                        )
                    }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: LocktySpacing.sm) {
                        Text(state.title)
                            .font(.system(.subheadline, design: .default, weight: .semibold))
                            .foregroundStyle(LocktyColors.primaryText)

                        if !isRequired {
                            Text("OPTIONAL")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(LocktyColors.tertiaryText)
                        }
                    }

                    Text(why)
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: LocktySpacing.sm)

                trailing(state: state, action: action)
            }
        }
    }

    @ViewBuilder
    private func trailing(state: SystemAccessItemState, action: @escaping () -> Void) -> some View {
        if state.isLoading {
            ProgressView()
                .tint(LocktyColors.primaryText)
        } else if state.isGranted {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(LocktyColors.productive)
                .transition(.blurReplace)
        } else {
            Button(action: action) {
                Text("Allow")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .padding(.horizontal, LocktySpacing.lg)
                    .frame(height: 36)
                    .background {
                        Capsule(style: .continuous).fill(LocktyColors.ink(0.08))
                    }
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
            .tappable()
        }
    }
}
