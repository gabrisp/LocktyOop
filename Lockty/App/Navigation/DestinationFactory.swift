import SwiftUI

struct DestinationFactory {
    let featureFactory: FeatureFactory

    @ViewBuilder
    func destination(for route: AppRoute) -> some View {
        switch route {
        case .today(let day):
            featureFactory.makeTodayView(day: day)

        case .routineDetail(let id):
            featureFactory.makeRoutineDetail(routineID: id)

        case .routineEditor(let route):
            featureFactory.makeRoutineEditor(route: route)

        case .settings:
            featureFactory.makeSettingsView()

        case .pauseDetail(let id):
            featureFactory.makePauseDetail(pauseID: id)

        case .pauseEditor(let route):
            featureFactory.makePauseEditor(route: route)

        case .productivityDetail(let day):
            featureFactory.makeProductivityDetail(day: day)

        case .controlDetail(let day):
            featureFactory.makeControlDetail(day: day)

        case .detoxDetail(let day):
            featureFactory.makeDetoxDetail(day: day)

        case .screenTimeDetail(let day):
            featureFactory.makeScreenTimeDetail(day: day)

        case .routineDaySummary(let day):
            featureFactory.makeRoutineDaySummary(day: day)

        case .pauseDaySummary(let day):
            featureFactory.makePauseDaySummary(day: day)

        case .distractionsDetail(let day):
            featureFactory.makeDistractionsDetail(day: day)

        case .intentionalTimeDetail(let day):
            featureFactory.makeIntentionalTimeDetail(day: day)

        case .digitalBalanceDetail(let day):
            featureFactory.makeDigitalBalanceDetail(day: day)

        case .applicationDetails(let id, let day):
            featureFactory.makeApplicationDetails(appID: id, day: day)
        }
    }

    @ViewBuilder
    func sheet(for route: SheetRoute) -> some View {
        switch route {
        case .appClassification(let appID):
            featureFactory.makeClassificationSheet(appID: appID)

        case .routineBreak(let routineID):
            featureFactory.makeRoutineBreakSheet(routineID: routineID)

        case .accentPicker:
            featureFactory.makeAccentPickerSheet()

        case .appPicker(let scope):
            featureFactory.makeAppPickerSheet(scope: scope)

        case .systemAccess:
            featureFactory.makeSystemAccessSheet()

        case .routineIconPicker(let draftID):
            featureFactory.makeRoutineIconPickerSheet(draftID: draftID)

        case .routineColorPicker(let draftID):
            featureFactory.makeRoutineColorPickerSheet(draftID: draftID)

        case .routineAppPicker(let draftID):
            featureFactory.makeRoutineAppPickerSheet(draftID: draftID)

        case .pauseAppPicker(let draftID):
            featureFactory.makePauseAppPickerSheet(draftID: draftID)

        case .routineDomains(let draftID):
            featureFactory.makeRoutineDomainsSheet(draftID: draftID)
        }
    }

    @ViewBuilder
    func fullScreen(for route: FullScreenRoute) -> some View {
        switch route {
        case .pause(let context):
            featureFactory.makePauseView(context: context)

        case .activeRoutine(let id):
            featureFactory.makeActiveRoutine(routineID: id)
        }
    }
}
