import Foundation
import SwiftUI
import Observation

@MainActor
@Observable
final class AppModel {
    // Live state
    private(set) var latestMetric: NetworkMetric?
    private(set) var currentOutage: OutageEvent?
    private(set) var recentMetrics: [NetworkMetric] = []
    private(set) var health: HealthState = .unknown
    private(set) var sessionSamples: Int = 0
    private(set) var startupError: String?

    // Pipeline
    private var store: MetricStore?
    private var engine: MonitorEngine?
    private var tracker = OutageTracker()
    private var consumeTask: Task<Void, Never>?

    func start() async {
        do {
            let store = try MetricStore()
            self.store = store

            let persistedOutages = try await store.loadOutages()
            tracker.loadPersisted(persistedOutages)
            currentOutage = tracker.currentOutage

            let fiveMinAgo = Date().addingTimeInterval(-5 * 60)
            recentMetrics = (try? await store.recentMetrics(since: fiveMinAgo)) ?? []

            let prefs = Preferences.shared
            let engine = MonitorEngine(config: MonitorEngine.Config(
                pingHost: prefs.pingHost,
                dnsHost: prefs.dnsHost,
                interval: .seconds(prefs.intervalSeconds)
            ))
            self.engine = engine
            let stream = engine.stream
            consumeTask = Task { [weak self] in
                for await metric in stream {
                    await self?.handle(metric)
                }
            }
            await engine.start()

            // Request notification permission once.
            await NotificationCoord.shared.requestAuthorization()

            // Prime SystemEventLog (subscribes to sleep/wake/path changes).
            _ = SystemEventLog.shared
        } catch {
            startupError = "Failed to start: \(error.localizedDescription)"
        }
    }

    /// Pull the latest preferences into the engine. Called from SettingsView changes.
    func applyPreferences() async {
        let prefs = Preferences.shared
        await engine?.update(config: MonitorEngine.Config(
            pingHost: prefs.pingHost,
            dnsHost: prefs.dnsHost,
            interval: .seconds(prefs.intervalSeconds)
        ))
    }

    func stop() async {
        await engine?.stop()
        consumeTask?.cancel()
    }

    func fetchMetrics(in range: HistoryRange) async -> [NetworkMetric] {
        guard let store else { return [] }
        do {
            switch range {
            case .all:
                return try await store.allMetrics()
            case .hours(let h):
                let since = Date().addingTimeInterval(-Double(h) * 3600)
                return try await store.recentMetrics(since: since)
            }
        } catch {
            return []
        }
    }

    func fetchOutages() async -> [OutageEvent] {
        guard let store else { return [] }
        return (try? await store.loadOutages()) ?? []
    }

    func fetchPostMortem(for outageID: String) async -> OutagePostMortem? {
        guard let store else { return nil }
        return try? await store.loadPostMortem(for: outageID)
    }

    fileprivate func savePostMortem(_ pm: OutagePostMortem, for outageID: String) async {
        try? await store?.savePostMortem(pm, for: outageID)
    }

    private func handle(_ metric: NetworkMetric) async {
        let result = tracker.processMetric(metric)

        // Persist metric (use the tracker-tagged copy so isOutage flag matches)
        var stored = metric
        stored.isOutage = result.ongoing?.id != nil || result.event?.endTime == nil && result.event != nil
        try? await store?.insertMetric(stored)

        if let event = result.event {
            try? await store?.upsertOutage(event)
            if event.endTime == nil {
                NotificationCoord.shared.outageStarted(event)
                // Fire-and-forget post-mortem capture. Traceroute is slow
                // (10-20s) so we don't await — the report lands in storage
                // when ready and the UI picks it up on next refresh.
                let target = Preferences.shared.pingHost
                Task.detached { [weak self] in
                    let pm = await PostMortemCollector.collect(
                        for: event.startTime, target: target
                    )
                    await self?.savePostMortem(pm, for: event.id)
                }
            } else {
                NotificationCoord.shared.outageEnded(event)
            }
        } else if let ongoing = result.ongoing {
            try? await store?.upsertOutage(ongoing)
        }

        latestMetric = stored
        currentOutage = tracker.currentOutage
        sessionSamples += 1

        // Maintain rolling 5-min window
        recentMetrics.append(stored)
        let fiveMinAgo = Date().addingTimeInterval(-5 * 60)
        recentMetrics.removeAll { $0.timestamp < fiveMinAgo }

        health = HealthScorer.score(stored)
    }
}

enum HistoryRange: Hashable, Identifiable, CaseIterable {
    case hours(Int)
    case all

    static var allCases: [HistoryRange] {
        [.hours(1), .hours(6), .hours(24), .hours(24 * 7), .all]
    }

    var id: String { label }

    var label: String {
        switch self {
        case .hours(let h) where h < 24: return "\(h)h"
        case .hours(let h) where h == 24: return "24h"
        case .hours(let h): return "\(h / 24)d"
        case .all: return "All"
        }
    }
}

enum HealthScorer {
    static func score(_ metric: NetworkMetric) -> HealthState {
        if metric.isOutage || metric.pingPacketLoss >= 50 { return .bad }
        if metric.pingPacketLoss >= 5 || metric.pingAvg >= 100 { return .degraded }
        return .good
    }
}
