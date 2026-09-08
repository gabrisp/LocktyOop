import Foundation

/// The objectives people actually set, ready-made.
///
/// A new objective from a blank form is five decisions -- name, glyph, target, unit, how
/// much a tap adds -- before anything exists. Almost all of them are one of these, so
/// they are offered as a grid and the form is left for the rest.
///
/// Custom is in the list rather than being the way in. Choosing "something else" is a
/// choice like any other, and putting it last says what the list is for.
nonisolated struct ObjectivePreset: Identifiable, Hashable {
    let id: String
    let title: String
    let symbolName: String
    let source: ObjectiveSource
    let unit: String
    let target: Double
    let step: Double
    /// What it is, for the tile. One line.
    let detail: String

    static let all: [ObjectivePreset] = [
        ObjectivePreset(
            id: "steps",
            title: "Steps",
            symbolName: "figure.walk",
            source: .steps,
            unit: "steps",
            target: 8000,
            step: 500,
            detail: "Read from Health"
        ),
        ObjectivePreset(
            id: "sleep",
            title: "Sleep",
            symbolName: "bed.double.fill",
            source: .sleep,
            unit: "h",
            target: 8,
            step: 1,
            detail: "Read from Health"
        ),
        ObjectivePreset(
            id: "water",
            title: "Water",
            symbolName: "drop.fill",
            source: .manual,
            unit: "glasses",
            target: 8,
            step: 1,
            detail: "One tap a glass"
        ),
        ObjectivePreset(
            id: "reading",
            title: "Reading",
            symbolName: "book.fill",
            source: .manual,
            unit: "min",
            target: 30,
            step: 10,
            detail: "Minutes with a book"
        ),
        ObjectivePreset(
            id: "training",
            title: "Training",
            symbolName: "dumbbell.fill",
            source: .manual,
            unit: "sessions",
            target: 3,
            step: 1,
            detail: "Sessions in the week"
        ),
        ObjectivePreset(
            id: "outside",
            title: "Outside",
            symbolName: "leaf.fill",
            source: .manual,
            unit: "min",
            target: 60,
            step: 15,
            detail: "Minutes out of the house"
        ),
        ObjectivePreset(
            id: "appTime",
            title: "App time",
            symbolName: "hourglass",
            source: .appUsage,
            unit: "min",
            target: 30,
            step: 5,
            detail: "Stay under, in one app"
        ),
        ObjectivePreset(
            id: "screenTime",
            title: "Screen time",
            symbolName: "iphone",
            source: .screenTime,
            unit: "min",
            target: 120,
            step: 15,
            detail: "Stay under, all apps"
        ),
        ObjectivePreset(
            id: "focusScore",
            title: "Focus score",
            symbolName: "gauge.medium",
            source: .focusScore,
            unit: "%",
            target: 70,
            step: 5,
            detail: "The score on today's badge"
        ),
        ObjectivePreset(
            id: "yesno",
            title: "Yes or no",
            symbolName: "checkmark.circle",
            source: .manual,
            unit: "",
            target: 1,
            step: 1,
            detail: "Done or not done"
        ),
        ObjectivePreset(
            id: "custom",
            title: "Custom",
            symbolName: "target",
            source: .manual,
            // Something to count, with a unit to change. It used to arrive as a target of
            // one with no unit, which *is* the yes-or-no above it -- so picking "anything
            // you count" produced an objective with nothing to count and no field on the
            // form to give it one.
            unit: "times",
            target: 5,
            step: 1,
            detail: "Anything you count"
        )
    ]

    /// The period a preset is usually counted in. Training is a week's worth; everything
    /// else is a day.
    var period: ObjectivePeriod {
        id == "training" ? .weekly : .daily
    }
}
