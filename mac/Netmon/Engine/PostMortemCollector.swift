import Foundation
import AppKit
import CoreWLAN
import CoreLocation

/// Captures the post-mortem snapshot for an outage. Runs in the background
/// — the most expensive piece (traceroute) takes 10-20s, so callers should
/// fire-and-forget and let the result land in storage when ready.
final class PostMortemCollector {
    static func collect(for outageStart: Date, target: String) async -> OutagePostMortem {
        // Cheap captures first so the snapshot reflects the moment closely.
        let route = await Task.detached { DefaultRoute.current() }.value
        let primary = route.interface
        let wifiInterfaceNames = await MainActor.run { Self.wifiInterfaceNames() }

        var wifi: WiFiSnapshot?
        var ethernet: EthernetSnapshot?
        if let primary, wifiInterfaceNames.contains(primary) {
            wifi = await MainActor.run { Self.captureWiFi(interface: primary) }
        } else if let primary {
            ethernet = await Task.detached { Self.captureEthernet(interface: primary) }.value
        }

        let events = await MainActor.run { SystemEventLog.shared.eventsNear(outageStart) }

        // Traceroute is slow and best run after the cheap captures.
        let hops = await Task.detached { Self.runTraceroute(target: target) }.value

        // Read link-down intervals last — gives the live log stream maximum
        // time to deliver the link_on event (the outage's link_on lands a
        // few seconds in, and traceroute above already bought us ~15s).
        let links = await LinkEventMonitor.shared.recentIntervals(near: outageStart).map {
            LinkDownInterval(interface: $0.interface, start: $0.start, end: $0.end, durationMs: $0.durationMs)
        }

        return OutagePostMortem(
            capturedAt: Date(),
            wifi: wifi,
            ethernet: ethernet,
            traceroute: hops,
            gatewayIP: route.gatewayIP,
            recentSystemEvents: events,
            linkDownIntervals: links
        )
    }

    // MARK: - Interface detection

    /// All BSD device names CoreWLAN considers Wi-Fi interfaces.
    @MainActor
    private static func wifiInterfaceNames() -> Set<String> {
        Set(CWWiFiClient.shared().interfaces()?.compactMap { $0.interfaceName } ?? [])
    }

    // MARK: - Wi-Fi

    @MainActor
    private static func captureWiFi(interface: String) -> WiFiSnapshot? {
        guard let iface = CWWiFiClient.shared().interface(withName: interface) else { return nil }
        return WiFiSnapshot(
            interface: interface,
            ssid: iface.ssid(),
            bssid: iface.bssid(),
            rssiDBm: iface.rssiValue(),
            noiseDBm: iface.noiseMeasurement(),
            channel: iface.wlanChannel()?.channelNumber,
            transmitRateMbps: iface.transmitRate()
        )
    }

    // MARK: - Ethernet

    private static func captureEthernet(interface: String) -> EthernetSnapshot? {
        let ifconfigText = Subprocess.capture("/sbin/ifconfig", [interface])
        guard !ifconfigText.isEmpty else { return nil }

        var mac: String?, ip: String?, media: String?, mtu: Int?
        var linkActive: Bool = false

        for line in ifconfigText.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // First line includes mtu, e.g. "en0: flags=... mtu 1500"
            if trimmed.hasPrefix("\(interface):"), let mtuRange = trimmed.range(of: "mtu ") {
                let after = trimmed[mtuRange.upperBound...]
                let firstNum = after.split(whereSeparator: { !$0.isNumber }).first ?? ""
                mtu = Int(firstNum)
            }
            if trimmed.hasPrefix("ether ") {
                mac = String(trimmed.dropFirst("ether ".count)).split(whereSeparator: { $0.isWhitespace }).first.map(String.init)
            }
            if trimmed.hasPrefix("inet "), let after = trimmed.split(whereSeparator: { $0.isWhitespace }).dropFirst().first {
                ip = String(after)
            }
            if trimmed.hasPrefix("media:") {
                // "media: autoselect (1000baseT <full-duplex>)" — keep just the parenthetical.
                if let open = trimmed.firstIndex(of: "("),
                   let close = trimmed.lastIndex(of: ")"),
                   open < close {
                    media = String(trimmed[trimmed.index(after: open)..<close])
                } else {
                    media = String(trimmed.dropFirst("media:".count)).trimmingCharacters(in: .whitespaces)
                }
            }
            if trimmed.hasPrefix("status:") {
                linkActive = trimmed.contains("active")
            }
        }

        let hardwarePort = lookupHardwarePort(for: interface)

        return EthernetSnapshot(
            interface: interface,
            hardwarePort: hardwarePort,
            macAddress: mac,
            ipAddress: ip,
            linkActive: linkActive,
            media: media,
            mtu: mtu
        )
    }

    /// Maps "en1" → "Ethernet" / "Wi-Fi" / "Thunderbolt Bridge" / ... using
    /// `networksetup -listallhardwareports`.
    private static func lookupHardwarePort(for interface: String) -> String? {
        let text = Subprocess.capture("/usr/sbin/networksetup", ["-listallhardwareports"])
        // Blocks look like:
        //   Hardware Port: Ethernet
        //   Device: en1
        //   Ethernet Address: aa:bb:...
        let blocks = text.components(separatedBy: "\n\n")
        for block in blocks {
            if block.contains("Device: \(interface)") {
                for line in block.split(separator: "\n") {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    if trimmed.hasPrefix("Hardware Port:") {
                        return String(trimmed.dropFirst("Hardware Port:".count)).trimmingCharacters(in: .whitespaces)
                    }
                }
            }
        }
        return nil
    }

    // MARK: - Traceroute

    private static func runTraceroute(target: String, maxHops: Int = 15) -> [TracerouteHop] {
        let text = Subprocess.capture(
            "/usr/sbin/traceroute",
            ["-n", "-m", "\(maxHops)", "-w", "1", "-q", "1", target]
        )
        return parseTraceroute(text)
    }

    /// Parses macOS traceroute output (with `-n` for numeric, so we get IPs only).
    static func parseTraceroute(_ output: String) -> [TracerouteHop] {
        var hops: [TracerouteHop] = []
        for line in output.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("traceroute") { continue }

            let parts = trimmed.split(whereSeparator: { $0.isWhitespace })
            guard parts.count >= 2,
                  let idx = Int(parts[0]) else { continue }

            if parts[1] == "*" {
                hops.append(TracerouteHop(index: idx, host: nil, ip: nil, rttMs: nil))
                continue
            }

            let ip = String(parts[1])
            var rtt: Double?
            if parts.count >= 3 {
                rtt = Double(parts[2])
            }
            hops.append(TracerouteHop(index: idx, host: nil, ip: ip, rttMs: rtt))
        }
        return hops
    }

}

/// Asks for Location Services authorization. CoreWLAN returns nil for
/// `ssid()` / `bssid()` unless the user grants this. Other Wi-Fi fields
/// (RSSI, channel, transmit rate) work without it. Not auto-prompted —
/// invoked explicitly from Settings if the user wants SSIDs in reports.
@MainActor
final class WiFiAuthCoordinator: NSObject, CLLocationManagerDelegate {
    static let shared = WiFiAuthCoordinator()
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
    }

    var status: CLAuthorizationStatus { manager.authorizationStatus }

    func requestIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        // No-op; CoreWLAN starts returning SSID/BSSID once authorized.
    }
}
