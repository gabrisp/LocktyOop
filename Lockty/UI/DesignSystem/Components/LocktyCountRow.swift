import SwiftUI

/// A whole number, as a row: what it is on the left, minus / value / plus on the right.
///
/// Replaces the system `Stepper`, which brings its own label styling, its own tint and a
/// control that looks like nothing else here. This is the same pair of round buttons the
/// break settings use, and the value swaps rather than redrawing, so a count going from
/// 9 to 10 rolls instead of blinking.
struct LocktyCountRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    /// How much one press moves it. A step goal that lands on 8137 is noise, not a choice.
    var step: Int = 1
    /// Trails the number, e.g. "s" or "steps".
    var suffix: String = ""

    private var displayValue: String {
        let number = value.formatted(.number.grouping(.automatic))
        return suffix.isEmpty ? number : "\(number) \(suffix)"
    }

    var body: some View {
        HStack(spacing: LocktySpacing.md) {
            Text(title)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            Spacer(minLength: LocktySpacing.sm)

            button(systemImage: "minus", isDisabled: value <= range.lowerBound) {
                value = max(value - step, range.lowerBound)
            }

            Text(displayValue)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.22), value: value)
                .frame(minWidth: 68)
                .multilineTextAlignment(.center)

            button(systemImage: "plus", isDisabled: value >= range.upperBound) {
                value = min(value + step, range.upperBound)
            }
        }
        .frame(minHeight: 44)
    }

    private func button(
        systemImage: String,
        isDisabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            ZStack {
                Circle().fill(Color.white)

                Image(systemName: systemImage)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.black)
            }
            .frame(width: 32, height: 32)
            .contentShape(Circle())
        }
        .buttonStyle(.locktyInteractive(shape: Circle()))
        .tappable()
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
    }
}
