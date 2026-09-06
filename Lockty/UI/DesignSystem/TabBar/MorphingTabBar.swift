import SwiftUI
import UIKit

/// The tabs a morphing bar can show.
protocol MorphingTabProtocol: CaseIterable, Hashable {
    var symbolImage: String { get }
}

/// A compact segmented tab bar that morphs into caller-provided content.
@available(iOS 26.0, *)
struct MorphingTabBar<Tab: MorphingTabProtocol, ExpandedContent: View>: View {
    @Binding var activeTab: Tab
    @Binding var isExpanded: Bool
    var collapsedWidth: CGFloat? = nil
    @ViewBuilder var expandedContent: ExpandedContent

    @State private var viewWidth: CGFloat?

    var body: some View {
        ZStack(alignment: .leading) {
            let tabs = Array(Tab.allCases)
            let symbols = tabs.map(\.symbolImage)
            let selectedIndex = Binding {
                symbols.firstIndex(of: activeTab.symbolImage) ?? 0
            } set: { index in
                guard tabs.indices.contains(index) else { return }
                activeTab = tabs[index]
            }

            if let viewWidth {
                let labelSize = CGSize(width: collapsedWidth ?? viewWidth, height: 52)

                ExpandableGlassEffect(
                    alignment: .center,
                    progress: isExpanded ? 1 : 0,
                    labelSize: labelSize,
                    cornerRadius: labelSize.height / 2
                ) {
                    expandedContent
                        .frame(width: viewWidth)
                } label: {
                    MorphingSegmentedControl(symbols: symbols, index: selectedIndex) { image in
                        let font = UIFont.systemFont(ofSize: 19, weight: .regular)
                        let configuration = UIImage.SymbolConfiguration(font: font)
                        return UIImage(systemName: image, withConfiguration: configuration)
                    }
                    .frame(height: 48)
                    .padding(.horizontal, 2)
                    .offset(y: -0.7)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { viewWidth = $0 }
        .frame(height: viewWidth == nil ? 52 : nil)
    }
}

private struct MorphingSegmentedControl: UIViewRepresentable {
    var tint: Color = .gray.opacity(0.15)
    var symbols: [String]
    @Binding var index: Int
    var image: (String) -> UIImage?

    func makeUIView(context: Context) -> UISegmentedControl {
        let control = UISegmentedControl(items: symbols)
        control.selectedSegmentIndex = index
        control.selectedSegmentTintColor = UIColor(tint)

        for (index, symbol) in symbols.enumerated() {
            control.setImage(image(symbol), forSegmentAt: index)
        }

        control.addTarget(context.coordinator, action: #selector(Coordinator.didSelect(_:)), for: .valueChanged)

        DispatchQueue.main.async {
            for view in control.subviews.dropLast() where view is UIImageView {
                view.alpha = 0
            }
        }

        return control
    }

    func updateUIView(_ uiView: UISegmentedControl, context: Context) {
        if uiView.selectedSegmentIndex != index {
            uiView.selectedSegmentIndex = index
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject {
        var parent: MorphingSegmentedControl

        init(parent: MorphingSegmentedControl) {
            self.parent = parent
        }

        @objc
        func didSelect(_ control: UISegmentedControl) {
            parent.index = control.selectedSegmentIndex
        }
    }

    func sizeThatFits(_ proposal: ProposedViewSize, uiView: UISegmentedControl, context: Context) -> CGSize? {
        proposal.replacingUnspecifiedDimensions()
    }
}
