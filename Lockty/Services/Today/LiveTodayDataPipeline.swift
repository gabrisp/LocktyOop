import FamilyControls
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
        perspectiveAnalyzer: DailyPerspectiveAnalyzing = DailyPerspectiveAnalyzer()
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
    }

    func dayState(for day: Date) async -> TodayDayState {
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: day)
        let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart
        do {
            let summary = try await usageDataService.usageSummary(for: dayStart)
            let snapshot = try? appGroupStore.loadScreenTimeReportSnapshot(for: DayKey(date: dayStart))
            let runtimeState = try? appGroupStore.loadRuntimeState()

            let pauseEvents = await pauseEventRepository.events(from: dayStart, to: dayEnd)
            let routineExecutions = (try? await routineExecutionRepository.executions(from: dayStart, to: dayEnd)) ?? []
            let timelineBuckets = makeTimelineBuckets(
                snapshot: snapshot,
                dayStart: dayStart,
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
            let rawDebugText = makeRawDebugText(
                day: dayStart,
                loadingState: .loaded,
                summary: summary,
                snapshot: snapshot,
                pauseEvents: pauseEvents,
                routineExecutions: routineExecutions,
                timelineBuckets: timelineBuckets,
                errorMessage: nil
            )
            print(rawDebugText)

            return TodayDayState(
                day: dayStart,
                loadingState: .loaded,
                rawDebugText: rawDebugText,
                activeRoutineChecklist: makeActiveRoutineChecklist(day: dayStart, runtimeState: runtimeState),
                primaryMetrics: PrimaryMetricsState(
                    metrics: [
                        PrimaryMetric(kind: .productivity, value: productivityResult.rawValue ?? 0),
                        PrimaryMetric(kind: .control, value: controlResult.rawValue),
                        PrimaryMetric(kind: .detox, value: detoxResult.rawValue)
                    ]
                ),
                perspective: perspective,
                perspectives: makePerspectiveStack(
                    primary: perspective,
                    mostProductiveBucket: mostProductiveBucket,
                    distractionBucket: distractionBucket,
                    leadingDistractionApps: summary.applications
                        .filter { $0.classification == .unproductive }
                        .sorted { $0.duration > $1.duration }
                        .prefix(2)
                        .map { $0.app.displayName },
                    bestDetoxDuration: bestDetox.duration
                ),
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
                }
            )
        } catch {
            print("Today pipeline falling back to partial unavailable state for \(DayKey(date: dayStart).id): \(error.localizedDescription)")
            return await unavailableState(day: dayStart, dayEnd: dayEnd, message: error.localizedDescription)
        }
    }

    func updateClassification(appID: AppIdentity.ID, classification: AppClassification) async {
        await classificationRepository.saveClassification(classification, for: appID)
    }

    /// One bucket per hour of the day, always 24 of them.
    ///
    /// The chart draws buckets as an evenly spaced row and positions its overlay bands
    /// by real time of day, so buckets have to be a fixed time grid too -- emitting one
    /// bucket per raw activity segment put a 3am segment right next to a 10pm one, which
    /// made the bars, the bands and the 00/06/12/18/24 axis three different x scales.
    /// A segment spanning several hours has its time split across them by overlap.
    private func makeTimelineBuckets(
        snapshot: ScreenTimeReportSnapshot?,
        dayStart: Date,
        classifications: [AppIdentity.ID: AppClassification]
    ) -> [UsageTimelineBucket] {
        guard let snapshot else { return [] }

        let calendar = Calendar.current
        let hourStarts: [Date] = (0..<24).compactMap {
            calendar.date(byAdding: .hour, value: $0, to: dayStart)
        }
        guard hourStarts.count == 24 else { return [] }

        var productive = [TimeInterval](repeating: 0, count: 24)
        var neutral = [TimeInterval](repeating: 0, count: 24)
        var unproductive = [TimeInterval](repeating: 0, count: 24)

        for segment in snapshot.activitySegments {
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

            let span = segment.dateInterval.duration
            for hour in 0..<24 where span > 0 {
                let hourStart = hourStarts[hour]
                let hourEnd = hourStart.addingTimeInterval(3600)
                let overlapStart = max(segment.dateInterval.start, hourStart)
                let overlapEnd = min(segment.dateInterval.end, hourEnd)
                let overlap = overlapEnd.timeIntervalSince(overlapStart)
                guard overlap > 0 else { continue }

                let share = overlap / span
                productive[hour] += totals.productive * share
                neutral[hour] += totals.neutral * share
                unproductive[hour] += totals.unproductive * share
            }

            // A zero-length segment overlaps no hour at all, but still carries
            // durations, so it lands whole in the hour it started in.
            if span <= 0, let hour = hourStarts.lastIndex(where: { $0 <= segment.dateInterval.start }) {
                productive[hour] += totals.productive
                neutral[hour] += totals.neutral
                unproductive[hour] += totals.unproductive
            }
        }

        return (0..<24).map { hour in
            UsageTimelineBucket(
                start: hourStarts[hour],
                end: hourStarts[hour].addingTimeInterval(3600),
                productive: productive[hour],
                neutral: neutral[hour],
                unproductive: unproductive[hour],
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

    private func unavailableState(day: Date, dayEnd: Date, message: String) async -> TodayDayState {
        let pauseEvents = await pauseEventRepository.events(from: day, to: dayEnd)
        let routineExecutions = (try? await routineExecutionRepository.executions(from: day, to: dayEnd)) ?? []
        let snapshot = try? appGroupStore.loadScreenTimeReportSnapshot(for: DayKey(date: day))
        let runtimeState = try? appGroupStore.loadRuntimeState()

        let completedRoutineTasks = routineExecutions.flatMap(\.taskCompletions).filter { $0.completedAt != nil }.count
        let totalRoutineTasks = routineExecutions.flatMap(\.taskCompletions).count
        let completedRoutines = routineExecutions.filter { $0.endedAt != nil }.count
        let pauseSummary = PauseSuccessCalculator().summary(from: pauseEvents)
        let routineCompletionRate = totalRoutineTasks == 0 ? (completedRoutines > 0 ? 1 : 0) : Double(completedRoutineTasks) / Double(totalRoutineTasks)
        let pauseAbandonmentRate = pauseSummary.decisionCount == 0 ? 0 : Double(pauseSummary.stoppedCount) / Double(pauseSummary.decisionCount)
        let restrictionAdherenceRate = max(0, 1 - (Double(pauseSummary.continuedCount) / Double(max(pauseSummary.triggeredCount, 1))))
        let controlResult = controlCalculator.score(
            from: ControlScoreInput(
                routineCompletionRate: routineCompletionRate,
                pauseAbandonmentRate: pauseAbandonmentRate,
                restrictionAdherenceRate: restrictionAdherenceRate,
                fragmentedUsagePenalty: 0
            )
        )
        let activities = makeDigitalActivities(
            dayStart: day,
            dayEnd: dayEnd,
            timelineBuckets: [],
            routineExecutions: routineExecutions,
            pauseEvents: pauseEvents,
            bestDetoxDuration: 0
        )
        let rawDebugText = makeRawDebugText(
            day: day,
            loadingState: .unavailable(message),
            summary: nil,
            snapshot: snapshot,
            pauseEvents: pauseEvents,
            routineExecutions: routineExecutions,
            timelineBuckets: [],
            errorMessage: message
        )
        print(rawDebugText)

        return TodayDayState(
            day: day,
            loadingState: .unavailable(message),
            rawDebugText: rawDebugText,
            activeRoutineChecklist: makeActiveRoutineChecklist(day: day, runtimeState: runtimeState),
            primaryMetrics: PrimaryMetricsState(
                metrics: [
                    PrimaryMetric(kind: .productivity, value: 0),
                    PrimaryMetric(kind: .control, value: controlResult.rawValue),
                    PrimaryMetric(kind: .detox, value: 0)
                ]
            ),
            perspective: DailyPerspective(
                id: "primary",
                title: "Usage data unavailable",
                body: "Lockty still shows routine and Pause events for this day, but Screen Time usage has not been delivered yet.",
                tone: .balanced
            ),
            perspectives: [
                DailyPerspective(
                    id: "primary",
                    title: "Usage data unavailable",
                    body: "Lockty still shows routine and Pause events for this day, but Screen Time usage has not been delivered yet.",
                    tone: .balanced
                ),
                DailyPerspective(
                    id: "fallback-routines",
                    title: "Lockty events are still visible",
                    body: "Routine runs, breaks and Pause decisions already recorded for this day still appear normally.",
                    tone: .focused
                ),
                DailyPerspective(
                    id: "fallback-retry",
                    title: "Still retrying Screen Time",
                    body: "The app is retrying direct usage access and any cached report available for this date.",
                    tone: .distracted
                )
            ],
            activities: activities,
            metrics: TodayMetricsState(
                screenTime: ScreenTimeCardState(durationText: "--", comparisonText: "Waiting for Screen Time data"),
                bestDetox: BestDetoxCardState(durationText: "--", comparisonText: "Needs activity data"),
                routines: RoutineSummaryCardState(
                    valueText: routineSummaryValue(completedRoutines: completedRoutines, totalRoutines: routineExecutions.count),
                    detailText: routineSummaryDetail(completedTasks: completedRoutineTasks, totalTasks: totalRoutineTasks)
                ),
                distractions: DistractionsCardState(
                    valueText: "\(pauseEvents.count)",
                    comparisonText: "Measured from Lockty events"
                ),
                pauseSuccess: PauseSuccessDayCardState(
                    valueText: pauseSummary.successRateValue.map { "\($0)%" } ?? "--",
                    detailText: "\(pauseSummary.stoppedCount) of \(pauseSummary.triggeredCount) stopped"
                ),
                intentionalTime: IntentionalTimeCardState(
                    valueText: "--",
                    detailText: "Needs Screen Time usage data"
                )
            ),
            timeline: .empty,
            appUsages: []
        )
    }

    private func makeActiveRoutineChecklist(day: Date, runtimeState: RuntimeState?) -> ActiveRoutineChecklistState? {
        guard Calendar.current.isDateInToday(day) else { return nil }
        guard let activeRoutine = runtimeState?.activeRoutine else { return nil }
        guard !activeRoutine.taskCompletions.isEmpty else { return nil }

        let sortedItems = activeRoutine.taskCompletions.sorted { $0.orderSnapshot < $1.orderSnapshot }
        let completedCount = sortedItems.filter { $0.completedAt != nil }.count

        return ActiveRoutineChecklistState(
            id: activeRoutine.id,
            routineID: activeRoutine.routineID,
            title: activeRoutine.nameSnapshot,
            subtitle: "\(completedCount) of \(sortedItems.count) completed",
            completedCount: completedCount,
            totalCount: sortedItems.count,
            items: sortedItems.map {
                ActiveRoutineChecklistItemState(
                    id: $0.taskID,
                    title: $0.titleSnapshot,
                    isCompleted: $0.completedAt != nil,
                    completedAtText: $0.completedAt?.formatted(date: .omitted, time: .shortened)
                )
            }
        )
    }

    /// Only builds the cards whose data actually exists. Emitting all of them
    /// unconditionally produced confident sentences about nothing — "landed around No
    /// clear period", "best detox was 0m from your unproductive apps" — which read as
    /// real findings.
    private func makePerspectiveStack(
        primary: DailyPerspective,
        mostProductiveBucket: UsageTimelineBucket?,
        distractionBucket: UsageTimelineBucket?,
        leadingDistractionApps: [String],
        bestDetoxDuration: TimeInterval?
    ) -> [DailyPerspective] {
        var perspectives = [primary]

        if let mostProductiveBucket {
            perspectives.append(
                DailyPerspective(
                    id: "focus-window",
                    title: "Focus window",
                    body: "Your strongest focused stretch landed around \(timeRangeText(start: mostProductiveBucket.start, end: mostProductiveBucket.end)).",
                    tone: .focused
                )
            )
        }

        if let bestDetoxDuration, bestDetoxDuration > 0 {
            let detoxText = LocktyDurationFormatter.abbreviated(bestDetoxDuration)
            var body = "Your longest phone-free stretch was \(detoxText)."

            // The distraction half only gets appended when there's something concrete to
            // name, so the sentence never trails off into a placeholder.
            if let distractionBucket, !leadingDistractionApps.isEmpty {
                body += " Distraction pressure rose near \(timeRangeText(start: distractionBucket.start, end: distractionBucket.end)) from \(leadingDistractionApps.joined(separator: " and "))."
            }

            perspectives.append(
                DailyPerspective(
                    id: "detox-distraction",
                    title: "Detox and drift",
                    body: body,
                    tone: .balanced
                )
            )
        } else if let distractionBucket, !leadingDistractionApps.isEmpty {
            perspectives.append(
                DailyPerspective(
                    id: "detox-distraction",
                    title: "Drift",
                    body: "Distraction pressure rose near \(timeRangeText(start: distractionBucket.start, end: distractionBucket.end)) from \(leadingDistractionApps.joined(separator: " and ")).",
                    tone: .balanced
                )
            )
        }

        return perspectives
    }

    private func makeRawDebugText(
        day: Date,
        loadingState: TodayLoadingState,
        summary: DayUsageSummary?,
        snapshot: ScreenTimeReportSnapshot?,
        pauseEvents: [PauseEvent],
        routineExecutions: [RoutineExecution],
        timelineBuckets: [UsageTimelineBucket],
        errorMessage: String?
    ) -> String {
        let key = DayKey(date: day)
        let authStatus = AuthorizationCenter.shared.authorizationStatus
        let allSnapshotCount = appGroupStore.loadAllScreenTimeReportSnapshots().count
        var lines: [String] = []
        lines.append("day=\(key.id)")
        lines.append("loadingState=\(String(describing: loadingState))")
        lines.append("authorizationStatus=\(authStatus.description)")
        if #available(iOS 26.4, *) {
            lines.append("approvedWithDataAccess=\(authStatus == .approvedWithDataAccess)")
        } else {
            lines.append("approvedWithDataAccess=unsupported_before_iOS_26_4")
        }
        lines.append("snapshotCachedForDay=\(snapshot != nil)")
        lines.append("allSnapshotsCached=\(allSnapshotCount)")
        lines.append("pauseEvents=\(pauseEvents.count)")
        lines.append("routineExecutions=\(routineExecutions.count)")
        lines.append("timelineBuckets=\(timelineBuckets.count)")

        if let errorMessage {
            lines.append("error=\(errorMessage)")
        }

        if let summary {
            lines.append("summary.totalUsage=\(summary.totalUsage)")
            lines.append("summary.applications=\(summary.applications.count)")
            for (index, app) in summary.applications.enumerated() {
                lines.append("app[\(index)]=\(app.app.displayName) bundle=\(app.app.bundleIdentifier ?? "nil") duration=\(app.duration) classification=\(app.classification.rawValue)")
            }
        } else {
            lines.append("summary=nil")
        }

        if let snapshot {
            lines.append("snapshot.totalActivityDuration=\(snapshot.totalActivityDuration)")
            lines.append("snapshot.totalPickupsWithoutApplicationActivity=\(snapshot.totalPickupsWithoutApplicationActivity)")
            lines.append("snapshot.firstPickup=\(snapshot.firstPickup?.description ?? "nil")")
            lines.append("snapshot.lastUpdatedAt=\(snapshot.lastUpdatedAt)")
            lines.append("snapshot.applications=\(snapshot.applications.count)")
            for (index, app) in snapshot.applications.enumerated() {
                lines.append("snapshot.app[\(index)]=\(app.app.displayName) bundle=\(app.app.bundleIdentifier ?? "nil") duration=\(app.totalActivityDuration) pickups=\(app.pickups) notifications=\(app.notifications)")
            }
            lines.append("snapshot.segments=\(snapshot.activitySegments.count)")
            for (index, segment) in snapshot.activitySegments.enumerated() {
                lines.append("segment[\(index)]=\(segment.dateInterval.start) -> \(segment.dateInterval.end) total=\(segment.totalActivityDuration) pickupsWithoutApp=\(segment.totalPickupsWithoutApplicationActivity) appDurations=\(segment.applicationDurations.count)")
            }
            lines.append("snapshot.webDomains=\(snapshot.webDomains.count)")
            for (index, domain) in snapshot.webDomains.enumerated() {
                lines.append("domain[\(index)]=\(domain.domain) duration=\(domain.totalActivityDuration)")
            }
        } else {
            lines.append("snapshot=nil")
        }

        if !pauseEvents.isEmpty {
            for (index, event) in pauseEvents.enumerated() {
                lines.append("pause[\(index)]=app=\(event.application.displayName) decision=\(event.decision.rawValue) triggeredAt=\(event.triggeredAt) completedAt=\(event.completedAt?.description ?? "nil") intention=\(event.intention ?? "nil")")
            }
        }

        if !routineExecutions.isEmpty {
            for (index, execution) in routineExecutions.enumerated() {
                lines.append("routine[\(index)]=\(execution.routineName) startedAt=\(execution.startedAt) endedAt=\(execution.endedAt?.description ?? "nil") tasks=\(execution.taskCompletions.count) breaks=\(execution.breakHistory.count)")
            }
        }

        return lines.joined(separator: "\n")
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
