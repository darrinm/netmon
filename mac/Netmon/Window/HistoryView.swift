import SwiftUI
import Charts

struct HistoryView: View {
    @Environment(AppModel.self) private var app
    @State private var range: HistoryRange = .hours(1)
    @State private var metrics: [NetworkMetric] = []
    @State private var outages: [OutageEvent] = []
    @State private var loading = false

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

            if loading && metrics.isEmpty {
                placeholder("Loading…")
            } else if metrics.count < 2 {
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
        .onChange(of: app.sessionSamples) { _, _ in
            // Refresh after the live tick so the chart stays current.
            Task { await reload() }
        }
    }

    private var latencyChart: some View {
        Chart {
            ForEach(metrics) { m in
                LineMark(
                    x: .value("Time", m.timestamp),
                    y: .value("ms", m.pingAvg)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(.tint)

                AreaMark(
                    x: .value("Time", m.timestamp),
                    y: .value("ms", m.pingAvg)
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [.accentColor.opacity(0.35), .accentColor.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
            }

            ForEach(outagesInRange) { o in
                RectangleMark(
                    xStart: .value("Start", o.startTime),
                    xEnd: .value("End", o.endTime ?? Date())
                )
                .foregroundStyle(.red.opacity(0.12))
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
        Chart(metrics) { m in
            BarMark(
                x: .value("Time", m.timestamp),
                y: .value("%", m.pingPacketLoss)
            )
            .foregroundStyle(barColor(for: m.pingPacketLoss))
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
        guard let first = metrics.first?.timestamp,
              let last  = metrics.last?.timestamp else { return [] }
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
        async let m = app.fetchMetrics(in: range)
        async let o = app.fetchOutages()
        metrics = await m
        outages = await o
        loading = false
    }
}
