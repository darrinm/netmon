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

    var id: Date { timestamp }
}

extension Array where Element == NetworkMetric {
    /// Contiguous runs of samples whose packet loss meets the outage threshold.
    /// Only runs of `minSamples` or more bad samples count — single-sample
    /// blips show up in the distribution band, not as a red outage rectangle.
    /// Each span's end is the next non-outage sample's timestamp (or, for an
    /// ongoing run, the last outage sample's timestamp plus `minOpenWidth`).
    func outageSpans(
        threshold: Double = 50,
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
                if runCount >= minSamples, let last = lastBad {
                    // Close the band at this good sample so it's at least one
                    // sampling interval wide.
                    spans.append((start, m.timestamp))
                    _ = last
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
    }
}
