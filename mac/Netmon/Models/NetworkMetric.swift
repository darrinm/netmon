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
