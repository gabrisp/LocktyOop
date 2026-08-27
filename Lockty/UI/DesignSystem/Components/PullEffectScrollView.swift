import SwiftUI

struct PullEffectScrollView<Content: View>: View {
    var dragDistance: CGFloat = 88
    var actionTopPadding: CGFloat = 0
    @Binding var centerRefreshing: Bool
    @Binding var scrollOffset: CGFloat
    let onRefresh: () async -> Void
    @ViewBuilder var content: Content

    @State private var effectProgress: CGFloat = 0
    @GestureState private var isGestureActive: Bool = false
    @State private var initialScrollOffset: CGFloat?
    @State private var isArmed = false
    @State private var hapticsTrigger = false
    @State private var gestureStartedFromLeadingEdge = false
    @State private var displayTopPadding: CGFloat = 0

    private let refreshingTopPadding: CGFloat = 56

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            content
                .padding(.top, displayTopPadding)
        }
        .scrollBounceBehavior(.always)
        .onScrollGeometryChange(for: CGFloat.self) { geometry in
            geometry.contentOffset.y + geometry.contentInsets.top
        } action: { _, newValue in
            scrollOffset = newValue
        }
        .onChange(of: isGestureActive) { _, newValue in
            initialScrollOffset = newValue ? scrollOffset.rounded() : nil
            if !newValue {
                gestureStartedFromLeadingEdge = false
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 10)
                .updating($isGestureActive) { _, out, _ in
                    out = true
                }
                .onChanged { value in
                    if value.startLocation.x < 50 {
                        gestureStartedFromLeadingEdge = true
                        return
                    }
                    if gestureStartedFromLeadingEdge {
                        return
                    }

                    guard let initialOffset = initialScrollOffset, initialOffset <= 8 else {
                        return
                    }

                    let translationY = value.translation.height
                    let translationX = value.translation.width
                    let absX = abs(translationX)
                    let absY = abs(translationY)

                    if absX > 20 && absX > absY * 0.5 {
                        return
                    }

                    guard translationY > 0 else {
                        return
                    }

                    guard absY > absX * 1.5 else {
                        return
                    }

                    let progress = min(max(translationY / dragDistance, 0), 1)
                    effectProgress = progress

                    let shouldArm = translationY >= dragDistance
                    if shouldArm != isArmed {
                        hapticsTrigger.toggle()
                    }
                    isArmed = shouldArm
                }
                .onEnded { _ in
                    defer { gestureStartedFromLeadingEdge = false }
                    guard !gestureStartedFromLeadingEdge else { return }
                    guard effectProgress > 0 else { return }

                    guard isArmed else {
                        withAnimation(.easeOut(duration: 0.25)) {
                            effectProgress = 0
                        }
                        return
                    }

                    centerRefreshing = true
                    effectProgress = 1

                    withAnimation(.easeOut(duration: 0.2)) {
                        displayTopPadding = refreshingTopPadding
                    }

                    Task {
                        await onRefresh()
                        await MainActor.run {
                            centerRefreshing = false
                        }
                    }
                },
            isEnabled: !centerRefreshing
        )
        .background(alignment: .top) {
            refreshActionView
                .padding(.top, actionTopPadding)
                .ignoresSafeArea()
        }
        .onChange(of: centerRefreshing) { _, isRefreshing in
            if !isRefreshing {
                withAnimation(.easeOut(duration: 0.35)) {
                    effectProgress = 0
                    isArmed = false
                    displayTopPadding = 0
                }
            }
        }
        .sensoryFeedback(.impact, trigger: hapticsTrigger)
    }

    private var refreshActionView: some View {
        let displayProgress = max(effectProgress, centerRefreshing ? 1 : 0)

        return HStack {
            Spacer()
            ProgressView()
                .tint(LocktyColors.primaryText)
                .frame(width: 40, height: 40)
                .safeGlass(radius: 20, interactive: false)
                .blur(radius: 10)
                .opacity(displayProgress)
                .scaleEffect(0.88 + (0.12 * displayProgress))
                .animation(.easeOut(duration: 0.2), value: displayProgress)
            Spacer()
        }
        .padding(.horizontal, 20)
    }
}
