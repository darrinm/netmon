import SwiftUI

struct PopoverView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            VStack(alignment: .leading, spacing: 6) {
                statRow(label: "Latency", value: latencyText)
                statRow(label: "Loss",    value: lossText)
                statRow(label: "Uptime",  value: uptimeText)
            }
            .font(.system(.body, design: .rounded))

            // Sparkline
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.4))
                if app.recentMetrics.count >= 2 {
                    Sparkline(metrics: app.recentMetrics, tint: app.health.tint)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 4)
                } else {
                    Text("Collecting samples…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 60)

            Divider()

            HStack {
                Text(app.latestMetric?.pingHost ?? "8.8.8.8")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("30s interval · \(app.sessionSamples) samples")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button("Open Netmon") {
                    openWindow(id: "main")
                    NSApp.activate(ignoringOtherApps: true)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Spacer()

                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(14)
    }

    private var header: some View {
        HStack {
            Text("Network").font(.headline)
            Spacer()
            Image(systemName: app.health.systemImage)
                .foregroundStyle(app.health.tint)
        }
    }

    private var latencyText: String {
        guard let m = app.latestMetric else { return "— ms" }
        if m.pingPacketLoss == 100 { return "no reply" }
        return String(format: "%.0f ms", m.pingAvg)
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

    private func statRow(label: String, value: String) -> some View {
        HStack {
            Text(label).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit()
        }
    }
}
