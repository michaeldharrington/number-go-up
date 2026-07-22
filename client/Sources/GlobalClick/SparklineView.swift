import SwiftUI

/// 24-hour sparkline drawn with a raw Path — no Charts dependency.
struct SparklineView: View {
    let points: [HistoryPoint]

    var body: some View {
        GeometryReader { geo in
            let values = points.map { Double($0.total) }
            if values.count >= 2,
               let min = values.min(), let max = values.max() {
                // Flat history still deserves a visible line: give a
                // zero-range series a tiny artificial span.
                let span = max - min == 0 ? 1 : max - min
                let stepX = geo.size.width / Double(values.count - 1)
                Path { p in
                    for (i, v) in values.enumerated() {
                        let x = Double(i) * stepX
                        let y = geo.size.height * (1 - (v - min) / span)
                        i == 0 ? p.move(to: CGPoint(x: x, y: y))
                               : p.addLine(to: CGPoint(x: x, y: y))
                    }
                }
                .stroke(.tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            } else {
                Text("Sparkline appears after a few hours of data")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: 32)
    }
}
