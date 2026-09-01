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

        // Typed, not left to inference: `5 * 60` on its own is an Int, and comparing an
        // Int against an Optional<TimeInterval> is false however right the number is.
        #expect(baseline?.baselineAverageDailyUsage == TimeInterval(5 * 60))
        #expect(baseline?.currentAverageDailyUsage == TimeInterval(9 * 60))
        #expect(baseline?.deltaPerDay == TimeInterval(-4 * 60))
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
    func openCountRuleShieldsUntilAPassIsAvailableAgain() {
        let rule = Rule(
            name: "Instagram",
            kind: .openCountLimit,
            openCountLimitConfiguration: OpenCountLimitRuleConfiguration(maximumOpens: 2, windowHours: 24)
        )

        var enforcement = RuleEnforcementState()
        #expect(rule.remainingOpens(given: enforcement) == 2)
        // The apps stay shielded throughout: the shield is what counts the opens, so it
        // has to be there even while passes remain.
        #expect(rule.isShielding(given: enforcement) == true)

        enforcement.update(rule.id) { $0.openCountUsed = 2 }
        #expect(rule.remainingOpens(given: enforcement) == 0)
        #expect(rule.isShielding(given: enforcement) == true)
    }

    @Test
    func openCountResetsOnTheNextDay() {
        let rule = Rule(
            name: "Instagram",
            kind: .openCountLimit,
            openCountLimitConfiguration: OpenCountLimitRuleConfiguration(maximumOpens: 3, windowHours: 24)
        )

        let yesterday = Date().addingTimeInterval(-24 * 60 * 60)
        var enforcement = RuleEnforcementState()
        enforcement.update(rule.id, on: yesterday) { $0.openCountUsed = 3 }

        #expect(rule.remainingOpens(given: enforcement, on: yesterday) == 0)
        // Same stored record, read on a different day: yesterday's count buys nothing.
        #expect(rule.remainingOpens(given: enforcement) == 3)
    }

    @Test
    func dailyUsageRuleOnlyShieldsOnceItsBudgetIsSpent() {
        let rule = Rule(
            name: "TikTok",
            kind: .dailyUsageLimit,
            dailyUsageLimitConfiguration: DailyUsageLimitRuleConfiguration(
                maximumMinutesPerDay: 30,
                resetPeriod: .daily
            )
        )

        var enforcement = RuleEnforcementState()
        #expect(rule.isShielding(given: enforcement) == false)

        enforcement.update(rule.id) { $0.usageLimitReachedAt = Date() }
        #expect(rule.isShielding(given: enforcement) == true)
    }

    @Test
    func sessionRuleGrantsItsConfiguredMinutesPerPass() {
        let rule = Rule(
            name: "YouTube",
            kind: .sessionDurationLimit,
            sessionDurationLimitConfiguration: SessionDurationLimitRuleConfiguration(
                maximumMinutesPerSession: 12
            )
        )

        #expect(rule.allowanceMinutesPerPass == 12)
        #expect(rule.remainingOpens(given: RuleEnforcementState()) == nil)
    }

    @Test
    func disabledRuleShieldsNothing() {
        let rule = Rule(
            name: "Off",
            isEnabled: false,
            kind: .sessionDurationLimit,
            sessionDurationLimitConfiguration: SessionDurationLimitRuleConfiguration(
                maximumMinutesPerSession: 5
            )
        )

        #expect(rule.isShielding(given: RuleEnforcementState()) == false)
    }

    @Test
    func scheduleRuleIsLeftToTheRoutineEngine() {
        let rule = Rule(routine: .mockDeepWork)

        #expect(rule.kind == .schedule)
        // Its shield comes from the active routine, not from the rule layer -- counting
        // it in both places would apply the same block twice.
        #expect(rule.isShielding(given: RuleEnforcementState()) == false)
    }

    @Test
    func shieldIsTheUnionOfEveryRunningRoutine() {
        let deepWork = ActiveRoutine(
            routineID: UUID(),
            nameSnapshot: "Deep work",
            modeSnapshot: .normal,
            startedAt: Date(),
            trigger: .manual,
            shieldPolicy: ShieldPolicy(
                blockedApplications: ["instagram", "reddit"],
                blockedDomains: [],
                reason: .routine(UUID())
            ),
            breakPolicySnapshot: .none,
            taskCompletions: [],
            allowsPauseDuringStrictMode: false
        )
        let evening = ActiveRoutine(
            routineID: UUID(),
            nameSnapshot: "Evening",
            modeSnapshot: .normal,
            startedAt: Date(),
            trigger: .manual,
            shieldPolicy: ShieldPolicy(
                blockedApplications: ["reddit", "youtube"],
                blockedDomains: [],
                reason: .routine(UUID())
            ),
            breakPolicySnapshot: .none,
            taskCompletions: [],
            allowsPauseDuringStrictMode: false
        )

        let policy = ShieldPolicyResolver().resolve(
            activeRoutines: [deepWork, evening],
            activeBreaks: [],
            activePauseAllowance: nil,
            pauseRules: []
        )

        #expect(policy.blockedApplications == ["instagram", "reddit", "youtube"])
    }

    @Test
    func endingOneRoutineLeavesWhatTheOtherStillBlocks() {
        let deepWork = ActiveRoutine(
            routineID: UUID(),
            nameSnapshot: "Deep work",
            modeSnapshot: .normal,
            startedAt: Date(),
            trigger: .manual,
            shieldPolicy: ShieldPolicy(
                blockedApplications: ["instagram", "reddit"],
                blockedDomains: [],
                reason: .routine(UUID())
            ),
            breakPolicySnapshot: .none,
            taskCompletions: [],
            allowsPauseDuringStrictMode: false
        )
        let evening = ActiveRoutine(
            routineID: UUID(),
            nameSnapshot: "Evening",
            modeSnapshot: .normal,
            startedAt: Date(),
            trigger: .manual,
            shieldPolicy: ShieldPolicy(
                blockedApplications: ["reddit", "youtube"],
                blockedDomains: [],
                reason: .routine(UUID())
            ),
            breakPolicySnapshot: .none,
            taskCompletions: [],
            allowsPauseDuringStrictMode: false
        )

        // Deep work is over; only Evening is left.
        let policy = ShieldPolicyResolver().resolve(
            activeRoutines: [evening],
            activeBreaks: [],
            activePauseAllowance: nil,
            pauseRules: []
        )

        _ = deepWork
        // Instagram was only Deep work's, so it comes free. Reddit was both routines',
        // and Evening never agreed to release it.
        #expect(policy.blockedApplications.contains("instagram") == false)
        #expect(policy.blockedApplications.contains("reddit"))
    }

    @Test
    func aBreakLiftsOnlyItsOwnRoutine() {
        let deepWorkID = UUID()
        let deepWork = ActiveRoutine(
            routineID: deepWorkID,
            nameSnapshot: "Deep work",
            modeSnapshot: .normal,
            startedAt: Date(),
            trigger: .manual,
            shieldPolicy: ShieldPolicy(
                blockedApplications: ["instagram", "reddit"],
                blockedDomains: [],
                reason: .routine(deepWorkID)
            ),
            breakPolicySnapshot: .none,
            taskCompletions: [],
            allowsPauseDuringStrictMode: false
        )
        let eveningID = UUID()
        let evening = ActiveRoutine(
            routineID: eveningID,
            nameSnapshot: "Evening",
            modeSnapshot: .normal,
            startedAt: Date(),
            trigger: .manual,
            shieldPolicy: ShieldPolicy(
                blockedApplications: ["reddit"],
                blockedDomains: [],
                reason: .routine(eveningID)
            ),
            breakPolicySnapshot: .none,
            taskCompletions: [],
            allowsPauseDuringStrictMode: false
        )

        let policy = ShieldPolicyResolver().resolve(
            activeRoutines: [deepWork, evening],
            activeBreaks: [
                ActiveBreak(
                    routineID: deepWorkID,
                    startedAt: Date(),
                    endsAt: Date().addingTimeInterval(600),
                    trigger: .manual
                )
            ],
            activePauseAllowance: nil,
            pauseRules: []
        )

        // Deep work is on a break, so what only it blocked is free.
        #expect(policy.blockedApplications.contains("instagram") == false)
        // Reddit is not: Evening is still running and never granted anything.
        #expect(policy.blockedApplications.contains("reddit"))
    }

    @Test
    func runtimeStateDecodesAStateWrittenWhenOnlyOneRoutineCouldRun() throws {
        let legacy = """
        {
          "activeRoutine": {
            "id": "\(UUID().uuidString)",
            "routineID": "\(UUID().uuidString)",
            "nameSnapshot": "Deep work",
            "modeSnapshot": "strict",
            "startedAt": 0,
            "trigger": { "manual": {} },
            "shieldPolicy": {
              "blockedApplications": ["instagram"],
              "blockedDomains": [],
              "reason": { "none": {} }
            },
            "breakPolicySnapshot": {
              "maximumBreaks": 0,
              "maximumDuration": 0,
              "minimumInterval": 0,
              "allowedTriggers": []
            },
            "taskCompletions": [],
            "allowsPauseDuringStrictMode": false
          },
          "shieldPolicy": {
            "blockedApplications": [],
            "blockedDomains": [],
            "reason": { "none": {} }
          },
          "pendingEvents": [],
          "recoveryFlags": [],
          "lastUpdatedAt": 0
        }
        """

        let state = try JSONDecoder().decode(RuntimeState.self, from: Data(legacy.utf8))

        // The single routine that was in flight when the app updated is carried over
        // rather than thrown away, which would have left its shields up with nothing
        // pointing at them.
        #expect(state.activeRoutines.count == 1)
        #expect(state.activeRoutines.first?.nameSnapshot == "Deep work")
        #expect(state.activeBreaks.isEmpty)
    }

    @Test
    func strictModeAllowsManualStop() {
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

        #expect(decision.isAllowed == true)
    }

    @Test
    func strictModeStillDeniesEditing() {
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
            for: .editRoutine,
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
