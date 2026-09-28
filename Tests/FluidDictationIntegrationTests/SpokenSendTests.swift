import AppKit
import Combine
import CoreGraphics
@testable import Liquid_Voice_Debug
import XCTest

// Parser tests ported from altic-dev/FluidVoice by altic-dev (@c679506d, @95fe1b15,
// @4310f143, @60480451). The delivery, policy, overlay-state and countdown tests are Liquid
// Voice's own; the terminal paste-then-send guarantees live in
// TypingServiceTransientPasteboardTests.swift next to the terminal paste tests they extend.

final class SpokenSendParserTests: XCTestCase {
    private func parse(_ text: String, phrase: String = "send it") -> SpokenSendParseResult {
        SpokenSendParser.parse(text, phrase: phrase, enabled: true)
    }

    // MARK: Liquid Voice's correctness bar

    func testPhraseAtTheTrueEndSendsWhateverThePunctuationAndCase() {
        XCTAssertEqual(self.parse("Fix the typo in the README, send it"), SpokenSendParseResult(text: "Fix the typo in the README.", shouldSend: true))
        XCTAssertEqual(self.parse("Fix the typo in the README. Send it."), SpokenSendParseResult(text: "Fix the typo in the README.", shouldSend: true))
        XCTAssertEqual(self.parse("fix the typo in the README, send it!"), SpokenSendParseResult(text: "fix the typo in the README.", shouldSend: true))
        XCTAssertEqual(self.parse("Looks right…, send it"), SpokenSendParseResult(text: "Looks right…", shouldSend: true))
        XCTAssertEqual(self.parse("Ship the build. SEND IT"), SpokenSendParseResult(text: "Ship the build.", shouldSend: true))
    }

    func testPhraseMidSentenceNeverSends() {
        for text in [
            "I'll send it tomorrow",
            "I'll send it tomorrow.",
            "send it to Bob and then…",
            "Send it to Bob and then ask for a review.",
            "Please send it when the tests pass",
            "We always resend it", // "resend" is not the phrase
            "What a godsend it",
        ] {
            XCTAssertEqual(self.parse(text), SpokenSendParseResult(text: text, shouldSend: false), text)
        }
    }

    func testTranscriptThatIsOnlyThePhraseSendsTheExistingDraft() {
        for text in ["Send it.", "send it", "Send it!", "  SEND IT  ", "Send it, send it."] {
            XCTAssertEqual(self.parse(text), SpokenSendParseResult(text: "", shouldSend: true), text)
        }
    }

    func testAQuestionEndingInThePhraseIsNotACommand() {
        XCTAssertEqual(self.parse("Can you send it?"), SpokenSendParseResult(text: "Can you send it?", shouldSend: false))
        XCTAssertEqual(self.parse("Did you send it?!"), SpokenSendParseResult(text: "Did you send it?!", shouldSend: false))
        XCTAssertFalse(
            SpokenSendParser.parseArmed("Can you sent it?", phrase: "send it", enabled: true, wasArmed: true).shouldSend,
            "an armed near miss must not turn a question into a send either"
        )
    }

    func testADanglingAndBeforeThePhraseGoesWithIt() {
        XCTAssertEqual(self.parse("Fix the typo and send it"), SpokenSendParseResult(text: "Fix the typo.", shouldSend: true))
        XCTAssertEqual(self.parse("Fix the typo, and send it."), SpokenSendParseResult(text: "Fix the typo.", shouldSend: true))
        XCTAssertEqual(self.parse("Fix the typo and then send it"), SpokenSendParseResult(text: "Fix the typo.", shouldSend: true))
        XCTAssertEqual(self.parse("And send it."), SpokenSendParseResult(text: "", shouldSend: true))
        // "then" alone can end a real sentence and stays.
        XCTAssertEqual(self.parse("See you then, send it."), SpokenSendParseResult(text: "See you then.", shouldSend: true))
        XCTAssertEqual(self.parse("Rock and roll, send it"), SpokenSendParseResult(text: "Rock and roll.", shouldSend: true))
    }

    // MARK: Ported from upstream

    func testDisabledFeatureLeavesTextUntouched() {
        XCTAssertEqual(
            SpokenSendParser.parse("Hello send it", phrase: "send it", enabled: false),
            SpokenSendParseResult(text: "Hello send it", shouldSend: false)
        )
    }

    func testTerminalPhraseIsRemovedAndArmsSend() {
        XCTAssertEqual(self.parse("Hello there, send it."), SpokenSendParseResult(text: "Hello there.", shouldSend: true))
    }

    func testCapitalizationAndFullStopDoNotAffectSend() {
        XCTAssertEqual(self.parse("Ready to go, SEND IT."), SpokenSendParseResult(text: "Ready to go.", shouldSend: true))
    }

    func testNearbyTrailingPunctuationDoesNotAffectSend() {
        XCTAssertEqual(self.parse(#"Ready to go — send it…")]"#), SpokenSendParseResult(text: "Ready to go.", shouldSend: true))
    }

    func testPhraseInMiddleDoesNotArmSend() {
        XCTAssertEqual(
            self.parse("Send it when you are ready"),
            SpokenSendParseResult(text: "Send it when you are ready", shouldSend: false)
        )
    }

    func testTerminalPhraseDoesNotRequireLeadingOrTrailingPunctuation() {
        XCTAssertEqual(self.parse("Ready to go send it"), SpokenSendParseResult(text: "Ready to go.", shouldSend: true))
    }

    func testRepeatedTerminalPhrasesAreAllRemoved() {
        XCTAssertEqual(self.parse("I wanna send it, send it."), SpokenSendParseResult(text: "I wanna.", shouldSend: true))
        XCTAssertEqual(self.parse("Ready SEND IT send it"), SpokenSendParseResult(text: "Ready.", shouldSend: true))
        XCTAssertEqual(self.parse("send it, send it."), SpokenSendParseResult(text: "", shouldSend: true))
    }

    func testRepeatedTrailingSeparatorsCollapseToOneSentenceEnding() {
        XCTAssertEqual(self.parse("Ready,,,,; — send it"), SpokenSendParseResult(text: "Ready.", shouldSend: true))
        XCTAssertEqual(self.parse("Ready.,,,;— send it, send it."), SpokenSendParseResult(text: "Ready.", shouldSend: true))
        XCTAssertEqual(self.parse("Ready?,,, send it"), SpokenSendParseResult(text: "Ready?", shouldSend: true))
    }

    func testFinalQuestionOrExclamationMarkIsPreserved() {
        XCTAssertEqual(self.parse("Are we ready? send it."), SpokenSendParseResult(text: "Are we ready?", shouldSend: true))
        XCTAssertEqual(self.parse("Ship it! send it."), SpokenSendParseResult(text: "Ship it!", shouldSend: true))
    }

    func testLiteralEscapeKeepsPhraseWithoutSending() {
        XCTAssertEqual(
            self.parse("Please type literal send it."),
            SpokenSendParseResult(text: "Please type send it", shouldSend: false)
        )
    }

    func testLiteralEscapeBeforeRepeatedCommandKeepsOnePhraseAndSends() {
        XCTAssertEqual(
            self.parse("Please type literal send it, send it."),
            SpokenSendParseResult(text: "Please type send it.", shouldSend: true)
        )
    }

    func testCustomPhraseAllowsFlexibleWhitespaceAndCase() {
        XCTAssertEqual(
            self.parse("Looks good. PLEASE   SUBMIT", phrase: "please submit"),
            SpokenSendParseResult(text: "Looks good.", shouldSend: true)
        )
    }

    func testEmptyOrPunctuationOnlyPhraseNeverSends() {
        XCTAssertEqual(self.parse("Hello", phrase: "   "), SpokenSendParseResult(text: "Hello", shouldSend: false))
        _ = self.parse("Hi !!!", phrase: "!!!")
    }

    // MARK: Countdown checks (upstream)

    func testImmediateStopRequiresChildOption() {
        XCTAssertTrue(SpokenSendParser.shouldStopImmediately("Ready, send it.", phrase: "send it", spokenSendEnabled: true, sendImmediatelyEnabled: true))
        XCTAssertFalse(SpokenSendParser.shouldStopImmediately("Ready, send it.", phrase: "send it", spokenSendEnabled: true, sendImmediatelyEnabled: false))
    }

    func testImmediateStopDoesNotTriggerForPhraseInMiddle() {
        XCTAssertFalse(
            SpokenSendParser.shouldStopImmediately("Send it when you are ready", phrase: "send it", spokenSendEnabled: true, sendImmediatelyEnabled: true)
        )
    }

    func testTerminalASRRefinementStaysArmed() {
        XCTAssertTrue(SpokenSendParser.shouldStopImmediately("Ready, send it", phrase: "send it", spokenSendEnabled: true, sendImmediatelyEnabled: true))
        XCTAssertTrue(SpokenSendParser.shouldStopImmediately("Ready, SEND IT.", phrase: "send it", spokenSendEnabled: true, sendImmediatelyEnabled: true))
        XCTAssertFalse(
            SpokenSendParser.shouldStopImmediately(
                "Ready, send it after I finish this sentence.",
                phrase: "send it",
                spokenSendEnabled: true,
                sendImmediatelyEnabled: true
            )
        )
    }

    func testImmediateStopCompletionRequiresTerminalPhraseAndSilence() {
        XCTAssertFalse(
            SpokenSendParser.canCompleteImmediateStop(
                "Ready, send it.", phrase: "send it", spokenSendEnabled: true, sendImmediatelyEnabled: true, quietDuration: 0
            )
        )
        XCTAssertTrue(
            SpokenSendParser.canCompleteImmediateStop(
                "Ready, send it.",
                phrase: "send it",
                spokenSendEnabled: true,
                sendImmediatelyEnabled: true,
                quietDuration: SpokenSendParser.immediateStopRequiredSilenceDuration
            )
        )
    }

    func testImmediateStopCompletionCancelsForContinuedSpeech() {
        XCTAssertFalse(
            SpokenSendParser.canCompleteImmediateStop(
                "Ready, send it after I finish this sentence.",
                phrase: "send it",
                spokenSendEnabled: true,
                sendImmediatelyEnabled: true,
                quietDuration: 2
            )
        )
    }

    func testVoiceActivityGraceIgnoresOnlyTheRecognitionTail() {
        let startedAt: TimeInterval = 100
        XCTAssertFalse(SpokenSendParser.shouldCancelCountdownForVoiceActivity(countdownStartedAt: startedAt, voiceActivityAt: startedAt + 0.05))
        XCTAssertTrue(
            SpokenSendParser.shouldCancelCountdownForVoiceActivity(
                countdownStartedAt: startedAt,
                voiceActivityAt: startedAt + SpokenSendParser.immediateStopVoiceActivityGraceDuration + 0.001
            )
        )
        XCTAssertFalse(SpokenSendParser.isMeaningfulVoiceActivity(SpokenSendParser.immediateStopVoiceActivityLevelThreshold.nextDown))
        XCTAssertTrue(SpokenSendParser.isMeaningfulVoiceActivity(SpokenSendParser.immediateStopVoiceActivityLevelThreshold))
    }

    // MARK: Armed phrase across noisy partials (upstream @60480451)

    func testArmedSendSurvivesNoisyStreamingRefinements() {
        let armed = "Ready to go, send it."
        for noisy in ["Ready to go, sent it.", "Ready to go, send", "Ready to go send it", "Ready to go —", ""] {
            XCTAssertTrue(SpokenSendParser.isArmed(noisy, armedText: armed, phrase: "send it", enabled: true), "\(noisy) must keep the send armed")
        }
        XCTAssertFalse(SpokenSendParser.isArmed("Ready to go, send it to Bob", armedText: armed, phrase: "send it", enabled: true))
        XCTAssertFalse(SpokenSendParser.isArmed("Ready to go, sent it.", armedText: nil, phrase: "send it", enabled: true))
        XCTAssertFalse(SpokenSendParser.isArmed("Ready to go, send it.", armedText: armed, phrase: "send it", enabled: false))
    }

    func testArmedCountdownCompletesThroughNoisyPartial() {
        XCTAssertTrue(
            SpokenSendParser.canCompleteImmediateStop(
                "Ready, sent it.",
                phrase: "send it",
                spokenSendEnabled: true,
                sendImmediatelyEnabled: true,
                quietDuration: SpokenSendParser.immediateStopRequiredSilenceDuration,
                armedText: "Ready, send it."
            )
        )
        XCTAssertFalse(
            SpokenSendParser.canCompleteImmediateStop(
                "Ready, send it after I finish this sentence.",
                phrase: "send it",
                spokenSendEnabled: true,
                sendImmediatelyEnabled: true,
                quietDuration: SpokenSendParser.immediateStopRequiredSilenceDuration,
                armedText: "Ready, send it."
            )
        )
    }

    func testArmedFinalParseAcceptsNearMissPhrase() {
        XCTAssertEqual(
            SpokenSendParser.parseArmed("Ready to go, sent it.", phrase: "send it", enabled: true, wasArmed: true),
            SpokenSendParseResult(text: "Ready to go.", shouldSend: true)
        )
        XCTAssertEqual(
            SpokenSendParser.parseArmed("Ready to go, Send It", phrase: "send it", enabled: true, wasArmed: false),
            SpokenSendParseResult(text: "Ready to go.", shouldSend: true)
        )
        XCTAssertEqual(
            SpokenSendParser.parseArmed("Ready to go, sent it.", phrase: "send it", enabled: true, wasArmed: false),
            SpokenSendParseResult(text: "Ready to go, sent it.", shouldSend: false)
        )
        XCTAssertEqual(
            SpokenSendParser.parseArmed("Ready to go, send it to Bob", phrase: "send it", enabled: true, wasArmed: true),
            SpokenSendParseResult(text: "Ready to go, send it to Bob", shouldSend: false)
        )
        XCTAssertEqual(
            SpokenSendParser.parseArmed("Please type literal send it.", phrase: "send it", enabled: true, wasArmed: true),
            SpokenSendParseResult(text: "Please type send it", shouldSend: false)
        )
    }

    private func run(_ partials: [String], phrase: String = "send it", eligible: Bool = true) -> (results: [Bool], state: SpokenSendArmingState) {
        var state = SpokenSendArmingState()
        let results = partials.map { state.update(partial: $0, isEligible: eligible, phrase: phrase) }
        return (results, state)
    }

    func testArmingSurvivesRealisticNoisyStream() {
        let stream = ["Ready", "Ready send", "Ready send it", "Ready sent it.", "Ready send", "Ready, send it.", "Ready, SEND IT"]
        let (results, state) = self.run(stream)
        XCTAssertEqual(results, [false, false, true, true, true, true, true])
        XCTAssertTrue(state.wasArmed)
    }

    func testArmingDisarmsWhenSpeechContinues() {
        let (results, state) = self.run(["Ready send it", "Ready send it to", "Ready send it to Bob"])
        XCTAssertEqual(results, [true, false, false])
        XCTAssertFalse(state.wasArmed)
    }

    func testArmingReArmsAfterContinuation() {
        let (results, state) = self.run(["Ready send it", "Ready send it to Bob", "Ready send it to Bob send it"])
        XCTAssertEqual(results, [true, false, true])
        XCTAssertEqual(state.armedText, "Ready send it to Bob send it")
    }

    func testArmingIsKeptAcrossTheStopPartial() {
        var state = SpokenSendArmingState()
        XCTAssertTrue(state.update(partial: "Ready send it", isEligible: true, phrase: "send it"))
        XCTAssertFalse(state.update(partial: "", isEligible: false, phrase: "send it"))
        XCTAssertTrue(state.wasArmed, "an ineligible partial must not forget the armed send")
        state.reset()
        XCTAssertFalse(state.wasArmed)
    }

    func testArmingNeverStartsFromANearMiss() {
        let (results, state) = self.run(["Ready sent it", "Ready sent it.", "Ready send"])
        XCTAssertEqual(results, [false, false, false])
        XCTAssertFalse(state.wasArmed)
    }

    func testArmingIgnoresPhraseInTheMiddle() {
        let (results, _) = self.run(["send it now please", "send it now please thanks"])
        XCTAssertEqual(results, [false, false])
    }

    func testArmingHoldsThroughPunctuationOnlyRefinements() {
        let (results, _) = self.run(["Ready send it", "Ready — send it …", "Ready, send it. —"])
        XCTAssertEqual(results, [true, true, true])
    }

    func testArmingWithCustomPhraseContainingRegexCharacters() {
        let (results, state) = self.run(["Done. ship it (now)", "Done. ship it (now"], phrase: "ship it (now)")
        XCTAssertEqual(results, [true, true])
        XCTAssertTrue(state.wasArmed)
    }

    func testArmingWithPunctuationOnlyPhraseDoesNotCrash() {
        var state = SpokenSendArmingState()
        _ = state.update(partial: "Hi !!!", isEligible: true, phrase: "!!!")
        _ = SpokenSendParser.parseArmed("Hi !!!", phrase: "!!!", enabled: true, wasArmed: true)
        _ = SpokenSendParser.parseArmed("Hi", phrase: "   ", enabled: true, wasArmed: true)
    }

    func testArmingStaysFastOnVeryLongPartials() {
        let long = Array(repeating: "word", count: 5000).joined(separator: " ") + " send it"
        var state = SpokenSendArmingState()
        let started = Date()
        for _ in 0..<20 {
            XCTAssertTrue(state.update(partial: long, isEligible: true, phrase: "send it"))
            XCTAssertTrue(state.update(partial: long + ".", isEligible: true, phrase: "send it"))
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1.0)
    }

    func testNearMissIsRefusedForVeryShortPhrases() {
        XCTAssertEqual(
            SpokenSendParser.parseArmed("The end", phrase: "send", enabled: true, wasArmed: true),
            SpokenSendParseResult(text: "The end", shouldSend: false)
        )
        XCTAssertEqual(
            SpokenSendParser.parseArmed("The send", phrase: "send", enabled: true, wasArmed: true),
            SpokenSendParseResult(text: "The.", shouldSend: true)
        )
    }

    func testNearMissAllowsOneEditForTwoWordPhrase() {
        for tail in ["sent it", "sand it", "send if", "sendit", "Send It"] {
            XCTAssertEqual(
                SpokenSendParser.parseArmed("Ready \(tail)", phrase: "send it", enabled: true, wasArmed: true),
                SpokenSendParseResult(text: "Ready.", shouldSend: true),
                tail
            )
        }
        for tail in ["sending", "send", "sent him", "end it", "spend a bit", "bend it", "tend it"] {
            XCTAssertFalse(SpokenSendParser.parseArmed("Ready \(tail)", phrase: "send it", enabled: true, wasArmed: true).shouldSend, tail)
        }
    }

    func testNearMissRequiresPhraseAtTheVeryEnd() {
        XCTAssertFalse(SpokenSendParser.parseArmed("Ready sent it now", phrase: "send it", enabled: true, wasArmed: true).shouldSend)
    }

    func testNearMissIsIgnoredWhenDisabledOrNotArmed() {
        XCTAssertFalse(SpokenSendParser.parseArmed("Ready sent it", phrase: "send it", enabled: false, wasArmed: true).shouldSend)
        XCTAssertFalse(SpokenSendParser.parseArmed("Ready sent it", phrase: "send it", enabled: true, wasArmed: false).shouldSend)
    }

    func testNearMissOnEmptyOrShortTextIsSafe() {
        XCTAssertEqual(SpokenSendParser.parseArmed("", phrase: "send it", enabled: true, wasArmed: true), SpokenSendParseResult(text: "", shouldSend: false))
        XCTAssertEqual(SpokenSendParser.parseArmed("it", phrase: "send it", enabled: true, wasArmed: true), SpokenSendParseResult(text: "it", shouldSend: false))
    }
}

// MARK: - Which apps get the key

final class SpokenSendPolicyTests: XCTestCase {
    func testC11IsAllowedAheadOfTheTerminalBlockList() {
        XCTAssertEqual(SpokenSendPolicy.verdict(bundleIdentifier: "com.stage11.c11", appName: "c11", allowsC11: true), .allowedC11)
        // Even when its identity would match a blocked term, c11 is decided by its bundle ID first.
        XCTAssertEqual(
            SpokenSendPolicy.verdict(bundleIdentifier: "com.stage11.c11", appName: "c11 (Ghostty Terminal)", allowsC11: true),
            .allowedC11
        )
        XCTAssertTrue(SpokenSendPolicy.Verdict.allowedC11.allowsSend)
    }

    func testTheC11ToggleTurnsItOff() {
        let verdict = SpokenSendPolicy.verdict(bundleIdentifier: "com.stage11.c11", appName: "c11", allowsC11: false)
        XCTAssertEqual(verdict, .c11Disabled)
        XCTAssertFalse(verdict.allowsSend)
    }

    func testEveryOtherTerminalIsBlocked() {
        let terminals: [(String, String)] = [
            ("com.apple.Terminal", "Terminal"),
            ("com.googlecode.iterm2", "iTerm2"),
            ("net.kovidgoyal.kitty", "kitty"),
            ("org.alacritty", "Alacritty"),
            ("dev.warp.Warp-Stable", "Warp"),
            ("com.mitchellh.ghostty", "Ghostty"),
            ("com.github.wez.wezterm", "WezTerm"),
            ("org.tabby", "Tabby"),
            ("co.zeit.hyper", "Hyper"),
            ("com.raphaelamorim.rio", "Rio"),
        ]
        for (bundleID, name) in terminals {
            for allowsC11 in [true, false] {
                let verdict = SpokenSendPolicy.verdict(bundleIdentifier: bundleID, appName: name, allowsC11: allowsC11)
                XCTAssertEqual(verdict, .blockedTerminal, bundleID)
                XCTAssertFalse(verdict.allowsSend, bundleID)
            }
        }
    }

    func testOrdinaryAppsAreAllowed() {
        for (bundleID, name) in [("com.tinyspeck.slackmacgap", "Slack"), ("com.apple.TextEdit", "TextEdit"), ("com.google.Chrome", "Google Chrome")] {
            XCTAssertEqual(SpokenSendPolicy.verdict(bundleIdentifier: bundleID, appName: name, allowsC11: false), .allowed, bundleID)
        }
        XCTAssertEqual(SpokenSendPolicy.verdict(bundleIdentifier: nil, appName: nil, allowsC11: true), .allowed)
    }

    func testC11AlwaysGetsAPlainReturn() {
        for key in SettingsStore.SpokenSendKey.allCases {
            XCTAssertEqual(SpokenSendPolicy.effectiveKey(key, verdict: .allowedC11), .enter, key.rawValue)
            XCTAssertEqual(SpokenSendPolicy.effectiveKey(key, verdict: .allowed), key, key.rawValue)
        }
    }

    func testAvailableSendKeysMapToExpectedFlags() {
        XCTAssertEqual(SettingsStore.SpokenSendKey.enter.eventFlags, [])
        XCTAssertEqual(SettingsStore.SpokenSendKey.shiftEnter.eventFlags, .maskShift)
        XCTAssertEqual(SettingsStore.SpokenSendKey.commandEnter.eventFlags, .maskCommand)
    }

    /// Our own Return must never trigger a Liquid Voice hotkey. PR #2 passes every keystroke this
    /// process posts straight through the tap by its source PID; the send key's events are made
    /// by this process, so they carry it.
    func testTheSendKeyNeverTriggersAHotkey() throws {
        for key in SettingsStore.SpokenSendKey.allCases {
            let events = SendKeyEvents.make(key)
            XCTAssertEqual(events.count, 2, key.rawValue)
            let (down, up) = try (XCTUnwrap(events.first), XCTUnwrap(events.last))
            XCTAssertEqual(down.getIntegerValueField(.keyboardEventKeycode), 36, "Return")
            XCTAssertEqual(down.flags.intersection([.maskShift, .maskCommand, .maskAlternate, .maskControl]), key.eventFlags)
            XCTAssertTrue(GlobalHotkeyManager.isSelfPostedKeyboardEvent(type: .keyDown, event: down), key.rawValue)
            XCTAssertTrue(GlobalHotkeyManager.isSelfPostedKeyboardEvent(type: .keyUp, event: up), key.rawValue)
            XCTAssertTrue(PasteCommandEvents.isSynthesized(down))
        }
        // A real keystroke from another process still reaches the hotkey matching.
        let physical = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 36, keyDown: true))
        physical.setIntegerValueField(.eventSourceUnixProcessID, value: 0)
        XCTAssertFalse(GlobalHotkeyManager.isSelfPostedKeyboardEvent(type: .keyDown, event: physical))
    }

    func testTheKeyInAnOrdinaryAppNeedsFocusStillInItAndATextField() {
        let editable = (assessment: DeliveryTargetAssessment.editable(role: "AXTextArea"), isSecure: false)
        XCTAssertNil(TypingService.sendKeyVerdict(targetPID: 42, focusedPID: 42, focus: editable))
        XCTAssertNil(
            TypingService.sendKeyVerdict(targetPID: 42, focusedPID: 42, focus: (.unknown(reason: "role_AXGroup"), false)),
            "an ambiguous element gets the key, as it got the text"
        )
        XCTAssertEqual(TypingService.sendKeyVerdict(targetPID: 42, focusedPID: 43, focus: editable), .targetNotInFront)
        XCTAssertEqual(TypingService.sendKeyVerdict(targetPID: 42, focusedPID: nil, focus: editable), .targetNotInFront)
        XCTAssertEqual(
            TypingService.sendKeyVerdict(targetPID: 42, focusedPID: 42, focus: (.editable(role: "AXTextField"), true)),
            .secureField
        )
        XCTAssertEqual(
            TypingService.sendKeyVerdict(targetPID: 42, focusedPID: 42, focus: (.notEditable(role: "AXButton"), false)),
            .focusNotEditable,
            "Return must never press a focused button"
        )
    }

    func testOnlyASentKeyCountsAsSent() {
        XCTAssertTrue(SendKeyOutcome.sent.wasSent)
        for outcome in [SendKeyOutcome.textNotDelivered, .targetNotInFront, .focusNotEditable, .secureField, .modifiersHeld, .targetMismatch, .eventsUnavailable] {
            XCTAssertFalse(outcome.wasSent, outcome.rawValue)
        }
    }

    @MainActor
    func testSettingsDefaultsAndBackupIncludeSpokenSend() async {
        let settings = SettingsStore.shared
        let original = SpokenSendController.Configuration.current()
        defer {
            settings.spokenSendEnabled = original.enabled
            settings.spokenSendImmediatelyEnabled = original.stopsAfterPause
            settings.spokenSendPhrase = original.phrase
            settings.spokenSendKey = original.key
            settings.spokenSendAllowsC11 = original.allowsC11
        }

        settings.spokenSendEnabled = true
        settings.spokenSendImmediatelyEnabled = false
        settings.spokenSendPhrase = "ship it"
        settings.spokenSendKey = .commandEnter
        settings.spokenSendAllowsC11 = false

        let document = await BackupService.shared.makeBackupDocument()
        XCTAssertEqual(document.settings.spokenSendEnabled, true)
        XCTAssertEqual(document.settings.spokenSendImmediatelyEnabled, false)
        XCTAssertEqual(document.settings.spokenSendPhrase, "ship it")
        XCTAssertEqual(document.settings.spokenSendKey, .commandEnter)
        XCTAssertEqual(document.settings.spokenSendAllowsC11, false)

        settings.spokenSendEnabled = false
        settings.spokenSendAllowsC11 = true
        settings.restore(from: document.settings)
        XCTAssertTrue(settings.spokenSendEnabled)
        XCTAssertFalse(settings.spokenSendAllowsC11)
    }
}

// MARK: - The dictation-side controller: countdown, cancel, decision

@MainActor
final class SpokenSendControllerTests: XCTestCase {
    private var controller: SpokenSendController!
    private var clock: TimeInterval = 1000
    private var isDictating = true
    private var recordingApp: (bundleIdentifier: String?, name: String?)? = ("com.stage11.c11", "c11")
    private var stops = 0
    private var config = SpokenSendController.Configuration(enabled: true, phrase: "send it", stopsAfterPause: true, key: .enter, allowsC11: true)

    override func setUp() async throws {
        try await super.setUp()
        let controller = SpokenSendController()
        controller.configuration = { [unowned self] in self.config }
        controller.now = { [unowned self] in self.clock }
        controller.settleDuration = 0.05
        controller.attach(
            partials: Empty().eraseToAnyPublisher(),
            audioLevels: Empty().eraseToAnyPublisher(),
            hooks: SpokenSendController.Hooks(
                isDictating: { [unowned self] in self.isDictating },
                recordingApp: { [unowned self] in self.recordingApp },
                stopAndProcess: { [unowned self] in self.stops += 1 }
            )
        )
        controller.beginRecording()
        self.controller = controller
    }

    override func tearDown() async throws {
        // Ends any countdown a test left running.
        self.controller.beginRecording()
        self.controller = nil
        try await super.tearDown()
    }

    /// Lets the countdown's sleep run out, with the clock moved past the required silence.
    private func letCountdownRunOut(quietFor seconds: TimeInterval = 1.0) async {
        self.clock += seconds
        try? await Task.sleep(nanoseconds: 250_000_000)
    }

    func testAQuietCountdownStopsTheDictationOnce() async {
        self.controller.handlePartial("Fix the typo in the README, send it")
        XCTAssertEqual(self.controller.indicator, .countingDown)
        await self.letCountdownRunOut()
        XCTAssertEqual(self.stops, 1)
        // Later partials of the same recording never start another countdown.
        self.controller.handlePartial("Fix the typo in the README, send it.")
        await self.letCountdownRunOut()
        XCTAssertEqual(self.stops, 1)
    }

    func testTheCountdownCanNeverFireAfterANewDictationStarted() async {
        self.controller.handlePartial("Fix the typo, send it")
        XCTAssertEqual(self.controller.indicator, .countingDown)
        self.controller.beginRecording()
        XCTAssertEqual(self.controller.indicator, .hidden)
        await self.letCountdownRunOut()
        XCTAssertEqual(self.stops, 0, "the old countdown must not stop the new dictation")
    }

    func testTheCountdownDoesNotFireOnceTheDictationStopped() async {
        self.controller.handlePartial("Fix the typo, send it")
        self.isDictating = false // the stop hotkey ran first
        await self.letCountdownRunOut()
        XCTAssertEqual(self.stops, 0)
    }

    func testCancelFromTheOverlayStopsTheCountdownAndTheSend() async {
        self.controller.handlePartial("Fix the typo, send it")
        self.controller.cancelSend()
        XCTAssertEqual(self.controller.indicator, .canceled)
        await self.letCountdownRunOut()
        XCTAssertEqual(self.stops, 0)
        // Saying it again later in the same dictation does not undo the cancel.
        self.controller.handlePartial("Fix the typo, send it, send it")
        XCTAssertEqual(self.controller.indicator, .canceled)
        let decision = self.controller.finishDictation("Fix the typo, send it.", isNormalRoute: true)
        XCTAssertEqual(decision, SpokenSendDecision(text: "Fix the typo.", phraseDetected: true, shouldSend: false))
    }

    func testSpeakingOnCancelsTheCountdown() async {
        self.controller.handlePartial("I'll send it")
        self.clock += SpokenSendParser.immediateStopVoiceActivityGraceDuration + 0.1
        self.controller.handleVoiceLevel(0.5)
        XCTAssertEqual(self.controller.indicator, .armed)
        await self.letCountdownRunOut()
        XCTAssertEqual(self.stops, 0)
        // The next words disarm it for good.
        self.controller.handlePartial("I'll send it tomorrow")
        XCTAssertEqual(self.controller.indicator, .hidden)
        XCTAssertEqual(
            self.controller.finishDictation("I'll send it tomorrow.", isNormalRoute: true),
            SpokenSendDecision(text: "I'll send it tomorrow.", phraseDetected: false, shouldSend: false)
        )
    }

    func testTheTailOfThePhraseItselfDoesNotCancelTheCountdown() async {
        self.controller.handlePartial("Ship it, send it")
        self.clock += 0.05
        self.controller.handleVoiceLevel(0.5) // still the end of "send it"
        XCTAssertEqual(self.controller.indicator, .countingDown)
    }

    func testWithoutTheCountdownThePhraseOnlyArms() async {
        self.config.stopsAfterPause = false
        self.controller.handlePartial("Ship it, send it")
        XCTAssertEqual(self.controller.indicator, .armed)
        await self.letCountdownRunOut()
        XCTAssertEqual(self.stops, 0)
        // An armed send accepts a noisy final decode.
        XCTAssertEqual(
            self.controller.finishDictation("Ship it, sent it.", isNormalRoute: true),
            SpokenSendDecision(text: "Ship it.", phraseDetected: true, shouldSend: true)
        )
    }

    func testABlockedTerminalShowsAHollowPlaneButStillStripsThePhrase() {
        self.config.stopsAfterPause = false
        self.recordingApp = ("com.apple.Terminal", "Terminal")
        self.controller.handlePartial("ls -la send it")
        XCTAssertEqual(self.controller.indicator, .armed)
        XCTAssertFalse(self.controller.sendsInRecordingApp)
    }

    func testThePhraseOnlyDictationSendsTheDraft() {
        let decision = self.controller.finishDictation("Send it.", isNormalRoute: true)
        XCTAssertTrue(decision.isPhraseOnly)
        XCTAssertTrue(decision.shouldSend)
    }

    func testDisabledOrSandboxedDictationsAreLeftAlone() {
        XCTAssertEqual(
            self.controller.finishDictation("Onboarding, send it.", isNormalRoute: false),
            .unchanged("Onboarding, send it.")
        )
        self.config.enabled = false
        self.controller.handlePartial("Anything, send it")
        XCTAssertEqual(self.controller.indicator, .hidden)
        XCTAssertEqual(self.controller.finishDictation("Anything, send it.", isNormalRoute: true), .unchanged("Anything, send it."))
    }

    func testTheKeyGoesOnlyWhereThePolicyAllowsIt() {
        let send = SpokenSendDecision(text: "Fix it.", phraseDetected: true, shouldSend: true)
        let c11 = DictationTarget(pid: 99901, bundleIdentifier: "com.stage11.c11", window: nil, element: nil)
        let terminal = DictationTarget(pid: 99902, bundleIdentifier: "com.apple.Terminal", window: nil, element: nil)
        let slack = DictationTarget(pid: 99903, bundleIdentifier: "com.tinyspeck.slackmacgap", window: nil, element: nil)

        self.config.key = .commandEnter
        let c11Request = self.controller.sendKeyRequest(for: send, target: c11, aiFailed: false)
        XCTAssertEqual(c11Request?.target.pid, 99901)
        XCTAssertEqual(c11Request?.key, .enter, "c11 always gets a plain Return")
        XCTAssertEqual(self.controller.sendKeyRequest(for: send, target: slack, aiFailed: false)?.key, .commandEnter)

        XCTAssertNil(self.controller.sendKeyRequest(for: send, target: terminal, aiFailed: false))
        XCTAssertNil(self.controller.sendKeyRequest(for: send, target: nil, aiFailed: false))
        XCTAssertNil(self.controller.sendKeyRequest(for: send, target: c11, aiFailed: true), "never submit an AI fallback")
        let own = DictationTarget(pid: ProcessInfo.processInfo.processIdentifier, bundleIdentifier: nil, window: nil, element: nil)
        XCTAssertNil(self.controller.sendKeyRequest(for: send, target: own, aiFailed: false))
        let canceled = SpokenSendDecision(text: "Fix it.", phraseDetected: true, shouldSend: false)
        XCTAssertNil(self.controller.sendKeyRequest(for: canceled, target: c11, aiFailed: false))

        self.config.allowsC11 = false
        XCTAssertNil(self.controller.sendKeyRequest(for: send, target: c11, aiFailed: false))
    }

    func testTheOverlayIndicatorVisibility() {
        XCTAssertFalse(SpokenSendController.Indicator.hidden.isVisible)
        XCTAssertTrue(SpokenSendController.Indicator.armed.isVisible)
        XCTAssertTrue(SpokenSendController.Indicator.countingDown.isVisible)
        XCTAssertTrue(SpokenSendController.Indicator.canceled.isVisible)
    }
}
