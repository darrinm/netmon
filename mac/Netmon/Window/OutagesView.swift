import SwiftUI

struct OutagesView: View {
    @Environment(AppModel.self) private var app
    @State private var outages: [OutageEvent] = []
    @State private var selection: OutageEvent.ID?

    var body: some View {
        HSplitView {
            list
                .frame(minWidth: 240, idealWidth: 300, maxWidth: 380)

            if let event = selectedOutage {
                OutageDetail(outage: event)
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Text("Select an outage to see details.")
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 380, maxWidth: .infinity, maxHeight: .infinity)
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
    @Environment(AppModel.self) private var app
    @State private var postMortem: OutagePostMortem?
    @State private var loadingPostMortem = true

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
                    Button {
                        copyAsMarkdown()
                    } label: {
                        Label("Copy", systemImage: "doc.on.clipboard")
                    }
                    .help("Copy outage report as Markdown")
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        row("Started", outage.startTime.formatted(date: .abbreviated, time: .standard))
                        if let endTime = outage.endTime {
                            row("Ended", endTime.formatted(date: .abbreviated, time: .standard))
                        }
                        row("Duration", durationText)
                        if let updated = outage.lastUpdateTime {
                            row("Last activity", updated.formatted(date: .abbreviated, time: .standard))
                        }
                        row("Packet loss at start", String(format: "%.1f%%", outage.startPacketLoss))
                        row("DNS at start", outage.startDNSFailure ? "Failure" : "OK")
                        row("Outage id", outage.id, selectable: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }

                postMortemSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: outage.id) {
            loadingPostMortem = true
            postMortem = await app.fetchPostMortem(for: outage.id)
            loadingPostMortem = false
        }
    }

    @ViewBuilder
    private var postMortemSection: some View {
        if let pm = postMortem {
            if let eth = pm.ethernet {
                GroupBox(label: Text(ethernetSectionTitle(eth)).font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        row("Interface", eth.interface)
                        if let port = eth.hardwarePort { row("Hardware port", port) }
                        row("Link", eth.linkActive ? "Active" : "Down")
                        if let media = eth.media { row("Media", media) }
                        if let mac = eth.macAddress { row("MAC", mac, selectable: true) }
                        if let ip = eth.ipAddress { row("IP", ip, selectable: true) }
                        if let mtu = eth.mtu { row("MTU", "\(mtu)") }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let wifi = pm.wifi {
                GroupBox(label: Text("Wi-Fi at the moment of failure").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        row("Interface", wifi.interface)
                        row("Network", wifi.ssid ?? "unknown (grant Location in Settings)")
                        row("BSSID", wifi.bssid ?? "unknown")
                        row("Signal", "\(wifi.rssiDBm) dBm")
                        row("Noise", "\(wifi.noiseDBm) dBm")
                        if let ch = wifi.channel { row("Channel", "\(ch)") }
                        if wifi.transmitRateMbps > 0 {
                            row("TX rate", String(format: "%.0f Mbps", wifi.transmitRateMbps))
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let gw = pm.gatewayIP {
                GroupBox(label: Text("Routing").font(.headline)) {
                    VStack(alignment: .leading, spacing: 10) {
                        row("Default gateway", gw, selectable: true)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if let hops = pm.traceroute, !hops.isEmpty {
                GroupBox(label: Text("Traceroute").font(.headline)) {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(hops) { hop in
                            HStack {
                                Text("\(hop.index)")
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                                    .frame(width: 24, alignment: .trailing)
                                Text(hop.ip ?? "*")
                                    .monospaced()
                                    .frame(width: 140, alignment: .leading)
                                if let rtt = hop.rttMs {
                                    Text(String(format: "%.1f ms", rtt))
                                        .monospacedDigit()
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("timeout")
                                        .foregroundStyle(.red)
                                }
                                Spacer()
                            }
                            .font(.callout)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if !pm.recentSystemEvents.isEmpty {
                GroupBox(label: Text("Nearby system events").font(.headline)) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(pm.recentSystemEvents) { ev in
                            HStack {
                                Image(systemName: ev.kind.systemImage)
                                    .foregroundStyle(ev.kind.tint)
                                    .frame(width: 18)
                                Text(ev.kind.label)
                                    .frame(width: 200, alignment: .leading)
                                Text(ev.timestamp.formatted(date: .omitted, time: .standard))
                                    .foregroundStyle(.secondary)
                                Spacer()
                            }
                            .font(.callout)
                        }
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        } else if loadingPostMortem {
            Text("Capturing post-mortem…")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            Text("No post-mortem available — only outages that occurred while Netmon was running get a snapshot.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func copyAsMarkdown() {
        let md = MarkdownReport.render(outage: outage, postMortem: postMortem)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(md, forType: .string)
    }

    private func ethernetSectionTitle(_ eth: EthernetSnapshot) -> String {
        if let port = eth.hardwarePort { return "\(port) at the moment of failure" }
        return "Ethernet at the moment of failure"
    }

    @ViewBuilder
    private func row(_ key: String, _ value: String, selectable: Bool = false) -> some View {
        LabeledContent {
            if selectable {
                Text(value)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
                    .textSelection(.enabled)
            } else {
                Text(value)
                    .monospacedDigit()
                    .multilineTextAlignment(.trailing)
            }
        } label: {
            Text(key).foregroundStyle(.secondary)
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
