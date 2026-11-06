import Foundation

/// Кадрирование протокола MOZA (serial-канал CDC-ACM базы руля).
///
/// Запрос:
/// ```
/// [0x7E][length][group][device][id…][payload…][checksum]
///   length   = len(id) + len(payload)
///   checksum = (13 + сумма всех предыдущих байт) % 256
/// ```
///
/// Ответ — тот же кадр, но `group` приходит с выставленным битом 7
/// (`40` → `0xA8`), а `device` — с перевёрнутыми полубайтами (`0x13` → `0x31`).
///
/// Присутствует ли в ответе байт checksum — по исходникам boxflat установить нельзя
/// (он его не читает), поэтому разбор допускает оба варианта и сообщает наверх,
/// что именно пришло. См. `MozaFrame.trailingChecksum`.
public enum MozaPacket {
    public static let start: UInt8 = 0x7E
    public static let checksumSeed: UInt8 = 13

    /// Диапазон length, который считается осмысленным (как в boxflat);
    /// всё остальное — мусор в потоке, ресинкуемся по стартовому байту.
    public static let lengthRange: ClosedRange<Int> = 2...11

    public static func checksum(over bytes: ArraySlice<UInt8>) -> UInt8 {
        var sum = UInt(checksumSeed)
        for byte in bytes { sum &+= UInt(byte) }
        return UInt8(sum % 256)
    }

    public static func checksum(over bytes: [UInt8]) -> UInt8 {
        checksum(over: bytes[...])
    }

    public static func swapNibbles(_ byte: UInt8) -> UInt8 {
        (byte << 4) | (byte >> 4)
    }

    /// Собрать кадр запроса.
    public static func encode(group: UInt8, device: UInt8, id: [UInt8], payload: [UInt8]) -> [UInt8] {
        var frame: [UInt8] = [start, UInt8(id.count + payload.count), group, device]
        frame.append(contentsOf: id)
        frame.append(contentsOf: payload)
        frame.append(checksum(over: frame))
        return frame
    }

    /// Выбрать из буфера следующий кадр, отбросив мусор перед ним.
    ///
    /// Возвращает `nil`, если данных пока недостаточно (буфер при этом сохраняется,
    /// за вычетом отброшенного мусора). `allowMissingChecksum` = `false` заставляет
    /// подождать ещё один байт на случай, если checksum в ответе всё-таки есть.
    public static func nextFrame(from buffer: inout [UInt8], allowMissingChecksum: Bool) -> MozaFrame? {
        while true {
            guard let startIndex = buffer.firstIndex(of: start) else {
                buffer.removeAll()
                return nil
            }
            if startIndex > 0 { buffer.removeFirst(startIndex) }
            guard buffer.count >= 2 else { return nil }

            let length = Int(buffer[1])
            guard lengthRange.contains(length) else {
                buffer.removeFirst()   // ложный стартовый байт
                continue
            }

            // start + length + group + device + (id + значение)
            let frameLength = 4 + length
            guard buffer.count >= frameLength else { return nil }

            let expected = checksum(over: buffer[0..<frameLength])
            var consumed = frameLength
            var trailing: UInt8?

            if buffer.count > frameLength {
                let candidate = buffer[frameLength]
                if candidate == start && candidate != expected {
                    // Это уже начало следующего кадра — значит checksum в ответе нет.
                    trailing = nil
                } else {
                    trailing = candidate
                    consumed = frameLength + 1
                }
            } else if !allowMissingChecksum {
                return nil   // ждём возможный байт checksum
            }

            let frame = MozaFrame(
                bytes: Array(buffer[0..<consumed]),
                group: buffer[2],
                device: buffer[3],
                body: Array(buffer[4..<frameLength]),
                trailingChecksum: trailing,
                expectedChecksum: expected
            )
            buffer.removeFirst(consumed)
            return frame
        }
    }
}

/// Разобранный кадр, пришедший от базы.
public struct MozaFrame {
    /// Весь кадр целиком, включая байт checksum, если он был.
    public let bytes: [UInt8]
    /// Байт group как он пришёл (с выставленным битом 7).
    public let group: UInt8
    /// Байт device как он пришёл (с перевёрнутыми полубайтами).
    public let device: UInt8
    /// id команды + значение.
    public let body: [UInt8]
    /// Байт, стоящий за кадром, если он был получен.
    public let trailingChecksum: UInt8?
    /// Checksum, посчитанный по той же формуле, что для запросов.
    public let expectedChecksum: UInt8

    /// `nil` — байта checksum в потоке не оказалось.
    public var checksumMatches: Bool? {
        trailingChecksum.map { $0 == expectedChecksum }
    }

    /// Group исходного запроса.
    public var requestGroup: UInt8 { group ^ 0x80 }
    /// Device исходного запроса.
    public var requestDevice: UInt8 { MozaPacket.swapNibbles(device) }

    /// Значение как беззнаковое big-endian целое, лежащее за id длиной `idLength`.
    public func value(idLength: Int, byteCount: Int) -> Int? {
        guard body.count >= idLength + byteCount else { return nil }
        var value = 0
        for byte in body[idLength..<(idLength + byteCount)] {
            value = (value << 8) | Int(byte)
        }
        return value
    }

    public func matches(id: [UInt8]) -> Bool {
        guard body.count >= id.count else { return false }
        return Array(body[0..<id.count]) == id
    }
}

public extension Array where Element == UInt8 {
    /// Hex-представление для логов: `7E 03 28 13 17 00 01 E1`.
    var hexDump: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
