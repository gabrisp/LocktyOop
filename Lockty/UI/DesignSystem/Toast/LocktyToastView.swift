import FamilyControls
import ManagedSettings
import SwiftUI

extension View {
    /// Attaches the app's toast presenter. Applied once, at the root.
    func locktyToasts(_ center: LocktyToastCenter) -> some View {
        modifier(LocktyToastPresenter(center: center))
    }
}

private struct LocktyToastPresenter: ViewModifier {
    @Bindable var center: LocktyToastCenter

    @State private var overlayWindow: LocktyPassThroughWindow?
    @State private var controller: LocktyToastHostingController<LocktyToastOverlay>?

    func body(content: Content) -> some View {
        content
            .background(
                LocktyWindowExtractor { mainWindow in
                    attachOverlay(to: mainWindow)
                }
            )
            .onChange(of: center.isPresented, initial: true) { _, newValue in
                // The status bar goes while the island is expanded: the toast grows out
                // of the island's own cutout, and the clock sitting inside it reads as
                // the toast having swallowed it.
                controller?.isStatusBarHidden = newValue
            }
    }

    private func attachOverlay(to mainWindow: UIWindow) {
        guard let scene = mainWindow.windowScene else { return }

        // Reused, never stacked. A second overlay window would leave the first one above
        // it swallowing touches for a toast nobody can see.
        if let existing = scene.windows.first(where: { $0.tag == Self.windowTag }) as? LocktyPassThroughWindow {
            overlayWindow = existing
            controller = existing.rootViewController as? LocktyToastHostingController<LocktyToastOverlay>
            return
        }

        let window = LocktyPassThroughWindow(windowScene: scene)
        window.backgroundColor = .clear
        window.isHidden = false
        window.isUserInteractionEnabled = true
        window.tag = Self.windowTag

        let hosting = LocktyToastHostingController(rootView: LocktyToastOverlay(center: center))
        hosting.view.backgroundColor = .clear
        window.rootViewController = hosting

        overlayWindow = window
        controller = hosting
    }

    private static var windowTag: Int { 1009 }
}

/// The toast itself, growing out of the Dynamic Island.
///
/// The content is always laid out at its expanded size and *scaled* down to the island's
/// dimensions rather than being laid out small and grown. Laying it out at the small size
/// would re-wrap the text on every frame of the animation.
///
/// Adapted from Balaji Venkatesh's DynamicIslandToast.
struct LocktyToastOverlay: View {
    @Bindable var center: LocktyToastCenter

    private let islandWidth: CGFloat = 120
    private let islandHeight: CGFloat = 36

    var body: some View {
        GeometryReader { proxy in
            let safeArea = proxy.safeAreaInsets
            let size = proxy.size

            // A device with the island has a top inset tall enough to hold it. Without
            // one there is nothing to grow out of, so the toast drops in from above.
            let hasIsland = safeArea.top >= 59
            let topOffset = 11 + max(safeArea.top - 59, 0)

            let expandedWidth = size.width - 20
            let expandedHeight: CGFloat = hasIsland ? 90 : 74

            let scaleX = isExpanded ? 1 : (islandWidth / expandedWidth)
            let scaleY = isExpanded ? 1 : (islandHeight / expandedHeight)

            RoundedRectangle(cornerRadius: isExpanded ? 30 : islandHeight / 2, style: .continuous)
                .fill(.black)
                .overlay {
                    content(hasIsland: hasIsland)
                        .frame(width: expandedWidth, height: expandedHeight)
                        .scaleEffect(x: scaleX, y: scaleY)
                }
                .frame(
                    width: isExpanded ? expandedWidth : islandWidth,
                    height: isExpanded ? expandedHeight : islandHeight
                )
                .offset(y: hasIsland ? topOffset : (isExpanded ? safeArea.top + 10 : -110))
                .opacity(hasIsland ? 1 : (isExpanded ? 1 : 0))
                // On a device with an island the black capsule must disappear the instant
                // it has finished shrinking, not fade -- the real island is underneath it
                // and two blacks cross-fading reads as a flicker.
                .animation(.linear(duration: 0.02).delay(isExpanded ? 0 : 0.28)) { view in
                    view.opacity(hasIsland ? (isExpanded ? 1 : 0) : 1)
                }
                .geometryGroup()
                .contentShape(.rect)
                .gesture(
                    DragGesture().onEnded { value in
                        guard value.translation.height < 0 else { return }
                        center.dismiss()
                    }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .ignoresSafeArea()
                .animation(.bouncy(duration: 0.34, extraBounce: 0), value: isExpanded)
        }
    }

    private var isExpanded: Bool { center.isPresented }

    @ViewBuilder
    private func content(hasIsland: Bool) -> some View {
        if let toast = center.current {
            HStack(spacing: LocktySpacing.md) {
                leading(toast.leading)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 3) {
                    if hasIsland {
                        Spacer(minLength: 0)
                    }

                    HStack(alignment: .firstTextBaseline, spacing: LocktySpacing.sm) {
                        Text(toast.title)
                            .font(.callout.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)

                        Spacer(minLength: 0)

                        if let value = toast.value {
                            Text("\(value)\(toast.valueSuffix ?? "")")
                                .font(.callout.weight(.semibold))
                                .foregroundStyle(LocktyColors.productive)
                                .monospacedDigit()
                                .contentTransition(.numericText())
                        }
                    }

                    Text(toast.message)
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)

                    if let progress = toast.progress {
                        progressBar(progress)
                            .padding(.top, 3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, hasIsland ? 12 : 0)
            }
            .padding(.horizontal, 18)
            .compositingGroup()
            // Blurred away as it shrinks rather than just scaled: text scaled to a tenth
            // of its size is unreadable smearing, and the blur hides it landing.
            .blur(radius: isExpanded ? 0 : 5)
            .opacity(isExpanded ? 1 : 0)
        }
    }

    @ViewBuilder
    private func leading(_ leading: LocktyToast.Leading) -> some View {
        switch leading {
        case .symbol(let name, let tint):
            Image(systemName: name)
                .font(.system(size: 26, weight: .regular))
                .foregroundStyle(tint)

        case .appIcon(let token):
            Label(token)
                .labelStyle(.iconOnly)
                .id(token)
        }
    }

    /// Fills as the toast opens, so the bar arrives with the number rather than being
    /// drawn already full behind it.
    private func progressBar(_ progress: Double) -> some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.16))

                Capsule()
                    .fill(LocktyColors.productive)
                    .frame(width: proxy.size.width * (isExpanded ? min(max(progress, 0), 1) : 0))
                    .animation(.smooth(duration: 0.7).delay(0.15), value: isExpanded)
            }
        }
        .frame(height: 4)
    }
}
