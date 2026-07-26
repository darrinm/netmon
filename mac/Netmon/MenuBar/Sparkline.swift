import SwiftUI
import Charts

/// Compact sparkline for the menubar popover. Green line, gradient fill,
/// translucent red bands over any contiguous run of ≥50%-packet-loss
/// samples so outages stay visible after recovery.
struct Sparkline: View {
    let metrics: [NetworkMetric]
    var windowSeconds: TimeInterval = 5 * 60

    var body: some View {
        // Spans depend only on `metrics`, so compute once per data change —
        // not on every 0.1s tick.
        let spans = metrics.outageSpans()
        // LiveTimeline, not TimelineView: MenuBarExtra keeps this view alive
        // after the popover is dismissed, and an unguarded timeline would keep
        // re-rendering this chart with nothing on screen.
        return LiveTimeline(interval: 0.1) { now in
            let start = now.addingTimeInterval(-windowSeconds)

            Chart {
                ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
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
                        y: .value("ms", m.displayLatency)
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
}
