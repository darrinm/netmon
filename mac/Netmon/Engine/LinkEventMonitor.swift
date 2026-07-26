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

    /// `eventMessage CONTAINS` is an *unindexed* filter: the log system has to
    /// render every message system-wide before it can substring-match, which
    /// measured ~11% of a core continuously. Gating on `process` first is
    /// indexed and cuts that to ~0.3% — a ~35x saving for the same events.
    ///
    /// The process list is a deliberate hedge. These events are emitted by the
    /// kernel (see OUTAGE-ANALYSIS.md), but that was observed during the 2026-05
    /// link flapping and no such event exists in the log store any more, so it
    /// couldn't be re-confirmed directly. Widening from `kernel` alone to this
    /// union costs nothing measurable and removes the risk of silently
    /// capturing nothing if the emitter differs. Re-verify when a real
    /// link event next occurs — see tasks/todo.md.
    private static let predicate = """
        (process == "kernel" OR process == "configd" \
        OR process == "airportd" OR process == "networkd") \
        AND (eventMessage CONTAINS "event=link_off" \
        OR eventMessage CONTAINS "event=link_on")
        """

    func start() {
        guard process == nil else { return }
        Self.reapOrphans()
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        proc.arguments = [
            "stream",
            "--style", "ndjson",
            "--predicate", Self.predicate,
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

    /// Kills `log stream` children left behind by a previous Netmon that exited
    /// without running `stop()` — a crash, or a SIGKILL, which no handler can
    /// intercept.
    ///
    /// They don't die on their own: `log stream` only discovers its parent is
    /// gone when a write to the closed pipe fails, and this predicate matches
    /// so rarely that it may never write at all. One was found still streaming
    /// 18 days after its parent died, burning ~5% of a core the whole time, and
    /// they accumulate one per abnormal exit.
    ///
    /// Reparenting to launchd (ppid 1) is what makes an orphan identifiable —
    /// a concurrently running instance's child still has that instance as its
    /// parent, so it's never a candidate here.
    private static func reapOrphans() {
        let listing = Subprocess.capture("/bin/ps", ["-Ao", "pid=,ppid=,args="])
        for line in listing.split(separator: "\n") {
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3,
                  let pid = pid_t(fields[0]),
                  let ppid = pid_t(fields[1]),
                  ppid == 1,
                  fields[2].hasPrefix("/usr/bin/log"),
                  fields[2].contains(orphanMarker)
            else { continue }
            kill(pid, SIGTERM)
        }
    }

    /// A fragment of our own predicate, distinctive enough to identify a stream
    /// we started without matching unrelated `log` invocations.
    private static let orphanMarker = #"eventMessage CONTAINS "event=link_off""#

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
