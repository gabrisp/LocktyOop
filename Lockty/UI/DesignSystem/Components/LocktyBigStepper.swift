import SwiftUI

/// A number being set, at the size of the thing being decided.
///
/// The row version of this -- label on the left, small figure between two circles -- is
/// right in a list of settings, where the figure is one of six things on the screen. It
/// is wrong when the figure *is* the screen: setting a step goal is one decision, and it
/// should be the biggest thing on the sheet rather than a caption between two buttons.
///
/// Minus on the left, plus on the right, the same white circles the rows use. The number
/// rolls between values instead of being replaced, because it is the same number moving.
struct LocktyBigStepper: View {
    @Binding var value: Int
    /// Every value it can take, in order. A list rather than a range because the sensible
    /// steps for a step count are not the sensible steps for a glass of water.
    let values: [Int]
    /// How the figure reads. Given the value, returns the whole string.
    var format: (Int) -> String = { $0.formatted(.number.grouping(.automatic)) }
    /// The word under the number: what it is measured in.
    var caption: String?
    /// How finely the slider behind the number goes, when the number is tapped.
    ///
    /// The buttons move in the steps that are sensible to think in -- five minutes, a
    /// hundred steps -- and that is right for a button. It is wrong as a limit: somebody
    /// who wants forty-two minutes should be able to say forty-two, and pressing plus
    /// eight times to land on forty-five is the control deciding instead of the person.
    ///
    /// Nil leaves the figure a read-out. A list of glasses of water has no meaningful
    /// in-between, and offering one would be asking for a decision that does not exist.
    var fineStep: Int?

    @State private var isShowingFineTune = false

    /// The ends of the slider: the whole list, however coarsely the buttons walk it.
    private var bounds: ClosedRange<Int>? {
        guard let lowest = values.min(), let highest = values.max(), lowest < highest else {
            return nil
        }
        return lowest...highest
    }

    private var allowsFineTune: Bool { fineStep != nil && bounds != nil }

    private var currentIndex: Int {
        values.firstIndex(of: value) ?? closestIndex
    }

    /// The nearest value we do offer, for a figure saved under an older set of options --
    /// so the buttons move from where it is rather than jumping to the start of the list.
    private var closestIndex: Int {
        guard !values.isEmpty else { return 0 }
        return values
            .enumerated()
            .min { abs($0.element - value) < abs($1.element - value) }?
            .offset ?? 0
    }

    var body: some View {
        VStack(spacing: LocktySpacing.sm) {
            HStack(spacing: LocktySpacing.xl) {
                button(systemImage: "minus", isDisabled: currentIndex <= 0) { move(by: -1) }

                if allowsFineTune {
                    Button { isShowingFineTune = true } label: { figure }
                        .buttonStyle(.locktyInteractive)
                        .tappable()
                        .locktyMenu(isPresented: $isShowingFineTune) { fineTuneMenu }
                } else {
                    figure
                }

                button(systemImage: "plus", isDisabled: currentIndex >= values.count - 1) { move(by: 1) }
            }

            if let caption {
                Text(caption)
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
            }
        }
        .frame(maxWidth: .infinity)
        // One tick per press, and a firmer one at either end, so the limits of the list
        // are felt rather than only seen in a dimmed button.
        .sensoryFeedback(.selection, trigger: value)
    }

    private var figure: some View {
        Text(format(value))
            .font(.system(size: 44, weight: .bold))
            .foregroundStyle(LocktyColors.primaryText)
            .monospacedDigit()
            .contentTransition(.numericText())
            .animation(.snappy(duration: 0.22), value: value)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .frame(maxWidth: .infinity)
    }

    /// The number, set by hand.
    ///
    /// The same figure at the top so the slider is read against what it is changing, and
    /// the two ends written underneath so the range is a fact rather than something to
    /// discover by dragging.
    @ViewBuilder
    private var fineTuneMenu: some View {
        if let bounds, let step = fineStep {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                Text(format(value))
                    .font(.system(size: 30, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.snappy(duration: 0.18), value: value)

                Slider(
                    value: fineBinding(in: bounds),
                    in: Double(bounds.lowerBound)...Double(bounds.upperBound),
                    step: Double(max(step, 1))
                )
                .tint(LocktyColors.primaryText)

                HStack(spacing: LocktySpacing.md) {
                    Text(format(bounds.lowerBound))
                    Spacer(minLength: 0)
                    Text(format(bounds.upperBound))
                }
                .font(.system(.caption, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .monospacedDigit()
            }
            .frame(width: 250)
            .padding(LocktySpacing.lg)
        }
    }

    /// Clamped on the way in as well as out: a value saved under an older set of options
    /// can sit outside today's list, and a slider handed a number past its own range
    /// snaps to an end and writes that back.
    private func fineBinding(in bounds: ClosedRange<Int>) -> Binding<Double> {
        Binding(
            get: { Double(min(max(value, bounds.lowerBound), bounds.upperBound)) },
            set: { value = min(max(Int($0.rounded()), bounds.lowerBound), bounds.upperBound) }
        )
    }

    private func move(by offset: Int) {
        let next = currentIndex + offset
        guard values.indices.contains(next) else { return }
        value = values[next]
    }

    private func button(
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(LocktyColors.primaryText)

                Image(systemName: systemImage)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(LocktyColors.onPrimary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Circle())
        }
        .buttonStyle(.locktyInteractive(shape: Circle()))
        .tappable()
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
    }
}
