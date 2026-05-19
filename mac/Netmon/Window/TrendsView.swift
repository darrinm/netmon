import SwiftUI
import Charts

struct TrendsView: View {
    @Environment(AppModel.self) private var app
    @State private var windowDays: Int = 7
    @State private var comparison: TrendAnalyzer.Comparison?
    @State private var loading = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Trends").font(.largeTitle.bold())
                    Spacer()
                    Picker("Window", selection: $windowDays) {
                        Text("1 day").tag(1)
                        Text("7 days").tag(7)
                        Text("30 days").tag(30)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                }

                if let c = comparison {
                    Text("Last \(c.windowDays) day\(c.windowDays == 1 ? "" : "s") vs the previous \(c.windowDays) day\(c.windowDays == 1 ? "" : "s")")
                        .foregroundStyle(.secondary)

                    HStack(spacing: 16) {
                        deltaCard("Median latency",
                                  recent: String(format: "%.0f ms", c.recent.medianLatencyMs),
                                  delta: c.medianLatencyDeltaPct,
                                  worseIsHigher: true)
                        deltaCard("p95 latency",
                                  recent: String(format: "%.0f ms", c.recent.p95LatencyMs),
                                  delta: c.p95LatencyDeltaPct,
                                  worseIsHigher: true)
                    }

                    HStack(spacing: 16) {
                        deltaCard("Mean packet loss",
                                  recent: String(format: "%.2f%%", c.recent.meanPacketLoss),
                                  delta: c.packetLossDeltaPct,
                                  worseIsHigher: true)
                        deltaCard("Total downtime",
                                  recent: formatSeconds(c.recent.outageSeconds),
                                  delta: c.outageSecondsDeltaPct,
                                  worseIsHigher: true)
                    }

                    if c.recent.samples < 30 || c.prior.samples < 30 {
                        Text("Not enough samples yet — trends become meaningful after a few days of monitoring.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else if loading {
                    Text("Computing trends…").foregroundStyle(.secondary)
                } else {
                    Text("No data yet.").foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .task(id: windowDays) { await reload() }
        .onChange(of: app.sessionSamples) { _, _ in
            Task { await reload() }
        }
    }

    private func reload() async {
        loading = true
        let metrics = await app.fetchMetrics(in: .all)
        let outages = await app.fetchOutages()
        comparison = TrendAnalyzer.compare(metrics: metrics, outages: outages, windowDays: windowDays)
        loading = false
    }

    @ViewBuilder
    private func deltaCard(_ title: String, recent: String, delta: Double?, worseIsHigher: Bool) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.caption).foregroundStyle(.secondary)
                Text(recent)
                    .font(.system(size: 28, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                deltaLabel(delta, worseIsHigher: worseIsHigher)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private func deltaLabel(_ delta: Double?, worseIsHigher: Bool) -> some View {
        if let d = delta {
            let isWorse = worseIsHigher ? d > 0 : d < 0
            let color: Color = abs(d) < 5 ? .secondary : (isWorse ? .red : .green)
            let symbol = d > 0 ? "▲" : (d < 0 ? "▼" : "—")
            HStack(spacing: 4) {
                Text(symbol)
                Text(String(format: "%.0f%% vs previous window", abs(d)))
            }
            .font(.caption)
            .foregroundStyle(color)
        } else {
            Text("no comparison (prior window empty)")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
    }

    private func formatSeconds(_ s: Double) -> String {
        if s < 1 { return "0s" }
        if s < 60 { return String(format: "%.0fs", s) }
        if s < 3600 { return String(format: "%dm %ds", Int(s/60), Int(s.truncatingRemainder(dividingBy: 60))) }
        return String(format: "%.1fh", s/3600)
    }
}
