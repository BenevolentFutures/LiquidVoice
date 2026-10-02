import CoreAudio
import Foundation

/// Keeps the Hollyland Lark A1's battery for the overlay's mic label (DESIGN.md §16).
///
/// Nothing here runs on the dictation start path or the paste path. The coordinator reports each
/// resolved input (`noteSelectedInput`, one comparison and one async hop); a background utility
/// queue resolves whether that input is the receiver (Core Audio, by USB IDs, through an
/// aggregate's sub-devices too), and while it is, sends the heartbeat 1 s after the input became
/// it and every 30 s after. The 30 s timer runs for whatever input is selected, re-resolving it
/// each tick (two Core Audio property reads), so a receiver replugged or added to the aggregate is
/// picked up; the HID heartbeat goes out only on ticks where the input is the receiver. The main actor keeps the last reading with its time and sets
/// `SignalOverlayModel.micBattery` only when what the label shows changes; the overlay reads that
/// and nothing else. A reading older than 2 minutes reads as none. Under `TestHostQuietMode` it
/// does nothing at all, so no test ever opens a HID device.
@MainActor
final class LapelMicBatteryMonitor {
    static let shared = LapelMicBatteryMonitor()

    static let pollInterval: TimeInterval = 30
    /// The first heartbeat after the input becomes the receiver waits this long, so it does not
    /// land on the capture start that resolved it. Later ticks run whether or not a recording is
    /// live; a status query on the receiver's HID interface does not touch its audio stream.
    static let firstPollDelay: TimeInterval = 1

    private let worker = Worker()
    private var selectedUID: String?
    /// Whether each input UID the worker resolved is the receiver.
    private var receiverInputs: [String: Bool] = [:]
    private var reading: LarkA1Status?
    private var readAt: Date?
    private var expiry: DispatchWorkItem?

    private init() {}

    /// The input the monitor is following, nil until one is reported (and always in quiet mode).
    var followedInputUID: String? {
        self.selectedUID
    }

    /// The input capture resolved. Cheap enough for the start path: a repeat of the same input
    /// returns at once, and a change only hands the UID to the background queue.
    func noteSelectedInput(uid: String?) {
        guard !TestHostQuietMode.isActive, uid != self.selectedUID else { return }
        self.selectedUID = uid
        self.publish()
        self.worker.select(uid: uid)
    }

    fileprivate func workerResolved(uid: String, isReceiver: Bool, outcome: LarkA1PollOutcome?) {
        self.receiverInputs[uid] = isReceiver
        if case let .reading(status) = outcome {
            self.reading = status
            self.readAt = Date()
            self.scheduleExpiry()
        }
        self.publish()
    }

    private func publish(now: Date = Date()) {
        let battery = SignalMicBattery.from(
            inputIsReceiver: self.selectedUID.flatMap { self.receiverInputs[$0] } ?? false,
            reading: self.reading,
            readAt: self.readAt,
            now: now
        )
        let model = SignalOverlayModel.shared
        if model.micBattery != battery {
            model.micBattery = battery
        }
    }

    /// Republishes once the last reading turns stale, so a receiver that stopped answering drops
    /// its percent within 2 minutes even when no other poll lands.
    private func scheduleExpiry() {
        self.expiry?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.publish() }
        self.expiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + SignalMicBattery.freshness + 0.5, execute: work)
    }

    /// The background half, confined to its serial queue: resolves the input, runs the 30 s
    /// timer while an input is selected, sends the heartbeat only while it is the receiver, and
    /// logs a poll only when its outcome changed.
    private final nonisolated class Worker: @unchecked Sendable {
        private let queue = DispatchQueue(label: "com.stage11.liquidvoice.mic-battery", qos: .utility)
        private let transport = LarkA1HIDTransport()
        private var uid: String?
        private var timer: DispatchSourceTimer?
        private var lastLogged: LarkA1PollOutcome?

        func select(uid: String?) {
            self.queue.async {
                self.uid = uid
                self.timer?.cancel()
                self.timer = nil
                guard let uid else { return }
                let isReceiver = Self.inputIsReceiver(uid)
                Self.report(uid: uid, isReceiver: isReceiver, outcome: nil)
                // Ticks re-resolve, so the aggregate's edits and the receiver's replugging are seen.
                let timer = DispatchSource.makeTimerSource(queue: self.queue)
                timer.schedule(
                    deadline: .now() + LapelMicBatteryMonitor.firstPollDelay,
                    repeating: LapelMicBatteryMonitor.pollInterval,
                    leeway: .seconds(5)
                )
                timer.setEventHandler { [weak self] in self?.tick(uid: uid) }
                timer.resume()
                self.timer = timer
            }
        }

        private func tick(uid: String) {
            guard uid == self.uid else { return }
            let isReceiver = Self.inputIsReceiver(uid)
            guard isReceiver else {
                Self.report(uid: uid, isReceiver: false, outcome: nil)
                return
            }
            let outcome = self.transport.heartbeat()
            if let line = LarkA1Protocol.logLine(for: outcome, previous: self.lastLogged) {
                DebugLogger.shared.info(line, source: "MicBattery")
                self.lastLogged = outcome
            }
            Self.report(uid: uid, isReceiver: true, outcome: outcome)
        }

        private static func report(uid: String, isReceiver: Bool, outcome: LarkA1PollOutcome?) {
            Task { @MainActor in
                LapelMicBatteryMonitor.shared.workerResolved(uid: uid, isReceiver: isReceiver, outcome: outcome)
            }
        }

        // MARK: Core Audio

        private static func inputIsReceiver(_ uid: String) -> Bool {
            LarkA1Protocol.inputIsReceiver(
                uid: uid,
                modelUID: { self.deviceID(forUID: $0).flatMap { self.modelUID(of: $0) } },
                subDeviceUIDs: { self.deviceID(forUID: $0).map { self.subDeviceUIDs(of: $0) } ?? [] }
            )
        }

        private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
            AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
        }

        private static func deviceID(forUID uid: String) -> AudioObjectID? {
            var address = self.address(kAudioHardwarePropertyTranslateUIDToDevice)
            var qualifier = uid as CFString
            var device = AudioObjectID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            let status = withUnsafeMutablePointer(to: &qualifier) { pointer in
                AudioObjectGetPropertyData(
                    AudioObjectID(kAudioObjectSystemObject),
                    &address,
                    UInt32(MemoryLayout<CFString>.size),
                    pointer,
                    &size,
                    &device
                )
            }
            return status == noErr && device != kAudioObjectUnknown ? device : nil
        }

        private static func modelUID(of device: AudioObjectID) -> String? {
            var address = self.address(kAudioDevicePropertyModelUID)
            var value: Unmanaged<CFString>?
            var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return nil }
            return value?.takeRetainedValue() as String?
        }

        /// An aggregate's sub-devices' UIDs; empty for any other device.
        private static func subDeviceUIDs(of device: AudioObjectID) -> [String] {
            var address = self.address(kAudioAggregateDevicePropertyFullSubDeviceList)
            guard AudioObjectHasProperty(device, &address) else { return [] }
            var value: Unmanaged<CFArray>?
            var size = UInt32(MemoryLayout<Unmanaged<CFArray>?>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else { return [] }
            return (value?.takeRetainedValue() as? [String]) ?? []
        }
    }
}
