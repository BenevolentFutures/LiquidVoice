import Foundation

/// The Hollyland Lark A1 receiver's status query, as pure data: the one frame Liquid Voice sends
/// and the parsing of its reply. No I/O here; `LapelMicBatteryMonitor` does the HID transfer.
///
/// The receiver (USB-C, VID 0x3547, PID 0x0407) publishes no battery to macOS, but answers a
/// heartbeat on HID feature report 5 (vendor page 0xFF12, 63 bytes plus the report ID). The
/// heartbeat only reads status; it changes no setting. It is the only command this app ever sends.
///
/// Protocol credit: decoded by pedrozimmermannsoares in vorssaint/vorssaint-utils issue #2510
/// (branch `feat/receiver-battery`). That code is GPL-3.0; this is an independent implementation
/// written from the documented frame layout, and copies none of it.
nonisolated enum LarkA1Protocol {
    static let vendorID = 0x3547
    static let productID = 0x0407
    /// The vendor usage page that carries report 5.
    static let statusUsagePage = 0xFF12
    static let reportID = 5
    static let reportLength = 64
    static let heartbeatCommand: UInt8 = 0x1F

    /// `05 03 AA DD 1F 00 00 EF`, then zeros to 64 bytes: report 5, a host-to-device frame, the
    /// heartbeat command 0x1F with a zero-length payload. A fixed constant on purpose, so no
    /// other command can ever be built.
    static let heartbeatRequest: [UInt8] = {
        var frame = [UInt8](repeating: 0, count: reportLength)
        frame.replaceSubrange(0..<5, with: [0x05, 0x03, 0xAA, 0xDD, heartbeatCommand])
        frame[7] = 0xEF
        return frame
    }()

    enum ParseFailure: String, Error, Equatable, Sendable {
        /// Shorter than its header, or than the payload its header announces.
        case short
        /// Not a device-to-host frame on report 5.
        case malformed
        /// A reply to some other command.
        case wrongCommand = "wrong-command"
    }

    /// Reply: `05 03 BB DD 1F lenHi lenLo`, then the payload. `payload[0]` and `payload[1]` are
    /// mic 1's and mic 2's link state (1 = linked); `payload[2]` and `payload[3]` their battery
    /// percent. A linked mic with a percent outside 0–100 reads as linked with no percent.
    static func parseHeartbeatReply(_ reply: [UInt8]) -> Result<LarkA1Status, ParseFailure> {
        let header = 7
        guard reply.count >= header else { return .failure(.short) }
        guard reply[0] == UInt8(reportID), reply[1] == 0x03, reply[2] == 0xBB, reply[3] == 0xDD else {
            return .failure(.malformed)
        }
        guard reply[4] == heartbeatCommand else { return .failure(.wrongCommand) }
        let length = Int(reply[5]) << 8 | Int(reply[6])
        guard length >= 4 else { return .failure(.malformed) }
        guard reply.count >= header + length else { return .failure(.short) }
        let payload = reply[header...]
        func mic(link: Int, battery: Int) -> LarkA1Status.Mic {
            let isLinked = payload[payload.startIndex + link] == 1
            let raw = Int(payload[payload.startIndex + battery])
            return LarkA1Status.Mic(isLinked: isLinked, percent: isLinked && raw <= 100 ? raw : nil)
        }
        return .success(LarkA1Status(mic1: mic(link: 0, battery: 2), mic2: mic(link: 1, battery: 3)))
    }

    /// AppleUSBAudioEngine sets a USB device's model UID to "<name>:<vid>:<pid>" in hex, so the
    /// raw receiver's is "Wireless Microphone:3547:0407". Matched on the IDs, never the name.
    static func isReceiverModelUID(_ modelUID: String?) -> Bool {
        guard let parts = modelUID?.lowercased().split(separator: ":"), parts.count >= 3 else { return false }
        return parts[parts.count - 2] == "3547" && parts[parts.count - 1] == "0407"
    }

    /// The selected input is the receiver itself, or an aggregate (Atin's "Hollyland Lapel Mic")
    /// with the receiver among its sub-devices. The lookups are Core Audio in the app, fakes in tests.
    static func inputIsReceiver(
        uid: String,
        modelUID: (String) -> String?,
        subDeviceUIDs: (String) -> [String]
    ) -> Bool {
        if self.isReceiverModelUID(modelUID(uid)) { return true }
        return subDeviceUIDs(uid).contains { self.isReceiverModelUID(modelUID($0)) }
    }

    /// The structured log line for one poll's outcome, or nil when it matches the last one logged:
    /// an unchanged poll logs nothing.
    static func logLine(for outcome: LarkA1PollOutcome, previous: LarkA1PollOutcome?) -> String? {
        guard outcome != previous else { return nil }
        func field(_ mic: LarkA1Status.Mic?) -> String {
            guard let mic else { return "-" }
            guard mic.isLinked else { return "off" }
            return mic.percent.map { "\($0)%" } ?? "linked"
        }
        let status: LarkA1Status? = if case let .reading(status) = outcome { status } else { nil }
        return "MIC_BATTERY device=lark-a1 mic1=\(field(status?.mic1)) mic2=\(field(status?.mic2)) result=\(outcome.result)"
    }
}

/// One heartbeat's decoded status.
nonisolated struct LarkA1Status: Equatable, Sendable {
    struct Mic: Equatable, Sendable {
        let isLinked: Bool
        /// 0–100, only for a linked mic that reported a value in range.
        let percent: Int?
    }

    let mic1: Mic
    let mic2: Mic

    var linkedCount: Int {
        [self.mic1, self.mic2].filter(\.isLinked).count
    }

    /// The linked mics' percents, mic 1 first.
    var linkedPercents: [Int] {
        [self.mic1, self.mic2].compactMap(\.percent)
    }
}

/// What one poll came to, for the log and the cache.
nonisolated enum LarkA1PollOutcome: Equatable, Sendable {
    case reading(LarkA1Status)
    case noDevice
    /// An IOKit call failed: which one, and its IOReturn.
    case transferFailed(step: String, code: Int32)
    case unreadable(LarkA1Protocol.ParseFailure)

    var result: String {
        switch self {
        case .reading: "ok"
        case .noDevice: "no-device"
        case let .transferFailed(step, code): "\(step)-failed:" + String(format: "0x%08x", UInt32(bitPattern: code))
        case let .unreadable(failure): failure.rawValue
        }
    }
}
