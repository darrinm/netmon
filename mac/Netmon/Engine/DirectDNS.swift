import Foundation
import Darwin

/// Sends a real DNS query over UDP to a specific resolver and times the
/// wire round-trip. Bypasses the system resolver cache so we get an honest
/// measurement on every tick.
enum DirectDNS {
    struct Result: Sendable {
        var responseTime: Double // ms
        var success: Bool
    }

    static func query(name: String, server: String = "1.1.1.1", timeout: TimeInterval = 2) -> Result {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        if fd < 0 { return Result(responseTime: 0, success: false) }
        defer { close(fd) }

        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var serverAddr = sockaddr_in()
        serverAddr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        serverAddr.sin_family = sa_family_t(AF_INET)
        serverAddr.sin_port = UInt16(53).bigEndian
        if inet_pton(AF_INET, server, &serverAddr.sin_addr) != 1 {
            return Result(responseTime: 0, success: false)
        }

        let queryID = UInt16.random(in: 0...UInt16.max)
        let packet = buildQuery(name: name, id: queryID)

        let start = Date()
        let sent = packet.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return withUnsafePointer(to: &serverAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, base, packet.count, 0, sa,
                           socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        if sent < 0 { return Result(responseTime: 0, success: false) }

        var buf = [UInt8](repeating: 0, count: 512)
        let n = recvfrom(fd, &buf, buf.count, 0, nil, nil)
        let elapsedMs = Date().timeIntervalSince(start) * 1000

        guard n >= 12 else { return Result(responseTime: elapsedMs, success: false) }
        let replyID = (UInt16(buf[0]) << 8) | UInt16(buf[1])
        guard replyID == queryID else { return Result(responseTime: elapsedMs, success: false) }
        let flags = (UInt16(buf[2]) << 8) | UInt16(buf[3])
        let rcode = flags & 0x0F
        let ancount = (UInt16(buf[6]) << 8) | UInt16(buf[7])
        let ok = rcode == 0 && ancount > 0
        return Result(responseTime: elapsedMs, success: ok)
    }

    /// DNS query packet for an A record (RFC 1035 §4.1).
    private static func buildQuery(name: String, id: UInt16) -> Data {
        var data = Data()
        // Header
        data.append(UInt8(id >> 8))
        data.append(UInt8(id & 0xff))
        data.append(0x01)               // flags hi: RD (recursion desired)
        data.append(0x00)               // flags lo
        data.append(0x00); data.append(0x01) // QDCOUNT = 1
        data.append(0x00); data.append(0x00) // ANCOUNT
        data.append(0x00); data.append(0x00) // NSCOUNT
        data.append(0x00); data.append(0x00) // ARCOUNT

        // QNAME: length-prefixed labels
        for label in name.split(separator: ".") {
            let bytes = Array(label.utf8)
            data.append(UInt8(bytes.count & 0x3F))
            data.append(contentsOf: bytes)
        }
        data.append(0x00)                    // root label

        data.append(0x00); data.append(0x01) // QTYPE = A
        data.append(0x00); data.append(0x01) // QCLASS = IN
        return data
    }
}
