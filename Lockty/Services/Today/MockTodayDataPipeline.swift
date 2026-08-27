import Foundation

protocol TodayDataProviding {
    func dayState(for day: Date) async -> TodayDayState
    func updateClassification(appID: AppIdentity.ID, classification: AppClassification) async
}

final class MockTodayDataPipeline: TodayDataProviding {
    private let classificationRepository: AppClassificationRepository
    private let productivityCalculator: ProductivityScoring
    private let controlCalculator: ControlScoreCalculating
    private let detoxCalculator: DetoxScoreCalculating
    private let distractionCalculator: DistractionMetricCalculating
    private let perspectiveAnalyzer: DailyPerspectiveAnalyzing
    private let patternAnalyzer: PatternAnalyzing

    init(
        classificationRepository: AppClassificationRepository = InMemoryAppClassificationRepository(),
        productivityCalculator: ProductivityScoring = WeightedProductivityScoreCalculator(),
        controlCalculator: ControlScoreCalculating = ControlScoreCalculator(),
        detoxCalculator: DetoxScoreCalculating = DetoxScoreCalculator(),
        distractionCalculator: DistractionMetricCalculating = DistractionMetricCalculator(),
        perspectiveAnalyzer: DailyPerspectiveAnalyzing = DailyPerspectiveAnalyzer(),
        patternAnalyzer: PatternAnalyzing = PatternAnalyzer()
    ) {
        self.classificationRepository = classificationRepository
        self.productivityCalculator = productivityCalculator
        self.controlCalculator = controlCalculator
        self.detoxCalculator = detoxCalculator
        self.distractionCalculator = distractionCalculator
        self.perspectiveAnalyzer = perspectiveAnalyzer
        self.patternAnalyzer = patternAnalyzer
    }

    func dayState(for day: Date) async -> TodayDayState {
        var usages: [AppUsageState] = []

        for usage in mockUsages() {
            let classification = await classificationRepository.classification(for: usage.app.id) ?? usage.classification
            usages.append(
                AppUsageState(
                    app: usage.app,
                    durationText: LocktyDurationFormatter.abbreviated(usage.duration),
                    duration: usage.duration,
                    classification: classification,
                    comparisonText: comparisonText(for: usage.app.id)
                )
            )
        }

        usages.sort { $0.duration > $1.duration }

        let productivityResult = productivityCalculator.score(
            for: usages.map {
                ClassifiedUsageDuration(
                    duration: $0.duration,
                    classification: $0.classification
                )
            }
        )

        let totalUsage = usages.reduce(0) { $0 + $1.duration }
        let controlResult = controlCalculator.score(from: mockControlInput())
        let detoxInput = mockDetoxInput()
        let detoxResult = detoxCalculator.score(from: detoxInput)
        let distractionCount = distractionCalculator.count(from: mockDistractionInput())
        let activities = mockActivities(for: day, apps: usages.map(\.app))
        let timeline = UsageTimelineChartState(
            buckets: mockTimelineBuckets(for: day, appUsages: usages),
            overlays: activities.map {
                UsageTimelineOverlay(
                    id: $0.id,
                    startDate: $0.startDate,
                    endDate: $0.endDate,
                    title: $0.title,
                    type: $0.type
                )
            }
        )
        let productivityScore = productivityResult.roundedValue ?? 0
        let perspective = perspectiveAnalyzer.perspective(
            from: DailyPerspectiveInput(
                productivityScore: productivityScore,
                controlScore: controlResult.roundedValue,
                detoxScore: detoxResult.roundedValue,
                mostProductivePeriodText: "09:00-13:20",
                distractionPeriodText: "16:00",
                leadingDistractionApps: ["Instagram", "TikTok"]
            )
        )
        let patterns = patternAnalyzer.patterns(
            from: PatternInput(
                productivityScore: productivityScore,
                controlScore: controlResult.roundedValue,
                longestDetoxText: LocktyDurationFormatter.abbreviated(detoxInput.longestPhoneFreeInterval),
                completedRoutines: 2,
                totalRoutines: 2
            )
        )

        return TodayDayState(
            day: day,
            loadingState: .loaded,
            primaryMetrics: PrimaryMetricsState(
                metrics: [
                    PrimaryMetric(kind: .productivity, value: Double(productivityScore)),
                    PrimaryMetric(kind: .control, value: Double(controlResult.roundedValue)),
                    PrimaryMetric(kind: .detox, value: Double(detoxResult.roundedValue))
                ]
            ),
            perspective: perspective,
            activities: activities,
            metrics: TodayMetricsState(
                screenTime: ScreenTimeCardState(
                    durationText: LocktyDurationFormatter.abbreviated(totalUsage),
                    comparisonText: "38m below average"
                ),
                bestDetox: BestDetoxCardState(
                    durationText: LocktyDurationFormatter.abbreviated(detoxInput.longestPhoneFreeInterval),
                    comparisonText: "Best this week"
                ),
                routines: RoutineSummaryCardState(
                    valueText: "2/2",
                    detailText: "92% completed"
                ),
                distractions: DistractionsCardState(
                    valueText: "\(distractionCount)",
                    comparisonText: "22% below average"
                ),
                pauseSuccess: PauseSuccessDayCardState(
                    valueText: "64%",
                    detailText: "9 of 14 stopped"
                ),
                intentionalTime: IntentionalTimeCardState(
                    valueText: "3h 18m",
                    detailText: "79% of relevant use"
                )
            ),
            timeline: timeline,
            appUsages: usages,
            patterns: patterns
        )
    }

    func updateClassification(appID: AppIdentity.ID, classification: AppClassification) async {
        await classificationRepository.saveClassification(classification, for: appID)
    }

    private func mockUsages() -> [ApplicationUsage] {
        [
            ApplicationUsage(
                app: app(
                    id: "notion",
                    name: "Notion",
                    bundleIdentifier: "notion.id",
                    artworkURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/96/8d/ae/968dae65-3869-0642-d5d6-d5a7f0e385b3/AppIconProd-0-0-1x_U007epad-0-0-0-1-0-0-P3-85-220.png/512x512bb.jpg"
                ),
                duration: 55 * 60,
                classification: .productive
            ),
            ApplicationUsage(
                app: app(
                    id: "slack",
                    name: "Slack",
                    bundleIdentifier: "com.tinyspeck.chatlyio",
                    artworkURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/e5/ec/29/e5ec2995-e467-3b2a-5f8f-138d48e4edcb/slack_icon_prod-0-0-1x_U007epad-0-1-sRGB-85-220.png/512x512bb.jpg"
                ),
                duration: 45 * 60,
                classification: .productive
            ),
            ApplicationUsage(
                app: app(
                    id: "gmail",
                    name: "Gmail",
                    bundleIdentifier: "com.google.Gmail",
                    artworkURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/05/30/5c/05305cc0-3dcf-7914-b3e5-5538b8d2503d/gmail_2026_ios-0-0-1x_U007epad-0-0-0-1-0-0-sRGB-0-0-85-220.png/512x512bb.jpg"
                ),
                duration: 40 * 60,
                classification: .productive
            ),
            ApplicationUsage(
                app: app(
                    id: "duolingo",
                    name: "Duolingo",
                    bundleIdentifier: "com.duolingo.DuolingoMobile",
                    artworkURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/67/e4/51/67e4516e-c1d0-452b-3f3e-5def33df3138/AppIcon-0-0-1x_U007epad-0-1-85-220.png/512x512bb.jpg"
                ),
                duration: 30 * 60,
                classification: .productive
            ),
            ApplicationUsage(
                app: app(
                    id: "google-calendar",
                    name: "Google Calendar",
                    bundleIdentifier: "com.google.calendar",
                    artworkURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/b0/d3/14/b0d31451-7521-b08f-901d-f7e612a425e4/calendar_2026_ios-0-0-1x_U007epad-0-0-0-1-0-0-sRGB-0-0-85-220.png/512x512bb.jpg"
                ),
                duration: 20 * 60,
                classification: .productive
            ),
            ApplicationUsage(
                app: app(
                    id: "spotify",
                    name: "Spotify",
                    bundleIdentifier: "com.spotify.client",
                    artworkURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/78/d3/2a/78d32a70-87dc-58e9-86c7-04b87c88f873/AppIcon-0-0-1x_U007epad-0-1-0-0-sRGB-85-220.png/512x512bb.jpg"
                ),
                duration: 18 * 60,
                classification: .neutral
            ),
            ApplicationUsage(
                app: app(
                    id: "google-maps",
                    name: "Google Maps",
                    bundleIdentifier: "com.google.Maps",
                    artworkURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/4e/d3/e2/4ed3e273-5114-70b7-b919-dca325bee1aa/maps_2025-0-0-1x_U007epad-0-0-0-1-0-0-sRGB-0-0-85-220.png/512x512bb.jpg"
                ),
                duration: 14 * 60,
                classification: .neutral
            ),
            ApplicationUsage(
                app: app(
                    id: "whatsapp",
                    name: "WhatsApp",
                    bundleIdentifier: "net.whatsapp.WhatsApp",
                    artworkURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/60/12/b8/6012b8e5-12b6-e819-2a54-f2ad93d02145/AppIcon-0-0-1x_U007epad-0-0-0-1-0-0-sRGB-0-85-220.png/512x512bb.jpg"
                ),
                duration: 8 * 60,
                classification: .neutral
            ),
            ApplicationUsage(
                app: app(
                    id: "instagram",
                    name: "Instagram",
                    bundleIdentifier: "com.burbn.instagram",
                    artworkURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/23/59/e9/2359e92d-376c-cc29-b9e6-ab9a4a00fcf4/Prod-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.jpg"
                ),
                duration: 7 * 60,
                classification: .unproductive
            ),
            ApplicationUsage(
                app: app(
                    id: "telegram",
                    name: "Telegram",
                    bundleIdentifier: "ph.telegra.Telegraph",
                    artworkURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/5a/2b/59/5a2b59f4-1458-d32d-7b33-00ba66d2d59e/Telegram-0-0-1x_U007epad-0-1-0-sRGB-85-220.png/512x512bb.jpg"
                ),
                duration: 4 * 60,
                classification: .neutral
            ),
            ApplicationUsage(
                app: app(
                    id: "youtube",
                    name: "YouTube",
                    bundleIdentifier: "com.google.ios.youtube",
                    artworkURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/e6/1d/28/e61d2805-7704-dc4f-8c2e-86a2f84e4ae9/logo_youtube_2024_q4_color-0-0-1x_U007emarketing-0-0-0-7-0-0-0-85-220.png/512x512bb.jpg"
                ),
                duration: 5 * 60,
                classification: .unproductive
            ),
            ApplicationUsage(
                app: app(
                    id: "tiktok",
                    name: "TikTok",
                    bundleIdentifier: "com.zhiliaoapp.musically",
                    artworkURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple211/v4/b4/f6/9e/b4f69e23-a20c-784c-7f41-400fd8ab3d1c/TikTok_AppIcon26-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.jpg"
                ),
                duration: 3 * 60,
                classification: .unproductive
            ),
            ApplicationUsage(
                app: app(
                    id: "reddit",
                    name: "Reddit",
                    bundleIdentifier: "com.reddit.Reddit",
                    artworkURL: "https://is1-ssl.mzstatic.com/image/thumb/Purple221/v4/21/41/4a/21414a76-4704-5801-452d-949dcb554447/AppIcon-0-0-1x_U007epad-0-1-0-85-220.png/512x512bb.jpg"
                ),
                duration: 3 * 60,
                classification: .unproductive
            )
        ]
    }

    private func comparisonText(for appID: AppIdentity.ID) -> String? {
        switch appID.rawValue {
        case "notion":
            "12m above average"
        case "slack":
            "8m below average"
        case "instagram":
            "18m below average"
        case "youtube":
            "24m below average"
        default:
            nil
        }
    }

    private func app(
        id: AppIdentity.ID,
        name: String,
        bundleIdentifier: String,
        artworkURL: String
    ) -> AppIdentity {
        AppIdentity(
            id: id,
            displayName: name,
            bundleIdentifier: bundleIdentifier,
            iconSource: .appStoreArtworkURL(artworkURL)
        )
    }

    private func mockControlInput() -> ControlScoreInput {
        ControlScoreInput(
            routineCompletionRate: 0.90,
            pauseAbandonmentRate: 0.60,
            restrictionAdherenceRate: 0.78,
            fragmentedUsagePenalty: 10
        )
    }

    private func mockDetoxInput() -> DetoxScoreInput {
        DetoxScoreInput(
            longestPhoneFreeInterval: (2 * 60 * 60) + (14 * 60),
            meaningfulPhoneFreeTime: (5 * 60 * 60) + (38 * 60),
            interruptionCount: 14
        )
    }

    private func mockDistractionInput() -> DistractionMetricInput {
        DistractionMetricInput(
            restrictedAccessAttempts: 8,
            unproductiveBursts: 4,
            repeatedAttempts: 2
        )
    }

    private func mockActivities(for day: Date, apps: [AppIdentity]) -> [DigitalActivity] {
        [
            DigitalActivity(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
                type: .routine,
                startDate: date(on: day, hour: 7, minute: 30),
                endDate: date(on: day, hour: 8, minute: 12),
                title: "Morning Routine",
                productivityScore: 92,
                relatedApplications: matchingApps(["google-calendar", "gmail"], in: apps),
                routineID: UUID(uuidString: "00000000-0000-0000-0000-000000000401")!
            ),
            DigitalActivity(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
                type: .focus,
                startDate: date(on: day, hour: 9, minute: 18),
                endDate: date(on: day, hour: 11, minute: 6),
                title: "Deep Work",
                productivityScore: 97,
                relatedApplications: matchingApps(["notion", "slack", "gmail"], in: apps),
                routineID: UUID(uuidString: "00000000-0000-0000-0000-000000000402")!
            ),
            DigitalActivity(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000303")!,
                type: .detox,
                startDate: date(on: day, hour: 11, minute: 22),
                endDate: date(on: day, hour: 12, minute: 38),
                title: "Detox",
                productivityScore: nil,
                relatedApplications: [],
                routineID: nil
            ),
            DigitalActivity(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000304")!,
                type: .freeTime,
                startDate: date(on: day, hour: 13, minute: 4),
                endDate: date(on: day, hour: 13, minute: 42),
                title: "Free Time",
                productivityScore: nil,
                relatedApplications: matchingApps(["spotify", "youtube", "instagram"], in: apps),
                routineID: nil
            ),
            DigitalActivity(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000305")!,
                type: .distraction,
                startDate: date(on: day, hour: 15, minute: 42),
                endDate: date(on: day, hour: 16, minute: 8),
                title: "Distraction",
                productivityScore: nil,
                relatedApplications: matchingApps(["instagram", "tiktok"], in: apps),
                routineID: nil
            ),
            DigitalActivity(
                id: UUID(uuidString: "00000000-0000-0000-0000-000000000306")!,
                type: .routine,
                startDate: date(on: day, hour: 17, minute: 10),
                endDate: date(on: day, hour: 18, minute: 31),
                title: "Study Routine",
                productivityScore: 88,
                relatedApplications: matchingApps(["duolingo", "notion"], in: apps),
                routineID: UUID(uuidString: "00000000-0000-0000-0000-000000000403")!
            )
        ]
    }

    private func matchingApps(_ ids: [String], in apps: [AppIdentity]) -> [AppIdentity] {
        ids.compactMap { id in
            apps.first { $0.id.rawValue == id }
        }
    }

    private func date(on day: Date, hour: Int, minute: Int) -> Date {
        var components = Calendar.current.dateComponents([.year, .month, .day], from: day)
        components.hour = hour
        components.minute = minute
        return Calendar.current.date(from: components) ?? day
    }

    private func mockTimelineBuckets(for day: Date, appUsages: [AppUsageState]) -> [UsageTimelineBucket] {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: day)
        let bucketCount = 24
        let classifications = Dictionary(uniqueKeysWithValues: appUsages.map { ($0.id, $0.classification) })
        let segments = mockUsageSegments()

        return (0..<bucketCount).map { hour in
            let start = calendar.date(byAdding: .hour, value: hour, to: startOfDay) ?? startOfDay
            let end = calendar.date(byAdding: .hour, value: hour + 1, to: startOfDay) ?? start

            var productive: TimeInterval = 0
            var neutral: TimeInterval = 0
            var unproductive: TimeInterval = 0

            for segment in segments where segment.hour == hour {
                let duration = TimeInterval(segment.minutes * 60)

                switch classifications[segment.appID] ?? .neutral {
                case .productive:
                    productive += duration
                case .neutral:
                    neutral += duration
                case .unproductive:
                    unproductive += duration
                }
            }

            return UsageTimelineBucket(
                start: start,
                end: end,
                productive: productive,
                neutral: neutral,
                unproductive: unproductive,
                confidence: .inferred
            )
        }
    }

    private func mockUsageSegments() -> [MockUsageSegment] {
        [
            MockUsageSegment(hour: 7, appID: "google-calendar", minutes: 20),
            MockUsageSegment(hour: 8, appID: "gmail", minutes: 20),
            MockUsageSegment(hour: 9, appID: "slack", minutes: 20),
            MockUsageSegment(hour: 9, appID: "notion", minutes: 25),
            MockUsageSegment(hour: 10, appID: "slack", minutes: 25),
            MockUsageSegment(hour: 10, appID: "gmail", minutes: 20),
            MockUsageSegment(hour: 12, appID: "google-maps", minutes: 14),
            MockUsageSegment(hour: 13, appID: "spotify", minutes: 18),
            MockUsageSegment(hour: 13, appID: "whatsapp", minutes: 8),
            MockUsageSegment(hour: 13, appID: "youtube", minutes: 5),
            MockUsageSegment(hour: 15, appID: "instagram", minutes: 7),
            MockUsageSegment(hour: 15, appID: "tiktok", minutes: 3),
            MockUsageSegment(hour: 16, appID: "telegram", minutes: 4),
            MockUsageSegment(hour: 17, appID: "notion", minutes: 30),
            MockUsageSegment(hour: 17, appID: "duolingo", minutes: 15),
            MockUsageSegment(hour: 18, appID: "duolingo", minutes: 15),
            MockUsageSegment(hour: 22, appID: "reddit", minutes: 3)
        ]
    }
}

private struct MockUsageSegment {
    let hour: Int
    let appID: AppIdentity.ID
    let minutes: Int
}
