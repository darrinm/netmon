import SwiftUI

struct OutagesView: View {
    @Environment(AppModel.self) private var app
    @State private var outages: [OutageEvent] = []
    @State private var selection: OutageEvent.ID?

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 280, idealWidth: 320)

            if let event = selectedOutage {
                OutageDetail(outage: event)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select an outage to see details.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { await load() }
        .onChange(of: app.sessionSamples) { _, _ in
            Task { await load() }
        }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Outages").font(.largeTitle.bold()).padding(.horizontal, 20).padding(.top, 20)

            if outages.isEmpty {
                Text("No outages recorded. 🎉")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(outages, selection: $selection) { o in
                    OutageRow(outage: o).tag(o.id)
                }
                .listStyle(.inset)
            }
        }
    }

    private var selectedOutage: OutageEvent? {
        outages.first { $0.id == selection }
    }

    private func load() async {
        let fetched = await app.fetchOutages()
        outages = fetched.reversed() // most recent first
        if selection == nil { selection = outages.first?.id }
    }
}

private struct OutageRow: View {
    let outage: OutageEvent

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(outage.type == .connectivity ? Color.red : Color.orange)
                .frame(width: 10, height: 10)
            VStack(alignment: .leading, spacing: 2) {
                Text(outage.startTime.formatted(date: .abbreviated, time: .shortened))
                    .font(.callout)
                Text(durationText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if outage.endTime == nil {
                Text("Ongoing")
                    .font(.caption2.bold())
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(.red.opacity(0.15), in: Capsule())
                    .foregroundStyle(.red)
            }
        }
        .padding(.vertical, 4)
    }

    private var durationText: String {
        let ms = outage.durationMs ?? (outage.endTime ?? Date()).timeIntervalSince(outage.startTime) * 1000
        let s = ms / 1000
        if s < 60 { return String(format: "%.0fs", s) }
        if s < 3600 { return String(format: "%.0fm %.0fs", floor(s/60), s.truncatingRemainder(dividingBy: 60)) }
        return String(format: "%.1fh", s/3600)
    }
}

private struct OutageDetail: View {
    let outage: OutageEvent

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text(outage.type == .connectivity ? "Connectivity Outage" : "Partial Outage")
                        .font(.title2.bold())
                    Spacer()
                    if outage.endTime == nil {
                        Text("Ongoing")
                            .font(.callout.bold())
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(.red.opacity(0.15), in: Capsule())
                            .foregroundStyle(.red)
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 8) {
                        kv("Started", outage.startTime.formatted(date: .long, time: .standard))
                        if let endTime = outage.endTime {
                            kv("Ended", endTime.formatted(date: .long, time: .standard))
                        }
                        kv("Duration", durationText)
                        if let updated = outage.lastUpdateTime {
                            kv("Last activity", updated.formatted(date: .abbreviated, time: .standard))
                        }
                        kv("Packet loss at start", String(format: "%.1f%%", outage.startPacketLoss))
                        kv("DNS at start", outage.startDNSFailure ? "Failure" : "OK")
                        kv("Outage id", outage.id)
                            .textSelection(.enabled)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(24)
        }
    }

    private func kv(_ key: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(key).foregroundStyle(.secondary).frame(width: 160, alignment: .leading)
            Text(value).monospacedDigit()
            Spacer()
        }
    }

    private var durationText: String {
        if let ms = outage.durationMs {
            return format(ms: ms)
        }
        let ms = (outage.endTime ?? Date()).timeIntervalSince(outage.startTime) * 1000
        return format(ms: ms)
    }

    private func format(ms: Double) -> String {
        let s = ms / 1000
        if s < 60 { return String(format: "%.1fs", s) }
        if s < 3600 { return String(format: "%dm %ds", Int(s/60), Int(s.truncatingRemainder(dividingBy: 60))) }
        return String(format: "%.2fh", s/3600)
    }
}
