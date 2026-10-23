import SwiftUI

struct Settings: Codable {
    var name = ""
    var dotHex = "#FF9F0A"
    var accentHex = "#30D158"
    var keepAlive = true
    var blocks: [Block]
}

final class ScheduleStore: ObservableObject {
    @Published var s: Settings { didSet { save() } }

    init() {
        if let d = UserDefaults.standard.data(forKey: "settings"),
           let v = try? JSONDecoder().decode(Settings.self, from: d) {
            s = v
        } else {
            s = Settings(blocks: ScheduleStore.sample)
        }
    }

    static var sample: [Block] {
        func t(_ h: Int, _ m: Int) -> Int { h * 60 + m }
        return [
            Block(name: "Math", kind: .period, number: 1, startMin: t(8, 30), endMin: t(9, 20), emoji: "📐"),
            Block(name: "English", kind: .period, number: 2, startMin: t(9, 25), endMin: t(10, 15), emoji: "📖"),
            Block(name: "Recess", kind: .recess, startMin: t(10, 15), endMin: t(10, 30), emoji: "🛝"),
            Block(name: "Science", kind: .period, number: 3, startMin: t(10, 30), endMin: t(11, 20), emoji: "🔬"),
            Block(name: "History", kind: .period, number: 4, startMin: t(11, 25), endMin: t(12, 15), emoji: "🏛️"),
            Block(name: "Lunch", kind: .lunch, startMin: t(12, 15), endMin: t(13, 0), emoji: "🍕"),
            Block(name: "Art", kind: .period, number: 5, startMin: t(13, 0), endMin: t(13, 50), emoji: "🎨"),
            Block(name: "PE", kind: .period, number: 6, startMin: t(13, 55), endMin: t(14, 45), emoji: "🏀"),
        ]
    }

    private func save() {
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: "settings") }
    }

    func attributes() -> ScheduleAttributes {
        ScheduleAttributes(blocks: s.blocks.sorted { $0.startMin < $1.startMin },
                           dayStart: Calendar.current.startOfDay(for: Date()),
                           dotHex: s.dotHex, accentHex: s.accentHex)
    }

    func sort() { s.blocks.sort { $0.startMin < $1.startMin } }

    func binding(_ id: UUID) -> Binding<Block> {
        Binding(
            get: { self.s.blocks.first { $0.id == id } ?? Block(name: "", kind: .other, startMin: 0, endMin: 1, emoji: "") },
            set: { new in
                if let i = self.s.blocks.firstIndex(where: { $0.id == id }) { self.s.blocks[i] = new }
            })
    }

    func add(_ kind: BlockKind) {
        let lastEnd = s.blocks.map { $0.endMin }.max() ?? (8 * 60 + 25)
        let start = min(lastEnd + 5, 23 * 60)
        let len = kind == .period ? 45 : 30
        let num = (s.blocks.filter { $0.kind == .period }.map { $0.number }.max() ?? 0) + 1
        let name: String
        switch kind {
        case .period: name = "Class \(num)"
        case .lunch: name = "Lunch"
        case .recess: name = "Recess"
        case .other: name = "Free time"
        }
        s.blocks.append(Block(name: name, kind: kind, number: num, startMin: start, endMin: min(start + len, 23 * 60 + 59), emoji: kind.emoji))
        sort()
    }

    func generate(count: Int, firstBell: Int, length: Int, passing: Int,
                  recessAfter: Int, recessLen: Int, lunchAfter: Int, lunchLen: Int) {
        var out: [Block] = []
        var t = firstBell
        for n in 1...max(count, 1) {
            out.append(Block(name: "Class \(n)", kind: .period, number: n, startMin: t, endMin: t + length, emoji: "📚"))
            t += length
            var added = false
            if n == recessAfter && recessLen > 0 {
                out.append(Block(name: "Recess", kind: .recess, startMin: t, endMin: t + recessLen, emoji: "🛝"))
                t += recessLen; added = true
            }
            if n == lunchAfter && lunchLen > 0 {
                out.append(Block(name: "Lunch", kind: .lunch, startMin: t, endMin: t + lunchLen, emoji: "🍕"))
                t += lunchLen; added = true
            }
            if !added { t += passing }
        }
        s.blocks = out.filter { $0.endMin < 24 * 60 }
    }
}
