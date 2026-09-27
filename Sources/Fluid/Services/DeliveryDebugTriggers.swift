import AppKit
import Foundation

// Scripted real-path checks for text delivery, in the spirit of the debug paste-last trigger
// from altic-dev/FluidVoice@fadaed91 and the card preview trigger from @ff92b4b8.
//
// Debug builds only, and inert unless enabled on this machine:
//   defaults write com.FluidApp.app.dev LiquidVoiceDebugDeliveryTriggers -bool YES
// Then post a distributed notification, for example:
//   swift -e 'import Foundation; DistributedNotificationCenter.default().postNotificationName(
//     .init("com.FluidApp.debug.deliverText"), object: "hello from a script", userInfo: nil,
//     deliverImmediately: true)'
// Every trigger logs a DEBUG_DELIVERY line (result included) to the app log.

@MainActor
enum DeliveryDebugTriggers {
    static let enabledDefaultsKey = "LiquidVoiceDebugDeliveryTriggers"

    /// Types `object` (a String) into the focused field through the normal delivery pipeline.
    static let deliverText = Notification.Name("com.FluidApp.debug.deliverText")
    /// Runs the Paste Last Transcription action, exactly as its hotkey does.
    static let pasteLastTranscript = Notification.Name("com.FluidApp.debug.pasteLastTranscript")
    /// Shows the failure card; `object` may name a `TextDeliveryFailure` raw value.
    static let showDeliveryFailure = Notification.Name("com.FluidApp.debug.showDeliveryFailure")

    private static var observers: [NSObjectProtocol] = []
    private static let typingService = TypingService()

    static func registerIfEnabled() {
        #if DEBUG
        guard UserDefaults.standard.bool(forKey: self.enabledDefaultsKey), self.observers.isEmpty else { return }
        let center = DistributedNotificationCenter.default()
        self.observers.append(center.addObserver(forName: self.deliverText, object: nil, queue: .main) { note in
            let text = (note.object as? String) ?? "Liquid Voice debug delivery"
            MainActor.assumeIsolated {
                DebugLogger.shared.info("DEBUG_DELIVERY deliverText chars=\(text.count)", source: "DeliveryDebugTriggers")
                self.typingService.typeOutputPlanInstantly(.plain(text), preferredTargetPID: nil, textReadyAt: nil) { result in
                    DebugLogger.shared.info("DEBUG_DELIVERY deliverText result=\(result)", source: "DeliveryDebugTriggers")
                }
            }
        })
        self.observers.append(center.addObserver(forName: self.pasteLastTranscript, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                DebugLogger.shared.info("DEBUG_DELIVERY pasteLastTranscript", source: "DeliveryDebugTriggers")
                NotchContentState.shared.onPasteLastRequested?()
            }
        })
        self.observers.append(center.addObserver(forName: self.showDeliveryFailure, object: nil, queue: .main) { note in
            let failure = (note.object as? String).flatMap(TextDeliveryFailure.init(rawValue:)) ?? .noEditableTarget
            MainActor.assumeIsolated {
                DebugLogger.shared.info("DEBUG_DELIVERY showDeliveryFailure failure=\(failure.rawValue)", source: "DeliveryDebugTriggers")
                DeliveryFailureOverlayController.shared.show(DeliveryFailureReport(
                    failure: failure,
                    transcript: "The quick brown fox jumps over the lazy dog and keeps going for a while, long enough to need a second line.",
                    keptOnClipboard: true
                ))
            }
        })
        DebugLogger.shared.info("Delivery debug triggers enabled", source: "DeliveryDebugTriggers")
        #endif
    }
}
