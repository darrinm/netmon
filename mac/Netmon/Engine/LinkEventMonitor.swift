import Foundation

/// Streams the macOS unified log for Ethernet/Wi-Fi link up/down kernel
/// events and records the *exact* duration each interface's link was down.
///
/// `log show` after-the-fact loses these once the high-volume log store
/// rolls (often within ~24h). Tailing `log stream` live captures them
/// permanently into outage post-mortems. Durations are computed from the
/// log's own timestamps, so they're accurate even if our read of the
/// stream is briefly delayed.
actor LinkEventMonitor {
    static let shared = LinkEventMonitor()

    struct DownInterval: Sendable {
        var interface: String
        var start: Date
        var end: Date?
        var durationMs: Double?
    }

    private(set) var intervals: [DownInterval] = []
    private var pendingDown: [String: Date] = [:]
    private var process: Process?
    private var lineBuffer = Data()
    private let capacity = 300

    func start() {
        guard process == nil else { return }
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        proc.arguments = [
            "stream",
            "--style", "ndjson",
            "--predicate",
            #"eventMessage CONTAINS "event=link_off" OR eventMessage CONTAINS "event=link_on""#,
        ]
        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = Pipe()

        let handle = pipe.fileHandleForReading
        handle.readabilityHandler = { fh in
            let chunk = fh.availableData
            guard !chunk.isEmpty else { return }
            Task { await LinkEventMonitor.shared.feed(chunk) }
        }

        do {
            try proc.run()
            process = proc
        } catch {
            handle.readabilityHandler = nil
        }
    }

    func stop() {
        process?.terminate()
        process = nil
    }

    /// Link-down intervals overlapping ±`tolerance` of `pivot`.
    func recentIntervals(near pivot: Date, tolerance: TimeInterval = 120) -> [DownInterval] {
        let lo = pivot.addingTimeInterval(-tolerance)
        let hi = pivot.addingTimeInterval(tolerance)
        return intervals.filter { iv in
            let end = iv.end ?? Date()
            return iv.start <= hi && end >= lo
        }
    }

    // MARK: - Stream parsing

    private func feed(_ chunk: Data) {
        lineBuffer.append(chunk)
        while let nl = lineBuffer.firstIndex(of: 0x0A) {
            let lineData = lineBuffer[lineBuffer.startIndex..<nl]
            lineBuffer.removeSubrange(lineBuffer.startIndex...nl)
            if let line = String(data: lineData, encoding: .utf8) {
                ingest(line)
            }
        }
        // Guard against unbounded growth if a line never terminates.
        if lineBuffer.count > 1_000_000 { lineBuffer.removeAll(keepingCapacity: false) }
    }

    private static let decoder = JSONDecoder()

    private func ingest(_ line: String) {
        guard let data = line.data(using: .utf8),
              let entry = try? Self.decoder.decode(LogEntry.self, from: data) else { return }
        let msg = entry.eventMessage
        guard let iface = Self.extract(msg, after: "intf=") else { return }
        let ts = Self.parseTimestamp(entry.timestamp) ?? Date()

        if msg.contains("event=link_off") {
            pendingDown[iface] = ts
        } else if msg.contains("event=link_on") {
            if let downAt = pendingDown.removeValue(forKey: iface) {
                let durationMs = ts.timeIntervalSince(downAt) * 1000
                append(DownInterval(interface: iface, start: downAt, end: ts, durationMs: durationMs))
            }
        }
    }

    private func append(_ interval: DownInterval) {
        intervals.append(interval)
        if intervals.count > capacity {
            intervals.removeFirst(intervals.count - capacity)
        }
    }

    private struct LogEntry: Decodable {
        var timestamp: String
        var eventMessage: String
    }

    /// Reads the whitespace-delimited token following `key` (e.g. "intf=").
    private static func extract(_ s: String, after key: String) -> String? {
        guard let range = s.range(of: key) else { return nil }
        let token = s[range.upperBound...].prefix { !$0.isWhitespace }
        return token.isEmpty ? nil : String(token)
    }

    /// Parses `log stream`'s timestamp, e.g. "2026-05-20 07:55:31.995481-0700".
    /// Fractional seconds are truncated to millisecond precision; absolute
    /// accuracy isn't needed, only consistent differences.
    private static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSSZ"
        return f
    }()

    private static func parseTimestamp(_ raw: String) -> Date? {
        var s = raw
        if let dot = s.firstIndex(of: "."),
           let sign = s[s.index(after: dot)...].firstIndex(where: { $0 == "-" || $0 == "+" }) {
            let frac = s[s.index(after: dot)..<sign]
            if frac.count > 3 {
                s = String(s[..<s.index(after: dot)]) + frac.prefix(3) + String(s[sign...])
            }
        }
        return formatter.date(from: s)
    }
}
