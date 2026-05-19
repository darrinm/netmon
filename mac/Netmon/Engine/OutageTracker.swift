import Foundation

/// Detects connectivity outages from a stream of NetworkMetric samples.
/// Mirrors the TypeScript OutageTracker with the recent fixes:
///   * outage startTime is the *first* failing metric, not the second
///   * lastUpdateTime is tracked while ongoing so a restart can tell how
///     recently we observed activity
///   * stale ongoing outages from a prior session are closed at load time
///     so they don't inflate stats with `Date.now() - startTime`.
struct OutageTracker {
    struct ProcessResult {
        /// State-changing event (open/close). `nil` when nothing transitioned.
        var event: OutageEvent?
        /// The currently-ongoing outage with its updated lastUpdateTime, if any.
        /// Callers should persist this if `event == nil && metric.isOutage`
        /// to keep lastUpdateTime fresh across restarts.
        var ongoing: OutageEvent?
    }

    /// How stale an ongoing outage can be on load before we close it instead
    /// of resuming. We can't claim downtime that occurred while the monitor
    /// wasn't running.
    static let staleOutageInterval: TimeInterval = 5 * 60

    private let packetLossThreshold: Double = 50
    private let consecutiveFailuresThreshold = 2

    private(set) var outages: [OutageEvent] = []
    private(set) var currentOutage: OutageEvent?

    private var consecutiveFailures = 0
    private var firstFailureMetric: NetworkMetric?

    mutating func processMetric(_ metricIn: NetworkMetric) -> ProcessResult {
        var metric = metricIn
        let isOutage = isOutageCondition(metric)
        metric.isOutage = isOutage

        if isOutage {
            consecutiveFailures += 1
            if firstFailureMetric == nil { firstFailureMetric = metric }

            if var current = currentOutage {
                current.lastUpdateTime = metric.timestamp
                currentOutage = current
                replaceInOutages(current)
                return ProcessResult(event: nil, ongoing: current)
            }

            if consecutiveFailures >= consecutiveFailuresThreshold,
               let first = firstFailureMetric {
                let new = startOutage(firstFailure: first, latestFailure: metric)
                currentOutage = new
                outages.append(new)
                return ProcessResult(event: new, ongoing: new)
            }

            return ProcessResult(event: nil, ongoing: nil)
        }

        firstFailureMetric = nil
        if var current = currentOutage {
            current.endTime = metric.timestamp
            current.durationMs = metric.timestamp.timeIntervalSince(current.startTime) * 1000
            current.lastUpdateTime = metric.timestamp
            currentOutage = nil
            consecutiveFailures = 0
            replaceInOutages(current)
            return ProcessResult(event: current, ongoing: nil)
        }
        consecutiveFailures = 0
        return ProcessResult(event: nil, ongoing: nil)
    }

    mutating func loadPersisted(_ persisted: [OutageEvent], now: Date = .now) {
        outages = persisted

        guard let idx = outages.firstIndex(where: { $0.endTime == nil }) else { return }
        var ongoing = outages[idx]
        let lastActivity = ongoing.lastUpdateTime ?? ongoing.startTime
        let staleness = now.timeIntervalSince(lastActivity)

        if staleness > Self.staleOutageInterval {
            ongoing.endTime = lastActivity
            ongoing.durationMs = lastActivity.timeIntervalSince(ongoing.startTime) * 1000
            outages[idx] = ongoing
        } else {
            currentOutage = ongoing
        }
    }

    private func isOutageCondition(_ metric: NetworkMetric) -> Bool {
        let hasHighPacketLoss = metric.pingPacketLoss >= packetLossThreshold
        let hasDNSFailure = !metric.dnsSuccess
        let hasNoConnectivity = metric.pingPacketLoss == 100
        return hasNoConnectivity || (hasHighPacketLoss && hasDNSFailure)
    }

    private func startOutage(firstFailure: NetworkMetric, latestFailure: NetworkMetric) -> OutageEvent {
        OutageEvent(
            id: "outage-\(Int(firstFailure.timestamp.timeIntervalSince1970 * 1000))",
            startTime: firstFailure.timestamp,
            endTime: nil,
            durationMs: nil,
            lastUpdateTime: latestFailure.timestamp,
            type: firstFailure.pingPacketLoss == 100 ? .connectivity : .partial,
            startPacketLoss: firstFailure.pingPacketLoss,
            startDNSFailure: !firstFailure.dnsSuccess
        )
    }

    private mutating func replaceInOutages(_ updated: OutageEvent) {
        if let i = outages.firstIndex(where: { $0.id == updated.id }) {
            outages[i] = updated
        }
    }
}
