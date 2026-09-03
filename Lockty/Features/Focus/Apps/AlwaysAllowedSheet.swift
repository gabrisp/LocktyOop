import FamilyControls
import SwiftUI

/// The apps nothing may block, in one sheet.
///
/// It was a pushed screen whose only control opened another sheet on top of it, so
/// editing the one list it holds meant two presentations stacked on a page that had
/// nothing else on it. Two faces in one dynamic sheet instead, like every other editor.
///
/// Deliberately plain: this is a list and one sentence about what being on it means.
/// Everything else in Focus is something you configure; this is something you exempt.
struct AlwaysAllowedSheet: View {
    @ObservedObject var viewModel: AppsLibraryViewModel
    let toastCenter: LocktyToastCenter
    let selectionStore: ScreenTimeSelectionStore

    @Environment(\.dismiss) private var dismiss
    @State private var isPickingApps = false
    @State private var isGoingBack = false
    @State private var selection = FamilyActivitySelection()

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
                .locktyDynamicSheetChrome(id: isPickingApps ? "apps" : "summary") {
                    Text(isPickingApps ? "Apps" : "Always Allowed")
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
            selection = (try? selectionStore.load(scope: .alwaysAllowed)) ?? FamilyActivitySelection()
        }
    }

    private var content: some View {
        ZStack {
            if isPickingApps {
                appsScreen
                    .locktyDynamicSheetSizes([.large])
                    .geometryGroup()
                    .transition(screenTransition)
            } else {
                summaryScreen
                    .geometryGroup()
                    .transition(screenTransition)
            }
        }
        .geometryGroup()
    }

    @ViewBuilder
    private var leadingChrome: some View {
        if isPickingApps {
            LocktyDynamicSheetBarButton(action: closeApps) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
            }
        } else {
            LocktyDynamicSheetBarButton(action: { dismiss() }) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .medium))
            }
        }
    }

    private func openApps() {
        // While a routine is running the list is sealed. Letting an app onto it mid-run
        // would release something the routine is currently holding shut, which is the
        // one edit that can undo a block from the outside.
        guard !viewModel.isAlwaysAllowedLocked else {
            toastCenter.show(.alwaysAllowedLocked())
            return
        }

        isGoingBack = false
        withAnimation(sheetAnimation) { isPickingApps = true }
    }

    private func closeApps() {
        isGoingBack = true
        withAnimation(sheetAnimation) { isPickingApps = false }
    }

    private var summaryScreen: some View {
        VStack(spacing: LocktySpacing.lg) {
            AppFolderCard(
                title: "Always Allowed",
                subtitle: viewModel.alwaysAllowedTokens.count == 1
                    ? "1 app"
                    : "\(viewModel.alwaysAllowedTokens.count) apps",
                tokens: viewModel.alwaysAllowedTokens,
                titleAlignment: .center
            )
            .frame(maxWidth: .infinity)

            Text("These apps are never blocked, not even when a rule blocks their whole category.")
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: openApps) {
                HStack(spacing: LocktySpacing.md) {
                    Text("Apps")
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)

                    Spacer(minLength: LocktySpacing.sm)

                    Text(viewModel.alwaysAllowedTokens.isEmpty
                         ? "Choose"
                         : (viewModel.alwaysAllowedTokens.count == 1 ? "1 app" : "\(viewModel.alwaysAllowedTokens.count) apps"))
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)

                    Image(systemName: viewModel.isAlwaysAllowedLocked ? "lock.fill" : "chevron.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(LocktyColors.secondaryText)
                }
                .padding(.vertical, LocktySpacing.md)
                .frame(minHeight: 56)
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 14, style: .continuous)))
            .tappable()
            .padding(.horizontal, LocktySpacing.cardInset)
            .locktyCardBackground(cornerRadius: 22)
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.md)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.md))
        .frame(maxWidth: .infinity, alignment: .center)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private var appsScreen: some View {
        LocktyActivitySelectionView(
            title: "Always Allowed",
            addLabel: "Add app",
            selection: Binding(
                get: { selection },
                set: { newValue in
                    selection = newValue
                    try? selectionStore.save(newValue, scope: .alwaysAllowed)
                    Task { await viewModel.load() }
                }
            ),
            rules: .appGroup,
            toastCenter: toastCenter,
            onClose: closeApps,
            onDone: closeApps
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
