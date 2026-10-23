import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: ScheduleStore
    @EnvironmentObject var live: LiveActivityManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    TimelineView(.periodic(from: .now, by: 30)) { tl in
                        statusCard(tl.date)
                    }

                    HStack(spacing: 12) {
                        Button {
                            Task { await live.start(store) }
                        } label: {
                            Label(live.isRunning ? "Restart" : "Start", systemImage: "play.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(.green).controlSize(.large)

                        Button(role: .destructive) {
                            Task { await live.stop() }
                        } label: {
                            Label("End", systemImage: "stop.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).controlSize(.large).disabled(!live.isRunning)
                    }

                    if let e = live.error {
                        Text(e).font(.footnote).foregroundStyle(.red)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Today's lineup").font(.headline)
                        ForEach(store.s.blocks.sorted { $0.startMin < $1.startMin }) { b in
                            HStack {
                                Text(b.emoji).frame(width: 30)
                                VStack(alignment: .leading) {
                                    Text(b.name).font(.subheadline.weight(.semibold))
                                    Text(b.kind == .period ? "Period \(b.number)" : b.kind.title)
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Text("\(fmt(b.startMin)) – \(fmt(b.endMin))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 4)
                            Divider()
                        }
                    }
                }
                .padding()
            }
            .navigationTitle(store.s.name.isEmpty ? "Schedule" : "\(store.s.name)'s Day")
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink { ScheduleEditor() } label: { Image(systemName: "slider.horizontal.3") }
                    NavigationLink { SettingsView() } label: { Image(systemName: "paintpalette") }
                }
            }
        }
    }

    private func statusCard(_ date: Date) -> some View {
        let attrs = store.attributes()
        let info = attrs.info(at: date)
        return VStack(alignment: .leading, spacing: 12) {
            Text(quip(info)).font(.footnote.weight(.medium)).foregroundStyle(.white.opacity(0.7))
            HStack(spacing: 12) {
                Text(info.emoji).font(.largeTitle)
                VStack(alignment: .leading) {
                    Text(info.title).font(.title2.bold())
                    Text(info.sub).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                if let e = info.end, !info.done, e > date {
                    Text(timerInterval: date...e, countsDown: true, showsHours: false)
                        .font(.title2.bold().monospacedDigit())
                }
            }
            RoadmapView(attrs: attrs, now: date)
        }
        .foregroundStyle(.white)
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 26).fill(Color.black.opacity(0.88)))
    }

    private func quip(_ i: NowInfo) -> String {
        let n = store.s.name.isEmpty ? "legend" : store.s.name
        if i.done { return "School's out, \(n). Go touch grass 🌱" }
        if i.start == nil { return "Backpack check, \(n)! 🎒" }
        if !i.solid { return i.emoji == "🚶" ? "Walk fast, look casual 😎" : "\(i.title) time. You earned it, \(n)." }
        return "Brain on, \(n). Phone away 🧠"
    }
}
