import Darwin

/// Probe only local binds; never terminate another listener or change firewall rules.
enum ServerPorts {
    static func available(_ port: Int, udp: Bool) -> Bool {
        guard (1024...65535).contains(port) else { return false }
        // With SO_REUSEADDR, a wildcard bind alone can miss a listener bound
        // specifically to loopback or one LAN address. Probe those addresses too.
        let addresses = ["0.0.0.0", "127.0.0.1"] + ServerLANAddress.current().map(\.ip)
        for type in udp ? [SOCK_STREAM, SOCK_DGRAM] : [SOCK_STREAM] {
            for ip in addresses where !canBind(port, ip: ip, type: type) { return false }
        }
        return true
    }
    private static func canBind(_ port: Int, ip: String, type: Int32) -> Bool {
        let descriptor = socket(AF_INET, type, 0)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        if type == SOCK_STREAM {
            // Match Go's TCP listener: TIME_WAIT is reusable, a live listener is not.
            var reuse: Int32 = 1
            guard setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)) == 0 else { return false }
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(port).bigEndian
        guard ip.withCString({ inet_pton(AF_INET, $0, &address.sin_addr) }) == 1 else { return false }
        return withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) == 0 }
        }
    }
    static func suggested(_ start: Int, udp: Bool) -> Int {
        (start...min(start + 100, 65535)).first { available($0, udp: udp) } ?? start
    }
}
