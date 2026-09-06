import SwiftUI

// MARK: - Copy the phrase

/// Retype a sentence, exactly.
///
/// The strongest of the six, and the dullest on purpose. There is no trick to learn and
/// no board to memorise: the only way through is to read a sentence and type it, which
/// takes about as long the hundredth time as the first.
struct UnlockCopyPhraseStepView: View {
    let configuration: CopyPhraseConfiguration
    @Binding var status: UnlockFlowStepStatus

    @State private var phrase = ""
    @State private var typed = ""
    @FocusState private var isFocused: Bool

    private var matches: Bool {
        let target = configuration.isCaseSensitive ? phrase : phrase.lowercased()
        let entry = configuration.isCaseSensitive ? typed : typed.lowercased()
        return target.trimmingCharacters(in: .whitespacesAndNewlines)
            == entry.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        UnlockStepSurface(tone: matches ? .success : .neutral, shakeTrigger: 0) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                Text(phrase)
                    .font(.system(.title3, design: .serif, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .fixedSize(horizontal: false, vertical: true)

                TextField("Type it here", text: $typed, axis: .vertical)
                    .focused($isFocused)
                    .textInputAutocapitalization(configuration.isCaseSensitive ? .sentences : .never)
                    .autocorrectionDisabled()
                    .font(.system(.body, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(3...6)
                    .padding(.horizontal, LocktySpacing.cardInset)
                    .padding(.vertical, LocktySpacing.md)
                    .locktyCardBackground(cornerRadius: 22)

                // Says how far in you are, without marking your work as you go: a live
                // right-or-wrong turns copying into a game of beating the validator.
                Text("\(typed.count) of \(phrase.count)")
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.tertiaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }
        }
        .task(id: configuration.id) {
            phrase = FrictionWordBank.phrase(
                approximateWordCount: configuration.length.approximateWordCount,
                excluding: phrase.isEmpty ? nil : phrase
            )
            typed = ""
            try? await Task.sleep(for: .milliseconds(300))
            isFocused = true
        }
        .onChange(of: matches, initial: true) { _, isMatching in
            status = UnlockFlowStepStatus(primaryState: .advance(enabled: isMatching))
        }
    }
}

// MARK: - Hold steady

/// Keep a finger down. Letting go starts again.
///
/// No skill and no cleverness -- just a length of time you have to sit through with your
/// hand occupied, which is exactly what makes it hard to do while doing something else.
struct UnlockHoldSteadyStepView: View {
    let configuration: HoldSteadyConfiguration
    @Binding var status: UnlockFlowStepStatus

    @State private var progress: CGFloat = 0
    @State private var isHolding = false
    @State private var isDone = false
    @State private var holdTask: Task<Void, Never>?

    private var remaining: Int {
        max(Int((Double(configuration.seconds) * (1 - progress)).rounded(.up)), 0)
    }

    var body: some View {
        UnlockStepSurface(tone: isDone ? .success : .neutral, shakeTrigger: 0) {
            VStack(spacing: LocktySpacing.lg) {
                ZStack {
                    Circle()
                        .stroke(LocktyColors.ink(0.10), lineWidth: 8)

                    Circle()
                        .trim(from: 0, to: progress)
                        .stroke(
                            LocktyColors.productive,
                            style: StrokeStyle(lineWidth: 8, lineCap: .round)
                        )
                        .rotationEffect(.degrees(-90))

                    Text(isDone ? "Done" : "\(remaining)")
                        .font(.system(size: 34, weight: .bold))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .foregroundStyle(LocktyColors.primaryText)
                }
                .frame(width: 160, height: 160)
                .scaleEffect(isHolding ? 0.97 : 1)
                .animation(.smooth(duration: 0.2), value: isHolding)

                Text(isDone ? "You can carry on." : "Press and keep holding.")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
            .onLongPressGesture(minimumDuration: .infinity) {
                // Never fires: the gesture is only here for its pressing callback.
            } onPressingChanged: { pressing in
                pressing ? begin() : cancel()
            }
        }
        .task(id: configuration.id) {
            status = UnlockFlowStepStatus(primaryState: .advance(enabled: false))
        }
        .sensoryFeedback(.success, trigger: isDone) { _, new in new }
    }

    private func begin() {
        guard !isDone else { return }
        isHolding = true
        holdTask?.cancel()
        holdTask = Task { @MainActor in
            let started = Date()
            let total = Double(configuration.seconds)
            while !Task.isCancelled {
                let elapsed = Date().timeIntervalSince(started) + Double(progress) * total
                let next = min(elapsed / total, 1)
                progress = next
                if next >= 1 {
                    isDone = true
                    status = UnlockFlowStepStatus(primaryState: .advance(enabled: true))
                    return
                }
                try? await Task.sleep(for: .milliseconds(16))
            }
        }
    }

    private func cancel() {
        holdTask?.cancel()
        holdTask = nil
        isHolding = false
        guard !isDone else { return }
        // All the way back. A hold you can do in instalments is a tap with extra steps.
        withAnimation(.smooth(duration: 0.3)) { progress = 0 }
    }
}

// MARK: - Odd one out

/// One glyph in the grid is not like the others.
///
/// Shapes rather than letters: a letter that differs is found by reading, and reading is
/// fast. Shapes have to be compared, which is slow and cannot be hurried.
struct UnlockOddOneOutStepView: View {
    let configuration: OddOneOutConfiguration
    @Binding var status: UnlockFlowStepStatus

    @State private var common = "circle.fill"
    @State private var odd = "hexagon.fill"
    @State private var oddIndex = 0
    @State private var round = 1
    @State private var tone: UnlockFeedbackTone = .neutral
    @State private var shakeTrigger = 0

    private var cellCount: Int { configuration.side * configuration.side }

    var body: some View {
        UnlockStepSurface(tone: tone, shakeTrigger: shakeTrigger) {
            VStack(spacing: LocktySpacing.lg) {
                Text("Round \(round) of \(configuration.rounds)")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .contentTransition(.numericText())

                LazyVGrid(
                    columns: Array(
                        repeating: GridItem(.flexible(), spacing: LocktySpacing.sm),
                        count: configuration.side
                    ),
                    spacing: LocktySpacing.sm
                ) {
                    ForEach(0..<cellCount, id: \.self) { index in
                        Button {
                            pick(index)
                        } label: {
                            Image(systemName: index == oddIndex ? odd : common)
                                .font(.system(size: 26, weight: .regular))
                                .foregroundStyle(LocktyColors.primaryText.opacity(0.82))
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.locktyInteractive(brighten: true))
                        .tappable()
                    }
                }
            }
        }
        .task(id: configuration.id) { deal() }
        .sensoryFeedback(.selection, trigger: round)
    }

    private func deal() {
        let pair = FrictionWordBank.confusablePair()
        common = pair.common
        odd = pair.odd
        oddIndex = Int.random(in: 0..<cellCount)
        status = UnlockFlowStepStatus(primaryState: .advance(enabled: false))
    }

    private func pick(_ index: Int) {
        guard index == oddIndex else {
            tone = .error
            shakeTrigger += 1
            // Re-dealt on a miss. Without it you could tap every cell in turn, which is
            // not finding the odd one, it is exhausting the grid.
            withAnimation(.smooth(duration: 0.28)) { deal() }
            return
        }

        if round >= configuration.rounds {
            tone = .success
            status = UnlockFlowStepStatus(primaryState: .advance(enabled: true))
        } else {
            round += 1
            withAnimation(.smooth(duration: 0.28)) { deal() }
        }
    }
}

// MARK: - Sort the numbers

/// Tap the numbers in order. One wrong tap and they shuffle.
struct UnlockSortNumbersStepView: View {
    let configuration: SortNumbersConfiguration
    @Binding var status: UnlockFlowStepStatus

    @State private var numbers: [Int] = []
    @State private var tapped: Set<Int> = []
    @State private var tone: UnlockFeedbackTone = .neutral
    @State private var shakeTrigger = 0

    private var next: Int? {
        numbers.sorted().first { !tapped.contains($0) }
    }

    var body: some View {
        UnlockStepSurface(tone: tone, shakeTrigger: shakeTrigger) {
            VStack(spacing: LocktySpacing.lg) {
                Text("Lowest first")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.secondaryText)

                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: LocktySpacing.sm), count: 4),
                    spacing: LocktySpacing.sm
                ) {
                    ForEach(numbers, id: \.self) { number in
                        let isDone = tapped.contains(number)

                        Button {
                            pick(number)
                        } label: {
                            Text("\(number)")
                                .font(.system(size: 20, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(isDone ? LocktyColors.tertiaryText : LocktyColors.primaryText)
                                .frame(maxWidth: .infinity)
                                .frame(height: 52)
                                .background {
                                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                                        .fill(LocktyColors.ink(isDone ? 0.03 : 0.07))
                                }
                                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
                        .tappable()
                        .disabled(isDone)
                    }
                }
            }
        }
        .task(id: configuration.id) { deal() }
        .sensoryFeedback(.selection, trigger: tapped.count)
    }

    private func deal() {
        // Spread out rather than 1...n: consecutive numbers are ordered at a glance,
        // where scattered ones have to be compared.
        numbers = Array(Set((0..<configuration.count * 4).map { _ in Int.random(in: 3...99) }))
            .shuffled()
            .prefix(configuration.count)
            .map { $0 }
        tapped = []
        tone = .neutral
        status = UnlockFlowStepStatus(primaryState: .advance(enabled: false))
    }

    private func pick(_ number: Int) {
        guard number == next else {
            tone = .error
            shakeTrigger += 1
            withAnimation(.smooth(duration: 0.3)) {
                numbers.shuffle()
                tapped = []
            }
            return
        }

        tapped.insert(number)
        if tapped.count == numbers.count {
            tone = .success
            status = UnlockFlowStepStatus(primaryState: .advance(enabled: true))
        }
    }
}

// MARK: - Past answers

/// What you wrote the last few times, handed back to you.
///
/// The only friction here that uses something you already gave it. It asks nothing new;
/// it just makes you read your own reasons before adding another one, which is a harder
/// thing to do quickly than any puzzle.
struct UnlockPastAnswersStepView: View {
    let configuration: PastAnswersConfiguration
    @Binding var status: UnlockFlowStepStatus

    @State private var answers: [String] = []

    private let store = AppGroupStore()

    var body: some View {
        UnlockStepSurface(tone: .neutral, shakeTrigger: 0) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                Text(answers.isEmpty ? "Nothing written yet" : "You said, last time:")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.secondaryText)

                if answers.isEmpty {
                    Text("The next reason you write will show up here.")
                        .font(.system(.body, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.tertiaryText)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(Array(answers.enumerated()), id: \.offset) { _, answer in
                        Text("\u{201C}\(answer)\u{201D}")
                            .font(.system(.body, design: .serif, weight: .regular))
                            .foregroundStyle(LocktyColors.primaryText)
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, LocktySpacing.cardInset)
                            .padding(.vertical, LocktySpacing.md)
                            .locktyCardBackground(cornerRadius: 20)
                    }
                }
            }
        }
        .task(id: configuration.id) {
            answers = Array(store.loadIntentionAnswers().suffix(configuration.recallCount).reversed())
            status = UnlockFlowStepStatus(primaryState: .advance(enabled: true))
        }
    }
}

// MARK: - Tune the value

/// Drag a line up a scale until it sits on a number.
///
/// Not a slider and not a scroll view: a bar you take hold of and move, on a scale short
/// enough to read at a glance and fine enough that you cannot fling it into place. Ten
/// marks and a line -- put the line on the eight.
///
/// Vertical because the hand is worse at it. A horizontal drag is the gesture every
/// slider in every app has trained; dragging upward against a scale that counts upward
/// takes a moment of thought each time, which is the whole job.
struct UnlockTuneValueStepView: View {
    let configuration: TuneValueConfiguration
    @Binding var status: UnlockFlowStepStatus

    /// The scale. Ten is enough to be fiddly and few enough to label every mark.
    private let steps = 10

    @State private var target = 8
    /// Where the line sits, in scale units. Continuous rather than snapped: snapping
    /// would do the aiming for you.
    @State private var value: Double = 1
    @State private var isDragging = false

    private var current: Int { Int(value.rounded()) }
    private var isOnTarget: Bool { abs(current - target) <= configuration.tolerance }

    var body: some View {
        UnlockStepSurface(tone: isOnTarget ? .success : .neutral, shakeTrigger: 0) {
            VStack(spacing: LocktySpacing.lg) {
                Text("Put the line on \(target)")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .contentTransition(.numericText())

                scale

                Text("\(current)")
                    .font(.system(size: 34, weight: .bold))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .foregroundStyle(isOnTarget ? LocktyColors.productive : LocktyColors.primaryText)
            }
        }
        .task(id: configuration.id) {
            // Never the ends, and never where the line already is: both would be arrived
            // at without aiming.
            target = Int.random(in: 2...(steps - 1))
            value = Double(target > steps / 2 ? 1 : steps)
            status = UnlockFlowStepStatus(primaryState: .advance(enabled: false))
        }
        .onChange(of: isOnTarget, initial: true) { _, onTarget in
            status = UnlockFlowStepStatus(primaryState: .advance(enabled: onTarget))
        }
        .sensoryFeedback(.selection, trigger: current)
    }

    private var scale: some View {
        GeometryReader { proxy in
            let height = proxy.size.height
            // 1 at the bottom and `steps` at the top: a scale that counts upward should
            // go upward.
            let y = height - (value - 1) / Double(steps - 1) * height

            ZStack(alignment: .topLeading) {
                marks(height: height)

                line
                    .position(x: proxy.size.width / 2, y: y)
            }
            .frame(width: proxy.size.width, height: height)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { drag in
                        isDragging = true
                        let ratio = 1 - min(max(drag.location.y / height, 0), 1)
                        value = 1 + ratio * Double(steps - 1)
                    }
                    .onEnded { _ in isDragging = false }
            )
        }
        .frame(height: 220)
    }

    private func marks(height: CGFloat) -> some View {
        VStack(spacing: 0) {
            ForEach(Array((1...steps).reversed()), id: \.self) { mark in
                HStack(spacing: LocktySpacing.sm) {
                    Text("\(mark)")
                        .font(.system(.caption, design: .default, weight: mark == target ? .bold : .regular))
                        .foregroundStyle(mark == target ? LocktyColors.productive : LocktyColors.tertiaryText)
                        .monospacedDigit()
                        .frame(width: 22, alignment: .trailing)

                    Rectangle()
                        .fill(mark == target ? LocktyColors.productive.opacity(0.5) : LocktyColors.ink(0.10))
                        .frame(height: 1)
                }
                .frame(maxHeight: .infinity)
            }
        }
        .frame(height: height)
    }

    /// The bar you take hold of. Wide, because a thin one is a target you miss, and lit
    /// while held so it is clear the drag has it.
    private var line: some View {
        Capsule(style: .continuous)
            .fill(isOnTarget ? LocktyColors.productive : LocktyColors.primaryText)
            .frame(height: 6)
            .shadow(
                color: (isOnTarget ? LocktyColors.productive : LocktyColors.primaryText)
                    .opacity(isDragging ? 0.5 : 0.25),
                radius: isDragging ? 10 : 5
            )
            .scaleEffect(y: isDragging ? 1.4 : 1)
            .animation(.smooth(duration: 0.18), value: isDragging)
    }
}

/// Have you done what you said you would?
///
/// The one friction made of your own words. It lists the objectives that are not met in
/// the period they are counted in, and the way through is to meet them -- the rings fill
/// here, on this screen, the same way they do on the card.
///
/// Nothing to solve and nothing to type, which makes it the slowest friction in the app
/// by a distance: the others cost twenty seconds of attention, and this one can cost a
/// glass of water and a walk to the kitchen. That is the point of it.
struct UnlockObjectivesStepView: View {
    let configuration: ObjectivesFrictionConfiguration
    @Binding var status: UnlockFlowStepStatus
    /// Handed down when there is one, so a step objective reads Health here too rather
    /// than showing whatever was last written.
    var healthService: HealthServicing?

    @StateObject private var viewModel: ObjectivesViewModel

    init(
        configuration: ObjectivesFrictionConfiguration,
        status: Binding<UnlockFlowStepStatus>,
        healthService: HealthServicing? = nil
    ) {
        self.configuration = configuration
        _status = status
        self.healthService = healthService
        _viewModel = StateObject(
            wrappedValue: ObjectivesViewModel(healthService: healthService)
        )
    }

    private var outstanding: [Objective] {
        viewModel.objectives.filter { !viewModel.isComplete($0) }
    }

    /// Whether the flow may go on: everything done, or one thing done, as configured.
    ///
    /// An empty list passes. A friction that cannot be satisfied is not a friction, it is
    /// a locked door -- and somebody who has set no objectives has not agreed to anything
    /// they can be held to.
    private var isSatisfied: Bool {
        guard !viewModel.objectives.isEmpty else { return true }
        return configuration.requiresAll
            ? outstanding.isEmpty
            : viewModel.completedCount > 0
    }

    var body: some View {
        UnlockStepSurface(tone: isSatisfied ? .success : .neutral, shakeTrigger: 0) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                Text(headline)
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(spacing: LocktySpacing.md) {
                    ForEach(viewModel.objectives) { objective in
                        row(objective)
                    }
                }
            }
        }
        .task {
            viewModel.load()
            status = UnlockFlowStepStatus(primaryState: .advance(enabled: isSatisfied))
        }
        .onChange(of: isSatisfied, initial: true) { _, satisfied in
            status = UnlockFlowStepStatus(primaryState: .advance(enabled: satisfied))
        }
    }

    private var headline: String {
        guard !viewModel.objectives.isEmpty else { return "Nothing set for now." }
        if isSatisfied { return "Done. That was the deal." }
        return configuration.requiresAll
            ? "Finish what you set yourself first."
            : "Finish one of these first."
    }

    private func row(_ objective: Objective) -> some View {
        Button {
            viewModel.advance(objective)
        } label: {
            HStack(spacing: LocktySpacing.md) {
                ObjectiveRing(
                    symbolName: objective.symbolName,
                    fraction: viewModel.fraction(of: objective),
                    isComplete: viewModel.isComplete(objective),
                    color: objective.color,
                    side: 34,
                    lineWidth: 2.5
                )

                VStack(alignment: .leading, spacing: 1) {
                    Text(objective.name)
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(LocktyColors.primaryText)
                        .lineLimit(1)

                    Text("\(viewModel.detail(for: objective)) · \(objective.period.currentTitle)")
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(
                            viewModel.isComplete(objective)
                                ? LocktyColors.productive
                                : LocktyColors.secondaryText
                        )
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .frame(minHeight: 46)
            .contentShape(Rectangle())
        }
        .buttonStyle(.locktyInteractive(brighten: true))
        .tappable()
    }
}
