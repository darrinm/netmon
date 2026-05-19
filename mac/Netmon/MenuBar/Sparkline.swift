import SwiftUI
import Charts

/// Compact sparkline for the menubar popover. Green line, gradient fill,
/// translucent red bands over any contiguous run of ≥50%-packet-loss
/// samples so outages stay visible after recovery.
struct Sparkline: View {
    let metrics: [NetworkMetric]
    var windowSeconds: TimeInterval = 5 * 60

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { context in
            let now = context.date
            let start = now.addingTimeInterval(-windowSeconds)

            Chart {
                ForEach(Array(metrics.outageSpans().enumerated()), id: \.offset) { _, span in
                    RectangleMark(
                        xStart: .value("Start", span.start),
                        xEnd: .value("End", span.end)
                    )
                    .foregroundStyle(.red.opacity(0.25))
                }

                ForEach(metrics) { m in
                    if m.pingPacketLoss < 100 && m.pingMax > m.pingMin {
                        AreaMark(
                            x: .value("t", m.timestamp),
                            yStart: .value("min", m.pingMin),
                            yEnd: .value("max", m.pingMax)
                        )
                        .foregroundStyle(Color.green.opacity(0.22))
                        .interpolationMethod(.catmullRom)
                    }
                }

                ForEach(metrics) { m in
                    LineMark(
                        x: .value("t", m.timestamp),
                        y: .value("ms", displayValue(m))
                    )
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }
            .chartXScale(domain: start...now)
            .chartXAxis(.hidden)
            .chartYAxis(.hidden)
            .chartPlotStyle { plot in
                plot.background(.clear)
            }
        }
    }

    private func displayValue(_ m: NetworkMetric) -> Double {
        m.pingPacketLoss >= 100 ? 0 : m.pingAvg
    }
}
