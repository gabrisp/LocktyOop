import SwiftUI

/// A whole number, as a row: what it is on the left, minus / value / plus on the right.
///
/// Replaces the system `Stepper`, which brings its own label styling, its own tint and a
/// control that looks like nothing else here. This is the same pair of round buttons the
/// break settings use, and the value swaps rather than redrawing, so a count going from
/// 9 to 10 rolls instead of blinking.
///
/// The number is also a button. Stepping is right for a nudge and wrong for a jump, and
/// a range of thirty is a long press away from being useful -- so touching the number
/// opens a wheel on the number itself. Only the number: the row has a title and two
/// buttons that have nothing to do with picking a value, and a menu that grew out of all
/// of them would be a menu about the row rather than about the figure being changed.
struct LocktyCountRow: View {
    let title: String
    @Binding var value: Int
    /// Every value the row can take, in the order the stepper walks them.
    ///
    /// A list rather than a range, because not every sequence is arithmetic: breaks go
    /// unlimited, 1, 2, 3, where "unlimited" is a number so large it cannot be reached by
    /// counting up to it. The stepper moves by index, so the order here is the order the
    /// buttons follow.
    let values: [Int]
    /// Trails the number, e.g. "s" or "steps".
    var suffix: String = ""
    /// How one value reads, when the plain numeral is not what should be shown.
    var format: ((Int) -> String)?
    var circleSize: CGFloat = 32
    var valueMinWidth: CGFloat = 68

    @State private var isPickerPresented = false

    init(
        title: String,
        value: Binding<Int>,
        range: ClosedRange<Int>,
        step: Int = 1,
        suffix: String = "",
        format: ((Int) -> String)? = nil,
        circleSize: CGFloat = 32,
        valueMinWidth: CGFloat = 68
    ) {
        self.init(
            title: title,
            value: value,
            values: Array(stride(from: range.lowerBound, through: range.upperBound, by: step)),
            suffix: suffix,
            format: format,
            circleSize: circleSize,
            valueMinWidth: valueMinWidth
        )
    }

    init(
        title: String,
        value: Binding<Int>,
        values: [Int],
        suffix: String = "",
        format: ((Int) -> String)? = nil,
        circleSize: CGFloat = 32,
        valueMinWidth: CGFloat = 68
    ) {
        self.title = title
        _value = value
        self.values = values
        self.suffix = suffix
        self.format = format
        self.circleSize = circleSize
        self.valueMinWidth = valueMinWidth
    }

    /// Where the current value sits in the list. A value that is not in it -- something
    /// saved under an older set of options -- reads as the first, so the buttons still
    /// move rather than doing nothing.
    private var currentIndex: Int {
        values.firstIndex(of: value) ?? 0
    }

    private func label(_ number: Int) -> String {
        if let format { return format(number) }
        let text = number.formatted(.number.grouping(.automatic))
        return suffix.isEmpty ? text : "\(text) \(suffix)"
    }

    var body: some View {
        HStack(spacing: LocktySpacing.md) {
            Text(title)
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            Spacer(minLength: LocktySpacing.sm)

            button(systemImage: "minus", isDisabled: currentIndex <= 0) {
                move(by: -1)
            }

            valueButton

            button(systemImage: "plus", isDisabled: currentIndex >= values.count - 1) {
                move(by: 1)
            }
        }
        // A little air above and below. The buttons are 32 tall inside a 44 row, so the
        // gap to the divider was four points -- and in a card of these the whole column
        // read as one solid block of controls.
        .padding(.vertical, LocktySpacing.sm)
        .frame(minHeight: 52)
    }

    private var valueButton: some View {
        Button {
            isPickerPresented = true
        } label: {
            Text(label(value))
                .font(.system(.subheadline, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.snappy(duration: 0.22), value: value)
                .frame(minWidth: valueMinWidth)
                .frame(height: circleSize)
                .multilineTextAlignment(.center)
                .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 12, style: .continuous)))
        .tappable()
        .locktyMenu(isPresented: $isPickerPresented) {
            Picker("", selection: $value) {
                ForEach(values, id: \.self) { number in
                    Text(label(number)).tag(number)
                }
            }
            .pickerStyle(.wheel)
            .frame(width: 150, height: 160)
            .labelsHidden()
        }
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
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(LocktyColors.onPrimary)
            }
            .frame(width: circleSize, height: circleSize)
            .contentShape(Circle())
        }
        .buttonStyle(.locktyInteractive(shape: Circle()))
        .tappable()
        .disabled(isDisabled)
        .opacity(isDisabled ? 0.35 : 1)
    }
}
