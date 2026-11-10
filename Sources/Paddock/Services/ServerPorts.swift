import Darwin

/// Probe only local binds; never terminate another listener or change firewall rules.
enum ServerPorts {
    static func available(_ port: Int, udp: Bool) -> Bool {
        guard (1024...65535).contains(port) else { return false }
        var sockets: [Int32] = []
        defer { sockets.forEach { close($0) } }
        for type in udp ? [SOCK_STREAM, SOCK_DGRAM] : [SOCK_STREAM] {
            let descriptor = socket(AF_INET, type, 0)
            guard descriptor >= 0 else { return false }
            sockets.append(descriptor)
            if type == SOCK_STREAM {
                // Match Go's TCP listener: TIME_WAIT is reusable, a live listener is not.
                var reuse: Int32 = 1
                guard setsockopt(descriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size)) == 0 else { return false }
            }
            var address = sockaddr_in()
            address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            address.sin_family = sa_family_t(AF_INET)
            address.sin_port = UInt16(port).bigEndian
            address.sin_addr.s_addr = INADDR_ANY
            let result = withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
            }
            if result != 0 { return false }
        }
        return true
    }
    static func suggested(_ start: Int, udp: Bool) -> Int {
        (start...min(start + 100, 65535)).first { available($0, udp: udp) } ?? start
    }
}
