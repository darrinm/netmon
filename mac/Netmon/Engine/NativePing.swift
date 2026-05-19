import Foundation
import Darwin

/// Unprivileged ICMP echo using SOCK_DGRAM/IPPROTO_ICMP — works on macOS
/// without sudo or special entitlements (the kernel inserts the identifier
/// and computes the checksum for SOCK_DGRAM sockets).
enum NativePing {
    struct Result: Sendable {
        var min: Double
        var avg: Double
        var max: Double
        var packetLoss: Double // 0..100
    }

    static let failure = Result(min: 0, avg: 0, max: 0, packetLoss: 100)

    /// Sends `count` echo requests sequentially, returns aggregate RTT + loss.
    static func ping(host: String, count: Int = 3, timeout: TimeInterval = 2) -> Result {
        // Resolve host to an IPv4 socket address.
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_INET,
            ai_socktype: SOCK_DGRAM,
            ai_protocol: IPPROTO_ICMP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var info: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &info) == 0, let resolved = info else {
            return failure
        }
        defer { freeaddrinfo(resolved) }

        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_ICMP)
        if fd < 0 { return failure }
        defer { close(fd) }

        // Receive timeout.
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var rtts: [Double] = []
        for i in 0..<count {
            let packet = makeEchoRequest(seq: UInt16(i))
            let start = Date()

            let sent = packet.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return sendto(
                    fd, base, packet.count, 0,
                    resolved.pointee.ai_addr,
                    resolved.pointee.ai_addrlen
                )
            }
            if sent < 0 { continue }

            var buf = [UInt8](repeating: 0, count: 1500)
            let n = recvfrom(fd, &buf, buf.count, 0, nil, nil)
            if n < 0 {
                // Likely EAGAIN/timeout
                continue
            }

            // Verify it's an Echo Reply (type 0). For SOCK_DGRAM the kernel
            // strips the IP header, so the ICMP packet starts at offset 0.
            if n >= 8 && buf[0] == 0 {
                let rttMs = Date().timeIntervalSince(start) * 1000
                rtts.append(rttMs)
            }

            // Small inter-ping spacing.
            if i < count - 1 {
                Thread.sleep(forTimeInterval: 0.2)
            }
        }

        let lost = count - rtts.count
        let lossPct = Double(lost) / Double(count) * 100
        guard let lo = rtts.min(), let hi = rtts.max(), !rtts.isEmpty else {
            return Result(min: 0, avg: 0, max: 0, packetLoss: lossPct)
        }
        let avg = rtts.reduce(0, +) / Double(rtts.count)
        return Result(min: lo, avg: avg, max: hi, packetLoss: lossPct)
    }

    /// ICMPv4 Echo Request packet body. Type=8 Code=0; checksum left zero
    /// (kernel fills for SOCK_DGRAM). Identifier 0 — kernel rewrites it.
    private static func makeEchoRequest(seq: UInt16) -> Data {
        var data = Data(count: 8)
        data[0] = 8           // type
        data[1] = 0           // code
        // checksum (2 bytes) left zero
        // id (2 bytes) left zero — kernel will rewrite
        // seq (2 bytes)
        let seqBE = seq.bigEndian
        data[6] = UInt8(truncatingIfNeeded: seqBE)
        data[7] = UInt8(truncatingIfNeeded: seqBE >> 8)

        // Add a small payload with a timestamp so packets are unique.
        let payload = "netmon-\(Date().timeIntervalSince1970)".data(using: .ascii) ?? Data()
        data.append(payload)
        return data
    }
}
