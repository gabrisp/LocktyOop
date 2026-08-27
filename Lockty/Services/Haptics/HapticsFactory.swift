import UIKit

protocol HapticsProviding {
    func selectionChanged()
    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat)
}

final class HapticsFactory: HapticsProviding {
    private let selectionGenerator = UISelectionFeedbackGenerator()
    private var impactGenerators: [UIImpactFeedbackGenerator.FeedbackStyle: UIImpactFeedbackGenerator] = [:]

    init() {
        selectionGenerator.prepare()
    }

    func selectionChanged() {
        selectionGenerator.selectionChanged()
        selectionGenerator.prepare()
    }

    func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1) {
        let generator = impactGenerator(for: style)
        generator.impactOccurred(intensity: intensity)
        generator.prepare()
    }

    private func impactGenerator(for style: UIImpactFeedbackGenerator.FeedbackStyle) -> UIImpactFeedbackGenerator {
        if let generator = impactGenerators[style] {
            return generator
        }

        let generator = UIImpactFeedbackGenerator(style: style)
        impactGenerators[style] = generator
        generator.prepare()
        return generator
    }
}
