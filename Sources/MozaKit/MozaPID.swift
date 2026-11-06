import Foundation
import IOKit
import IOKit.hid

/// Управление отдачей напрямую через стандартные HID PID-репорты базы.
///
/// Подсистема Force Feedback самой macOS с этой базой не работает (плагин
/// ForceFeedback устройству не сопоставлен), но база объявляет полноценный
/// PID-блок, а output-репорты можно писать через IOHIDDevice без всяких
/// разрешений. Раскладка репортов взята из разбора HID-дескриптора устройства.
public final class MozaPID {
    public enum PIDError: Error, CustomStringConvertible {
        case deviceNotFound
        case openFailed(IOReturn)
        case reportFailed(name: String, code: IOReturn)
        case effectNotAllocated(status: UInt8)

        public var description: String {
            switch self {
            case .deviceNotFound:
                return "HID-интерфейс MOZA не найден"
            case let .openFailed(code):
                return "не удалось открыть HID-устройство (0x\(String(format: "%08X", UInt32(bitPattern: code))))"
            case let .reportFailed(name, code):
                return "репорт «\(name)» не принят (0x\(String(format: "%08X", UInt32(bitPattern: code))))"
            case let .effectNotAllocated(status):
                let meaning: String
                switch status {
                case 2: meaning = "память эффектов заполнена"
                case 3: meaning = "ошибка загрузки блока"
                default: meaning = "код \(status)"
                }
                return "база не выделила блок под эффект: \(meaning)"
            }
        }
    }

    // Идентификаторы репортов (из дескриптора устройства).
    private enum Report {
        static let setEffect: CFIndex = 1
        static let setConstantForce: CFIndex = 5
        static let effectOperation: CFIndex = 10
        static let blockFree: CFIndex = 11
        static let deviceControl: CFIndex = 12
        static let deviceGain: CFIndex = 13
        static let createNewEffect: CFIndex = 17   // feature
        static let blockLoad: CFIndex = 18         // feature
        static let pool: CFIndex = 19              // feature
        static let pidState: CFIndex = 2           // input
    }

    /// Тип эффекта в массиве Effect Type репортов 1 и 17.
    public enum EffectType: UInt8 {
        case constantForce = 1
        case ramp = 2
        case square = 3
        case sine = 4
        case triangle = 5
        case sawtoothUp = 6
        case sawtoothDown = 7
        case spring = 8
        case damper = 9
        case inertia = 10
        case friction = 11
    }

    /// Байт Device Control. Для «включить» и «выключить» побитовая и массивная
    /// трактовки дескриптора совпадают (0x01 и 0x02), поэтому они однозначны.
    private enum DeviceControl: UInt8 {
        case enableActuators = 0x01
        case disableActuators = 0x02
    }

    private enum Operation: UInt8 {
        case start = 1
        case startSolo = 2
        case stop = 3
    }

    public static let magnitudeMax = 32767

    private var device: IOHIDDevice?
    public var verbose: Bool

    public init(verbose: Bool = false) {
        self.verbose = verbose
    }

    deinit { close() }

    // MARK: - Открытие устройства

    public func open() throws {
        guard let matching = IOServiceMatching("IOHIDDevice") else { throw PIDError.deviceNotFound }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            throw PIDError.deviceNotFound
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            guard let vendor = property(service, "VendorID") as? Int, vendor == MozaDiscovery.vendorID,
                  let usagePage = property(service, "PrimaryUsagePage") as? Int, usagePage == 1
            else { continue }

            guard let candidate = IOHIDDeviceCreate(kCFAllocatorDefault, service) else { continue }
            let status = IOHIDDeviceOpen(candidate, IOOptionBits(kIOHIDOptionsTypeNone))
            guard status == kIOReturnSuccess else { throw PIDError.openFailed(status) }
            device = candidate
            return
        }

        throw PIDError.deviceNotFound
    }

    public func close() {
        if let device {
            IOHIDDeviceClose(device, IOOptionBits(kIOHIDOptionsTypeNone))
            self.device = nil
        }
    }

    // MARK: - Отдельные команды PID

    public func setDeviceGain(_ gain: Int) throws {
        let value = UInt8(max(0, min(255, gain)))
        try send(.output, Report.deviceGain, [value], name: "Device Gain")
    }

    public func enableActuators() throws {
        try send(.output, Report.deviceControl, [DeviceControl.enableActuators.rawValue],
                 name: "Device Control: включить приводы")
    }

    public func disableActuators() throws {
        try send(.output, Report.deviceControl, [DeviceControl.disableActuators.rawValue],
                 name: "Device Control: выключить приводы")
    }

    /// Инициализация PID-движка ровно как в рабочем драйвере Linux
    /// (`pidff_reset`): сброс дважды, остановка всех эффектов, включение
    /// приводов. Дескриптор объявляет поле Device Control как набор бит,
    /// поэтому команды задаются битовой маской.
    public func reset() throws {
        try sendDeviceControl(raw: 0x08, name: "сброс")
        try sendDeviceControl(raw: 0x08, name: "сброс (повторно)")
        try sendDeviceControl(raw: 0x04, name: "остановить все эффекты")
        try sendDeviceControl(raw: 0x01, name: "включить приводы")
    }

    /// Попросить базу выделить блок под эффект и вернуть его индекс.
    public func createEffect(_ type: EffectType) throws -> UInt8 {
        try send(.feature, Report.createNewEffect, [type.rawValue], name: "Create New Effect")

        // Block Load (данные без байта report ID):
        // [0] Effect Block Index, [1] статус (1 — успех), [2…3] свободная память.
        let response = try receive(.feature, Report.blockLoad, length: 8, name: "Block Load")
        guard response.count >= 2 else {
            throw PIDError.effectNotAllocated(status: 0)
        }
        let index = response[0]
        let status = response[1]

        guard status == 1, index >= 1 else {
            throw PIDError.effectNotAllocated(status: status)
        }
        return index
    }

    /// Параметры эффекта. Раскладка репорта 1 (21 байт данных), проверена по
    /// дескриптору с правильными usage-кодами PID:
    ///
    /// ```
    ///  0     индекс блока эффекта
    ///  1     тип эффекта (массив)
    ///  2…3   Duration, мс
    ///  4…5   Trigger Repeat Interval
    ///  6…7   Sample Period
    ///  8…9   Start Delay
    /// 10     Gain 0…255          ← ноль здесь означает «без силы»
    /// 11     Trigger Button 0 — без привязки к кнопке
    /// 12     бит0 ось X, бит1 ось Y, бит2 Direction Enable
    /// 13…16  Direction по X и Y, сотые доли градуса (0…36000)
    /// 17…20  Type Specific Block Offset
    /// ```
    public func setEffect(
        index: UInt8,
        type: EffectType,
        durationMilliseconds: Int,
        gain: Int = 255,
        triggerButton: UInt8 = 0,
        enableAxisX: Bool = false,
        directionEnable: Bool = true,
        directionCentiDegrees: Int = 9000
    ) throws {
        var payload = [UInt8](repeating: 0, count: 21)
        payload[0] = index
        payload[1] = type.rawValue
        writeLittleEndian(&payload, offset: 2, value: durationMilliseconds, byteCount: 2)
        payload[10] = UInt8(max(0, min(255, gain)))
        payload[11] = triggerButton
        payload[12] = (enableAxisX ? 0x01 : 0) | (directionEnable ? 0x04 : 0)
        writeLittleEndian(&payload, offset: 13, value: directionCentiDegrees, byteCount: 2)
        try send(.output, Report.setEffect, payload, name: "Set Effect")
    }

    /// Величина постоянной силы: −32768…32767, знак задаёт сторону.
    public func setConstantForce(index: UInt8, magnitude: Int) throws {
        let clamped = max(-32768, min(MozaPID.magnitudeMax, magnitude))
        var payload = [UInt8](repeating: 0, count: 3)
        payload[0] = index
        writeLittleEndian(&payload, offset: 1, value: clamped, byteCount: 2)
        try send(.output, Report.setConstantForce, payload, name: "Set Constant Force")
    }

    public func startEffect(index: UInt8, loops: Int = 1) throws {
        try send(.output, Report.effectOperation,
                 [index, Operation.start.rawValue, UInt8(max(1, min(255, loops)))],
                 name: "Effect Operation: старт")
    }

    public func stopEffect(index: UInt8) throws {
        try send(.output, Report.effectOperation, [index, Operation.stop.rawValue, 0],
                 name: "Effect Operation: стоп")
    }

    public func freeEffect(index: UInt8) throws {
        try send(.output, Report.blockFree, [index], name: "Block Free")
    }

    /// Сырой байт PID Device Control — для перебора трактовок дескриптора
    /// (массив значений 1…6 против битовой маски).
    public func sendDeviceControl(raw: UInt8, name: String) throws {
        try send(.output, Report.deviceControl, [raw], name: "Device Control: \(name)")
    }

    /// Сырая операция над эффектом: 1 — старт, 2 — старт солo, 3 — стоп.
    public func sendEffectOperation(index: UInt8, operation: UInt8, loops: UInt8) throws {
        try send(.output, Report.effectOperation, [index, operation, loops],
                 name: "Effect Operation: операция \(operation)")
    }

    /// Освободить все блоки эффектов. Нужно после прерванного сеанса: занятый
    /// блок остаётся выделенным, и база начинает выдавать следующие индексы.
    /// Ошибки по незанятым блокам игнорируются — это норма.
    public func freeAllEffects() {
        for index in UInt8(1)...UInt8(10) {
            try? freeEffect(index: index)
        }
    }

    /// Что база сообщает о своих приводах (входной репорт 2).
    /// Раскладка: [0] индекс эффекта, [1] биты — пауза, приводы включены,
    /// защитный выключатель, принудительное включение, эффект играет.
    public struct State {
        public let effectIndex: UInt8
        public let devicePaused: Bool
        public let actuatorsEnabled: Bool
        public let safetySwitch: Bool
        public let actuatorOverride: Bool
        public let effectPlaying: Bool
    }

    public func state() throws -> State {
        let response = try receive(.input, Report.pidState, length: 8, name: "PID State")
        guard response.count >= 2 else { throw PIDError.reportFailed(name: "PID State", code: 0) }
        let bits = response[1]
        return State(
            effectIndex: response[0],
            devicePaused: bits & 0x01 != 0,
            actuatorsEnabled: bits & 0x02 != 0,
            safetySwitch: bits & 0x04 != 0,
            actuatorOverride: bits & 0x08 != 0,
            effectPlaying: bits & 0x10 != 0
        )
    }

    /// Параметры пула эффектов (feature-репорт 19), данные без байта report ID:
    /// [0…1] размер памяти, [2] максимум одновременных эффектов,
    /// [3] бит 0 — питание привода, бит 1 — принудительное включение.
    public func pool() throws -> (ramPoolSize: Int, simultaneousEffects: Int, actuatorPower: Bool?) {
        let response = try receive(.feature, Report.pool, length: 8, name: "PID Pool")
        let size = response.count > 1 ? Int(response[0]) | (Int(response[1]) << 8) : 0
        let simultaneous = response.count > 2 ? Int(response[2]) : 0
        let power = response.count > 3 ? (response[3] & 0x01) != 0 : nil
        return (size, simultaneous, power)
    }

    // MARK: - Транспорт

    private enum ReportKind {
        case output, feature, input

        var iokit: IOHIDReportType {
            switch self {
            case .output: return kIOHIDReportTypeOutput
            case .feature: return kIOHIDReportTypeFeature
            case .input: return kIOHIDReportTypeInput
            }
        }
    }

    private func send(_ kind: ReportKind, _ reportID: CFIndex, _ payload: [UInt8], name: String) throws {
        guard let device else { throw PIDError.deviceNotFound }

        if verbose {
            let prefix = kind == .feature ? "feature" : (kind == .input ? "input" : "output")
            FileHandle.standardError.write(
                Data("→ \(prefix) \(reportID) \(name): \(([UInt8(reportID)] + payload).hexDump)\n".utf8)
            )
        }

        // На macOS буфер должен НАЧИНАТЬСЯ с байта report ID (так же поступает
        // hidapi). Для output-репортов это критично: они уходят в interrupt OUT,
        // где первый байт пакета и есть идентификатор репорта, — без него
        // прошивка разбирает пакет как совсем другой репорт и молча его теряет.
        let framed = [UInt8(reportID)] + payload
        let status = framed.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(device, kind.iokit, reportID, buffer.baseAddress!, framed.count)
        }
        guard status == kIOReturnSuccess else {
            throw PIDError.reportFailed(name: name, code: status)
        }
    }

    private func receive(_ kind: ReportKind, _ reportID: CFIndex, length: Int, name: String) throws -> [UInt8] {
        guard let device else { throw PIDError.deviceNotFound }

        var buffer = [UInt8](repeating: 0, count: length)
        var actual = CFIndex(length)
        let status = buffer.withUnsafeMutableBufferPointer { pointer in
            IOHIDDeviceGetReport(device, kind.iokit, reportID, pointer.baseAddress!, &actual)
        }
        guard status == kIOReturnSuccess else {
            throw PIDError.reportFailed(name: name, code: status)
        }

        var result = Array(buffer[0..<max(0, min(length, Int(actual)))])
        if verbose {
            FileHandle.standardError.write(Data("← \(kind == .input ? "input" : "feature") \(reportID) \(name): \(result.hexDump)\n".utf8))
        }
        // Ответ приходит с байтом report ID в начале — снимаем его, чтобы
        // смещения совпадали с раскладкой полей из дескриптора.
        if let first = result.first, CFIndex(first) == reportID {
            result.removeFirst()
        }
        return result
    }

    private func writeLittleEndian(_ buffer: inout [UInt8], offset: Int, value: Int, byteCount: Int) {
        let unsigned = UInt32(bitPattern: Int32(value))
        for byte in 0..<byteCount {
            buffer[offset + byte] = UInt8((unsigned >> (8 * UInt32(byte))) & 0xFF)
        }
    }

    private func property(_ entry: io_registry_entry_t, _ key: String) -> Any? {
        guard let reference = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return reference.takeRetainedValue()
    }
}
