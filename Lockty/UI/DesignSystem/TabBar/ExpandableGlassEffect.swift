import SwiftUI

/// A glass shape that grows out of one thing into another.
@available(iOS 26.0, *)
struct ExpandableGlassEffect<Content: View, Label: View>: View, Animatable {
    var alignment: Alignment
    var progress: CGFloat
    var labelSize: CGSize = .init(width: 55, height: 55)
    var cornerRadius: CGFloat = 30
    @ViewBuilder var content: Content
    @ViewBuilder var label: Label

    @State private var contentSize: CGSize = .zero

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    var body: some View {
        GlassEffectContainer {
            let widthDiff = contentSize.width - labelSize.width
            let heightDiff = contentSize.height - labelSize.height
            let rWidth = widthDiff * contentOpacity
            let rHeight = heightDiff * contentOpacity

            ZStack(alignment: alignment) {
                content
                    .compositingGroup()
                    .scaleEffect(contentScale)
                    .blur(radius: 14 * blurProgress)
                    .opacity(contentOpacity)
                    .onGeometryChange(for: CGSize.self) { $0.size } action: { contentSize = $0 }
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(width: labelSize.width + rWidth, height: labelSize.height + rHeight)

                label
                    .compositingGroup()
                    .blur(radius: 14 * blurProgress)
                    .opacity(1 - labelOpacity)
                    .frame(width: labelSize.width, height: labelSize.height)
            }
            .compositingGroup()
            .clipShape(.rect(cornerRadius: cornerRadius))
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: cornerRadius))
        }
        .scaleEffect(
            x: 1 - (blurProgress * 0.5),
            y: 1 + (blurProgress * 0.35),
            anchor: scaleAnchor
        )
        .offset(y: offset * blurProgress)
    }

    private var labelOpacity: CGFloat { min(progress / 0.35, 1) }
    private var contentOpacity: CGFloat { max(progress - 0.35, 0) / 0.65 }

    private var contentScale: CGFloat {
        guard contentSize.width > 0, contentSize.height > 0 else { return 1 }

        let minAspectScale = min(labelSize.width / contentSize.width, labelSize.height / contentSize.height)
        return minAspectScale + (1 - minAspectScale) * progress
    }

    private var blurProgress: CGFloat {
        progress > 0.5 ? (1 - progress) / 0.5 : progress / 0.5
    }

    private var offset: CGFloat {
        switch alignment {
        case .bottom, .bottomLeading, .bottomTrailing: -80
        case .top, .topLeading, .topTrailing: 80
        default: -10
        }
    }

    private var scaleAnchor: UnitPoint {
        switch alignment {
        case .bottomLeading: .bottomLeading
        case .bottom: .bottom
        case .bottomTrailing: .bottomTrailing
        case .topLeading: .topLeading
        case .top: .top
        case .topTrailing: .topTrailing
        case .leading: .leading
        case .trailing: .trailing
        default: .center
        }
    }
}

/// A button that is a piece of glass and nothing else.
@available(iOS 26.0, *)
struct PlainGlassButtonEffect<S: Shape>: ButtonStyle {
    var shape: S

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .glassEffect(.regular.interactive(), in: shape)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.smooth(duration: 0.2), value: configuration.isPressed)
    }
}
