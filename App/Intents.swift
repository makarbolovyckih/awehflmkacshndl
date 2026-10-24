import AppIntents

struct ScheduleEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Schedule"
    static var defaultQuery = ScheduleQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ScheduleQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ScheduleEntity] {
        await MainActor.run {
            ScheduleStore.shared.s.schedules
                .filter { identifiers.contains($0.id.uuidString) }
                .map { ScheduleEntity(id: $0.id.uuidString, name: $0.name) }
        }
    }
    func suggestedEntities() async throws -> [ScheduleEntity] {
        await MainActor.run {
            ScheduleStore.shared.s.schedules.map { ScheduleEntity(id: $0.id.uuidString, name: $0.name) }
        }
    }
}

struct StartScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Schedule"
    static var description = IntentDescription("Starts the Live Activity for one of your schedules (e.g. your Gym schedule when you wake up).")
    static var openAppWhenRun: Bool = true

    @Parameter(title: "Schedule")
    var schedule: ScheduleEntity

    static var parameterSummary: some ParameterSummary { Summary("Start \(\.$schedule)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        await LiveActivityManager.shared.start(schedule.id)
        return .result()
    }
}

struct EndScheduleIntent: AppIntent {
    static var title: LocalizedStringResource = "End Schedule"
    static var description = IntentDescription("Ends the Live Activity for one schedule.")
    static var openAppWhenRun: Bool = false

    @Parameter(title: "Schedule")
    var schedule: ScheduleEntity

    static var parameterSummary: some ParameterSummary { Summary("End \(\.$schedule)") }

    @MainActor
    func perform() async throws -> some IntentResult {
        await LiveActivityManager.shared.stop(schedule.id)
        return .result()
    }
}

struct EndAllIntent: AppIntent {
    static var title: LocalizedStringResource = "End All Schedules"
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await LiveActivityManager.shared.stopAll()
        return .result()
    }
}

struct DrinkWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "Drink Water Now"
    static var description = IntentDescription("Buzzes 3 times and shows \"Drink water\" for a minute on the gym Live Activity.")
    static var openAppWhenRun: Bool = false

    @MainActor
    func perform() async throws -> some IntentResult {
        await LiveActivityManager.shared.remindNow()
        return .result()
    }
}

struct ScheduleShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: StartScheduleIntent(), phrases: ["Start a schedule in \(.applicationName)"],
                    shortTitle: "Start schedule", systemImageName: "play.fill")
        AppShortcut(intent: EndAllIntent(), phrases: ["End my schedules in \(.applicationName)"],
                    shortTitle: "End all", systemImageName: "stop.fill")
        AppShortcut(intent: DrinkWaterIntent(), phrases: ["Drink water in \(.applicationName)"],
                    shortTitle: "Drink water now", systemImageName: "drop.fill")
    }
}
