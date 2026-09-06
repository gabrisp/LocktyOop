import SwiftUI

/// What the plus opens: the things you do often, one tap away.
///
/// A grid of tiles that is the person's own, not a menu the app decided on. Holding any
/// tile turns the panel over: each one grows a minus, the card grows a strip along the
/// bottom with everything else that could be on it, and tiles can be dragged into the
/// order you want them in. The check puts it back.
///
/// One state, not three flags. `mode` is the whole of what the panel is doing, so there is
/// no arrangement of booleans that can describe a panel both editing and not.
struct QuickActionsPanel: View {
    @Binding var set: QuickActionSet
    /// The objectives that can be logged from here, for the tiles that log one.
    let objectives: [Objective]
    /// The modes that can be started from here, for the tiles that start one.
    let routines: [Routine]
    /// Whether an objective already counts as done, for the tile that says so.
    let isComplete: (Objective) -> Bool
    var onRun: (QuickAction) -> Void
    var onSave: (QuickActionSet) -> Void

    /// What the panel is doing, and -- while it is being arranged -- the arrangement so
    /// far.
    ///
    /// The draft lives in the state rather than beside it. Editing is a thing you can back
    /// out of, so what you are doing to the layout has to be somewhere that is thrown away
    /// when you do: with the changes written straight through, there was nothing to cancel
    /// and no moment at which anything was saved.
    enum Mode: Equatable {
        case running
        case editing(QuickActionSet)

        var isEditing: Bool {
            if case .editing = self { return true }
            return false
        }

        /// The arrangement being worked on, if one is.
        var draft: QuickActionSet? {
            if case .editing(let draft) = self { return draft }
            return nil
        }
    }

    @State private var mode: Mode = .running
    @Environment(\.colorScheme) private var colorScheme

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 3)

    /// What is on screen: the draft while arranging, what is saved otherwise.
    private var shown: QuickActionSet {
        mode.draft ?? set
    }

    var body: some View {
        VStack(spacing: 0) {
            if mode.isEditing {
                header
            }

            if shown.actions.isEmpty {
                emptyTile
                    .padding(.horizontal, 15)
                    .padding(.top, mode.isEditing ? 16 : 18)
                    .padding(.bottom, 18)
            } else {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(shown.actions) { action in
                        tile(action)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, mode.isEditing ? 16 : 18)
                .padding(.bottom, 18)
            }

            if mode.isEditing {
                addStrip
            }
        }
        .animation(.smooth(duration: 0.32), value: mode)
        .animation(.smooth(duration: 0.32), value: shown.actions)
    }

    /// Changes the arrangement being worked on. Does nothing when nothing is being
    /// arranged, which is what keeps a stray tap from rewriting a saved layout.
    private func edit(_ transform: (inout QuickActionSet) -> Void) {
        guard var draft = mode.draft else { return }
        transform(&draft)
        withAnimation(.smooth(duration: 0.32)) { mode = .editing(draft) }
    }

    /// What is here when there is nothing here.
    ///
    /// The way in was holding a tile, so removing the last one removed the way to get any
    /// back: an empty panel with no gesture on it and no button, which is a dead end you
    /// cannot even see the shape of. This is the door, and it says what it opens.
    private var emptyTile: some View {
        Button {
            withAnimation(.smooth(duration: 0.32)) {
                mode = mode.isEditing ? mode : .editing(set)
            }
        } label: {
            VStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)

                Text(mode.isEditing ? "Pick from below" : "Add actions")
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 96)
            .background {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(LocktyColors.ink(0.06))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(LocktyColors.ink(0.10), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)))
        .tappable()
    }

    // MARK: - Editing chrome

    private var header: some View {
        HStack(spacing: LocktySpacing.sm) {
            // Out without saving. The layout you started with is still in `set`, so
            // leaving is simply forgetting the draft.
            Button {
                withAnimation(.smooth(duration: 0.32)) { mode = .running }
            } label: {
                Text("Cancel")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .padding(.horizontal, LocktySpacing.md)
                    .frame(height: 34)
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
            .tappable()

            Spacer(minLength: 0)

            Text("Arrange")
                .font(.system(.subheadline, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)

            Spacer(minLength: 0)

            Button {
                guard let draft = mode.draft else { return }
                set = draft
                onSave(draft)
                withAnimation(.smooth(duration: 0.32)) { mode = .running }
            } label: {
                Text("Save")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.onPrimary)
                    .padding(.horizontal, LocktySpacing.md)
                    .frame(height: 34)
                    .background { Capsule(style: .continuous).fill(LocktyColors.primaryText) }
                    .contentShape(Capsule(style: .continuous))
            }
            .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
            .tappable()
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        // Room between the bar and what it is acting on. Pressed against the first row of
        // tiles, Cancel and Save read as part of the grid rather than as the frame around
        // it.
        .padding(.bottom, 4)
        .transition(.blurReplace)
    }

    /// Everything that is not already on the panel, to be added from the bottom.
    private var addStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Divider().overlay(LocktyColors.separator.opacity(0.45))

            HStack {
                Text("Add actions")
                    .font(.system(.subheadline, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.primaryText)

                Spacer(minLength: 0)

                Text(slotsText)
                    .font(.system(.footnote, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.tertiaryText)
                    .contentTransition(.numericText())
            }
            .padding(.horizontal, 18)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .top, spacing: 12) {
                    ForEach(available) { action in
                        addTile(action)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.bottom, 16)
            }
            .scrollClipDisabled()
        }
        .transition(.blurReplace)
    }

    private var slotsText: String {
        switch shown.remainingSlots {
        case 0: "Full"
        case 1: "1 slot left"
        default: "\(set.remainingSlots) slots left"
        }
    }

    /// What could still be added: every kind not already on the panel, plus one tile per
    /// objective that is not being logged from here yet.
    private var available: [QuickAction] {
        var result: [QuickAction] = QuickAction.Kind.allCases
            .filter { $0 != .logObjective && $0 != .startRoutine }
            .map { QuickAction(kind: $0) }
            .filter { !shown.contains($0) }

        // One tile per mode and one per objective: "start a mode" as a category is a menu
        // you still have to read, and the point of the panel is to press the thing itself.
        result += routines
            .map { QuickAction(kind: .startRoutine, routineID: $0.id) }
            .filter { !shown.contains($0) }

        result += objectives
            .map { QuickAction(kind: .logObjective, objectiveID: $0.id) }
            .filter { !shown.contains($0) }

        return result
    }

    // MARK: - Tiles

    /// One tile, and what a press of it means.
    ///
    /// The gestures are split by mode rather than layered, and that is the whole of why
    /// holding a tile did nothing: `draggable` installs a press-and-hold of its own to
    /// start a drag, and two long presses on one view is a race the drag wins every time.
    /// So a tile is draggable only while the panel is being arranged, and only while it is
    /// *not* being arranged does holding it start arranging.
    @ViewBuilder
    private func tile(_ action: QuickAction) -> some View {
        if mode.isEditing {
            tileFace(action)
                .draggable(action.id) {
                    Image(systemName: symbol(for: action))
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(tint(for: action))
                        .frame(width: 56, height: 56)
                        .background {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(LocktyColors.ink(0.10))
                        }
                }
                .dropDestination(for: String.self) { items, _ in
                    guard let draft = mode.draft,
                          let moved = items.first,
                          let source = draft.actions.first(where: { $0.id == moved }),
                          let index = draft.actions.firstIndex(where: { $0.id == action.id })
                    else { return false }

                    edit { $0.move(source, to: index) }
                    return true
                }
        } else {
            tileFace(action)
                // Simultaneous, because the tile is a `Button` and a button claims the
                // press for itself.
                .simultaneousGesture(
                    LongPressGesture(minimumDuration: 0.45)
                        .onEnded { _ in
                            // The arrangement starts as a copy of what is saved.
                            withAnimation(.smooth(duration: 0.32)) { mode = .editing(set) }
                        }
                )
        }
    }

    private func tileFace(_ action: QuickAction) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topLeading) {
                Button {
                    guard !mode.isEditing else { return }
                    onRun(action)
                } label: {
                    Image(systemName: symbol(for: action))
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(tint(for: action))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background { tileSurface(action) }
                        .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                }
                .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 18, style: .continuous)))
                .tappable()

                if mode.isEditing {
                    Button {
                        edit { $0.remove(action) }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(LocktyColors.onPrimary)
                            .frame(width: 24, height: 24)
                            .background { Circle().fill(LocktyColors.primaryText) }
                            .contentShape(Circle())
                    }
                    .buttonStyle(.locktyInteractive(shape: Circle()))
                    .tappable()
                    .offset(x: -8, y: -8)
                    .transition(.blurReplace)
                }
            }

            Text(title(for: action))
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    /// The tile's body, on glass.
    ///
    /// Nothing opaque here. The panel is a piece of glass over whatever screen is behind
    /// it, and a tile painted with a card colour fights it: white on near-white glass is
    /// an invisible button in light mode, which is exactly what these had become. What a
    /// tile is drawn in is its own colour where it has one, and `ink` where it does not --
    /// black at six per cent on a pale panel, white at six on a dark one, so it is a shade
    /// away from its ground either way rather than a colour that only works in the dark.
    private func tileSurface(_ action: QuickAction) -> some View {
        let shape = RoundedRectangle(cornerRadius: 18, style: .continuous)
        let glow = glow(for: action)
        let isDark = colorScheme == .dark
        let accent = accent(for: action)

        return ZStack {
            // The bloom. Added light in the dark, laid over in the light: adding light to
            // something already pale does nothing at all.
            if let accent, glow > 0 {
                shape
                    .fill(accent)
                    .blur(radius: 10)
                    .opacity((isDark ? 0.35 : 0.20) * glow)
                    .blendMode(isDark ? .plusLighter : .normal)
                    .padding(-1)
            }

            if let accent {
                shape.fill(accent.opacity(isDark ? 0.22 : 0.18))
            } else {
                shape.fill(LocktyColors.ink(0.06))
            }

            // A hairline, so the tile has an edge on glass rather than only a fill.
            shape.stroke(LocktyColors.ink(isDark ? 0.10 : 0.08), lineWidth: 1)
        }
        .animation(.smooth(duration: 0.35), value: glow)
    }

    private func addTile(_ action: QuickAction) -> some View {
        VStack(spacing: 6) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: symbol(for: action))
                    .font(.system(size: 18, weight: .regular))
                    .foregroundStyle(tint(for: action))
                    .frame(width: 62, height: 52)
                    .background { tileSurface(action) }

                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(LocktyColors.onPrimary)
                    .frame(width: 22, height: 22)
                    .background { Circle().fill(LocktyColors.primaryText) }
                    .offset(x: 7, y: -7)
            }

            Text(title(for: action))
                .font(.system(size: 10, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: 70)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            guard shown.remainingSlots > 0 else { return }
            edit { $0.add(action) }
        }
        .opacity(shown.remainingSlots > 0 ? 1 : 0.4)
    }

    // MARK: - What a tile says

    private func objective(_ action: QuickAction) -> Objective? {
        guard let id = action.objectiveID else { return nil }
        return objectives.first { $0.id == id }
    }

    private func routine(_ action: QuickAction) -> Routine? {
        guard let id = action.routineID else { return nil }
        return routines.first { $0.id == id }
    }

    /// A tile about something is called what that thing is called. "Start a mode" tells
    /// you what the button does; "Deep work" tells you what is about to happen.
    private func title(for action: QuickAction) -> String {
        if let objective = objective(action) { return objective.name }
        if let routine = routine(action) { return routine.name }
        return action.kind.title
    }

    private func symbol(for action: QuickAction) -> String {
        if let objective = objective(action) { return objective.symbolName }
        if let routine = routine(action), let icon = routine.icon, !icon.isEmpty { return icon }
        return action.kind.symbolName
    }

    /// The colour a tile is in.
    ///
    /// A mode's tile wears the mode's colour and an objective's wears the objective's --
    /// they are that thing, sitting on the panel, and recognising it by its colour is
    /// faster than reading nine labels. The doors stay in the plain foreground: a door has
    /// no colour of its own because it is not about anything in particular.
    private func accent(for action: QuickAction) -> Color? {
        if let objective = objective(action) { return LocktyColors.routine(objective.color) }
        if let routine = routine(action) { return LocktyColors.routine(routine.color) }
        return nil
    }

    private func tint(for action: QuickAction) -> Color {
        accent(for: action) ?? LocktyColors.primaryText
    }

    /// How lit the tile's aura is. An objective already done burns at full; everything
    /// else keeps the faint glow that says it has a colour at all.
    private func glow(for action: QuickAction) -> Double {
        guard accent(for: action) != nil else { return 0 }
        if let objective = objective(action), isComplete(objective) { return 1 }
        return 0.45
    }
}
