import FamilyControls
import SwiftUI

/// Distracting interventions, in one sheet.
///
/// It was four pushed screens -- the apps, the level, the friction, the cooldown -- which
/// is a lot of travelling for answers that only mean anything together. One sheet with
/// the picker as its second face, the way every other editor in the app works.
///
/// There is no friction here, and there cannot be. A friction is a screen that stands in
/// front of an app, and standing in front of an app is something Screen Time only lets
/// Lockty do against a block the person set up themselves. This fires off a threshold the
/// app noticed on its own, so what it can do is *say something* -- a notification, which
/// you can ignore. Offering a friction here would be offering a door we are not allowed
/// to close.
struct DistractingGroupSheet: View {
    @ObservedObject var viewModel: DistractingGroupViewModel
    let frictions: [Friction]
    let toastCenter: LocktyToastCenter
    let manager: AutoFocusManager

    @Environment(\.dismiss) private var dismiss
    @State private var screen: Screen = .settings
    @State private var isGoingBack = false
    @State private var isChoosingLevel = false
    @State private var selection = FamilyActivitySelection()

    private enum Screen: String, Identifiable {
        case settings
        case apps

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
        case .settings: "Interventions"
        case .apps: "Unproductive apps"
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
                title: "Unproductive",
                subtitle: viewModel.distractingTokens.count == 1 ? "1 app" : "\(viewModel.distractingTokens.count) apps",
                tokens: viewModel.distractingTokens,
                titleAlignment: .center
            )
            .frame(maxWidth: .infinity)

            Text("A notification, once you have been in these apps long enough. It cannot block anything: Lockty may only stand in front of an app against a block you set up yourself, and this one is noticed rather than chosen.")
                .font(.system(.footnote, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            VStack(spacing: 0) {
                row(
                    title: "Apps",
                    value: viewModel.distractingTokens.isEmpty
                        ? "Choose"
                        : (viewModel.distractingTokens.count == 1 ? "1 app" : "\(viewModel.distractingTokens.count) apps")
                ) {
                    open(.apps)
                }
            }
            .padding(.horizontal, LocktySpacing.cardInset)
            .locktyCardBackground(cornerRadius: 22)

            frequencyCard

            LocktySectionTitle("Intervention types", prominent: true)

            typesCard
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.md)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.md))
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// How often it interrupts, as one row with a menu.
    ///
    /// One dial, not two. "How often does this interrupt me" was being asked twice --
    /// once as a threshold and once as a cooldown -- which let the two be set against
    /// each other: a high level with a four-hour gap is not a high level.
    private var frequencyCard: some View {
        HStack(spacing: LocktySpacing.md) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Intervention frequency")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Text(viewModel.configuration.interventionLevel.summary)
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: LocktySpacing.sm)

            Button {
                isChoosingLevel = true
            } label: {
                HStack(spacing: LocktySpacing.xs) {
                    Text(viewModel.configuration.interventionLevel.title)
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)

                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(LocktyColors.tertiaryText)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .tappable()
            .locktyMenu(isPresented: $isChoosingLevel) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(AutoFocusInterventionLevel.allCases) { level in
                        LocktyMenuItem(
                            title: level.title,
                            subtitle: level.summary,
                            isSelected: viewModel.configuration.interventionLevel == level
                        ) {
                            isChoosingLevel = false
                            Task { await viewModel.updateInterventionLevel(level) }
                        }
                    }
                }
                .padding(.vertical, LocktySpacing.sm)
                .padding(.horizontal, LocktySpacing.xs)
                .frame(width: 260)
            }
        }
        .padding(.vertical, LocktySpacing.md)
        .frame(minHeight: 58)
        .padding(.horizontal, LocktySpacing.cardInset)
        .locktyCardBackground(cornerRadius: 22)
    }

    /// The kinds of intervention there are, which is one.
    ///
    /// A section for a single switch, because the list is the honest answer to "what can
    /// this do to me": one thing, and you can turn it off.
    private var typesCard: some View {
        HStack(spacing: LocktySpacing.md) {
            Image(systemName: "bell")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Text("A word when a scroll has run long.")
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
            }

            Spacer(minLength: LocktySpacing.sm)

            LocktySwitch(
                isOn: Binding(
                    get: { viewModel.configuration.notificationsEnabled },
                    set: { isOn in Task { await viewModel.setNotificationsEnabled(isOn) } }
                )
            )
        }
        .padding(.vertical, LocktySpacing.md)
        .frame(minHeight: 58)
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
            title: "Unproductive",
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

}
