import Foundation
import Darwin

/// Periodically measures ping latency + DNS resolution and emits NetworkMetric
/// samples to an async stream. Uses /sbin/ping (shell-out) for now; a native
/// ICMP implementation lives in the Phase 5 roadmap.
actor MonitorEngine {
    struct Config: Sendable {
        var pingHost: String = "8.8.8.8"
        var dnsHost: String = "google.com"
        var pingCount: Int = 3
        var pingDeadline: Int = 5    // total deadline seconds for the ping run
        var interval: Duration = .seconds(30)
        /// SOCK_DGRAM ICMP via `NativePing` is experimental on macOS; off by default.
        var useNativeICMP: Bool = false
    }

    nonisolated let stream: AsyncStream<NetworkMetric>
    private let continuation: AsyncStream<NetworkMetric>.Continuation
    private var task: Task<Void, Never>?
    private(set) var config: Config

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
        async let ping = measurePing()
        async let dns = measureDNS()
        let (p, d) = await (ping, dns)
        return NetworkMetric(
            timestamp: Date(),
            pingHost: config.pingHost,
            pingMin: p.min,
            pingAvg: p.avg,
            pingMax: p.max,
            pingPacketLoss: p.packetLoss,
            dnsResponseTime: d.responseTime,
            dnsSuccess: d.success
        )
    }

    // MARK: - Ping

    private struct PingResult: Sendable {
        var min: Double
        var avg: Double
        var max: Double
        var packetLoss: Double // 0..100
    }

    private func measurePing() async -> PingResult {
        let host = config.pingHost
        // Scale the ping cycle to the sampling interval so we always finish
        // inside one tick. At 1–2s intervals we send a single ping; at 5s+
        // we send the configured pingCount.
        let intervalSec = max(1, Int(config.interval.components.seconds))
        let count: Int
        if intervalSec <= 2 {
            count = 1
        } else if intervalSec <= 4 {
            count = min(config.pingCount, 2)
        } else {
            count = config.pingCount
        }
        let deadline = max(1, min(config.pingDeadline, intervalSec - 1))
        let useNative = config.useNativeICMP
        return await Task.detached { () -> PingResult in
            if useNative {
                let native = NativePing.ping(host: host, count: count, timeout: 2)
                if native.packetLoss < 100 {
                    return PingResult(
                        min: native.min, avg: native.avg, max: native.max,
                        packetLoss: native.packetLoss
                    )
                }
            }
            return Self.shellPing(host: host, count: count, deadline: deadline)
        }.value
    }

    /// Last-resort shell-out fallback. Same parser as the original
    /// implementation; only used if NativePing returns 100% loss.
    private static func shellPing(host: String, count: Int, deadline: Int) -> PingResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/sbin/ping")
        process.arguments = ["-c", "\(count)", "-t", "\(deadline)", host]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return PingResult(min: 0, avg: 0, max: 0, packetLoss: 100)
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        return Self.parsePingOutput(output)
    }

    /// Parses macOS `ping` output. Looks for `X.X% packet loss` and
    /// `round-trip min/avg/max/stddev = a/b/c/d ms`.
    private static func parsePingOutput(_ output: String) -> PingResult {
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

        return PingResult(min: minMs, avg: avgMs, max: maxMs, packetLoss: packetLoss)
    }

    // MARK: - DNS

    private struct DNSResult: Sendable {
        var responseTime: Double // ms
        var success: Bool
    }

    private func measureDNS() async -> DNSResult {
        await Task.detached { [host = config.dnsHost] in
            let start = Date()
            var hints = addrinfo(
                ai_flags: 0,
                ai_family: AF_UNSPEC,
                ai_socktype: SOCK_STREAM,
                ai_protocol: 0,
                ai_addrlen: 0,
                ai_canonname: nil,
                ai_addr: nil,
                ai_next: nil
            )
            var info: UnsafeMutablePointer<addrinfo>?
            let status = getaddrinfo(host, nil, &hints, &info)
            let elapsedMs = Date().timeIntervalSince(start) * 1000
            if info != nil { freeaddrinfo(info) }
            return DNSResult(responseTime: elapsedMs, success: status == 0)
        }.value
    }
}
