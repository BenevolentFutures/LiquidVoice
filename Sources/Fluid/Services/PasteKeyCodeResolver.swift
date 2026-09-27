import Carbon.HIToolbox
import Foundation

// Ported from altic-dev/FluidVoice@42e33e68 (Reduce dictation latency and add pipeline
// evaluation, #950) by ALTIC. Only this resolver and PasteKeyCodeCache were taken from that
// PR: keyboard-layout support for the synthesized Cmd+V (altic-dev/FluidVoice@fb896ebe,
// grohith327) needs them. The rest of #950 (latency analytics, pipeline evaluation) is not
// ported.

nonisolated enum PasteKeyCodeResolver {
    /// Resolve the shortcut with Command held, not the unmodified typing character.
    /// Dvorak-QWERTY Command and non-Latin layouts can use different shortcut mappings.
    static func current() -> CGKeyCode {
        precondition(Thread.isMainThread)
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return 9 }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return self.resolve(layoutData: data, keyboardType: UInt32(LMGetKbdType()))
    }

    static func resolve(layoutData: Data?, keyboardType: UInt32) -> CGKeyCode {
        guard let layoutData, !layoutData.isEmpty else { return 9 }
        return layoutData.withUnsafeBytes { bytes -> CGKeyCode in
            guard let layout = bytes.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return 9 }
            var characters = [UniChar](repeating: 0, count: 4)
            for key: UInt16 in 0..<128 {
                var dead: UInt32 = 0
                var length = 0
                let status = UCKeyTranslate(
                    layout,
                    key,
                    UInt16(kUCKeyActionDisplay),
                    UInt32(cmdKey >> 8),
                    keyboardType,
                    UInt32(kUCKeyTranslateNoDeadKeysMask),
                    &dead,
                    characters.count,
                    &length,
                    &characters
                )
                if status == noErr, length == 1, characters[0] == 118 { return key }
            }
            return 9
        }
    }
}
