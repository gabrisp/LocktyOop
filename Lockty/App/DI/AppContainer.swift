import Foundation

final class AppContainer {
    let session: AppSession
    let router: AppRouter

    let appGroupStore: AppGroupStore
    let persistenceController: PersistenceController
    let systemCapabilities: SystemCapabilities
    let haptics: HapticsFactory

    let screenTimeAuthorizationService: ScreenTimeAuthorizationServicing
    let usageDataService: UsageDataServicing
    let shieldService: ShieldServicing
    let deviceActivityService: DeviceActivityServicing

    let routineEngine: RoutineEngine
    let pauseEngine: PauseEngine

    let alarmService: AlarmServicing
    let nfcService: NFCServicing
    let locationService: LocationTriggerServicing
    let notificationService: NotificationServicing

    let todayViewModel: TodayViewModel
    let routinesViewModel: RoutinesViewModel
    let focusViewModel: FocusViewModel
    let pausesViewModel: PausesViewModel
    let lifetimeViewModel: LifetimeViewModel
    let systemAccessViewModel: SystemAccessViewModel
    let selectionStore: ScreenTimeSelectionStore
    let editorStore: EditorViewModelStore

    let featureFactory: FeatureFactory
    let destinationFactory: DestinationFactory
    let startupCoordinator: StartupCoordinator

    private init(
        session: AppSession,
        router: AppRouter,
        appGroupStore: AppGroupStore,
        persistenceController: PersistenceController,
        systemCapabilities: SystemCapabilities,
        haptics: HapticsFactory,
        screenTimeAuthorizationService: ScreenTimeAuthorizationServicing,
        usageDataService: UsageDataServicing,
        shieldService: ShieldServicing,
        deviceActivityService: DeviceActivityServicing,
        routineEngine: RoutineEngine,
        pauseEngine: PauseEngine,
        alarmService: AlarmServicing,
        nfcService: NFCServicing,
        locationService: LocationTriggerServicing,
        notificationService: NotificationServicing,
        todayViewModel: TodayViewModel,
        routinesViewModel: RoutinesViewModel,
        focusViewModel: FocusViewModel,
        pausesViewModel: PausesViewModel,
        lifetimeViewModel: LifetimeViewModel,
        systemAccessViewModel: SystemAccessViewModel,
        selectionStore: ScreenTimeSelectionStore,
        editorStore: EditorViewModelStore,
        featureFactory: FeatureFactory,
        destinationFactory: DestinationFactory,
        startupCoordinator: StartupCoordinator
    ) {
        self.session = session
        self.router = router
        self.appGroupStore = appGroupStore
        self.persistenceController = persistenceController
        self.systemCapabilities = systemCapabilities
        self.haptics = haptics
        self.screenTimeAuthorizationService = screenTimeAuthorizationService
        self.usageDataService = usageDataService
        self.shieldService = shieldService
        self.deviceActivityService = deviceActivityService
        self.routineEngine = routineEngine
        self.pauseEngine = pauseEngine
        self.alarmService = alarmService
        self.nfcService = nfcService
        self.locationService = locationService
        self.notificationService = notificationService
        self.todayViewModel = todayViewModel
        self.routinesViewModel = routinesViewModel
        self.focusViewModel = focusViewModel
        self.pausesViewModel = pausesViewModel
        self.lifetimeViewModel = lifetimeViewModel
        self.systemAccessViewModel = systemAccessViewModel
        self.selectionStore = selectionStore
        self.editorStore = editorStore
        self.featureFactory = featureFactory
        self.destinationFactory = destinationFactory
        self.startupCoordinator = startupCoordinator
    }

    static func live() -> AppContainer {
        let session = AppSession()
        let router = AppRouter()
        let appGroupStore = AppGroupStore()
        let persistenceController = PersistenceController()
        let capabilities = SystemCapabilities.current
        let haptics = HapticsFactory()

        let authorizationService = LiveScreenTimeAuthorizationService()
        let classificationRepository = CoreDataAppClassificationRepository(controller: persistenceController)
        let selectionStore = ScreenTimeSelectionStore(appGroupStore: appGroupStore)
        let editorStore = EditorViewModelStore()
        let usageDataService = LiveUsageDataService(
            appGroupStore: appGroupStore,
            classificationRepository: classificationRepository
        )
        let shieldService = LiveShieldService(appGroupStore: appGroupStore, selectionStore: selectionStore)
        let deviceActivityService = LiveDeviceActivityService()
        let pauseRuleRepository = CoreDataPauseRuleRepository(
            controller: persistenceController,
            appGroupStore: appGroupStore,
            selectionStore: selectionStore
        )
        let pauseEventRepository = CoreDataPauseEventRepository(controller: persistenceController)
        let routineExecutionRepository = CoreDataRoutineExecutionRepository(controller: persistenceController)
        let routineRepository = CoreDataRoutineRepository(
            controller: persistenceController,
            selectionStore: selectionStore
        )
        let alarmService = LiveAlarmService()
        let routineEngine = RoutineEngine(
            shieldService: shieldService,
            deviceActivityService: deviceActivityService,
            alarmService: alarmService,
            appGroupStore: appGroupStore,
            pauseRuleRepository: pauseRuleRepository,
            executionRepository: routineExecutionRepository
        )
        let pauseEngine = PauseEngine(
            shieldService: shieldService,
            deviceActivityService: deviceActivityService,
            appGroupStore: appGroupStore,
            pauseRuleRepository: pauseRuleRepository,
            pauseEventRepository: pauseEventRepository
        )
        let nfcService = LiveNFCService()
        let locationService = LiveLocationTriggerService()
        let notificationService = LiveNotificationService()

        let todayPipeline = LiveTodayDataPipeline(
            usageDataService: usageDataService,
            appGroupStore: appGroupStore,
            classificationRepository: classificationRepository,
            pauseEventRepository: pauseEventRepository,
            routineExecutionRepository: routineExecutionRepository
        )
        let todayViewModel = TodayViewModel(dataProvider: todayPipeline, routineEngine: routineEngine)
        let routineScheduleCoordinator = RoutineScheduleCoordinator(
            repository: routineRepository,
            appGroupStore: appGroupStore,
            deviceActivityService: deviceActivityService
        )
        let routinesViewModel = RoutinesViewModel(
            routineEngine: routineEngine,
            repository: routineRepository,
            shieldService: shieldService,
            scheduleCoordinator: routineScheduleCoordinator
        )
        let focusViewModel = FocusViewModel()
        let pausesViewModel = PausesViewModel(
            ruleRepository: pauseRuleRepository,
            eventRepository: pauseEventRepository,
            calculator: PauseSuccessCalculator(),
            routineEngine: routineEngine
        )
        let lifetimeViewModel = LifetimeViewModel(
            usageDataService: usageDataService,
            pauseEventRepository: pauseEventRepository,
            routineExecutionRepository: routineExecutionRepository,
            appGroupStore: appGroupStore
        )
        let systemAccessViewModel = SystemAccessViewModel(
            screenTime: authorizationService,
            notifications: notificationService,
            location: locationService,
            alarms: alarmService
        )
        let featureFactory = FeatureFactory(
            router: router,
            todayViewModel: todayViewModel,
            routinesViewModel: routinesViewModel,
            focusViewModel: focusViewModel,
            pausesViewModel: pausesViewModel,
            lifetimeViewModel: lifetimeViewModel,
            systemAccessViewModel: systemAccessViewModel,
            selectionStore: selectionStore,
            pauseEngine: pauseEngine,
            routineEngine: routineEngine,
            routineRepository: routineRepository,
            routineExecutionRepository: routineExecutionRepository,
            pauseRuleRepository: pauseRuleRepository,
            pauseEventRepository: pauseEventRepository,
            classificationRepository: classificationRepository,
            haptics: haptics,
            editorStore: editorStore,
            usageDataService: usageDataService
        )
        let destinationFactory = DestinationFactory(featureFactory: featureFactory)
        let startupCoordinator = StartupCoordinator(
            session: session,
            router: router,
            appGroupStore: appGroupStore,
            pauseEngine: pauseEngine,
            routineEngine: routineEngine,
            shieldService: shieldService
        )

        return AppContainer(
            session: session,
            router: router,
            appGroupStore: appGroupStore,
            persistenceController: persistenceController,
            systemCapabilities: capabilities,
            haptics: haptics,
            screenTimeAuthorizationService: authorizationService,
            usageDataService: usageDataService,
            shieldService: shieldService,
            deviceActivityService: deviceActivityService,
            routineEngine: routineEngine,
            pauseEngine: pauseEngine,
            alarmService: alarmService,
            nfcService: nfcService,
            locationService: locationService,
            notificationService: notificationService,
            todayViewModel: todayViewModel,
            routinesViewModel: routinesViewModel,
            focusViewModel: focusViewModel,
            pausesViewModel: pausesViewModel,
            lifetimeViewModel: lifetimeViewModel,
            systemAccessViewModel: systemAccessViewModel,
            selectionStore: selectionStore,
            editorStore: editorStore,
            featureFactory: featureFactory,
            destinationFactory: destinationFactory,
            startupCoordinator: startupCoordinator
        )
    }

    static func make() -> AppContainer {
        live()
    }
}
