import SwiftUI

func timeBinding(_ m: Binding<Int>) -> Binding<Date> {
    Binding(
        get: { Calendar.current.date(bySettingHour: m.wrappedValue / 60, minute: m.wrappedValue % 60, second: 0, of: Date()) ?? Date() },
        set: {
            let c = Calendar.current.dateComponents([.hour, .minute], from: $0)
            m.wrappedValue = (c.hour ?? 0) * 60 + (c.minute ?? 0)
        })
}

struct ScheduleEditor: View {
    @EnvironmentObject var store: ScheduleStore
    @State private var showGen = false

    var body: some View {
        List {
            ForEach(store.s.blocks) { b in
                NavigationLink { BlockEditor(id: b.id) } label: {
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
            .onDelete { store.s.blocks.remove(atOffsets: $0) }
        }
        .navigationTitle("Edit schedule")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Add class") { store.add(.period) }
                    Button("Add lunch") { store.add(.lunch) }
                    Button("Add recess") { store.add(.recess) }
                    Button("Add other") { store.add(.other) }
                    Divider()
                    Button("Quick setup…") { showGen = true }
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(isPresented: $showGen) { GeneratorView() }
        .onDisappear { store.sort() }
    }
}

struct BlockEditor: View {
    @EnvironmentObject var store: ScheduleStore
    let id: UUID

    var body: some View {
        let b = store.binding(id)
        Form {
            Section("Name") {
                TextField("Name", text: b.name)
                TextField("Emoji", text: b.emoji)
            }
            Section("Type") {
                Picker("Type", selection: b.kind) {
                    ForEach(BlockKind.allCases) { Text($0.title).tag($0) }
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
        .onDisappear { store.sort() }
    }
}

struct GeneratorView: View {
    @EnvironmentObject var store: ScheduleStore
    @Environment(\.dismiss) var dismiss
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
                Section { Text("This replaces your current schedule. You can rename everything afterwards.")
                    .font(.footnote).foregroundStyle(.secondary) }
            }
            .navigationTitle("Quick setup")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Create") {
                        store.generate(count: count, firstBell: first, length: length, passing: passing,
                                       recessAfter: recessAfter, recessLen: recessLen,
                                       lunchAfter: lunchAfter, lunchLen: lunchLen)
                        dismiss()
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject var store: ScheduleStore

    private func color(_ kp: WritableKeyPath<Settings, String>) -> Binding<Color> {
        Binding(get: { Color(hex: store.s[keyPath: kp]) },
                set: { store.s[keyPath: kp] = $0.hex })
    }

    var body: some View {
        Form {
            Section("You") {
                TextField("Your name (for the sass)", text: $store.s.name)
            }
            Section("Colors") {
                ColorPicker("Your dot", selection: color(\.dotHex), supportsOpacity: false)
                ColorPicker("Road (done part)", selection: color(\.accentHex), supportsOpacity: false)
                RoadmapView(attrs: store.attributes(), now: Date())
                    .padding(14)
                    .background(RoundedRectangle(cornerRadius: 16).fill(Color.black.opacity(0.88)))
                    .listRowInsets(EdgeInsets())
            }
            Section {
                Toggle("Keep updating in background", isOn: $store.s.keepAlive)
            } footer: {
                Text("Lets the Live Activity switch periods and move your dot on time while the app is closed. Uses a background-location trick (you'll see the blue pill) but never reads your location. Restart the Live Activity after changing your schedule or colors.")
            }
        }
        .navigationTitle("Style & settings")
    }
}
