import AppIntents
import SwiftUI
import WidgetKit

/// The objectives, on the home screen, as the pills they are inside the app.
///
/// The same object in both places: a rim drawn to how far along it is, the glyph, the
/// figure. And the same gesture -- a tap adds a step, a yes-or-no flips -- except here it
/// happens without opening anything, which is the reason for the widget at all. Logging a
/// glass of water is not worth a launch, and an objective you have to open an app to tick
/// is one you stop ticking.
struct ObjectivesWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: ObjectiveWidgetStore.kind,
            intent: SelectObjectiveIntent.self,
            provider: ObjectivesTimelineProvider()
        ) { entry in
            ObjectivesWidgetView(entry: entry)
                .containerBackground(for: .widget) { LocktyColors.background }
        }
        .configurationDisplayName("Objectives")
        .description("Tap to log a glass, a walk, a page -- without opening Lockty.")
        // Two sizes and no more: a tile is for tapping, and eight of them on a large
        // square is a list, which is what the app is for.
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Timeline

struct ObjectiveEntry: TimelineEntry {
    let date: Date
    /// What to draw, in the order it should be read.
    let objectives: [Objective]
    let progress: ObjectiveProgressState
    /// The ones the widget was configured for, in the order they were picked.

    func value(of objective: Objective) -> Double { progress.value(for: objective) }
    func fraction(of objective: Objective) -> Double { progress.fraction(for: objective) }
    func isComplete(_ objective: Objective) -> Bool { progress.isComplete(objective) }
}

struct ObjectivesTimelineProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> ObjectiveEntry {
        ObjectiveEntry(date: Date(), objectives: [], progress: .empty)
    }

    func snapshot(for configuration: SelectObjectiveIntent, in context: Context) async -> ObjectiveEntry {
        entry(for: configuration)
    }

    /// One entry, and another at midnight.
    ///
    /// Nothing else is scheduled: what changes here is a tap, and a tap reloads the
    /// timeline itself. The midnight entry is for the day rolling over while the phone is
    /// in a pocket, so the morning does not open on last night's figures.
    func timeline(for configuration: SelectObjectiveIntent, in context: Context) async -> Timeline<ObjectiveEntry> {
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: Date())) ?? Date()
        return Timeline(entries: [entry(for: configuration)], policy: .after(midnight))
    }

    private func entry(for configuration: SelectObjectiveIntent) -> ObjectiveEntry {
        let progress = ObjectiveWidgetStore.progress()
        let all = ObjectiveWidgetStore.dailyObjectives()

        // What was picked, in the order it was picked -- the slots are the layout, so a
        // chosen list is never reordered by what is done and what is not.
        let chosen = configuration.chosenIDs.compactMap { id in all.first { $0.id == id } }

        // Nothing picked: still to do first, so a widget dropped on the home screen has
        // the useful ones in it rather than being empty until it is configured.
        let ordered = chosen.isEmpty
            ? all.filter { !progress.isComplete($0) } + all.filter { progress.isComplete($0) }
            : chosen

        return ObjectiveEntry(date: Date(), objectives: ordered, progress: progress)
    }
}

// MARK: - Views

struct ObjectivesWidgetView: View {
    let entry: ObjectiveEntry
    @Environment(\.widgetFamily) private var family

    /// How many fit: two on a small tile, four on a medium.
    private var capacity: Int {
        family == .systemMedium ? 4 : 2
    }

    private var shown: [Objective] {
        Array(entry.objectives.prefix(capacity))
    }

    var body: some View {
        if shown.isEmpty {
            empty
        } else if family == .systemMedium {
            // Two by two. A medium tile is twice a small one, and four squares fill it
            // the way two rows fill the small -- same tile, twice over.
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 2),
                spacing: 8
            ) {
                ForEach(shown) { objective in
                    ObjectiveTile(objective: objective, entry: entry, isLarge: false)
                }
            }
        } else {
            // Stacked, not side by side: two half-width tiles on a small widget leave the
            // name with about four letters, and the name is how you know which one you
            // are about to add a glass of water to.
            VStack(spacing: 8) {
                ForEach(shown) { objective in
                    ObjectiveTile(objective: objective, entry: entry, isLarge: false)
                }
            }
        }
    }

    /// Nothing to draw. Said as the thing to do about it, in the place it is done: a
    /// widget's own settings are behind a long press, and there is no other way in.
    private var empty: some View {
        VStack(spacing: 6) {
            Image(systemName: "hand.tap")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)

            Text("Long press to select objectives")
                .font(.system(.footnote, design: .default, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(8)
    }
}

/// One objective as a pill, pressable.
///
/// A `Button` carrying an intent rather than a link: the tile is the control, and the tap
/// is served by the system without the app being launched. The ones Health counts have no
/// button at all -- there is nothing to add by hand -- so those are drawn plain.
struct ObjectiveTile: View {
    let objective: Objective
    let entry: ObjectiveEntry
    /// A small widget gives its one objective the whole tile; a grid gives it a row.
    let isLarge: Bool

    private var colour: Color { LocktyColors.routine(objective.color) }
    private var isDone: Bool { entry.isComplete(objective) }
    private var fraction: Double { max(entry.fraction(of: objective), 0.02) }

    var body: some View {
        if objective.source.isMeasured {
            face
        } else {
            Button(intent: AdvanceObjectiveIntent(objectiveID: objective.id)) {
                face
            }
            .buttonStyle(.plain)
        }
    }

    private var face: some View {
        VStack(alignment: .leading, spacing: isLarge ? 8 : 3) {
            HStack(spacing: 6) {
                Image(systemName: objective.symbolName)
                    .font(.system(size: isLarge ? 18 : 13, weight: .semibold))
                    .foregroundStyle(colour)

                if !isLarge {
                    Spacer(minLength: 0)
                }
            }

            if isLarge {
                Spacer(minLength: 0)
            }

            Text(value)
                .font(.system(size: isLarge ? 34 : 17, weight: .bold))
                .foregroundStyle(LocktyColors.primaryText)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Text(objective.name)
                .font(.system(size: isLarge ? 13 : 11, weight: .regular))
                .foregroundStyle(LocktyColors.secondaryText)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(maxHeight: isLarge ? .infinity : nil, alignment: .leading)
        .padding(isLarge ? 14 : 10)
        .background { surface }
    }

    /// "6", or the answer itself for the ones that are simply done or not.
    private var value: String {
        guard !objective.isYesNo else { return isDone ? "Yes" : "Not yet" }
        return objective.formatNumber(entry.value(of: objective))
    }

    /// The pill's body, as the app draws it: the colour laid over the ground, the rim
    /// trimmed to how far along it is, and a bloom behind the whole thing.
    private var surface: some View {
        let shape = RoundedRectangle(cornerRadius: isLarge ? 22 : 16, style: .continuous)

        return ZStack {
            shape.fill(colour.opacity(0.16))

            shape.stroke(LocktyColors.ink(0.10), lineWidth: 2)

            shape
                .trim(from: 0, to: fraction)
                .stroke(colour, style: StrokeStyle(lineWidth: 2, lineCap: .round))
        }
    }
}
