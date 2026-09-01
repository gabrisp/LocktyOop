import AVFoundation
import FamilyControls
import SwiftUI

enum UnlockFlowStepPrimaryState: Equatable {
    case advance(enabled: Bool)
    case submit(enabled: Bool)
    case scan(enabled: Bool)

    var isEnabled: Bool {
        switch self {
        case .advance(let enabled), .submit(let enabled), .scan(let enabled):
            enabled
        }
    }

    var title: String {
        switch self {
        case .advance:
            "Continuar"
        case .submit:
            "Comprobar"
        case .scan:
            "Escanear"
        }
    }
}

struct UnlockFlowStepStatus: Equatable {
    var primaryState: UnlockFlowStepPrimaryState
    var intentionText: String?

    static let ready = UnlockFlowStepStatus(primaryState: .advance(enabled: true))
}

enum UnlockFeedbackTone: Equatable {
    case neutral
    case active
    case success
    case error
}

struct UnlockStepSurface<Content: View>: View {
    let tone: UnlockFeedbackTone
    let shakeTrigger: Int
    @ViewBuilder var content: Content

    private var strokeColor: Color {
        switch tone {
        case .neutral:
            LocktyColors.cardStroke
        case .active:
            LocktyColors.warning.opacity(0.65)
        case .success:
            LocktyColors.productive
        case .error:
            LocktyColors.error
        }
    }

    private var fillColor: Color {
        switch tone {
        case .neutral:
            LocktyColors.elevatedBackground
        case .active:
            LocktyColors.warning.opacity(0.12)
        case .success:
            LocktyColors.productive.opacity(0.12)
        case .error:
            LocktyColors.error.opacity(0.12)
        }
    }

    private var glowColor: Color {
        switch tone {
        case .neutral:
            .clear
        case .active:
            LocktyColors.warning.opacity(0.32)
        case .success:
            LocktyColors.productive.opacity(0.34)
        case .error:
            LocktyColors.error.opacity(0.36)
        }
    }

    var body: some View {
        content
            .padding(LocktySpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(fillColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .stroke(strokeColor, lineWidth: tone == .neutral ? 1 : 1.5)
            )
            .shadow(color: glowColor, radius: 24)
            .modifier(ShakeEffect(trigger: shakeTrigger))
            .animation(.smooth(duration: 0.26), value: tone)
    }
}

private struct ShakeEffect: GeometryEffect {
    var trigger: Int
    var amplitude: CGFloat = 10

    var animatableData: CGFloat {
        get { CGFloat(trigger) }
        set { }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        let translation = amplitude * sin(CGFloat(trigger) * .pi * 3)
        return ProjectionTransform(CGAffineTransform(translationX: translation, y: 0))
    }
}

private struct GridPoint: Hashable, Identifiable {
    let row: Int
    let column: Int

    var id: String { "\(row)-\(column)" }
}

private struct WordSearchSession {
    var board: [[String]]
    var words: [String]
    var currentWordIndex: Int
    var foundWords: [String]

    static let empty = WordSearchSession(board: [], words: [], currentWordIndex: 0, foundWords: [])
}

struct UnlockWordSearchStepView: View {
    let configuration: WordSearchConfiguration
    @Binding var status: UnlockFlowStepStatus

    @State private var session = WordSearchSession.empty
    @State private var activePath: [GridPoint] = []
    @State private var feedbackTone: UnlockFeedbackTone = .neutral
    @State private var shakeTrigger = 0
    @State private var feedbackPulse = 0

    private let haptics = HapticsFactory()

    var body: some View {
        UnlockStepSurface(tone: feedbackTone, shakeTrigger: shakeTrigger) {
            VStack(spacing: LocktySpacing.lg) {
                header

                UnlockSquareBoardContainer { side in
                    wordSearchBoard(side: side)
                }
            }
        }
        .padding(.horizontal, 16)
        .task(id: configuration.id) {
            resetSession()
        }
        .sensoryFeedback(.selection, trigger: feedbackPulse)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.9), trigger: feedbackTone) { _, new in
            new == .error
        }
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.85), trigger: session.foundWords.count) { old, new in
            new > old
        }
    }

    private var header: some View {
        VStack(spacing: LocktySpacing.lg) {
            Text("Find these words")
                .font(.system(.title3, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(currentTargetWord)
                .font(.system(size: 30, weight: .bold, design: .rounded))
                .foregroundStyle(LocktyColors.primaryText)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .contentTransition(.numericText())

            wordProgressBars
        }
    }

    private var wordProgressBars: some View {
        HStack(spacing: LocktySpacing.sm) {
            ForEach(session.words, id: \.self) { word in
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(progressFill(for: word))
                    .frame(maxWidth: .infinity)
                    .frame(height: 10)
                    .overlay(
                        RoundedRectangle(cornerRadius: 999, style: .continuous)
                            .stroke(progressStroke(for: word), lineWidth: 1)
                    )
                    .shadow(color: progressGlow(for: word), radius: 10)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private func wordSearchBoard(side: CGFloat) -> some View {
        let size = session.board.count
        let cellSize = side / CGFloat(max(size, 1))

        return ZStack {
            if !session.board.isEmpty {
                Path { path in
                    addPath(activePath, cellSize: cellSize, in: &path)
                }
                .stroke(
                    activePathColor,
                    style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: activePathGlow, radius: 18)

                ForEach(session.foundWords, id: \.self) { word in
                    Path { path in
                        addPath(cellsForWord(word), cellSize: cellSize, in: &path)
                    }
                    .stroke(
                        LocktyColors.productive.opacity(0.3),
                        style: StrokeStyle(lineWidth: 20, lineCap: .round, lineJoin: .round)
                    )
                    .shadow(color: LocktyColors.productive.opacity(0.18), radius: 18)
                }

                VStack(spacing: 0) {
                    ForEach(Array(session.board.enumerated()), id: \.offset) { rowIndex, row in
                        HStack(spacing: 0) {
                            ForEach(Array(row.enumerated()), id: \.offset) { columnIndex, letter in
                                let point = GridPoint(row: rowIndex, column: columnIndex)
                                let isActive = activePath.contains(point)
                                let isFound = foundPoints.contains(point)

                                Text(letter)
                                    .font(.system(size: 22, weight: isActive || isFound ? .bold : .regular, design: .rounded))
                                    .foregroundStyle(letterForeground(isActive: isActive, isFound: isFound))
                                    .frame(width: cellSize, height: cellSize)
                                    .contentShape(Rectangle())
                                    .contentTransition(.numericText())
                            }
                        }
                    }
                }
                .padding(10)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    guard !session.board.isEmpty else { return }
                    updateWordSearchDrag(location: value.location, side: side)
                }
                .onEnded { _ in
                    finishWordSearchSelection()
                }
        )
    }

    private var currentTargetWord: String {
        guard session.words.indices.contains(session.currentWordIndex) else { return "..." }
        return session.words[session.currentWordIndex]
    }

    private var foundPoints: Set<GridPoint> {
        Set(session.foundWords.flatMap(cellsForWord))
    }

    private func resetSession() {
        session = makeWordSearchSession(configuration: configuration)
        activePath = []
        feedbackTone = .neutral
        shakeTrigger = 0
        status = UnlockFlowStepStatus(primaryState: .advance(enabled: false))
    }

    private func updateWordSearchDrag(location: CGPoint, side: CGFloat) {
        guard let cell = cell(at: location, side: side, count: session.board.count) else { return }

        if activePath.isEmpty {
            activePath = [cell]
            feedbackPulse += 1
            haptics.selectionChanged()
            return
        }

        if activePath.count >= 2, activePath[activePath.count - 2] == cell {
            activePath.removeLast()
            return
        }

        guard activePath.last != cell else { return }
        guard !activePath.contains(cell) else { return }
        guard canAppendWordSearchCell(cell) else { return }

        activePath.append(cell)
        feedbackPulse += 1
        haptics.selectionChanged()
    }

    private func canAppendWordSearchCell(_ cell: GridPoint) -> Bool {
        guard let last = activePath.last else { return false }
        guard isOrthogonallyAdjacent(last, cell) else { return false }

        if activePath.count == 1 {
            return true
        }

        guard let direction = normalizedDirection(from: activePath[0], to: activePath[1]) else {
            return false
        }
        guard let nextDirection = normalizedDirection(from: last, to: cell) else {
            return false
        }
        return nextDirection == direction
    }

    private func finishWordSearchSelection() {
        guard !activePath.isEmpty else { return }
        let candidate = activePath.map { session.board[$0.row][$0.column] }.joined()
        let reversed = String(candidate.reversed())
        let target = currentTargetWord

        guard candidate == target || reversed == target else {
            feedbackTone = .error
            shakeTrigger += 1
            activePath = []
            haptics.impact(.heavy, intensity: 0.95)
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(520))
                feedbackTone = .neutral
            }
            return
        }

        feedbackTone = .success
        if !session.foundWords.contains(target) {
            session.foundWords.append(target)
        }
        haptics.impact(.rigid, intensity: 1)

        let didFinish = session.foundWords.count == session.words.count
        status.primaryState = .advance(enabled: didFinish)

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(620))
            activePath = []
            if didFinish {
                feedbackTone = .success
            } else {
                session.currentWordIndex += 1
                feedbackTone = .neutral
            }
        }
    }

    private func addPath(_ cells: [GridPoint], cellSize: CGFloat, in path: inout Path) {
        guard let first = cells.first else { return }
        path.move(to: center(for: first, cellSize: cellSize))
        for point in cells.dropFirst() {
            path.addLine(to: center(for: point, cellSize: cellSize))
        }
    }

    private func center(for point: GridPoint, cellSize: CGFloat) -> CGPoint {
        CGPoint(
            x: CGFloat(point.column) * cellSize + cellSize / 2 + 10,
            y: CGFloat(point.row) * cellSize + cellSize / 2 + 10
        )
    }

    private func cell(at location: CGPoint, side: CGFloat, count: Int) -> GridPoint? {
        guard count > 0 else { return nil }
        let inset: CGFloat = 10
        let cellSize = side / CGFloat(count)
        let translatedX = location.x - inset
        let translatedY = location.y - inset
        guard translatedX >= 0, translatedY >= 0 else { return nil }

        let column = min(max(Int(translatedX / cellSize), 0), count - 1)
        let row = min(max(Int(translatedY / cellSize), 0), count - 1)
        return GridPoint(row: row, column: column)
    }

    private func cellsForWord(_ word: String) -> [GridPoint] {
        for sequence in allStraightSequences(in: session.board.count) {
            let candidate = sequence.map { session.board[$0.row][$0.column] }.joined()
            if candidate == word || String(candidate.reversed()) == word {
                return sequence
            }
        }
        return []
    }

    private func allStraightSequences(in size: Int) -> [[GridPoint]] {
        guard size > 0 else { return [] }
        let directions = [
            (-1, -1), (-1, 0), (-1, 1),
            (0, -1),           (0, 1),
            (1, -1),  (1, 0),  (1, 1)
        ]

        var sequences: [[GridPoint]] = []
        for row in 0..<size {
            for column in 0..<size {
                for (dx, dy) in directions {
                    var path = [GridPoint(row: row, column: column)]
                    var current = GridPoint(row: row, column: column)

                    while true {
                        let next = GridPoint(row: current.row + dx, column: current.column + dy)
                        guard (0..<size).contains(next.row), (0..<size).contains(next.column) else { break }
                        path.append(next)
                        if path.count >= 3 {
                            sequences.append(path)
                        }
                        current = next
                    }
                }
            }
        }
        return sequences
    }

    private func letterForeground(isActive: Bool, isFound: Bool) -> Color {
        return LocktyColors.primaryText
    }

    private func progressFill(for word: String) -> Color {
        if session.foundWords.contains(word) {
            return LocktyColors.productive.opacity(0.26)
        }
        if word == currentTargetWord {
            return LocktyColors.warning.opacity(0.16)
        }
        return LocktyColors.cardStroke.opacity(0.42)
    }

    private func progressStroke(for word: String) -> Color {
        if session.foundWords.contains(word) {
            return LocktyColors.productive.opacity(0.85)
        }
        if word == currentTargetWord {
            return LocktyColors.warning.opacity(0.5)
        }
        return .clear
    }

    private func progressGlow(for word: String) -> Color {
        if session.foundWords.contains(word) {
            return LocktyColors.productive.opacity(0.2)
        }
        if word == currentTargetWord {
            return LocktyColors.warning.opacity(0.12)
        }
        return .clear
    }

    private var activePathColor: Color {
        if feedbackTone == .error {
            return LocktyColors.error.opacity(0.3)
        }
        if feedbackTone == .success {
            return LocktyColors.productive.opacity(0.3)
        }
        return .white.opacity(0.3)
    }

    private var activePathGlow: Color {
        if feedbackTone == .error {
            return LocktyColors.error.opacity(0.18)
        }
        if feedbackTone == .success {
            return LocktyColors.productive.opacity(0.18)
        }
        return .white.opacity(0.08)
    }
}

private struct LetterMatchSession {
    var pairs: [LetterMatchPair]
    var lockedPaths: [UUID: [GridPoint]]
    var activePairID: UUID?
    var activePath: [GridPoint]
}

struct UnlockLetterMatchStepView: View {
    let configuration: LetterMatchConfiguration
    @Binding var status: UnlockFlowStepStatus

    @State private var session = LetterMatchSession(pairs: [], lockedPaths: [:], activePairID: nil, activePath: [])
    @State private var feedbackTone: UnlockFeedbackTone = .neutral
    @State private var shakeTrigger = 0
    @State private var feedbackPulse = 0

    private let haptics = HapticsFactory()
    private let gridSide = 5

    var body: some View {
        UnlockStepSurface(tone: feedbackTone, shakeTrigger: shakeTrigger) {
            VStack(spacing: LocktySpacing.lg) {
                letterMatchHeader
                letterMatchBoardContainer
            }
        }
        .padding(.horizontal, 16)
        .task(id: configuration.id) {
            resetLetterMatch()
        }
        .sensoryFeedback(.selection, trigger: feedbackPulse)
        .sensoryFeedback(.impact(weight: .heavy, intensity: 0.92), trigger: feedbackTone) { _, new in
            new == .error
        }
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.88), trigger: session.lockedPaths.count) { old, new in
            new > old
        }
    }

    private var letterMatchHeader: some View {
        VStack(alignment: .center, spacing: LocktySpacing.md) {
            Text("Connect every letter")
                .font(.system(.title3, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .frame(maxWidth: .infinity)

            HStack(spacing: LocktySpacing.sm) {
                ForEach(Array(session.pairs.enumerated()), id: \.element.id) { _, pair in
                    letterBadge(for: pair, isDone: session.lockedPaths[pair.id] != nil)
                }
            }
        }
    }

    private var letterMatchBoardContainer: some View {
        UnlockSquareBoardContainer { side in
            letterMatchBoard(side: side)
        }
    }

    private func resetLetterMatch() {
        session = makeLetterMatchSession(configuration: configuration)
        feedbackTone = .neutral
        shakeTrigger = 0
        status = UnlockFlowStepStatus(primaryState: .advance(enabled: false))
    }

    private func letterMatchBoard(side: CGFloat) -> some View {
        let cellSize = side / CGFloat(gridSide)

        return ZStack {
            gridLines(cellSize: cellSize)

            ForEach(Array(session.pairs.enumerated()), id: \.element.id) { _, pair in
                if let path = session.lockedPaths[pair.id] {
                    Path { pathShape in
                        addOrthogonalPath(path, cellSize: cellSize, in: &pathShape)
                    }
                    .stroke(pair.tint, style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round))
                    .shadow(color: pair.tint.opacity(0.34), radius: 16)
                }
            }

            if let activePair {
                Path { path in
                    addOrthogonalPath(session.activePath, cellSize: cellSize, in: &path)
                }
                .stroke(
                    feedbackTone == .error ? LocktyColors.error : activePair.tintColor,
                    style: StrokeStyle(lineWidth: 12, lineCap: .round, lineJoin: .round)
                )
                .shadow(color: (feedbackTone == .error ? LocktyColors.error : activePair.tintColor).opacity(0.36), radius: 16)
            }

            ForEach(0..<gridSide, id: \.self) { row in
                ForEach(0..<gridSide, id: \.self) { column in
                    let point = GridPoint(row: row, column: column)
                    let endpoint = endpoint(for: point)

                    ZStack {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(blockFill(for: point))

                        if let endpoint {
                            Circle()
                                .fill(endpoint.0.tintColor)
                                .frame(width: 34, height: 34)
                                .shadow(color: endpoint.0.tintColor.opacity(0.36), radius: 10)

                            Text(endpoint.0.letter)
                                .font(.system(.headline, design: .rounded, weight: .bold))
                                .foregroundStyle(.black)
                        }
                    }
                    .frame(width: cellSize - 6, height: cellSize - 6)
                    .position(x: CGFloat(column) * cellSize + cellSize / 2, y: CGFloat(row) * cellSize + cellSize / 2)
                }
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 32, style: .continuous))
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    updateLetterMatchDrag(location: value.location, side: side)
                }
                .onEnded { _ in
                    finishLetterMatchPath()
                }
        )
    }

    private func gridLines(cellSize: CGFloat) -> some View {
        ZStack {
            ForEach(1..<gridSide, id: \.self) { index in
                Rectangle()
                    .fill(LocktyColors.cardStroke.opacity(0.7))
                    .frame(width: 1, height: cellSize * CGFloat(gridSide) - 12)
                    .position(x: CGFloat(index) * cellSize, y: cellSize * CGFloat(gridSide) / 2)

                Rectangle()
                    .fill(LocktyColors.cardStroke.opacity(0.7))
                    .frame(width: cellSize * CGFloat(gridSide) - 12, height: 1)
                    .position(x: cellSize * CGFloat(gridSide) / 2, y: CGFloat(index) * cellSize)
            }
        }
    }

    private var activePair: ResolvedLetterPair? {
        guard let id = session.activePairID else { return nil }
        return resolvedPair(id: id)
    }

    private func endpoint(for point: GridPoint) -> (ResolvedLetterPair, Bool)? {
        for pair in session.pairs {
            let resolved = resolvedPair(id: pair.id)
            if resolved.start == point { return (resolved, true) }
            if resolved.end == point { return (resolved, false) }
        }
        return nil
    }

    private func resolvedPair(id: UUID) -> ResolvedLetterPair {
        let pair = session.pairs.first(where: { $0.id == id })!
        return ResolvedLetterPair(pair: pair)
    }

    private func updateLetterMatchDrag(location: CGPoint, side: CGFloat) {
        guard let point = cell(at: location, side: side, count: gridSide) else { return }

        if session.activePath.isEmpty {
            guard let endpoint = endpoint(for: point), session.lockedPaths[endpoint.0.id] == nil else { return }
            session.activePairID = endpoint.0.id
            session.activePath = [point]
            feedbackTone = .active
            feedbackPulse += 1
            haptics.selectionChanged()
            return
        }

        guard let activePair else { return }
        guard session.activePath.last != point else { return }

        if session.activePath.count >= 2, session.activePath[session.activePath.count - 2] == point {
            session.activePath.removeLast()
            return
        }

        guard isOrthogonallyAdjacent(session.activePath.last!, point) else { return }
        guard !lockedBlockedPoints.contains(point) else { return }
        guard canVisit(point, for: activePair) else { return }
        guard !session.activePath.contains(point) else { return }

        session.activePath.append(point)
        feedbackTone = .active
        feedbackPulse += 1
        haptics.selectionChanged()
    }

    private func canVisit(_ point: GridPoint, for pair: ResolvedLetterPair) -> Bool {
        guard let endpoint = endpoint(for: point) else { return true }
        return endpoint.0.id == pair.id
    }

    private func finishLetterMatchPath() {
        defer {
            if feedbackTone == .active {
                feedbackTone = .neutral
            }
        }

        guard let activePair else { return }
        guard session.activePath.last == activePair.end || session.activePath.last == activePair.start else {
            failLetterMatchPath()
            return
        }

        let endpoints = Set([activePair.start, activePair.end])
        guard endpoints.isSubset(of: Set(session.activePath)), session.activePath.count > 1 else {
            failLetterMatchPath()
            return
        }

        let proposedLockedPaths = session.lockedPaths.merging([activePair.id: session.activePath]) { _, new in new }
        guard hasLetterMatchSolution(pairs: session.pairs, lockedPaths: proposedLockedPaths, gridSide: gridSide) else {
            failLetterMatchPath()
            return
        }

        session.lockedPaths = proposedLockedPaths
        session.activePairID = nil
        session.activePath = []
        feedbackTone = .success
        haptics.impact(.rigid, intensity: 1)

        let finished = session.lockedPaths.count == session.pairs.count
        status.primaryState = .advance(enabled: finished)

        if !finished {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(420))
                feedbackTone = .neutral
            }
        }
    }

    private func failLetterMatchPath() {
        session.activePairID = nil
        session.activePath = []
        feedbackTone = .error
        shakeTrigger += 1
        haptics.impact(.heavy, intensity: 0.95)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            feedbackTone = .neutral
        }
    }

    private var lockedBlockedPoints: Set<GridPoint> {
        Set(session.lockedPaths.values.flatMap { $0 })
    }

    private func blockFill(for point: GridPoint) -> Color {
        if let activePair, session.activePath.contains(point) {
            return activePair.tintColor.opacity(0.2)
        }
        for pair in session.pairs where session.lockedPaths[pair.id]?.contains(point) == true {
            return ResolvedLetterPair(pair: pair).tintColor.opacity(0.18)
        }
        return .clear
    }

    private func letterBadge(for pair: LetterMatchPair, isDone: Bool) -> some View {
        let tint = pair.tint
        let foreground = isDone ? Color.black : tint
        let background = isDone ? tint : tint.opacity(0.16)

        return Text(pair.letter)
            .font(.system(.headline, design: .rounded, weight: .semibold))
            .foregroundStyle(foreground)
            .frame(width: 34, height: 34)
            .background(Circle().fill(background))
            .overlay(
                Circle().stroke(tint.opacity(0.36), lineWidth: 1)
            )
            .transition(.blurReplace.combined(with: .scale(0.9)).combined(with: .opacity))
    }

    private func addOrthogonalPath(_ points: [GridPoint], cellSize: CGFloat, in path: inout Path) {
        guard let first = points.first else { return }
        path.move(to: center(for: first, cellSize: cellSize))
        for point in points.dropFirst() {
            path.addLine(to: center(for: point, cellSize: cellSize))
        }
    }

    private func center(for point: GridPoint, cellSize: CGFloat) -> CGPoint {
        CGPoint(
            x: CGFloat(point.column) * cellSize + cellSize / 2,
            y: CGFloat(point.row) * cellSize + cellSize / 2
        )
    }
}

private struct ResolvedLetterPair: Identifiable {
    let id: UUID
    let letter: String
    let tintColor: Color
    let start: GridPoint
    let end: GridPoint

    init(pair: LetterMatchPair) {
        id = pair.id
        letter = pair.letter
        tintColor = pair.tint
        start = GridPoint(row: pair.startIndex / 5, column: pair.startIndex % 5)
        end = GridPoint(row: pair.endIndex / 5, column: pair.endIndex % 5)
    }
}

private struct LetterMatchPathPair: Identifiable {
    let id: UUID
    let start: GridPoint
    let end: GridPoint

    init(pair: LetterMatchPair) {
        id = pair.id
        start = GridPoint(row: pair.startIndex / 5, column: pair.startIndex % 5)
        end = GridPoint(row: pair.endIndex / 5, column: pair.endIndex % 5)
    }
}

private struct UnlockSquareBoardContainer<Content: View>: View {
    @ViewBuilder let content: (CGFloat) -> Content

    var body: some View {
        Color.clear
            .aspectRatio(1, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { proxy in
                    let side = min(proxy.size.width, proxy.size.height)
                    content(side)
                        .frame(width: side, height: side)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
                }
            }
    }
}

struct UnlockOperationsStepView: View {
    let configuration: OperationsConfiguration
    let submitTrigger: Int
    @Binding var status: UnlockFlowStepStatus

    @State private var runtime = OperationsRuntimeState(problems: [])
    @State private var answers: [String] = []
    @State private var activeIndex = 0
    @State private var fieldHighlights: [OperationsFieldHighlight] = []
    @State private var feedbackTone: UnlockFeedbackTone = .neutral
    @State private var shakeTrigger = 0
    @State private var isChecking = false

    private let haptics = HapticsFactory()

    var body: some View {
        UnlockStepSurface(tone: feedbackTone, shakeTrigger: shakeTrigger) {
            VStack(spacing: LocktySpacing.lg) {
                operationsHeader
                operationsList

                Rectangle()
                    .fill(.white.opacity(0.08))
                    .frame(height: 1)
                    .padding(.top, 2)
                    .padding(.bottom, 2)

                keypad
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .task(id: configuration.id) {
            resetOperations()
        }
        .onChange(of: submitTrigger, initial: false) { _, _ in
            submitAnswerIfNeeded()
        }
    }

    private var operationsHeader: some View {
        Text("Responde a todas las preguntas:")
            .font(.system(.callout, design: .default, weight: .medium))
            .foregroundStyle(LocktyColors.secondaryText)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var operationsList: some View {
        VStack(spacing: LocktySpacing.sm) {
            ForEach(Array(runtime.problems.enumerated()), id: \.element.id) { index, problem in
                operationRow(problem: problem, index: index)
            }
        }
    }

    private var keypad: some View {
        VStack(spacing: LocktySpacing.xs) {
            keypadRow(["1", "2", "3"])
            keypadRow(["4", "5", "6"])
            keypadRow(["7", "8", "9"])
            keypadRow([nil, "0", "delete"])
        }
    }

    private func resetOperations() {
        runtime = makeOperationsRuntime(configuration: configuration)
        answers = Array(repeating: "", count: runtime.problems.count)
        fieldHighlights = Array(repeating: .idle, count: runtime.problems.count)
        activeIndex = 0
        feedbackTone = .neutral
        shakeTrigger = 0
        isChecking = false
        status = UnlockFlowStepStatus(primaryState: .submit(enabled: false))
    }

    private func submitAnswerIfNeeded() {
        guard !isChecking else { return }
        guard answers.count == runtime.problems.count else { return }
        guard answers.allSatisfy({ !$0.isEmpty }) else { return }

        isChecking = true

        let invalidIndices = zip(runtime.problems.indices, zip(runtime.problems, answers))
            .compactMap { index, payload -> Int? in
                let (problem, answerText) = payload
                return Int(answerText) == problem.answer ? nil : index
            }
        let solved = invalidIndices.isEmpty

        guard solved else {
            failOperationsAndRestart(invalidIndices: invalidIndices)
            return
        }

        fieldHighlights = Array(repeating: .correct, count: runtime.problems.count)
        feedbackTone = .success
        haptics.impact(.rigid, intensity: 1)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(280))
            status.primaryState = .advance(enabled: true)
            isChecking = false
        }
    }

    private func failOperationsAndRestart(invalidIndices: [Int]) {
        fieldHighlights = runtime.problems.indices.map { invalidIndices.contains($0) ? .wrong : .correct }
        feedbackTone = .error
        shakeTrigger += 1
        isChecking = true
        haptics.impact(.heavy, intensity: 0.95)
        status.primaryState = .submit(enabled: false)
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(520))
            resetOperations()
        }
    }

    private func operationRow(problem: ArithmeticProblem, index: Int) -> some View {
        let answer = answers.indices.contains(index) ? answers[index] : ""
        let isActive = index == activeIndex
        let isFilled = !answer.isEmpty

        return Button {
            guard !isChecking, status.primaryState != .advance(enabled: true) else { return }
            guard canActivateOperation(at: index) else { return }
            withAnimation(.snappy(duration: 0.18)) {
                activeIndex = index
            }
            haptics.selectionChanged()
        } label: {
            HStack(spacing: LocktySpacing.sm) {
                Text("\(problem.left)")
                    .contentTransition(.numericText())
                Text(problem.operation.rawValue)
                    .foregroundStyle(LocktyColors.secondaryText)
                Text("\(problem.right)")
                    .contentTransition(.numericText())
                Text("=")
                    .foregroundStyle(LocktyColors.primaryText)

                answerField(answer: answer, index: index, isActive: isActive, isFilled: isFilled)
            }
            .font(.system(size: 24, weight: .bold, design: .rounded))
            .foregroundStyle(LocktyColors.primaryText)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isChecking || !canActivateOperation(at: index))
    }

    private func answerField(answer: String, index: Int, isActive: Bool, isFilled: Bool) -> some View {
        let highlight = fieldHighlights.indices.contains(index) ? fieldHighlights[index] : .idle
        let colors = colors(for: highlight, isActive: isActive)

        return ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(colors.fill)

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(colors.stroke, lineWidth: isActive ? 2.5 : 1.5)

            Text(answer.isEmpty ? " " : answer)
                .font(.system(size: 24, weight: .bold, design: .rounded))
                .foregroundStyle(isFilled ? LocktyColors.primaryText : .clear)
                .monospacedDigit()
                .contentTransition(.numericText())
        }
        .frame(width: 82, height: 58)
        .shadow(color: colors.glow, radius: 12)
        .animation(.smooth(duration: 0.22), value: isActive)
        .animation(.smooth(duration: 0.22), value: answer)
        .animation(.smooth(duration: 0.2), value: fieldHighlights)
    }

    @ViewBuilder
    private func keypadRow(_ keys: [String?]) -> some View {
        HStack(spacing: LocktySpacing.lg) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                keypadButton(for: key)
            }
        }
    }

    @ViewBuilder
    private func keypadButton(for key: String?) -> some View {
        switch key {
        case nil:
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 44)

        case "delete":
            Button {
                handleDelete()
            } label: {
                Image(systemName: "delete.left")
                    .font(.system(size: 21, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isChecking || status.primaryState == .advance(enabled: true))

        case .some(let digit):
            Button {
                handleDigit(digit)
            } label: {
                Text(digit)
                    .font(.system(size: 26, weight: .regular, design: .rounded))
                    .foregroundStyle(LocktyColors.primaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)
            .disabled(isChecking || status.primaryState == .advance(enabled: true))
        }
    }

    private func handleDigit(_ digit: String) {
        guard answers.indices.contains(activeIndex), !isChecking else { return }
        guard status.primaryState != .advance(enabled: true) else { return }

        let limit = max(String(runtime.problems[activeIndex].answer).count, 1)
        guard answers[activeIndex].count < max(limit, 2) else { return }

        withAnimation(.snappy(duration: 0.18)) {
            fieldHighlights[activeIndex] = .idle
            answers[activeIndex].append(digit)
            if answers[activeIndex].count >= limit {
                moveToNextEditableField()
            }
        }
        haptics.selectionChanged()
        syncSubmitState()
    }

    private func handleDelete() {
        guard !isChecking else { return }
        guard answers.indices.contains(activeIndex) else { return }
        guard status.primaryState != .advance(enabled: true) else { return }

        withAnimation(.snappy(duration: 0.18)) {
            if !answers[activeIndex].isEmpty {
                fieldHighlights[activeIndex] = .idle
                answers[activeIndex].removeLast()
            } else if let previous = previousEditableIndex(before: activeIndex) {
                activeIndex = previous
                if !answers[previous].isEmpty {
                    fieldHighlights[previous] = .idle
                    answers[previous].removeLast()
                }
            }
        }
        haptics.selectionChanged()
        syncSubmitState()
    }

    private func moveToNextEditableField() {
        guard let next = nextEmptyIndex(after: activeIndex) ?? nextEditableIndex(after: activeIndex) else { return }
        activeIndex = next
    }

    private func nextEmptyIndex(after index: Int) -> Int? {
        answers.indices.first { $0 > index && answers[$0].isEmpty }
    }

    private func nextEditableIndex(after index: Int) -> Int? {
        answers.indices.first { $0 > index }
    }

    private func previousEditableIndex(before index: Int) -> Int? {
        answers.indices.reversed().first { $0 < index }
    }

    private func canActivateOperation(at index: Int) -> Bool {
        guard let firstIncomplete = answers.firstIndex(where: \.isEmpty) else { return true }
        return index <= firstIncomplete
    }

    private func syncSubmitState() {
        guard status.primaryState != .advance(enabled: true) else { return }
        status.primaryState = .submit(enabled: answers.allSatisfy { !$0.isEmpty } && !isChecking)
    }

    private func colors(for highlight: OperationsFieldHighlight, isActive: Bool) -> (fill: Color, stroke: Color, glow: Color) {
        switch highlight {
        case .idle:
            if isActive {
                let accent = Color(red: 0.70, green: 0.98, blue: 0.88)
                return (
                    fill: Color(red: 0.16, green: 0.20, blue: 0.17),
                    stroke: accent,
                    glow: accent.opacity(0.28)
                )
            }
            return (
                fill: Color.black.opacity(0.16),
                stroke: LocktyColors.cardStroke.opacity(0.9),
                glow: .clear
            )
        case .correct:
            return (
                fill: LocktyColors.productive.opacity(0.14),
                stroke: LocktyColors.productive,
                glow: LocktyColors.productive.opacity(0.28)
            )
        case .wrong:
            return (
                fill: LocktyColors.error.opacity(0.14),
                stroke: LocktyColors.error,
                glow: LocktyColors.error.opacity(0.3)
            )
        }
    }
}

private enum OperationsFieldHighlight: Equatable {
    case idle
    case correct
    case wrong
}

struct UnlockIntentionStepView: View {
    let configuration: IntentionConfiguration
    @Binding var status: UnlockFlowStepStatus
    @State private var text = ""
    @FocusState private var isFocused: Bool

    private var trimmed: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var minimumLength: Int {
        configuration.minimumLength ?? 0
    }

    private var isValid: Bool {
        if configuration.isRequired {
            return !trimmed.isEmpty && trimmed.count >= minimumLength
        }
        return trimmed.count >= minimumLength
    }

    private var tone: UnlockFeedbackTone {
        if text.isEmpty { return .neutral }
        return isValid ? .success : .error
    }

    var body: some View {
        UnlockStepSurface(tone: tone, shakeTrigger: 0) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                Text(configuration.prompt)
                    .font(.system(.title3, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)

                TextField("Write here", text: $text, axis: .vertical)
                    .focused($isFocused)
                    .font(LocktyTypography.body)
                    .foregroundStyle(LocktyColors.primaryText)
                    .padding(.horizontal, LocktySpacing.md)
                    .padding(.vertical, LocktySpacing.md)
                    .background(
                        RoundedRectangle(cornerRadius: 24, style: .continuous)
                            .fill(LocktyColors.elevatedBackground)
                    )

                HStack {
                    if configuration.isRequired {
                        Text("Required")
                            .font(LocktyTypography.caption)
                            .foregroundStyle(LocktyColors.secondaryText)
                    }

                    Spacer(minLength: 0)

                    if minimumLength > 0 {
                        Text("\(trimmed.count)/\(minimumLength)")
                            .font(.system(.caption, design: .rounded, weight: .semibold))
                            .monospacedDigit()
                            .foregroundStyle(isValid ? LocktyColors.productive : LocktyColors.secondaryText)
                            .contentTransition(.numericText())
                    }
                }
            }
        }
        .task(id: configuration.id) {
            text = ""
            syncStatus()
            try? await Task.sleep(for: .milliseconds(320))
            isFocused = true
        }
        .onChange(of: text, initial: true) { _, _ in
            syncStatus()
        }
    }

    private func syncStatus() {
        status = UnlockFlowStepStatus(
            primaryState: .advance(enabled: isValid),
            intentionText: trimmed.isEmpty ? nil : trimmed
        )
    }
}

struct UnlockConfirmationStepView: View {
    let configuration: ConfirmationConfiguration

    var body: some View {
        UnlockStepSurface(tone: .neutral, shakeTrigger: 0) {
            VStack(spacing: LocktySpacing.lg) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 42, weight: .light))
                    .foregroundStyle(LocktyColors.primaryText)

                Text(configuration.prompt)
                    .font(.system(.title3, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct UnlockPersonalTextStepView: View {
    let configuration: PersonalTextConfiguration
    @Binding var status: UnlockFlowStepStatus
    @State private var chosenPhrase = ""

    var body: some View {
        UnlockStepSurface(tone: .success, shakeTrigger: 0) {
            VStack(alignment: .leading, spacing: LocktySpacing.lg) {
                Text("Read this once before you continue")
                    .font(LocktyTypography.callout)
                    .foregroundStyle(LocktyColors.secondaryText)

                Text("“\(chosenPhrase)”")
                    .font(.system(size: 30, weight: .bold, design: .rounded))
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentTransition(.interpolate)
            }
        }
        .task(id: configuration.id) {
            let phrases = configuration.phrases.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            chosenPhrase = phrases.randomElement() ?? ""
            status = .ready
        }
    }
}

private enum UnlockVideoPhase: Equatable {
    case loading
    case missing
    case playing
    case finished
    case failed(String)
}

struct UnlockPersonalVideoStepView: View {
    let configuration: PersonalVideoConfiguration
    @Binding var status: UnlockFlowStepStatus

    @State private var player: AVPlayer?
    @State private var phase: UnlockVideoPhase = .loading
    @State private var videoAspectRatio: CGFloat = 9 / 16
    @State private var isMuted = false
    @State private var isPlaying = false
    @State private var didCompletePlayback = false
    @State private var observationToken: NSObjectProtocol?

    var body: some View {
        // The video is its own surface. Wrapping it in an UnlockStepSurface put the
        // step's padding and a second rounded border around a frame that already draws
        // its own, so the video sat inset inside a card with two strokes around it.
        // Only the message states, which are text and need the padding, still use it.
        Group {
            switch phase {
            case .missing:
                messageSurface { unavailableMessage("The selected video file is missing.") }
            case .failed(let message):
                messageSurface { unavailableMessage(message) }
            default:
                videoPlayer
            }
        }
        .task(id: configuration.id) {
            await prepareVideo()
        }
        .onDisappear {
            player?.pause()
            if let observationToken {
                NotificationCenter.default.removeObserver(observationToken)
            }
        }
    }

    private func messageSurface<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        UnlockStepSurface(tone: .error, shakeTrigger: 0) {
            content()
        }
    }

    private var videoPlayer: some View {
        VideoPreviewLayer(player: player)
            .aspectRatio(videoAspectRatio, contentMode: .fit)
            .frame(maxWidth: .infinity)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(videoBorderColor, lineWidth: didCompletePlayback ? 1.5 : 1)
            }
            .shadow(color: videoGlowColor, radius: didCompletePlayback ? 20 : 0)
            .overlay(alignment: .bottomTrailing) {
                videoControls
                    .padding(14)
            }
            .animation(.smooth(duration: 0.24), value: didCompletePlayback)
            .animation(.smooth(duration: 0.24), value: phase)
    }

    private func unavailableMessage(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
            Image(systemName: "video.slash")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(LocktyColors.error)

            Text(message)
                .font(LocktyTypography.callout)
                .foregroundStyle(LocktyColors.secondaryText)
        }
        .frame(maxWidth: .infinity, minHeight: 220, alignment: .center)
    }

    private var videoControls: some View {
        HStack(spacing: 10) {
            videoControlButton(
                systemImage: isPlaying ? "pause.fill" : "play.fill",
                action: togglePlayback
            )
            videoControlButton(
                systemImage: isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                action: toggleMute
            )
            videoControlButton(
                systemImage: "arrow.counterclockwise",
                action: replay
            )
        }
    }

    private func videoControlButton(systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(Color.black.opacity(0.54))
                )
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var videoBorderColor: Color {
        switch phase {
        case .missing, .failed:
            LocktyColors.error
        default:
            didCompletePlayback ? LocktyColors.productive : LocktyColors.cardStroke
        }
    }

    private var videoGlowColor: Color {
        switch phase {
        case .missing, .failed:
            LocktyColors.error.opacity(0.16)
        default:
            didCompletePlayback ? LocktyColors.productive.opacity(0.28) : .clear
        }
    }

    @MainActor
    private func prepareVideo() async {
        status = UnlockFlowStepStatus(primaryState: .advance(enabled: false))
        if let observationToken {
            NotificationCenter.default.removeObserver(observationToken)
            self.observationToken = nil
        }
        didCompletePlayback = false
        isMuted = false
        isPlaying = false

        guard let url = resolveVideoURL(fileName: configuration.videoFileName) else {
            phase = .missing
            return
        }

        videoAspectRatio = await resolvedAspectRatio(for: url)
        let player = AVPlayer(url: url)
        player.isMuted = isMuted
        self.player = player
        phase = .playing
        isPlaying = true
        player.play()

        observationToken = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem,
            queue: .main
        ) { _ in
            phase = .finished
            didCompletePlayback = true
            isPlaying = false
            status = .ready
        }
    }

    private func togglePlayback() {
        guard let player else { return }
        if isPlaying {
            player.pause()
            isPlaying = false
            return
        }

        player.play()
        isPlaying = true
    }

    private func toggleMute() {
        isMuted.toggle()
        player?.isMuted = isMuted
    }

    private func replay() {
        guard let player else { return }
        player.seek(to: .zero)
        player.play()
        phase = didCompletePlayback ? .finished : .playing
        isPlaying = true
    }

    private func resolvedAspectRatio(for url: URL) async -> CGFloat {
        let asset = AVURLAsset(url: url)
        guard let track = try? await asset.loadTracks(withMediaType: .video).first else {
            return 9 / 16
        }

        guard
            let naturalSize = try? await track.load(.naturalSize),
            let preferredTransform = try? await track.load(.preferredTransform)
        else {
            return 9 / 16
        }

        let transformedSize = naturalSize.applying(preferredTransform)
        let width = abs(transformedSize.width)
        let height = abs(transformedSize.height)
        guard width > 0, height > 0 else {
            return 9 / 16
        }
        return width / height
    }
}

private struct VideoPreviewLayer: UIViewRepresentable {
    let player: AVPlayer?

    func makeUIView(context: Context) -> PlayerContainerView {
        let view = PlayerContainerView()
        view.playerLayer.videoGravity = .resizeAspect
        return view
    }

    func updateUIView(_ uiView: PlayerContainerView, context: Context) {
        uiView.playerLayer.player = player
    }
}

private final class PlayerContainerView: UIView {
    override static var layerClass: AnyClass { AVPlayerLayer.self }
    var playerLayer: AVPlayerLayer { layer as! AVPlayerLayer }
}

private enum UnlockNFCPhase: Equatable {
    case idle
    case scanning
    case matched
    case mismatched
    case failed(String)
}

private enum UnlockLocationPhase: Equatable {
    case idle
    case checking
    case matched
    case outside
    case failed(String)
}

struct UnlockNFCTagStepView: View {
    let configuration: NFCTagConfiguration
    let scanTrigger: Int
    let nfcService: NFCServicing?
    @Binding var status: UnlockFlowStepStatus

    @State private var phase: UnlockNFCPhase = .idle
    @State private var shakeTrigger = 0

    private let haptics = HapticsFactory()

    var body: some View {
        UnlockStepSurface(tone: tone, shakeTrigger: shakeTrigger) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                HStack {
                    Text(configuration.displayName ?? "NFC Tag")
                        .font(.system(.headline, design: .rounded, weight: .semibold))
                        .foregroundStyle(LocktyColors.primaryText)

                    Spacer(minLength: 0)

                    Text(phaseTitle)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(phaseForeground)
                        .padding(.horizontal, LocktySpacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(phaseBackground)
                        )
                        .contentTransition(.interpolate)
                }

                Image(systemName: phase == .matched ? "checkmark.circle.fill" : "wave.3.right.circle")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(phase == .matched ? LocktyColors.productive : LocktyColors.primaryText)
                    .frame(maxWidth: .infinity)

                Text(phaseMessage)
                    .font(.system(.title3, design: .rounded, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .task(id: configuration.id) {
            phase = .idle
            status = UnlockFlowStepStatus(primaryState: .scan(enabled: true))
        }
        .onChange(of: scanTrigger, initial: false) { _, _ in
            Task { await scanIfNeeded() }
        }
    }

    private var tone: UnlockFeedbackTone {
        switch phase {
        case .idle:
            .neutral
        case .scanning:
            .active
        case .matched:
            .success
        case .mismatched, .failed:
            .error
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .idle:
            "Ready"
        case .scanning:
            "Scanning"
        case .matched:
            "Matched"
        case .mismatched, .failed:
            "Try again"
        }
    }

    private var phaseForeground: Color {
        switch phase {
        case .matched:
            .black
        case .mismatched, .failed:
            LocktyColors.error
        default:
            LocktyColors.primaryText
        }
    }

    private var phaseBackground: Color {
        switch phase {
        case .matched:
            LocktyColors.productive
        case .mismatched, .failed:
            LocktyColors.error.opacity(0.14)
        default:
            LocktyColors.elevatedBackground
        }
    }

    private var phaseMessage: String {
        switch phase {
        case .idle:
            return "Scan the saved tag to continue."
        case .scanning:
            return "Hold your iPhone near the NFC tag."
        case .matched:
            return "Correct tag detected."
        case .mismatched:
            return "That tag does not match this friction."
        case .failed(let message):
            return message
        }
    }

    @MainActor
    private func scanIfNeeded() async {
        guard case .matched = phase else {
            guard case .scanning = phase else {
                status.primaryState = .scan(enabled: false)
                phase = .scanning

                guard let nfcService else {
                    phase = .failed("NFC is unavailable in this build.")
                    status.primaryState = .scan(enabled: true)
                    shakeTrigger += 1
                    haptics.impact(.heavy, intensity: 0.95)
                    return
                }

                do {
                    let scanned = normalizeTagID(try await nfcService.scanTagIdentifier())
                    let expected = normalizeTagID(configuration.normalizedIdentifier)
                    if scanned == expected {
                        phase = .matched
                        status = .ready
                        haptics.impact(.rigid, intensity: 1)
                    } else {
                        phase = .mismatched
                        status.primaryState = .scan(enabled: true)
                        shakeTrigger += 1
                        haptics.impact(.heavy, intensity: 0.95)
                    }
                } catch {
                    phase = .failed(error.localizedDescription)
                    status.primaryState = .scan(enabled: true)
                    shakeTrigger += 1
                    haptics.impact(.heavy, intensity: 0.95)
                }
                return
            }
            return
        }
        status = .ready
    }
}

struct UnlockLocationStepView: View {
    let configuration: LocationTrigger
    let checkTrigger: Int
    let locationService: LocationTriggerServicing?
    @Binding var status: UnlockFlowStepStatus

    @State private var phase: UnlockLocationPhase = .idle
    @State private var shakeTrigger = 0

    private let haptics = HapticsFactory()

    var body: some View {
        UnlockStepSurface(tone: tone, shakeTrigger: shakeTrigger) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(configuration.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Saved place" : configuration.name)
                            .font(.system(.headline, design: .rounded, weight: .semibold))
                            .foregroundStyle(LocktyColors.primaryText)

                        Text("\(Int(configuration.radiusMeters)) m radius")
                            .font(.system(.caption, design: .rounded, weight: .medium))
                            .foregroundStyle(LocktyColors.secondaryText)
                            .contentTransition(.numericText())
                    }

                    Spacer(minLength: 0)

                    Text(phaseTitle)
                        .font(.system(.caption, design: .rounded, weight: .semibold))
                        .foregroundStyle(phaseForeground)
                        .padding(.horizontal, LocktySpacing.sm)
                        .padding(.vertical, 6)
                        .background(
                            Capsule(style: .continuous)
                                .fill(phaseBackground)
                        )
                        .contentTransition(.interpolate)
                }

                Image(systemName: phase == .matched ? "location.fill" : "location.circle")
                    .font(.system(size: 54, weight: .light))
                    .foregroundStyle(phase == .matched ? LocktyColors.productive : LocktyColors.primaryText)
                    .frame(maxWidth: .infinity)

                Text(phaseMessage)
                    .font(.system(.title3, design: .rounded, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity)
        }
        .task(id: configuration.id) {
            phase = .idle
            status = UnlockFlowStepStatus(primaryState: .submit(enabled: true))
        }
        .onChange(of: checkTrigger, initial: false) { _, _ in
            Task { await checkLocationIfNeeded() }
        }
    }

    private var tone: UnlockFeedbackTone {
        switch phase {
        case .idle:
            .neutral
        case .checking:
            .active
        case .matched:
            .success
        case .outside, .failed:
            .error
        }
    }

    private var phaseTitle: String {
        switch phase {
        case .idle:
            "Ready"
        case .checking:
            "Checking"
        case .matched:
            "Inside"
        case .outside, .failed:
            "Try again"
        }
    }

    private var phaseForeground: Color {
        switch phase {
        case .matched:
            .black
        case .outside, .failed:
            LocktyColors.error
        default:
            LocktyColors.primaryText
        }
    }

    private var phaseBackground: Color {
        switch phase {
        case .matched:
            LocktyColors.productive
        case .outside, .failed:
            LocktyColors.error.opacity(0.14)
        default:
            LocktyColors.elevatedBackground
        }
    }

    private var phaseMessage: String {
        switch phase {
        case .idle:
            return "Check that you are inside the saved location."
        case .checking:
            return "Verifying your current position."
        case .matched:
            return "You are inside the allowed area."
        case .outside:
            return "You are not inside the saved area yet."
        case .failed(let message):
            return message
        }
    }

    @MainActor
    private func checkLocationIfNeeded() async {
        guard case .matched = phase else {
            status.primaryState = .submit(enabled: false)
            phase = .checking

            guard let locationService else {
                phase = .failed("Location is unavailable in this build.")
                status.primaryState = .submit(enabled: true)
                shakeTrigger += 1
                haptics.impact(.heavy, intensity: 0.95)
                return
            }

            do {
                if try await locationService.isInside(configuration) {
                    phase = .matched
                    status = .ready
                    haptics.impact(.rigid, intensity: 1)
                } else {
                    phase = .outside
                    status.primaryState = .submit(enabled: true)
                    shakeTrigger += 1
                    haptics.impact(.heavy, intensity: 0.95)
                }
            } catch {
                phase = .failed(error.localizedDescription)
                status.primaryState = .submit(enabled: true)
                shakeTrigger += 1
                haptics.impact(.heavy, intensity: 0.95)
            }
            return
        }

        status = .ready
    }
}

private func normalizeDirection(from start: GridPoint, to end: GridPoint) -> (Int, Int)? {
    let rowDelta = end.row - start.row
    let columnDelta = end.column - start.column
    guard rowDelta != 0 || columnDelta != 0 else { return nil }
    return (rowDelta == 0 ? 0 : rowDelta / abs(rowDelta), columnDelta == 0 ? 0 : columnDelta / abs(columnDelta))
}

private func isOrthogonallyAdjacent(_ lhs: GridPoint, _ rhs: GridPoint) -> Bool {
    abs(lhs.row - rhs.row) + abs(lhs.column - rhs.column) == 1
}

private func normalizedDirection(from start: GridPoint, to end: GridPoint) -> (Int, Int)? {
    let rowDelta = end.row - start.row
    let columnDelta = end.column - start.column
    guard rowDelta != 0 || columnDelta != 0 else { return nil }
    return (
        rowDelta == 0 ? 0 : rowDelta / abs(rowDelta),
        columnDelta == 0 ? 0 : columnDelta / abs(columnDelta)
    )
}

private func cell(at location: CGPoint, side: CGFloat, count: Int) -> GridPoint? {
    guard side > 0, count > 0 else { return nil }
    let cellSize = side / CGFloat(count)
    let column = Int(location.x / cellSize)
    let row = Int(location.y / cellSize)
    guard (0..<count).contains(row), (0..<count).contains(column) else { return nil }
    return GridPoint(row: row, column: column)
}

private func makeWordSearchSession(configuration: WordSearchConfiguration) -> WordSearchSession {
    let size = configuration.difficulty.gridSize
    let words = makeWordSearchWords(configuration: configuration)
    var board = Array(repeating: Array(repeating: "", count: size), count: size)
    let directions = [
        (-1, 0),
        (0, -1), (0, 1),
        (1, 0)
    ]

    for word in words {
        let letters = word.map(String.init)
        var placed = false

        for _ in 0..<240 where !placed {
            let direction = directions.randomElement()!
            let row = Int.random(in: 0..<size)
            let column = Int.random(in: 0..<size)
            let endRow = row + direction.0 * (letters.count - 1)
            let endColumn = column + direction.1 * (letters.count - 1)

            guard (0..<size).contains(endRow), (0..<size).contains(endColumn) else { continue }

            var points: [GridPoint] = []
            var canPlace = true
            for index in letters.indices {
                let point = GridPoint(row: row + direction.0 * index, column: column + direction.1 * index)
                let existing = board[point.row][point.column]
                if !existing.isEmpty && existing != letters[index] {
                    canPlace = false
                    break
                }
                points.append(point)
            }

            guard canPlace else { continue }
            for (index, point) in points.enumerated() {
                board[point.row][point.column] = letters[index]
            }
            placed = true
        }
    }

    let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
    for row in 0..<size {
        for column in 0..<size where board[row][column].isEmpty {
            board[row][column] = alphabet.randomElement()!
        }
    }

    return WordSearchSession(board: board, words: words, currentWordIndex: 0, foundWords: [])
}

private func makeWordSearchWords(configuration: WordSearchConfiguration) -> [String] {
    if let target = configuration.targetWord?
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .uppercased(),
       !target.isEmpty {
        return [target]
    }

    let bank: [String]
    let count: Int
    switch configuration.difficulty {
    case .easy:
        bank = ["FOCUS", "CALM", "PAUSE", "BOUND", "INTENT", "CHOICE"]
        count = 2
    case .medium:
        bank = ["FOCUS", "INTENT", "BALANCE", "ROUTINE", "BREATH", "CENTER", "DECIDE"]
        count = 3
    case .hard:
        bank = ["BOUNDARY", "CLARITY", "DISCIPLINE", "INTENTION", "PRIORITY", "ATTENTION", "STABILITY"]
        count = 4
    }

    let maxLength = configuration.difficulty.gridSize
    let filtered = bank.filter { $0.count <= maxLength }
    return Array(filtered.shuffled().prefix(count))
}

private func makeLetterMatchSession(configuration: LetterMatchConfiguration) -> LetterMatchSession {
    let pairStyles: [(String, String)] = [
        ("A", "red"),
        ("B", "blue"),
        ("C", "green"),
        ("D", "yellow"),
        ("E", "mint"),
        ("F", "orange")
    ]
    let pairCount = min(max(configuration.pairCount, 2), pairStyles.count)
    let paths = makeLetterMatchTemplatePaths(pairCount: pairCount, gridSide: 5)

    let pairs = Array(zip(pairStyles.prefix(pairCount), paths)).map { style, path in
        LetterMatchPair(
            letter: style.0,
            colorName: style.1,
            startIndex: path.first!.row * 5 + path.first!.column,
            endIndex: path.last!.row * 5 + path.last!.column
        )
    }

    return LetterMatchSession(pairs: pairs, lockedPaths: [:], activePairID: nil, activePath: [])
}

private func makeLetterMatchTemplatePaths(pairCount: Int, gridSide: Int) -> [[GridPoint]] {
    let basePaths: [[GridPoint]] = [
        [GridPoint(row: 0, column: 0), GridPoint(row: 0, column: 1), GridPoint(row: 0, column: 2), GridPoint(row: 0, column: 3)],
        [GridPoint(row: 1, column: 0), GridPoint(row: 2, column: 0), GridPoint(row: 3, column: 0)],
        [GridPoint(row: 1, column: 2), GridPoint(row: 1, column: 3), GridPoint(row: 1, column: 4), GridPoint(row: 2, column: 4)],
        [GridPoint(row: 2, column: 1), GridPoint(row: 2, column: 2), GridPoint(row: 3, column: 2), GridPoint(row: 4, column: 2)],
        [GridPoint(row: 3, column: 4), GridPoint(row: 4, column: 4), GridPoint(row: 4, column: 3)],
        [GridPoint(row: 4, column: 0), GridPoint(row: 4, column: 1), GridPoint(row: 3, column: 1)]
    ]
    let transform = Int.random(in: 0..<8)

    return Array(basePaths.prefix(pairCount)).map { path in
        path.map { transformLetterMatchPoint($0, gridSide: gridSide, variant: transform) }
    }
}

private func transformLetterMatchPoint(_ point: GridPoint, gridSide: Int, variant: Int) -> GridPoint {
    let last = gridSide - 1

    switch variant {
    case 0:
        return point
    case 1:
        return GridPoint(row: point.column, column: last - point.row)
    case 2:
        return GridPoint(row: last - point.row, column: last - point.column)
    case 3:
        return GridPoint(row: last - point.column, column: point.row)
    case 4:
        return GridPoint(row: point.row, column: last - point.column)
    case 5:
        return GridPoint(row: last - point.row, column: point.column)
    case 6:
        return GridPoint(row: point.column, column: point.row)
    default:
        return GridPoint(row: last - point.column, column: last - point.row)
    }
}

private func hasLetterMatchSolution(
    pairs: [LetterMatchPair],
    lockedPaths: [UUID: [GridPoint]],
    gridSide: Int
) -> Bool {
    let blocked = Set(lockedPaths.values.flatMap { $0 })
    let unresolved = pairs
        .filter { lockedPaths[$0.id] == nil }
        .map { pair in
            LetterMatchPathPair(pair: pair)
        }
        .sorted { lhs, rhs in
            letterMatchDistance(lhs.start, lhs.end) < letterMatchDistance(rhs.start, rhs.end)
        }

    func search(pairIndex: Int, occupied: Set<GridPoint>) -> Bool {
        guard pairIndex < unresolved.count else { return true }

        let pair = unresolved[pairIndex]
        guard !occupied.contains(pair.start), !occupied.contains(pair.end) else { return false }

        let candidatePaths = makeLetterMatchCandidatePaths(
            from: pair.start,
            to: pair.end,
            gridSide: gridSide,
            occupied: occupied,
            limit: 24
        )

        for path in candidatePaths {
            if search(pairIndex: pairIndex + 1, occupied: occupied.union(path)) {
                return true
            }
        }

        return false
    }

    return search(pairIndex: 0, occupied: blocked)
}

private func makeLetterMatchCandidatePaths(
    from start: GridPoint,
    to end: GridPoint,
    gridSide: Int,
    occupied: Set<GridPoint>,
    limit: Int
) -> [[GridPoint]] {
    var results: [[GridPoint]] = []
    let maxLength = gridSide * gridSide - occupied.count

    func dfs(current: GridPoint, path: [GridPoint], visited: Set<GridPoint>) {
        guard results.count < limit else { return }
        guard path.count <= maxLength else { return }

        if current == end {
            results.append(path)
            return
        }

        let neighbors = letterMatchNeighbors(for: current, gridSide: gridSide)
            .filter { neighbor in
                if neighbor == end { return true }
                return !occupied.contains(neighbor) && !visited.contains(neighbor)
            }
            .sorted { lhs, rhs in
                letterMatchDistance(lhs, end) < letterMatchDistance(rhs, end)
            }

        for neighbor in neighbors {
            var nextVisited = visited
            nextVisited.insert(neighbor)
            dfs(current: neighbor, path: path + [neighbor], visited: nextVisited)
        }
    }

    guard !occupied.contains(start), !occupied.contains(end) else { return [] }
    dfs(current: start, path: [start], visited: [start])

    return results.sorted { lhs, rhs in
        if lhs.count == rhs.count {
            return letterMatchTurns(in: lhs) < letterMatchTurns(in: rhs)
        }
        return lhs.count < rhs.count
    }
}

private func letterMatchNeighbors(for point: GridPoint, gridSide: Int) -> [GridPoint] {
    [
        GridPoint(row: point.row - 1, column: point.column),
        GridPoint(row: point.row + 1, column: point.column),
        GridPoint(row: point.row, column: point.column - 1),
        GridPoint(row: point.row, column: point.column + 1)
    ]
    .filter { (0..<gridSide).contains($0.row) && (0..<gridSide).contains($0.column) }
}

private func letterMatchDistance(_ lhs: GridPoint, _ rhs: GridPoint) -> Int {
    abs(lhs.row - rhs.row) + abs(lhs.column - rhs.column)
}

private func letterMatchTurns(in path: [GridPoint]) -> Int {
    guard path.count >= 3 else { return 0 }

    var turns = 0
    for index in 2..<path.count {
        let previous = path[index - 2]
        let current = path[index - 1]
        let next = path[index]
        let firstDirection = (current.row - previous.row, current.column - previous.column)
        let secondDirection = (next.row - current.row, next.column - current.column)
        if firstDirection != secondDirection {
            turns += 1
        }
    }
    return turns
}

private func makeOperationsRuntime(configuration: OperationsConfiguration) -> OperationsRuntimeState {
    let operators = Array(configuration.allowedOperators).sorted { $0.rawValue < $1.rawValue }
    let problems = (0..<max(configuration.problemCount, 1)).map { _ in
        makeProblem(difficulty: configuration.difficulty, operators: operators)
    }
    return OperationsRuntimeState(problems: problems)
}

private func makeProblem(difficulty: OperationsDifficulty, operators: [ArithmeticOperator]) -> ArithmeticProblem {
    let operation = operators.randomElement() ?? .addition

    let range: ClosedRange<Int>
    switch difficulty {
    case .easy:
        range = 1...9
    case .medium:
        range = 3...20
    case .hard:
        range = 8...50
    }

    switch operation {
    case .addition:
        let left = Int.random(in: range)
        let right = Int.random(in: range)
        return ArithmeticProblem(left: left, right: right, operation: .addition, answer: left + right)
    case .subtraction:
        let left = Int.random(in: range)
        let right = Int.random(in: range.lowerBound...left)
        return ArithmeticProblem(left: left, right: right, operation: .subtraction, answer: left - right)
    case .multiplication:
        let left = Int.random(in: range)
        let right = Int.random(in: difficulty == .hard ? 3...12 : 2...9)
        return ArithmeticProblem(left: left, right: right, operation: .multiplication, answer: left * right)
    case .division:
        let divisor = Int.random(in: 2...9)
        let answer = Int.random(in: range)
        return ArithmeticProblem(left: divisor * answer, right: divisor, operation: .division, answer: answer)
    }
}

private func resolveVideoURL(fileName: String) -> URL? {
    let trimmed = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let fileManager = FileManager.default
    let url = URL(fileURLWithPath: trimmed)
    if trimmed.hasPrefix("/") && fileManager.fileExists(atPath: url.path) {
        return url
    }

    let baseName = URL(fileURLWithPath: trimmed).deletingPathExtension().lastPathComponent
    let pathName = URL(fileURLWithPath: trimmed).lastPathComponent
    let searchNames = Array(Set([trimmed, pathName, baseName]))
    let directories = [
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedKeys.appGroupIdentifier)?
            .appendingPathComponent("SharedState", isDirectory: true),
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("LocktySharedFallback", isDirectory: true),
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first,
        URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
    ].compactMap { $0 }

    for directory in directories {
        for name in searchNames {
            let direct = directory.appendingPathComponent(name)
            if fileManager.fileExists(atPath: direct.path) {
                return direct
            }
        }

        if let enumerator = fileManager.enumerator(at: directory, includingPropertiesForKeys: nil) {
            for case let fileURL as URL in enumerator {
                let lastPath = fileURL.lastPathComponent
                if searchNames.contains(lastPath) || searchNames.contains(fileURL.deletingPathExtension().lastPathComponent) {
                    return fileURL
                }
            }
        }
    }

    let bundleCandidates = [
        Bundle.main.url(forResource: baseName, withExtension: URL(fileURLWithPath: trimmed).pathExtension.isEmpty ? nil : URL(fileURLWithPath: trimmed).pathExtension),
        Bundle.main.url(forResource: baseName, withExtension: "mp4"),
        Bundle.main.url(forResource: baseName, withExtension: "mov"),
        Bundle.main.url(forResource: baseName, withExtension: "m4v")
    ]
    return bundleCandidates.compactMap { $0 }.first
}

private func normalizeTagID(_ value: String) -> String {
    value
        .filter(\.isHexDigit)
        .lowercased()
}

private extension LetterMatchPair {
    var tint: Color {
        switch colorName {
        case "red":
            LocktyColors.error
        case "blue":
            Color(red: 0.36, green: 0.62, blue: 1)
        case "green":
            LocktyColors.productive
        case "yellow":
            LocktyColors.warning
        case "mint":
            Color.mint
        case "orange":
            Color.orange
        default:
            LocktyColors.primaryText
        }
    }
}

private enum UnlockStepsPhase: Equatable {
    case reading
    case met(Int)
    case short(current: Int, goal: Int)
    case unavailable(String)
}

/// The step goal, measured against what Health says you have actually walked today.
///
/// Read at the moment the step appears rather than stored: a step count is only true for
/// the minute it was taken in, and a saved one would be answering yesterday's question.
struct UnlockStepsStepView: View {
    let configuration: StepsConfiguration
    let healthService: HealthServicing?
    @Binding var status: UnlockFlowStepStatus

    @State private var phase: UnlockStepsPhase = .reading
    /// Counted up to rather than set: the number climbing to what you walked is the
    /// whole point of showing it, and it is what the confetti lands on.
    @State private var displayedCount = 0
    @State private var celebrates = false

    private let haptics = HapticsFactory()

    var body: some View {
        UnlockStepSurface(tone: surfaceTone, shakeTrigger: 0) {
            VStack(spacing: LocktySpacing.lg) {
                Image(systemName: "figure.walk")
                    .font(.system(size: 30, weight: .light))
                    .foregroundStyle(accent)

                Text(displayedCount.formatted(.number.grouping(.automatic)))
                    .font(.system(size: 56, weight: .semibold, design: .rounded))
                    .foregroundStyle(LocktyColors.primaryText)
                    .monospacedDigit()
                    .contentTransition(.numericText())
                    .animation(.smooth(duration: 0.9), value: displayedCount)

                shortfallLabel
            }
            .frame(maxWidth: .infinity)
            // The confetti sits over the whole surface rather than over the number, so
            // the burst reads as coming from the card, not out of the digits.
            .overlay {
                if celebrates {
                    LocktyConfettiEmitter()
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .task(id: configuration.id) {
            await evaluate()
        }
    }

    @ViewBuilder
    private var shortfallLabel: some View {
        switch phase {
        case .reading:
            Text("Leyendo tus pasos...")
                .font(LocktyTypography.callout)
                .foregroundStyle(LocktyColors.secondaryText)

        case .met:
            Text("Has llegado a tu meta de hoy.")
                .font(LocktyTypography.callout)
                .foregroundStyle(LocktyColors.productive)
                .multilineTextAlignment(.center)

        case .short(let current, let goal):
            // The exact shortfall, not a percentage: what is being asked for is a number
            // of steps, so the answer is a number of steps.
            Text("Te faltan un total de \(max(goal - current, 0).formatted(.number.grouping(.automatic))) pasos para poder desbloquear")
                .font(LocktyTypography.callout)
                .foregroundStyle(LocktyColors.secondaryText)
                .multilineTextAlignment(.center)

        case .unavailable(let message):
            Text(message)
                .font(LocktyTypography.callout)
                .foregroundStyle(LocktyColors.secondaryText)
                .multilineTextAlignment(.center)
        }
    }

    private var accent: Color {
        switch phase {
        case .met:
            LocktyColors.productive
        case .unavailable:
            LocktyColors.error
        case .reading, .short:
            LocktyColors.primaryText
        }
    }

    private var surfaceTone: UnlockFeedbackTone {
        switch phase {
        case .met:
            .success
        case .unavailable:
            .error
        case .reading, .short:
            .neutral
        }
    }

    @MainActor
    private func evaluate() async {
        status = UnlockFlowStepStatus(primaryState: .advance(enabled: false))
        phase = .reading
        displayedCount = 0
        celebrates = false

        guard let healthService, healthService.isAvailable else {
            phase = .unavailable("Health no está disponible en este dispositivo.")
            // Nothing can be measured, so nothing can be demanded. Blocking the unlock on
            // a reading that cannot exist would make the friction impossible to pass.
            status = .ready
            return
        }

        do {
            let count = try await healthService.stepCountToday()

            withAnimation(.smooth(duration: 0.9)) {
                displayedCount = count
            }

            if count >= configuration.dailyGoal {
                phase = .met(count)
                status = .ready
                // After the count has finished climbing, so the burst marks the number
                // arriving rather than firing over a zero.
                try? await Task.sleep(for: .milliseconds(700))
                guard !Task.isCancelled else { return }
                withAnimation(.smooth(duration: 0.3)) {
                    celebrates = true
                }
                haptics.impact(.medium, intensity: 1)
            } else {
                phase = .short(current: count, goal: configuration.dailyGoal)
                status = UnlockFlowStepStatus(primaryState: .advance(enabled: false))
            }
        } catch {
            phase = .unavailable(error.localizedDescription)
            status = .ready
        }
    }
}

/// The burst that marks a met goal.
///
/// A CAEmitterLayer rather than a pile of animated SwiftUI views: this is hundreds of
/// short-lived particles, and the work belongs on the render server rather than in a
/// layout pass that has to keep up with them.
private struct LocktyConfettiEmitter: UIViewRepresentable {
    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        view.layer.addSublayer(makeEmitter())
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        guard let emitter = uiView.layer.sublayers?.first as? CAEmitterLayer else { return }
        emitter.emitterPosition = CGPoint(x: uiView.bounds.midX, y: -12)
        emitter.emitterSize = CGSize(width: uiView.bounds.width, height: 1)
    }

    private func makeEmitter() -> CAEmitterLayer {
        let emitter = CAEmitterLayer()
        emitter.emitterShape = .line
        emitter.birthRate = 1
        emitter.emitterCells = colors.map(makeCell)
        // Stops after the burst rather than raining forever: this celebrates a moment.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
            emitter.birthRate = 0
        }
        return emitter
    }

    private var colors: [UIColor] {
        [
            UIColor(LocktyColors.productive),
            .systemYellow,
            .systemTeal,
            .white
        ]
    }

    private func makeCell(color: UIColor) -> CAEmitterCell {
        let cell = CAEmitterCell()
        cell.birthRate = 14
        cell.lifetime = 3.4
        cell.velocity = 180
        cell.velocityRange = 70
        cell.emissionLongitude = .pi
        cell.emissionRange = .pi / 5
        cell.spin = 3.4
        cell.spinRange = 4
        cell.scale = 0.5
        cell.scaleRange = 0.25
        cell.color = color.cgColor
        cell.contents = Self.particleImage.cgImage
        return cell
    }

    /// One small rounded rectangle, drawn once and tinted per cell.
    private static let particleImage: UIImage = {
        let size = CGSize(width: 9, height: 14)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.white.setFill()
            UIBezierPath(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 2).fill()
            _ = context
        }
    }()
}
