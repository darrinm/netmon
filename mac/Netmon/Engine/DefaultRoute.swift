import Foundation

/// Reads the system default route — the gateway IP and the interface that
/// carries it. Shells out to `route -n get default`; blocking, so call it
/// off the main actor.
enum DefaultRoute {
    struct Info: Sendable {
        var gatewayIP: String?
        var interface: String?
    }

    static func current() -> Info {
        let text = Subprocess.capture("/sbin/route", ["-n", "get", "default"])
        var gateway: String?
        var interface: String?
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("gateway:") {
                gateway = String(trimmed.dropFirst("gateway:".count)).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("interface:") {
                interface = String(trimmed.dropFirst("interface:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return Info(gatewayIP: gateway, interface: interface)
    }
}
