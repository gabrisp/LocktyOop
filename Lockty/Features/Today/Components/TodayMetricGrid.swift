import SwiftUI

struct TodayMetricGrid: View {
    let state: TodayDayState
    var onMetricSelected: ((TodayMetricKind) -> Void)?

    private let columns = [
        GridItem(.flexible(), spacing: LocktySpacing.sm),
        GridItem(.flexible(), spacing: LocktySpacing.sm)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: LocktySpacing.lg) {
//            ScreenTimeCard(state: state.metrics.screenTime) { onMetricSelected?(.screenTime) }
//            BestDetoxCard(state: state.metrics.bestDetox) { onMetricSelected?(.bestDetox) }
//            RoutineSummaryCard(state: state.metrics.routines) { onMetricSelected?(.routines) }
//            PauseSuccessDayCard(state: state.metrics.pauseSuccess) { onMetricSelected?(.pauseSuccess) }
//            // Both commented out rather than removed. Distractions is a count that
//            // belongs inside Detox, and intentional time inside Focus -- the two figures
//            // are still computed and still shown on those pages, so a card repeating
//            // them here is the same number twice on one screen.
//            DistractionsCard(state: state.metrics.distractions) { onMetricSelected?(.distractions) }
//            IntentionalTimeCard(state: state.metrics.intentionalTime) { onMetricSelected?(.intentionalTime) }
        }
    }
}
