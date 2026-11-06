import Foundation
import ForceFeedback
import IOKit
import IOKit.hid

/// Что подсистема Force Feedback macOS думает об устройстве.
public struct ForceFeedbackProbe {
    public let productName: String?
    public let primaryUsagePage: Int?
    public let primaryUsage: Int?
    /// Результат `FFIsForceFeedback` (0 = поддерживается).
    public let isForceFeedbackStatus: HRESULT
    /// Результат `FFCreateDevice`, если до него дошло дело.
    public let createStatus: HRESULT?
    public let axisCount: Int?
    public let supportedEffects: [String]
    public let emulatedEffects: [String]

    public var supported: Bool { isForceFeedbackStatus == 0 }
}

/// Диагностика отдачи. Ничего не проигрывает — только спрашивает возможности.
///
/// База отдаёт стандартный HID PID-блок (usage page 0x0F), то есть на уровне
/// протокола отдача описана. Вопрос лишь в том, подхватывает ли её macOS.
public enum MozaForceFeedback {
    public static func probe() -> [ForceFeedbackProbe] {
        var results: [ForceFeedbackProbe] = []

        guard let matching = IOServiceMatching("IOHIDDevice") else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            guard let vendor = intProperty(service, "VendorID"), vendor == MozaDiscovery.vendorID else {
                continue
            }

            let status = FFIsForceFeedback(service)
            var createStatus: HRESULT?
            var axisCount: Int?
            var supported: [String] = []
            var emulated: [String] = []

            if status == 0 {
                var device: FFDeviceObjectReference?
                let created = FFCreateDevice(service, &device)
                createStatus = created

                if created == 0, let device {
                    var capabilities = FFCAPABILITIES()
                    if FFDeviceGetForceFeedbackCapabilities(device, &capabilities) == 0 {
                        axisCount = Int(capabilities.numFfAxes)
                        supported = effectNames(capabilities.supportedEffects)
                        emulated = effectNames(capabilities.emulatedEffects)
                    }
                    FFReleaseDevice(device)
                }
            }

            results.append(ForceFeedbackProbe(
                productName: stringProperty(service, "Product"),
                primaryUsagePage: intProperty(service, "PrimaryUsagePage"),
                primaryUsage: intProperty(service, "PrimaryUsage"),
                isForceFeedbackStatus: status,
                createStatus: createStatus,
                axisCount: axisCount,
                supportedEffects: supported,
                emulatedEffects: emulated
            ))
        }

        return results
    }

    /// Расшифровка кодов ошибок ForceFeedback.framework.
    public static func describe(status: HRESULT) -> String {
        switch status {
        case 0: return "поддерживается"
        case HRESULT(bitPattern: 0x80040200): return "устройство не поддерживает Force Feedback (FFERR_DEVICENOTREG)"
        case HRESULT(bitPattern: 0x80004001): return "не реализовано (FFERR_UNSUPPORTED)"
        case HRESULT(bitPattern: 0x80070005): return "нет доступа (FFERR_NOTEXCLUSIVEACQUIRED)"
        case HRESULT(bitPattern: 0x8007000E): return "нет памяти"
        case HRESULT(bitPattern: 0x80070057): return "неверный параметр"
        default: return String(format: "код 0x%08X", UInt32(bitPattern: status))
        }
    }

    private static func effectNames(_ mask: UInt32) -> [String] {
        let table: [(UInt32, String)] = [
            (UInt32(FFCAP_ET_CONSTANTFORCE), "постоянная сила"),
            (UInt32(FFCAP_ET_RAMPFORCE), "нарастающая сила"),
            (UInt32(FFCAP_ET_SQUARE), "меандр"),
            (UInt32(FFCAP_ET_SINE), "синус"),
            (UInt32(FFCAP_ET_TRIANGLE), "треугольник"),
            (UInt32(FFCAP_ET_SAWTOOTHUP), "пила вверх"),
            (UInt32(FFCAP_ET_SAWTOOTHDOWN), "пила вниз"),
            (UInt32(FFCAP_ET_SPRING), "пружина"),
            (UInt32(FFCAP_ET_DAMPER), "демпфер"),
            (UInt32(FFCAP_ET_INERTIA), "инерция"),
            (UInt32(FFCAP_ET_FRICTION), "трение"),
            (UInt32(FFCAP_ET_CUSTOMFORCE), "произвольная сила"),
        ]
        return table.filter { mask & $0.0 != 0 }.map(\.1)
    }

    private static func stringProperty(_ entry: io_registry_entry_t, _ key: String) -> String? {
        guard let reference = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return reference.takeRetainedValue() as? String
    }

    private static func intProperty(_ entry: io_registry_entry_t, _ key: String) -> Int? {
        guard let reference = IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0) else {
            return nil
        }
        return (reference.takeRetainedValue() as? NSNumber)?.intValue
    }
}
