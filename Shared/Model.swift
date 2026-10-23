import SwiftUI
import ActivityKit

enum BlockKind: String, Codable, CaseIterable, Identifiable {
    case period, lunch, recess, other
    var id: String { rawValue }
    var title: String {
        switch self {
        case .period: return "Class"
        case .lunch: return "Lunch"
        case .recess: return "Recess"
        case .other: return "Other"
        }
    }
    var emoji: String {
        switch self {
        case .period: return "📚"
        case .lunch: return "🍕"
        case .recess: return "🛝"
        case .other: return "⭐️"
        }
    }
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
                           solid: b.kind == .period, startMin: start, endMin: b.endMin))
    }
    return out
}

struct NowInfo {
    var title: String
    var short: String
    var sub: String
    var emoji: String
    var start: Date?
    var end: Date?
    var solid: Bool
    var done: Bool
}

struct ScheduleAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable { var tick: Date }
    var blocks: [Block]
    var dayStart: Date
    var dotHex: String
    var accentHex: String

    var segments: [Segment] { buildSegments(blocks) }
    func date(_ minutes: Int) -> Date { dayStart.addingTimeInterval(Double(minutes) * 60) }
    func minutes(at d: Date) -> Double { d.timeIntervalSince(dayStart) / 60 }

    func info(at d: Date) -> NowInfo {
        let segs = segments
        guard let first = segs.first, let last = segs.last else {
            return NowInfo(title: "No schedule yet", short: "—", sub: "Add classes in the app", emoji: "🤷",
                           start: nil, end: nil, solid: false, done: true)
        }
        let m = minutes(at: d)
        if m < Double(first.startMin) {
            return NowInfo(title: first.go, short: first.goShort, sub: "School starts soon", emoji: "🎒",
                           start: nil, end: date(first.startMin), solid: false, done: false)
        }
        if m >= Double(last.endMin) {
            return NowInfo(title: "School's out!", short: "🎉", sub: "Go touch grass", emoji: "🎉",
                           start: nil, end: nil, solid: false, done: true)
        }
        let s = segs.first { m >= Double($0.startMin) && m < Double($0.endMin) } ?? last
        return NowInfo(title: s.title, short: s.short, sub: s.sub, emoji: s.emoji,
                       start: date(s.startMin), end: date(s.endMin), solid: s.solid, done: false)
    }
}

func fmt(_ m: Int) -> String {
    let h = m / 60, mm = m % 60
    let h12 = h % 12 == 0 ? 12 : h % 12
    return String(format: "%d:%02d %@", h12, mm, h < 12 ? "AM" : "PM")
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
