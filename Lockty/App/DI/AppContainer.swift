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
    let healthService: HealthServicing
    let notificationService: NotificationServicing

    let todayViewModel: TodayViewModel
    let rulesViewModel: RulesViewModel
    let routinesViewModel: RoutinesViewModel
    let focusViewModel: FocusViewModel
    let frictionsViewModel: FrictionsViewModel
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
        healthService: HealthServicing,
        notificationService: NotificationServicing,
        todayViewModel: TodayViewModel,
        rulesViewModel: RulesViewModel,
        routinesViewModel: RoutinesViewModel,
        focusViewModel: FocusViewModel,
        frictionsViewModel: FrictionsViewModel,
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
        self.healthService = healthService
        self.notificationService = notificationService
        self.todayViewModel = todayViewModel
        self.rulesViewModel = rulesViewModel
        self.routinesViewModel = routinesViewModel
        self.focusViewModel = focusViewModel
        self.frictionsViewModel = frictionsViewModel
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
        let appGroupRepository = AppGroupStoreUserAppGroupRepository(appGroupStore: appGroupStore)
        let autoFocusRepository = AppGroupStoreAutoFocusRepository(appGroupStore: appGroupStore)
        let autoFocusManager = AutoFocusManager(
            repository: autoFocusRepository,
            classificationRepository: classificationRepository,
            selectionStore: selectionStore
        )
        let editorStore = EditorViewModelStore()
        let usageDataService = LiveUsageDataService(
            appGroupStore: appGroupStore,
            classificationRepository: classificationRepository
        )
        let shieldService = LiveShieldService(appGroupStore: appGroupStore, selectionStore: selectionStore)
        let deviceActivityService = LiveDeviceActivityService(selectionStore: selectionStore)
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
        let ruleRepository = HybridRuleRepository(
            routineRepository: routineRepository,
            appGroupStore: appGroupStore
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
        let healthService = LiveHealthService()
        let notificationService = LiveNotificationService()

        let todayPipeline = LiveTodayDataPipeline(
            usageDataService: usageDataService,
            appGroupStore: appGroupStore,
            classificationRepository: classificationRepository,
            pauseEventRepository: pauseEventRepository,
            routineExecutionRepository: routineExecutionRepository
        )
        let todayViewModel = TodayViewModel(
            dataProvider: todayPipeline,
            routineEngine: routineEngine,
            pauseEngine: pauseEngine,
            routineRepository: routineRepository,
            selectionStore: selectionStore,
            autoFocusManager: autoFocusManager
        )
        let routineScheduleCoordinator = RoutineScheduleCoordinator(
            repository: routineRepository,
            appGroupStore: appGroupStore,
            deviceActivityService: deviceActivityService
        )
        let routinesViewModel = RoutinesViewModel(
            routineEngine: routineEngine,
            repository: routineRepository,
            appGroupRepository: appGroupRepository,
            shieldService: shieldService,
            scheduleCoordinator: routineScheduleCoordinator,
            selectionStore: selectionStore
        )
        let rulesViewModel = RulesViewModel(
            routineEngine: routineEngine,
            repository: ruleRepository,
            appGroupRepository: appGroupRepository,
            scheduleCoordinator: routineScheduleCoordinator,
            selectionStore: selectionStore
        )
        let focusViewModel = FocusViewModel()
        let pauseFlowRepository = AppGroupPauseFlowRepository(appGroupStore: appGroupStore)
        let frictionRepository = AppGroupFrictionRepository(
            pauseFlowRepository: pauseFlowRepository,
            routineRepository: routineRepository,
            appGroupStore: appGroupStore
        )
        let frictionsViewModel = FrictionsViewModel(repository: frictionRepository)
        let appsViewModel = AppsLibraryViewModel(
            appGroupRepository: appGroupRepository,
            autoFocusManager: autoFocusManager,
            selectionStore: selectionStore
        )
        let distractingGroupViewModel = DistractingGroupViewModel(
            autoFocusManager: autoFocusManager,
            frictionRepository: frictionRepository,
            selectionStore: selectionStore
        )
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
            rulesViewModel: rulesViewModel,
            routinesViewModel: routinesViewModel,
            focusViewModel: focusViewModel,
            frictionsViewModel: frictionsViewModel,
            pausesViewModel: pausesViewModel,
            lifetimeViewModel: lifetimeViewModel,
            systemAccessViewModel: systemAccessViewModel,
            selectionStore: selectionStore,
            pauseEngine: pauseEngine,
            routineEngine: routineEngine,
            ruleRepository: ruleRepository,
            routineRepository: routineRepository,
            routineExecutionRepository: routineExecutionRepository,
            pauseRuleRepository: pauseRuleRepository,
            pauseFlowRepository: pauseFlowRepository,
            frictionRepository: frictionRepository,
            pauseEventRepository: pauseEventRepository,
            classificationRepository: classificationRepository,
            appGroupRepository: appGroupRepository,
            autoFocusManager: autoFocusManager,
            appsViewModel: appsViewModel,
            distractingGroupViewModel: distractingGroupViewModel,
            haptics: haptics,
            nfcService: nfcService,
            locationService: locationService,
            healthService: healthService,
            editorStore: editorStore,
            usageDataService: usageDataService
        )
        let destinationFactory = DestinationFactory(featureFactory: featureFactory)
        let startupCoordinator = StartupCoordinator(
            session: session,
            router: router,
            appGroupStore: appGroupStore,
            pauseEngine: pauseEngine,
            frictionRepository: frictionRepository,
            notificationService: notificationService,
            routineEngine: routineEngine,
            shieldService: shieldService,
            scheduleCoordinator: routineScheduleCoordinator
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
            healthService: healthService,
            notificationService: notificationService,
            todayViewModel: todayViewModel,
            rulesViewModel: rulesViewModel,
            routinesViewModel: routinesViewModel,
            focusViewModel: focusViewModel,
            frictionsViewModel: frictionsViewModel,
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
