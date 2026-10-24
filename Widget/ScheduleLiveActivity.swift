import WidgetKit
import SwiftUI
import ActivityKit

@main
struct ScheduleWidgetBundle: WidgetBundle {
    var body: some Widget { ScheduleLiveActivity() }
}

struct TimerText: View {
    let info: NowInfo
    var body: some View {
        let now = Date()
        if let end = info.timerEnd, !info.done, end > now {
            Text(timerInterval: now...end, countsDown: true, showsHours: end.timeIntervalSince(now) >= 3600)
                .monospacedDigit()
                .multilineTextAlignment(.trailing)
        } else {
            Text(info.emoji)
        }
    }
}

struct TimesRow: View {
    let info: NowInfo
    var body: some View {
        HStack {
            if let s = info.start {
                Text("Starts ") + Text(s, style: .time)
                Spacer()
                if let e = info.end { Text("Ends ") + Text(e, style: .time) }
            } else if let n = info.note {
                Text(n)
                Spacer()
            }
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(.white.opacity(0.75))
    }
}

struct LockScreenView: View {
    let attrs: ScheduleAttributes
    let state: ScheduleAttributes.ContentState
    var body: some View {
        let now = Date()
        let info = attrs.info(at: now, state: state)
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Text(info.emoji).font(.title2)
                    .frame(width: 44, height: 44)
                    .background(Circle().fill(Color.white.opacity(0.18)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(info.title).font(.title3.bold()).lineLimit(1).minimumScaleFactor(0.6)
                    Text(info.sub).font(.subheadline).foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1).minimumScaleFactor(0.7)
                }
                Spacer(minLength: 4)
                TimerText(info: info).font(.title2.bold()).frame(maxWidth: 100, alignment: .trailing)
            }
            RoadmapView(attrs: attrs, now: now)
            TimesRow(info: info)
        }
        .foregroundStyle(.white)
        .padding(16)
        .activityBackgroundTint(Color.black.opacity(0.78))
        .activitySystemActionForegroundColor(.white)
    }
}

struct ScheduleLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ScheduleAttributes.self) { context in
            LockScreenView(attrs: context.attributes, state: context.state)
        } dynamicIsland: { context in
            let attrs = context.attributes
            let now = Date()
            let info = attrs.info(at: now, state: context.state)
            return DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Text(info.short).font(.title2.bold()).foregroundStyle(Color(hex: attrs.dotHex))
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    TimerText(info: info).font(.title3.bold()).frame(maxWidth: 90, alignment: .trailing)
                        .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    Text(info.title).font(.headline).lineLimit(1).minimumScaleFactor(0.6)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 8) {
                        RoadmapView(attrs: attrs, now: now)
                        TimesRow(info: info)
                    }
                    // keeps everything clear of the island's rounded corners so nothing gets clipped
                    .padding(.horizontal, 16)
                    .padding(.top, 6)
                    .padding(.bottom, 12)
                }
            } compactLeading: {
                Text(info.short).font(.caption.bold()).foregroundStyle(Color(hex: attrs.dotHex))
            } compactTrailing: {
                TimerText(info: info).font(.caption.bold()).frame(width: 56)
                    .minimumScaleFactor(0.7)
            } minimal: {
                Text(info.short).font(.caption2.bold())
            }
        }
    }
}
