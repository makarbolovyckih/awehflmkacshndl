import SwiftUI
import ActivityKit

enum ScheduleType: String, Codable, CaseIterable, Identifiable {
    case school, work, gym
    var id: String { rawValue }
    var title: String {
        switch self {
        case .school: return "School"
        case .work: return "Work"
        case .gym: return "Gym & health"
        }
    }
    var emoji: String {
        switch self {
        case .school: return "🎒"
        case .work: return "💼"
        case .gym: return "💪"
        }
    }
    var blurb: String {
        switch self {
        case .school: return "Periods, lunch, recess. Shows P1, P2…"
        case .work: return "Work blocks, lunch and breaks. Shows emojis."
        case .gym: return "Water, supplements, workout days & muscle groups."
        }
    }
    var defaultDays: [Int] { self == .gym ? [1, 2, 3, 4, 5, 6, 7] : [2, 3, 4, 5, 6] }
    var kinds: [BlockKind] {
        switch self {
        case .school: return [.period, .lunch, .recess, .other]
        case .work: return [.work, .lunch, .rest, .other]
        case .gym: return [.workout, .other]
        }
    }
}

enum BlockKind: String, Codable, CaseIterable, Identifiable {
    case period, work, workout, lunch, rest, recess, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .period: return "Class"
        case .work: return "Work time"
        case .workout: return "Workout"
        case .lunch: return "Lunch"
        case .rest: return "Break"
        case .recess: return "Recess"
        case .other: return "Other"
        }
    }
    var emoji: String {
        switch self {
        case .period: return "📚"
        case .work: return "💼"
        case .workout: return "🏋️"
        case .lunch: return "🍕"
        case .rest: return "☕️"
        case .recess: return "🛝"
        case .other: return "⭐️"
        }
    }
    var solid: Bool { self == .period || self == .work || self == .workout }
}

/// One thing in your day. Kept tiny on purpose: Live Activities have a ~4KB data limit.
struct Block: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var kind: BlockKind
    var number: Int = 1
    var startMin: Int
    var endMin: Int
    var emoji: String

    enum CodingKeys: String, CodingKey {
        case name = "n", kind = "k", number = "p", startMin = "s", endMin = "x", emoji = "e"
    }
    var short: String { kind == .period ? "P\(number)" : emoji }
    var goName: String { kind == .period ? "period \(number)" : name.lowercased() }
}

struct Supplement: Codable, Hashable, Identifiable {
    var id = UUID()
    var name: String
    var emoji: String = "💊"
    var everyMin: Int = 1440
    var firstAfterMin: Int = 0
    enum CodingKeys: String, CodingKey {
        case name = "n", emoji = "e", everyMin = "v", firstAfterMin = "f"
    }
}

struct Reminder {
    var emoji: String
    var text: String
    var date: Date
}

/// The tiny slice of the gym plan the Live Activity needs.
struct GymLite: Codable, Hashable {
    var title: String
    var emoji: String
    var water: Int
    var supps: [Supplement]

    /// Next reminder strictly after `d`. Water starts at `anchor`, supplements at anchor + firstAfter.
    func next(after d: Date, anchor: Date, until: Date) -> Reminder? {
        var best: Reminder?
        func consider(_ emoji: String, _ text: String, first: TimeInterval, every: TimeInterval) {
            guard every > 0 else { return }
            let t0 = anchor.addingTimeInterval(first)
            var t = t0
            if d >= t0 {
                let k = floor(d.timeIntervalSince(t0) / every) + 1
                t = t0.addingTimeInterval(k * every)
            }
            if t > until { return }
            if best == nil || t < best!.date { best = Reminder(emoji: emoji, text: text, date: t) }
        }
        if water > 0 { consider("💧", "Drink water", first: 0, every: Double(water) * 60) }
        for s in supps {
            consider(s.emoji, "Take \(s.name)", first: Double(s.firstAfterMin) * 60, every: Double(s.everyMin) * 60)
        }
        return best
    }
}

/// A piece of the road: a block, or the gap (walking time) between blocks.
struct Segment: Identifiable {
    var id: Int
    var title: String
    var short: String
    var sub: String
    var emoji: String
    var go: String
    var goShort: String
    var solid: Bool
    var startMin: Int
    var endMin: Int
}

func buildSegments(_ blocks: [Block]) -> [Segment] {
    let sorted = blocks.filter { $0.endMin > $0.startMin }.sorted { $0.startMin < $1.startMin }
    var out: [Segment] = []
    for b in sorted {
        var start = b.startMin
        let go = "Go to \(b.goName)"
        if let last = out.last {
            if start > last.endMin {
                out.append(Segment(id: out.count, title: go, short: "→" + b.short, sub: "Next: \(b.name)",
                                   emoji: "🚶", go: go, goShort: "→" + b.short, solid: false,
                                   startMin: last.endMin, endMin: start))
            } else {
                start = last.endMin
            }
        }
        if b.endMin <= start { continue }
        out.append(Segment(id: out.count, title: b.name, short: b.short,
                           sub: b.kind == .period ? "Period \(b.number)" : b.kind.title,
                           emoji: b.emoji, go: go, goShort: "→" + b.short,
                           solid: b.kind.solid, startMin: start, endMin: b.endMin))
    }
    return out
}

struct NowInfo {
    var title: String
    var short: String
    var sub: String
    var emoji: String
    var start: Date? = nil
    var end: Date? = nil
    var timerEnd: Date? = nil
    var solid: Bool = false
    var done: Bool = false
    var note: String? = nil
}

struct ScheduleAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var tick: Date
        var alert: String? = nil
        var alertEnd: Date? = nil
    }
    var scheduleID: String
    var type: ScheduleType
    var blocks: [Block]
    var dayStart: Date
    var startedAt: Date
    var dotHex: String
    var accentHex: String
    var gym: GymLite? = nil

    var segments: [Segment] { buildSegments(blocks) }
    var endDate: Date? { segments.last.map { date($0.endMin) } }
    func date(_ minutes: Int) -> Date { dayStart.addingTimeInterval(Double(minutes) * 60) }
    func minutes(at d: Date) -> Double { d.timeIntervalSince(dayStart) / 60 }

    func baseInfo(at d: Date) -> NowInfo {
        let segs = segments
        guard let first = segs.first, let last = segs.last else {
            return NowInfo(title: "Nothing planned", short: "—", sub: "Add something in the app", emoji: "🤷",
                           done: true, note: "Nothing planned")
        }
        let m = minutes(at: d)
        if m < Double(first.startMin) {
            let t = date(first.startMin)
            return NowInfo(title: first.go, short: first.goShort, sub: "Starts soon", emoji: "🎒",
                           end: nil, timerEnd: t, note: "Not started yet")
        }
        if m >= Double(last.endMin) {
            return NowInfo(title: "All done!", short: "🎉", sub: "Nice work today", emoji: "🎉",
                           done: true, note: "Finished for today")
        }
        let s = segs.first { m >= Double($0.startMin) && m < Double($0.endMin) } ?? last
        return NowInfo(title: s.title, short: s.short, sub: s.sub, emoji: s.emoji,
                       start: date(s.startMin), end: date(s.endMin), timerEnd: date(s.endMin), solid: s.solid)
    }

    func info(at d: Date, state: ContentState? = nil) -> NowInfo {
        var i = baseInfo(at: d)
        guard let g = gym, !i.done else { return i }
        i.title = g.title
        guard let st = state else {
            i.sub = i.solid ? "Workout time! 💪" : "Tap Start for water & supplement reminders"
            i.timerEnd = nil
            return i
        }
        if let a = st.alert, let e = st.alertEnd, e > d {
            let em = String(a.prefix(1))
            return NowInfo(title: a, short: em, sub: "Do it now 📳", emoji: em, timerEnd: e, note: "Right now!")
        }
        let prefix = i.solid ? "Workout 💪 · " : ""
        if let n = g.next(after: d, anchor: startedAt, until: endDate ?? d) {
            i.sub = prefix + "Next: \(n.emoji) \(n.text)"
            i.timerEnd = n.date
        } else {
            i.sub = prefix + "No more reminders today"
            i.timerEnd = i.end
        }
        return i
    }
}

func fmt(_ m: Int) -> String {
    let h = m / 60, mm = m % 60
    let h12 = h % 12 == 0 ? 12 : h % 12
    return String(format: "%d:%02d %@", h12, mm, h < 12 ? "AM" : "PM")
}

func durText(_ m: Int) -> String {
    if m <= 0 { return "Off" }
    if m == 1440 { return "Once a day" }
    let h = m / 60, mm = m % 60
    if h == 0 { return "Every \(mm) min" }
    if mm == 0 { return "Every \(h) h" }
    return "Every \(h) h \(mm) min"
}

extension Color {
    init(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var v: UInt64 = 0
        Scanner(string: s).scanHexInt64(&v)
        self.init(red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255)
    }
    var hex: String {
        let u = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        u.getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
