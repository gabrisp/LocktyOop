import SwiftUI

struct DestinationFactory {
    let featureFactory: FeatureFactory

    @ViewBuilder
    func destination(for route: AppRoute) -> some View {
        switch route {
        case .rulesList:
            featureFactory.makeRulesList()

        case .routinesList:
            featureFactory.makeRoutinesList()

        case .frictionsList:
            featureFactory.makeFrictionsList()

        case .appsList:
            featureFactory.makeAppsList()

        case .alwaysAllowedGroup:
            featureFactory.makeAlwaysAllowedGroupView()

        case .settings:
            featureFactory.makeSettingsView()

        case .distractingGroup:
            featureFactory.makeDistractingGroup()

        case .distractingApps:
            featureFactory.makeDistractingAppsSelection()

        case .distractingIntervention:
            featureFactory.makeDistractingInterventionPicker()

        case .distractingFriction:
            featureFactory.makeDistractingFrictionPicker()

        case .screenTimeInsights(let day):
            featureFactory.makeScreenTimeInsights(day: day)

        case .blockScreens:
            featureFactory.makeBlockScreenSettings()

        case .usageBreakdown(let day):
            featureFactory.makeUsageBreakdown(day: day)

        }
    }

    @ViewBuilder
    func sheet(for route: SheetRoute) -> some View {
        switch route {
        case .allowanceTimer(let route):
            featureFactory.makeAllowanceTimerSheet(route: route)

        case .dayPicker:
            featureFactory.makeDayPickerSheet()

        case .focusCreationChoice(let route):
            featureFactory.makeFocusCreationChoiceSheet(route: route)

        case .appClassification(let appID):
            featureFactory.makeClassificationSheet(appID: appID)

        case .breakStatus(let state):
            featureFactory.makeBreakStatusSheet(state: state)

        case .routineBreak(let routineID):
            featureFactory.makeRoutineBreakSheet(routineID: routineID)

        case .appPicker(let scope):
            featureFactory.makeAppPickerSheet(scope: scope)

        case .systemAccess:
            featureFactory.makeSystemAccessSheet()


        case .applicationDetails(let id, let day):
            featureFactory.makeApplicationDetails(appID: id, day: day)

        case .liveSession:
            featureFactory.makeLiveSessionSheet()

        case .ruleEditor(let route):
            featureFactory.makeRuleEditor(route: route)

        case .routineEditor(let route):
            featureFactory.makeRoutineEditor(route: route)

        case .pauseFlowEditor(let route):
            featureFactory.makePauseFlowEditor(route: route)

        case .pauseEditor(let route):
            featureFactory.makePauseEditor(route: route)

        case .frictionEditor(let route):
            featureFactory.makeFrictionEditor(route: route)

        case .appGroupEditor(let route):
            featureFactory.makeAppGroupEditor(route: route)

        case .productivityDetail(let day):
            todaySheet { featureFactory.makeProductivityDetail(day: day) }

        case .controlDetail(let day):
            todaySheet { featureFactory.makeControlDetail(day: day) }

        case .detoxDetail(let day):
            todaySheet { featureFactory.makeDetoxDetail(day: day) }

        case .screenTimeDetail(let day):
            todaySheet { featureFactory.makeScreenTimeDetail(day: day) }

        case .routineDaySummary(let day):
            todaySheet { featureFactory.makeRoutineDaySummary(day: day) }

        case .pauseDaySummary(let day):
            todaySheet { featureFactory.makePauseDaySummary(day: day) }

        case .distractionsDetail(let day):
            todaySheet { featureFactory.makeDistractionsDetail(day: day) }

        case .intentionalTimeDetail(let day):
            todaySheet { featureFactory.makeIntentionalTimeDetail(day: day) }

        case .digitalBalanceDetail(let day):
            todaySheet { featureFactory.makeDigitalBalanceDetail(day: day) }
        }
    }

    /// Today's detail sheets: no navigation stack, no title, no toolbar buttons —
    /// just the drag indicator, opening at the smaller detent.
    @ViewBuilder
    private func todaySheet<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    func fullScreen(for route: FullScreenRoute) -> some View {
        switch route {
        case .activeRoutine(let id):
            featureFactory.makeActiveRoutine(routineID: id)

        case .unlockFlow(let token):
            featureFactory.makeUnlockFlow(token: token)
        }
    }
}
