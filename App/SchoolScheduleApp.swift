import SwiftUI

@main
struct SchoolScheduleApp: App {
    @StateObject private var store = ScheduleStore()
    @StateObject private var live = LiveActivityManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(live)
        }
    }
}
