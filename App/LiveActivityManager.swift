import SwiftUI
import ActivityKit
import CoreLocation

/// Keeps the app alive in the background so the Live Activity can move your dot and
/// switch periods on time. It never actually reads your location.
final class BackgroundKeeper: NSObject, CLLocationManagerDelegate {
    private let m = CLLocationManager()

    func start() {
        m.delegate = self
        m.desiredAccuracy = kCLLocationAccuracyThreeKilometers
        m.distanceFilter = 5000
        m.allowsBackgroundLocationUpdates = true
        m.pausesLocationUpdatesAutomatically = false
        m.showsBackgroundLocationIndicator = true
        switch m.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: m.startUpdatingLocation()
        default: m.requestWhenInUseAuthorization()
        }
    }

    func stop() {
        m.stopUpdatingLocation()
        m.allowsBackgroundLocationUpdates = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
}

@MainActor
final class LiveActivityManager: ObservableObject {
    @Published var isRunning = !Activity<ScheduleAttributes>.activities.isEmpty
    @Published var error: String?
    private var loop: Task<Void, Never>?
    private var endsAt: Date?
    private let keeper = BackgroundKeeper()

    func start(_ store: ScheduleStore) async {
        error = nil
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            error = "Live Activities are off. Turn them on in Settings → Schedule."
            return
        }
        let attrs = store.attributes()
        guard let last = attrs.segments.last else {
            error = "Add some classes first!"
            return
        }
        await stop()
        do {
            let content = ActivityContent(state: ScheduleAttributes.ContentState(tick: Date()), staleDate: nil)
            _ = try Activity<ScheduleAttributes>.request(attributes: attrs, content: content, pushType: nil)
            isRunning = true
            endsAt = attrs.date(last.endMin)
            if store.s.keepAlive { keeper.start() }
            startLoop()
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stop() async {
        loop?.cancel()
        loop = nil
        keeper.stop()
        for a in Activity<ScheduleAttributes>.activities {
            await a.end(nil, dismissalPolicy: .immediate)
        }
        isRunning = false
    }

    private func refresh() async {
        if let e = endsAt, Date() > e.addingTimeInterval(300) {
            await stop()
            return
        }
        for a in Activity<ScheduleAttributes>.activities {
            await a.update(ActivityContent(state: ScheduleAttributes.ContentState(tick: Date()), staleDate: nil))
        }
        if Activity<ScheduleAttributes>.activities.isEmpty { await stop() }
    }

    /// Wake up every minute on the dot and refresh the activity.
    private func startLoop() {
        loop?.cancel()
        loop = Task { [weak self] in
            while !Task.isCancelled {
                let now = Date()
                let next = Calendar.current.nextDate(after: now, matching: DateComponents(second: 0),
                                                     matchingPolicy: .nextTime) ?? now.addingTimeInterval(60)
                let secs = max(next.timeIntervalSince(now), 1)
                try? await Task.sleep(nanoseconds: UInt64(secs * 1_000_000_000))
                if Task.isCancelled { break }
                await self?.refresh()
            }
        }
    }
}
