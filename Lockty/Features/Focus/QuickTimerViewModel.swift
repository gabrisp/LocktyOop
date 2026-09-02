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

        let endsAt = Date().addingTimeInterval(TimeInterval(minutes * 60))
        let routine = Routine(
            id: Self.routineID,
            name: "Quick timer",
            icon: "timer",
            color: .mint,
            mode: .normal,
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
    }

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
