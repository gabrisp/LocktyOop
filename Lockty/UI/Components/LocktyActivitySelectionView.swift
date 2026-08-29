import FamilyControls
import ManagedSettings
import SwiftUI

struct LocktyActivitySelectionRules: Hashable {
    enum PickerSeedStrategy: Hashable {
        case currentSelection
        case empty
    }

    var allowsApplications: Bool = true
    var allowsCategories: Bool = true
    var allowsWebDomains: Bool = true
    var maximumApplications: Int? = nil
    var maximumCategories: Int? = nil
    var maximumWebDomains: Int? = nil
    var pickerSeedStrategy: PickerSeedStrategy = .currentSelection

    static let library = LocktyActivitySelectionRules()
    static let routine = LocktyActivitySelectionRules(
        allowsApplications: true,
        allowsCategories: true,
        allowsWebDomains: false,
        maximumApplications: nil,
        maximumCategories: nil,
        maximumWebDomains: 0,
        pickerSeedStrategy: .currentSelection
    )
    static let pause = LocktyActivitySelectionRules(
        allowsApplications: true,
        allowsCategories: false,
        allowsWebDomains: false,
        maximumApplications: 1,
        maximumCategories: 0,
        maximumWebDomains: 0,
        pickerSeedStrategy: .empty
    )
}

private enum LocktyActivitySelectionViolation: Hashable {
    case applicationsNotAllowed
    case categoriesNotAllowed
    case websitesNotAllowed
    case tooManyApps(Int)
    case tooManyCategories(Int)
    case tooManyWebsites(Int)

    var message: String {
        switch self {
        case .applicationsNotAllowed:
            "Aquí no se pueden seleccionar apps."
        case .categoriesNotAllowed:
            "Aquí no se pueden seleccionar categorías."
        case .websitesNotAllowed:
            "Aquí no se pueden seleccionar sitios web."
        case .tooManyApps(let max):
            max == 1 ? "Solo se puede seleccionar 1 app." : "Solo se pueden seleccionar \(max) apps."
        case .tooManyCategories(let max):
            max == 1 ? "Solo se puede seleccionar 1 categoría." : "Solo se pueden seleccionar \(max) categorías."
        case .tooManyWebsites(let max):
            max == 1 ? "Solo se puede seleccionar 1 sitio web." : "Solo se pueden seleccionar \(max) sitios web."
        }
    }
}

private struct LocktySelectedActivityItem: Identifiable, Hashable {
    enum Kind: Hashable {
        case app(ManagedSettings.ApplicationToken)
        case category(ManagedSettings.ActivityCategoryToken)
        case webDomain(ManagedSettings.WebDomainToken)
    }

    let kind: Kind

    var id: String {
        switch kind {
        case .app(let token):
            "app-\(token.hashValue)"
        case .category(let token):
            "category-\(token.hashValue)"
        case .webDomain(let token):
            "web-\(token.hashValue)"
        }
    }
}

struct LocktyFeedbackOverlayState: Identifiable, Equatable {
    let id = UUID()
    let systemImage: String
    let title: String
    let subtitle: String
    let tint: Color
}

struct LocktyActivitySelectionView: View {
    let title: String
    let addLabel: String
    @Binding var selection: FamilyActivitySelection
    let rules: LocktyActivitySelectionRules
    let suggestions: [AppIdentity]
    var externalOverlay: Binding<LocktyFeedbackOverlayState?>
    let onClose: () -> Void
    let onDone: () -> Void

    @Namespace private var selectionNamespace
    @State private var isShowingOfficialPicker = false
    @State private var overlay: LocktyFeedbackOverlayState?

    init(
        title: String = "Seleccionadas",
        addLabel: String = "Añadir App o sitio web",
        selection: Binding<FamilyActivitySelection>,
        rules: LocktyActivitySelectionRules,
        suggestions: [AppIdentity] = [],
        externalOverlay: Binding<LocktyFeedbackOverlayState?> = .constant(nil),
        onClose: @escaping () -> Void,
        onDone: @escaping () -> Void
    ) {
        self.title = title
        self.addLabel = addLabel
        _selection = selection
        self.rules = rules
        self.suggestions = suggestions
        self.externalOverlay = externalOverlay
        self.onClose = onClose
        self.onDone = onDone
    }

    var body: some View {
        ZStack {
            Color.black
                .ignoresSafeArea()

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: LocktySpacing.xl) {
                    // No top bar of its own. This is pushed inside a navigation stack
                    // now, which already carries the way back, and the selection is
                    // written straight through the binding -- there is nothing for a
                    // confirm button to confirm.
                    addButton
                        .padding(.top, LocktySpacing.sm)

                    selectedItemsSection

                    if !visibleSuggestions.isEmpty {
                        suggestionsSection
                            .transition(.blurReplace.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, LocktySpacing.lg)
                .padding(.bottom, LocktySpacing.xxl)
            }

            if let activeOverlay {
                LocktyCenteredFeedbackOverlay(
                    state: activeOverlay
                )
                .transition(.blurReplace.combined(with: .scale(0.96)).combined(with: .opacity))
                .zIndex(5)
            }
        }
        .sheet(isPresented: $isShowingOfficialPicker) {
            LocktyOfficialActivityPickerSheet(
                selection: selection,
                rules: rules
            ) { newSelection in
                withAnimation(.smooth(duration: 0.28)) {
                    selection = newSelection
                }
            } onCancel: {
                withAnimation(.smooth(duration: 0.28)) {
                    isShowingOfficialPicker = false
                }
            } onViolation: { message in
                showOverlay(message: message)
            }
            .presentationDetents([.large])
            .presentationBackground(.clear)
        }
        .task(id: activeOverlay?.id) {
            guard activeOverlay != nil else { return }
            try? await Task.sleep(for: .seconds(1.6))
            guard !Task.isCancelled else { return }
            withAnimation(.smooth(duration: 0.22)) {
                self.overlay = nil
                self.externalOverlay.wrappedValue = nil
            }
        }
    }

    private var addButton: some View {
        Button {
            withAnimation(.smooth(duration: 0.28)) {
                isShowingOfficialPicker = true
            }
        } label: {
            HStack(spacing: LocktySpacing.lg) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.white.opacity(0.06))
                    .overlay {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(.white.opacity(0.08), lineWidth: 1)
                    }
                    .frame(width: 68, height: 68)
                    .overlay {
                        Image(systemName: "plus")
                            .font(.system(size: 30, weight: .regular))
                            .foregroundStyle(LocktyColors.primaryText)
                    }

                Text(addLabel)
                    .font(.system(.body, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 0)
            }
        }
        .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 16, style: .continuous)))
        .tappable()
    }

    private var selectedItemsSection: some View {
        VStack(spacing: 0) {
            ForEach(selectedItems) { item in
                selectedRow(item)
                    .transition(.blurReplace.combined(with: .opacity))

                if item.id != selectedItems.last?.id {
                    Divider()
                        .overlay(LocktyColors.separator.opacity(0.55))
                }
            }
        }
        .animation(.smooth(duration: 0.28), value: selectedItems.map(\.id))
    }

    @ViewBuilder
    private func selectedRow(_ item: LocktySelectedActivityItem) -> some View {
        HStack(spacing: LocktySpacing.lg) {
            selectedRowLabel(item)

            Spacer(minLength: 0)

            Button {
                remove(item)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 17, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(Color.white.opacity(0.09)))
            }
            .buttonStyle(.locktyInteractive(shape: Circle()))
        }
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func selectedRowLabel(_ item: LocktySelectedActivityItem) -> some View {
        switch item.kind {
        case .app(let token):
            let app = AppIdentity(token: token)
            HStack(spacing: LocktySpacing.md) {
                AppIconView(
                    source: app.iconSource,
                    applicationToken: token,
                    fallbackSystemImage: app.iconSystemName,
                    size: 38,
                    chrome: .plain
                )
                .matchedGeometryEffect(id: item.id, in: selectionNamespace)

                // Label(token) rather than a name we derive ourselves: the token is the
                // only thing that actually carries the app's real, localized name.
                Label(token)
                    .labelStyle(.titleOnly)
                    .font(.system(.body, design: .default, weight: .regular))
                    .foregroundStyle(LocktyColors.primaryText)
                    .lineLimit(1)
            }

        case .category(let token):
            Label(token)
                .labelStyle(.titleAndIcon)
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)

        case .webDomain(let token):
            Label(token)
                .labelStyle(.titleAndIcon)
                .font(.system(.body, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.primaryText)
        }
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: LocktySpacing.lg) {
            Text("Sugeridas")
                .font(.system(.headline, design: .default, weight: .semibold))
                .foregroundStyle(LocktyColors.primaryText)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: LocktySpacing.lg) {
                    ForEach(visibleSuggestions, id: \.id) { suggestion in
                        if let token = suggestion.applicationToken {
                            Button {
                                addSuggestedApp(token)
                            } label: {
                                ZStack {
                                    AppIconView(
                                        source: suggestion.iconSource,
                                        applicationToken: token,
                                        fallbackSystemImage: suggestion.iconSystemName,
                                        size: 72,
                                        chrome: .plain
                                    )
                                    .matchedGeometryEffect(id: "app-\(token.hashValue)", in: selectionNamespace)

                                    Image(systemName: "plus")
                                        .font(.system(size: 25, weight: .medium))
                                        .foregroundStyle(.white)
                                        .shadow(color: .black.opacity(0.28), radius: 8, y: 2)
                                }
                                .frame(width: 84, height: 84)
                            }
                            .buttonStyle(.locktyInteractive(brighten: true))
                            .transition(.blurReplace.combined(with: .scale(0.9)).combined(with: .opacity))
                        }
                    }
                }
                .padding(.horizontal, LocktySpacing.xs)
                .padding(.vertical, 2)
            }
            .scrollClipDisabled()
        }
        .animation(.smooth(duration: 0.28), value: visibleSuggestions.map(\.id))
    }

    private var visibleSuggestions: [AppIdentity] {
        var seen = Set<AppIdentity.ID>()
        return suggestions.filter { suggestion in
            guard let token = suggestion.applicationToken else { return false }
            guard seen.insert(suggestion.id).inserted else { return false }
            return !selection.applicationTokens.contains(token)
        }
    }

    private var selectedItems: [LocktySelectedActivityItem] {
        let apps = stableApplications(selection.applicationTokens).map { LocktySelectedActivityItem(kind: .app($0)) }
        let categories = stableCategories(selection.categoryTokens).map { LocktySelectedActivityItem(kind: .category($0)) }
        let domains = stableWebDomains(selection.webDomainTokens).map { LocktySelectedActivityItem(kind: .webDomain($0)) }
        return apps + categories + domains
    }

    private func addSuggestedApp(_ token: ManagedSettings.ApplicationToken) {
        var proposed = selection
        proposed.applicationTokens.insert(token)
        let result = normalizedSelection(proposed, previous: selection, rules: rules)

        withAnimation(.smooth(duration: 0.28)) {
            selection = result.selection
        }

        if let violation = result.violations.first {
            showOverlay(message: violation.message)
        }
    }

    private func remove(_ item: LocktySelectedActivityItem) {
        var proposed = selection

        switch item.kind {
        case .app(let token):
            proposed.applicationTokens.remove(token)
        case .category(let token):
            proposed.categoryTokens.remove(token)
        case .webDomain(let token):
            proposed.webDomainTokens.remove(token)
        }

        withAnimation(.smooth(duration: 0.28)) {
            selection = proposed
        }
    }

    private func showOverlay(message: String) {
        let state = LocktyFeedbackOverlayState(
            systemImage: "exclamationmark.triangle.fill",
            title: "Selección no válida",
            subtitle: message,
            tint: Color.red.opacity(0.5)
        )
        withAnimation(.smooth(duration: 0.22)) {
            overlay = state
            externalOverlay.wrappedValue = state
        }
    }

    private var activeOverlay: LocktyFeedbackOverlayState? {
        externalOverlay.wrappedValue ?? overlay
    }
}

private struct LocktyOfficialActivityPickerSheet: View {
    let selection: FamilyActivitySelection
    let rules: LocktyActivitySelectionRules
    let onSave: (FamilyActivitySelection) -> Void
    let onCancel: () -> Void
    let onViolation: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var draftSelection: FamilyActivitySelection

    init(
        selection: FamilyActivitySelection,
        rules: LocktyActivitySelectionRules,
        onSave: @escaping (FamilyActivitySelection) -> Void,
        onCancel: @escaping () -> Void,
        onViolation: @escaping (String) -> Void
    ) {
        self.selection = selection
        self.rules = rules
        self.onSave = onSave
        self.onCancel = onCancel
        self.onViolation = onViolation

        switch rules.pickerSeedStrategy {
        case .currentSelection:
            _draftSelection = State(initialValue: selection)
        case .empty:
            _draftSelection = State(initialValue: FamilyActivitySelection())
        }
    }

    /// How much of the picker's bottom edge is faded out. Short on purpose: it is a hint
    /// that the list continues, not a scrim.
    private let pickerFadeHeight: CGFloat = 28

    var body: some View {
        // One VStack: the picker takes the space that's left and the buttons sit below
        // it in normal flow. They used to float over the picker in a ZStack behind a
        // 92pt scrim, which covered the last rows outright -- the fade was cropping real
        // content instead of just softening an edge.
        ZStack {
            Color.black
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Text("Selecciona apps/sitios web, toca \">\" para expandir")
                    .font(.system(.footnote, design: .default, weight: .semibold))
                    .foregroundStyle(LocktyColors.secondaryText)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, LocktySpacing.xl)
                    .padding(.top, LocktySpacing.lg)
                    .padding(.bottom, LocktySpacing.md)

                FamilyActivityPicker(selection: Binding(
                    get: { draftSelection },
                    set: { newValue in
                        let result = normalizedSelection(newValue, previous: draftSelection, rules: rules)
                        withAnimation(.smooth(duration: 0.22)) {
                            draftSelection = result.selection
                        }
                        if let violation = result.violations.first {
                            onViolation(violation.message)
                        }
                    }
                ))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                // A fixed-height fade on the picker's own bottom edge, so it stays the
                // same softness whatever height the picker ends up with.
                .mask {
                    VStack(spacing: 0) {
                        LinearGradient(
                            colors: [.black.opacity(0), .black],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: pickerFadeHeight)

                        Rectangle()

                        LinearGradient(
                            colors: [.black, .black.opacity(0)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                        .frame(height: pickerFadeHeight)
                    }
                }

                VStack(spacing: LocktySpacing.lg) {
                    Text(bottomCounterText)
                        .font(.system(.subheadline, design: .default, weight: .medium))
                        .foregroundStyle(LocktyColors.secondaryText)
                        .textCase(.uppercase)
                        .contentTransition(.numericText())

                    Button {
                        withAnimation(.smooth(duration: 0.28)) {
                            onSave(draftSelection)
                        }
                        dismiss()
                    } label: {
                        Text("Guardar")
                            .font(.system(.body, design: .default, weight: .medium))
                            .frame(maxWidth: .infinity)
                            .frame(height: 58)
                            .background(
                                RoundedRectangle(cornerRadius: 28, style: .continuous)
                                    .fill(canSave ? Color.white.opacity(0.55) : Color.white.opacity(0.16))
                            )
                            .foregroundStyle(canSave ? .black.opacity(0.72) : .white.opacity(0.28))
                    }
                    .buttonStyle(.locktyInteractive(shape: RoundedRectangle(cornerRadius: 28, style: .continuous)))
                    .disabled(!canSave)

                    Button {
                        onCancel()
                        dismiss()
                    } label: {
                        Text("Cancelar")
                            .font(.system(.body, design: .default, weight: .regular))
                            .foregroundStyle(LocktyColors.primaryText)
                            .frame(maxWidth: .infinity)
                            .frame(height: 44)
                            .contentShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.locktyInteractive(shape: Capsule(style: .continuous)))
                }
                .padding(.horizontal, LocktySpacing.xl)
                .padding(.top, LocktySpacing.sm)
                .padding(.bottom, LocktySpacing.xl)
                .background(Color.black)
            }
        }
    }

    private var canSave: Bool {
        draftSelection != selection || draftSelection.hasAnySelection || selection.hasAnySelection
    }

    private var bottomCounterText: String {
        draftSelection.locktySelectionCounterText
    }
}

struct LocktyCenteredFeedbackOverlay: View {
    let state: LocktyFeedbackOverlayState

    var body: some View {
        VStack {
            HStack(spacing: LocktySpacing.md) {
                Image(systemName: state.systemImage)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(.white.opacity(0.09)))

                VStack(alignment: .leading, spacing: 3) {
                    Text(state.title)
                        .font(.system(.subheadline, design: .default, weight: .semibold))
                        .foregroundStyle(.white)

                    Text(state.subtitle)
                        .font(.system(.footnote, design: .default, weight: .medium))
                        .foregroundStyle(.white.opacity(0.82))
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(.horizontal, LocktySpacing.lg)
            .padding(.vertical, 14)
            .frame(maxWidth: 360)
            .safeGlass(radius: 22, tint: state.tint)
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(.white.opacity(0.10), lineWidth: 1)
            }
            .shadow(color: state.tint.opacity(0.38), radius: 24, y: 10)

            Spacer()
        }
        .padding(.top, 110)
        .padding(.horizontal, LocktySpacing.xl)
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

private struct StableHashSort {
    static func sort<T: Hashable>(_ values: some Collection<T>) -> [T] {
        values.sorted { $0.hashValue < $1.hashValue }
    }
}

private func stableApplications(_ tokens: Set<ManagedSettings.ApplicationToken>) -> [ManagedSettings.ApplicationToken] {
    StableHashSort.sort(tokens)
}

private func stableCategories(_ tokens: Set<ManagedSettings.ActivityCategoryToken>) -> [ManagedSettings.ActivityCategoryToken] {
    StableHashSort.sort(tokens)
}

private func stableWebDomains(_ tokens: Set<ManagedSettings.WebDomainToken>) -> [ManagedSettings.WebDomainToken] {
    StableHashSort.sort(tokens)
}

private func limitedSet<T: Hashable>(
    proposed: Set<T>,
    previous: Set<T>,
    maximum: Int
) -> Set<T> {
    let added = StableHashSort.sort(proposed.subtracting(previous))
    let retained = StableHashSort.sort(proposed.intersection(previous))
    return Set(Array((added + retained).prefix(maximum)))
}

private func normalizedSelection(
    _ selection: FamilyActivitySelection,
    previous: FamilyActivitySelection,
    rules: LocktyActivitySelectionRules
) -> (selection: FamilyActivitySelection, violations: [LocktyActivitySelectionViolation]) {
    var normalized = selection
    var violations: [LocktyActivitySelectionViolation] = []

    if !rules.allowsApplications, !normalized.applicationTokens.isEmpty {
        normalized.applicationTokens = []
        violations.append(.applicationsNotAllowed)
    }

    if !rules.allowsCategories, !normalized.categoryTokens.isEmpty {
        normalized.categoryTokens = []
        violations.append(.categoriesNotAllowed)
    }

    if !rules.allowsWebDomains, !normalized.webDomainTokens.isEmpty {
        normalized.webDomainTokens = []
        violations.append(.websitesNotAllowed)
    }

    if let maximum = rules.maximumApplications, normalized.applicationTokens.count > maximum {
        normalized.applicationTokens = limitedSet(
            proposed: normalized.applicationTokens,
            previous: previous.applicationTokens,
            maximum: maximum
        )
        violations.append(.tooManyApps(maximum))
    }

    if let maximum = rules.maximumCategories, normalized.categoryTokens.count > maximum {
        normalized.categoryTokens = limitedSet(
            proposed: normalized.categoryTokens,
            previous: previous.categoryTokens,
            maximum: maximum
        )
        violations.append(.tooManyCategories(maximum))
    }

    if let maximum = rules.maximumWebDomains, normalized.webDomainTokens.count > maximum {
        normalized.webDomainTokens = limitedSet(
            proposed: normalized.webDomainTokens,
            previous: previous.webDomainTokens,
            maximum: maximum
        )
        violations.append(.tooManyWebsites(maximum))
    }

    return (normalized, violations)
}

private extension FamilyActivitySelection {
    var hasAnySelection: Bool {
        !applicationTokens.isEmpty || !categoryTokens.isEmpty || !webDomainTokens.isEmpty
    }

    var locktySelectionCounterText: String {
        if !categoryTokens.isEmpty || !webDomainTokens.isEmpty {
            var parts: [String] = []
            if categoryTokens.count > 0 {
                parts.append(categoryTokens.count == 1 ? "1 categoría" : "\(categoryTokens.count) categorías")
            }
            if applicationTokens.count > 0 {
                parts.append(applicationTokens.count == 1 ? "1 app" : "\(applicationTokens.count) apps")
            }
            if webDomainTokens.count > 0 {
                parts.append(webDomainTokens.count == 1 ? "1 sitio web" : "\(webDomainTokens.count) sitios web")
            }
            return parts.joined(separator: " y ")
        }

        return applicationTokens.count == 1
            ? "1 app seleccionada"
            : "\(applicationTokens.count) apps seleccionadas"
    }
}
