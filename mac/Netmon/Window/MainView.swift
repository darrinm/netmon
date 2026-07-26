import SwiftUI
import Charts

struct MainView: View {
    @Environment(AppModel.self) private var app
    @State private var selection: Section? = .now

    enum Section: String, CaseIterable, Identifiable {
        case now = "Now"
        case history = "History"
        case outages = "Outages"
        case trends = "Trends"
        case settings = "Settings"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .now: return "gauge.with.dots.needle.50percent"
            case .history: return "chart.xyaxis.line"
            case .outages: return "exclamationmark.triangle"
            case .trends: return "chart.line.uptrend.xyaxis"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: $selection) { section in
                Label(section.rawValue, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationSplitViewColumnWidth(min: 160, ideal: 180)
        } detail: {
            switch selection ?? .now {
            case .now:      NowDetail()
            case .history:  HistoryView()
            case .outages:  OutagesView()
            case .trends:   TrendsView()
            case .settings: SettingsView(prefs: Preferences.shared)
                                .onDisappear { Task { await app.applyPreferences() } }
            }
        }
    }
}

private struct NowDetail: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Now").font(.largeTitle.bold())

            HStack(alignment: .top, spacing: 24) {
                bigStat(title: "Latency (5m avg)", value: latencyText,
                        secondary: minMaxText, tint: app.health.tint)
                bigStat(title: "Packet Loss (5m)", value: lossText, secondary: nil)
                bigStat(title: "Uptime (5m)", value: uptimeText, secondary: nil)
                bigStat(title: "Gateway loss (5m)", value: gatewayLossText,
                        secondary: gatewayLatencyText)
            }

            GroupBox("Last 5 Minutes") {
                if app.recentMetrics.count < 2 {
                    Text("Collecting samples…")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
                } else {
                    RecentLatencyChart(metrics: app.recentMetrics)
                        .frame(height: 200)
                        .padding(.top, 4)
                }
            }

            if let outage = app.currentOutage {
                GroupBox("Ongoing Outage") {
                    VStack(alignment: .leading) {
                        Text("Started \(outage.startTime.formatted(.relative(presentation: .named)))")
                        Text("Type: \(outage.type.rawValue.capitalized)")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let err = app.startupError {
                Text(err).foregroundStyle(.red)
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }

    private func bigStat(title: String, value: String, secondary: String?, tint: Color = .primary) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 32, weight: .semibold, design: .rounded))
                .foregroundStyle(tint)
                .monospacedDigit()
            if let secondary {
                Text(secondary).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// Latencies of samples that actually got a reply — averaged over the 5m window.
    private var validLatencies: [Double] {
        app.recentMetrics
            .filter { $0.pingPacketLoss < 100 }
            .map(\.pingAvg)
    }

    private var latencyText: String {
        guard !validLatencies.isEmpty else { return "—" }
        let avg = validLatencies.reduce(0, +) / Double(validLatencies.count)
        return String(format: "%.0f ms", avg)
    }

    private var minMaxText: String? {
        guard let lo = validLatencies.min(), let hi = validLatencies.max() else { return nil }
        return String(format: "min %.0f · max %.0f", lo, hi)
    }

    private var lossText: String {
        guard !app.recentMetrics.isEmpty else { return "—" }
        let avg = app.recentMetrics
            .map(\.pingPacketLoss)
            .reduce(0, +) / Double(app.recentMetrics.count)
        return String(format: "%.1f%%", avg)
    }

    /// Fraction of recent samples where packet loss stayed below the outage
    /// threshold (50%). Single-sample blips that didn't open an outage in
    /// the tracker still count against uptime here.
    private var uptimeText: String {
        guard !app.recentMetrics.isEmpty else { return "—" }
        let up = app.recentMetrics.filter { $0.pingPacketLoss < NetworkThresholds.outagePacketLoss }.count
        let pct = Double(up) / Double(app.recentMetrics.count) * 100
        return String(format: "%.1f%%", pct)
    }

    /// 5-minute mean packet loss to the LAN gateway. If this stays near 0
    /// while "Packet Loss" rises, the trouble is upstream of the router;
    /// if both rise together, it's the local Mac↔router link.
    private var gatewayLossText: String {
        let losses = app.recentMetrics.compactMap { $0.gatewayPacketLoss }
        guard !losses.isEmpty else { return "—" }
        return String(format: "%.1f%%", losses.reduce(0, +) / Double(losses.count))
    }

    private var gatewayLatencyText: String? {
        let lats = app.recentMetrics.compactMap { m -> Double? in
            guard let avg = m.gatewayPingAvg, (m.gatewayPacketLoss ?? 100) < 100 else { return nil }
            return avg
        }
        guard !lats.isEmpty else { return nil }
        return String(format: "%.1f ms avg", lats.reduce(0, +) / Double(lats.count))
    }
}

private struct RecentLatencyChart: View {
    let metrics: [NetworkMetric]
    /// Visible window length (anchored to a continuously-advancing "now").
    var windowSeconds: TimeInterval = 5 * 60

    var body: some View {
        // Spans depend only on `metrics` — compute once per data change,
        // not on every 0.1s tick.
        let spans = metrics.outageSpans()
        // Ticks 10× per second so the X-axis advances smoothly instead of
        // jumping when a new sample arrives — but only while this window is
        // actually on screen, not when it's closed or fully occluded.
        return LiveTimeline(interval: 0.1) { now in
            let start = now.addingTimeInterval(-windowSeconds)

            Chart {
                ForEach(Array(spans.enumerated()), id: \.offset) { _, span in
                    RectangleMark(
                        xStart: .value("Start", span.start),
                        xEnd: .value("End", span.end)
                    )
                    .foregroundStyle(.red.opacity(0.22))
                }

                ForEach(metrics) { m in
                    if m.pingPacketLoss < 100 && m.pingMax > m.pingMin {
                        AreaMark(
                            x: .value("Time", m.timestamp),
                            yStart: .value("min", m.pingMin),
                            yEnd: .value("max", m.pingMax)
                        )
                        .foregroundStyle(Color.green.opacity(0.20))
                        .interpolationMethod(.monotone)
                    }
                }

                ForEach(metrics) { m in
                    LineMark(
                        x: .value("Time", m.timestamp),
                        y: .value("ms", m.displayLatency)
                    )
                    .interpolationMethod(.monotone)
                    .foregroundStyle(.green)
                    .lineStyle(StrokeStyle(lineWidth: 2))
                }
            }
            .chartXScale(domain: start...now)
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
                AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                    AxisGridLine().foregroundStyle(.quaternary.opacity(0.4))
                    AxisValueLabel(format: .dateTime.hour().minute())
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
