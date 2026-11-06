import Foundation

public struct MozaReadResult {
    public let command: MozaCommand
    public let request: [UInt8]
    public let response: [UInt8]
    public let wireValue: Int
    public let humanValue: Int
    /// `nil` — байта checksum в ответе не оказалось (гипотеза о его наличии не подтвердилась).
    public let checksumMatches: Bool?
    /// Кадры, пришедшие до нужного (для диагностики).
    public let unexpectedFrames: [[UInt8]]
    public let attempts: Int
}

public struct MozaWriteResult {
    public let command: MozaCommand
    public let request: [UInt8]
    public let requestedHuman: Int
    public let requestedWire: Int
    /// Результат контрольного чтения; `nil` для команд, которые нельзя прочитать
    /// (например, калибровка).
    public let readBack: MozaReadResult?

    /// `nil` — проверить нечем (команда только на запись).
    public var verified: Bool? {
        readBack.map { $0.wireValue == requestedWire }
    }
}

/// Общение с базой руля по serial-протоколу.
///
/// Запись выключена по умолчанию: `writesEnabled` нужно включить явно, чтобы
/// случайный вызов не изменил настройки базы.
public final class MozaDevice {
    public enum DeviceError: Error, CustomStringConvertible {
        case notFound
        case commandUnknown(String)
        case notReadable(String)
        case notWritable(String)
        case writesDisabled
        case valueOutOfRange(command: String, value: Int, range: ClosedRange<Int>, unit: String)
        case valueNotRepresentable(command: String, value: Int, nearest: Int, unit: String)
        case noResponse(command: String, request: [UInt8])
        case malformedResponse(command: String, frame: [UInt8])

        public var description: String {
            switch self {
            case .notFound:
                return "устройство MOZA не найдено: нет serial-порта с VID 0x346e (проверьте кабель и питание базы)"
            case let .commandUnknown(name):
                return "неизвестная команда «\(name)»"
            case let .notReadable(name):
                return "команда «\(name)» не поддерживает чтение"
            case let .notWritable(name):
                return "команда «\(name)» не поддерживает запись"
            case .writesDisabled:
                return "запись не включена (в mozactl добавьте --yes)"
            case let .valueOutOfRange(name, value, range, unit):
                return "значение \(MozaCommand.format(value, unit: unit)) вне допустимого диапазона "
                    + "\(range.lowerBound)…\(range.upperBound) для «\(name)»"
            case let .valueNotRepresentable(name, value, nearest, unit):
                return "значение \(MozaCommand.format(value, unit: unit)) нельзя передать точно "
                    + "для «\(name)»: ближайшее представимое — \(MozaCommand.format(nearest, unit: unit))"
            case let .noResponse(name, request):
                return "база не ответила на запрос \(name) (\(request.hexDump))"
            case let .malformedResponse(name, frame):
                return "не удалось разобрать ответ на \(name): \(frame.hexDump)"
            }
        }
    }

    private let port: SerialPort
    public let portInfo: SerialPortInfo
    public var verbose: Bool
    /// Пока `false`, любая попытка записи отклоняется.
    public var writesEnabled = false
    /// Сколько ждать ответ на один запрос (boxflat ждёт 50 мс; берём с запасом).
    public var responseTimeout: TimeInterval = 0.3
    /// Сколько ждать байт checksum после полного кадра, прежде чем счесть, что его нет.
    public var checksumGrace: TimeInterval = 0.06
    /// Пауза после записи, чтобы база успела применить значение до контрольного чтения.
    public var settleDelay: TimeInterval = 0.05

    public init(portInfo: SerialPortInfo, verbose: Bool = false) {
        self.portInfo = portInfo
        self.port = SerialPort(path: portInfo.calloutPath)
        self.verbose = verbose
    }

    /// Найти базу и открыть её порт.
    public static func discover(verbose: Bool = false) throws -> MozaDevice {
        guard let info = MozaDiscovery.mozaSerialPorts().first else {
            throw DeviceError.notFound
        }
        let device = MozaDevice(portInfo: info, verbose: verbose)
        try device.open()
        return device
    }

    public func open() throws {
        try port.openPort()
        port.flush()
    }

    public func close() {
        port.closePort()
    }

    // MARK: - Чтение

    public func read(_ name: String) throws -> MozaReadResult {
        guard let command = MozaSettings.command(named: name) else {
            throw DeviceError.commandUnknown(name)
        }
        return try read(command)
    }

    public func read(_ command: MozaCommand) throws -> MozaReadResult {
        guard let group = command.readGroup else {
            throw DeviceError.notReadable(command.name)
        }

        // Read-запрос по формату идентичен write и несёт payload = 1:
        // «read commands only work with a value of 1».
        let payload = MozaDevice.bigEndian(1, byteCount: command.byteCount)
        let request = MozaPacket.encode(
            group: group,
            device: MozaSettings.baseDeviceID,
            id: command.id,
            payload: payload
        )

        var unexpected: [[UInt8]] = []

        // Один повтор при отсутствии ответа — как в boxflat.
        for attempt in 1...2 {
            if verbose {
                FileHandle.standardError.write(
                    Data("→ \(command.name) попытка \(attempt): \(request.hexDump)\n".utf8)
                )
            }

            port.flush()
            try port.write(request)

            if let frame = try awaitFrame(group: group, command: command, collecting: &unexpected) {
                guard let wire = frame.value(idLength: command.id.count, byteCount: command.byteCount) else {
                    throw DeviceError.malformedResponse(command: command.name, frame: frame.bytes)
                }
                if verbose {
                    FileHandle.standardError.write(
                        Data("← \(command.name): \(frame.bytes.hexDump)\n".utf8)
                    )
                }
                return MozaReadResult(
                    command: command,
                    request: request,
                    response: frame.bytes,
                    wireValue: wire,
                    humanValue: command.human(fromWire: wire),
                    checksumMatches: frame.checksumMatches,
                    unexpectedFrames: unexpected,
                    attempts: attempt
                )
            }
        }

        throw DeviceError.noResponse(command: command.name, request: request)
    }

    /// Прочитать всё, что поддерживает чтение. Ошибки по отдельным командам не
    /// прерывают опрос — они возвращаются вместе с успешными результатами.
    public func readAll() -> [(command: MozaCommand, result: Result<MozaReadResult, Error>)] {
        MozaSettings.readable.map { command in
            do {
                return (command, .success(try read(command)))
            } catch {
                return (command, .failure(error))
            }
        }
    }

    // MARK: - Запись

    /// Записать одну настройку и, если её можно прочитать, сверить результат.
    ///
    /// Значение задаётся в человеческих единицах (градусы, проценты) — пересчёт
    /// в значение на проводе делает таблица команд.
    public func write(_ command: MozaCommand, human value: Int) throws -> MozaWriteResult {
        guard writesEnabled else { throw DeviceError.writesDisabled }
        guard let group = command.writeGroup else { throw DeviceError.notWritable(command.name) }

        if let range = command.humanRange, !range.contains(value) {
            throw DeviceError.valueOutOfRange(
                command: command.name, value: value, range: range, unit: command.unit
            )
        }

        let wire = command.wire(fromHuman: value)

        // Значение должно быть представимо точно: при масштабе ÷2 нечётные градусы
        // округлились бы молча, и прочитанное обратно не совпало бы с заданным.
        let roundTrip = command.human(fromWire: wire)
        guard roundTrip == value else {
            throw DeviceError.valueNotRepresentable(
                command: command.name, value: value, nearest: roundTrip, unit: command.unit
            )
        }

        // Значение обязано влезть в поле нужной длины.
        let limit = 1 << (8 * command.byteCount)
        guard wire >= 0, wire < limit else {
            throw DeviceError.valueOutOfRange(
                command: command.name, value: value,
                range: 0...(command.human(fromWire: limit - 1)), unit: command.unit
            )
        }

        let request = MozaPacket.encode(
            group: group,
            device: MozaSettings.baseDeviceID,
            id: command.id,
            payload: MozaDevice.bigEndian(wire, byteCount: command.byteCount)
        )

        if verbose {
            FileHandle.standardError.write(
                Data("→ ЗАПИСЬ \(command.name) = \(value)\(command.unit) (на проводе \(wire)): \(request.hexDump)\n".utf8)
            )
        }

        port.flush()
        try port.write(request)

        // Ответа на запись протокол не предполагает; даём базе применить значение.
        // Мусор, если он всё же придёт, будет сброшен flush() внутри read().
        Thread.sleep(forTimeInterval: settleDelay)

        let readBack = command.readGroup != nil ? try read(command) : nil

        return MozaWriteResult(
            command: command,
            request: request,
            requestedHuman: value,
            requestedWire: wire,
            readBack: readBack
        )
    }

    public func write(_ name: String, human value: Int) throws -> MozaWriteResult {
        guard let command = MozaSettings.command(named: name) else {
            throw DeviceError.commandUnknown(name)
        }
        return try write(command, human: value)
    }

    /// Угол поворота руля. Пишется парой `limit` + `max-angle` — так же делает boxflat,
    /// и только тогда база применяет новый предел.
    public func setRotationAngle(degrees: Int) throws -> [MozaWriteResult] {
        var results: [MozaWriteResult] = []
        for name in ["limit", "max-angle"] {
            guard let command = MozaSettings.command(named: name) else {
                throw DeviceError.commandUnknown(name)
            }
            results.append(try write(command, human: degrees))
            Thread.sleep(forTimeInterval: 0.02)
        }
        return results
    }

    /// Текущий угол поворота: пара значений, которые должны совпадать.
    public func rotationAngle() throws -> (limit: Int, maxAngle: Int) {
        let limit = try read("limit")
        let maxAngle = try read("max-angle")
        return (limit.humanValue, maxAngle.humanValue)
    }

    /// Калибровка центра руля. Команда только на запись — сверить чтением нечего,
    /// проверяется физически по положению оси руля.
    public func calibrateCenter() throws -> MozaWriteResult {
        guard let command = MozaSettings.command(named: "calibration") else {
            throw DeviceError.commandUnknown("calibration")
        }
        return try write(command, human: 1)
    }

    // MARK: - Приём кадра

    private func awaitFrame(
        group: UInt8,
        command: MozaCommand,
        collecting unexpected: inout [[UInt8]]
    ) throws -> MozaFrame? {
        var buffer: [UInt8] = []
        var firstByteAt: Date?
        let deadline = Date().addingTimeInterval(responseTimeout)

        while Date() < deadline {
            let chunk = try port.readAvailable(timeoutMs: 20)
            if !chunk.isEmpty {
                if firstByteAt == nil { firstByteAt = Date() }
                buffer.append(contentsOf: chunk)
            }

            // Пока не истекла отсрочка, ждём возможный байт checksum за кадром.
            let allowMissingChecksum = firstByteAt.map {
                Date().timeIntervalSince($0) > checksumGrace
            } ?? false

            while let frame = MozaPacket.nextFrame(from: &buffer, allowMissingChecksum: allowMissingChecksum) {
                if isExpected(frame, group: group, command: command) {
                    return frame
                }
                unexpected.append(frame.bytes)
            }
        }

        if !buffer.isEmpty {
            unexpected.append(buffer)
        }
        return nil
    }

    private func isExpected(_ frame: MozaFrame, group: UInt8, command: MozaCommand) -> Bool {
        frame.requestGroup == group
            && frame.requestDevice == MozaSettings.baseDeviceID
            && frame.matches(id: command.id)
    }

    static func bigEndian(_ value: Int, byteCount: Int) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        var remaining = value
        for index in stride(from: byteCount - 1, through: 0, by: -1) {
            bytes[index] = UInt8(remaining & 0xFF)
            remaining >>= 8
        }
        return bytes
    }
}
