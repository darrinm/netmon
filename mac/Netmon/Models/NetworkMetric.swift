import Foundation
import GRDB

struct NetworkMetric: Codable, Hashable, Identifiable, Sendable {
    var timestamp: Date
    var pingHost: String
    var pingMin: Double
    var pingAvg: Double
    var pingMax: Double
    var pingPacketLoss: Double // 0..100
    var dnsResponseTime: Double // ms; -1 if failed
    var dnsSuccess: Bool
    var isOutage: Bool = false
    // Concurrent ping of the default gateway. nil when the gateway is
    // unknown or for samples recorded before gateway monitoring existed.
    var gatewayIP: String? = nil
    var gatewayPingAvg: Double? = nil
    var gatewayPacketLoss: Double? = nil

    var id: Date { timestamp }

    /// Latency to plot — a full-loss sample reads as 0 so the line drops
    /// cleanly to the floor instead of leaving a gap.
    var displayLatency: Double {
        pingPacketLoss >= 100 ? 0 : pingAvg
    }
}

extension Array where Element == NetworkMetric {
    /// Contiguous runs of samples whose packet loss meets the outage threshold.
    /// Only runs of `minSamples` or more bad samples count — single-sample
    /// blips show up in the distribution band, not as a red outage rectangle.
    /// Each span's end is the next non-outage sample's timestamp (or, for an
    /// ongoing run, the last outage sample's timestamp plus `minOpenWidth`).
    func outageSpans(
        threshold: Double = NetworkThresholds.outagePacketLoss,
        minSamples: Int = 2,
        minOpenWidth: TimeInterval = 1
    ) -> [(start: Date, end: Date)] {
        var spans: [(start: Date, end: Date)] = []
        var runStart: Date?
        var runCount: Int = 0
        var lastBad: Date?

        for m in self {
            if m.pingPacketLoss >= threshold {
                if runStart == nil { runStart = m.timestamp }
                runCount += 1
                lastBad = m.timestamp
            } else if let start = runStart {
                // A good sample closes the run; end the band at it so even a
                // minimal run is one sampling interval wide.
                if runCount >= minSamples {
                    spans.append((start, m.timestamp))
                }
                runStart = nil
                runCount = 0
                lastBad = nil
            }
        }
        if let start = runStart, let last = lastBad, runCount >= minSamples {
            let end = Swift.max(last, start.addingTimeInterval(minOpenWidth))
            spans.append((start, end))
        }
        return spans
    }
}

extension NetworkMetric: FetchableRecord, PersistableRecord {
    static let databaseTableName = "metrics"

    enum Columns {
        static let timestamp = Column("timestamp")
        static let pingHost = Column("ping_host")
        static let pingMin = Column("ping_min")
        static let pingAvg = Column("ping_avg")
        static let pingMax = Column("ping_max")
        static let pingPacketLoss = Column("ping_packet_loss")
        static let dnsResponseTime = Column("dns_response_time")
        static let dnsSuccess = Column("dns_success")
        static let isOutage = Column("is_outage")
        static let gatewayIP = Column("gateway_ip")
        static let gatewayPingAvg = Column("gateway_ping_avg")
        static let gatewayPacketLoss = Column("gateway_packet_loss")
    }

    init(row: Row) throws {
        timestamp = row[Columns.timestamp]
        pingHost = row[Columns.pingHost]
        pingMin = row[Columns.pingMin]
        pingAvg = row[Columns.pingAvg]
        pingMax = row[Columns.pingMax]
        pingPacketLoss = row[Columns.pingPacketLoss]
        dnsResponseTime = row[Columns.dnsResponseTime]
        dnsSuccess = row[Columns.dnsSuccess]
        isOutage = row[Columns.isOutage]
        gatewayIP = row[Columns.gatewayIP]
        gatewayPingAvg = row[Columns.gatewayPingAvg]
        gatewayPacketLoss = row[Columns.gatewayPacketLoss]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.timestamp] = timestamp
        container[Columns.pingHost] = pingHost
        container[Columns.pingMin] = pingMin
        container[Columns.pingAvg] = pingAvg
        container[Columns.pingMax] = pingMax
        container[Columns.pingPacketLoss] = pingPacketLoss
        container[Columns.dnsResponseTime] = dnsResponseTime
        container[Columns.dnsSuccess] = dnsSuccess
        container[Columns.isOutage] = isOutage
        container[Columns.gatewayIP] = gatewayIP
        container[Columns.gatewayPingAvg] = gatewayPingAvg
        container[Columns.gatewayPacketLoss] = gatewayPacketLoss
    }
}
