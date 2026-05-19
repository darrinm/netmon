import Foundation
import GRDB

enum OutageType: String, Codable, Sendable {
    case connectivity
    case partial
}

struct OutageEvent: Codable, Hashable, Identifiable, Sendable {
    var id: String
    var startTime: Date
    var endTime: Date?
    var durationMs: Double?
    var lastUpdateTime: Date?
    var type: OutageType
    var startPacketLoss: Double
    var startDNSFailure: Bool
}

extension OutageEvent: FetchableRecord, PersistableRecord {
    static let databaseTableName = "outages"

    enum Columns {
        static let id = Column("id")
        static let startTime = Column("start_time")
        static let endTime = Column("end_time")
        static let durationMs = Column("duration_ms")
        static let lastUpdateTime = Column("last_update_time")
        static let type = Column("type")
        static let startPacketLoss = Column("start_packet_loss")
        static let startDNSFailure = Column("start_dns_failure")
    }

    init(row: Row) throws {
        id = row[Columns.id]
        startTime = row[Columns.startTime]
        endTime = row[Columns.endTime]
        durationMs = row[Columns.durationMs]
        lastUpdateTime = row[Columns.lastUpdateTime]
        let typeString: String = row[Columns.type]
        type = OutageType(rawValue: typeString) ?? .partial
        startPacketLoss = row[Columns.startPacketLoss]
        startDNSFailure = row[Columns.startDNSFailure]
    }

    func encode(to container: inout PersistenceContainer) throws {
        container[Columns.id] = id
        container[Columns.startTime] = startTime
        container[Columns.endTime] = endTime
        container[Columns.durationMs] = durationMs
        container[Columns.lastUpdateTime] = lastUpdateTime
        container[Columns.type] = type.rawValue
        container[Columns.startPacketLoss] = startPacketLoss
        container[Columns.startDNSFailure] = startDNSFailure
    }
}
