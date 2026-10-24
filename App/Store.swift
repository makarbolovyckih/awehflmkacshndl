import SwiftUI

struct Exercise: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var sets: Int = 3
    var reps: Int = 10
    var weight: String = ""
}

struct GymConfig: Codable {
    var wakeMin = 7 * 60 + 10
    var sleepMin = 22 * 60
    var workoutStart = 17 * 60
    var workoutEnd = 18 * 60
    var waterEvery = 60
    var supps: [Supplement] = []
    /// index 0 = Sunday … 6 = Saturday; up to 3 muscle groups each; all empty = rest day
    var plan: [[String]] = Array(repeating: ["", "", ""], count: 7)
    /// exercises per weekday (same indexing as plan)
    var exercises: [[Exercise]] = Array(repeating: [], count: 7)
    /// sets done today, keyed "yyyy-MM-dd|exerciseID"
    var progress: [String: Int] = [:]

    init() {}

    // Tolerant decoding so older saved data keeps working.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        wakeMin = try c.decodeIfPresent(Int.self, forKey: .wakeMin) ?? wakeMin
        sleepMin = try c.decodeIfPresent(Int.self, forKey: .sleepMin) ?? sleepMin
        workoutStart = try c.decodeIfPresent(Int.self, forKey: .workoutStart) ?? workoutStart
        workoutEnd = try c.decodeIfPresent(Int.self, forKey: .workoutEnd) ?? workoutEnd
        waterEvery = try c.decodeIfPresent(Int.self, forKey: .waterEvery) ?? waterEvery
        supps = try c.decodeIfPresent([Supplement].self, forKey: .supps) ?? supps
        plan = try c.decodeIfPresent([[String]].self, forKey: .plan) ?? plan
        exercises = try c.decodeIfPresent([[Exercise]].self, forKey: .exercises) ?? exercises
        progress = try c.decodeIfPresent([String: Int].self, forKey: .progress) ?? progress
    }
}

struct Schedule: Codable, Identifiable {
    var id = UUID()
    var name: String
    var type: ScheduleType
    var blocks: [Block] = []
    var days: [Int]
    var background = false
    var chainTo: String? = nil
    var dotHex = "#FFD60A"
    var accentHex = "#30D158"
    var gym = GymConfig()

    static func make(_ t: ScheduleType) -> Schedule {
        func m(_ h: Int, _ mi: Int) -> Int { h * 60 + mi }
        var s = Schedule(name: t.title, type: t, days: t.defaultDays)
        switch t {
        case .school:
            s.blocks = [
                Block(name: "Math", kind: .period, number: 1, startMin: m(8, 30), endMin: m(9, 20), emoji: "📐"),
                Block(name: "English", kind: .period, number: 2, startMin: m(9, 25), endMin: m(10, 15), emoji: "📖"),
                Block(name: "Recess", kind: .recess, startMin: m(10, 15), endMin: m(10, 30), emoji: "🛝"),
                Block(name: "Science", kind: .period, number: 3, startMin: m(10, 30), endMin: m(11, 20), emoji: "🔬"),
                Block(name: "History", kind: .period, number: 4, startMin: m(11, 25), endMin: m(12, 15), emoji: "🏛️"),
                Block(name: "Lunch", kind: .lunch, startMin: m(12, 15), endMin: m(13, 0), emoji: "🍕"),
                Block(name: "Art", kind: .period, number: 5, startMin: m(13, 0), endMin: m(13, 50), emoji: "🎨"),
                Block(name: "PE", kind: .period, number: 6, startMin: m(13, 55), endMin: m(14, 45), emoji: "🏀"),
            ]
        case .work:
            s.dotHex = "#64D2FF"
            s.blocks = [
                Block(name: "Emails", kind: .work, startMin: m(9, 0), endMin: m(10, 30), emoji: "📧"),
                Block(name: "Break", kind: .rest, startMin: m(10, 30), endMin: m(10, 45), emoji: "☕️"),
                Block(name: "Deep work", kind: .work, startMin: m(10, 45), endMin: m(12, 30), emoji: "💻"),
                Block(name: "Lunch", kind: .lunch, startMin: m(12, 30), endMin: m(13, 15), emoji: "🥪"),
                Block(name: "Meetings", kind: .work, startMin: m(13, 15), endMin: m(15, 0), emoji: "📞"),
                Block(name: "Break", kind: .rest, startMin: m(15, 0), endMin: m(15, 15), emoji: "🧋"),
                Block(name: "Wrap up", kind: .work, startMin: m(15, 15), endMin: m(17, 0), emoji: "📝"),
            ]
        case .gym:
            s.dotHex = "#FF453A"
            s.accentHex = "#0A84FF"
        }
        return s
    }
}

struct Settings: Codable {
    var name = ""
    var schedules: [Schedule] = []
}

final class ScheduleStore: ObservableObject {
    static let shared = ScheduleStore()
    @Published var s: Settings { didSet { save() } }

    init() {
        if let d = UserDefaults.standard.data(forKey: "settings_v2"),
           let v = try? JSONDecoder().decode(Settings.self, from: d) {
            s = v
        } else {
            s = Settings(schedules: [Schedule.make(.school)])
        }
    }

    private func save() {
        if let d = try? JSONEncoder().encode(s) { UserDefaults.standard.set(d, forKey: "settings_v2") }
    }

    // MARK: lookups
    func idx(_ id: UUID) -> Int? { s.schedules.firstIndex { $0.id == id } }
    func schedule(_ id: String) -> Schedule? { s.schedules.first { $0.id.uuidString == id } }
    var canAdd: Bool { s.schedules.count < 3 }
    var backgroundCount: Int { s.schedules.filter { $0.background }.count }

    // MARK: bindings
    func field<T>(_ sid: UUID, _ kp: WritableKeyPath<Schedule, T>) -> Binding<T> {
        Binding(get: { (self.s.schedules.first { $0.id == sid } ?? Schedule.make(.school))[keyPath: kp] },
                set: { v in if let i = self.idx(sid) { self.s.schedules[i][keyPath: kp] = v } })
    }
    func gym<T>(_ sid: UUID, _ kp: WritableKeyPath<GymConfig, T>) -> Binding<T> {
        Binding(get: { (self.s.schedules.first { $0.id == sid } ?? Schedule.make(.gym)).gym[keyPath: kp] },
                set: { v in if let i = self.idx(sid) { self.s.schedules[i].gym[keyPath: kp] = v } })
    }
    func block(_ sid: UUID, _ bid: UUID) -> Binding<Block> {
        Binding(get: { self.s.schedules.first { $0.id == sid }?.blocks.first { $0.id == bid }
                    ?? Block(name: "", kind: .other, startMin: 0, endMin: 1, emoji: "") },
                set: { v in
                    if let i = self.idx(sid), let j = self.s.schedules[i].blocks.firstIndex(where: { $0.id == bid }) {
                        self.s.schedules[i].blocks[j] = v
                    }
                })
    }
    func supp(_ sid: UUID, _ pid: UUID) -> Binding<Supplement> {
        Binding(get: { self.s.schedules.first { $0.id == sid }?.gym.supps.first { $0.id == pid } ?? Supplement(name: "") },
                set: { v in
                    if let i = self.idx(sid), let j = self.s.schedules[i].gym.supps.firstIndex(where: { $0.id == pid }) {
                        self.s.schedules[i].gym.supps[j] = v
                    }
                })
    }
    func plan(_ sid: UUID, _ day: Int, _ k: Int) -> Binding<String> {
        Binding(get: { self.s.schedules.first { $0.id == sid }?.gym.plan[day][k] ?? "" },
                set: { v in if let i = self.idx(sid) { self.s.schedules[i].gym.plan[day][k] = v } })
    }

    // MARK: schedules
    @discardableResult
    func add(_ t: ScheduleType) -> UUID? {
        guard canAdd else { return nil }
        var n = Schedule.make(t)
        n.background = backgroundCount < 2
        s.schedules.append(n)
        return n.id
    }
    func delete(_ id: UUID) {
        s.schedules.removeAll { $0.id == id }
        for i in s.schedules.indices where s.schedules[i].chainTo == id.uuidString { s.schedules[i].chainTo = nil }
    }
    /// Max 2 schedules may run in the background.
    func setBackground(_ id: UUID, _ on: Bool) -> Bool {
        guard let i = idx(id) else { return false }
        if on && !s.schedules[i].background && backgroundCount >= 2 { return false }
        s.schedules[i].background = on
        return true
    }

    // MARK: blocks
    func sortedBlocks(_ sid: UUID) -> [Block] {
        (s.schedules.first { $0.id == sid }?.blocks ?? []).sorted { $0.startMin < $1.startMin }
    }
    func sort(_ sid: UUID) {
        if let i = idx(sid) { s.schedules[i].blocks.sort { $0.startMin < $1.startMin } }
    }
    func addBlock(_ sid: UUID, _ kind: BlockKind) {
        guard let i = idx(sid) else { return }
        let sc = s.schedules[i]
        let lastEnd = sc.blocks.map { $0.endMin }.max() ?? (8 * 60 + 25)
        let start = min(lastEnd + 5, 23 * 60)
        let len = kind == .period ? 45 : (kind == .work ? 60 : 30)
        let num = (sc.blocks.filter { $0.kind == .period }.map { $0.number }.max() ?? 0) + 1
        let name: String
        switch kind {
        case .period: name = "Class \(num)"
        case .work: name = "Work"
        case .workout: name = "Workout"
        case .lunch: name = "Lunch"
        case .rest: name = "Break"
        case .recess: name = "Recess"
        case .other: name = "Free time"
        }
        s.schedules[i].blocks.append(Block(name: name, kind: kind, number: num, startMin: start,
                                           endMin: min(start + len, 23 * 60 + 59), emoji: kind.emoji))
        sort(sid)
    }

    /// Drag-to-reorder: the time slots stay where they are, the blocks swap into them.
    func move(_ sid: UUID, from: IndexSet, to: Int) {
        guard let i = idx(sid) else { return }
        var blocks = sortedBlocks(sid)
        let slots = blocks.map { ($0.startMin, $0.endMin) }
        blocks.move(fromOffsets: from, toOffset: to)
        for k in blocks.indices {
            blocks[k].startMin = slots[k].0
            blocks[k].endMin = slots[k].1
        }
        var n = 0
        for k in blocks.indices where blocks[k].kind == .period {
            n += 1
            blocks[k].number = n
        }
        s.schedules[i].blocks = blocks
    }

    func generate(_ sid: UUID, count: Int, firstBell: Int, length: Int, passing: Int,
                  recessAfter: Int, recessLen: Int, lunchAfter: Int, lunchLen: Int) {
        guard let i = idx(sid) else { return }
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
        s.schedules[i].blocks = out.filter { $0.endMin < 24 * 60 }
    }

    // MARK: exercises
    func exercise(_ sid: UUID, _ day: Int, _ eid: UUID) -> Binding<Exercise> {
        Binding(get: { self.s.schedules.first { $0.id == sid }?.gym.exercises[day].first { $0.id == eid } ?? Exercise(name: "") },
                set: { v in
                    if let i = self.idx(sid), let j = self.s.schedules[i].gym.exercises[day].firstIndex(where: { $0.id == eid }) {
                        self.s.schedules[i].gym.exercises[day][j] = v
                    }
                })
    }
    func addExercise(_ sid: UUID, _ day: Int) {
        if let i = idx(sid) { s.schedules[i].gym.exercises[day].append(Exercise(name: "New exercise")) }
    }
    private func todayString() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: Date())
    }
    func done(_ sid: UUID, _ e: Exercise) -> Int {
        s.schedules.first { $0.id == sid }?.gym.progress["\(todayString())|\(e.id.uuidString)"] ?? 0
    }
    /// Tap = one more set done; tapping past the last set resets it.
    func bump(_ sid: UUID, _ e: Exercise) {
        guard let i = idx(sid) else { return }
        let today = todayString()
        let key = "\(today)|\(e.id.uuidString)"
        let cur = s.schedules[i].gym.progress[key] ?? 0
        var p = s.schedules[i].gym.progress.filter { $0.key.hasPrefix(today) }
        p[key] = cur >= e.sets ? 0 : cur + 1
        s.schedules[i].gym.progress = p
    }

    // MARK: Live Activity data
    static func joinGroups(_ g: [String]) -> String {
        g.count <= 1 ? g.joined() : g.dropLast().joined(separator: ", ") + " & " + (g.last ?? "")
    }

    func attributes(for sc: Schedule) -> ScheduleAttributes {
        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now)
        var blocks = sc.blocks.sorted { $0.startMin < $1.startMin }
        var lite: GymLite? = nil

        if sc.type == .gym {
            let g = sc.gym
            let groups = g.plan[weekday - 1].map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let nowMin = cal.component(.hour, from: now) * 60 + cal.component(.minute, from: now)
            let start = min(g.wakeMin, nowMin)
            blocks = []
            if !groups.isEmpty && g.workoutEnd > g.workoutStart {
                if g.workoutStart > start {
                    blocks.append(Block(name: "Hydrate & fuel", kind: .other, startMin: start, endMin: g.workoutStart, emoji: "💧"))
                }
                blocks.append(Block(name: "Workout", kind: .workout, startMin: max(start, g.workoutStart), endMin: g.workoutEnd, emoji: "🏋️"))
                if g.sleepMin > g.workoutEnd {
                    blocks.append(Block(name: "Recover", kind: .other, startMin: g.workoutEnd, endMin: g.sleepMin, emoji: "💧"))
                }
            } else {
                blocks.append(Block(name: "Rest day", kind: .other, startMin: start, endMin: max(g.sleepMin, start + 1), emoji: "😴"))
            }
            let title = groups.isEmpty ? "Rest day 😴" : "\(ScheduleStore.joinGroups(groups)) day"
            lite = GymLite(title: title, emoji: groups.isEmpty ? "😴" : "💪", water: g.waterEvery, supps: g.supps)
        } else if let cid = sc.chainTo, let next = schedule(cid), next.days.contains(weekday) {
            // After this schedule ends, the follow-up (e.g. work) continues on the same road.
            blocks += next.blocks.sorted { $0.startMin < $1.startMin }
        }

        return ScheduleAttributes(scheduleID: sc.id.uuidString, type: sc.type, blocks: blocks,
                                  dayStart: cal.startOfDay(for: now), startedAt: now,
                                  dotHex: sc.dotHex, accentHex: sc.accentHex, gym: lite)
    }
}
