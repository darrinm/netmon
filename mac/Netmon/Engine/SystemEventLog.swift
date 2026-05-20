import Foundation
import AppKit
import Network

/// Keeps a small rolling buffer of recent system events (sleep/wake, screen
/// lock, network path changes) so an outage post-mortem can attach the
/// "what just happened on this Mac" context.
@MainActor
final class SystemEventLog {
    static let shared = SystemEventLog()

    private(set) var events: [SystemEvent] = []
    private let capacity = 200
    private var pathMonitor: NWPathMonitor?

    init() {
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(self, selector: #selector(onSleep), name: NSWorkspace.willSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(onWake), name: NSWorkspace.didWakeNotification, object: nil)
        ws.addObserver(self, selector: #selector(onScreenLocked), name: NSWorkspace.screensDidSleepNotification, object: nil)
        ws.addObserver(self, selector: #selector(onScreenUnlocked), name: NSWorkspace.screensDidWakeNotification, object: nil)

        startPathMonitor()
    }

    /// Events whose timestamps fall within ±`tolerance` of `pivot`. Used by
    /// the post-mortem to attach "what happened nearby" context.
    func eventsNear(_ pivot: Date, tolerance: TimeInterval = 60) -> [SystemEvent] {
        let lo = pivot.addingTimeInterval(-tolerance)
        let hi = pivot.addingTimeInterval(tolerance)
        return events.filter { $0.timestamp >= lo && $0.timestamp <= hi }
    }

    // MARK: - Observers

    @objc private func onSleep() { record(.sleep) }
    @objc private func onWake() { record(.wake) }
    @objc private func onScreenLocked() { record(.screenLocked) }
    @objc private func onScreenUnlocked() { record(.screenUnlocked) }

    private func record(_ kind: SystemEvent.Kind) {
        events.append(SystemEvent(kind: kind, timestamp: Date()))
        if events.count > capacity {
            events.removeFirst(events.count - capacity)
        }
    }

    // MARK: - Network path

    private func startPathMonitor() {
        let monitor = NWPathMonitor()
        pathMonitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let isSatisfied = path.status == .satisfied
            Task { @MainActor in
                // Only record genuine transitions — macOS fires path
                // updates often even when satisfied-status is unchanged,
                // which would otherwise flush the buffer with duplicates.
                guard let self, self.lastPathSatisfied != isSatisfied else { return }
                self.lastPathSatisfied = isSatisfied
                self.record(isSatisfied ? .networkPathSatisfied : .networkPathUnsatisfied)
            }
        }
        monitor.start(queue: .global(qos: .utility))
    }

    private var lastPathSatisfied: Bool?
}
