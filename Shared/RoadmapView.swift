import SwiftUI

/// The "road": solid lines = classes, dotted = lunch / recess / walking time. The circle is you.
struct RoadmapView: View {
    let attrs: ScheduleAttributes
    let now: Date
    var height: CGFloat = 18

    var body: some View {
        let segs = attrs.segments
        let startM = Double(segs.first?.startMin ?? 0)
        let total = max(1, Double(segs.last?.endMin ?? 1) - startM)
        let m = min(max(attrs.minutes(at: now), startM), startM + total)
        GeometryReader { geo in
            let w = geo.size.width
            let px = CGFloat((m - startM) / total) * w
            ZStack(alignment: .leading) {
                road(segs, startM, total, w, Color.white.opacity(0.28))
                road(segs, startM, total, w, Color(hex: attrs.accentHex))
                    .mask(alignment: .leading) { Rectangle().frame(width: px) }
                Circle()
                    .fill(Color(hex: attrs.dotHex))
                    .frame(width: height, height: height)
                    .overlay(Circle().stroke(Color.white, lineWidth: 3))
                    .offset(x: min(max(px - height / 2, 0), max(w - height, 0)))
            }
            .frame(width: w, height: height)
        }
        .frame(height: height)
    }

    private func road(_ segs: [Segment], _ startM: Double, _ total: Double, _ w: CGFloat, _ color: Color) -> some View {
        ZStack(alignment: .leading) {
            ForEach(segs) { s in
                let x = CGFloat((Double(s.startMin) - startM) / total) * w
                let len = CGFloat(Double(s.endMin - s.startMin) / total) * w
                if s.solid {
                    Capsule().fill(color)
                        .frame(width: max(len - 3, 2), height: 6)
                        .offset(x: x + 1.5)
                } else {
                    Path { p in
                        p.move(to: CGPoint(x: x + 3, y: height / 2))
                        p.addLine(to: CGPoint(x: x + max(len - 3, 4), y: height / 2))
                    }
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [0.1, 7]))
                }
            }
        }
        .frame(width: w, height: height)
    }
}
