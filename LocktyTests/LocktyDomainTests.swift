import Foundation
import Testing
@testable import Lockty

@Suite("Lockty domain logic")
struct LocktyDomainTests {
    @Test
    func productivityScoreUsesInitialWeights() {
        let calculator = WeightedProductivityScoreCalculator()
        let result = calculator.score(
            for: [
                ClassifiedUsageDuration(duration: 60, classification: .productive),
                ClassifiedUsageDuration(duration: 60, classification: .neutral),
                ClassifiedUsageDuration(duration: 60, classification: .unproductive)
            ]
        )

        #expect(result.roundedValue == 50)
    }

    @Test
    func productivityScoreReturnsNoDataForEmptyUsage() {
        let calculator = WeightedProductivityScoreCalculator()
        let result = calculator.score(for: [])

        #expect(result.roundedValue == nil)
        #expect(result.rawValue == nil)
    }

    @Test
    func controlScoreUsesBehavioralSignals() {
        let calculator = ControlScoreCalculator()
        let result = calculator.score(
            from: ControlScoreInput(
                routineCompletionRate: 0.90,
                pauseAbandonmentRate: 0.60,
                restrictionAdherenceRate: 0.78,
                fragmentedUsagePenalty: 10
            )
        )

        #expect(result.roundedValue == 71)
    }

    @Test
    func detoxScoreRewardsLongMeaningfulPhoneFreeTime() {
        let calculator = DetoxScoreCalculator()
        let result = calculator.score(
            from: DetoxScoreInput(
                longestPhoneFreeInterval: (2 * 60 * 60) + (14 * 60),
                meaningfulPhoneFreeTime: (5 * 60 * 60) + (38 * 60),
                interruptionCount: 14
            )
        )

        #expect(result.roundedValue == 68)
    }

    @Test
    func projectionCalculatorHandlesZeroUsage() {
        let projection = DigitalTimeProjectionCalculator().project(
            averageDailyUsage: 0,
            horizon: 365 * 24 * 60 * 60
        )

        #expect(projection.weeklyUsage == 0)
        #expect(projection.yearlyUsage == 0)
        #expect(projection.equivalentFullDaysPerYear == 0)
        #expect(projection.projectedUsageOverHorizon == 0)
        #expect(projection.equivalentFullYearsOverHorizon == 0)
    }

    @Test
    func projectionCalculatorConvertsOneHourPerDay() {
        let oneHourPerDay: TimeInterval = 60 * 60
        let projection = DigitalTimeProjectionCalculator().project(averageDailyUsage: oneHourPerDay)

        #expect(projection.weeklyUsage == 7 * 60 * 60)
        #expect(projection.yearlyUsage == 365 * 60 * 60)
        #expect(abs(projection.equivalentFullDaysPerYear - (365.0 / 24.0)) < 0.0001)
    }

    @Test
    func projectionCalculatorSupportsMultiYearHorizon() {
        let averageDailyUsage: TimeInterval = 91 * 60
        let tenYears: TimeInterval = 10 * 365 * 24 * 60 * 60
        let projection = DigitalTimeProjectionCalculator().project(
            averageDailyUsage: averageDailyUsage,
            horizon: tenYears
        )

        let expectedUsage = averageDailyUsage * 365 * 10
        #expect(projection.projectedUsageOverHorizon == expectedUsage)
        #expect(abs((projection.equivalentFullDaysOverHorizon ?? 0) - (expectedUsage / (24 * 60 * 60))) < 0.0001)
        #expect(abs((projection.equivalentFullYearsOverHorizon ?? 0) - (expectedUsage / (365 * 24 * 60 * 60))) < 0.0001)
    }

    @Test
    func baselineCalculatorBuildsWindowedAverages() {
        let baseline = BaselineCalculator().calculate(
            dailyUsages: [4, 6, 8, 10].map { TimeInterval($0 * 60) },
            baselineWindow: 2,
            currentWindow: 2
        )

        #expect(baseline?.baselineAverageDailyUsage == 5 * 60)
        #expect(baseline?.currentAverageDailyUsage == 9 * 60)
        #expect(baseline?.deltaPerDay == -4 * 60)
    }

    @Test
    func reclaimedTimeCalculatorRewardsImprovementOnly() {
        let reclaimed = ReclaimedTimeCalculator().reclaimedTime(
            from: ReclaimedTimeInput(
                baselineDistractingUsagePerDay: 120 * 60,
                measuredDistractingUsageByDay: [60 * 60, 150 * 60, 30 * 60]
            )
        )

        #expect(reclaimed == (60 * 60) + 0 + (90 * 60))
    }

    @Test
    func pauseSuccessCalculatorCountsStoppedAndContinued() {
        let now = Date(timeIntervalSinceReferenceDate: 0)
        let events = [
            PauseEvent(
                pauseRuleID: UUID(),
                application: AppIdentity(id: "instagram", displayName: "Instagram"),
                triggeredAt: now,
                completedAt: now,
                decision: .abandoned
            ),
            PauseEvent(
                pauseRuleID: UUID(),
                application: AppIdentity(id: "instagram", displayName: "Instagram"),
                triggeredAt: now,
                completedAt: now,
                decision: .continued
            ),
            PauseEvent(
                pauseRuleID: UUID(),
                application: AppIdentity(id: "instagram", displayName: "Instagram"),
                triggeredAt: now,
                decision: .interrupted
            )
        ]

        let summary = PauseSuccessCalculator().summary(from: events)

        #expect(summary.triggeredCount == 3)
        #expect(summary.stoppedCount == 1)
        #expect(summary.continuedCount == 1)
        #expect(summary.decisionCount == 2)
        #expect(summary.successRateValue == 50)
    }

    @Test
    func routineAdherenceCalculatorCombinesExecutionAndTaskCompletion() {
        let result = RoutineAdherenceCalculator().calculate(
            from: RoutineAdherenceInput(
                completedExecutions: 3,
                attemptedExecutions: 4,
                completedTasks: 7,
                totalTasks: 10
            )
        )

        #expect(abs(result.executionCompletionRate - 0.75) < 0.0001)
        #expect(abs(result.taskCompletionRate - 0.70) < 0.0001)
        #expect(abs(result.combinedRate - 0.7325) < 0.0001)
    }

    @Test
    func metricsHeaderGeometryClampsAndInterpolates() {
        #expect(MetricsHeaderGeometry.collapseProgress(for: -20) == 0)
        #expect(MetricsHeaderGeometry.collapseProgress(for: MetricsHeaderGeometry.collapseDistance * 2) == 1)
        #expect(MetricsHeaderGeometry.lerp(10, 30, progress: 0.5) == 20)
        #expect(MetricsHeaderGeometry.rangedProgress(0.5, from: 0.25, to: 0.75) == 0.5)
    }

    @Test
    func strictModeDeniesManualStop() {
        let routine = Routine.mockDeepWork
        let activeRoutine = ActiveRoutine(
            routineID: routine.id,
            nameSnapshot: routine.name,
            modeSnapshot: .strict,
            startedAt: Date(),
            trigger: .manual,
            shieldPolicy: .routine(routine),
            breakPolicySnapshot: routine.breakPolicy,
            taskCompletions: [],
            allowsPauseDuringStrictMode: true
        )

        let decision = StrictModePolicy().decision(
            for: .stopRoutine,
            activeRoutine: activeRoutine
        )

        #expect(decision.isAllowed == false)
    }

    @Test
    func notificationResolverRoutesPausePayload() {
        let context = PauseContext(
            pauseRuleID: UUID(),
            appID: "instagram",
            displayName: "Instagram",
            allowanceDuration: 5 * 60,
            steps: [.countdown(CountdownConfiguration(duration: 10))],
            source: .notification
        )
        let payload = NotificationPayload(
            type: .pauseRequested,
            pauseContext: context,
            idempotencyKey: "pause-instagram"
        )

        let event = NotificationRouteResolver().resolve(payload)

        #expect(event?.payload == .pauseRequested(context))
    }
}
