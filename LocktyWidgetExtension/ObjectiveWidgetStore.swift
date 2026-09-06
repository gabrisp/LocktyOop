import Foundation
import WidgetKit

/// What the widget knows, and the one place it writes.
///
/// The widget is a second window onto the same two files the app keeps in the App Group:
/// `objectives.json` and `objective-progress.json`. It holds no state of its own -- a
/// widget that remembered anything would be a third copy of the truth, and the first
/// thing to disagree with the other two.
///
/// Every write goes through here and ends by reloading the timelines, because a tap on
/// the home screen has to redraw the tile it was made on.
enum ObjectiveWidgetStore {
    static let kind = ObjectiveWidgets.kind

    private static var store: AppGroupStore { AppGroupStore() }

    /// The objectives that can be tapped from the home screen: the daily ones you count
    /// yourself. Steps and sleep are read from Health, so a button for them would be a
    /// button that writes down a number you did not walk.
    static func tappableObjectives() -> [Objective] {
        store.loadObjectives()
            .filter { $0.period == .daily && !$0.source.isMeasured }
            .sorted { $0.createdAt < $1.createdAt }
    }

    /// Everything counted by the day, tappable or not -- the widget shows Health-read ones
    /// too, it just does not offer a button for them.
    static func dailyObjectives() -> [Objective] {
        store.loadObjectives()
            .filter { $0.period == .daily }
            .sorted { $0.createdAt < $1.createdAt }
    }

    static func objective(id: UUID) -> Objective? {
        store.loadObjectives().first { $0.id == id }
    }

    static func progress() -> ObjectiveProgressState {
        store.loadObjectiveProgress()
    }

    /// One step, the whole interaction: a glass of water logged without opening anything.
    static func advance(_ objective: Objective) {
        write { $0.add(objective.step, to: objective) }
    }

    /// A yes or a no, flipped. Filled to the target, or emptied.
    static func toggle(_ objective: Objective) {
        write { state in
            if state.isComplete(objective) {
                state.set(0, for: objective)
            } else {
                state.set(objective.target, for: objective)
            }
        }
    }

    private static func write(_ transform: (inout ObjectiveProgressState) -> Void) {
        try? store.updateObjectiveProgress(transform)
        WidgetCenter.shared.reloadTimelines(ofKind: kind)
    }
}
