import Foundation

/// Packet-loss / latency thresholds shared across the tracker, health
/// scorer, charts, and outage classification.
enum NetworkThresholds {
    /// Loss at or above this counts as an outage condition.
    static let outagePacketLoss: Double = 50
    /// Loss at or above this is "degraded" but not an outage.
    static let degradedPacketLoss: Double = 5
    /// Latency at or above this (ms) is "degraded".
    static let degradedLatency: Double = 100
}

extension TimeInterval {
    /// Human-readable duration: "3.5s", "38s", "2m 14s", "1.3h".
    var humanDuration: String {
        if self < 10 { return String(format: "%.1fs", self) }
        if self < 60 { return String(format: "%.0fs", self) }
        if self < 3600 {
            return String(format: "%dm %ds", Int(self / 60), Int(self.truncatingRemainder(dividingBy: 60)))
        }
        return String(format: "%.1fh", self / 3600)
    }
}
