import SwiftUI

struct TodayMetricGrid: View {
    let state: TodayDayState
    var onMetricSelected: ((TodayMetricKind) -> Void)?

    private let columns = [
        GridItem(.flexible(), spacing: LocktySpacing.sm),
        GridItem(.flexible(), spacing: LocktySpacing.sm)
    ]

    var body: some View {
        LazyVGrid(columns: columns, spacing: LocktySpacing.sm) {
            ScreenTimeCard(state: state.metrics.screenTime) { onMetricSelected?(.screenTime) }
            BestDetoxCard(state: state.metrics.bestDetox) { onMetricSelected?(.bestDetox) }
//            RoutineSummaryCard(state: state.metrics.routines) { onMetricSelected?(.routines) }
//            PauseSuccessDayCard(state: state.metrics.pauseSuccess) { onMetricSelected?(.pauseSuccess) }
            DistractionsCard(state: state.metrics.distractions) { onMetricSelected?(.distractions) }
            IntentionalTimeCard(state: state.metrics.intentionalTime) { onMetricSelected?(.intentionalTime) }
        }
    }
}
