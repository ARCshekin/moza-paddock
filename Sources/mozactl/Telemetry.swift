import Foundation

// Приём UDP-телеметрии DiRT Rally. Пакет — массив 32-битных float
// (little-endian). Раскладку не считаем известной: показываем все значения с
// номерами и отмечаем, какие меняются, — так поля определяются по живым данным,
// а не по догадкам.

func runTelemetry(port: UInt16, dumpAll: Bool) {
    let handle = socket(AF_INET, SOCK_DGRAM, 0)
    guard handle >= 0 else { fail("не удалось создать UDP-сокет") }
    defer { Darwin.close(handle) }

    var reuse: Int32 = 1
    setsockopt(handle, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

    var address = sockaddr_in()
    address.sin_family = sa_family_t(AF_INET)
    address.sin_port = port.bigEndian
    address.sin_addr.s_addr = INADDR_ANY

    let bound = withUnsafePointer(to: &address) { pointer in
        pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            bind(handle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
        }
    }
    guard bound == 0 else {
        fail("порт \(port) занят — кто-то уже слушает телеметрию")
    }

    print("Слушаю UDP \(port). Запустите заезд в игре.")
    print("Ctrl-C для выхода.")
    print("")

    var buffer = [UInt8](repeating: 0, count: 2048)
    var packets = 0
    var reportedSize = -1
    var minimum: [Float] = []
    var maximum: [Float] = []
    var lastPrint = Date.distantPast
    var firstPacket: Date?

    while true {
        var pollDescriptor = pollfd(fd: handle, events: Int16(POLLIN), revents: 0)
        guard poll(&pollDescriptor, 1, 1000) > 0 else {
            if packets == 0 { continue }
            continue
        }

        let count = recv(handle, &buffer, buffer.count, 0)
        guard count > 0 else { continue }
        packets += 1
        if firstPacket == nil { firstPacket = Date() }

        // Разбор в массив float.
        let floatCount = count / 4
        var values = [Float](repeating: 0, count: floatCount)
        for index in 0..<floatCount {
            var bits: UInt32 = 0
            for byte in 0..<4 {
                bits |= UInt32(buffer[index * 4 + byte]) << (8 * UInt32(byte))
            }
            values[index] = Float(bitPattern: bits)
        }

        if reportedSize != count {
            reportedSize = count
            print("Пакет: \(count) байт = \(floatCount) значений float")
            print("")
            minimum = values
            maximum = values
        }
        for index in 0..<min(floatCount, minimum.count) {
            minimum[index] = min(minimum[index], values[index])
            maximum[index] = max(maximum[index], values[index])
        }

        guard Date().timeIntervalSince(lastPrint) > 0.4 else { continue }
        lastPrint = Date()

        let elapsed = firstPacket.map { Date().timeIntervalSince($0) } ?? 1
        let rate = elapsed > 0 ? Double(packets) / elapsed : 0

        var lines: [String] = []
        for index in 0..<floatCount {
            let value = values[index]
            let span = maximum[index] - minimum[index]
            // Пометка у тех, что реально меняются: по ним и опознаём поля.
            let mark = span > 0.001 ? "*" : " "
            if !dumpAll && span <= 0.001 && abs(value) < 0.0001 { continue }
            lines.append(String(format: "%2d%@%10.3f", index, mark, value))
        }

        print("\u{1B}[H\u{1B}[2J", terminator: "")   // очистить экран
        print("Пакетов: \(packets), \(String(format: "%.0f", rate)) в секунду. "
            + "Звёздочкой отмечены значения, которые менялись.")
        print(dumpAll ? "Показаны все значения." : "Скрыты значения, которые всё время были нулевыми (--all покажет все).")
        print("")
        for row in stride(from: 0, to: lines.count, by: 6) {
            print(lines[row..<min(row + 6, lines.count)].joined(separator: "   "))
        }
        fflush(stdout)
    }
}
