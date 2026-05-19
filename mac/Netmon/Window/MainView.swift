import SwiftUI
import Charts

struct MainView: View {
    @Environment(AppModel.self) private var app
    @State private var selection: Section? = .now

    enum Section: String, CaseIterable, Identifiable {
        case now = "Now"
        case history = "History"
        case outages = "Outages"
        case settings = "Settings"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .now: return "gauge.with.dots.needle.50percent"
            case .history: return "chart.xyaxis.line"
            case .outages: return "exclamationmark.triangle"
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

            HStack(spacing: 24) {
                bigStat(title: "Latency", value: latencyText,
                        secondary: minMaxText, tint: app.health.tint)
                bigStat(title: "Packet Loss", value: lossText, secondary: nil)
                bigStat(title: "Uptime (5m)", value: uptimeText, secondary: nil)
            }

            GroupBox("Last 5 Minutes") {
                if app.recentMetrics.count < 2 {
                    Text("Collecting samples…")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 200, alignment: .center)
                } else {
                    RecentLatencyChart(metrics: app.recentMetrics, tint: app.health.tint)
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

    private var latencyText: String {
        guard let m = app.latestMetric else { return "—" }
        if m.pingPacketLoss == 100 { return "—" }
        return String(format: "%.0f ms", m.pingAvg)
    }

    private var minMaxText: String? {
        guard let m = app.latestMetric, m.pingPacketLoss < 100 else { return nil }
        return String(format: "min %.0f · max %.0f", m.pingMin, m.pingMax)
    }

    private var lossText: String {
        guard let m = app.latestMetric else { return "—" }
        return String(format: "%.1f%%", m.pingPacketLoss)
    }

    private var uptimeText: String {
        guard !app.recentMetrics.isEmpty else { return "—" }
        let up = app.recentMetrics.filter { !$0.isOutage }.count
        let pct = Double(up) / Double(app.recentMetrics.count) * 100
        return String(format: "%.1f%%", pct)
    }
}

private struct RecentLatencyChart: View {
    let metrics: [NetworkMetric]
    let tint: Color

    var body: some View {
        Chart {
            ForEach(metrics) { m in
                LineMark(
                    x: .value("Time", m.timestamp),
                    y: .value("ms", displayValue(m))
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(tint)
                .lineStyle(StrokeStyle(lineWidth: 2))

                AreaMark(
                    x: .value("Time", m.timestamp),
                    y: .value("ms", displayValue(m))
                )
                .interpolationMethod(.monotone)
                .foregroundStyle(
                    LinearGradient(
                        colors: [tint.opacity(0.35), tint.opacity(0.02)],
                        startPoint: .top, endPoint: .bottom
                    )
                )
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
            AxisMarks(values: .automatic(desiredCount: 5)) { _ in
                AxisGridLine().foregroundStyle(.quaternary.opacity(0.4))
                AxisValueLabel(format: .dateTime.hour().minute())
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func displayValue(_ m: NetworkMetric) -> Double {
        m.pingPacketLoss >= 100 ? 0 : m.pingAvg
    }
}

private struct PlaceholderDetail: View {
    let title: String
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.largeTitle.bold())
            Text(note).foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(24)
    }
}
