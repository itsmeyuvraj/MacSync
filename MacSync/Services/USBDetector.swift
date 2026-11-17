import Foundation
import IOKit

public final class USBDetector: @unchecked Sendable {
    public static let shared = USBDetector()

    // Common Android Manufacturer Vendor IDs (USB-IF registered)
    public static let androidVendorIDs: Set<Int> = [
        0x18d1, // Google
        0x04e8, // Samsung
        0x2717, // Xiaomi
        0x22d9, // OnePlus / Oppo / Realme
        0x12d1, // Huawei / Honor
        0x22b8, // Motorola
        0x0fce, // Sony
        0x1004, // LG
        0x0bb4, // HTC
        0x2d95, // Vivo
        0x0b05, // Asus
        0x2a70, // Nothing Phone
        0x2a45, // Meizu
        0x19d2, // ZTE
        0x05c6  // Qualcomm Reference
    ]

    private init() {}

    public func scanDevices() -> [DetectedUSBDevice] {
        var devices: [DetectedUSBDevice] = []
        let matchingDict = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        var iterator: io_iterator_t = 0
        let kr = IOServiceGetMatchingServices(kIOMainPortDefault, matchingDict, &iterator)
        guard kr == kIOReturnSuccess else { return devices }

        var service = IOIteratorNext(iterator)
        while service != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == kIOReturnSuccess,
               let dict = props?.takeRetainedValue() as? [String: Any] {
                let name = dict["USB Product Name"] as? String
                    ?? dict["kUSBProductString"] as? String
                    ?? "Android Device"
                let vendor = dict["idVendor"] as? Int ?? 0
                let product = dict["idProduct"] as? Int ?? 0
                let speed = dict["Device Speed"] as? Int ?? dict["Speed"] as? Int ?? -1
                let linkSpeed = dict["UsbLinkSpeed"] as? Int64 ?? (dict["UsbLinkSpeed"] as? Int).map { Int64($0) } ?? 0
                let bcdUSB = dict["bcdUSB"] as? Int ?? 0
                let isAndroid = Self.androidVendorIDs.contains(vendor)

                // Inspect child interfaces to determine whether MTP interface descriptor is exposed
                var hasMTP = false
                var childIterator: io_iterator_t = 0
                if IORegistryEntryGetChildIterator(service, kIOServicePlane, &childIterator) == kIOReturnSuccess {
                    var child = IOIteratorNext(childIterator)
                    while child != 0 {
                        var childProps: Unmanaged<CFMutableDictionary>?
                        if IORegistryEntryCreateCFProperties(child, &childProps, kCFAllocatorDefault, 0) == kIOReturnSuccess,
                           let cDict = childProps?.takeRetainedValue() as? [String: Any] {
                            let cName = cDict["kUSBString"] as? String ?? cDict["USB Product Name"] as? String ?? ""
                            let bInterfaceClass = cDict["bInterfaceClass"] as? Int ?? 0
                            if cName.localizedCaseInsensitiveContains("mtp") || bInterfaceClass == 6 {
                                hasMTP = true
                            }
                        }
                        IOObjectRelease(child)
                        child = IOIteratorNext(childIterator)
                    }
                    IOObjectRelease(childIterator)
                }

                // Skip Apple built-in hubs and internal keyboards/trackpads
                if vendor != 0x05ac {
                    devices.append(
                        DetectedUSBDevice(
                            name: name,
                            vendorId: vendor,
                            productId: product,
                            speed: speed,
                            linkSpeed: linkSpeed,
                            bcdUSB: bcdUSB,
                            isAndroidVendor: isAndroid,
                            hasMTPInterface: hasMTP
                        )
                    )
                }
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        IOObjectRelease(iterator)
        return devices
    }

    /// Returns the detected Android device if it is plugged in on the USB bus
    public func detectConnectedAndroid() -> DetectedUSBDevice? {
        let devices = scanDevices()
        return devices.first(where: { $0.isAndroidVendor })
    }

    /// Returns the detected Android device if it is plugged in but in Charge-Only mode (no MTP interface exposed)
    public func detectChargeOnlyAndroid() -> DetectedUSBDevice? {
        let devices = scanDevices()
        return devices.first(where: { $0.isAndroidVendor && !$0.hasMTPInterface })
    }

    /// Evaluates the negotiated speed of the connected phone
    public func getUSBSpeedInfo(vendorId: Int? = nil, productId: Int? = nil) -> USBSpeedInfo? {
        let devices = scanDevices()
        let matched = devices.first(where: { dev in
            if let v = vendorId, dev.vendorId == v { return true }
            return dev.isAndroidVendor
        })
        guard let dev = matched else { return nil }

        let speedType: USBSpeedType
        // IOUSBHostDevice link speed and speed index evaluation
        if dev.linkSpeed >= 10_000_000_000 || dev.speed >= 4 {
            speedType = .usb31
        } else if dev.linkSpeed >= 5_000_000_000 || dev.speed == 3 || dev.bcdUSB >= 0x0300 {
            speedType = .usb3
        } else if dev.linkSpeed == 480_000_000 || dev.speed == 2 {
            speedType = .usb2
        } else {
            speedType = .usb2
        }

        return USBSpeedInfo(
            speedType: speedType,
            rawSpeed: dev.speed,
            linkSpeed: dev.linkSpeed,
            bcdUSB: dev.bcdUSB,
            productName: dev.name,
            vendorId: dev.vendorId,
            productId: dev.productId
        )
    }

    // MARK: - Live USB Hardware Event Monitoring (Instant Disconnect / Connect)
    private var notifyPort: IONotificationPortRef?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    public var onUSBChanged: (@Sendable () -> Void)?

    public func startMonitoring(onChange: @escaping @Sendable () -> Void) {
        stopMonitoring()
        self.onUSBChanged = onChange

        guard let port = IONotificationPortCreate(kIOMainPortDefault) else { return }
        self.notifyPort = port

        if let runLoopSource = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
        }

        let refCon = Unmanaged.passUnretained(self).toOpaque()

        // Match plugged devices
        let matchDict1 = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        IOServiceAddMatchingNotification(
            port,
            kIOMatchedNotification,
            matchDict1,
            { (ref, iterator) in
                while case let obj = IOIteratorNext(iterator), obj != 0 {
                    IOObjectRelease(obj)
                }
                guard let ref = ref else { return }
                let detector = Unmanaged<USBDetector>.fromOpaque(ref).takeUnretainedValue()
                detector.onUSBChanged?()
            },
            refCon,
            &matchedIterator
        )
        while case let obj = IOIteratorNext(matchedIterator), obj != 0 {
            IOObjectRelease(obj)
        }

        // Match unplugged / removed devices
        let matchDict2 = IOServiceMatching("IOUSBHostDevice") as NSMutableDictionary
        IOServiceAddMatchingNotification(
            port,
            kIOTerminatedNotification,
            matchDict2,
            { (ref, iterator) in
                while case let obj = IOIteratorNext(iterator), obj != 0 {
                    IOObjectRelease(obj)
                }
                guard let ref = ref else { return }
                let detector = Unmanaged<USBDetector>.fromOpaque(ref).takeUnretainedValue()
                detector.onUSBChanged?()
            },
            refCon,
            &terminatedIterator
        )
        while case let obj = IOIteratorNext(terminatedIterator), obj != 0 {
            IOObjectRelease(obj)
        }
    }

    public func stopMonitoring() {
        if let port = notifyPort {
            if let runLoopSource = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() {
                CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .defaultMode)
            }
            IONotificationPortDestroy(port)
            self.notifyPort = nil
        }
        if matchedIterator != 0 {
            IOObjectRelease(matchedIterator)
            matchedIterator = 0
        }
        if terminatedIterator != 0 {
            IOObjectRelease(terminatedIterator)
            terminatedIterator = 0
        }
        onUSBChanged = nil
    }
}
