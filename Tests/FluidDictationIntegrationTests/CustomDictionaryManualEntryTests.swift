@testable import MouthKeys_Debug
import Foundation
import XCTest

@MainActor
final class CustomDictionaryManualEntryTests: XCTestCase {
    func testKeepsWhitespaceOnlyReplacements() {
        XCTAssertEqual(CustomDictionaryManualEntry.sanitizedReplacement("\n"), "\n")
        XCTAssertEqual(CustomDictionaryManualEntry.sanitizedReplacement(" "), " ")
        XCTAssertEqual(CustomDictionaryManualEntry.sanitizedReplacement("\t"), "\t")
        XCTAssertEqual(CustomDictionaryManualEntry.sanitizedReplacement(""), "")
        XCTAssertEqual(CustomDictionaryManualEntry.sanitizedReplacement("  FluidVoice \n"), "FluidVoice")
    }

    func testRendersWhitespaceReplacementsVisibly() {
        XCTAssertEqual(CustomDictionaryManualEntry.replacementDisplayText("\n"), "⏎")
        XCTAssertEqual(CustomDictionaryManualEntry.replacementDisplayText(" "), "␣")
        XCTAssertEqual(CustomDictionaryManualEntry.replacementDisplayText("\t"), "⇥")
        XCTAssertEqual(CustomDictionaryManualEntry.replacementDisplayText(" \n"), "␣⏎")
        XCTAssertEqual(CustomDictionaryManualEntry.replacementDisplayText("FluidVoice"), "FluidVoice")
        XCTAssertEqual(CustomDictionaryManualEntry.replacementDisplayText(""), "")
    }

    func testWhitespaceReplacementSurvivesTransferAndReplacement() throws {
        let document = DictionaryTransferDocument(
            replacements: [DictionaryTransferReplacement(from: ["new line"], to: "\n")],
            customWords: []
        )

        let data = try DictionaryTransferService.shared.encode(document)
        let decoded = try DictionaryTransferService.shared.decode(data)
        let state = try DictionaryTransferService.importState(
            document: decoded,
            mode: .replace,
            currentReplacements: [],
            currentCustomWords: []
        )

        XCTAssertEqual(state.replacements.first?.replacement, "\n")
        self.withRestoredDictionary(state.replacements) {
            XCTAssertEqual(ASRService.applyCustomDictionary("first new line second"), "first\nsecond")
        }
    }

    func testWhitespaceReplacementsOwnAdjacentHorizontalSeparators() {
        let entries = [
            SettingsStore.CustomDictionaryEntry(triggers: ["new line"], replacement: "\n"),
            SettingsStore.CustomDictionaryEntry(triggers: ["new paragraph"], replacement: "\n\n"),
            SettingsStore.CustomDictionaryEntry(triggers: ["tab over"], replacement: "\t"),
            SettingsStore.CustomDictionaryEntry(triggers: ["little space"], replacement: " "),
        ]

        self.withRestoredDictionary(entries) {
            XCTAssertEqual(ASRService.applyCustomDictionary("first new line second"), "first\nsecond")
            XCTAssertEqual(ASRService.applyCustomDictionary("first  new paragraph  second"), "first\n\nsecond")
            XCTAssertEqual(ASRService.applyCustomDictionary("first tab over second"), "first\tsecond")
            XCTAssertEqual(ASRService.applyCustomDictionary("first   little space   second"), "first second")
            XCTAssertEqual(ASRService.applyCustomDictionary("first\n  new line  second"), "first\n\nsecond")
        }
    }

    func testTransferStillRejectsEmptyAndTrimsVisibleReplacement() throws {
        let document = DictionaryTransferDocument(
            replacements: [
                DictionaryTransferReplacement(from: ["empty"], to: ""),
                DictionaryTransferReplacement(from: ["fluid voice"], to: " FluidVoice \n"),
            ],
            customWords: []
        )

        let decoded = try DictionaryTransferService.shared.decode(DictionaryTransferService.shared.encode(document))

        XCTAssertEqual(decoded.replacements.count, 1)
        XCTAssertEqual(decoded.replacements.first?.to, "FluidVoice")
    }

    func testLocalAPIAcceptsWhitespaceReplacementAndRejectsEmpty() async throws {
        let body = Data(#"{"mode":"replace","entries":[{"triggers":["new line"],"replacement":"\n"},{"triggers":["empty"],"replacement":""}]}"#.utf8)
        let request = LocalAPI.Request(
            method: "POST",
            path: "/v1/dictionary/replacements",
            query: [:],
            headers: ["content-type": "application/json"],
            body: body
        )

        try await self.withRestoredDictionaryAsync {
            let response = await DictionaryAPIController().handle(request)

            XCTAssertEqual(response.status, 200)
            XCTAssertEqual(SettingsStore.shared.customDictionaryEntries.count, 1)
            XCTAssertEqual(SettingsStore.shared.customDictionaryEntries.first?.triggers, ["new line"])
            XCTAssertEqual(SettingsStore.shared.customDictionaryEntries.first?.replacement, "\n")
        }
    }

    private func withRestoredDictionary(_ entries: [SettingsStore.CustomDictionaryEntry], run: () -> Void) {
        let original = SettingsStore.shared.customDictionaryEntries
        defer {
            SettingsStore.shared.customDictionaryEntries = original
            ASRService.invalidateDictionaryCache()
        }
        SettingsStore.shared.customDictionaryEntries = entries
        ASRService.invalidateDictionaryCache()
        run()
    }

    private func withRestoredDictionaryAsync(run: () async throws -> Void) async throws {
        let original = SettingsStore.shared.customDictionaryEntries
        defer {
            SettingsStore.shared.customDictionaryEntries = original
            ASRService.invalidateDictionaryCache()
        }
        try await run()
    }
}

final class RegionalFillerOfferTests: XCTestCase {
    private let us = Locale(identifier: "en_US")
    private let defaults = SettingsStore.defaultFillerWords

    private func zone(_ identifier: String) -> TimeZone {
        TimeZone(identifier: identifier)!
    }

    private func offer(
        locale: Locale? = nil,
        zone identifier: String,
        fillerWords: [String]? = nil,
        answered: Bool = false,
        removalEnabled: Bool = true,
        dictation: String? = nil
    ) -> RegionalFillerOffer? {
        RegionalFillerOffer.offer(
            fillerWords: fillerWords ?? self.defaults,
            answered: answered,
            removalEnabled: removalEnabled,
            dictation: dictation,
            locale: locale ?? self.us,
            timeZone: self.zone(identifier)
        )
    }

    func testCanadianRegionCounts() {
        XCTAssertEqual(self.offer(locale: Locale(identifier: "en_CA"), zone: "America/Los_Angeles")?.region, .canada)
    }

    func testCanadianTimeZoneCountsEvenWithUSRegion() {
        XCTAssertEqual(self.offer(zone: "America/Toronto")?.region, .canada)
        XCTAssertEqual(self.offer(zone: "America/Winnipeg")?.region, .canada)
    }

    func testSameOffsetUSEasternZoneGetsNothing() {
        XCTAssertNil(self.offer(zone: "America/New_York"))
        XCTAssertNil(self.offer(zone: "America/Los_Angeles"))
    }

    func testCentralTimeAsksAboutMinnesota() {
        let offer = self.offer(zone: "America/Chicago")
        XCTAssertEqual(offer?.region, .minnesota)
        XCTAssertEqual(offer?.word, "eh")
        XCTAssertTrue(offer?.message.hasPrefix("Minnesota, by any chance?") ?? false)
    }

    func testDictatedOpeMakesMinnesotaSure() {
        for dictation in ["Ope, let me just sneak past ya.", "oop sorry", "Uff da that's cold.", "You betcha."] {
            let offer = self.offer(zone: "America/Chicago", dictation: dictation)
            XCTAssertTrue(offer?.message.hasPrefix("Ope, sounds like Minnesota.") ?? false, dictation)
        }
        XCTAssertFalse(RegionalFillerOffer.soundsMinnesotan("I hope the scope is open."))
    }

    func testOpeOutsideCentralTimeGetsNothing() {
        XCTAssertNil(self.offer(zone: "America/New_York", dictation: "Ope, sorry."))
    }

    func testCanadaWinsOverMinnesota() {
        XCTAssertEqual(
            self.offer(locale: Locale(identifier: "en_CA"), zone: "America/Chicago", dictation: "Ope")?.region,
            .canada
        )
    }

    func testEveryListedZoneResolves() {
        let zones = RegionalFillerOffer.canadianTimeZoneIdentifiers
            .union(RegionalFillerOffer.usCentralTimeZoneIdentifiers)
        for identifier in zones {
            XCTAssertNotNil(TimeZone(identifier: identifier), identifier)
        }
    }

    func testOffersOnlyWhileWordIsRemovedAndUnanswered() {
        XCTAssertNotNil(self.offer(zone: "America/Toronto"))
        XCTAssertNil(self.offer(zone: "America/Toronto", answered: true))
        XCTAssertNil(self.offer(zone: "America/Toronto", fillerWords: ["um"]))
        XCTAssertNil(self.offer(zone: "America/Toronto", removalEnabled: false))
    }

    func testDefaultFillerListStillRemovesEh() {
        XCTAssertTrue(SettingsStore.defaultFillerWords.contains("eh"))
    }
}
