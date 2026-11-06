import Foundation

/// Одна команда протокола: адрес (group + id), размер значения и масштаб.
///
/// Таблица ниже — **единственный** источник истины. Ничего, кроме перечисленных
/// здесь group/id, в устройство не отправляется: перебор неизвестных команд по живому
/// железу недопустим (в известной таблице нет команд прошивки/EEPROM/сброса, значит
/// всё за её пределами — неисследованная территория).
public struct MozaCommand {
    /// Группа для чтения; `nil` — команда только на запись.
    public let readGroup: UInt8?
    /// Группа для записи; `nil` — команда только на чтение.
    public let writeGroup: UInt8?
    public let name: String
    public let id: [UInt8]
    public let byteCount: Int

    /// Значение на проводе = человеческое * scaleNumerator / scaleDenominator.
    ///
    /// Угол: 1080° → 540 (`1/2`). Сила FFB: 70 % → 700 (`10/1`).
    public let scaleNumerator: Int
    public let scaleDenominator: Int

    public let unit: String
    /// Допустимый диапазон в человеческих единицах (для валидации записи).
    public let humanRange: ClosedRange<Int>?
    /// Сколько знаков после запятой показывать (температуры приходят в сотых долях).
    public let decimalPlaces: Int
    public let note: String

    init(
        name: String,
        readGroup: UInt8?,
        writeGroup: UInt8?,
        id: [UInt8],
        byteCount: Int = 2,
        scaleNumerator: Int = 1,
        scaleDenominator: Int = 1,
        unit: String = "",
        humanRange: ClosedRange<Int>? = nil,
        decimalPlaces: Int = 0,
        note: String = ""
    ) {
        self.name = name
        self.readGroup = readGroup
        self.writeGroup = writeGroup
        self.id = id
        self.byteCount = byteCount
        self.scaleNumerator = scaleNumerator
        self.scaleDenominator = scaleDenominator
        self.unit = unit
        self.humanRange = humanRange
        self.decimalPlaces = decimalPlaces
        self.note = note
    }

    public func human(fromWire wire: Int) -> Int {
        wire * scaleDenominator / scaleNumerator
    }

    public func wire(fromHuman human: Int) -> Int {
        human * scaleNumerator / scaleDenominator
    }

    /// Значение с единицей измерения по правилам вывода: `900°`, `100 %`, `36.00 °C`.
    public static func format(_ value: Int, unit: String) -> String {
        switch unit {
        case "": return "\(value)"
        case "°": return "\(value)°"
        default: return "\(value) \(unit)"
        }
    }

    /// Человеческое значение с единицей измерения, готовое к выводу.
    public func humanText(fromWire wire: Int) -> String {
        let number: String
        if decimalPlaces > 0 {
            let value = Double(wire) * Double(scaleDenominator) / Double(scaleNumerator)
            number = String(format: "%.\(decimalPlaces)f", value)
        } else {
            number = "\(human(fromWire: wire))"
        }

        switch unit {
        case "": return number
        case "°": return number + unit          // 900°
        default: return number + " " + unit     // 36.00 °C, 100 %
        }
    }

    public var isScaled: Bool { scaleNumerator != 1 || scaleDenominator != 1 }
}

public enum MozaSettings {
    /// device_id базы руля.
    public static let baseDeviceID: UInt8 = 0x13

    static let readGroupBase: UInt8 = 40        // 0x28 — настройки
    static let writeGroupBase: UInt8 = 41       // 0x29
    static let writeGroupAction: UInt8 = 42     // 0x2A — калибровка и прочие действия
    static let readGroupTelemetry: UInt8 = 43   // 0x2B — только чтение

    /// Настройки, которые нужны для минимального аналога Pit House,
    /// плюс безопасная телеметрия для сверки разбора протокола.
    public static let all: [MozaCommand] = [
        MozaCommand(
            name: "max-angle",
            readGroup: readGroupBase, writeGroup: writeGroupBase,
            id: [23], scaleNumerator: 1, scaleDenominator: 2,
            unit: "°", humanRange: 90...2700,
            note: "угол поворота руля; на провод уходит половина градусов"
        ),
        MozaCommand(
            name: "limit",
            readGroup: readGroupBase, writeGroup: writeGroupBase,
            id: [1], scaleNumerator: 1, scaleDenominator: 2,
            unit: "°", humanRange: 90...2700,
            note: "пишется в паре с max-angle тем же значением"
        ),
        MozaCommand(
            name: "ffb-strength",
            readGroup: readGroupBase, writeGroup: writeGroupBase,
            id: [2], scaleNumerator: 10, scaleDenominator: 1,
            unit: "%", humanRange: 0...100,
            note: "общая сила отдачи; на провод уходит percent * 10"
        ),
        MozaCommand(
            name: "torque",
            readGroup: readGroupBase, writeGroup: writeGroupBase,
            id: [18], unit: "%", humanRange: 50...100,
            note: "аппаратный лимит момента базы"
        ),
        // Настройки, формирующие отдачу. Масштаб и диапазон этих значений НЕ
        // подтверждены: на живой базе прочитались damper 420, friction 150,
        // inertia 4000 — то есть это не проценты. Поэтому единицы и диапазоны
        // не указаны, а запись доступна только «как есть», без пересчёта.
        MozaCommand(
            name: "ffb-disable",
            readGroup: readGroupBase, writeGroup: writeGroupBase,
            id: [254], humanRange: 0...1,
            note: "1 — отдача полностью отключена на базе"
        ),
        MozaCommand(
            name: "damper", readGroup: readGroupBase, writeGroup: writeGroupBase,
            id: [7], note: "масштаб не подтверждён: демпфирование"
        ),
        MozaCommand(
            name: "friction", readGroup: readGroupBase, writeGroup: writeGroupBase,
            id: [8], note: "масштаб не подтверждён: трение"
        ),
        MozaCommand(
            name: "spring", readGroup: readGroupBase, writeGroup: writeGroupBase,
            id: [9], note: "масштаб не подтверждён: возврат к центру"
        ),
        MozaCommand(
            name: "inertia", readGroup: readGroupBase, writeGroup: writeGroupBase,
            id: [4], note: "масштаб не подтверждён: инерция"
        ),
        MozaCommand(
            name: "road-sensitivity", readGroup: readGroupBase, writeGroup: writeGroupBase,
            id: [12], note: "масштаб не подтверждён: детализация дороги"
        ),
        MozaCommand(
            name: "ffb-reverse",
            readGroup: readGroupBase, writeGroup: writeGroupBase,
            id: [24], humanRange: 0...1,
            note: "инверсия направления отдачи"
        ),
        // Группа 43 — только чтение, write-группы у этих команд не существует.
        MozaCommand(name: "state", readGroup: readGroupTelemetry, writeGroup: nil, id: [1],
                    note: "код состояния базы (семантика неизвестна)"),
        MozaCommand(name: "state-err", readGroup: readGroupTelemetry, writeGroup: nil, id: [2],
                    note: "код ошибки, 0 — ошибок нет"),
        // Температуры приходят в сотых долях градуса: 3600 = 36,00 °C.
        MozaCommand(name: "mcu-temp", readGroup: readGroupTelemetry, writeGroup: nil, id: [4],
                    scaleNumerator: 100, unit: "°C", humanRange: 0...120, decimalPlaces: 2,
                    note: "температура микроконтроллера"),
        MozaCommand(name: "mosfet-temp", readGroup: readGroupTelemetry, writeGroup: nil, id: [5],
                    scaleNumerator: 100, unit: "°C", humanRange: 0...120, decimalPlaces: 2,
                    note: "температура силовых транзисторов"),
        MozaCommand(name: "motor-temp", readGroup: readGroupTelemetry, writeGroup: nil, id: [6],
                    scaleNumerator: 100, unit: "°C", humanRange: 0...120, decimalPlaces: 2,
                    note: "температура двигателя"),
        // Только запись. На этапе «только чтение» запись в коде не реализована —
        // запись появится отдельным шагом, после подтверждения разбора протокола.
        MozaCommand(
            name: "calibration",
            readGroup: nil, writeGroup: writeGroupAction,
            id: [1], note: "калибровка центра, значение 1"
        ),
    ]

    public static func command(named name: String) -> MozaCommand? {
        all.first { $0.name == name }
    }

    /// Всё, что можно прочитать — набор для сверки разбора протокола.
    public static var readable: [MozaCommand] {
        all.filter { $0.readGroup != nil }
    }
}
