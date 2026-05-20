import Foundation
import GRDB

/// SQLite-backed store for metrics and outages. Lives at
/// ~/Library/Application Support/Netmon/store.sqlite.
actor MetricStore {
    private let dbPool: DatabasePool
    private let maxMetrics = 100_000

    init() throws {
        let fm = FileManager.default
        let appSupport = try fm.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = appSupport.appendingPathComponent("Netmon", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let dbURL = dir.appendingPathComponent("store.sqlite")

        var config = Configuration()
        config.label = "netmon.store"
        dbPool = try DatabasePool(path: dbURL.path, configuration: config)

        try Self.migrator.migrate(dbPool)
    }

    private static var migrator: DatabaseMigrator {
        var m = DatabaseMigrator()
        m.registerMigration("v1") { db in
            try db.create(table: "metrics") { t in
                t.column("timestamp", .datetime).primaryKey()
                t.column("ping_host", .text).notNull()
                t.column("ping_min", .double).notNull()
                t.column("ping_avg", .double).notNull()
                t.column("ping_max", .double).notNull()
                t.column("ping_packet_loss", .double).notNull()
                t.column("dns_response_time", .double).notNull()
                t.column("dns_success", .boolean).notNull()
                t.column("is_outage", .boolean).notNull().defaults(to: false)
            }
            try db.create(index: "metrics_timestamp_desc", on: "metrics", columns: ["timestamp"])

            try db.create(table: "outages") { t in
                t.column("id", .text).primaryKey()
                t.column("start_time", .datetime).notNull()
                t.column("end_time", .datetime)
                t.column("duration_ms", .double)
                t.column("last_update_time", .datetime)
                t.column("type", .text).notNull()
                t.column("start_packet_loss", .double).notNull()
                t.column("start_dns_failure", .boolean).notNull()
            }
            try db.create(index: "outages_start_time", on: "outages", columns: ["start_time"])
        }
        m.registerMigration("v2_post_mortems") { db in
            try db.create(table: "outage_post_mortems") { t in
                t.column("outage_id", .text).primaryKey()
                t.column("json", .text).notNull()
            }
        }
        m.registerMigration("v3_gateway") { db in
            try db.alter(table: "metrics") { t in
                t.add(column: "gateway_ip", .text)
                t.add(column: "gateway_ping_avg", .double)
                t.add(column: "gateway_packet_loss", .double)
            }
        }
        return m
    }

    func insertMetric(_ metric: NetworkMetric) async throws {
        try await dbPool.write { db in
            try metric.insert(db)

            // Retention: keep newest `maxMetrics` rows.
            let count = try Int.fetchOne(db, sql: "SELECT COUNT(*) FROM metrics") ?? 0
            if count > self.maxMetrics {
                let toDelete = count - self.maxMetrics
                try db.execute(sql: """
                    DELETE FROM metrics
                    WHERE timestamp IN (
                      SELECT timestamp FROM metrics ORDER BY timestamp ASC LIMIT ?
                    )
                """, arguments: [toDelete])
            }
        }
    }

    func upsertOutage(_ outage: OutageEvent) async throws {
        try await dbPool.write { db in
            try outage.save(db)
        }
    }

    func loadOutages() async throws -> [OutageEvent] {
        try await dbPool.read { db in
            try OutageEvent.order(OutageEvent.Columns.startTime).fetchAll(db)
        }
    }

    func recentMetrics(since: Date) async throws -> [NetworkMetric] {
        try await dbPool.read { db in
            try NetworkMetric
                .filter(NetworkMetric.Columns.timestamp >= since)
                .order(NetworkMetric.Columns.timestamp)
                .fetchAll(db)
        }
    }

    func allMetrics() async throws -> [NetworkMetric] {
        try await dbPool.read { db in
            try NetworkMetric.order(NetworkMetric.Columns.timestamp).fetchAll(db)
        }
    }

    func metrics(from: Date, to: Date) async throws -> [NetworkMetric] {
        try await dbPool.read { db in
            try NetworkMetric
                .filter(NetworkMetric.Columns.timestamp >= from
                        && NetworkMetric.Columns.timestamp <= to)
                .order(NetworkMetric.Columns.timestamp)
                .fetchAll(db)
        }
    }

    // MARK: - Outage post-mortems

    func savePostMortem(_ pm: OutagePostMortem, for outageID: String) async throws {
        let json = try JSONEncoder.iso8601.encode(pm)
        let jsonString = String(data: json, encoding: .utf8) ?? "{}"
        try await dbPool.write { db in
            try db.execute(sql: """
                INSERT INTO outage_post_mortems (outage_id, json) VALUES (?, ?)
                ON CONFLICT(outage_id) DO UPDATE SET json = excluded.json
            """, arguments: [outageID, jsonString])
        }
    }

    func loadPostMortem(for outageID: String) async throws -> OutagePostMortem? {
        try await dbPool.read { db in
            guard let json = try String.fetchOne(
                db,
                sql: "SELECT json FROM outage_post_mortems WHERE outage_id = ?",
                arguments: [outageID]
            ) else { return nil }
            guard let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder.iso8601.decode(OutagePostMortem.self, from: data)
        }
    }
}

private extension JSONEncoder {
    static let iso8601: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()
}

private extension JSONDecoder {
    static let iso8601: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()
}
