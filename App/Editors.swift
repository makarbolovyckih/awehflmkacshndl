import SwiftUI

func timeBinding(_ m: Binding<Int>) -> Binding<Date> {
    Binding(
        get: { Calendar.current.date(bySettingHour: m.wrappedValue / 60, minute: m.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
        set: {
            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
            m.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
}

struct DaysPicker: View {
    @Binding var days: [Int]
    private let names = ["S", "M", "T", "W", "T", "F", "S"]
    var body: some View {
        HStack {
            ForEach(1...7, id: \.self) { d in
                let on = days.contains(d)
                Button {
                    if on { days.removeAll { $0 == d } } else { days.append(d) }
                } label: {
                    Text(names[d - 1]).font(.subheadline.bold())
                        .frame(width: 34, height: 34)
                        .background(Circle().fill(on ? Color.accentColor : Color.gray.opacity(0.25)))
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                if d < 7 { Spacer(minLength: 0) }
            }
        }
    }
}

// MARK: - schedule detail

struct ScheduleDetail: View {
    @EnvironmentObject var store: ScheduleStore
    @EnvironmentObject var live: LiveActivityManager
    @Environment(\.dismiss) var dismiss
    let id: UUID
    @State private var showLimit = false
    @State private var confirmDelete = false

    private func color(_ kp: WritableKeyPath<Schedule, String>) -> Binding<Color> {
        let b = store.field(id, kp)
        return Binding(get: { Color(hex: b.wrappedValue) }, set: { b.wrappedValue = $0.hex })
    }

    var body: some View {
        if let sc = store.s.schedules.first(where: { $0.id == id }) {
            Form {
                Section("Basics") {
                    TextField("Name", text: store.field(id, \.name))
                    VStack(alignment: .leading, spacing: 8) {
                        Text(sc.type == .gym ? "Days it can run" : "Days you \(sc.type == .school ? "go to school" : "work")")
                            .font(.footnote).foregroundStyle(.secondary)
                        DaysPicker(days: store.field(id, \.days))
                    }
                    .padding(.vertical, 4)
                }

                switch sc.type {
                case .school, .work:
                    Section {
                        NavigationLink(sc.type == .school ? "Classes, lunch & recess" : "Work blocks, lunch & breaks") {
                            BlockListEditor(sid: id)
                        }
                    }
                    if sc.type == .school {
                        let works = store.s.schedules.filter { $0.type == .work }
                        Section {
                            Picker("Then start", selection: store.field(id, \.chainTo)) {
                                Text("Nothing").tag(String?.none)
                                ForEach(works) { w in Text(w.name).tag(Optional(w.id.uuidString)) }
                            }
                        } footer: {
                            Text("When school ends, the work schedule continues on the same road (“Go to work”). Change the work start time in the work schedule. Add a Work schedule first to pick it here.")
                        }
                    }
                case .gym:
                    GymSections(sid: id)
                }

                Section("Colors") {
                    ColorPicker("Your dot", selection: color(\.dotHex), supportsOpacity: false)
                    ColorPicker("Road (done part)", selection: color(\.accentHex), supportsOpacity: false)
                    RoadmapView(attrs: store.attributes(for: sc), now: Date())
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.88)))
                        .listRowInsets(EdgeInsets())
                }

                Section {
                    Toggle("Run in background", isOn: Binding(
                        get: { sc.background },
                        set: { on in
                            if !store.setBackground(id, on) { showLimit = true }
                            live.applyBackground()
                        }))
                } footer: {
                    Text("Only 2 schedules can run in the background (\(store.backgroundCount)/2 used). Background ones keep updating, switching periods and buzzing while the app is closed. Restart a schedule after editing it.")
                }

                Section {
                    Button("Delete schedule", role: .destructive) { confirmDelete = true }
                }
            }
            .navigationTitle(sc.name)
            .alert("Background limit reached", isPresented: $showLimit) {
                Button("OK", role: .cancel) {}
            } message: { Text("Only 2 schedules can run in the background. Turn one off first.") }
            .confirmationDialog("Delete \(sc.name)?", isPresented: $confirmDelete, titleVisibility: .visible) {
                Button("Delete", role: .destructive) {
                    Task { await live.stop(id.uuidString) }
                    store.delete(id)
                    dismiss()
                }
            }
        }
    }
}

// MARK: - school / work blocks

struct BlockListEditor: View {
    @EnvironmentObject var store: ScheduleStore
    let sid: UUID
    @State private var showGen = false

    var body: some View {
        let type = store.s.schedules.first { $0.id == sid }?.type ?? .school
        List {
            Section {
                ForEach(store.sortedBlocks(sid)) { b in
                    NavigationLink { BlockEditor(sid: sid, bid: b.id) } label: {
                        HStack {
                            Text(b.emoji)
                            VStack(alignment: .leading) {
                                Text(b.name)
                                Text("\(fmt(b.startMin)) – \(fmt(b.endMin))").font(.caption).foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(b.kind == .period ? "P\(b.number)" : b.kind.title).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete { offsets in
                    let ids = offsets.map { store.sortedBlocks(sid)[$0].id }
                    if let i = store.idx(sid) { store.s.schedules[i].blocks.removeAll { ids.contains($0.id) } }
                }
                .onMove { store.move(sid, from: $0, to: $1) }
            } footer: {
                Text("Tap Edit, then drag a row to a new spot. The times stay with the spot, so everything swaps into the right slot.")
            }
        }
        .navigationTitle("Schedule")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                EditButton()
                Menu {
                    ForEach(type.kinds) { k in Button("Add \(k.title.lowercased())") { store.addBlock(sid, k) } }
                    if type == .school {
                        Divider()
                        Button("Quick setup…") { showGen = true }
                    }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showGen) { GeneratorView(sid: sid) }
    }
}

struct BlockEditor: View {
    @EnvironmentObject var store: ScheduleStore
    let sid: UUID
    let bid: UUID

    var body: some View {
        let b = store.block(sid, bid)
        let type = store.s.schedules.first { $0.id == sid }?.type ?? .school
        Form {
            Section("Name") {
                TextField("Name", text: b.name)
                TextField("Emoji", text: b.emoji)
            }
            Section("Type") {
                Picker("Type", selection: b.kind) {
                    ForEach(type.kinds) { Text($0.title).tag($0) }
                }
                if b.wrappedValue.kind == .period {
                    Stepper("Period number: \(b.wrappedValue.number)", value: b.number, in: 1...20)
                }
            }
            Section("Time") {
                DatePicker("Starts", selection: timeBinding(b.startMin), displayedComponents: .hourAndMinute)
                DatePicker("Ends", selection: timeBinding(b.endMin), displayedComponents: .hourAndMinute)
            }
        }
        .navigationTitle(b.wrappedValue.name)
        .onDisappear { store.sort(sid) }
    }
}

struct GeneratorView: View {
    @EnvironmentObject var store: ScheduleStore
    @Environment(\.dismiss) var dismiss
    let sid: UUID
    @State private var count = 6
    @State private var first = 8 * 60 + 30
    @State private var length = 50
    @State private var passing = 5
    @State private var recessAfter = 2
    @State private var recessLen = 15
    @State private var lunchAfter = 4
    @State private var lunchLen = 45

    var body: some View {
        NavigationStack {
            Form {
                Section("Classes") {
                    Stepper("Number of classes: \(count)", value: $count, in: 1...12)
                    DatePicker("First bell", selection: timeBinding($first), displayedComponents: .hourAndMinute)
                    Stepper("Class length: \(length) min", value: $length, in: 10...120, step: 5)
                    Stepper("Passing time: \(passing) min", value: $passing, in: 0...20)
                }
                Section("Breaks (0 = none)") {
                    Stepper("Recess after class: \(recessAfter)", value: $recessAfter, in: 0...12)
                    Stepper("Recess length: \(recessLen) min", value: $recessLen, in: 0...45, step: 5)
                    Stepper("Lunch after class: \(lunchAfter)", value: $lunchAfter, in: 0...12)
                    Stepper("Lunch length: \(lunchLen) min", value: $lunchLen, in: 0...90, step: 5)
                }
                Section {
                    Text("This replaces the current schedule. You can rename everything afterwards.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Quick setup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        store.generate(sid, count: count, firstBell: first, length: length, passing: passing,
                                       recessAfter: recessAfter, recessLen: recessLen,
                                       lunchAfter: lunchAfter, lunchLen: lunchLen)
                        dismiss()
                    }
                }
            }
        }
    }
}

// MARK: - gym

struct GymSections: View {
    @EnvironmentObject var store: ScheduleStore
    let sid: UUID
    private let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    var body: some View {
        let g = store.s.schedules.first { $0.id == sid }?.gym ?? GymConfig()

        Section("Your day") {
            DatePicker("Wake up (reminders start)", selection: timeBinding(store.gym(sid, \.wakeMin)), displayedComponents: .hourAndMinute)
            DatePicker("Bedtime (reminders stop)", selection: timeBinding(store.gym(sid, \.sleepMin)), displayedComponents: .hourAndMinute)
        }

        Section("Workout time") {
            DatePicker("Starts", selection: timeBinding(store.gym(sid, \.workoutStart)), displayedComponents: .hourAndMinute)
            DatePicker("Ends", selection: timeBinding(store.gym(sid, \.workoutEnd)), displayedComponents: .hourAndMinute)
        }

        Section {
            Stepper(durText(g.waterEvery) == "Off" ? "Water: off" : "Water: \(durText(g.waterEvery).lowercased())",
                    value: store.gym(sid, \.waterEvery), in: 0...240, step: 15)
        } header: { Text("💧 Water") } footer: {
            Text("The phone buzzes 3 times and the Live Activity says “Drink water” for 1 minute, then the timer starts over.")
        }

        Section("💊 Supplements") {
            ForEach(g.supps) { p in
                NavigationLink { SupplementEditor(sid: sid, pid: p.id) } label: {
                    HStack {
                        Text(p.emoji)
                        VStack(alignment: .leading) {
                            Text(p.name)
                            Text(durText(p.everyMin)).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .onDelete { offsets in
                if let i = store.idx(sid) { store.s.schedules[i].gym.supps.remove(atOffsets: offsets) }
            }
            Button("Add supplement") {
                if let i = store.idx(sid) { store.s.schedules[i].gym.supps.append(Supplement(name: "Supplement")) }
            }
        }

        Section {
            ForEach(0..<7, id: \.self) { d in
                let groups = g.plan[d].filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
                NavigationLink { DayPlanEditor(sid: sid, day: d) } label: {
                    HStack {
                        Text(dayNames[d])
                        Spacer()
                        Text(groups.isEmpty ? "Rest day 😴" : ScheduleStore.joinGroups(groups))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        } header: { Text("Weekly plan") } footer: {
            Text("Up to 3 muscle groups per day. Leave them all empty for a rest day.")
        }
    }
}

struct SupplementEditor: View {
    @EnvironmentObject var store: ScheduleStore
    let sid: UUID
    let pid: UUID

    var body: some View {
        let p = store.supp(sid, pid)
        Form {
            Section("Name") {
                TextField("Name", text: p.name)
                TextField("Emoji", text: p.emoji)
            }
            Section {
                Stepper(durText(p.wrappedValue.everyMin), value: p.everyMin, in: 30...1440, step: 30)
                Stepper("First one \(p.wrappedValue.firstAfterMin / 60) h \(p.wrappedValue.firstAfterMin % 60) min after you start",
                        value: p.firstAfterMin, in: 0...720, step: 15)
            } header: { Text("How often") } footer: {
                Text("“Once a day” = 24 hours. Reminders count from the moment you start the gym schedule.")
            }
        }
        .navigationTitle(p.wrappedValue.name)
    }
}

struct DayPlanEditor: View {
    @EnvironmentObject var store: ScheduleStore
    let sid: UUID
    let day: Int
    private let dayNames = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

    var body: some View {
        Form {
            Section {
                ForEach(0..<3, id: \.self) { k in
                    TextField("Muscle group \(k + 1)", text: store.plan(sid, day, k))
                }
            } footer: {
                Text("e.g. Legs and Chest → shows “Legs & Chest day” on the Live Activity. All empty = rest day.")
            }
        }
        .navigationTitle(dayNames[day])
    }
}

// MARK: - global settings

struct SettingsView: View {
    @EnvironmentObject var store: ScheduleStore
    var body: some View {
        Form {
            Section("You") {
                TextField("Your name (for the sass)", text: $store.s.name)
            }
            Section {
                Text("Live Activities that keep running in the background use a background-location trick (you'll see the blue pill). Your location is never read or stored.")
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Settings")
    }
}
