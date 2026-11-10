import Foundation
import Darwin

struct ServerLANAddress: Identifiable, Equatable {
    let interface: String
    let ip: String
    var broadcast: String? = nil
    var id: String { ip }

    static func current() -> [ServerLANAddress] {
        var first: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&first) == 0 else { return [] }
        defer { freeifaddrs(first) }
        var found: [ServerLANAddress] = []
        var cursor = first
        while let entry = cursor {
            defer { cursor = entry.pointee.ifa_next }
            let value = entry.pointee
            guard let address = value.ifa_addr, address.pointee.sa_family == UInt8(AF_INET),
                  value.ifa_flags & UInt32(IFF_UP) != 0, value.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }
            var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            guard getnameinfo(address, socklen_t(address.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 else { continue }
            let ip = String(cString: buffer)
            guard !ip.hasPrefix("127."), ip != "0.0.0.0", !found.contains(where: { $0.ip == ip }) else { continue }
            var broadcast: String?
            if value.ifa_flags & UInt32(IFF_BROADCAST) != 0, let target = value.ifa_dstaddr {
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(target, socklen_t(target.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    broadcast = String(cString: buffer)
                }
            }
            found.append(.init(interface: String(cString: value.ifa_name), ip: ip, broadcast: broadcast))
        }
        // Prefer Wi-Fi/Ethernet to virtual adapters while retaining VPN addresses.
        return found.sorted {
            let left = $0.interface.hasPrefix("en"), right = $1.interface.hasPrefix("en")
            return left != right ? left : $0.ip.localizedStandardCompare($1.ip) == .orderedAscending
        }
    }
}

/// Only the immutable configuration of the created server, never a new UI draft.
struct ServerConnectionDetails {
    let configuration: HostedServerDraft
    var addresses: [ServerLANAddress]
    var localAddress: String { endpoint("127.0.0.1") }
    func endpoint(_ ip: String) -> String { "\(ip):\(configuration.httpPort)" }
    func invitation(ip: String) -> String {
        ["Сервер: \(configuration.name)",
         "Адрес для Paddock / Content Manager: \(endpoint(ip))",
         "Игровой порт TCP/UDP: \(configuration.racePort)",
         "Режим: \(configuration.mode.title)",
         "Автомобили и места: \(configuration.carSummary)",
         "Трасса: \(configuration.track)\(configuration.layout.isEmpty ? "" : " / " + configuration.layout)",
         "Пароль: \(configuration.password.isEmpty ? "не требуется" : "нужен — получите у организатора")"].joined(separator: "\n")
    }
}
