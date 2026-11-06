import Foundation
import IOKit
import IOKit.hid

/// Чтение осей и кнопок через IOHIDManager.
///
/// Устройство уже обслуживается macOS как штатный джойстик — здесь мы лишь
/// подписываемся на те же события, чтобы видеть, что происходит с рулём.
/// Настройки через HID **не** передаются: для них есть serial-канал.
public final class MozaHIDInput {
    public enum HIDError: Error, CustomStringConvertible {
        case managerUnavailable
        case deviceNotFound
        case openFailed(IOReturn)

        public var description: String {
            switch self {
            case .managerUnavailable:
                return "не удалось создать IOHIDManager"
            case .deviceNotFound:
                return "HID-интерфейс MOZA не найден"
            case let .openFailed(code):
                let hint = (code == kIOReturnNotPermitted || code == kIOReturnNotPrivileged)
                    ? " — разрешите доступ в «Системные настройки → Конфиденциальность и безопасность → Мониторинг ввода»"
                    : ""
                return "не удалось открыть HID-устройство (код 0x\(String(format: "%08X", UInt32(bitPattern: code))))\(hint)"
            }
        }
    }

    public struct AxisState {
        public let usage: UInt32
        public let value: Int
        public let logicalMin: Int
        public let logicalMax: Int

        public var name: String { MozaHIDInput.axisName(usage: usage) }

        /// Положение в диапазоне −1…+1 относительно середины шкалы.
        public var normalized: Double {
            let span = Double(logicalMax - logicalMin)
            guard span > 0 else { return 0 }
            return (Double(value - logicalMin) / span) * 2 - 1
        }
    }

    private var manager: IOHIDManager?
    private let lock = NSLock()
    private var axisStates: [UInt32: AxisState] = [:]
    private var pressedButtons: Set<UInt32> = []
    private var eventCount = 0

    public init() {}

    deinit { stop() }

    public func start(productID: Int? = nil) throws {
        let manager = IOHIDManagerCreate(kCFAllocatorDefault, IOOptionBits(kIOHIDOptionsTypeNone))

        var matching: [String: Any] = [kIOHIDVendorIDKey: MozaDiscovery.vendorID]
        if let productID { matching[kIOHIDProductIDKey] = productID }
        IOHIDManagerSetDeviceMatching(manager, matching as CFDictionary)

        let status = IOHIDManagerOpen(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        guard status == kIOReturnSuccess else { throw HIDError.openFailed(status) }

        guard let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice>, !devices.isEmpty else {
            IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
            throw HIDError.deviceNotFound
        }

        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterInputValueCallback(manager, MozaHIDInput.inputCallback, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)

        self.manager = manager
        // Seed all axes/buttons: unchanged pedals may never generate a callback.
        for device in devices {
            guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement] else { continue }
            for element in elements {
                let page = IOHIDElementGetUsagePage(element)
                guard page == 1 || page == 9 else { continue }
                guard IOHIDElementGetType(element).rawValue <= kIOHIDElementTypeInput_ScanCodes.rawValue else { continue }
                withUnsafeTemporaryAllocation(of: Unmanaged<IOHIDValue>.self, capacity: 1) { value in
                    if IOHIDDeviceGetValue(device, element, value.baseAddress!) == kIOReturnSuccess {
                        handle(value[0].takeUnretainedValue())
                    }
                }
            }
        }
    }

    public func isConnected() -> Bool {
        guard let manager, let devices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else { return false }
        return !devices.isEmpty
    }

    public func stop() {
        guard let manager else { return }
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetCurrent(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, IOOptionBits(kIOHIDOptionsTypeNone))
        self.manager = nil
    }

    /// Оси, по которым приходили события, в порядке usage.
    public func axes() -> [AxisState] {
        lock.lock(); defer { lock.unlock() }
        return axisStates.values.sorted { $0.usage < $1.usage }
    }

    public func buttons() -> [Int] {
        lock.lock(); defer { lock.unlock() }
        return pressedButtons.map(Int.init).sorted()
    }

    public func receivedEvents() -> Int {
        lock.lock(); defer { lock.unlock() }
        return eventCount
    }

    /// Ось руля (Generic Desktop / X).
    public func steering() -> AxisState? {
        lock.lock(); defer { lock.unlock() }
        return axisStates[UInt32(kHIDUsage_GD_X)]
    }

    // MARK: - Приём событий

    private static let inputCallback: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        Unmanaged<MozaHIDInput>.fromOpaque(context).takeUnretainedValue().handle(value)
    }

    private func handle(_ value: IOHIDValue) {
        let element = IOHIDValueGetElement(value)
        let usagePage = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let integerValue = IOHIDValueGetIntegerValue(value)

        lock.lock()
        defer { lock.unlock() }
        eventCount += 1

        switch Int(usagePage) {
        case kHIDPage_GenericDesktop:
            axisStates[usage] = AxisState(
                usage: usage,
                value: Int(integerValue),
                logicalMin: Int(IOHIDElementGetLogicalMin(element)),
                logicalMax: Int(IOHIDElementGetLogicalMax(element))
            )
        case kHIDPage_Button:
            if integerValue != 0 {
                pressedButtons.insert(usage)
            } else {
                pressedButtons.remove(usage)
            }
        default:
            break
        }
    }

    static func axisName(usage: UInt32) -> String {
        switch Int(usage) {
        case kHIDUsage_GD_X: return "X (руль)"
        case kHIDUsage_GD_Y: return "Y"
        case kHIDUsage_GD_Z: return "Z (газ)"
        case kHIDUsage_GD_Rx: return "Rx"
        case kHIDUsage_GD_Ry: return "Ry"
        case kHIDUsage_GD_Rz: return "Rz (тормоз)"
        case kHIDUsage_GD_Slider: return "Slider"
        case kHIDUsage_GD_Dial: return "Dial"
        case kHIDUsage_GD_Hatswitch: return "Hat"
        default: return String(format: "usage 0x%02X", usage)
        }
    }
}
