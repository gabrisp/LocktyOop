import Foundation

protocol TodayDataProviding {
    func dayState(for day: Date) async -> TodayDayState
    func updateClassification(appID: AppIdentity.ID, classification: AppClassification) async
}

struct LiveTodayDataPipeline: TodayDataProviding {
    private let usageDataService: UsageDataServicing
    private let appGroupStore: AppGroupStore
    private let classificationRepository: AppClassificationRepository
    private let pauseEventRepository: PauseEventRepository
    private let routineExecutionRepository: RoutineExecutionRepository
    private let productivityCalculator: ProductivityScoring
    private let controlCalculator: ControlScoreCalculating
    private let detoxCalculator: DetoxScoreCalculating
    private let distractionCalculator: DistractionMetricCalculating
    private let intentionalTimeCalculator: IntentionalTimeCalculating
    private let bestDetoxCalculator: BestDetoxCalculator
    private let perspectiveAnalyzer: DailyPerspectiveAnalyzing
    private let patternAnalyzer: PatternAnalyzing

    init(
        usageDataService: UsageDataServicing,
        appGroupStore: AppGroupStore,
        classificationRepository: AppClassificationRepository,
        pauseEventRepository: PauseEventRepository,
        routineExecutionRepository: RoutineExecutionRepository,
        productivityCalculator: ProductivityScoring = WeightedProductivityScoreCalculator(),
        controlCalculator: ControlScoreCalculating = ControlScoreCalculator(),
        detoxCalculator: DetoxScoreCalculating = DetoxScoreCalculator(),
        distractionCalculator: DistractionMetricCalculating = DistractionMetricCalculator(),
        intentionalTimeCalculator: IntentionalTimeCalculating = IntentionalTimeCalculator(),
        bestDetoxCalculator: BestDetoxCalculator = BestDetoxCalculator(),
        perspectiveAnalyzer: DailyPerspectiveAnalyzing = DailyPerspectiveAnalyzer(),
        patternAnalyzer: PatternAnalyzing = PatternAnalyzer()
    ) {
        self.usageDataService = usageDataService
        self.appGroupStore = appGroupStore
        self.classificationRepository = classificationRepository
        self.pauseEventRepository = pauseEventRepository
        self.routineExecutionRepository = routineExecutionRepository
        self.productivityCalculator = productivityCalculator
        self.controlCalculator = controlCalculator
        self.detoxCalculator = detoxCalculator
        self.distractionCalculator = distractionCalculator
        self.intentionalTimeCalculator = intentionalTimeCalculator
        self.bestDetoxCalculator = bestDetoxCalculator
        self.perspectiveAnalyzer = perspectiveAnalyzer
        self.patternAnalyzer = patternAnalyzer
    }

    func dayState(for day: Date) async -> TodayDayState {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        do {
            let summary = try await usageDataService.usageSummary(for: dayStart)
            let snapshot = try? appGroupStore.loadScreenTimeReportSnapshot(for: DayKey(date: dayStart))

            let pauseEvents = await pauseEventRepository.events(from: dayStart, to: dayEnd)
            let routineExecutions = (try? await routineExecutionRepository.executions(from: dayStart, to: dayEnd)) ?? []
            let timelineBuckets = makeTimelineBuckets(
                snapshot: snapshot,
                classifications: Dictionary(uniqueKeysWithValues: summary.applications.map { ($0.app.id, $0.classification) })
            )
            let bestDetox = bestDetoxCalculator.longestInactivePeriod(
                usageIntervals: (snapshot?.activitySegments ?? []).map(\.dateInterval).map { UsageActivityInterval(start: $0.start, end: $0.end) },
                dayStart: dayStart,
                dayEnd: dayEnd
            )

            let productiveUsage = summary.applications
                .filter { $0.classification == .productive }
                .reduce(0) { $0 + $1.duration }
            let neutralUsage = summary.applications
                .filter { $0.classification == .neutral }
                .reduce(0) { $0 + $1.duration }
            let productivityResult = productivityCalculator.score(
                for: summary.applications.map {
                    ClassifiedUsageDuration(duration: $0.duration, classification: $0.classification)
                }
            )

            let completedRoutineTasks = routineExecutions.flatMap(\.taskCompletions).filter { $0.completedAt != nil }.count
            let totalRoutineTasks = routineExecutions.flatMap(\.taskCompletions).count
            let completedRoutines = routineExecutions.filter { $0.endedAt != nil }.count
            let pauseSummary = PauseSuccessCalculator().summary(from: pauseEvents)
            let unproductiveBursts = timelineBuckets.filter { $0.unproductive > (10 * 60) }.count
            let repeatedPauseAttempts = max(0, pauseEvents.count - Set(pauseEvents.map(\.application.id)).count)
            let distractionCount = distractionCalculator.count(
                from: DistractionMetricInput(
                    restrictedAccessAttempts: pauseEvents.count,
                    unproductiveBursts: unproductiveBursts,
                    repeatedAttempts: repeatedPauseAttempts
                )
            )

            let routineCompletionRate = totalRoutineTasks == 0 ? (completedRoutines > 0 ? 1 : 0) : Double(completedRoutineTasks) / Double(totalRoutineTasks)
            let pauseAbandonmentRate = pauseSummary.decisionCount == 0 ? 0 : Double(pauseSummary.stoppedCount) / Double(pauseSummary.decisionCount)
            let restrictionAdherenceRate = max(0, 1 - (Double(pauseSummary.continuedCount) / Double(max(pauseSummary.triggeredCount, 1))))
            let fragmentedUsagePenalty = min(Double(snapshot?.activitySegments.count ?? 0) / 2, 18)
            let controlResult = controlCalculator.score(
                from: ControlScoreInput(
                    routineCompletionRate: routineCompletionRate,
                    pauseAbandonmentRate: pauseAbandonmentRate,
                    restrictionAdherenceRate: restrictionAdherenceRate,
                    fragmentedUsagePenalty: fragmentedUsagePenalty
                )
            )

            let meaningfulPhoneFreeTime = dayEnd.timeIntervalSince(dayStart) - summary.totalUsage
            let detoxResult = detoxCalculator.score(
                from: DetoxScoreInput(
                    longestPhoneFreeInterval: bestDetox.duration ?? 0,
                    meaningfulPhoneFreeTime: meaningfulPhoneFreeTime,
                    interruptionCount: snapshot?.activitySegments.count ?? 0
                )
            )

            let intentionalTime = intentionalTimeCalculator.intentionalTime(
                from: IntentionalTimeInput(
                    productiveUsage: productiveUsage,
                    neutralUsage: neutralUsage,
                    routineUsage: routineExecutions.reduce(0) {
                        $0 + (($1.endedAt ?? dayEnd).timeIntervalSince($1.startedAt))
                    },
                    successfulPauseCount: pauseSummary.stoppedCount
                )
            )

            let activities = makeDigitalActivities(
                dayStart: dayStart,
                dayEnd: dayEnd,
                timelineBuckets: timelineBuckets,
                routineExecutions: routineExecutions,
                pauseEvents: pauseEvents,
                bestDetoxDuration: bestDetox.duration ?? 0
            )

            let patterns = patternAnalyzer.patterns(
                from: PatternInput(
                    productivityScore: productivityResult.roundedValue ?? 0,
                    controlScore: controlResult.roundedValue,
                    longestDetoxText: LocktyDurationFormatter.abbreviated(bestDetox.duration ?? 0),
                    completedRoutines: completedRoutines,
                    totalRoutines: max(routineExecutions.count, completedRoutines)
                )
            )

            let mostProductiveBucket = timelineBuckets.max(by: { $0.productive < $1.productive })
            let distractionBucket = timelineBuckets.max(by: { $0.unproductive < $1.unproductive })
            let perspective = perspectiveAnalyzer.perspective(
                from: DailyPerspectiveInput(
                    productivityScore: productivityResult.roundedValue ?? 0,
                    controlScore: controlResult.roundedValue,
                    detoxScore: detoxResult.roundedValue,
                    mostProductivePeriodText: timeRangeText(start: mostProductiveBucket?.start, end: mostProductiveBucket?.end),
                    distractionPeriodText: timeRangeText(start: distractionBucket?.start, end: distractionBucket?.end),
                    leadingDistractionApps: summary.applications
                        .filter { $0.classification == .unproductive }
                        .sorted { $0.duration > $1.duration }
                        .prefix(2)
                        .map { $0.app.displayName }
                )
            )

            let averageUsage = await rollingAverageUsage(endingBefore: dayStart, days: 7)
            let averageDistractions = await rollingAveragePauseEvents(endingBefore: dayStart, days: 7)

            return TodayDayState(
                day: dayStart,
                loadingState: .loaded,
                primaryMetrics: PrimaryMetricsState(
                    metrics: [
                        PrimaryMetric(kind: .productivity, value: productivityResult.rawValue ?? 0),
                        PrimaryMetric(kind: .control, value: controlResult.rawValue),
                        PrimaryMetric(kind: .detox, value: detoxResult.rawValue)
                    ]
                ),
                perspective: perspective,
                activities: activities,
                metrics: TodayMetricsState(
                    screenTime: ScreenTimeCardState(
                        durationText: LocktyDurationFormatter.abbreviated(summary.totalUsage),
                        comparisonText: usageComparisonText(current: summary.totalUsage, average: averageUsage)
                    ),
                    bestDetox: BestDetoxCardState(
                        durationText: LocktyDurationFormatter.abbreviated(bestDetox.duration ?? 0),
                        comparisonText: bestDetoxComparisonText(duration: bestDetox.duration)
                    ),
                    routines: RoutineSummaryCardState(
                        valueText: routineSummaryValue(completedRoutines: completedRoutines, totalRoutines: routineExecutions.count),
                        detailText: routineSummaryDetail(completedTasks: completedRoutineTasks, totalTasks: totalRoutineTasks)
                    ),
                    distractions: DistractionsCardState(
                        valueText: "\(distractionCount)",
                        comparisonText: deltaText(current: Double(distractionCount), average: averageDistractions, unitSuffix: "")
                    ),
                    pauseSuccess: PauseSuccessDayCardState(
                        valueText: pauseSummary.successRateValue.map { "\($0)%" } ?? "--",
                        detailText: "\(pauseSummary.stoppedCount) of \(pauseSummary.triggeredCount) stopped"
                    ),
                    intentionalTime: IntentionalTimeCardState(
                        valueText: LocktyDurationFormatter.abbreviated(intentionalTime),
                        detailText: intentionalTimeDetailText(intentionalTime: intentionalTime, totalUsage: summary.totalUsage)
                    )
                ),
                timeline: UsageTimelineChartState(
                    buckets: timelineBuckets,
                    overlays: activities.map {
                        UsageTimelineOverlay(
                            id: $0.id,
                            startDate: $0.startDate,
                            endDate: $0.endDate,
                            title: $0.title,
                            type: $0.type
                        )
                    }
                ),
                appUsages: summary.applications.map { usage in
                    AppUsageState(
                        app: usage.app,
                        durationText: LocktyDurationFormatter.abbreviated(usage.duration),
                        duration: usage.duration,
                        classification: usage.classification,
                        comparisonText: nil
                    )
                },
                patterns: patterns
            )
        } catch {
            return unavailableState(day: dayStart, message: error.localizedDescription)
        }
    }

    func updateClassification(appID: AppIdentity.ID, classification: AppClassification) async {
        await classificationRepository.saveClassification(classification, for: appID)
    }

    private func makeTimelineBuckets(
        snapshot: ScreenTimeReportSnapshot?,
        classifications: [AppIdentity.ID: AppClassification]
    ) -> [UsageTimelineBucket] {
        guard let snapshot else { return [] }

        return snapshot.activitySegments.map { segment in
            let totals = segment.applicationDurations.reduce(into: (productive: TimeInterval(0), neutral: TimeInterval(0), unproductive: TimeInterval(0))) { partialResult, item in
                switch classifications[item.key] ?? .neutral {
                case .productive:
                    partialResult.productive += item.value
                case .neutral:
                    partialResult.neutral += item.value
                case .unproductive:
                    partialResult.unproductive += item.value
                }
            }

            return UsageTimelineBucket(
                start: segment.dateInterval.start,
                end: segment.dateInterval.end,
                productive: totals.productive,
                neutral: totals.neutral,
                unproductive: totals.unproductive,
                confidence: .inferred
            )
        }
    }

    private func makeDigitalActivities(
        dayStart: Date,
        dayEnd: Date,
        timelineBuckets: [UsageTimelineBucket],
        routineExecutions: [RoutineExecution],
        pauseEvents: [PauseEvent],
        bestDetoxDuration: TimeInterval
    ) -> [DigitalActivity] {
        var items: [DigitalActivity] = routineExecutions.map { execution in
            DigitalActivity(
                id: execution.id,
                type: .routine,
                startDate: execution.startedAt,
                endDate: execution.endedAt ?? execution.startedAt,
                title: execution.routineName,
                productivityScore: nil,
                relatedApplications: [],
                routineID: execution.routineID
            )
        }

        if let longestDetoxBucket = longestQuietGap(from: timelineBuckets, dayStart: dayStart, dayEnd: dayEnd), longestDetoxBucket.duration >= bestDetoxDuration, bestDetoxDuration > 0 {
            items.append(
                DigitalActivity(
                    id: UUID(),
                    type: .detox,
                    startDate: longestDetoxBucket.start,
                    endDate: longestDetoxBucket.end,
                    title: "Detox",
                    productivityScore: nil,
                    relatedApplications: [],
                    routineID: nil
                )
            )
        }

        items.append(contentsOf: pauseEvents.prefix(6).map { event in
            DigitalActivity(
                id: event.id,
                type: event.decision == .abandoned ? .focus : .distraction,
                startDate: event.triggeredAt,
                endDate: event.completedAt ?? event.triggeredAt,
                title: event.decision == .abandoned ? "Pause · \(event.application.displayName)" : "Distraction · \(event.application.displayName)",
                productivityScore: nil,
                relatedApplications: [event.application],
                routineID: nil
            )
        })

        return items.sorted { $0.startDate < $1.startDate }
    }

    private func longestQuietGap(
        from buckets: [UsageTimelineBucket],
        dayStart: Date,
        dayEnd: Date
    ) -> (start: Date, end: Date, duration: TimeInterval)? {
        var cursor = dayStart
        var longest: (Date, Date, TimeInterval)?

        for bucket in buckets.sorted(by: { $0.start < $1.start }) where (bucket.productive + bucket.neutral + bucket.unproductive) > 0 {
            let duration = bucket.start.timeIntervalSince(cursor)
            if longest == nil || duration > longest!.2 {
                longest = (cursor, bucket.start, duration)
            }
            cursor = bucket.end
        }

        let lastDuration = dayEnd.timeIntervalSince(cursor)
        if longest == nil || lastDuration > longest!.2 {
            longest = (cursor, dayEnd, lastDuration)
        }

        return longest
    }

    private func unavailableState(day: Date, message: String) -> TodayDayState {
        var state = TodayDayState.loading(day: day)
        state.loadingState = .unavailable(message)
        return state
    }

    private func rollingAverageUsage(endingBefore day: Date, days: Int) async -> TimeInterval {
        let calendar = Calendar.current
        let values = (1...days).compactMap { offset -> ScreenTimeReportSnapshot? in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: day) else { return nil }
            return try? appGroupStore.loadScreenTimeReportSnapshot(for: DayKey(date: date))
        }

        guard !values.isEmpty else { return 0 }
        let total = values.reduce(0) { $0 + $1.totalActivityDuration }
        return total / Double(values.count)
    }

    private func rollingAveragePauseEvents(endingBefore day: Date, days: Int) async -> Double {
        let calendar = Calendar.current
        var counts: [Int] = []
        for offset in 1...days {
            guard let date = calendar.date(byAdding: .day, value: -offset, to: day) else { continue }
            let start = calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 1, to: start) ?? start
            let events = await pauseEventRepository.events(from: start, to: end)
            counts.append(events.count)
        }

        guard !counts.isEmpty else { return 0 }
        return Double(counts.reduce(0, +)) / Double(counts.count)
    }

    private func routineSummaryValue(completedRoutines: Int, totalRoutines: Int) -> String {
        guard totalRoutines > 0 else { return "--" }
        return "\(completedRoutines)/\(totalRoutines)"
    }

    private func routineSummaryDetail(completedTasks: Int, totalTasks: Int) -> String {
        guard totalTasks > 0 else { return "No tasks completed" }
        let percentage = Int((Double(completedTasks) / Double(totalTasks) * 100).rounded())
        return "\(percentage)% completed"
    }

    private func bestDetoxComparisonText(duration: TimeInterval?) -> String {
        guard let duration, duration > 0 else { return "No phone-free interval detected" }
        return duration >= (2 * 60 * 60) ? "Strong disconnect window" : "Measured from activity gaps"
    }

    private func intentionalTimeDetailText(intentionalTime: TimeInterval, totalUsage: TimeInterval) -> String {
        guard totalUsage > 0 else { return "No relevant usage" }
        let ratio = Int(((intentionalTime / totalUsage) * 100).rounded())
        return "\(ratio)% of relevant use"
    }

    private func usageComparisonText(current: TimeInterval, average: TimeInterval) -> String {
        deltaText(current: current, average: average, unitSuffix: "")
    }

    private func deltaText(current: Double, average: Double, unitSuffix: String) -> String {
        guard average > 0 else { return "No comparison history" }
        let delta = current - average
        if abs(delta) < 1 {
            return "In line with average"
        }

        if unitSuffix.isEmpty, current > 1000 {
            let deltaDuration = LocktyDurationFormatter.abbreviated(abs(delta))
            return delta < 0 ? "\(deltaDuration) below average" : "\(deltaDuration) above average"
        }

        let percent = Int(((abs(delta) / average) * 100).rounded())
        return delta < 0 ? "\(percent)% below average" : "\(percent)% above average"
    }

    private func timeRangeText(start: Date?, end: Date?) -> String {
        guard let start, let end else { return "No clear period" }
        return "\(start.formatted(date: .omitted, time: .shortened))-\(end.formatted(date: .omitted, time: .shortened))"
    }
}
