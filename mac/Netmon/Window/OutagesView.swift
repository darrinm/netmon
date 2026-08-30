import SwiftUI

struct OutagesView: View {
    @Environment(AppModel.self) private var app
    @State private var outages: [OutageEvent] = []
    @State private var selection: OutageEvent.ID?

    /// Outages bucketed into calendar days, newest day first. `outages` is
    /// already newest-first, so rows within a day keep that order too.
    private var days: [OutageDay] {
        let calendar = Calendar.current
        var order: [Date] = []
        var buckets: [Date: [OutageEvent]] = [:]
        for outage in outages {
            let day = calendar.startOfDay(for: outage.startTime)
            if buckets[day] == nil { order.append(day) }
            buckets[day, default: []].append(outage)
        }
        return order.map { OutageDay(date: $0, outages: buckets[$0] ?? []) }
    }

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
        // Outages change only when one starts or ends — refresh on that,
        // not on every sample tick.
        .onChange(of: app.currentOutage) { _, _ in
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
                List(selection: $selection) {
                    ForEach(days) { day in
                        SwiftUI.Section {
                            ForEach(day.outages) { o in
                                OutageRow(outage: o).tag(o.id)
                            }
                        } header: {
                            OutageDayHeader(day: day)
                        }
                    }
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

/// One calendar day's worth of outages, for a list section.
private struct OutageDay: Identifiable {
    let date: Date
    let outages: [OutageEvent]

    var id: Date { date }

    /// "Today" / "Yesterday" for the two most recent days, otherwise a
    /// weekday-and-date label like "Sat, Aug 29, 2026".
    var title: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
    }

    /// "3 outages · 15s down" — how bad the day was, at a glance.
    var summary: String {
        let count = outages.count
        let total = outages.reduce(0) { $0 + $1.effectiveDuration }
        return "\(count) outage\(count == 1 ? "" : "s") · \(total.humanDuration) down"
    }
}

private struct OutageDayHeader: View {
    let day: OutageDay

    var body: some View {
        HStack {
            Text(day.title).font(.subheadline.bold())
            Spacer()
            Text(day.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
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
                // Date lives in the section header, so the row shows time only.
                Text(outage.startTime.formatted(date: .omitted, time: .shortened))
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

    private var durationText: String { outage.effectiveDuration.humanDuration }
}

private struct OutageDetail: View {
    let outage: OutageEvent
    @Environment(AppModel.self) private var app
    @State private var postMortem: OutagePostMortem?
    @State private var loadingPostMortem = true
    @State private var scope: OutageScope = .unknown

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

                scopeBanner

                postMortemSection
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .task(id: outage.id) {
            loadingPostMortem = true
            postMortem = await app.fetchPostMortem(for: outage.id)
            let around = await app.metricsAround(outage.startTime, windowSeconds: 30)
            scope = OutageScope.classify(around)
            loadingPostMortem = false
        }
    }

    @ViewBuilder
    private var scopeBanner: some View {
        if scope != .unknown {
            HStack(spacing: 10) {
                Image(systemName: scope.systemImage)
                    .font(.title2)
                    .foregroundStyle(scope.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text(scope.label).font(.headline)
                    Text(scope.detail)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
            }
            .padding(12)
            .background(scope.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    @ViewBuilder
    private var postMortemSection: some View {
        if let pm = postMortem {
            if let eth = pm.ethernet {
                GroupBox(label: Text("\(eth.displayName) at the moment of failure").font(.headline)) {
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

            if let links = pm.linkDownIntervals, !links.isEmpty {
                GroupBox(label: Text("Ethernet link events").font(.headline)) {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(links) { iv in
                            HStack {
                                Image(systemName: "cable.connector")
                                    .foregroundStyle(.red)
                                    .frame(width: 18)
                                Text(iv.interface)
                                    .monospaced()
                                    .frame(width: 60, alignment: .leading)
                                Text("link down")
                                    .foregroundStyle(.secondary)
                                if let ms = iv.durationMs {
                                    Text(String(format: "%.2f s", ms / 1000))
                                        .monospacedDigit()
                                        .bold()
                                }
                                Spacer()
                                Text(iv.start.formatted(date: .omitted, time: .standard))
                                    .foregroundStyle(.secondary)
                            }
                            .font(.callout)
                        }
                        Text("Captured live from the kernel log — a real physical link drop, not a measurement artifact.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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

    private var durationText: String { outage.effectiveDuration.humanDuration }
}

/// Whether an outage was local (Mac↔router link) or upstream (past the
/// router), inferred by comparing internet-target loss against the
/// concurrent gateway ping during the outage window.
enum OutageScope: Equatable {
    case local
    case upstream
    case unknown

    /// Internet loss is high. If the gateway was also unreachable → local;
    /// if the gateway stayed reachable → upstream. No gateway data → unknown.
    static func classify(_ metrics: [NetworkMetric]) -> OutageScope {
        let outageSamples = metrics.filter { $0.pingPacketLoss >= NetworkThresholds.outagePacketLoss }
        guard !outageSamples.isEmpty else { return .unknown }
        let gwLosses = outageSamples.compactMap { $0.gatewayPacketLoss }
        guard !gwLosses.isEmpty else { return .unknown }
        let avgGatewayLoss = gwLosses.reduce(0, +) / Double(gwLosses.count)
        return avgGatewayLoss >= NetworkThresholds.outagePacketLoss ? .local : .upstream
    }

    var label: String {
        switch self {
        case .local:    return "Local — Mac ↔ router link"
        case .upstream: return "Upstream — past the router"
        case .unknown:  return ""
        }
    }

    var detail: String {
        switch self {
        case .local:
            return "The gateway was unreachable too, so the drop is between this Mac and the router — link, cable, switch, or NIC."
        case .upstream:
            return "The gateway stayed reachable while the internet target did not — the drop is past the router (ISP or beyond)."
        case .unknown:
            return ""
        }
    }

    var systemImage: String {
        switch self {
        case .local:    return "cable.connector"
        case .upstream: return "globe.americas"
        case .unknown:  return "questionmark.circle"
        }
    }

    var tint: Color {
        switch self {
        case .local:    return .orange
        case .upstream: return .blue
        case .unknown:  return .secondary
        }
    }
}
