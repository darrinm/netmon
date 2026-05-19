import SwiftUI
import Charts

/// Compact Swift Charts sparkline for the menubar popover.
/// No axes, single accent-tinted line with a soft gradient area fill.
struct Sparkline: View {
    let metrics: [NetworkMetric]
    var tint: Color = .accentColor

    var body: some View {
        Chart(metrics) { metric in
            LineMark(
                x: .value("t", metric.timestamp),
                y: .value("ms", displayValue(metric))
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(tint)
            .lineStyle(StrokeStyle(lineWidth: 1.5))

            AreaMark(
                x: .value("t", metric.timestamp),
                y: .value("ms", displayValue(metric))
            )
            .interpolationMethod(.catmullRom)
            .foregroundStyle(
                LinearGradient(
                    colors: [tint.opacity(0.35), tint.opacity(0.02)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartPlotStyle { plot in
            plot.background(.clear)
        }
    }

    /// Treat full outages (no reply) as 0 so the line drops cleanly; otherwise show avg ms.
    private func displayValue(_ m: NetworkMetric) -> Double {
        m.pingPacketLoss >= 100 ? 0 : m.pingAvg
    }
}
