import Foundation

/// Snapshot of system + network state at the moment an outage was first
/// detected. Useful for "what was going on when the network died?".
struct OutagePostMortem: Codable, Sendable {
    var capturedAt: Date
    var wifi: WiFiSnapshot?
    var ethernet: EthernetSnapshot?
    var traceroute: [TracerouteHop]?
    var gatewayIP: String?
    var recentSystemEvents: [SystemEvent]
    /// Kernel link_off→link_on intervals near the outage, captured live from
    /// the unified log. Empty for outages recorded before this was added.
    var linkDownIntervals: [LinkDownInterval]?
}

struct LinkDownInterval: Codable, Sendable, Identifiable {
    var id: Date { start }
    var interface: String
    var start: Date
    var end: Date?
    var durationMs: Double?
}

struct WiFiSnapshot: Codable, Sendable {
    var interface: String
    /// May be nil if Location Services authorization wasn't granted.
    var ssid: String?
    /// Same caveat as `ssid`.
    var bssid: String?
    var rssiDBm: Int
    var noiseDBm: Int
    var channel: Int?
    var transmitRateMbps: Double
}

struct EthernetSnapshot: Codable, Sendable {
    var interface: String           // en0, en1, ...
    var hardwarePort: String?       // "Ethernet", "Thunderbolt Bridge", ...
    var macAddress: String?
    var ipAddress: String?
    var linkActive: Bool
    /// Human-readable media string from `ifconfig`, e.g. "1000baseT <full-duplex>".
    var media: String?
    var mtu: Int?

    /// Hardware-port name for headings, falling back to "Ethernet".
    var displayName: String { hardwarePort ?? "Ethernet" }
}

struct TracerouteHop: Codable, Sendable, Identifiable {
    var id: Int { index }
    var index: Int
    var host: String?
    var ip: String?
    /// Round-trip time in ms. `nil` if the hop timed out.
    var rttMs: Double?
}

struct SystemEvent: Codable, Sendable, Identifiable {
    enum Kind: String, Codable, Sendable {
        case sleep, wake, screenLocked, screenUnlocked
        case networkPathSatisfied, networkPathUnsatisfied

        var label: String {
            switch self {
            case .sleep:                   return "Mac slept"
            case .wake:                    return "Mac woke"
            case .screenLocked:            return "Screen locked"
            case .screenUnlocked:          return "Screen unlocked"
            case .networkPathSatisfied:    return "Network path satisfied"
            case .networkPathUnsatisfied:  return "Network path unsatisfied"
            }
        }

        var systemImage: String {
            switch self {
            case .sleep, .wake:                       return "moon.zzz"
            case .screenLocked, .screenUnlocked:      return "lock"
            case .networkPathSatisfied:               return "checkmark.circle"
            case .networkPathUnsatisfied:             return "exclamationmark.triangle"
            }
        }
    }
    var id: UUID = UUID()
    var kind: Kind
    var timestamp: Date

    private enum CodingKeys: String, CodingKey { case kind, timestamp }

    init(kind: Kind, timestamp: Date) {
        self.kind = kind
        self.timestamp = timestamp
    }
}

import SwiftUI

extension SystemEvent.Kind {
    var tint: Color {
        switch self {
        case .sleep, .screenLocked:           return .indigo
        case .wake, .screenUnlocked:          return .blue
        case .networkPathSatisfied:           return .green
        case .networkPathUnsatisfied:         return .red
        }
    }
}
