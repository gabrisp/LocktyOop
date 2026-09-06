import AppIntents
import Foundation
import WidgetKit

/// One objective, as something the system can be asked about.
///
/// Needed so a widget can be configured to show a particular one: the entity is what the
/// picker in the widget's own settings lists.
struct ObjectiveEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Objective" }
    static var defaultQuery = ObjectiveEntityQuery()

    let id: UUID
    let name: String
    let symbolName: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", image: .init(systemName: symbolName))
    }

    init(_ objective: Objective) {
        id = objective.id
        name = objective.name
        symbolName = objective.symbolName
    }
}

struct ObjectiveEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [ObjectiveEntity] {
        let wanted = Set(identifiers)
        return ObjectiveWidgetStore.dailyObjectives()
            .filter { wanted.contains($0.id) }
            .map(ObjectiveEntity.init)
    }

    func suggestedEntities() async throws -> [ObjectiveEntity] {
        ObjectiveWidgetStore.dailyObjectives().map(ObjectiveEntity.init)
    }

    func defaultResult() async -> ObjectiveEntity? {
        try? await suggestedEntities().first
    }
}

/// Which objectives the tile is about.
///
/// Four slots rather than a list: a small tile shows the first two and a medium all four,
/// so which slot something is in decides where it appears -- and picking them one at a
/// time is how you say that. Left empty, the tile falls back to whatever is still
/// outstanding today, so a widget just dropped on the home screen has something in it.
struct SelectObjectiveIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Objectives" }
    static var description: IntentDescription {
        IntentDescription("Pick up to four objectives. A small widget shows the first two.")
    }

    @Parameter(title: "First")
    var objective: ObjectiveEntity?

    @Parameter(title: "Second")
    var second: ObjectiveEntity?

    @Parameter(title: "Third")
    var third: ObjectiveEntity?

    @Parameter(title: "Fourth")
    var fourth: ObjectiveEntity?

    init() {}

    init(objective: ObjectiveEntity?) {
        self.objective = objective
    }

    /// The ids that were chosen, in the order they were chosen.
    var chosenIDs: [UUID] {
        [objective, second, third, fourth].compactMap(\.self).map(\.id)
    }
}

/// A tap on the tile: one step added, from the home screen.
///
/// `AppIntent` rather than a link into the app, because that is the whole point of the
/// widget -- logging a glass of water should not cost a launch, a splash and a scroll.
struct AdvanceObjectiveIntent: AppIntent {
    static var title: LocalizedStringResource { "Add one" }
    /// Nothing is shown and nothing is opened: the tile redraws where it stands.
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Objective")
    var objectiveID: String

    init() {}

    init(objectiveID: UUID) {
        self.objectiveID = objectiveID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: objectiveID), let objective = ObjectiveWidgetStore.objective(id: id) {
            if objective.isYesNo {
                ObjectiveWidgetStore.toggle(objective)
            } else {
                ObjectiveWidgetStore.advance(objective)
            }
        }
        return .result()
    }
}

/// A yes or a no, flipped from the home screen.
struct ToggleObjectiveIntent: AppIntent {
    static var title: LocalizedStringResource { "Mark as done" }
    static var openAppWhenRun: Bool { false }

    @Parameter(title: "Objective")
    var objectiveID: String

    init() {}

    init(objectiveID: UUID) {
        self.objectiveID = objectiveID.uuidString
    }

    func perform() async throws -> some IntentResult {
        if let id = UUID(uuidString: objectiveID), let objective = ObjectiveWidgetStore.objective(id: id) {
            ObjectiveWidgetStore.toggle(objective)
        }
        return .result()
    }
}
