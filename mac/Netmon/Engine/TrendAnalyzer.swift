import Foundation

/// Compares network behaviour in a recent window against the prior window of
/// the same length, so users can spot slow degradation before it becomes a
/// full outage.
enum TrendAnalyzer {
    struct WindowStats: Sendable {
        var samples: Int
        var medianLatencyMs: Double
        var p95LatencyMs: Double
        var meanPacketLoss: Double
        var outageSeconds: Double
    }

    struct Comparison: Sendable {
        var recent: WindowStats
        var prior: WindowStats
        var windowDays: Int

        /// Recent stats relative to prior. Positive = worse for latency/loss/outage,
        /// negative = better. nil when prior is zero (avoids div-by-zero noise).
        var medianLatencyDeltaPct: Double? { delta(recent.medianLatencyMs, prior.medianLatencyMs) }
        var p95LatencyDeltaPct: Double?    { delta(recent.p95LatencyMs,    prior.p95LatencyMs) }
        var packetLossDeltaPct: Double?    { delta(recent.meanPacketLoss,  prior.meanPacketLoss) }
        var outageSecondsDeltaPct: Double? { delta(recent.outageSeconds,   prior.outageSeconds) }

        private func delta(_ recent: Double, _ prior: Double) -> Double? {
            guard prior > 0 else { return nil }
            return (recent - prior) / prior * 100
        }
    }

    static func compare(
        metrics: [NetworkMetric],
        outages: [OutageEvent],
        windowDays: Int = 7,
        now: Date = .now
    ) -> Comparison {
        let recentStart = now.addingTimeInterval(-Double(windowDays) * 86400)
        let priorStart  = now.addingTimeInterval(-2 * Double(windowDays) * 86400)

        let recentMetrics = metrics.filter { $0.timestamp >= recentStart && $0.timestamp <  now }
        let priorMetrics  = metrics.filter { $0.timestamp >= priorStart  && $0.timestamp <  recentStart }

        return Comparison(
            recent: stats(metrics: recentMetrics, outages: outages, from: recentStart, to: now),
            prior:  stats(metrics: priorMetrics,  outages: outages, from: priorStart,  to: recentStart),
            windowDays: windowDays
        )
    }

    private static func stats(
        metrics: [NetworkMetric],
        outages: [OutageEvent],
        from: Date,
        to: Date
    ) -> WindowStats {
        let latencies = metrics
            .filter { $0.pingPacketLoss < 100 }
            .map(\.pingAvg)
            .sorted()
        let losses = metrics.map(\.pingPacketLoss)

        let outageMs = outages.reduce(0.0) { acc, o in
            // Intersect outage interval with window.
            let oStart = o.startTime
            let oEnd = o.endTime ?? Date()
            let s = Swift.max(oStart, from)
            let e = Swift.min(oEnd, to)
            return acc + Swift.max(0, e.timeIntervalSince(s)) * 1000
        }

        return WindowStats(
            samples: metrics.count,
            medianLatencyMs: percentile(latencies, 0.50) ?? 0,
            p95LatencyMs:    percentile(latencies, 0.95) ?? 0,
            meanPacketLoss:  losses.isEmpty ? 0 : losses.reduce(0, +) / Double(losses.count),
            outageSeconds: outageMs / 1000
        )
    }

    private static func percentile(_ sorted: [Double], _ p: Double) -> Double? {
        guard !sorted.isEmpty else { return nil }
        let idx = Int((Double(sorted.count - 1) * p).rounded())
        return sorted[idx]
    }
}
