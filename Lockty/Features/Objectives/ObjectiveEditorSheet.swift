import SwiftUI

/// An objective: read on one screen, changed on another, named on a third.
///
/// The same shape as a rule or a routine, and for the same reason -- opening one used to
/// drop you straight into its form, so reading "eight glasses a day" meant reading a page
/// of controls. What an objective *is* is a ring, a name and a number; the settings sit
/// one tap behind the pencil and the name one further, exactly where they are on a rule.
///
/// A new objective has nothing to read, so it opens on the form.
struct ObjectiveEditorSheet: View {
    let objective: Objective?
    /// Where the progress is read and written.
    ///
    /// Passed in rather than made here, so the plus and minus on the preview move the
    /// same figure the card and the page are already showing.
    @ObservedObject var viewModel: ObjectivesViewModel
    let onSave: (Objective) -> Void
    let onDelete: (Objective) -> Void

    private enum Screen: Hashable {
        case reading
        case form
        /// The grid of ready-made objectives.
        case type
        /// Which app an app-time objective is about.
        case app
        case naming
        case symbol
    }

    @State private var screen: Screen
    /// Which way the last move went, so the screens leave the way they arrived.
    @State private var isGoingBack = false

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var symbolName: String
    @State private var target: Double
    @State private var step: Double
    @State private var unit: String
    @State private var period: ObjectivePeriod
    @State private var source: ObjectiveSource
    @State private var isChoosingPeriod = false
    @State private var isShowingIconPicker = false
    @State private var isShowingColorPicker = false
    @State private var color: RoutineColor
    @State private var appID: AppIdentity.ID?
    @State private var appName: String?
    /// Every app seen in the last month, for the app-time picker. Read once, when that
    /// screen is first opened -- it is a month of cached files.
    @State private var knownApps: [UsageBreakdownApp] = []
    @FocusState private var isNameFocused: Bool

    /// The glyphs on offer. A short list on purpose: an objective is read at a glance in
    /// a row, and every symbol in the system is a search field nobody wants.
    private static let symbols = [
        "target", "drop.fill", "figure.walk", "book.fill", "dumbbell.fill",
        "leaf.fill", "bed.double.fill", "fork.knife", "pencil", "guitars.fill",
        "cup.and.saucer.fill", "heart.fill", "sun.max.fill", "moon.fill", "brain.head.profile"
    ]

    init(
        objective: Objective?,
        viewModel: ObjectivesViewModel,
        onSave: @escaping (Objective) -> Void,
        onDelete: @escaping (Objective) -> Void
    ) {
        self.objective = objective
        self.viewModel = viewModel
        self.onSave = onSave
        self.onDelete = onDelete
        // A new objective starts at its name, its glyph and its colour -- the three
        // things that make it a thing at all -- and carries on to what kind it is. The
        // form is where you land afterwards, not where you begin.
        _screen = State(initialValue: objective == nil ? .naming : .reading)
        _name = State(initialValue: objective?.name ?? "")
        _symbolName = State(initialValue: objective?.symbolName ?? "target")
        _target = State(initialValue: objective?.target ?? 1)
        _step = State(initialValue: objective?.step ?? 1)
        _unit = State(initialValue: objective?.unit ?? "")
        _period = State(initialValue: objective?.period ?? .daily)
        _source = State(initialValue: objective?.source ?? .manual)
        _color = State(initialValue: objective?.color ?? .mint)
        _appID = State(initialValue: objective?.appID)
        _appName = State(initialValue: objective?.appName)
    }

    private var isSavable: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        // An app-time objective without an app is a sentence with the subject missing.
        return source != .appUsage || appID != nil
    }

    var body: some View {
        LocktyDynamicSheet {
            // The screens are swapped in place, each in its own geometry group, so the
            // sheet resizing and the content changing move together rather than the
            // transition being measured mid-flight.
            ZStack {
                switch screen {
                case .reading: preview.geometryGroup().transition(screenTransition)
                case .form: form.geometryGroup().transition(screenTransition)
                case .type: typeScreen.geometryGroup().transition(screenTransition)
                case .app: appScreen.geometryGroup().transition(screenTransition)
                case .naming: namingScreen.geometryGroup().transition(screenTransition)
                case .symbol: symbolScreen.geometryGroup().transition(screenTransition)
                }
            }
            .geometryGroup()
            .frame(maxWidth: .infinity, alignment: .top)
            // The objective's colour, behind everything -- the same bloom a routine's
            // sheet wears. The sheet was the one surface still ignoring what was picked,
            // so choosing a colour changed five small things and none of the screen.
            .background(alignment: .top) { colourAura }
            // The id carries everything the bar draws from, not just which screen it is.
            //
            // The chrome is captured as a snapshot and only re-taken when this id changes
            // -- so a button whose enabled-ness comes from `@State` was frozen at whatever
            // it was when the screen arrived. That is why the check on the name screen
            // never came alive however much you typed: it had been captured while the
            // name was empty, and nothing told it otherwise.
            .locktyDynamicSheetChrome(
                id: "objective-\(screen)-\(isSavable)-\(name.isEmpty)"
            ) {
                chromeTitle
            } leading: {
                chromeLeading
            } trailing: {
                chromeTrailing
            }
        }
    }

    /// The objective's colour, behind whichever screen is showing.
    ///
    /// The same bloom a routine's sheet has, written the same way: one wide ellipse from
    /// the top, blurred until it is light rather than a shape. It is the one thing on the
    /// sheet that is purely this objective's -- everything else is a field -- and it is
    /// what makes two objectives feel unlike each other at a glance.
    private var colourAura: some View {
        Ellipse()
            .fill(LocktyColors.routine(color))
            .frame(height: 260)
            .blur(radius: 90)
            .opacity(0.26)
            .offset(y: -60)
            .allowsHitTesting(false)
            .animation(.smooth(duration: 0.4), value: color)
    }

    // MARK: - Chrome

    @ViewBuilder
    private var chromeTitle: some View {
        switch screen {
        case .reading:
            // Nothing: the ring and the name are right underneath, at full size.
            EmptyView()
        case .form:
            chromeText(objective == nil ? "New objective" : name)
        case .type:
            chromeText("Type")
        case .app:
            chromeText("Which app")
        case .naming:
            chromeText("Name")
        case .symbol:
            chromeText("Icon")
        }
    }

    private func chromeText(_ text: String) -> some View {
        Text(text)
            .font(.system(.title3, design: .default, weight: .regular))
            .foregroundStyle(LocktyColors.primaryText)
            .lineLimit(1)
    }

    private var chromeLeading: some View {
        let isRoot = screen == .reading || (objective == nil && screen == .naming)

        return LocktyDynamicSheetBarButton(action: goBack) {
            Image(systemName: isRoot ? "xmark" : "chevron.left")
                .font(.system(size: 15, weight: .medium))
        }
    }

    @ViewBuilder
    private var chromeTrailing: some View {
        switch screen {
        case .reading:
            // Delete and edit together, as on a rule: both are things you do *to* the
            // objective rather than with it.
            HStack(spacing: LocktySpacing.sm) {
                if let objective {
                    LocktyDynamicSheetBarButton(action: {
                        onDelete(objective)
                        dismiss()
                    }) {
                        Image(systemName: "trash")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(LocktyColors.error)
                    }
                }

                LocktyDynamicSheetBarButton(action: { move(to: .form) }) {
                    Image(systemName: "pencil")
                        .font(.system(size: 15, weight: .medium))
                }
            }
        case .form:
            // From the form the pencil opens the name, which is the only thing left to
            // open -- the same two meanings the pencil has on a rule.
            LocktyDynamicSheetBarButton(action: { move(to: .naming) }) {
                Image(systemName: "pencil")
                    .font(.system(size: 15, weight: .medium))
            }
        case .naming:
            // A check, whichever way it goes. The glyph answers the screen -- "this name
            // is right" -- rather than announcing where the sheet is about to travel.
            LocktyDynamicSheetBarButton(action: {
                // Checked here as well as in the button's state: a name typed and then
                // cleared leaves the bar a beat behind, and a tap in that beat should do
                // nothing rather than carry an objective forward with no name.
                guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                move(to: objective == nil ? .type : .form)
            }) {
                Image(systemName: "checkmark")
                    .font(.system(size: 18, weight: .medium))
            }
            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        case .type, .app, .symbol:
            Color.clear.frame(width: 44, height: 44)
        }
    }

    private func goBack() {
        switch screen {
        case .reading:
            dismiss()
        case .form:
            if objective == nil { move(to: .type) } else { move(to: .reading) }
        case .naming:
            if objective == nil { dismiss() } else { move(to: .form) }
        case .type:
            if objective == nil { move(to: .naming) } else { move(to: .form) }
        case .app, .symbol:
            move(to: .form)
        }
    }

    /// Going in slides from the right; coming back slides from the left. The same
    /// transition the routine editor uses, because it is the same fake navigation: there
    /// is no stack here, only one screen replacing another, and the movement is what says
    /// which direction you went.
    private var screenTransition: AnyTransition {
        .asymmetric(
            insertion: .move(edge: isGoingBack ? .leading : .trailing)
                .combined(with: AnyTransition(.blurReplace))
                .combined(with: .opacity),
            removal: .move(edge: isGoingBack ? .trailing : .leading)
                .combined(with: AnyTransition(.blurReplace))
                .combined(with: .opacity)
        )
    }

    private func move(to next: Screen) {
        // Reading is the root, so anything arriving at it is a step back -- and so is
        // walking the creation flow in reverse.
        isGoingBack = next == .reading
            || (screen == .type && next == .naming)
            || (screen != .reading && screen != .type && next == .form)
        withAnimation(.snappy(duration: 0.4, extraBounce: 0.02)) { screen = next }
    }

    /// The objective as the sheet currently has it, for the preview to read.
    private var draft: Objective {
        Objective(
            id: objective?.id ?? UUID(),
            name: name,
            symbolName: symbolName,
            target: target,
            step: step,
            unit: unit,
            period: period,
            color: color,
            source: source,
            appID: appID,
            appName: appName,
            createdAt: objective?.createdAt ?? Date(),
            updatedAt: Date()
        )
    }

    // MARK: - Reading

    /// The objective itself: its ring, its name, and the number.
    ///
    /// For one you count yourself the number *is* the control -- plus and minus add and
    /// take back a step, and the ring fills as they do, which is the whole of logging a
    /// glass of water. For one Health counts there are no buttons: the figure is a
    /// reading, and a button that changed it would be writing down something you did not
    /// do.
    private var preview: some View {
        VStack(spacing: LocktySpacing.xl) {
            ObjectiveRing(
                symbolName: symbolName,
                fraction: viewModel.fraction(of: draft),
                isComplete: viewModel.isComplete(draft),
                // The objective's own colour, here as everywhere else it appears. This
                // ring was left on the default mint, so an objective picked in orange was
                // orange on Today and green in the sheet that set it.
                color: color,
                side: 96,
                lineWidth: 5
            )

            VStack(spacing: 2) {
                Text(name)
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(LocktyColors.primaryText)
                    .multilineTextAlignment(.center)

                Text("\(period.title) · \(source.title)")
                    .font(.system(.subheadline, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)
            }

            if source.isReadFromHealth {
                VStack(spacing: LocktySpacing.sm) {
                    Text(draft.format(viewModel.value(of: draft)))
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(LocktyColors.primaryText)
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .animation(.snappy(duration: 0.22), value: viewModel.value(of: draft))

                    Text("of \(draft.format(target)), read from Health")
                        .font(.system(.footnote, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                }
            } else if draft.isYesNo {
                // Two answers, one control. A stepper walking between nothing and one is
                // a switch that has been made to count.
                VStack(spacing: LocktySpacing.md) {
                    LocktySwitch(
                        isOn: Binding(
                            get: { viewModel.isComplete(draft) },
                            set: { isOn in
                                if isOn { viewModel.complete(draft) } else { viewModel.reset(draft) }
                            }
                        )
                    )
                    .scaleEffect(1.2)

                    Text("Done \(period.currentTitle)?")
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)
                }
            } else {
                VStack(spacing: LocktySpacing.lg) {
                    LocktyBigStepper(
                        value: Binding(
                            get: { Int(viewModel.value(of: draft).rounded()) },
                            set: { newValue in
                                let current = Int(viewModel.value(of: draft).rounded())
                                if newValue > current {
                                    viewModel.advance(draft)
                                } else if newValue < current {
                                    viewModel.stepBack(draft)
                                }
                            }
                        ),
                        values: progressValues,
                        format: { draft.format(Double($0)) },
                        caption: "of \(draft.format(target)) \(period.currentTitle)"
                    )

                    // Straight to the target, for the objective you did all at once and
                    // are not going to tap out eight times. Held rather than tapped: it
                    // is a claim about the whole period, not a step.
                    if !viewModel.isComplete(draft) {
                        LocktyHoldButton(
                            title: "Hold to mark as done",
                            systemImage: "checkmark",
                            tint: LocktyColors.routine(color)
                        ) {
                            viewModel.complete(draft)
                        }
                    } else {
                        Button {
                            viewModel.reset(draft)
                        } label: {
                            HStack(spacing: LocktySpacing.sm) {
                                Image(systemName: "arrow.uturn.backward")
                                    .font(.system(size: 15, weight: .medium))

                                Text("Start it again")
                                    .font(.system(.subheadline, design: .default, weight: .semibold))
                            }
                            .foregroundStyle(LocktyColors.secondaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 52)
                            .contentShape(Capsule(style: .continuous))
                        }
                        .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
                        .tappable()
                    }
                }
            }
            // Out of the sheet, as asked. The sheet is where an objective is set and
            // logged; how the fortnight went is a reading, and there is a chart for that
            // on the objectives page under the pill. Kept, not deleted.
//            history
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.xl)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.md))
        .frame(maxWidth: .infinity)
    }

    /// This objective, day by day.
    ///
    /// The figure at the top is the period; this is how it was reached -- which Monday
    /// had the water and which one did not. Only drawn once there is something behind it:
    /// a flat line at nothing is a chart saying "no data" in the most elaborate way
    /// available.
    @ViewBuilder
    private var history: some View {
        let values = viewModel.dailyValues(of: draft, days: 14)

        if values.contains(where: { $0.value > 0 }) {
            VStack(alignment: .leading, spacing: LocktySpacing.md) {
                Divider()
                    .overlay(LocktyColors.separator.opacity(0.45))

                Text("THE FORTNIGHT")
                    .locktyEyebrow()

                LocktyTrendChart(
                    points: historyPoints(values),
                    tint: LocktyColors.routine(color),
                    format: { draft.format($0) },
                    height: 140
                )
            }
            .padding(.top, LocktySpacing.md)
        }
    }

    private func historyPoints(_ values: [(date: Date, value: Double)]) -> [LocktyTrendChart.Point] {
        let named = Set([0, values.count / 2, values.count - 1])

        return values.enumerated().map { index, entry in
            LocktyTrendChart.Point(
                id: index,
                value: entry.value,
                label: named.contains(index) ? Self.weekdayFormatter.string(from: entry.date) : nil,
                caption: Self.captionFormatter.string(from: entry.date)
            )
        }
    }

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()

    private static let captionFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE d MMM")
        return formatter
    }()

    /// The values the preview's stepper walks: nothing, then one step at a time to the
    /// target, and one past it for the day you go over.
    /// Every value the stepper can walk to, up to twice the target.
    ///
    /// Past the target on purpose. Fifteen glasses is what you meant to drink, not the
    /// most you are allowed to write down -- and a stepper that stops one step past the
    /// goal has no way to say you had twenty.
    private var progressValues: [Int] {
        let stepSize = max(Int(step.rounded()), 1)
        let goal = max(Int(target.rounded()), stepSize)
        return Array(stride(from: 0, through: goal * 2, by: stepSize))
    }

    // MARK: - Type

    /// What kind of objective this is, as a grid.
    ///
    /// A screen rather than a menu because these are not settings of one thing -- each
    /// one is a whole objective ready to go, with its glyph, its unit and a target that
    /// makes sense. Two columns: the tiles have to be big enough to be read at a glance,
    /// and there are seven of them.
    private var typeScreen: some View {
        ScrollView(.vertical, showsIndicators: false) {
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: LocktySpacing.md), count: 2),
                spacing: LocktySpacing.md
            ) {
                ForEach(ObjectivePreset.all) { preset in
                    Button { apply(preset) } label: {
                        VStack(alignment: .leading, spacing: LocktySpacing.sm) {
                            Image(systemName: preset.symbolName)
                                .font(.system(size: 22, weight: .regular))
                                .foregroundStyle(LocktyColors.primaryText)

                            Spacer(minLength: 0)

                            Text(preset.title)
                                .font(.system(.subheadline, design: .default, weight: .semibold))
                                .foregroundStyle(LocktyColors.primaryText)

                            Text(preset.detail)
                                .font(.system(.footnote, design: .default, weight: .regular))
                                .foregroundStyle(LocktyColors.secondaryText)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .frame(height: 118)
                        .padding(LocktySpacing.lg)
                        .locktyCardBackground(cornerRadius: 24)
                    }
                    .buttonStyle(.locktyInteractive(brighten: true))
                    .tappable()
                }
            }
            .padding(.horizontal, LocktySpacing.screenInset)
            .padding(.vertical, LocktySpacing.lg)
        }
        // Eight tiles do not fit a sheet sized to its content, so this screen asks for a
        // tall one and scrolls inside it.
        //
        // Nothing caps the height here any more. A `maxHeight` of its own on top of the
        // size it asked for is two answers to the same question: the sheet was built tall
        // and the grid was held to 520 inside it, which is the odd cropped scroll with
        // dead space under it.
        .locktyDynamicSheetSizes([.large])
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            // The face of it, centred: the glyph is what every other screen shows, and
            // beside a text field it read as a button attached to the name.
            VStack(spacing: LocktySpacing.md) {
                Button { move(to: .symbol) } label: {
                    ObjectiveRing(symbolName: symbolName, fraction: 1, isComplete: false, color: color, side: 76, lineWidth: 3)
                }
                .buttonStyle(.locktyInteractive(brighten: true))
                .tappable()

                Button { move(to: .naming) } label: {
                    Text(name.isEmpty ? "Name it" : name)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(name.isEmpty ? LocktyColors.tertiaryText : LocktyColors.primaryText)
                        .multilineTextAlignment(.center)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.locktyInteractive(brighten: true))
                .tappable()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, LocktySpacing.md)

            // How much counts as done, at the size of the decision it is rather than as
            // a caption between two small circles in a list of rows.
            //
            // Said in words above it, because a large number on its own is not a
            // question: "8" tells you nothing, "how much counts as done -- 8 glasses a
            // day" tells you what you are setting.
            if !draft.isYesNo {
                VStack(spacing: LocktySpacing.sm) {
                    Text("How much counts as done?")
                        .font(.system(.subheadline, design: .default, weight: .regular))
                        .foregroundStyle(LocktyColors.secondaryText)

                    LocktyBigStepper(
                        value: targetBinding,
                        values: targetValues,
                        format: { formatTarget($0) },
                        caption: targetCaption
                    )
                }
                .padding(.bottom, LocktySpacing.sm)
            }

            VStack(spacing: 0) {
                Button { move(to: .type) } label: {
                    HStack(spacing: LocktySpacing.md) {
                        Text("Type")
                            .font(.system(.body, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.primaryText)

                        Spacer(minLength: LocktySpacing.sm)

                        Text(source.title)
                            .font(.system(.body, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.secondaryText)

                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(LocktyColors.tertiaryText)
                    }
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.locktyInteractive(brighten: true))
                .tappable()

                if source == .appUsage {
                    divider

                    Button { move(to: .app) } label: {
                        HStack(spacing: LocktySpacing.md) {
                            Text("App")
                                .font(.system(.body, design: .default, weight: .regular))
                                .foregroundStyle(LocktyColors.primaryText)

                            Spacer(minLength: LocktySpacing.sm)

                            Text(appName ?? "Choose")
                                .font(.system(.body, design: .default, weight: .regular))
                                .foregroundStyle(appName == nil ? LocktyColors.tertiaryText : LocktyColors.secondaryText)
                                .lineLimit(1)

                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(LocktyColors.tertiaryText)
                        }
                        .frame(minHeight: 56)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.locktyInteractive(brighten: true))
                    .tappable()
                }

                divider

                periodRow

                if source == .manual, !draft.isYesNo {
                    divider

                    LocktyCountRow(
                        title: "One tap adds",
                        value: Binding(get: { Int(step) }, set: { step = Double($0) }),
                        range: 1...50,
                        suffix: unit
                    )
                }

                // Always, for anything counted by hand -- including one that is a yes or a
                // no right now. What makes an objective a yes or a no is having no unit
                // and a target of one, so hiding the unit field from it was hiding the
                // only way out: "Custom" arrived as a yes-or-no and could never be given
                // anything to count.
                if source == .manual {
                    divider

                    HStack(spacing: LocktySpacing.md) {
                        Text("Unit")
                            .font(.system(.body, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.primaryText)

                        Spacer(minLength: LocktySpacing.sm)

                        TextField("glasses, min, pages", text: $unit)
                            .multilineTextAlignment(.trailing)
                            .font(.system(.body, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.secondaryText)
                            .textInputAutocapitalization(.never)
                            .frame(maxWidth: 160)
                    }
                    .frame(minHeight: 56)
                }

            }
            .padding(.horizontal, LocktySpacing.cardInset)
            .locktyCardBackground(cornerRadius: 26)

            LocktyHoldButton(title: objective == nil ? "Hold to create" : "Hold to save") {
                guard isSavable else { return }
                onSave(draft)
                dismiss()
            }
            .disabled(!isSavable)
            .opacity(isSavable ? 1 : 0.5)
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.md)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.md))
    }

    /// How often it comes round. A menu on the value, not on the row: the menu opens out
    /// of the thing it is about, and the label on the left is a label.
    private var periodRow: some View {
        HStack(spacing: LocktySpacing.md) {
            Text("Repeats")
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

            Spacer(minLength: LocktySpacing.sm)

            HStack(spacing: LocktySpacing.sm) {
                Text(period.title)
                    .font(.system(.body, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.secondaryText)

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(LocktyColors.tertiaryText)
            }
            .contentShape(Rectangle())
            .onTapGesture { isChoosingPeriod = true }
            .locktyMenu(isPresented: $isChoosingPeriod) {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(ObjectivePeriod.allCases) { option in
                        LocktyMenuItem(title: option.title, isSelected: option == period) {
                            period = option
                            isChoosingPeriod = false
                        }
                    }
                }
                .padding(.vertical, LocktySpacing.sm)
                .padding(.horizontal, LocktySpacing.xs)
                .frame(width: 210)
            }
        }
        .frame(minHeight: 56)
    }

    /// Which app the objective is about.
    ///
    /// The apps Screen Time has actually reported, not a picker: this objective does not
    /// block anything, so it needs no authorization to choose with -- and the list of
    /// apps you have used is a better list than the whole phone anyway.
    private var appScreen: some View {
        VStack(spacing: 0) {
            ForEach(Array(knownApps.prefix(40).enumerated()), id: \.element.id) { index, app in
                if index > 0 {
                    Divider().overlay(LocktyColors.separator.opacity(0.45))
                }

                Button {
                    appID = app.app.id
                    appName = app.app.displayName
                    if name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        name = "Less \(app.app.displayName)"
                    }
                    move(to: .form)
                } label: {
                    HStack(spacing: LocktySpacing.md) {
                        AppIconView(
                            source: app.app.iconSource,
                            applicationToken: app.app.applicationToken,
                            fallbackSystemImage: app.app.iconSystemName,
                            size: 34,
                            chrome: .plain
                        )

                        Text(app.app.displayName)
                            .font(.system(.body, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.primaryText)
                            .lineLimit(1)

                        Spacer(minLength: LocktySpacing.sm)

                        if app.app.id == appID {
                            Image(systemName: "checkmark")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(LocktyColors.routine(color))
                        }
                    }
                    .frame(minHeight: 56)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.locktyInteractive(brighten: true))
                .tappable()
            }
        }
        .padding(.horizontal, LocktySpacing.cardInset)
        .locktyCardBackground(cornerRadius: 26)
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.vertical, LocktySpacing.lg)
        .task {
            guard knownApps.isEmpty else { return }
            let builder = UsageBreakdownBuilder()
            knownApps = await Task.detached(priority: .userInitiated) {
                builder.knownApps(classifications: [:])
            }.value
        }
    }

    /// The name, on a screen of its own -- reached from the pencil, exactly as a rule's is.
    ///
    /// The field and nothing else. The glyph is chosen on the form, from the ring that
    /// stands at the top of it; putting it here as well made a screen called "Name" into
    /// a screen with two decisions on it.
    private var namingScreen: some View {
        VStack(spacing: LocktySpacing.lg) {
            HStack(spacing: LocktySpacing.sm) {
                TextField("Drink 8 glasses of water", text: $name)
                    .font(LocktyTypography.body)
                    .foregroundStyle(LocktyColors.primaryText)
                    .textInputAutocapitalization(.sentences)
                    .focused($isNameFocused)
                    .padding(.horizontal, LocktySpacing.lg)
                    .padding(.vertical, LocktySpacing.md)
                    .background(Capsule(style: .continuous).fill(LocktyColors.elevatedBackground))

                // The glyph beside the name, not inside the field: it is the other half
                // of what identifies the objective, and it opens its own popover.
                Button { isShowingIconPicker = true } label: {
                    Image(systemName: symbolName)
                        .font(.system(size: 18, weight: .light))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(LocktyColors.routine(color).opacity(0.24)))
                }
                .buttonStyle(.locktyInteractive(shape: Circle()))
                .tappable()
                .locktyMenu(isPresented: $isShowingIconPicker) {
                    RoutineIconPickerSheet(selectedIcon: $symbolName)
                }

                // The colour, picked the same way and at the same size.
                Button { isShowingColorPicker = true } label: {
                    Circle()
                        .fill(LocktyColors.routine(color))
                        .frame(width: 24, height: 24)
                        .frame(width: 52, height: 52)
                        .background(Circle().fill(LocktyColors.routine(color).opacity(0.24)))
                }
                .buttonStyle(.locktyInteractive(shape: Circle()))
                .tappable()
                .locktyMenu(isPresented: $isShowingColorPicker) {
                    RoutineColorPickerPopover(selectedColor: $color)
                }
            }
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.top, LocktySpacing.xl)
        .padding(.bottom, LocktySpacing.sheetBottom(forTop: LocktySpacing.md))
        .frame(maxWidth: .infinity)
        .task { isNameFocused = true }
    }

    private var symbolScreen: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: LocktySpacing.md), count: 5),
            spacing: LocktySpacing.md
        ) {
            ForEach(Self.symbols, id: \.self) { symbol in
                Button {
                    symbolName = symbol
                    move(to: .form)
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(LocktyColors.primaryText)
                        .frame(width: 54, height: 54)
                        .background {
                            Circle().fill(
                                symbol == symbolName
                                    ? LocktyColors.routine(color).opacity(0.24)
                                    : LocktyColors.ink(0.06)
                            )
                        }
                }
                .buttonStyle(.locktyInteractive(shape: Circle()))
                .tappable()
            }
        }
        .padding(.horizontal, LocktySpacing.screenInset)
        .padding(.vertical, LocktySpacing.lg)
    }

    /// Taking a ready-made objective: everything it knows about itself comes with it.
    ///
    /// The name only when there is not one already -- somebody editing "Morning water"
    /// and switching it to Steps has not asked to have their name thrown away.
    private func apply(_ preset: ObjectivePreset) {
        source = preset.source
        if preset.source != .appUsage { appID = nil; appName = nil }
        symbolName = preset.symbolName
        unit = preset.unit
        step = preset.step
        target = preset.target
        if preset.id != "custom", name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            name = preset.title
        }
        if objective == nil { period = preset.period }
        // An app-time objective is not an objective until it names an app, so choosing
        // one leads straight to the list rather than back to a form with a gap in it.
        move(to: preset.source == .appUsage && appID == nil ? .app : .form)
    }

    /// The target as whole numbers the stepper can walk.
    ///
    /// Sleep counts in minutes behind the scenes so half hours are reachable -- seven and
    /// a half is a normal night, and a control that could only offer seven or eight would
    /// be asking people to round their sleep to suit it.
    private var targetBinding: Binding<Int> {
        Binding(
            get: { source == .sleep ? Int((target * 60).rounded()) : Int(target.rounded()) },
            set: { target = source == .sleep ? Double($0) / 60 : Double($0) }
        )
    }

    private var targetValues: [Int] {
        switch source {
        // In hundreds, which is how step counts are actually thought about.
        case .steps: Array(stride(from: 1000, through: 40000, by: 100))
        case .sleep: Array(stride(from: 240, through: 720, by: 30))
        case .appUsage: Array(stride(from: 5, through: 240, by: 5))
        case .manual: Array(1...200)
        }
    }

    /// What the target is counted in, under the figure. "glasses a day", "steps a day",
    /// "sessions a week" -- the sentence the number belongs to.
    private var targetCaption: String {
        let every: String = switch period {
        case .daily: "a day"
        case .weekly: "a week"
        case .monthly: "a month"
        }

        switch source {
        case .steps: return "steps \(every)"
        case .sleep: return "asleep \(every)"
        case .appUsage: return "minutes \(every), at most"
        case .manual: return unit.isEmpty ? "times \(every)" : "\(unit) \(every)"
        }
    }

    private func formatTarget(_ value: Int) -> String {
        switch source {
        case .steps:
            return value.formatted(.number.grouping(.automatic))
        case .appUsage:
            return value < 60 ? "\(value) min" : "\(value / 60) h \(value % 60)"
        case .sleep:
            let hours = value / 60
            let minutes = value % 60
            return minutes == 0 ? "\(hours) h" : "\(hours) h \(minutes)"
        case .manual:
            return unit.isEmpty ? "\(value)" : "\(value) \(unit)"
        }
    }

    private var divider: some View {
        Divider().overlay(LocktyColors.separator.opacity(0.45))
    }
}
