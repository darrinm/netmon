import SwiftUI
import Charts

struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @State private var range: HistoryRange = .hours(1)
    @State private var buckets: [Bucket] = []
    @State private var outages: [OutageEvent] = []
    @State private var loading = false

    /// Target render points — we bucket-downsample the raw metrics down to
    /// this many before handing them to Swift Charts. At 1s sampling, even
    /// a 24h range would otherwise put 86,400 LineMarks on screen.
    private let targetPoints = 600

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("History").font(.largeTitle.bold())
                Spacer()
                Picker("Range", selection: $range) {
                    ForEach(HistoryRange.allCases) { r in
                        Text(r.label).tag(r)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 320)
            }

            if loading && buckets.isEmpty {
                placeholder("Loading…")
            } else if buckets.count < 2 {
                placeholder("Not enough samples for this range yet.")
            } else {
                GroupBox("Latency") {
                    latencyChart
                        .frame(height: 220)
                        .padding(.top, 4)
                }

                GroupBox("Packet Loss") {
                    packetLossChart
                        .frame(height: 120)
                        .padding(.top, 4)
                }
            }

            Spacer()
        }
        .padding(24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .task(id: range) { await reload() }
        // Intentionally not refetching on every live sample — at large ranges
        // the SQL query + downsampling is expensive. Re-select the range to
        // refresh, or open Now for live data.
    }

    private var latencyChart: some View {
        Chart {
            // Smoke band: per-bucket min/max envelope.
            ForEach(buckets) { b in
                if b.maxMs > b.minMs {
                    AreaMark(
                        x: .value("Time", b.timestamp),
                        yStart: .value("min", b.minMs),
                        yEnd: .value("max", b.maxMs)
                    )
                    .foregroundStyle(Color.green.opacity(0.20))
                    .interpolationMethod(.monotone)
                }
            }

            ForEach(buckets) { b in
                LineMark(
                    x: .value("Time", b.timestamp),
                    y: .value("ms", b.avgMs)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.green)
                .lineStyle(StrokeStyle(lineWidth: 1.5))
            }

            ForEach(outagesInRange) { o in
                RectangleMark(
                    xStart: .value("Start", o.startTime),
                    xEnd: .value("End", o.endTime ?? Date())
                )
                .foregroundStyle(.red.opacity(0.18))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v)) ms").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine().foregroundStyle(.quaternary.opacity(0.5))
                AxisValueLabel(format: xAxisFormat)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var packetLossChart: some View {
        Chart(buckets) { b in
            BarMark(
                x: .value("Time", b.timestamp),
                y: .value("%", b.maxPacketLoss)
            )
            .foregroundStyle(barColor(for: b.maxPacketLoss))
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading, values: [0, 50, 100]) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v))%").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .chartXAxis {
            AxisMarks(values: .automatic) { _ in
                AxisGridLine().foregroundStyle(.quaternary.opacity(0.5))
                AxisValueLabel(format: xAxisFormat)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func barColor(for loss: Double) -> Color {
        if loss == 0 { return .green }
        if loss < 5  { return .yellow }
        return .red
    }

    private var xAxisFormat: Date.FormatStyle {
        switch range {
        case .hours(let h) where h <= 6:  return .dateTime.hour().minute()
        case .hours(let h) where h <= 24: return .dateTime.hour()
        default:                          return .dateTime.month(.abbreviated).day()
        }
    }

    private var outagesInRange: [OutageEvent] {
        guard let first = buckets.first?.timestamp,
              let last  = buckets.last?.timestamp else { return [] }
        return outages.filter { o in
            o.startTime <= last && (o.endTime ?? Date()) >= first
        }
    }

    private func placeholder(_ text: String) -> some View {
        Text(text)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, minHeight: 240, alignment: .center)
    }

    private func reload() async {
        loading = true
        async let mTask = app.fetchMetrics(in: range)
        async let oTask = app.fetchOutages()
        let metrics = await mTask
        let outagesAll = await oTask
        // Move the heavy bucketing work off the main actor.
        let target = targetPoints
        let downsampled = await Task.detached { Bucket.downsample(metrics, targetPoints: target) }.value
        buckets = downsampled
        outages = outagesAll
        loading = false
    }
}

/// One row in the downsampled chart series. Each bucket summarizes a window
/// of raw samples by min / avg / max latency and the worst packet loss in
/// the window — preserves spikes and the distribution shape (Smokeping-style)
/// while keeping the chart render count bounded.
struct Bucket: Identifiable, Sendable {
    var id: Date { timestamp }
    var timestamp: Date
    var minMs: Double
    var avgMs: Double
    var maxMs: Double
    var maxPacketLoss: Double

    static func downsample(_ metrics: [NetworkMetric], targetPoints: Int) -> [Bucket] {
        guard !metrics.isEmpty else { return [] }
        // Already small enough — promote each metric to a one-sample bucket.
        if metrics.count <= targetPoints {
            return metrics.map {
                Bucket(
                    timestamp: $0.timestamp,
                    minMs: $0.pingMin,
                    avgMs: $0.pingAvg,
                    maxMs: $0.pingMax,
                    maxPacketLoss: $0.pingPacketLoss
                )
            }
        }

        let bucketSize = Swift.max(1, metrics.count / targetPoints)
        var result: [Bucket] = []
        result.reserveCapacity(metrics.count / bucketSize + 1)

        var i = 0
        while i < metrics.count {
            let end = Swift.min(i + bucketSize, metrics.count)
            let slice = metrics[i..<end]

            let valid = slice.filter { $0.pingPacketLoss < 100 }
            let minLat = valid.map(\.pingMin).min() ?? 0
            let maxLat = valid.map(\.pingMax).max() ?? 0
            let avgLat: Double = valid.isEmpty
                ? 0
                : valid.map(\.pingAvg).reduce(0, +) / Double(valid.count)
            let maxLoss = slice.map(\.pingPacketLoss).max() ?? 0
            let midpoint = slice[slice.index(slice.startIndex, offsetBy: slice.count / 2)].timestamp

            result.append(Bucket(
                timestamp: midpoint,
                minMs: minLat,
                avgMs: avgLat,
                maxMs: maxLat,
                maxPacketLoss: maxLoss
            ))
            i = end
        }
        return result
    }
}
