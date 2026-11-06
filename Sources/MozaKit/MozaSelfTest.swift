import Foundation

/// Офлайн-проверка кадрирования на эталонных байтах.
///
/// Смысл: поймать ошибку в реализации протокола **до** обращения к железу.
/// Эталоны взяты из разбора boxflat, контрольные суммы пересчитаны вручную.
/// Ничего никуда не отправляется.
public enum MozaSelfTest {
    public struct Check {
        public let name: String
        public let passed: Bool
        public let detail: String
    }

    /// Эталонные кадры: (описание, group, id, значение на проводе, ожидаемые байты).
    static let vectors: [(label: String, group: UInt8, id: [UInt8], wire: Int, bytes: [UInt8])] = [
        ("read limit",        0x28, [1],  1, [0x7E, 0x03, 0x28, 0x13, 0x01, 0x00, 0x01, 0xCB]),
        ("read ffb-strength", 0x28, [2],  1, [0x7E, 0x03, 0x28, 0x13, 0x02, 0x00, 0x01, 0xCC]),
        ("read torque",       0x28, [18], 1, [0x7E, 0x03, 0x28, 0x13, 0x12, 0x00, 0x01, 0xDC]),
        ("read max-angle",    0x28, [23], 1, [0x7E, 0x03, 0x28, 0x13, 0x17, 0x00, 0x01, 0xE1]),
        ("read ffb-reverse",  0x28, [24], 1, [0x7E, 0x03, 0x28, 0x13, 0x18, 0x00, 0x01, 0xE2]),
        ("read motor-temp",   0x2B, [6],  1, [0x7E, 0x03, 0x2B, 0x13, 0x06, 0x00, 0x01, 0xD3]),
        // Кадры записи проверяем только арифметически: на этапе «только чтение»
        // они никуда не отправляются, но кодировщик у чтения и записи общий.
        ("write max-angle 1080°", 0x29, [23], 540, [0x7E, 0x03, 0x29, 0x13, 0x17, 0x02, 0x1C, 0xFF]),
        ("write calibration",     0x2A, [1],    1, [0x7E, 0x03, 0x2A, 0x13, 0x01, 0x00, 0x01, 0xCD]),
    ]

    public static func run() -> [Check] {
        var checks: [Check] = []

        // 1. Кодирование кадров совпадает с эталонами байт в байт.
        for vector in vectors {
            let encoded = MozaPacket.encode(
                group: vector.group,
                device: MozaSettings.baseDeviceID,
                id: vector.id,
                payload: MozaDevice.bigEndian(vector.wire, byteCount: 2)
            )
            checks.append(Check(
                name: "кадр: \(vector.label)",
                passed: encoded == vector.bytes,
                detail: encoded == vector.bytes
                    ? encoded.hexDump
                    : "получено \(encoded.hexDump), ожидалось \(vector.bytes.hexDump)"
            ))
        }

        // 2. Масштабирование значений в обе стороны.
        checks.append(contentsOf: scaleChecks())

        // 3. Разбор ответа с байтом checksum.
        //    7E 03 A8 31 17 02 1C + checksum(=0x9C): max-angle = 540 на проводе.
        var withChecksum: [UInt8] = [0x7E, 0x03, 0xA8, 0x31, 0x17, 0x02, 0x1C]
        withChecksum.append(MozaPacket.checksum(over: withChecksum))
        checks.append(parseCheck(
            name: "разбор ответа (checksum присутствует)",
            buffer: withChecksum,
            expectedWire: 540,
            expectedChecksumMatches: true
        ))

        // 4. Разбор ответа без байта checksum — вторая допустимая гипотеза.
        checks.append(parseCheck(
            name: "разбор ответа (checksum отсутствует)",
            buffer: [0x7E, 0x03, 0xA8, 0x31, 0x17, 0x02, 0x1C],
            expectedWire: 540,
            expectedChecksumMatches: nil
        ))

        // 5. Ресинк: мусор перед кадром отбрасывается.
        checks.append(parseCheck(
            name: "ресинк после мусора в потоке",
            buffer: [0x00, 0xFF, 0x42] + withChecksum,
            expectedWire: 540,
            expectedChecksumMatches: true
        ))

        // 6. Неполный кадр не разбирается, а ждёт данных.
        var partial: [UInt8] = [0x7E, 0x03, 0xA8, 0x31, 0x17]
        let partialFrame = MozaPacket.nextFrame(from: &partial, allowMissingChecksum: true)
        checks.append(Check(
            name: "неполный кадр не разбирается",
            passed: partialFrame == nil,
            detail: partialFrame == nil ? "ожидает данных" : "разобран преждевременно"
        ))

        // 7. Ложный стартовый байт с недопустимым length отбрасывается.
        var falseStart: [UInt8] = [0x7E, 0xFF] + withChecksum
        let recovered = MozaPacket.nextFrame(from: &falseStart, allowMissingChecksum: true)
        let recoveredOK = recovered?.value(idLength: 1, byteCount: 2) == 540
        checks.append(Check(
            name: "ложный стартовый байт отбрасывается",
            passed: recoveredOK,
            detail: recoveredOK ? "кадр найден за ложным стартом" : "кадр потерян"
        ))

        // 8. Таблица команд непротиворечива.
        checks.append(contentsOf: tableChecks())

        return checks
    }

    private static func scaleChecks() -> [Check] {
        var checks: [Check] = []

        if let angle = MozaSettings.command(named: "max-angle") {
            let wire = angle.wire(fromHuman: 1080)
            let human = angle.human(fromWire: 540)
            checks.append(Check(
                name: "масштаб max-angle (1080° ↔ 540)",
                passed: wire == 540 && human == 1080,
                detail: "1080° → \(wire), 540 → \(human)°"
            ))
        }

        if let ffb = MozaSettings.command(named: "ffb-strength") {
            let wire = ffb.wire(fromHuman: 70)
            let human = ffb.human(fromWire: 700)
            checks.append(Check(
                name: "масштаб ffb-strength (70 % ↔ 700)",
                passed: wire == 700 && human == 70,
                detail: "70 % → \(wire), 700 → \(human) %"
            ))
        }

        if let torque = MozaSettings.command(named: "torque") {
            let wire = torque.wire(fromHuman: 85)
            checks.append(Check(
                name: "масштаб torque (без пересчёта)",
                passed: wire == 85 && torque.human(fromWire: 85) == 85,
                detail: "85 % → \(wire)"
            ))
        }

        return checks
    }

    private static func tableChecks() -> [Check] {
        var checks: [Check] = []

        let names = MozaSettings.all.map(\.name)
        checks.append(Check(
            name: "имена команд уникальны",
            passed: Set(names).count == names.count,
            detail: "\(names.count) команд"
        ))

        let telemetry = MozaSettings.all.filter { $0.readGroup == MozaSettings.readGroupTelemetry }
        checks.append(Check(
            name: "телеметрия (группа 43) недоступна для записи",
            passed: telemetry.allSatisfy { $0.writeGroup == nil } && !telemetry.isEmpty,
            detail: "\(telemetry.count) команд только на чтение"
        ))

        let readableAddresses = MozaSettings.all.compactMap { command -> String? in
            guard let group = command.readGroup else { return nil }
            return "\(group)/\(command.id)"
        }
        checks.append(Check(
            name: "адреса чтения не пересекаются",
            passed: Set(readableAddresses).count == readableAddresses.count,
            detail: "\(readableAddresses.count) читаемых команд"
        ))

        return checks
    }

    private static func parseCheck(
        name: String,
        buffer: [UInt8],
        expectedWire: Int,
        expectedChecksumMatches: Bool?
    ) -> Check {
        var working = buffer
        guard let frame = MozaPacket.nextFrame(from: &working, allowMissingChecksum: true) else {
            return Check(name: name, passed: false, detail: "кадр не разобран")
        }

        let wire = frame.value(idLength: 1, byteCount: 2)
        let groupOK = frame.requestGroup == 0x28
        let deviceOK = frame.requestDevice == MozaSettings.baseDeviceID
        let checksumOK = frame.checksumMatches == expectedChecksumMatches
        let passed = wire == expectedWire && groupOK && deviceOK && checksumOK

        let checksumText: String
        switch frame.checksumMatches {
        case .some(true): checksumText = "checksum совпал"
        case .some(false): checksumText = "checksum НЕ совпал"
        case .none: checksumText = "checksum отсутствует"
        }

        return Check(
            name: name,
            passed: passed,
            detail: "group=\(frame.requestGroup), device=0x\(String(format: "%02X", frame.requestDevice)), "
                + "значение=\(wire.map(String.init) ?? "нет"), \(checksumText)"
        )
    }
}
