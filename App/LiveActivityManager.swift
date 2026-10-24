import SwiftUI
import ActivityKit
import CoreLocation
import AudioToolbox

/// Keeps the app alive in the background so Live Activities can move your dot, switch periods and
/// buzz you on time. It never actually reads your location.
final class BackgroundKeeper: NSObject, CLLocationManagerDelegate {
    private let m = CLLocationManager()
    private(set) var on = false

    func start() {
        guard !on else { return }
        on = true
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
        guard on else { return }
        on = false
        m.stopUpdatingLocation()
        m.allowsBackgroundLocationUpdates = false
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if on && (manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways) {
            manager.startUpdatingLocation()
        }
    }
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {}
}

private struct GymRT {
    var next: Reminder?
    var alert: String?
    var alertEnd: Date?
}

@MainActor
final class LiveActivityManager: ObservableObject {
    static let shared = LiveActivityManager()

    @Published var runningIDs: Set<String> = []
    @Published var error: String?
    private var loop: Task<Void, Never>?
    private let keeper = BackgroundKeeper()
    private var rt: [String: GymRT] = [:]

    init() {
        syncRunning()
        if !runningIDs.isEmpty { startLoop() }
    }

    private func activities(_ id: String? = nil) -> [Activity<ScheduleAttributes>] {
        Activity<ScheduleAttributes>.activities.filter { id == nil || $0.attributes.scheduleID == id }
    }

    private func syncRunning() {
        runningIDs = Set(activities().map { $0.attributes.scheduleID })
    }

    private func updateKeeper() {
        let store = ScheduleStore.shared
        let needs = runningIDs.contains { store.schedule($0)?.background ?? false }
        if needs { keeper.start() } else { keeper.stop() }
    }

    // MARK: start / stop
    func start(_ id: String) async {
        error = nil
        let store = ScheduleStore.shared
        guard let sc = store.schedule(id) else { return }
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            error = "Live Activities are off. Turn them on in Settings → Schedule."
            return
        }
        let weekday = Calendar.current.component(.weekday, from: Date())
        guard sc.days.contains(weekday) else {
            error = "\(sc.name) isn't set to run today. Change its days in the editor."
            return
        }
        let attrs = store.attributes(for: sc)
        guard !attrs.segments.isEmpty else {
            error = "Add something to \(sc.name) first!"
            return
        }
        await stop(id)
        do {
            let content = ActivityContent(state: ScheduleAttributes.ContentState(tick: Date()), staleDate: nil)
            _ = try Activity<ScheduleAttributes>.request(attributes: attrs, content: content, pushType: nil)
            syncRunning()
            updateKeeper()
            startLoop()
            _ = await tick()   // fires the first gym reminder right away
        } catch {
            self.error = error.localizedDescription
        }
    }

    func stop(_ id: String) async {
        for a in activities(id) { await a.end(nil, dismissalPolicy: .immediate) }
        rt[id] = nil
        syncRunning()
        updateKeeper()
        if runningIDs.isEmpty { loop?.cancel(); loop = nil }
    }

    func stopAll() async {
        for a in activities() { await a.end(nil, dismissalPolicy: .immediate) }
        rt.removeAll()
        syncRunning()
        keeper.stop()
        loop?.cancel(); loop = nil
    }

    /// Called when a schedule's background switch changes.
    func applyBackground() { updateKeeper() }

    /// Manual "drink water now" (used by the Shortcuts action).
    func remindNow(_ text: String = "💧 Drink water") async {
        let now = Date()
        for a in activities() where a.attributes.gym != nil {
            var r = rt[a.attributes.scheduleID] ?? GymRT()
            r.alert = text
            r.alertEnd = now.addingTimeInterval(60)
            rt[a.attributes.scheduleID] = r
            vibrate()
            await a.update(ActivityContent(state: .init(tick: now, alert: text, alertEnd: r.alertEnd), staleDate: nil))
        }
        startLoop()
    }

    // MARK: the heartbeat
    private func vibrate() {
        Task {
            for _ in 0..<3 {
                AudioServicesPlaySystemSound(kSystemSoundID_Vibrate)
                try? await Task.sleep(nanoseconds: 700_000_000)
            }
        }
    }

    private func gymState(_ a: Activity<ScheduleAttributes>, now: Date, wake: inout Date) -> ScheduleAttributes.ContentState {
        let attrs = a.attributes
        guard let g = attrs.gym else { return .init(tick: now) }
        let id = attrs.scheduleID
        let until = attrs.endDate ?? now
        var r = rt[id] ?? GymRT(next: g.next(after: attrs.startedAt.addingTimeInterval(-1), anchor: attrs.startedAt, until: until))
        if let e = r.alertEnd, now >= e { r.alert = nil; r.alertEnd = nil }
        var texts: [String] = []
        while let n = r.next, now.addingTimeInterval(0.5) >= n.date {
            if now.timeIntervalSince(n.date) < 90 { texts.append("\(n.emoji) \(n.text)") }  // skip stale ones
            r.next = g.next(after: n.date, anchor: attrs.startedAt, until: until)
        }
        if !texts.isEmpty {
            r.alert = texts.joined(separator: " + ")
            r.alertEnd = now.addingTimeInterval(60)
            vibrate()
        }
        rt[id] = r
        if let n = r.next, n.date < wake { wake = n.date }
        if let e = r.alertEnd, e < wake { wake = e }
        return .init(tick: now, alert: r.alert, alertEnd: r.alertEnd)
    }

    /// Refreshes every running activity. Returns how long to sleep, or nil when nothing is running.
    private func tick() async -> Double? {
        let now = Date()
        let acts = activities()
        if acts.isEmpty { syncRunning(); updateKeeper(); return nil }
        let inForeground = UIApplication.shared.applicationState == .active
        let store = ScheduleStore.shared
        var wake = Calendar.current.nextDate(after: now, matching: DateComponents(second: 0), matchingPolicy: .nextTime)
            ?? now.addingTimeInterval(60)

        for a in acts {
            if let end = a.attributes.endDate, now > end.addingTimeInterval(300) {
                await a.end(nil, dismissalPolicy: .immediate)
                rt[a.attributes.scheduleID] = nil
                continue
            }
            // Only schedules marked "background" keep updating when the app isn't open.
            let bg = store.schedule(a.attributes.scheduleID)?.background ?? false
            guard inForeground || bg else { continue }
            let state = gymState(a, now: now, wake: &wake)
            await a.update(ActivityContent(state: state, staleDate: nil))
        }
        syncRunning()
        updateKeeper()
        return max(wake.timeIntervalSince(Date()), 1)
    }

    private func startLoop() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { break }
                guard let wait = await self.tick() else { break }
                try? await Task.sleep(nanoseconds: UInt64(wait * 1_000_000_000))
            }
            await MainActor.run { self?.loop = nil }
        }
    }
}
