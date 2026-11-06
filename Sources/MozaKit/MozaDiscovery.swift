import Foundation
import IOKit
import IOKit.serial

public struct SerialPortInfo {
    public let calloutPath: String
    public let vendorID: Int?
    public let productID: Int?
    public let productName: String?
}

public struct HIDDeviceInfo {
    public let productName: String?
    public let vendorID: Int
    public let productID: Int
    public let primaryUsagePage: Int?
    public let primaryUsage: Int?
    public let transport: String?
}

/// Поиск устройства в IORegistry по VID/PID — чтобы не зашивать `usbmodem101`
/// и переживать переподключение с другим номером порта.
public enum MozaDiscovery {
    /// Gudsen (производитель MOZA).
    public static let vendorID = 0x346e

    /// Подтверждённая на живом устройстве модель. Остальные PID семейства
    /// известны только из сторонних списков, поэтому их не утверждаем.
    public static let knownProductNames: [Int: String] = [
        0x0004: "MOZA R5 Base",
    ]

    public static func modelName(productID: Int) -> String {
        knownProductNames[productID] ?? String(format: "неизвестная модель (PID 0x%04X)", productID)
    }

    /// Все serial-порты, у которых USB-родитель — устройство Gudsen.
    public static func mozaSerialPorts() -> [SerialPortInfo] {
        var found: [SerialPortInfo] = []

        guard let matching = IOServiceMatching(kIOSerialBSDServiceValue) else { return [] }
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
            return []
        }
        defer { IOObjectRelease(iterator) }

        while true {
            let service = IOIteratorNext(iterator)
            if service == 0 { break }
            defer { IOObjectRelease(service) }

            guard let callout = stringProperty(service, kIOCalloutDeviceKey) else { continue }
            guard let usb = usbParent(of: service), usb.vendorID == vendorID else { continue }

            found.append(SerialPortInfo(
                calloutPath: callout,
                vendorID: usb.vendorID,
                productID: usb.productID,
                productName: usb.name
            ))
        }

        return found
    }

    /// HID-интерфейсы устройства. Только чтение свойств из IORegistry —
    /// устройство не открывается, поэтому разрешение Input Monitoring не требуется.
    public static func mozaHIDDevices() -> [HIDDeviceInfo] {
        var found: [HIDDeviceInfo] = []

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

            guard let vid = intProperty(service, "VendorID"), vid == vendorID,
                  let pid = intProperty(service, "ProductID") else { continue }

            found.append(HIDDeviceInfo(
                productName: stringProperty(service, "Product"),
                vendorID: vid,
                productID: pid,
                primaryUsagePage: intProperty(service, "PrimaryUsagePage"),
                primaryUsage: intProperty(service, "PrimaryUsage"),
                transport: stringProperty(service, "Transport")
            ))
        }

        return found
    }

    // MARK: - IORegistry

    private static func usbParent(of service: io_object_t) -> (vendorID: Int, productID: Int, name: String?)? {
        var current: io_object_t = service
        IOObjectRetain(current)

        // Глубина вложенности IOSerialBSDClient -> ... -> IOUSBHostDevice невелика,
        // ограничиваем подъём, чтобы не уйти в корень реестра.
        for _ in 0..<12 {
            if let vid = intProperty(current, "idVendor"), let pid = intProperty(current, "idProduct") {
                let name = stringProperty(current, "USB Product Name")
                    ?? stringProperty(current, "kUSBProductString")
                IOObjectRelease(current)
                return (vid, pid, name)
            }

            var parent: io_registry_entry_t = 0
            let status = IORegistryEntryGetParentEntry(current, kIOServicePlane, &parent)
            IOObjectRelease(current)
            guard status == KERN_SUCCESS, parent != 0 else { return nil }
            current = parent
        }

        IOObjectRelease(current)
        return nil
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
