import FamilyControls
import SwiftUI

/// AutoFocus, in one sheet.
///
/// It was four pushed screens -- the apps, the level, the friction, the cooldown --
/// which is a lot of travelling for four answers that only make sense together: the
/// friction is greyed out at the lowest level, and the cooldown means nothing without
/// the apps. One sheet with the picker as its second face, the way every other editor
/// in the app works.
struct DistractingGroupSheet: View {
    @ObservedObject var viewModel: DistractingGroupViewModel
    let frictions: [Friction]
    let toastCenter: LocktyToastCenter
    let manager: AutoFocusManager

    @Environment(\.dismiss) private var dismiss
    @State private var screen: Screen = .settings
    @State private var isGoingBack = false
    @State private var selection = FamilyActivitySelection()

    private enum Screen: String, Identifiable {
        case settings
        case apps
        case friction

        var id: String { rawValue }
    }

    private var sheetAnimation: Animation { .snappy(duration: 0.4, extraBounce: 0.02) }

    private var screenTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isGoingBack ? .leading : .trailing)
                .combined(with: AnyTransition(.blurReplace))
                .combined(with: .opacity),
            removal: .move(edge: isGoingBack ? .trailing : .leading)
                .combined(with: AnyTransition(.blurReplace))
                .combined(with: .opacity)
        )
    }

    var body: some View {
        LocktyDynamicSheet(animation: sheetAnimation) {
            content
                .locktyDynamicSheetChrome(id: screen.rawValue) {
                    Text(title)
                        .font(.system(.title3, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)
                } leading: {
                    leadingChrome
                } trailing: {
                    Color.clear.frame(width: 44, height: 44)
                }
        }
        .task {
            await viewModel.load()
            selection = manager.distractingSelection()
        }
    }

    private var title: String {
        switch screen {
        case .settings: "AutoFocus"
        case .apps: "Distracting apps"
        case .friction: "Friction"
        }
    }

    private var content: some View {
        ZStack {
            switch screen {
            case .settings:
                settingsScreen
                    .geometryGroup()
                    .transition(screenTransition)
            case .apps:
                appsScreen
                    .locktyDynamicSheetSizes([.large])
                    .geometryGroup()
                    .transition(screenTransition)
            case .friction:
                frictionScreen
                    .geometryGroup()
                    .transition(screenTransition)
            }
        }
        .geometryGroup()
    }

    @ViewBuilder
    private var leadingChrome: some View {
        if screen == .settings {
            LocktyDynamicSheetBarButton(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
            }
        } else {
            LocktyDynamicSheetBarButton(action: back) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
            }
        }
    }

    private func open(_ next: Screen) {
        isGoingBack = false
        withAnimation(sheetAnimation) { screen = next }
    }

    private func back() {
        isGoingBack = true
        withAnimation(sheetAnimation) { screen = .settings }
    }

    // MARK: - Settings

    private var settingsScreen: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            AppFolderCard(
                title: "Distracting",
                subtitle: viewModel.distractingTokens.count == 1 ? "1 app" : "\(viewModel.distractingTokens.count) apps",
                tokens: viewModel.distractingTokens,
                titleAlignment: .center
            )
            .frame(maxWidth: .infinity)

            // What it watches, then how hard it steps in, then what it says it with.
            VStack(spacing: 0) {
                row(
                    title: "Apps",
                    value: viewModel.distractingTokens.isEmpty
                        ? "Choose"
                        : (viewModel.distractingTokens.count == 1 ? "1 app" : "\(viewModel.distractingTokens.count) apps")
                ) {
                    open(.apps)
                }

                divider

                row(title: "Friction", value: viewModel.frictionName ?? "None") {
                    open(.friction)
                }
                .disabled(viewModel.configuration.interventionLevel == .low)
                .opacity(viewModel.configuration.interventionLevel == .low ? 0.45 : 1)
            }
            .padding(.horizontal, LocktySpacing.cardInset)
            .locktyCardBackground(cornerRadius: 22)

            levelCard

            LocktyCountRow(
                title: "Cooldown",
                value: Binding(
                    get: { viewModel.configuration.cooldownMinutes },
                    set: { minutes in Task { await viewModel.updateCooldown(minutes: minutes) } }
                ),
                range: 5...240,
                step: 5,
                suffix: "min",
                circleSize: 36,
                valueMinWidth: 84
            )
            .padding(.horizontal, LocktySpacing.cardInset)
            .locktyCardBackground(cornerRadius: 22)
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.md)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.md))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The level, with what it actually means underneath: a name on its own says how
    /// strongly you want interrupting without saying when that would happen.
    private var levelCard: some View {
        VStack(spacing: 0) {
            ForEach(Array(AutoFocusInterventionLevel.allCases.enumerated()), id: \.element) { index, level in
                if index > 0 { divider }

                Button {
                    Task { await viewModel.updateInterventionLevel(level) }
                } label: {
                    HStack(spacing: LocktySpacing.md) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(level.title)
                                .font(.system(.subheadline, design: .default, weight: .regular))
                                .foregroundStyle(LocktyColors.primaryText)

                            Text("Steps in after \(AutoFocusIntervention.thresholdMinutes(for: level)) min in a row.")
                                .font(.system(.footnote, design: .default, weight: .regular))
                                .foregroundStyle(LocktyColors.secondaryText)
                        }

                        Spacer(minLength: LocktySpacing.sm)

                        Image(systemName: viewModel.configuration.interventionLevel == level
                              ? "checkmark.circle.fill"
                              : "circle")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(
                                viewModel.configuration.interventionLevel == level
                                ? LocktyColors.productive
                                : LocktyColors.secondaryText
                            )
                    }
                    .padding(.vertical, LocktySpacing.md)
                    .frame(minHeight: 58)
                    .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)))
                .tappable()
            }
        }
        .padding(.horizontal, LocktySpacing.cardInset)
        .locktyCardBackground(cornerRadius: 22)
    }

    private func row(title: String, value: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: LocktySpacing.md) {
                Text(title)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Spacer(minLength: LocktySpacing.sm)

                Text(value)
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .lineLimit(1)

                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(LocktyColors.secondaryText)
            }
            .padding(.vertical, LocktySpacing.md)
            .frame(minHeight: 56)
            .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)))
        .tappable()
    }

    private var divider: some View {
        Divider().overlay(LocktyColors.separator.opacity(0.45))
    }

    // MARK: - Apps

    private var appsScreen: some View {
        LocktyActivitySelectionView(
            title: "Distracting",
            addLabel: "Add app",
            selection: Binding(
                get: { selection },
                set: { newValue in
                    selection = newValue
                    Task {
                        try? await manager.saveDistractingSelection(newValue)
                        await viewModel.load()
                    }
                }
            ),
            rules: .distracting,
            toastCenter: toastCenter,
            onClose: back,
            onDone: back
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    // MARK: - Friction

    private var frictionScreen: some View {
        QuickTimerFrictionPicker(
            frictions: frictions,
            selectedID: viewModel.configuration.frictionID,
            onSelect: { friction in
                Task {
                    await viewModel.updateFriction(friction?.id)
                    back()
                }
            }
        )
    }
}
