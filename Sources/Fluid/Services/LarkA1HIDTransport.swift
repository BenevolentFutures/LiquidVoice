import Foundation
import IOKit
import IOKit.hid

/// Sends the Lark A1 heartbeat (`LarkA1Protocol.heartbeatRequest`) and reads the reply. Blocking:
/// call it only from `LapelMicBatteryMonitor`'s background queue, never the main thread.
///
/// It matches the one IOHIDDevice service with the receiver's vendor and product ID through the
/// I/O Registry and opens only that device, unseized, for the duration of one query. No
/// IOHIDManager, so nothing else (no keyboard) is ever opened. The receiver's HID device does not
/// carry `RequiresTCCAuthorization` (only keyboards and pointing devices do), so opening it asks
/// for no Input Monitoring permission. Under `TestHostQuietMode` it never touches IOKit.
nonisolated struct LarkA1HIDTransport: Sendable {
    func heartbeat() -> LarkA1PollOutcome {
        guard !TestHostQuietMode.isActive else { return .noDevice }
        guard let device = Self.copyReceiver() else { return .noDevice }

        let options = IOOptionBits(kIOHIDOptionsTypeNone)
        let opened = IOHIDDeviceOpen(device, options)
        guard opened == kIOReturnSuccess else { return .transferFailed(step: "open", code: opened) }
        defer { IOHIDDeviceClose(device, options) }

        let reportID = CFIndex(LarkA1Protocol.reportID)
        let request = LarkA1Protocol.heartbeatRequest
        let sent = request.withUnsafeBufferPointer { buffer in
            IOHIDDeviceSetReport(device, kIOHIDReportTypeFeature, reportID, buffer.baseAddress!, buffer.count)
        }
        guard sent == kIOReturnSuccess else { return .transferFailed(step: "set", code: sent) }

        var reply = [UInt8](repeating: 0, count: LarkA1Protocol.reportLength)
        var length = CFIndex(reply.count)
        let received = reply.withUnsafeMutableBufferPointer { buffer in
            IOHIDDeviceGetReport(device, kIOHIDReportTypeFeature, reportID, buffer.baseAddress!, &length)
        }
        guard received == kIOReturnSuccess else { return .transferFailed(step: "get", code: received) }

        switch LarkA1Protocol.parseHeartbeatReply(Array(reply.prefix(max(0, min(length, reply.count))))) {
        case let .success(status): return .reading(status)
        case let .failure(failure): return .unreadable(failure)
        }
    }

    /// The receiver's IOHIDDevice: the first service with its vendor and product ID that carries
    /// the status usage page (the receiver exposes one, with consumer control beside it).
    private static func copyReceiver() -> IOHIDDevice? {
        guard let matching = IOServiceMatching(kIOHIDDeviceKey) as NSMutableDictionary? else { return nil }
        matching[kIOHIDVendorIDKey] = LarkA1Protocol.vendorID
        matching[kIOHIDProductIDKey] = LarkA1Protocol.productID
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            defer { IOObjectRelease(service) }
            guard Self.carriesStatusPage(service) else { continue }
            if let device = IOHIDDeviceCreate(kCFAllocatorDefault, service) { return device }
        }
        return nil
    }

    private static func carriesStatusPage(_ service: io_service_t) -> Bool {
        let key = kIOHIDDeviceUsagePairsKey as CFString
        guard let pairs = IORegistryEntryCreateCFProperty(service, key, kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? [[String: Any]]
        else { return false }
        return pairs.contains { ($0[kIOHIDDeviceUsagePageKey] as? Int) == LarkA1Protocol.statusUsagePage }
    }
}
