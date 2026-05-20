import Foundation
import Darwin

/// Periodically measures ping latency + DNS resolution and emits NetworkMetric
/// samples to an async stream. Uses /sbin/ping (shell-out) for now; a native
/// ICMP implementation lives in the Phase 5 roadmap.
actor MonitorEngine {
    struct Config: Sendable {
        // Cloudflare's resolver is far more permissive about ICMP than 8.8.8.8,
        // which Google rate-limits. See research: pinging 8.8.8.8 will report
        // "dropped packets" even when the network is fine because Google
        // chooses not to reply to every echo request.
        var pingHost: String = "1.1.1.1"
        var dnsHost: String = "google.com"
        // Always send multiple probes per sample so a single dropped echo
        // doesn't read as 100% loss for the tick. macOS ping allows non-root
        // -i down to ~0.2s, giving us 3 pings in ~0.4s wall time.
        var pingCount: Int = 3
        var pingInterval: Double = 0.2
        var pingDeadline: Int = 5    // total deadline seconds for the ping run
        var interval: Duration = .seconds(30)
        /// SOCK_DGRAM ICMP via `NativePing` is experimental on macOS; off by default.
        var useNativeICMP: Bool = false
    }

    nonisolated let stream: AsyncStream<NetworkMetric>
    private let continuation: AsyncStream<NetworkMetric>.Continuation
    private var task: Task<Void, Never>?
    private(set) var config: Config
    private var cachedGateway: String?
    private var tickCount = 0

    init(config: Config = Config()) {
        self.config = config
        var c: AsyncStream<NetworkMetric>.Continuation!
        self.stream = AsyncStream { c = $0 }
        self.continuation = c
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let metric = await self.collectOnce()
                await self.yield(metric)
                let interval = await self.config.interval
                try? await Task.sleep(for: interval)
            }
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        continuation.finish()
    }

    /// Update the configuration. The new interval / host applies on the next tick.
    func update(config newConfig: Config) {
        self.config = newConfig
    }

    private func yield(_ metric: NetworkMetric) {
        continuation.yield(metric)
    }

    func collectOnce() async -> NetworkMetric {
        // Refresh the gateway IP on the first tick and roughly once a minute
        // after — it rarely changes, no need to shell out every second.
        tickCount += 1
        if cachedGateway == nil || tickCount % 60 == 0 {
            cachedGateway = await Task.detached { DefaultRoute.current().gatewayIP }.value
        }
        let gateway = cachedGateway

        async let ping = measurePing()
        async let dns = measureDNS()
        async let gw = measureGatewayPing(gateway)
        let (p, d, g) = await (ping, dns, gw)

        return NetworkMetric(
            timestamp: Date(),
            pingHost: config.pingHost,
            pingMin: p.min,
            pingAvg: p.avg,
            pingMax: p.max,
            pingPacketLoss: p.packetLoss,
            dnsResponseTime: d.responseTime,
            dnsSuccess: d.success,
            gatewayIP: gateway,
            gatewayPingAvg: g?.avg,
            gatewayPacketLoss: g?.loss
        )
    }

    /// Pings the LAN gateway concurrently with the internet target. Two quick
    /// pings — the gateway is local, so this stays well under one tick.
    private func measureGatewayPing(_ gateway: String?) async -> (avg: Double, loss: Double)? {
        guard let gateway else { return nil }
        return await Task.detached {
            let r = Self.shellPing(host: gateway, count: 2, deadline: 1, perPingInterval: 0.2)
            return (avg: r.avg, loss: r.packetLoss)
        }.value
    }

    // MARK: - Ping

    private func measurePing() async -> NativePing.Result {
        let host = config.pingHost
        // Always send `pingCount` probes per sample (default 3) regardless of
        // interval. Single-ping samples are too noisy to distinguish a real
        // outage from a deprioritized ICMP echo — see Smokeping/PingPlotter
        // research notes.
        let intervalSec = max(1, Int(config.interval.components.seconds))
        let count = config.pingCount
        let perPingInterval = config.pingInterval
        let deadline = max(1, min(config.pingDeadline, intervalSec - 1))
        let useNative = config.useNativeICMP
        return await Task.detached { () -> NativePing.Result in
            if useNative {
                let native = NativePing.ping(host: host, count: count, timeout: 2)
                if native.packetLoss < 100 { return native }
            }
            return Self.shellPing(host: host, count: count, deadline: deadline, perPingInterval: perPingInterval)
        }.value
    }

    /// Primary ping implementation: shells out to /sbin/ping with a sub-second
    /// inter-packet interval so we can fit multiple probes inside a 1s tick.
    private static func shellPing(host: String, count: Int, deadline: Int, perPingInterval: Double) -> NativePing.Result {
        let output = Subprocess.capture("/sbin/ping", [
            "-c", "\(count)",
            "-i", String(format: "%.2f", perPingInterval),
            "-t", "\(deadline)",
            host,
        ])
        return Self.parsePingOutput(output)
    }

    /// Parses macOS `ping` output. Looks for `X.X% packet loss` and
    /// `round-trip min/avg/max/stddev = a/b/c/d ms`.
    private static func parsePingOutput(_ output: String) -> NativePing.Result {
        var packetLoss = 100.0
        var minMs = 0.0, avgMs = 0.0, maxMs = 0.0

        for line in output.split(separator: "\n") {
            let s = String(line)
            if let lossRange = s.range(of: #"([0-9.]+)% packet loss"#, options: .regularExpression) {
                let part = s[lossRange]
                let numStr = part.split(separator: "%").first ?? ""
                if let value = Double(numStr) { packetLoss = value }
            }
            if s.contains("min/avg/max") {
                // round-trip min/avg/max/stddev = 14.123/15.456/16.789/0.123 ms
                if let eq = s.range(of: "=") {
                    let tail = s[eq.upperBound...].trimmingCharacters(in: .whitespaces)
                    let numberPart = tail.split(separator: " ").first ?? Substring()
                    let parts = numberPart.split(separator: "/").compactMap { Double($0) }
                    if parts.count >= 3 {
                        minMs = parts[0]
                        avgMs = parts[1]
                        maxMs = parts[2]
                    }
                }
            }
        }

        return NativePing.Result(min: minMs, avg: avgMs, max: maxMs, packetLoss: packetLoss)
    }

    // MARK: - DNS

    private struct DNSResult: Sendable {
        var responseTime: Double // ms
        var success: Bool
    }

    private func measureDNS() async -> DNSResult {
        await Task.detached { [host = config.dnsHost] in
            // Issue a fresh DNS A-record query directly to 1.1.1.1:53 via UDP
            // so we measure real wire round-trip, not a cached getaddrinfo.
            let r = DirectDNS.query(name: host, server: "1.1.1.1", timeout: 2)
            return DNSResult(responseTime: r.responseTime, success: r.success)
        }.value
    }
}
