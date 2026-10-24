import SwiftUI

@main
struct SchoolScheduleApp: App {
    @StateObject private var store = ScheduleStore.shared
    @StateObject private var live = LiveActivityManager.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(live)
        }
    }
}
