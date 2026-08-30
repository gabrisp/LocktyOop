import SwiftUI

private enum FocusCreationScreen {
    case choice
    case rule
    case friction
}

struct FocusCreationChoiceSheet: View {
    @ObservedObject var router: AppRouter
    let makeRuleEditor: (@escaping () -> Void) -> AnyView
    let makeFrictionEditor: (@escaping () -> Void) -> AnyView
    let releaseRuleEditor: () -> Void
    let releaseFrictionEditor: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var screen: FocusCreationScreen = .choice
    @State private var isGoingBack = false

    private let columns = [
        GridItem(.flexible(), spacing: LocktySpacing.md),
        GridItem(.flexible(), spacing: LocktySpacing.md)
    ]

    var body: some View {
        LocktyDynamicSheet(animation: sheetAnimation) {
            ZStack {
                switch screen {
                case .choice:
                    choiceContent
                        .locktyDynamicSheetChrome(id: "focus-creation-choice") {
                            chromeTitle("Create")
                        } leading: {
                            LocktyDynamicSheetBarButton(action: dismissSheet) {
                                Image(systemName: "xmark")
                                    .font(.system(size: 15, weight: .medium))
                            }
                        } trailing: {
                            Color.clear
                                .frame(width: 44, height: 44)
                        }
                        .geometryGroup()
                        .transition(screenTransition)
                case .rule:
                    makeRuleEditor(returnToChoice)
                        .geometryGroup()
                        .transition(screenTransition)
                case .friction:
                    makeFrictionEditor(returnToChoice)
                        .geometryGroup()
                        .transition(screenTransition)
                }
            }
            .geometryGroup()
        }
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

    private var choiceContent: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(columns: columns, spacing: LocktySpacing.md) {
                creationTile(
                    title: "Rule",
                    subtitle: "Schedule, opens, limits",
                    systemImage: "line.3.horizontal.decrease.circle"
                ) {
                    open(.rule)
                }

                creationTile(
                    title: "Friction",
                    subtitle: "Games, prompts, proof",
                    systemImage: "sparkles.rectangle.stack"
                ) {
                    open(.friction)
                }
            }
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.vertical, LocktySpacing.lg)
        }
    }

    private func chromeTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(.title3, design: .default, weight: .regular))
            .foregroundStyle(LocktyColors.primaryText)
    }

    private func dismissSheet() {
        releaseRuleEditor()
        releaseFrictionEditor()
        dismiss()
    }

    private func open(_ next: FocusCreationScreen) {
        isGoingBack = false
        withAnimation(sheetAnimation) {
            screen = next
        }
    }

    private func returnToChoice() {
        isGoingBack = true
        withAnimation(sheetAnimation) {
            screen = .choice
        }
    }

    private func creationTile(
        title: String,
        subtitle: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            CardView(radius: LocktyRadius.large, interactive: true, height: 188) {
                VStack(alignment: .leading, spacing: LocktySpacing.md) {
                    Image(systemName: systemImage)
                        .font(.system(size: 22, weight: .light))
                        .foregroundStyle(LocktyColors.primaryText)

                    Spacer(minLength: 0)

                    Text(title)
                        .font(LocktyTypography.headline)
                        .foregroundStyle(LocktyColors.primaryText)

                    Text(subtitle)
                        .font(LocktyTypography.callout)
                        .foregroundStyle(LocktyColors.secondaryText)
                }
            }
        }
        .buttonStyle(.locktyInteractive)
        .tappable()
    }
}
