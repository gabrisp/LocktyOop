import Combine
import FamilyControls
import Foundation

/// The session you start without making anything first.
///
/// It runs as a routine, because a running block *is* a routine as far as the shield,
/// the breaks and the extensions are concerned -- inventing a second kind of running
/// thing would mean teaching every one of them about it. What it is not is a routine in
/// the library: it is never saved, and it lives under one fixed id so the apps you
/// picked for it last time are still there the next time you open Focus.
@MainActor
final class QuickTimerViewModel: ObservableObject {
    /// One quick timer, one id. The selection is stored against it like any routine's,
    /// which is what lets the shield resolve it with no special case anywhere.
    static let routineID = UUID(uuidString: "9E6D2C51-8A34-4C2E-9E0B-3F1D5A7C2B44")!

    @Published var minutes = 30
    /// Whether it runs until it is stopped by hand.
    ///
    /// Past the longest length on the dial rather than a switch of its own: "longer, and
    /// longer, and then no end" is one decision, and a separate toggle would ask it twice.
    @Published var isInfinite = false
    /// Strict mode: nothing can end it early, not even the app.
    ///
    /// Refused on a shield with no end, and that is a safety rule rather than a design
    /// one: a strict block with nothing to expire is a phone you cannot get back.
    @Published var isStrict = false
    /// What strictness closes, when it is on. Asked for in the same place as everything
    /// else the session restricts.
    @Published var strictGuards = StrictModeGuards()
    @Published private(set) var selection = FamilyActivitySelection()
    @Published private(set) var frictionName: String?
    @Published var frictionID: UUID?
    @Published var contentRestrictions: ContentRestrictions = .none
    @Published var errorMessage: String?

    private let routineEngine: RoutineEngine
    private let selectionStore: ScreenTimeSelectionStore
    private let frictionRepository: FrictionRepository
    private var cancellables = Set<AnyCancellable>()

    init(
        routineEngine: RoutineEngine,
        selectionStore: ScreenTimeSelectionStore,
        frictionRepository: FrictionRepository
    ) {
        self.routineEngine = routineEngine
        self.selectionStore = selectionStore
        self.frictionRepository = frictionRepository

        // Republished so the card redraws when the session ends in the background, which
        // is the case this whole feature turns on.
        routineEngine.objectWillChange
            .sink { [weak self] _ in self?.objectWillChange.send() }
            .store(in: &cancellables)
    }

    var scope: ScreenTimeSelectionScope { .routine(Self.routineID) }

    /// When the running quick timer ends, or nil when none is running.
    var endsAt: Date? {
        routineEngine.activeRoutines
            .first { $0.routineID == Self.routineID }?
            .expectedEndAt
    }

    /// Whether the session is up, whether or not it has an end to count down to.
    var isSessionRunning: Bool {
        routineEngine.activeRoutines.contains { $0.routineID == Self.routineID }
    }

    var blockedSummary: String {
        let apps = selection.applicationTokens.count
        let categories = selection.categoryTokens.count
        return RestrictionSummary.appsAndCategories(apps: apps, categories: categories)
            .map { $0.hasSuffix(".") ? String($0.dropLast()) : $0 }
            ?? "Choose"
    }

    var frictionSummary: String { frictionName ?? "None" }

    func load() async {
        selection = (try? selectionStore.load(scope: scope)) ?? FamilyActivitySelection()
        if let frictionID, let friction = await frictionRepository.friction(id: frictionID) {
            frictionName = friction.name
        } else {
            frictionName = nil
        }
    }

    func replaceSelection(_ newValue: FamilyActivitySelection) {
        selection = newValue
        try? selectionStore.save(newValue, scope: scope)
    }

    func selectFriction(_ friction: Friction?) {
        frictionID = friction?.id
        frictionName = friction?.name
    }

    /// Builds the session and starts it. Nothing is written to the routine library.
    func start() async {
        guard !selection.applicationTokens.isEmpty || !selection.categoryTokens.isEmpty else {
            errorMessage = "Choose at least one app to block."
            return
        }

        // No end at all when it is infinite: the engine takes nil as "until it is stopped".
        let endsAt = isInfinite ? nil : Date().addingTimeInterval(TimeInterval(minutes * 60))

        // Named after the moment it was made. A session is not a thing you keep, so there
        // is nothing to call it -- and asking for a name before a five-minute block is
        // asking a question about a thing that will be over before it is answered.
        let name = Self.nameFormatter.string(from: Date())

        // Strict is refused outright when there is no end, whatever the switch says: a
        // block that cannot be ended and does not expire is a phone you cannot get back.
        let mode: RoutineMode = (isStrict && !isInfinite) ? .strict : .normal

        let routine = Routine(
            id: Self.routineID,
            name: name,
            icon: "shield",
            color: .mint,
            mode: mode,
            triggers: [.manual],
            blockedApplications: Set(selection.applicationTokens.map(AppIdentity.ID.init(token:))),
            blockedDomains: [],
            contentRestrictions: contentRestrictions,
            tasks: [],
            breakPolicy: .none,
            pausePolicy: await resolvedPausePolicy()
        )

        let outcome = await routineEngine.start(routine, trigger: .manual, expectedEndAt: endsAt)
        switch outcome {
        case .started, .alreadyRunning:
            errorMessage = nil
        case .blocked(let reason), .failed(let reason):
            errorMessage = reason
        }
    }

    func stop() async {
        await routineEngine.stop(routineID: Self.routineID)

        // And the session forgets what it held. A shield is decided in one go and gone
        // when it ends; keeping the last selection meant the next one arrived already
        // pointed at the apps you blocked yesterday afternoon, and a "Start" that blocks
        // something you have not looked at is the app deciding for you.
        replaceSelection(FamilyActivitySelection())
        contentRestrictions = .none
        isStrict = false
        strictGuards = StrictModeGuards()
        isInfinite = false
        minutes = 30
    }

    /// "12 Sep, 18:40" -- what a session is called, since nobody names one.
    private static let nameFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("d MMM HH:mm")
        return formatter
    }()

    /// The friction resolved at start, the same way a routine resolves its own: the flow
    /// can be edited or deleted afterwards and the running session keeps what it was
    /// given.
    private func resolvedPausePolicy() async -> RoutinePausePolicy {
        guard let frictionID, let friction = await frictionRepository.friction(id: frictionID) else {
            return .off
        }
        return friction.policy
    }
}
