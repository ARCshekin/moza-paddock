import Foundation

/// Кадр телеметрии DiRT Rally: 264 байта = 66 значений float (little-endian),
/// приходит по UDP на 127.0.0.1:20777 при `<udp enabled="true" extradata="3">`.
///
/// Раскладка установлена на живой игре (порт Feral, macOS): газ, тормоз и руль
/// подтверждены сопоставлением с осями, прочитанными через HID параллельно
/// (r = 0,85 / 0,71 / 0,96), остальное — по диапазонам и связям между полями.
public struct MozaTelemetryFrame {
    public let raw: [Float]

    public init?(_ values: [Float]) {
        guard values.count >= 66 else { return nil }
        raw = values
    }

    public var time: Float { raw[0] }
    public var lapTime: Float { raw[1] }
    public var distance: Float { raw[2] }
    public var progress: Float { raw[3] }

    /// Скорость, м/с.
    public var speed: Float { raw[7] }

    /// Ход подвески, порядок: ЗЛ, ЗП, ПЛ, ПП.
    ///
    /// Порядок подтверждён косвенно: температуры тормозов (поля 51…54) идут в
    /// том же порядке, и в записи заезда две последние заметно горячее
    /// (375 и 374 против 231 и 332) — что соответствует передней развесовке
    /// тормозов, то есть последняя пара это передние колёса.
    public var suspensionPosition: [Float] { Array(raw[17...20]) }
    public var suspensionVelocity: [Float] { Array(raw[21...24]) }
    public var wheelPatchSpeed: [Float] { Array(raw[25...28]) }

    public var suspensionVelocityFrontLeft: Float { raw[23] }
    public var suspensionVelocityFrontRight: Float { raw[24] }
    public var wheelSpeedFrontLeft: Float { raw[27] }
    public var wheelSpeedFrontRight: Float { raw[28] }

    public var throttle: Float { raw[29] }
    /// Положение руля, −1…1.
    public var steer: Float { raw[30] }
    public var brake: Float { raw[31] }
    public var clutch: Float { raw[32] }
    /// Передача; 10 — задняя.
    public var gear: Float { raw[33] }

    /// Боковая перегрузка. Поворот вправо даёт ОТРИЦАТЕЛЬНОЕ значение
    /// (проверено: r с положением руля = −0,87 в поворотах на скорости).
    public var gForceLateral: Float { raw[34] }
    /// Продольная перегрузка: торможение отрицательна, разгон положителен.
    public var gForceLongitudinal: Float { raw[35] }

    public var lap: Float { raw[36] }
    /// Обороты двигателя в рад/с (733,04 = 7000 об/мин).
    public var engineRate: Float { raw[37] }
    public var brakeTemperatures: [Float] { Array(raw[51...54]) }
    public var maxEngineRate: Float { raw[63] }
    public var idleEngineRate: Float { raw[64] }
    public var maxGears: Float { raw[65] }

    public var engineRPM: Float { engineRate * 60 / (2 * .pi) }
    public var speedKmh: Float { speed * 3.6 }
}

/// Приём телеметрии по UDP.
public final class MozaTelemetryReceiver {
    public enum ReceiverError: Error, CustomStringConvertible {
        case socketFailed
        case bindFailed(port: UInt16, errno: Int32)

        public var description: String {
            switch self {
            case .socketFailed: return "не удалось создать UDP-сокет"
            case let .bindFailed(port, code):
                return "не удалось занять порт \(port): \(String(cString: strerror(code)))"
                    + " — возможно, телеметрию уже кто-то слушает"
            }
        }
    }

    private var handle: Int32 = -1
    private var thread: Thread?
    private var running = false
    public let port: UInt16

    public init(port: UInt16 = 20777) {
        self.port = port
    }

    deinit { stop() }

    /// Запускает приём. Обработчик вызывается на отдельном потоке.
    public func start(_ handler: @escaping (MozaTelemetryFrame) -> Void) throws {
        let socketHandle = socket(AF_INET, SOCK_DGRAM, 0)
        guard socketHandle >= 0 else { throw ReceiverError.socketFailed }

        var reuse: Int32 = 1
        setsockopt(socketHandle, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = INADDR_ANY

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(socketHandle, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            Darwin.close(socketHandle)
            throw ReceiverError.bindFailed(port: port, errno: code)
        }

        handle = socketHandle
        running = true

        let thread = Thread { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 2048)
            while let self, self.running {
                var descriptor = pollfd(fd: socketHandle, events: Int16(POLLIN), revents: 0)
                guard poll(&descriptor, 1, 200) > 0 else { continue }

                let count = recv(socketHandle, &buffer, buffer.count, 0)
                guard count > 0, count % 4 == 0 else { continue }

                var values = [Float](repeating: 0, count: count / 4)
                for index in 0..<(count / 4) {
                    var bits: UInt32 = 0
                    for byte in 0..<4 {
                        bits |= UInt32(buffer[index * 4 + byte]) << (8 * UInt32(byte))
                    }
                    values[index] = Float(bitPattern: bits)
                }
                if let frame = MozaTelemetryFrame(values) { handler(frame) }
            }
        }
        thread.name = "moza.telemetry"
        thread.start()
        self.thread = thread
    }

    public func stop() {
        running = false
        if handle >= 0 {
            Darwin.close(handle)
            handle = -1
        }
    }
}
