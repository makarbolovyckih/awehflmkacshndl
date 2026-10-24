import SwiftUI

func daysText(_ d: [Int]) -> String {
    let set = Set(d)
    if set.count == 7 { return "Every day" }
    if set == [2, 3, 4, 5, 6] { return "Mon–Fri" }
    if set == [1, 7] { return "Weekends" }
    if set.isEmpty { return "No days" }
    let n = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]
    return set.sorted().map { n[$0 - 1] }.joined(separator: ", ")
}

struct ContentView: View {
    @EnvironmentObject var store: ScheduleStore
    @EnvironmentObject var live: LiveActivityManager
    @State private var showNew = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(store.s.schedules) { sc in
                        ScheduleCard(id: sc.id)
                    }
                    if let e = live.error {
                        Text(e).font(.footnote).foregroundStyle(.red)
                    }
                    Button { showNew = true } label: {
                        Label(store.canAdd ? "New schedule" : "3 of 3 schedules used", systemImage: "plus.circle.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).controlSize(.large).disabled(!store.canAdd)

                    Text("Shortcuts app → Automation → Time of Day → “Start Schedule” to launch a schedule automatically (like Gym at your wake-up time).")
                        .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding()
            }
            .navigationTitle(store.s.name.isEmpty ? "Schedules" : "\(store.s.name)'s Day")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink { SettingsView() } label: { Image(systemName: "person.crop.circle") }
                }
            }
            .sheet(isPresented: $showNew) { NewScheduleSheet() }
        }
    }
}

struct ScheduleCard: View {
    @EnvironmentObject var store: ScheduleStore
    @EnvironmentObject var live: LiveActivityManager
    let id: UUID

    var body: some View {
        if let sc = store.s.schedules.first(where: { $0.id == id }) {
            let running = live.runningIDs.contains(sc.id.uuidString)
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text(sc.type.emoji).font(.title)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(sc.name).font(.headline)
                        Text("\(sc.type.title) · \(daysText(sc.days))" + (sc.background ? " · background" : ""))
                            .font(.caption).foregroundStyle(.white.opacity(0.6))
                    }
                    Spacer()
                    NavigationLink { ScheduleDetail(id: id) } label: {
                        Image(systemName: "slider.horizontal.3").font(.title3)
                    }
                }
                TimelineView(.periodic(from: .now, by: 30)) { tl in
                    status(sc, tl.date)
                }
                if sc.type == .gym { workoutList(sc) }
                HStack(spacing: 12) {
                    Button {
                        Task { await live.start(sc.id.uuidString) }
                    } label: {
                        Label(running ? "Restart" : "Start", systemImage: "play.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).tint(.green).controlSize(.large)

                    Button(role: .destructive) {
                        Task { await live.stop(sc.id.uuidString) }
                    } label: {
                        Label("End", systemImage: "stop.fill").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered).controlSize(.large).disabled(!running)
                }
            }
            .foregroundStyle(.white)
            .padding(18)
            .background(RoundedRectangle(cornerRadius: 26).fill(Color.black.opacity(0.88)))
        }
    }

    @ViewBuilder
    private func workoutList(_ sc: Schedule) -> some View {
        let day = Calendar.current.component(.weekday, from: Date()) - 1
        let ex = sc.gym.exercises.indices.contains(day) ? sc.gym.exercises[day] : []
        if !ex.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Today's workout").font(.subheadline.weight(.semibold))
                ForEach(ex) { e in
                    let d = store.done(sc.id, e)
                    Button { store.bump(sc.id, e) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: d >= e.sets ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(d >= e.sets ? Color.green : Color.white.opacity(0.6))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(e.name).font(.subheadline)
                                Text("\(e.sets) × \(e.reps)" + (e.weight.isEmpty ? "" : " · \(e.weight)"))
                                    .font(.caption).foregroundStyle(.white.opacity(0.6))
                            }
                            Spacer()
                            Text("\(d)/\(e.sets) sets").font(.caption.monospacedDigit())
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                    .buttonStyle(.plain)
                }
                Text("Tap an exercise after each set.").font(.caption2).foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private func status(_ sc: Schedule, _ date: Date) -> some View {
        let attrs = store.attributes(for: sc)
        let info = attrs.info(at: date)
        let today = sc.days.contains(Calendar.current.component(.weekday, from: date))
        return VStack(alignment: .leading, spacing: 10) {
            if today {
                HStack(spacing: 12) {
                    Text(info.emoji).font(.largeTitle)
                    VStack(alignment: .leading) {
                        Text(info.title).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.7)
                        Text(info.sub).font(.subheadline).foregroundStyle(.white.opacity(0.7)).lineLimit(1)
                    }
                    Spacer()
                    if let e = info.timerEnd, !info.done, e > date {
                        Text(timerInterval: date...e, countsDown: true, showsHours: e.timeIntervalSince(date) >= 3600)
                            .font(.title3.bold().monospacedDigit())
                    }
                }
                RoadmapView(attrs: attrs, now: date)
            } else {
                Text("😴 Not a \(sc.type.title.lowercased()) day. Enjoy it!")
                    .font(.subheadline).foregroundStyle(.white.opacity(0.8))
            }
        }
    }
}

struct NewScheduleSheet: View {
    @EnvironmentObject var store: ScheduleStore
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(ScheduleType.allCases) { t in
                        Button {
                            store.add(t)
                            dismiss()
                        } label: {
                            HStack(spacing: 14) {
                                Text(t.emoji).font(.largeTitle)
                                VStack(alignment: .leading) {
                                    Text(t.title).font(.headline)
                                    Text(t.blurb).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 6)
                        }
                        .tint(.primary)
                    }
                } footer: {
                    Text("You can have up to 3 schedules.")
                }
            }
            .navigationTitle("New schedule")
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
        }
        .presentationDetents([.medium])
    }
}
