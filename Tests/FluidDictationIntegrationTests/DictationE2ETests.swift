@testable import Liquid_Voice_Debug
import Combine
import Foundation
import SwiftUI
import XCTest

@MainActor
final class DictationE2ETests: XCTestCase {
    private let enableTranscriptionSoundsKey = "EnableTranscriptionSounds"
    private let transcriptionStartSoundKey = "TranscriptionStartSound"
    private let dictationPromptProfilesKey = "DictationPromptProfiles"
    private let appPromptBindingsKey = "AppPromptBindings"
    private let selectedDictationPromptIDKey = "SelectedDictationPromptID"
    private let selectedEditPromptIDKey = "SelectedEditPromptID"
    private let dictationPromptOffKey = "DictationPromptOff"
    private let editPromptOffKey = "EditPromptOff"
    private let defaultDictationPromptOverrideKey = "DefaultDictationPromptOverride"
    private let defaultEditPromptOverrideKey = "DefaultEditPromptOverride"
    private let dictationPromptRoutingScopeKey = "DictationPromptRoutingScope"
    private let savedProvidersKey = "SavedProviders"
    private let selectedProviderIDKey = "SelectedProviderID"
    private let selectedAIModelKey = "SelectedAIModel"
    private let availableModelsByProviderKey = "AvailableModelsByProvider"
    private let selectedModelByProviderKey = "SelectedModelByProvider"
    private let dictationPromptConfigurationsKey = "DictationPromptConfigurations"
    private let customDictionaryEntriesKey = "CustomDictionaryEntries"
    private let autoConvertPunctuationEnabledKey = "AutoConvertPunctuationEnabled"
    private let literalDictationFormattingEnabledKey = "LiteralDictationFormattingEnabled"
    private let punctuationDictionaryPrefixKey = "PunctuationDictionaryPrefix"
    private let punctuationDictionaryRulesKey = "PunctuationDictionaryRules"
    private let spokenFormattingActionRulesKey = "SpokenFormattingActionRules"
    private let commandModeLinkedToGlobalKey = "CommandModeLinkedToGlobal"
    private let commandModeSelectedProviderIDKey = "CommandModeSelectedProviderID"
    private let commandModeSelectedModelKey = "CommandModeSelectedModel"
    private let rewriteModeSelectedProviderIDKey = "RewriteModeSelectedProviderID"
    private let rewriteModeSelectedModelKey = "RewriteModeSelectedModel"
    private let secondaryDictationPromptOffKey = "SecondaryDictationPromptOff"
    private let promptModeSelectedPromptIDKey = "PromptModeSelectedPromptID"

    private let verifiedProviderFingerprintsKey = "VerifiedProviderFingerprints"

    private var punctuationFormattingDefaultsKeys: [String] {
        [
            self.autoConvertPunctuationEnabledKey,
            self.punctuationDictionaryPrefixKey,
            self.punctuationDictionaryRulesKey,
            self.spokenFormattingActionRulesKey,
        ]
    }

    func testTranscriptionHistoryEntryClipboardTextPrefersProcessedText() {
        let entry = TranscriptionHistoryEntry(
            rawText: " raw transcript ",
            processedText: " processed transcript ",
            appName: "Notes",
            windowTitle: "Draft",
            wasAIProcessed: true
        )

        XCTAssertEqual(entry.clipboardText, "processed transcript")
    }

    func testTranscriptionHistoryEntryClipboardTextFallsBackToRawText() {
        let entry = TranscriptionHistoryEntry(
            rawText: " raw transcript ",
            processedText: "   ",
            appName: "Notes",
            windowTitle: "Draft",
            wasAIProcessed: false
        )

        XCTAssertEqual(entry.clipboardText, "raw transcript")
    }

    func testTranscriptionHistoryEntryClipboardTextSkipsEmptyText() {
        let entry = TranscriptionHistoryEntry(
            rawText: "   ",
            processedText: "   ",
            appName: "Notes",
            windowTitle: "Draft",
            wasAIProcessed: false
        )

        XCTAssertNil(entry.clipboardText)
    }

    func testTranscriptionStartSound_noneOptionHasNoFile() {
        XCTAssertEqual(SettingsStore.TranscriptionStartSound.none.displayName, "None")
        XCTAssertNil(SettingsStore.TranscriptionStartSound.none.startSoundFileName)
    }

    func testTranscriptionStartSound_legacyDisabledToggleMigratesToNone() {
        self.withRestoredDefaults(keys: [self.enableTranscriptionSoundsKey, self.transcriptionStartSoundKey]) {
            let defaults = UserDefaults.standard
            defaults.set(false, forKey: self.enableTranscriptionSoundsKey)
            defaults.set(SettingsStore.TranscriptionStartSound.fluidSfx1.rawValue, forKey: self.transcriptionStartSoundKey)

            let value = SettingsStore.shared.transcriptionStartSound

            XCTAssertEqual(value, .none)
            XCTAssertNil(defaults.object(forKey: self.enableTranscriptionSoundsKey))
            XCTAssertEqual(defaults.string(forKey: self.transcriptionStartSoundKey), SettingsStore.TranscriptionStartSound.none.rawValue)
        }
    }

    func testTranscriptionStartSound_legacyEnabledToggleKeepsSelectedSound() {
        self.withRestoredDefaults(keys: [self.enableTranscriptionSoundsKey, self.transcriptionStartSoundKey]) {
            let defaults = UserDefaults.standard
            defaults.set(true, forKey: self.enableTranscriptionSoundsKey)
            defaults.set(SettingsStore.TranscriptionStartSound.fluidSfx2.rawValue, forKey: self.transcriptionStartSoundKey)

            let value = SettingsStore.shared.transcriptionStartSound

            XCTAssertEqual(value, .fluidSfx2)
            XCTAssertNil(defaults.object(forKey: self.enableTranscriptionSoundsKey))
            XCTAssertEqual(defaults.string(forKey: self.transcriptionStartSoundKey), SettingsStore.TranscriptionStartSound.fluidSfx2.rawValue)
        }
    }

    func testDictionaryTransferDocument_encodesSimpleUserFormat() throws {
        let document = DictionaryTransferDocument(
            replacements: [
                DictionaryTransferReplacement(from: ["fluid voice", "fluid boys"], to: "FluidVoice"),
            ],
            customWords: ["FluidVoice", "GEMBA-E"]
        )

        let data = try DictionaryTransferService.shared.encode(document)
        let json = String(data: data, encoding: .utf8) ?? ""
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let replacements = try XCTUnwrap(root["replacements"] as? [[String: Any]])
        let firstReplacement = try XCTUnwrap(replacements.first)

        XCTAssertEqual(firstReplacement["from"] as? [String], ["fluid voice", "fluid boys"])
        XCTAssertEqual(firstReplacement["to"] as? String, "FluidVoice")
        XCTAssertEqual(root["customWords"] as? [String], ["FluidVoice", "GEMBA-E"])
        XCTAssertFalse(json.contains("\"triggers\""))
        XCTAssertFalse(json.contains("\"replacement\""))
        XCTAssertFalse(json.contains("\"aliases\""))
    }

    func testDictionaryTransferImport_replaceMapsSimpleFormatToStores() throws {
        let document = DictionaryTransferDocument(
            replacements: [
                DictionaryTransferReplacement(from: [" Fluid Voice ", "FLUID BOYS", ""], to: " FluidVoice "),
            ],
            customWords: [" FluidVoice ", "fluidvoice", " Barath "]
        )
        let existingReplacement = SettingsStore.CustomDictionaryEntry(triggers: ["old"], replacement: "Old")
        let existingWord = ParakeetVocabularyStore.VocabularyConfig.Term(text: "OldWord", weight: 13.0)

        let state = try DictionaryTransferService.importState(
            document: document,
            mode: .replace,
            currentReplacements: [existingReplacement],
            currentCustomWords: [existingWord]
        )

        XCTAssertEqual(state.replacements.count, 1)
        XCTAssertEqual(state.replacements.first?.triggers, ["fluid voice", "fluid boys"])
        XCTAssertEqual(state.replacements.first?.replacement, "FluidVoice")
        XCTAssertEqual(state.customWords.map(\.text), ["FluidVoice", "Barath"])
        XCTAssertEqual(state.customWords.map(\.weight), [10.0, 10.0])
        XCTAssertEqual(state.customWords.map(\.aliases), [[], []])
    }

    func testDictionaryTransferImport_mergeDedupesAndMovesDuplicateTriggers() throws {
        let oldReplacement = SettingsStore.CustomDictionaryEntry(
            triggers: ["fluid voice", "old trigger"],
            replacement: "Old"
        )
        let existingReplacement = SettingsStore.CustomDictionaryEntry(
            triggers: ["fluid boys"],
            replacement: "FluidVoice"
        )
        let existingWord = ParakeetVocabularyStore.VocabularyConfig.Term(
            text: "Barath",
            weight: 13.0,
            aliases: ["barath w"]
        )
        let document = DictionaryTransferDocument(
            replacements: [
                DictionaryTransferReplacement(from: ["fluid voice", "fluid boys"], to: "FluidVoice"),
            ],
            customWords: ["barath", "GEMBA-E"]
        )

        let state = try DictionaryTransferService.importState(
            document: document,
            mode: .merge,
            currentReplacements: [oldReplacement, existingReplacement],
            currentCustomWords: [existingWord]
        )

        let fluidVoiceEntry = try XCTUnwrap(state.replacements.first { $0.replacement == "FluidVoice" })
        let oldEntry = try XCTUnwrap(state.replacements.first { $0.replacement == "Old" })
        let barathTerm = try XCTUnwrap(state.customWords.first { $0.text == "Barath" })
        let gembaeTerm = try XCTUnwrap(state.customWords.first { $0.text == "GEMBA-E" })

        XCTAssertEqual(Set(fluidVoiceEntry.triggers), Set(["fluid voice", "fluid boys"]))
        XCTAssertEqual(oldEntry.triggers, ["old trigger"])
        XCTAssertEqual(barathTerm.weight, 13.0)
        XCTAssertEqual(barathTerm.aliases, ["barath w"])
        XCTAssertEqual(gembaeTerm.weight, 10.0)
    }

    func testDictionaryTransferImport_acceptsAppStyleReplacementKeysAndSingleFromValue() throws {
        let json = """
        {
          "replacements": [
            {
              "from": "fluid voice",
              "to": "FluidVoice"
            },
            {
              "triggers": ["gemba e"],
              "replacement": "GEMBA-E"
            }
          ]
        }
        """

        let document = try DictionaryTransferService.shared.decode(Data(json.utf8))
        let state = try DictionaryTransferService.importState(
            document: document,
            mode: .replace,
            currentReplacements: [],
            currentCustomWords: []
        )

        XCTAssertEqual(state.replacements.map(\.triggers), [["fluid voice"], ["gemba e"]])
        XCTAssertEqual(state.replacements.map(\.replacement), ["FluidVoice", "GEMBA-E"])
    }

    func testDictionaryTransferImport_acceptsLocalAPIReplacementItemsResponse() throws {
        let json = """
        {
          "count": 1,
          "items": [
            {
              "triggers": ["fluid voice"],
              "replacement": "FluidVoice"
            }
          ]
        }
        """

        let document = try DictionaryTransferService.shared.decode(Data(json.utf8))
        let state = try DictionaryTransferService.importState(
            document: document,
            mode: .replace,
            currentReplacements: [],
            currentCustomWords: []
        )

        XCTAssertEqual(state.replacements.first?.triggers, ["fluid voice"])
        XCTAssertEqual(state.replacements.first?.replacement, "FluidVoice")
        XCTAssertEqual(state.customWords.count, 0)
    }

    func testDictionaryTransferImportFeedsActualReplacementPath() throws {
        defer { ASRService.invalidateDictionaryCache() }
        let document = DictionaryTransferDocument(
            replacements: [
                DictionaryTransferReplacement(from: ["fluid voice"], to: "FluidVoice"),
            ],
            customWords: []
        )
        let state = try DictionaryTransferService.importState(
            document: document,
            mode: .replace,
            currentReplacements: [],
            currentCustomWords: []
        )

        self.withRestoredDefaults(keys: [self.customDictionaryEntriesKey]) {
            SettingsStore.shared.customDictionaryEntries = state.replacements
            ASRService.invalidateDictionaryCache()

            XCTAssertEqual(
                ASRService.applyCustomDictionary("I use fluid voice daily."),
                "I use FluidVoice daily."
            )
        }
    }

    func testCustomDictionaryReplacementTreatsReplacementTextLiterally() {
        defer { ASRService.invalidateDictionaryCache() }
        let entry = SettingsStore.CustomDictionaryEntry(
            triggers: ["dollar path"],
            replacement: #"$5 \path"#
        )

        self.withRestoredDefaults(keys: [self.customDictionaryEntriesKey]) {
            SettingsStore.shared.customDictionaryEntries = [entry]
            ASRService.invalidateDictionaryCache()

            XCTAssertEqual(
                ASRService.applyCustomDictionary("Use dollar path now."),
                #"Use $5 \path now."#
            )
        }
    }

    func testPronunciationDictionaryLabelsUseLastDuplicateEntry() {
        let id = UUID()
        let labels = FluidAudioProvider.dictionaryLabels(from: [
            SettingsStore.CustomDictionaryEntry(id: id, triggers: ["old"], replacement: "Old"),
            SettingsStore.CustomDictionaryEntry(id: id, triggers: ["new"], replacement: "New"),
        ])

        XCTAssertEqual(labels, [id: "New"])
    }

    func testCustomDictionaryReplacementMatchesPunctuationTriggers() {
        defer { ASRService.invalidateDictionaryCache() }
        let entry = SettingsStore.CustomDictionaryEntry(
            triggers: [",,", ","],
            replacement: ","
        )

        self.withRestoredDefaults(keys: [self.customDictionaryEntriesKey]) {
            SettingsStore.shared.customDictionaryEntries = [entry]
            ASRService.invalidateDictionaryCache()

            XCTAssertEqual(
                ASRService.applyCustomDictionary("Hello,, world."),
                "Hello, world."
            )
            XCTAssertEqual(
                ASRService.applyCustomDictionary("Hello, world."),
                "Hello, world."
            )
        }
    }

    func testSlashCommandFormattingLeavesNonCommandSlashUsageAlone() {
        let text = "Use 1/2 and and/or. Open src slash services. Go to https slash slash example dot com. Slash and burn."

        XCTAssertEqual(
            ASRService.applySlashCommandFormatting(text),
            text
        )
    }

    func testLiteralFormattingCanBeDisabled() {
        self.withRestoredDefaults(keys: [self.literalDictationFormattingEnabledKey]) {
            UserDefaults.standard.removeObject(forKey: self.literalDictationFormattingEnabledKey)
            XCTAssertFalse(SettingsStore.shared.literalDictationFormattingEnabled)

            UserDefaults.standard.set(false, forKey: self.literalDictationFormattingEnabledKey)

            XCTAssertEqual(ASRService.applySlashCommandFormatting("slash compact"), "slash compact")
            XCTAssertEqual(ASRService.applyMentionFormatting("mention Paul"), "mention Paul")
            XCTAssertEqual(
                ASRService.makeDictationLiteralOutputPlan(
                    for: "/compact ",
                    appName: "Codex",
                    bundleID: "com.openai.codex"
                ).plainText,
                "/compact "
            )
        }
    }

    func testMentionFormattingLeavesProseAlone() {
        let text = "I am at the store. Meet me at lunch. I am at Paul. Look at Paul's message."

        XCTAssertEqual(
            ASRService.applyMentionFormatting(text, appName: "Slack", bundleID: "com.tinyspeck.slackmacgap"),
            text
        )
    }

    func testMentionOutputPlanDoesNotAutoConfirmAutocomplete() {
        let plan = ASRService.makeDictationLiteralOutputPlan(
            for: "@Paul can you check this",
            appName: "Slack",
            bundleID: "com.tinyspeck.slackmacgap"
        )

        XCTAssertEqual(plan.steps, [.text("@Paul can you check this")])
        XCTAssertEqual(plan.plainText, "@Paul can you check this")
    }

    func testMentionOutputPlanStaysPlainOutsideMentionApps() {
        let text = "@Paul can you check this"

        XCTAssertEqual(
            ASRService.makeDictationLiteralOutputPlan(
                for: text,
                appName: "Notes",
                bundleID: "com.apple.Notes"
            ).steps,
            [.text(text)]
        )
    }

    func testSpokenPunctuationFormattingRequiresDictionaryPrefix() {
        self.withRestoredDefaults(keys: self.punctuationFormattingDefaultsKeys) {
            UserDefaults.standard.set(true, forKey: self.autoConvertPunctuationEnabledKey)

            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting(
                    "Hello literal comma world literal question mark literal open paren yes literal close paren literal quote done literal quote"
                ),
                "Hello, world? (yes) \"done\""
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("Hello comma world question mark"),
                "Hello comma world question mark"
            )
        }
    }

    func testSpokenPunctuationFormattingConvertsCodeAndContactPunctuationWithPrefix() {
        self.withRestoredDefaults(keys: self.punctuationFormattingDefaultsKeys) {
            UserDefaults.standard.set(true, forKey: self.autoConvertPunctuationEnabledKey)

            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting(
                    "email literal at the rate example literal dot com literal slash help literal underscore me"
                ),
                "email@example.com/help_me"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting(
                    "email literal at sign example literal dot com",
                    appName: "Codex",
                    bundleID: "com.openai.codex"
                ),
                "email@example.com"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("email at sign example"),
                "email at sign example"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("x literal hyphen ray costs 50 literal percent"),
                "x-ray costs 50%"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("a literal plus b literal equals c"),
                "a + b = c"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("plus equal percent"),
                "plus equal percent"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("literal plus literal equal 50 literal percent"),
                "+ = 50%"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("plus I need the normal word"),
                "plus I need the normal word"
            )
        }
    }

    func testSpokenPunctuationFormattingKeepsBareDotInProse() {
        self.withRestoredDefaults(keys: self.punctuationFormattingDefaultsKeys) {
            UserDefaults.standard.set(true, forKey: self.autoConvertPunctuationEnabledKey)

            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("the polka dot dress"),
                "the polka dot dress"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("example literal dot com"),
                "example.com"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("version 1 literal dot 2"),
                "version 1.2"
            )
        }
    }

    func testSpokenPunctuationFormattingCleansGeneratedCommaNoiseWithPrefix() {
        self.withRestoredDefaults(keys: self.punctuationFormattingDefaultsKeys) {
            UserDefaults.standard.set(true, forKey: self.autoConvertPunctuationEnabledKey)

            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("literal hyphen literal comma literal hyphen literal comma literal hyphen"),
                "---"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("50 literal comma literal percent"),
                "50%"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("literal open bracket literal comma literal close bracket"),
                "[]"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("literal open paren literal comma literal close paren"),
                "()"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("literal question mark literal comma literal exclamation mark"),
                "?!"
            )
        }
    }

    func testSpokenPunctuationFormattingPreservesExistingCommasNearSymbols() {
        self.withRestoredDefaults(keys: self.punctuationFormattingDefaultsKeys) {
            UserDefaults.standard.set(true, forKey: self.autoConvertPunctuationEnabledKey)

            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("Thanks, @Sam"),
                "Thanks, @Sam"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("Use C++, now"),
                "Use C++, now"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("-,-,-"),
                "-,-,-"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("50, %"),
                "50, %"
            )
        }
    }

    func testSpokenPunctuationFormattingRespectsSetting() {
        self.withRestoredDefaults(keys: self.punctuationFormattingDefaultsKeys) {
            UserDefaults.standard.set(false, forKey: self.autoConvertPunctuationEnabledKey)

            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("Hello literal comma world literal question mark"),
                "Hello literal comma world literal question mark"
            )
        }
    }

    func testSpokenPunctuationFormattingUsesCustomPrefixAndRules() {
        self.withRestoredDefaults(keys: self.punctuationFormattingDefaultsKeys) {
            let settings = SettingsStore.shared
            UserDefaults.standard.set(true, forKey: self.autoConvertPunctuationEnabledKey)
            settings.punctuationDictionaryPrefix = "type"
            settings.punctuationDictionaryRules = [
                SettingsStore.PunctuationDictionaryRule(
                    aliases: ["right arrow", "arrow"],
                    symbol: "->"
                ),
            ]

            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("type right arrow"),
                "->"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("literal right arrow"),
                "literal right arrow"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("type comma"),
                "type comma"
            )
        }
    }

    func testSpokenPunctuationFormattingUsesEditedRules() {
        self.withRestoredDefaults(keys: self.punctuationFormattingDefaultsKeys) {
            let settings = SettingsStore.shared
            UserDefaults.standard.set(true, forKey: self.autoConvertPunctuationEnabledKey)
            settings.punctuationDictionaryRules = [
                SettingsStore.PunctuationDictionaryRule(
                    aliases: ["full stop"],
                    symbol: "."
                ),
            ]

            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("literal full stop"),
                "."
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("literal period"),
                "literal period"
            )
        }
    }

    func testTerminalLiteralAutocompleteSpacingLeavesNonAutocompleteTextAlone() {
        XCTAssertEqual(
            ASRService.applyTerminalLiteralAutocompleteSpacing(
                "/model ",
                appName: "Notes",
                bundleID: "com.apple.Notes"
            ),
            "/model "
        )
        XCTAssertEqual(
            ASRService.applyTerminalLiteralAutocompleteSpacing(
                "Run /status please ",
                appName: "Codex",
                bundleID: "com.openai.codex"
            ),
            "Run /status please "
        )
        XCTAssertEqual(
            ASRService.applyTerminalLiteralAutocompleteSpacing(
                "@Paul can you check this ",
                appName: "Slack",
                bundleID: "com.tinyspeck.slackmacgap"
            ),
            "@Paul can you check this "
        )
    }

    func testSlashCommandOutputPlanDoesNotAutoConfirmAutocomplete() {
        XCTAssertEqual(
            ASRService.makeDictationLiteralOutputPlan(
                for: "/goal update the plan",
                appName: "Codex",
                bundleID: "com.openai.codex"
            ).steps,
            [.text("/goal update the plan")]
        )
        XCTAssertEqual(
            ASRService.makeDictationLiteralOutputPlan(
                for: "Run /status please",
                appName: "Codex",
                bundleID: "com.openai.codex"
            ).steps,
            [.text("Run /status please")]
        )
    }

    func testDictionaryTrainingNormalizesSamplesAndIgnoresIntendedText() {
        let triggers = CustomDictionaryTrainingMerge.normalizedTriggers(
            from: [" Fluid Voice. ", "FluidVoice", "fluid voice", " "],
            intendedReplacement: "FluidVoice"
        )

        XCTAssertEqual(triggers, ["fluid voice"])
    }

    func testDictionaryTrainingMergeDedupesAndMovesDuplicateTriggers() {
        let oldReplacement = SettingsStore.CustomDictionaryEntry(
            triggers: ["Fluid Voice.", "old trigger"],
            replacement: "Old"
        )
        let existingReplacement = SettingsStore.CustomDictionaryEntry(
            triggers: ["fluid boys"],
            replacement: "FluidVoice"
        )

        let entries = CustomDictionaryTrainingMerge.mergedEntries(
            current: [existingReplacement, oldReplacement],
            replacement: " fluidvoice ",
            triggers: ["Fluid Voice.", "fluid boys", "FluidVoice", ""]
        )

        let fluidVoiceEntry = entries.first { $0.replacement == "FluidVoice" }
        let oldEntry = entries.first { $0.replacement == "Old" }

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries.map(\.replacement), ["FluidVoice", "Old"])
        XCTAssertEqual(Set(fluidVoiceEntry?.triggers ?? []), Set(["fluid voice", "fluid boys"]))
        XCTAssertEqual(oldEntry?.triggers, ["old trigger"])
    }

    func testDictionaryTrainingNewReplacementPrependsEntry() {
        let existingReplacement = SettingsStore.CustomDictionaryEntry(
            triggers: ["existing trigger"],
            replacement: "Existing"
        )

        let entries = CustomDictionaryTrainingMerge.mergedEntries(
            current: [existingReplacement],
            replacement: "FluidVoice",
            triggers: ["fluid voice"]
        )

        XCTAssertEqual(entries.map(\.replacement), ["FluidVoice", "Existing"])
        XCTAssertEqual(entries.first?.triggers, ["fluid voice"])
    }

    func testManualDictionaryEntryParsesCommaSeparatedVariants() {
        XCTAssertEqual(
            CustomDictionaryManualEntry.normalizedDraftTriggers("fluid voice, fluid boys, fluid voice"),
            ["fluid voice", "fluid boys"]
        )
    }

    func testManualDictionaryEntryPreservesLiteralCommas() {
        XCTAssertEqual(CustomDictionaryManualEntry.normalizedDraftTriggers(","), [","])
        XCTAssertEqual(CustomDictionaryManualEntry.normalizedDraftTriggers(",,"), [",,"])
    }

    func testAutomaticDictionaryCorrectionDetectsEditedWordInsideDictation() {
        let before = "Notes: I met Barad yesterday."
        let after = "Notes: I met Barath yesterday."
        let insertedRange = (before as NSString).range(of: "I met Barad yesterday.")

        let candidate = AutomaticDictionaryCorrectionDetector.candidate(
            before: before,
            after: after,
            insertedRange: insertedRange
        )

        XCTAssertEqual(candidate?.heardText, "Barad")
        XCTAssertEqual(candidate?.correctedText, "Barath")
    }

    func testAutomaticDictionaryCorrectionDetectsInsertionOnlySpellingFix() {
        let before = "Barat joined the call"
        let after = "Barath joined the call"
        let insertedRange = NSRange(location: 0, length: (before as NSString).length)

        let candidate = AutomaticDictionaryCorrectionDetector.candidate(
            before: before,
            after: after,
            insertedRange: insertedRange
        )

        XCTAssertEqual(candidate?.heardText, "Barat")
        XCTAssertEqual(candidate?.correctedText, "Barath")
    }

    func testAutomaticDictionaryCorrectionDetectsInsertionAtDictationEnd() {
        let before = "Barat"
        let after = "Barath"
        let insertedRange = NSRange(location: 0, length: (before as NSString).length)
        let change = AutomaticDictionaryCorrectionDetector.textChange(before: before, after: after)

        XCTAssertNotNil(change)
        if let change {
            XCTAssertTrue(AutomaticDictionaryCorrectionDetector.isWordContinuationAtInsertedRangeEnd(
                change,
                after: after,
                insertedRange: insertedRange
            ))
        }
        let candidate = AutomaticDictionaryCorrectionDetector.candidate(
            before: before,
            after: after,
            insertedRange: insertedRange,
            allowsInsertionAtEnd: true
        )
        XCTAssertEqual(candidate?.heardText, "Barat")
        XCTAssertEqual(candidate?.correctedText, "Barath")
    }

    func testAutomaticDictionaryCorrectionRejectsNewWordAtDictationEnd() {
        let before = "FluidVoice works"
        let after = "FluidVoice works well"
        let insertedRange = NSRange(location: 0, length: (before as NSString).length)
        let change = AutomaticDictionaryCorrectionDetector.textChange(before: before, after: after)

        XCTAssertNotNil(change)
        if let change {
            XCTAssertFalse(AutomaticDictionaryCorrectionDetector.isWordContinuationAtInsertedRangeEnd(
                change,
                after: after,
                insertedRange: insertedRange
            ))
        }
    }

    func testPronunciationReplacementPreservesPunctuationAndSpacing() {
        let replacements = [
            FluidAudioProvider.PronunciationTextReplacement(wordRange: 1...1, label: "Barath"),
        ]

        XCTAssertEqual(
            FluidAudioProvider.applyingPronunciationReplacements(
                to: "Hi,  Barad! How are you?",
                wordTexts: ["Hi,", "Barad!", "How", "are", "you?"],
                replacements: replacements
            ),
            "Hi,  Barath! How are you?"
        )
    }

    func testPronunciationStoreRejectsInconsistentEnrollments() async {
        let store = PronunciationDictionaryStore()
        let enrollments = [
            PronunciationEnrollmentCapture(values: [1, 2], sourceFrameCount: 1, modelKey: "model-a"),
            PronunciationEnrollmentCapture(values: [1], sourceFrameCount: 1, modelKey: "model-b"),
        ]

        do {
            try await store.upsert(
                dictionaryEntryID: UUID(),
                label: "Barath",
                modelKey: "model-a",
                enrollments: enrollments
            )
            XCTFail("Expected inconsistent enrollment validation to fail")
        } catch {
            XCTAssertEqual(error as? PronunciationDictionaryStoreError, .inconsistentEnrollment)
        }
    }

    func testPronunciationStoreRetainsPriorEnrollmentsWhenRetrained() async throws {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PronunciationStore-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PronunciationDictionaryStore(fileURL: fileURL)
        let entryID = UUID()

        let initialEnrollments = (0..<8).map { value in
            PronunciationEnrollmentCapture(
                values: [Float(value), Float(value)],
                sourceFrameCount: 1,
                modelKey: "model-a"
            )
        }
        let retrainedEnrollments = (8..<13).map { value in
            PronunciationEnrollmentCapture(
                values: [Float(value), Float(value)],
                sourceFrameCount: 1,
                modelKey: "model-a"
            )
        }

        try await store.upsert(
            dictionaryEntryID: entryID,
            label: "Barath",
            modelKey: "model-a",
            enrollments: initialEnrollments
        )
        try await store.upsert(
            dictionaryEntryID: entryID,
            label: "Barath",
            modelKey: "model-a",
            enrollments: retrainedEnrollments
        )

        let profiles = await store.profiles(modelKey: "model-a")
        XCTAssertEqual(profiles.count, 1)
        XCTAssertEqual(profiles.first?.enrollments.compactMap(\.values.first), (3..<13).map { Float($0) })
    }

    func testPronunciationStoreRestoreRejectsMalformedProfiles() async {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("PronunciationStore-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }
        let store = PronunciationDictionaryStore(fileURL: fileURL)
        let malformedProfile = PronunciationDictionaryProfile(
            dictionaryEntryID: UUID(),
            label: "Barath",
            modelKey: "model-a",
            hiddenSize: 2,
            enrollments: [PronunciationEnrollmentCapture(values: [1], sourceFrameCount: 1, modelKey: "model-a")]
        )

        do {
            try await store.replaceAllProfiles([malformedProfile])
            XCTFail("Expected malformed profile validation to fail")
        } catch {
            XCTAssertEqual(error as? PronunciationDictionaryStoreError, .inconsistentEnrollment)
        }
    }

    func testPronunciationProfileEditPolicyDiscardsProfileWhenMeaningChanges() {
        XCTAssertTrue(
            PronunciationProfileEditPolicy.shouldDiscardProfile(
                previousReplacement: "Barath",
                updatedReplacement: "FluidVoice"
            )
        )
        XCTAssertFalse(
            PronunciationProfileEditPolicy.shouldDiscardProfile(
                previousReplacement: "Barath",
                updatedReplacement: "BARATH"
            )
        )
    }

    func testPronunciationMatchingRequiresSupportedAppleSiliconModel() {
        #if arch(arm64)
        XCTAssertTrue(SettingsStore.SpeechModel.parakeetTDT.supportsPronunciationMatching)
        XCTAssertTrue(SettingsStore.SpeechModel.parakeetTDTv2.supportsPronunciationMatching)
        #else
        XCTAssertFalse(SettingsStore.SpeechModel.parakeetTDT.supportsPronunciationMatching)
        XCTAssertFalse(SettingsStore.SpeechModel.parakeetTDTv2.supportsPronunciationMatching)
        #endif
        XCTAssertFalse(SettingsStore.SpeechModel.whisperLargeTurbo.supportsPronunciationMatching)
        XCTAssertFalse(SettingsStore.SpeechModel.cohereTranscribeSixBit.supportsPronunciationMatching)
    }

    func testDictionaryTrainingAudioCursorResetsAfterBufferGenerationChange() {
        var cursor = DictionaryTrainingAudioCursor(generation: 4)
        cursor.consume(1600)
        cursor.synchronize(generation: 4)
        XCTAssertEqual(cursor.sampleOffset, 1600)

        cursor.synchronize(generation: 5)
        XCTAssertEqual(cursor.sampleOffset, 0)
    }

    func testProgressiveDownloaderRetainsFileByMovingIt() throws {
        let source = FileManager.default.temporaryDirectory
            .appendingPathComponent("FluidVoiceDownloadSource-\(UUID().uuidString)")
        try Data([1, 2, 3]).write(to: source)
        let retained = try ProgressiveFileDownloader.retainDownloadedFile(at: source)
        defer { try? FileManager.default.removeItem(at: retained) }

        XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        XCTAssertEqual(try Data(contentsOf: retained), Data([1, 2, 3]))
    }

    func testAutomaticDictionaryCorrectionIgnoresTypingAfterDictation() {
        let before = "FluidVoice works"
        let after = "FluidVoice works well"
        let insertedRange = NSRange(location: 0, length: (before as NSString).length)

        XCTAssertNil(AutomaticDictionaryCorrectionDetector.candidate(
            before: before,
            after: after,
            insertedRange: insertedRange
        ))
    }

    func testAutomaticDictionaryCorrectionAllowsContinuedCorrectionAtRangeEnd() {
        let change = AutomaticDictionaryTextChange(
            oldRange: NSRange(location: 5, length: 0),
            newRange: NSRange(location: 5, length: 1)
        )
        let insertedRange = NSRange(location: 0, length: 5)

        XCTAssertFalse(AutomaticDictionaryCorrectionDetector.isChangeInsideInsertedRange(
            change,
            insertedRange: insertedRange
        ))
        XCTAssertTrue(AutomaticDictionaryCorrectionDetector.isChangeInsideInsertedRange(
            change,
            insertedRange: insertedRange,
            allowsInsertionAtEnd: true
        ))
    }

    func testAutomaticDictionaryCorrectionKeepsWaitingWhileCaretTouchesCorrectedWord() {
        let correctedRange = NSRange(location: 8, length: 6)

        XCTAssertTrue(AutomaticDictionaryCorrectionDetector.selectionTouchesCandidate(
            NSRange(location: 14, length: 0),
            candidateRange: correctedRange
        ))
        XCTAssertFalse(AutomaticDictionaryCorrectionDetector.selectionTouchesCandidate(
            NSRange(location: 15, length: 0),
            candidateRange: correctedRange
        ))
    }

    func testAutomaticDictionaryCorrectionTreatsSpaceAfterWordAsCompletion() {
        let change = AutomaticDictionaryTextChange(
            oldRange: NSRange(location: 6, length: 0),
            newRange: NSRange(location: 6, length: 1)
        )
        let correctedRange = NSRange(location: 0, length: 6)

        XCTAssertFalse(AutomaticDictionaryCorrectionDetector.changeContinuesCandidate(
            change,
            after: "Barath ",
            candidateRange: correctedRange
        ))
        XCTAssertTrue(AutomaticDictionaryCorrectionDetector.changeContinuesCandidate(
            change,
            after: "Baratha",
            candidateRange: correctedRange
        ))
    }

    func testAutomaticDictionaryCorrectionIgnoresEditOutsideDictation() {
        let before = "Title: I met Barad"
        let after = "Heading: I met Barad"
        let insertedRange = (before as NSString).range(of: "I met Barad")

        XCTAssertNil(AutomaticDictionaryCorrectionDetector.candidate(
            before: before,
            after: after,
            insertedRange: insertedRange
        ))
    }

    func testAutomaticDictionaryCorrectionIgnoresCaseOnlyEdit() {
        let before = "fluidvoice"
        let after = "FluidVoice"
        let insertedRange = NSRange(location: 0, length: (before as NSString).length)

        XCTAssertNil(AutomaticDictionaryCorrectionDetector.candidate(
            before: before,
            after: after,
            insertedRange: insertedRange
        ))
    }

    func testAutomaticDictionaryCorrectionIgnoresPunctuationAndSpacingOnlyEdit() {
        let before = "Use Fluid-Voice today"
        let after = "Use Fluid Voice today"
        let insertedRange = NSRange(location: 0, length: (before as NSString).length)

        XCTAssertNil(AutomaticDictionaryCorrectionDetector.candidate(
            before: before,
            after: after,
            insertedRange: insertedRange
        ))
    }

    func testAutomaticDictionaryCorrectionIgnoresSingleCharacterCorrection() {
        let before = "Choose k today"
        let after = "Choose okay today"
        let insertedRange = NSRange(location: 0, length: (before as NSString).length)

        XCTAssertNil(AutomaticDictionaryCorrectionDetector.candidate(
            before: before,
            after: after,
            insertedRange: insertedRange
        ))
    }

    func testAutomaticDictionarySuggestionRequiresRepeatedCorrection() throws {
        let defaults = try self.makeSuggestionPolicyDefaults()
        var configuration = DictionarySuggestionPolicyConfig()
        configuration.globalCooldown = 0
        let policy = AutomaticDictionarySuggestionPolicy(defaults: defaults, configuration: configuration)
        let candidate = AutomaticDictionaryCorrectionCandidate(heardText: "Barad", correctedText: "Barath")
        let now = Date(timeIntervalSince1970: 1000)

        XCTAssertFalse(policy.shouldShow(candidate, now: now))
        XCTAssertTrue(policy.shouldShow(candidate, now: now.addingTimeInterval(60)))
    }

    func testAutomaticDictionarySuggestionPersistsDismissalCooldown() throws {
        let defaults = try self.makeSuggestionPolicyDefaults()
        var configuration = DictionarySuggestionPolicyConfig()
        configuration.requiredOccurrences = 1
        configuration.globalCooldown = 0
        configuration.dismissedPairCooldown = 100
        let candidate = AutomaticDictionaryCorrectionCandidate(heardText: "Barad", correctedText: "Barath")
        let now = Date(timeIntervalSince1970: 2000)

        let policy = AutomaticDictionarySuggestionPolicy(defaults: defaults, configuration: configuration)
        XCTAssertTrue(policy.shouldShow(candidate, now: now))
        policy.markShown(candidate, now: now)
        policy.record(.dismissed, for: candidate, now: now)

        let restoredPolicy = AutomaticDictionarySuggestionPolicy(defaults: defaults, configuration: configuration)
        XCTAssertFalse(restoredPolicy.shouldShow(candidate, now: now.addingTimeInterval(50)))
        XCTAssertTrue(restoredPolicy.shouldShow(candidate, now: now.addingTimeInterval(101)))
    }

    func testAutomaticDictionarySuggestionAppliesGlobalCooldown() throws {
        let defaults = try self.makeSuggestionPolicyDefaults()
        var configuration = DictionarySuggestionPolicyConfig()
        configuration.requiredOccurrences = 1
        configuration.globalCooldown = 600
        let policy = AutomaticDictionarySuggestionPolicy(defaults: defaults, configuration: configuration)
        let first = AutomaticDictionaryCorrectionCandidate(heardText: "Barad", correctedText: "Barath")
        let second = AutomaticDictionaryCorrectionCandidate(heardText: "Floral Voice", correctedText: "FluidVoice")
        let now = Date(timeIntervalSince1970: 3000)

        XCTAssertTrue(policy.shouldShow(first, now: now))
        policy.markShown(first, now: now)
        XCTAssertFalse(policy.shouldShow(second, now: now.addingTimeInterval(60)))
        XCTAssertTrue(policy.shouldShow(second, now: now.addingTimeInterval(601)))
    }

    func testAutomaticDictionarySuggestionStopsAfterSessionIgnoreLimit() throws {
        let defaults = try self.makeSuggestionPolicyDefaults()
        var configuration = DictionarySuggestionPolicyConfig()
        configuration.requiredOccurrences = 1
        configuration.globalCooldown = 0
        configuration.dismissedPairCooldown = 0
        let policy = AutomaticDictionarySuggestionPolicy(defaults: defaults, configuration: configuration)
        let now = Date(timeIntervalSince1970: 4000)

        for index in 0..<configuration.maximumSessionIgnores {
            let candidate = AutomaticDictionaryCorrectionCandidate(
                heardText: "heard \(index)",
                correctedText: "corrected \(index)"
            )
            XCTAssertTrue(policy.shouldShow(candidate, now: now.addingTimeInterval(Double(index))))
            policy.markShown(candidate, now: now.addingTimeInterval(Double(index)))
            policy.record(.timedOut, for: candidate, now: now.addingTimeInterval(Double(index)))
        }

        let next = AutomaticDictionaryCorrectionCandidate(heardText: "another error", correctedText: "another word")
        XCTAssertFalse(policy.shouldShow(next, now: now.addingTimeInterval(10)))
    }

    func testAutomaticDictionarySuggestionNeverReturnsAfterAcceptance() throws {
        let defaults = try self.makeSuggestionPolicyDefaults()
        var configuration = DictionarySuggestionPolicyConfig()
        configuration.requiredOccurrences = 1
        configuration.globalCooldown = 0
        let policy = AutomaticDictionarySuggestionPolicy(defaults: defaults, configuration: configuration)
        let candidate = AutomaticDictionaryCorrectionCandidate(heardText: "Barad", correctedText: "Barath")
        let now = Date(timeIntervalSince1970: 5000)

        XCTAssertTrue(policy.shouldShow(candidate, now: now))
        policy.record(.accepted, for: candidate, now: now)
        XCTAssertFalse(policy.shouldShow(candidate, now: now.addingTimeInterval(10_000)))
    }

    func testAutomaticDictionarySuggestionStopsAfterPairDismissalLimit() throws {
        let defaults = try self.makeSuggestionPolicyDefaults()
        var configuration = DictionarySuggestionPolicyConfig()
        configuration.requiredOccurrences = 1
        configuration.globalCooldown = 0
        configuration.dismissedPairCooldown = 0
        configuration.maximumSessionIgnores = 10
        let policy = AutomaticDictionarySuggestionPolicy(defaults: defaults, configuration: configuration)
        let candidate = AutomaticDictionaryCorrectionCandidate(heardText: "Barad", correctedText: "Barath")
        let now = Date(timeIntervalSince1970: 6000)

        for index in 0..<configuration.maximumPairDismissals {
            let date = now.addingTimeInterval(Double(index))
            XCTAssertTrue(policy.shouldShow(candidate, now: date))
            policy.record(.dismissed, for: candidate, now: date)
        }
        XCTAssertFalse(policy.shouldShow(candidate, now: now.addingTimeInterval(10)))
    }

    private func makeSuggestionPolicyDefaults() throws -> UserDefaults {
        let suiteName = "AutomaticDictionarySuggestionPolicyTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return defaults
    }

    func testDictionaryTransferImport_rejectsInvalidReplacementTriggerType() {
        let json = """
        {
          "replacements": [
            {
              "from": 42,
              "to": "FluidVoice"
            }
          ]
        }
        """

        XCTAssertThrowsError(try DictionaryTransferService.shared.decode(Data(json.utf8)))
    }

    func testDictionaryTransferImport_acceptsParakeetVocabularyTermsFile() throws {
        let json = """
        {
          "alpha": 2.8,
          "terms": [
            {
              "text": "FluidVoice",
              "aliases": ["fluid voice"],
              "weight": 13.0
            },
            {
              "text": "GEMBA-E"
            }
          ]
        }
        """

        let document = try DictionaryTransferService.shared.decode(Data(json.utf8))
        let state = try DictionaryTransferService.importState(
            document: document,
            mode: .replace,
            currentReplacements: [],
            currentCustomWords: []
        )

        XCTAssertEqual(state.replacements.count, 0)
        XCTAssertEqual(state.customWords.map(\.text), ["FluidVoice", "GEMBA-E"])
        XCTAssertEqual(state.customWords.map(\.weight), [13.0, 10.0])
        XCTAssertEqual(state.customWords.map(\.aliases), [[], []])
    }

    func testDictionaryTransferImport_acceptsLocalAPICustomWordsResponse() throws {
        let json = """
        {
          "count": 2,
          "items": [
            {
              "text": "FluidVoice",
              "weight": 10.0,
              "aliases": ["fluid voice"]
            },
            {
              "text": "Barath"
            }
          ]
        }
        """

        let document = try DictionaryTransferService.shared.decode(Data(json.utf8))
        let state = try DictionaryTransferService.importState(
            document: document,
            mode: .replace,
            currentReplacements: [],
            currentCustomWords: []
        )

        XCTAssertEqual(state.replacements.count, 0)
        XCTAssertEqual(state.customWords.map(\.text), ["FluidVoice", "Barath"])
        XCTAssertEqual(state.customWords.map(\.weight), [10.0, 10.0])
        XCTAssertEqual(state.customWords.map(\.aliases), [[], []])
    }

    func testDictationEndToEnd_whisperTiny_transcribesFixture() async throws {
        // Arrange
        let modelDirectory = Self.modelDirectoryForRun()
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let provider = WhisperProvider(modelDirectory: modelDirectory, modelOverride: .whisperTiny)

        // Act
        try await provider.prepare()
        let samples = try AudioFixtureLoader.load16kMonoFloatSamples(named: "dictation_fixture", ext: "wav")
        let result = try await provider.transcribe(samples)

        // Assert
        let raw = result.text.trimmingCharacters(in: .whitespacesAndNewlines)
        XCTAssertFalse(raw.isEmpty, "Expected non-empty transcription text.")

        let normalized = Self.normalize(raw)
        XCTAssertTrue(normalized.contains("hello"), "Expected transcription to contain 'hello'. Got: \(raw)")
        XCTAssertTrue(normalized.contains("fluid"), "Expected transcription to contain 'fluid'. Got: \(raw)")
        XCTAssertTrue(
            normalized.contains("voice") || normalized.contains("fluidvoice") || normalized.contains("boys"),
            "Expected transcription to contain 'voice' (or a close variant like 'boys'). Got: \(raw)"
        )
    }

    func testWhisperProvider_legacyBinCacheDoesNotCountAsDownloadedOrDeletedByReadinessCheck() throws {
        let modelDirectory = Self.modelDirectoryForRun()
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let legacyURL = modelDirectory.appendingPathComponent("ggml-tiny.bin")
        try Data([0x01, 0x02, 0x03]).write(to: legacyURL)

        let provider = WhisperProvider(modelDirectory: modelDirectory, modelOverride: .whisperTiny)

        XCTAssertFalse(provider.modelsExistOnDisk())
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    func testWhisperProvider_readinessCheckDoesNotCreateMissingDirectory() {
        let modelDirectory = Self.modelDirectoryForRun()
        let provider = WhisperProvider(modelDirectory: modelDirectory, modelOverride: .whisperTiny)

        XCTAssertFalse(FileManager.default.fileExists(atPath: modelDirectory.path))
        XCTAssertFalse(provider.modelsExistOnDisk())
        XCTAssertFalse(FileManager.default.fileExists(atPath: modelDirectory.path))
    }

    func testWhisperProvider_ggufCacheReadinessDoesNotDeleteLegacyUntilExplicitClear() async throws {
        let modelDirectory = Self.modelDirectoryForRun()
        try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

        let model = SettingsStore.SpeechModel.whisperTiny
        let ggufFilename = try XCTUnwrap(model.whisperModelFile)
        let legacyFilename = try XCTUnwrap(model.legacyWhisperModelFile)
        let ggufURL = modelDirectory.appendingPathComponent(ggufFilename)
        let legacyURL = modelDirectory.appendingPathComponent(legacyFilename)
        try Self.createSparseFile(at: ggufURL, size: model.expectedDownloadBytes)
        try Data([0x01, 0x02, 0x03]).write(to: legacyURL)

        let provider = WhisperProvider(modelDirectory: modelDirectory, modelOverride: model)

        XCTAssertTrue(provider.modelsExistOnDisk())
        XCTAssertTrue(FileManager.default.fileExists(atPath: legacyURL.path))
        try await provider.clearCache()
        XCTAssertFalse(FileManager.default.fileExists(atPath: ggufURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
    }

    func testAppPromptBinding_profileOverridesModeSelection() {
        self.withPromptSettingsRestored {
            let settings = SettingsStore.shared

            let global = SettingsStore.DictationPromptProfile(
                name: "Global Dictate",
                prompt: "Global dictate prompt",
                mode: .dictate
            )
            let mail = SettingsStore.DictationPromptProfile(
                name: "Mail Dictate",
                prompt: "Mail dictate prompt",
                mode: .dictate
            )

            settings.dictationPromptProfiles = [global, mail]
            settings.selectedDictationPromptID = global.id
            settings.appPromptBindings = [
                SettingsStore.AppPromptBinding(
                    mode: .dictate,
                    appBundleID: "com.apple.mail",
                    appName: "Mail",
                    promptID: mail.id
                ),
            ]

            let mailResolution = settings.promptResolution(for: .dictate, appBundleID: "com.apple.mail")
            XCTAssertEqual(mailResolution.source, .appBindingProfile)
            XCTAssertEqual(mailResolution.profile?.id, mail.id)

            let notesResolution = settings.promptResolution(for: .dictate, appBundleID: "com.apple.notes")
            XCTAssertEqual(notesResolution.source, .selectedProfile)
            XCTAssertEqual(notesResolution.profile?.id, global.id)
        }
    }

    func testAppPromptBinding_defaultFallbackIgnoresGlobalSelection() {
        self.withPromptSettingsRestored {
            let settings = SettingsStore.shared

            let global = SettingsStore.DictationPromptProfile(
                name: "Global Dictate",
                prompt: "Global dictate prompt",
                mode: .dictate
            )

            settings.dictationPromptProfiles = [global]
            settings.selectedDictationPromptID = global.id
            settings.appPromptBindings = [
                SettingsStore.AppPromptBinding(
                    mode: .dictate,
                    appBundleID: "com.apple.mail",
                    appName: "Mail",
                    promptID: nil
                ),
            ]

            let mailResolution = settings.promptResolution(for: .dictate, appBundleID: "com.apple.mail")
            XCTAssertEqual(mailResolution.source, .appBindingDefault)
            XCTAssertNil(mailResolution.profile)
            XCTAssertEqual(
                mailResolution.systemPrompt,
                SettingsStore.defaultSystemPromptText(for: .dictate)
            )

            let otherResolution = settings.promptResolution(for: .dictate, appBundleID: "com.apple.notes")
            XCTAssertEqual(otherResolution.source, .selectedProfile)
            XCTAssertEqual(otherResolution.profile?.id, global.id)
        }
    }

    func testEditPromptOffUsesBuiltInDefaultAndPausesOverrides() {
        self.withPromptSettingsRestored {
            let settings = SettingsStore.shared

            let global = SettingsStore.DictationPromptProfile(
                name: "Global Edit",
                prompt: "Global edit prompt",
                mode: .edit
            )
            let mail = SettingsStore.DictationPromptProfile(
                name: "Mail Edit",
                prompt: "Mail edit prompt",
                mode: .edit
            )

            settings.dictationPromptProfiles = [global, mail]
            settings.selectedEditPromptID = global.id
            settings.defaultEditPromptOverride = "Custom default edit prompt"
            settings.appPromptBindings = [
                SettingsStore.AppPromptBinding(
                    mode: .edit,
                    appBundleID: "com.apple.mail",
                    appName: "Mail",
                    promptID: mail.id
                ),
            ]

            settings.setPromptOff(true, for: .edit)

            let paused = settings.promptResolution(for: .edit, appBundleID: "com.apple.mail")
            XCTAssertEqual(paused.source, .builtInDefault)
            XCTAssertNil(paused.profile)
            XCTAssertNil(paused.appBinding)
            XCTAssertEqual(paused.systemPrompt, SettingsStore.defaultSystemPromptText(for: .edit))

            settings.setSelectedPromptID(global.id, for: .edit)

            XCTAssertFalse(settings.isPromptOff(for: .edit))
            XCTAssertEqual(settings.promptResolution(for: .edit, appBundleID: nil).profile?.id, global.id)
        }
    }

    func testAppPromptBindings_reconcileInvalidPromptAndLegacyMode() {
        self.withPromptSettingsRestored {
            let settings = SettingsStore.shared

            let editProfile = SettingsStore.DictationPromptProfile(
                name: "Edit",
                prompt: "Edit prompt",
                mode: .edit
            )
            settings.dictationPromptProfiles = [editProfile]
            settings.appPromptBindings = [
                SettingsStore.AppPromptBinding(
                    mode: .rewrite,
                    appBundleID: " COM.APPLE.SAFARI ",
                    appName: "Safari",
                    promptID: "missing-profile"
                ),
            ]

            settings.reconcilePromptStateAfterProfileChanges()

            guard let binding = settings.appPromptBindings.first else {
                XCTFail("Expected normalized app prompt binding")
                return
            }

            XCTAssertEqual(binding.mode, .edit)
            XCTAssertEqual(binding.appBundleID, "com.apple.safari")
            XCTAssertNil(binding.promptID)
        }
    }

    func testLegacyBlockedPromptPlaceholderIsRemoved() {
        self.withPromptSettingsRestored {
            let settings = SettingsStore.shared

            let blocked = SettingsStore.DictationPromptProfile(
                name: "Blocked",
                prompt: "Blocked prompt",
                mode: .dictate
            )
            let real = SettingsStore.DictationPromptProfile(
                name: "Keep Me",
                prompt: "Real user prompt",
                mode: .dictate
            )

            settings.dictationPromptProfiles = [blocked, real]
            settings.selectedDictationPromptID = blocked.id
            settings.appPromptBindings = [
                SettingsStore.AppPromptBinding(
                    mode: .dictate,
                    appBundleID: "com.apple.notes",
                    appName: "Notes",
                    promptID: blocked.id
                ),
            ]

            settings.reconcilePromptStateAfterProfileChanges()

            XCTAssertEqual(settings.dictationPromptProfiles.map(\.id), [real.id])
            XCTAssertNil(settings.selectedDictationPromptID)
            XCTAssertEqual(settings.appPromptBindings.first?.promptID, nil)
        }
    }

    func testCustomProviderSettingsRoundTripThroughSettingsStore() {
        self.withProviderSettingsRestored {
            let settings = SettingsStore.shared
            let provider = SettingsStore.SavedProvider(
                id: "custom-provider-test",
                name: "Issue299 Temp",
                baseURL: "http://10.0.0.138:1234/v1",
                models: ["google/gemma-4-e4b"]
            )
            let providerKey = "custom:\(provider.id)"

            settings.savedProviders = [provider]
            settings.availableModelsByProvider = [providerKey: provider.models]
            settings.selectedModelByProvider = [providerKey: provider.models[0]]
            settings.selectedProviderID = provider.id

            XCTAssertEqual(settings.selectedProviderID, provider.id)
            XCTAssertEqual(settings.savedProviders, [provider])
            XCTAssertEqual(settings.availableModelsByProvider[providerKey], provider.models)
            XCTAssertEqual(settings.selectedModelByProvider[providerKey], provider.models[0])
        }
    }

    func testUnavailableSelectedProviderClearsSelection() {
        self.withProviderSettingsRestored {
            let settings = SettingsStore.shared

            settings.savedProviders = []
            settings.selectedProviderID = "removed-provider"

            XCTAssertEqual(settings.selectedProviderID, "")
        }
    }

    func testAppleIntelligenceIsNotAvailableAsABuiltInProvider() {
        XCTAssertFalse(ModelRepository.builtInProviderIDs.contains("apple-intelligence"))
        XCTAssertFalse(ModelRepository.shared.builtInProvidersList().contains { $0.id.contains("apple-intelligence") })
    }

    func testRetiredAppleIntelligenceStateIsPurgedWithoutSelectingAFallbackProvider() {
        self.withRestoredDefaults(
            keys: [
                self.dictationPromptOffKey,
                self.selectedDictationPromptIDKey,
                self.selectedProviderIDKey,
                self.selectedAIModelKey,
                self.availableModelsByProviderKey,
                self.selectedModelByProviderKey,
                self.verifiedProviderFingerprintsKey,
                self.commandModeSelectedProviderIDKey,
                self.commandModeSelectedModelKey,
                self.rewriteModeSelectedProviderIDKey,
                self.rewriteModeSelectedModelKey,
                self.dictationPromptConfigurationsKey,
            ]
        ) {
            let settings = SettingsStore.shared
            let shortcut = HotkeyShortcut(keyCode: 1, modifierFlags: [.command])
            settings.selectedProviderID = "apple-intelligence"
            settings.selectedModel = "System Model"
            settings.availableModelsByProvider = ["apple-intelligence": ["System Model"]]
            settings.selectedModelByProvider = ["apple-intelligence": "System Model"]
            settings.verifiedProviderFingerprints = ["apple-intelligence": "apple-intelligence"]
            settings.commandModeSelectedProviderID = "apple-intelligence-disabled"
            settings.commandModeSelectedModel = "System Model"
            settings.rewriteModeSelectedProviderID = "apple-intelligence"
            settings.rewriteModeSelectedModel = "System Model"
            settings.dictationPromptConfigurations = [
                "__default__": SettingsStore.DictationPromptConfiguration(
                    shortcut: shortcut,
                    providerID: "apple-intelligence",
                    modelName: "System Model"
                ),
            ]

            settings.purgeRetiredAppleIntelligenceState()
            settings.purgeRetiredAppleIntelligenceState()

            XCTAssertEqual(settings.selectedProviderID, "")
            XCTAssertNil(settings.selectedModel)
            XCTAssertEqual(settings.commandModeSelectedProviderID, "")
            XCTAssertNil(settings.commandModeSelectedModel)
            XCTAssertEqual(settings.rewriteModeSelectedProviderID, "")
            XCTAssertNil(settings.rewriteModeSelectedModel)
            XCTAssertNil(settings.availableModelsByProvider["apple-intelligence"])
            XCTAssertNil(settings.selectedModelByProvider["apple-intelligence"])
            XCTAssertNil(settings.verifiedProviderFingerprints["apple-intelligence"])
            // The prompt keeps its retired provider so it fails closed instead of using the main provider.
            XCTAssertEqual(settings.dictationPromptConfigurations["__default__"]?.shortcut, shortcut)
            XCTAssertEqual(settings.dictationPromptConfigurations["__default__"]?.providerID, "apple-intelligence")
            XCTAssertFalse(DictationAIPostProcessingGate.isProviderConfigured())

            settings.selectedProviderID = "openai"
            settings.setDictationPromptSelection(.default, for: .primary)
            XCTAssertEqual(
                DictationProviderRoute.resolve(settings: settings, dictationSlot: .primary),
                DictationProviderRoute(providerID: "", providerKey: "", baseURL: "", model: "", apiKey: "")
            )
        }
    }

    /// Settings left behind by an upstream FluidVoice build that used Fluid Intelligence must land on
    /// plain dictation: the FI-routed slot is Off, nothing dangles, other providers are untouched.
    func testRetiredFluidIntelligenceStateIsPurgedToPlainDictation() {
        self.withRestoredDefaults(keys: self.retiredFluidIntelligenceTestKeys) {
            let settings = SettingsStore.shared
            let defaults = UserDefaults.standard
            let shortcut = HotkeyShortcut(keyCode: 1, modifierFlags: [.command])
            let custom = SettingsStore.DictationPromptProfile(name: "Custom", prompt: "Tidy it", mode: .dictate)
            settings.dictationPromptProfiles = [custom]

            // Primary slot selected the FI prompt; secondary slot uses a custom prompt pinned to OpenAI.
            defaults.set(false, forKey: self.dictationPromptOffKey)
            defaults.set("__FLUID_1__", forKey: self.selectedDictationPromptIDKey)
            defaults.set(false, forKey: self.secondaryDictationPromptOffKey)
            defaults.set(custom.id, forKey: self.promptModeSelectedPromptIDKey)
            defaults.set("fluid-1", forKey: self.selectedProviderIDKey)
            settings.selectedModel = "fluid-1"
            settings.availableModelsByProvider = ["custom:fluid-1": ["fluid-1"], "openai": ["gpt-4.1"]]
            settings.selectedModelByProvider = ["custom:fluid-1": "fluid-1", "openai": "gpt-4.1"]
            settings.verifiedProviderFingerprints = ["fluid-1": "private-ai-provider|fluid-1", "openai": "verified"]
            settings.commandModeSelectedProviderID = "fluid-1"
            settings.commandModeSelectedModel = "fluid-1"
            settings.rewriteModeSelectedProviderID = "custom:fluid-1"
            settings.rewriteModeSelectedModel = "fluid-1"
            settings.dictationPromptConfigurations = [
                "__privateAI__": SettingsStore.DictationPromptConfiguration(shortcut: shortcut),
                "__default__": SettingsStore.DictationPromptConfiguration(
                    shortcut: shortcut,
                    providerID: "fluid-1",
                    modelName: "fluid-1"
                ),
                "profile:\(custom.id)": SettingsStore.DictationPromptConfiguration(
                    providerID: "openai",
                    modelName: "gpt-4.1"
                ),
            ]
            defaults.set("mlx", forKey: "FluidIntelligenceBackendPreference")
            defaults.set(true, forKey: "PrivateAIProviderBoostEnabled")

            settings.purgeRetiredFluidIntelligenceState()
            settings.purgeRetiredFluidIntelligenceState()

            XCTAssertEqual(settings.dictationPromptSelection(for: .primary), .off)
            XCTAssertNil(settings.selectedDictationPromptID)
            XCTAssertEqual(settings.dictationPromptSelection(for: .secondary), .profile(custom.id))
            XCTAssertEqual(settings.selectedProviderID, "")
            XCTAssertNil(settings.selectedModel)
            XCTAssertEqual(settings.commandModeSelectedProviderID, "")
            XCTAssertNil(settings.commandModeSelectedModel)
            XCTAssertEqual(settings.rewriteModeSelectedProviderID, "")
            XCTAssertNil(settings.rewriteModeSelectedModel)
            XCTAssertEqual(settings.availableModelsByProvider, ["openai": ["gpt-4.1"]])
            XCTAssertEqual(settings.selectedModelByProvider, ["openai": "gpt-4.1"])
            XCTAssertEqual(settings.verifiedProviderFingerprints, ["openai": "verified"])
            XCTAssertNil(settings.dictationPromptConfigurations["__privateAI__"])
            // Prompts pinned to FI keep that provider, so they fail closed rather than fall back.
            XCTAssertEqual(settings.dictationPromptConfigurations["__default__"]?.shortcut, shortcut)
            XCTAssertEqual(settings.dictationPromptConfigurations["__default__"]?.providerID, "fluid-1")
            XCTAssertEqual(settings.dictationPromptConfigurations["profile:\(custom.id)"]?.providerID, "openai")
            XCTAssertNil(defaults.object(forKey: "FluidIntelligenceBackendPreference"))
            XCTAssertNil(defaults.object(forKey: "PrivateAIProviderBoostEnabled"))
            XCTAssertFalse(DictationAIPostProcessingGate.isConfigured(for: .primary))
            XCTAssertEqual(settings.dictationPromptDisplayName(for: .primary, appBundleID: nil), "Off")
        }
    }

    func testRetiredFluidIntelligenceGlobalProviderTurnsDefaultDictationOff() {
        self.withRestoredDefaults(keys: self.retiredFluidIntelligenceTestKeys) {
            let settings = SettingsStore.shared
            let defaults = UserDefaults.standard
            settings.dictationPromptConfigurations = [:]
            settings.setDictationPromptSelection(.default, for: .primary)
            defaults.set(true, forKey: self.secondaryDictationPromptOffKey)
            defaults.set("fluid-1", forKey: self.selectedProviderIDKey)

            settings.purgeRetiredFluidIntelligenceState()

            XCTAssertEqual(settings.dictationPromptSelection(for: .primary), .off)
            XCTAssertEqual(settings.dictationPromptSelection(for: .secondary), .off)
            XCTAssertEqual(settings.selectedProviderID, "")
        }
    }

    /// Main provider is OpenAI; a prompt that used Fluid Intelligence is reached through an app
    /// override or its own shortcut. It must produce raw text, never a call to OpenAI.
    func testPromptPinnedToFluidIntelligenceFailsClosedInsteadOfUsingTheMainProvider() {
        self.withRestoredDefaults(
            keys: self.retiredFluidIntelligenceTestKeys + [self.appPromptBindingsKey, self.dictationPromptRoutingScopeKey]
        ) {
            let settings = SettingsStore.shared
            let defaults = UserDefaults.standard
            let appBundleID = "com.example.editor"
            let fiPrompt = SettingsStore.DictationPromptProfile(name: "Polish", prompt: "Polish it", mode: .dictate)
            settings.dictationPromptProfiles = [fiPrompt]
            settings.appPromptBindings = [
                SettingsStore.AppPromptBinding(
                    mode: .dictate,
                    appBundleID: appBundleID,
                    appName: "Editor",
                    promptID: fiPrompt.id
                ),
            ]
            settings.dictationPromptRoutingScope = .allApps
            settings.dictationPromptConfigurations = [
                "profile:\(fiPrompt.id)": SettingsStore.DictationPromptConfiguration(
                    providerID: "fluid-1",
                    modelName: "fluid-1"
                ),
            ]
            settings.selectedProviderID = "openai"
            settings.selectedModelByProvider = ["openai": "gpt-4.1"]
            settings.setDictationPromptSelection(.default, for: .primary)
            defaults.set(true, forKey: self.secondaryDictationPromptOffKey)

            settings.purgeRetiredFluidIntelligenceState()

            // Control: outside the bound app, Default still routes to the main provider.
            XCTAssertEqual(settings.dictationPromptSelection(for: .primary), .default)
            XCTAssertEqual(
                DictationProviderRoute.resolve(settings: settings, dictationSlot: .primary, appBundleID: "com.example.other").providerID,
                "openai"
            )

            // App override reaches the FI prompt: empty route, no AI, raw text.
            let emptyRoute = DictationProviderRoute(providerID: "", providerKey: "", baseURL: "", model: "", apiKey: "")
            XCTAssertEqual(
                DictationProviderRoute.resolve(settings: settings, dictationSlot: .primary, appBundleID: appBundleID),
                emptyRoute
            )
            XCTAssertFalse(DictationAIPostProcessingGate.isConfigured(for: .primary, appBundleID: appBundleID))

            // The prompt's own shortcut (selected directly on a slot) fails closed too.
            settings.setDictationPromptSelection(.profile(fiPrompt.id), for: .secondary)
            XCTAssertEqual(DictationProviderRoute.resolve(settings: settings, dictationSlot: .secondary), emptyRoute)
            XCTAssertFalse(DictationAIPostProcessingGate.isConfigured(for: .secondary))
        }
    }

    func testNonFluidIntelligenceSettingsSurviveTheRetiredFluidIntelligencePurge() {
        self.withRestoredDefaults(keys: self.retiredFluidIntelligenceTestKeys) {
            let settings = SettingsStore.shared
            settings.dictationPromptConfigurations = [:]
            settings.setDictationPromptSelection(.default, for: .primary)
            settings.selectedProviderID = "openai"
            settings.selectedModelByProvider = ["openai": "gpt-4.1"]

            settings.purgeRetiredFluidIntelligenceState()

            XCTAssertEqual(settings.dictationPromptSelection(for: .primary), .default)
            XCTAssertEqual(settings.selectedProviderID, "openai")
            XCTAssertEqual(settings.selectedModelByProvider, ["openai": "gpt-4.1"])
        }
    }

    func testFeedbackIssueURLIsAPrefilledIssueOnTheFork() throws {
        let body = "Dictation dropped text in c11 & Ghostty.\n\nSteps: 1+1=2 #tag"
        let url = LiquidVoiceLinks.prefilledIssueURL(title: "Dropped text", body: body)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))

        XCTAssertEqual(components.scheme, "https")
        XCTAssertEqual(components.host, "github.com")
        XCTAssertEqual(components.path, "/BenevolentFutures/LiquidVoice/issues/new")
        let items = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["title"], "Dropped text")
        XCTAssertEqual(items["body"], body)
        XCTAssertFalse(url.absoluteString.contains("+"), "a literal + would read as a space on GitHub")
    }

    func testFeedbackIssueURLTruncatesFeedbackButKeepsVersionInfo() throws {
        let body = String(repeating: "long feedback ", count: 2000)
        let footer = "---\nLiquid Voice 1.2.3 (45)\nmacOS 26.0"
        let url = LiquidVoiceLinks.prefilledIssueURL(title: "Long", body: body, footer: footer)
        XCTAssertLessThanOrEqual(url.absoluteString.count, LiquidVoiceLinks.maxIssueURLLength)
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let sentBody = try XCTUnwrap(components.queryItems?.first { $0.name == "body" }?.value)
        XCTAssertTrue(sentBody.hasPrefix("long feedback "))
        XCTAssertTrue(sentBody.hasSuffix("[truncated]\n\n" + footer))
    }

    func testFeedbackIssueTitleUsesFirstLineOfFeedback() {
        XCTAssertEqual(LiquidVoiceLinks.issueTitle(forFeedback: "Mic switch fails\nmore detail"), "Mic switch fails")
        XCTAssertEqual(LiquidVoiceLinks.issueTitle(forFeedback: "   "), "Feedback")
        XCTAssertEqual(LiquidVoiceLinks.issueTitle(forFeedback: String(repeating: "a", count: 200)).count, 80)
    }

    func testDebugBuildLogsToItsOwnFolder() {
        XCTAssertEqual(AppStorageLocation.logFolderName, "LiquidVoice-Dev")
        let logURL = FileLogger.shared.currentLogFileURL()
        XCTAssertEqual(logURL.deletingLastPathComponent().lastPathComponent, "LiquidVoice-Dev")
        XCTAssertEqual(logURL.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent, "Logs")
    }

    private var retiredFluidIntelligenceTestKeys: [String] {
        [
            self.selectedProviderIDKey,
            self.selectedAIModelKey,
            self.availableModelsByProviderKey,
            self.selectedModelByProviderKey,
            self.verifiedProviderFingerprintsKey,
            self.commandModeSelectedProviderIDKey,
            self.commandModeSelectedModelKey,
            self.rewriteModeSelectedProviderIDKey,
            self.rewriteModeSelectedModelKey,
            self.dictationPromptConfigurationsKey,
            self.dictationPromptProfilesKey,
            self.dictationPromptOffKey,
            self.selectedDictationPromptIDKey,
            self.secondaryDictationPromptOffKey,
            self.promptModeSelectedPromptIDKey,
        ] + SettingsStore.retiredFluidIntelligenceDefaultsKeys
    }

    func testDictationProviderRouteUsesPromptConfigurationWithoutMutatingGlobalSelection() {
        self.withRestoredDefaults(
            keys: [
                self.selectedProviderIDKey,
                self.selectedModelByProviderKey,
                self.verifiedProviderFingerprintsKey,
                self.dictationPromptConfigurationsKey,
                self.dictationPromptOffKey,
                self.selectedDictationPromptIDKey,
            ]
        ) {
            let settings = SettingsStore.shared
            settings.selectedProviderID = "openai"
            settings.selectedModelByProvider = ["openai": "gpt-4.1", "ollama": "test-local-model"]
            settings.verifiedProviderFingerprints = [
                "ollama": DictationAIPostProcessingGate.providerFingerprint(
                    baseURL: ModelRepository.shared.defaultBaseURL(for: "ollama"),
                    apiKey: ""
                ) ?? "",
            ]
            settings.setDictationPromptSelection(.default, for: .primary)
            settings.setDictationPromptConfiguration(
                SettingsStore.DictationPromptConfiguration(
                    providerID: "ollama",
                    modelName: "test-local-model"
                ),
                for: .default
            )

            let route = DictationProviderRoute.resolve(settings: settings, dictationSlot: .primary)

            XCTAssertEqual(route.providerID, "ollama")
            XCTAssertEqual(route.providerKey, "ollama")
            XCTAssertEqual(route.model, "test-local-model")
            XCTAssertEqual(settings.selectedProviderID, "openai")
            XCTAssertEqual(settings.selectedModelByProvider["openai"], "gpt-4.1")

            XCTAssertTrue(DictationAIPostProcessingGate.isConfigured(for: .primary))
            XCTAssertEqual(settings.selectedProviderID, "openai")
        }
    }

    func testDictationProviderRouteUsesAppBoundPromptConfiguration() {
        self.withRestoredDefaults(
            keys: [
                self.dictationPromptProfilesKey,
                self.appPromptBindingsKey,
                self.dictationPromptRoutingScopeKey,
                self.selectedProviderIDKey,
                self.selectedModelByProviderKey,
                self.verifiedProviderFingerprintsKey,
                self.dictationPromptConfigurationsKey,
                self.dictationPromptOffKey,
                self.selectedDictationPromptIDKey,
            ]
        ) {
            let settings = SettingsStore.shared
            let appBundleID = "com.example.editor"
            let profile = SettingsStore.DictationPromptProfile(
                name: "Editor",
                prompt: "Clean up text for this editor.",
                mode: .dictate
            )
            settings.dictationPromptProfiles = [profile]
            settings.appPromptBindings = [
                SettingsStore.AppPromptBinding(
                    mode: .dictate,
                    appBundleID: appBundleID,
                    appName: "Editor",
                    promptID: profile.id
                ),
            ]
            settings.dictationPromptRoutingScope = .allApps
            settings.selectedProviderID = "openai"
            settings.selectedModelByProvider = ["openai": "gpt-4.1", "ollama": "editor-model"]
            settings.verifiedProviderFingerprints = [
                "ollama": DictationAIPostProcessingGate.providerFingerprint(
                    baseURL: ModelRepository.shared.defaultBaseURL(for: "ollama"),
                    apiKey: ""
                ) ?? "",
            ]
            settings.setDictationPromptSelection(.default, for: .primary)
            settings.setDictationPromptConfiguration(
                SettingsStore.DictationPromptConfiguration(
                    providerID: "openai",
                    modelName: "gpt-4.1"
                ),
                for: .default
            )
            settings.setDictationPromptConfiguration(
                SettingsStore.DictationPromptConfiguration(
                    providerID: "ollama",
                    modelName: "editor-model"
                ),
                for: .profile(profile.id)
            )

            let route = DictationProviderRoute.resolve(
                settings: settings,
                dictationSlot: .primary,
                appBundleID: appBundleID
            )

            XCTAssertEqual(route.providerID, "ollama")
            XCTAssertEqual(route.model, "editor-model")
            XCTAssertEqual(settings.selectedProviderID, "openai")
            XCTAssertTrue(DictationAIPostProcessingGate.isConfigured(for: .primary, appBundleID: appBundleID))
        }
    }

    func testPostProcessingRouteUsesGlobalProviderWithoutAppContext() {
        self.withRestoredDefaults(
            keys: [
                self.dictationPromptRoutingScopeKey,
                self.selectedProviderIDKey,
                self.selectedModelByProviderKey,
                self.dictationPromptOffKey,
                self.selectedDictationPromptIDKey,
            ]
        ) {
            let settings = SettingsStore.shared
            settings.dictationPromptRoutingScope = .selectedAppsOnly
            settings.selectedProviderID = "openai"
            settings.selectedModelByProvider = ["openai": "gpt-4.1"]
            settings.setDictationPromptSelection(.default, for: .primary)

            let route = DictationProviderRoute.resolveForPostProcessing(
                settings: settings,
                dictationSlot: .primary
            )

            XCTAssertEqual(route.providerID, "openai")
            XCTAssertEqual(route.model, "gpt-4.1")
        }
    }

    func testRollbackBackupsPreferFilenameTimestampOverModificationDate() {
        let firstBackupWithNewestModificationDate = URL(
            fileURLWithPath: "/tmp/FluidVoice-1.5.11-beta.1-100.app"
        )
        let secondBackup = URL(
            fileURLWithPath: "/tmp/FluidVoice-1.5.11-beta.2-150.app"
        )
        let thirdBackup = URL(
            fileURLWithPath: "/tmp/FluidVoice-1.5.11-beta.3-rollback-200.app"
        )
        let fourthBackupWithOldestModificationDate = URL(
            fileURLWithPath: "/tmp/FluidVoice-1.5.11-beta.4-rollback-300.app"
        )
        let modificationDates = [
            firstBackupWithNewestModificationDate: Date(timeIntervalSince1970: 500),
            secondBackup: Date(timeIntervalSince1970: 300),
            thirdBackup: Date(timeIntervalSince1970: 50),
            fourthBackupWithOldestModificationDate: Date(timeIntervalSince1970: 10),
        ]

        let sorted = SimpleUpdater.sortedRollbackBackups(
            [
                firstBackupWithNewestModificationDate,
                secondBackup,
                thirdBackup,
                fourthBackupWithOldestModificationDate,
            ]
        ) { url in
            modificationDates[url]
        }

        XCTAssertEqual(
            sorted,
            [
                fourthBackupWithOldestModificationDate,
                thirdBackup,
                secondBackup,
                firstBackupWithNewestModificationDate,
            ]
        )
    }

    func testRollbackVersionIgnoresCurrentAppVersion() {
        XCTAssertFalse(SimpleUpdater.isRollbackVersion("1.5.11-beta.3", differentFrom: "1.5.11-beta.3"))
        XCTAssertTrue(SimpleUpdater.isRollbackVersion("1.5.11-beta.2", differentFrom: "1.5.11-beta.3"))
        XCTAssertFalse(SimpleUpdater.isRollbackVersion(nil, differentFrom: "1.5.11-beta.3"))
    }

    // MARK: - Model download HTML/markup rejection (#353)

    func testLooksLikeHTML_rejectsMarkupVariants() {
        // A proxy/block page or stand-in markup document must be rejected regardless of
        // which markup token it opens with — not just <!doctype / <html.
        let rejected = [
            "<!DOCTYPE html><html lang=\"en\"><head></head></html>",
            "<html><body>Blocked by corporate proxy</body></html>",
            "<script>window.location='https://proxy'</script>",
            "<head><title>Access Denied</title></head>",
            "<body>Forbidden</body>",
            "<meta http-equiv=\"refresh\" content=\"0\">",
            "<!-- corporate gateway notice -->",
            "<?xml version=\"1.0\" encoding=\"UTF-8\"?><error>blocked</error>",
            "</html>",
            "<!doctype HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\">",
        ]
        for markup in rejected {
            XCTAssertTrue(
                HuggingFaceModelDownloader.looksLikeHTML(Data(markup.utf8)),
                "Expected markup to be rejected: \(markup)"
            )
        }
    }

    func testLooksLikeHTML_rejectsLeadingWhitespaceAndBOMVariants() {
        let bom: [UInt8] = [0xef, 0xbb, 0xbf]

        // Leading ASCII whitespace before the markup token.
        XCTAssertTrue(HuggingFaceModelDownloader.looksLikeHTML(Data("   \n\t<!DOCTYPE html>".utf8)))
        XCTAssertTrue(HuggingFaceModelDownloader.looksLikeHTML(Data("\r\n  <html>".utf8)))

        // UTF-8 BOM, then markup.
        XCTAssertTrue(HuggingFaceModelDownloader.looksLikeHTML(Data(bom + Array("<html>".utf8))))

        // BOM, then whitespace, then an XML declaration.
        XCTAssertTrue(
            HuggingFaceModelDownloader.looksLikeHTML(Data(bom + Array("  \n<?xml version=\"1.0\"?>".utf8)))
        )
    }

    func testLooksLikeHTML_acceptsModelArtifacts() {
        // JSON object (vocab / metadata / Manifest) — note the embedded `<pad>` must NOT
        // trip the detector; only a LEADING `<` does.
        XCTAssertFalse(HuggingFaceModelDownloader.looksLikeHTML(Data("{\"0\": \"<pad>\", \"1\": \"a\"}".utf8)))
        // JSON array body.
        XCTAssertFalse(HuggingFaceModelDownloader.looksLikeHTML(Data("[1, 2, 3]".utf8)))
        // MIL program text (`model.mil`).
        XCTAssertFalse(HuggingFaceModelDownloader.looksLikeHTML(Data("program(1.0)\n[buildInfo = ...]".utf8)))
        // Binary CoreML / Mach-O magic prefix.
        XCTAssertFalse(HuggingFaceModelDownloader.looksLikeHTML(Data([0xcf, 0xfa, 0xed, 0xfe, 0x07, 0x00])))
        // Leading-NUL binary (e.g. coremldata.bin / weight.bin style payloads).
        XCTAssertFalse(HuggingFaceModelDownloader.looksLikeHTML(Data([0x00, 0x00, 0x01, 0x3c, 0x68])))
        // Empty payload.
        XCTAssertFalse(HuggingFaceModelDownloader.looksLikeHTML(Data()))
        // A stray `<` NOT followed by a markup-ish byte must not be over-rejected.
        XCTAssertFalse(HuggingFaceModelDownloader.looksLikeHTML(Data("< not markup".utf8)))
        XCTAssertFalse(HuggingFaceModelDownloader.looksLikeHTML(Data("<".utf8)))
    }

    func testValidateDownloadedFile_rejectsHTMLBodyAndAcceptsJSON() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FluidVoice-ValidateTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // HTML body written without an HTML Content-Type (response: nil) must still be
        // rejected by the byte-sniff path.
        let htmlURL = dir.appendingPathComponent("coremldata.bin")
        try Data("<!DOCTYPE html><html><body>Blocked</body></html>".utf8).write(to: htmlURL)
        XCTAssertThrowsError(
            try HuggingFaceModelDownloader.validateDownloadedFile(
                at: htmlURL,
                response: nil,
                relativePath: "coremldata.bin"
            )
        )

        // A real JSON vocab payload must pass validation.
        let jsonURL = dir.appendingPathComponent("parakeet_v3_vocab.json")
        try Data("{\"0\": \"<pad>\", \"1\": \"the\"}".utf8).write(to: jsonURL)
        XCTAssertNoThrow(
            try HuggingFaceModelDownloader.validateDownloadedFile(
                at: jsonURL,
                response: nil,
                relativePath: "parakeet_v3_vocab.json"
            )
        )
    }

    func testCachedFileIsMarkup_detectsCachedCorruptHTMLAndAcceptsModelData() throws {
        // Guards the #353 cached-file path: a corrupt HTML payload already on disk (cached
        // before download-time validation existed) must be detected so it is re-downloaded,
        // while a real model artifact must not be flagged, and an unreadable path must be
        // treated as valid (never deleted on uncertainty).
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FluidVoice-CachedMarkupTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // A cached HTML/proxy page persisted as a model file must be detected as markup.
        let htmlURL = dir.appendingPathComponent("coremldata.bin")
        try Data("<!DOCTYPE html><html><body>Blocked by proxy</body></html>".utf8).write(to: htmlURL)
        XCTAssertTrue(HuggingFaceModelDownloader.cachedFileIsMarkup(at: htmlURL))

        // A real JSON vocab payload must not be flagged.
        let jsonURL = dir.appendingPathComponent("parakeet_v3_vocab.json")
        try Data("{\"0\": \"<pad>\", \"1\": \"the\"}".utf8).write(to: jsonURL)
        XCTAssertFalse(HuggingFaceModelDownloader.cachedFileIsMarkup(at: jsonURL))

        // An unreadable / missing path must be treated as valid (conservative on read error).
        let missingURL = dir.appendingPathComponent("does-not-exist.bin")
        XCTAssertFalse(HuggingFaceModelDownloader.cachedFileIsMarkup(at: missingURL))
    }

    func testCachedPayloadContainsMarkup_detectsCorruptFileInPresentArtifactTree() throws {
        // Guards the #353 provider-PREFLIGHT path: a corrupt HTML payload nested inside a
        // present `.mlpackage` bundle (or a loose required file) must be detected so the preflight
        // re-downloads instead of trusting a file-existence/manifest check, while a valid cached
        // tree must not be flagged, and missing/empty required entries stay conservative.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("FluidVoice-CachedPayloadTest-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // A realistic `.mlpackage` layout: a JSON manifest plus a nested binary weight payload.
        let packageName = "encoder.mlpackage"
        let weightsDir = root.appendingPathComponent(packageName)
            .appendingPathComponent("Data/com.apple.CoreML/weights", isDirectory: true)
        try FileManager.default.createDirectory(at: weightsDir, withIntermediateDirectories: true)
        let manifestURL = root.appendingPathComponent(packageName).appendingPathComponent("Manifest.json")
        try Data("{\"fileFormatVersion\": \"1.0.0\"}".utf8).write(to: manifestURL)
        let weightURL = weightsDir.appendingPathComponent("weight.bin")
        try Data([0x00, 0x01, 0x02, 0x03, 0x04]).write(to: weightURL)

        // A loose required file (e.g. a tokenizer) with real binary content.
        let tokenizerURL = root.appendingPathComponent("tokenizer.model")
        try Data([0x0a, 0x09, 0x05, 0x00]).write(to: tokenizerURL)

        let entries = [packageName, "tokenizer.model"]

        // An all-valid tree must not be flagged.
        XCTAssertFalse(
            HuggingFaceModelDownloader.cachedPayloadContainsMarkup(root: root, relativePaths: entries)
        )

        // A proxy HTML page persisted as a binary INSIDE the package must be detected.
        try Data("<!DOCTYPE html><html><body>Blocked by proxy</body></html>".utf8).write(to: weightURL)
        XCTAssertTrue(
            HuggingFaceModelDownloader.cachedPayloadContainsMarkup(root: root, relativePaths: entries)
        )

        // Restore the binary; corrupt the loose required file instead — must still be detected.
        try Data([0x00, 0x01, 0x02, 0x03, 0x04]).write(to: weightURL)
        try Data("<html><head></head></html>".utf8).write(to: tokenizerURL)
        XCTAssertTrue(
            HuggingFaceModelDownloader.cachedPayloadContainsMarkup(root: root, relativePaths: entries)
        )

        // Missing entries and an empty required directory are conservative: never flagged corrupt
        // on uncertainty (incompleteness is the existence check's concern, not this one's).
        try Data([0x0a, 0x09, 0x05, 0x00]).write(to: tokenizerURL)
        let emptyPackage = root.appendingPathComponent("empty.mlpackage", isDirectory: true)
        try FileManager.default.createDirectory(at: emptyPackage, withIntermediateDirectories: true)
        XCTAssertFalse(
            HuggingFaceModelDownloader.cachedPayloadContainsMarkup(
                root: root,
                relativePaths: ["empty.mlpackage", "does-not-exist.json"]
            )
        )
    }

    private static func modelDirectoryForRun() -> URL {
        // Use a stable path on CI so GitHub Actions cache can speed up runs.
        if ProcessInfo.processInfo.environment["GITHUB_ACTIONS"] == "true" ||
            ProcessInfo.processInfo.environment["CI"] == "true"
        {
            guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
                preconditionFailure("Could not find caches directory")
            }
            return caches.appendingPathComponent("WhisperModels")
        }

        // Local runs: isolate per test execution.
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("FluidVoiceTests", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        return base.appendingPathComponent("WhisperModels", isDirectory: true)
    }

    private static func createSparseFile(at url: URL, size: Int64) throws {
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        let handle = try FileHandle(forWritingTo: url)
        try handle.truncate(atOffset: UInt64(size))
        try handle.close()
    }

    private static func normalize(_ text: String) -> String {
        let lowered = text.lowercased()
        let noPunct = lowered.unicodeScalars.map { scalar -> Character in
            if CharacterSet.punctuationCharacters.contains(scalar) { return " " }
            return Character(scalar)
        }
        return String(noPunct)
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private func withRestoredDefaults(keys: [String], run: () -> Void) {
        let defaults = UserDefaults.standard
        var snapshot: [String: Any] = [:]
        for key in keys {
            if let value = defaults.object(forKey: key) {
                snapshot[key] = value
            }
        }

        defer {
            for key in keys {
                if let previous = snapshot[key] {
                    defaults.set(previous, forKey: key)
                } else {
                    defaults.removeObject(forKey: key)
                }
            }
        }

        run()
    }

    private func withPromptSettingsRestored(run: () -> Void) {
        self.withRestoredDefaults(
            keys: [
                self.dictationPromptProfilesKey,
                self.appPromptBindingsKey,
                self.selectedDictationPromptIDKey,
                self.selectedEditPromptIDKey,
                self.dictationPromptOffKey,
                self.editPromptOffKey,
                self.defaultDictationPromptOverrideKey,
                self.defaultEditPromptOverrideKey,
            ],
            run: run
        )
    }

    private func withProviderSettingsRestored(run: () -> Void) {
        self.withRestoredDefaults(
            keys: [
                self.savedProvidersKey,
                self.selectedProviderIDKey,
                self.availableModelsByProviderKey,
                self.selectedModelByProviderKey,
            ],
            run: run
        )
    }

    private func withPromptAndProviderSettingsRestored(run: () -> Void) {
        self.withRestoredDefaults(
            keys: [
                self.dictationPromptProfilesKey,
                self.appPromptBindingsKey,
                self.selectedDictationPromptIDKey,
                self.selectedEditPromptIDKey,
                self.dictationPromptOffKey,
                self.editPromptOffKey,
                self.defaultDictationPromptOverrideKey,
                self.defaultEditPromptOverrideKey,
                self.savedProvidersKey,
                self.selectedProviderIDKey,
                self.availableModelsByProviderKey,
                self.selectedModelByProviderKey,
                self.verifiedProviderFingerprintsKey,
            ],
            run: run
        )
    }
}

extension DictationE2ETests {
    func testSpokenFormattingActionsUseSharedPrefix() {
        self.withRestoredDefaults(keys: self.punctuationFormattingDefaultsKeys) {
            let settings = SettingsStore.shared
            UserDefaults.standard.set(true, forKey: self.autoConvertPunctuationEnabledKey)
            settings.punctuationDictionaryPrefix = "literal"
            settings.spokenFormattingActionRules = SettingsStore.defaultSpokenFormattingActionRules

            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("First literal next line second"),
                "First\nsecond"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("First literal next paragraph second"),
                "First\n\nsecond"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("one literal tab two"),
                "one\ttwo"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("one   literal space   two"),
                "one two"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("First next line second"),
                "First next line second"
            )
        }
    }

    func testSpokenFormattingActionsRemoveAdjacentGeneratedPeriodsOnly() {
        self.withRestoredDefaults(keys: self.punctuationFormattingDefaultsKeys) {
            let settings = SettingsStore.shared
            UserDefaults.standard.set(true, forKey: self.autoConvertPunctuationEnabledKey)
            settings.punctuationDictionaryPrefix = "literal"
            settings.spokenFormattingActionRules = SettingsStore.defaultSpokenFormattingActionRules

            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("First. literal new line. Second"),
                "First\nSecond"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("First. literal new paragraph. Second"),
                "First\n\nSecond"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("one. literal tab. two"),
                "one\ttwo"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("one. literal space. two"),
                "one two"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("First literal period literal new line Second"),
                "First.\nSecond"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("First literal new line, Second"),
                "First\nSecond"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("First literal new paragraph, Second"),
                "First\n\nSecond"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("First literal new line literal comma Second"),
                "First\n, Second"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("one literal tab, two"),
                "one\t, two"
            )
        }
    }

    func testSpokenFormattingActionsCanBeCustomizedAndUnset() {
        self.withRestoredDefaults(keys: self.punctuationFormattingDefaultsKeys) {
            let settings = SettingsStore.shared
            UserDefaults.standard.set(true, forKey: self.autoConvertPunctuationEnabledKey)
            settings.spokenFormattingActionRules = [
                SettingsStore.SpokenFormattingActionRule(
                    action: .newLine,
                    aliases: ["drop down"]
                ),
                SettingsStore.SpokenFormattingActionRule(
                    action: .tab,
                    aliases: [],
                    isEnabled: true
                ),
                SettingsStore.SpokenFormattingActionRule(
                    action: .space,
                    aliases: ["little gap"],
                    isEnabled: false
                ),
            ]

            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("First literal drop down second"),
                "First\nsecond"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("literal tab"),
                "literal tab"
            )
            XCTAssertEqual(
                ASRService.applySpokenPunctuationFormatting("literal little gap"),
                "literal little gap"
            )
        }
    }

    func testSpokenFormattingActionAliasesRejectPunctuationAndActionConflicts() {
        self.withRestoredDefaults(keys: self.punctuationFormattingDefaultsKeys) {
            let settings = SettingsStore.shared
            settings.spokenFormattingActionRules = [
                SettingsStore.SpokenFormattingActionRule(
                    action: .newLine,
                    aliases: ["comma", "shared action", "drop down"]
                ),
                SettingsStore.SpokenFormattingActionRule(
                    action: .newParagraph,
                    aliases: ["shared action", "paragraph break"]
                ),
            ]

            let rules = settings.spokenFormattingActionRules
            XCTAssertEqual(rules.first { $0.action == .newLine }?.aliases, ["shared action", "drop down"])
            XCTAssertEqual(rules.first { $0.action == .newParagraph }?.aliases, ["paragraph break"])

            UserDefaults.standard.set(true, forKey: self.autoConvertPunctuationEnabledKey)
            XCTAssertEqual(ASRService.applySpokenPunctuationFormatting("literal comma"), ",")
            XCTAssertEqual(ASRService.applySpokenPunctuationFormatting("literal shared action"), "\n")
        }
    }

    func testSpokenFormattingActionRulesRoundTripAndLegacyBackupsPreserveCurrentRules() async throws {
        let defaults = UserDefaults.standard
        let originalValue = defaults.object(forKey: self.spokenFormattingActionRulesKey)
        defer {
            if let originalValue {
                defaults.set(originalValue, forKey: self.spokenFormattingActionRulesKey)
            } else {
                defaults.removeObject(forKey: self.spokenFormattingActionRulesKey)
            }
        }

        let settings = SettingsStore.shared
        let backedUpRules = [
            SettingsStore.SpokenFormattingActionRule(
                action: .newLine,
                aliases: ["line break"]
            ),
            SettingsStore.SpokenFormattingActionRule(
                action: .tab,
                aliases: ["indent"],
                isEnabled: false
            ),
        ]
        settings.spokenFormattingActionRules = backedUpRules

        let document = await BackupService.shared.makeBackupDocument()
        let encoded = try BackupService.shared.encode(document)
        let decoded = try BackupService.shared.decode(encoded)
        XCTAssertEqual(decoded.settings.spokenFormattingActionRules, settings.spokenFormattingActionRules)

        settings.spokenFormattingActionRules = SettingsStore.defaultSpokenFormattingActionRules
        settings.restore(from: decoded.settings)
        XCTAssertEqual(settings.spokenFormattingActionRules, decoded.settings.spokenFormattingActionRules)

        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var encodedSettings = try XCTUnwrap(root["settings"] as? [String: Any])
        encodedSettings.removeValue(forKey: "spokenFormattingActionRules")
        root["settings"] = encodedSettings
        let legacyBackup = try BackupService.shared.decode(JSONSerialization.data(withJSONObject: root))
        XCTAssertNil(legacyBackup.settings.spokenFormattingActionRules)

        let rulesBeforeLegacyRestore = [
            SettingsStore.SpokenFormattingActionRule(
                action: .newParagraph,
                aliases: ["keep this paragraph"]
            ),
        ]
        settings.spokenFormattingActionRules = rulesBeforeLegacyRestore
        let normalizedRulesBeforeLegacyRestore = settings.spokenFormattingActionRules
        settings.restore(from: legacyBackup.settings)
        XCTAssertEqual(settings.spokenFormattingActionRules, normalizedRulesBeforeLegacyRestore)
    }

    func testBackupKeepsDeprecatedIndependentVolumeKeyAndDecodesWithoutIt() async throws {
        let document = try await BackupService.shared.makeBackupDocument()
        let encoded = try BackupService.shared.encode(document)
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        var encodedSettings = try XCTUnwrap(root["settings"] as? [String: Any])
        XCTAssertEqual(encodedSettings["transcriptionSoundIndependentVolume"] as? Bool, false)

        encodedSettings.removeValue(forKey: "transcriptionSoundIndependentVolume")
        root["settings"] = encodedSettings
        let strippedBackup = try BackupService.shared.decode(JSONSerialization.data(withJSONObject: root))
        XCTAssertNil(strippedBackup.settings.transcriptionSoundIndependentVolume)
    }
}

@MainActor
final class OverlayFailureStateTests: XCTestCase {
    func testCustomNonRetryableMessage() {
        let state = NotchContentState.shared
        defer {
            state.showAIProcessingFailure()
            state.clearAIProcessingFailure()
        }

        state.showAIProcessingFailure(
            message: "Edit Mode needs a verified provider",
            canRetry: false
        )

        XCTAssertTrue(state.isAIProcessingFailureVisible)
        XCTAssertEqual(state.aiProcessingFailureMessage, "Edit Mode needs a verified provider")
        XCTAssertFalse(state.canRetryAIProcessingFailure)

        state.showAIProcessingFailure()

        XCTAssertEqual(state.aiProcessingFailureMessage, "AI Enhancement failed")
        XCTAssertTrue(state.canRetryAIProcessingFailure)
    }
}

@MainActor
final class SimpleUpdaterTests: XCTestCase {
    func testUpdateOperationGateAllowsOnlyOneActiveInstall() {
        var gate = UpdateOperationGate()

        XCTAssertTrue(gate.begin())
        XCTAssertTrue(gate.isActive)
        XCTAssertFalse(gate.begin())

        gate.finish()

        XCTAssertFalse(gate.isActive)
        XCTAssertTrue(gate.begin())
    }
}

/// The test host must stay invisible and silent on the operator's machine (see CLAUDE.md).
@MainActor
final class TestHostQuietModeTests: XCTestCase {
    func testQuietModeIsDetectedUnderXCTest() {
        XCTAssertTrue(TestHostQuietMode.isActive, "XCTest hosts the app, so quiet mode must be on")
        XCTAssertTrue(TestHostQuietMode.detect(environment: ["XCTestConfigurationFilePath": "/tmp/x"], arguments: []))
        XCTAssertTrue(TestHostQuietMode.detect(environment: [:], arguments: ["app", "-LiquidVoiceQuietMode", "YES"]))
        XCTAssertFalse(TestHostQuietMode.detect(environment: [:], arguments: ["app", "-LiquidVoiceQuietMode", "NO"]))
        XCTAssertFalse(TestHostQuietMode.detect(environment: [:], arguments: ["app"]))
    }

    func testTestHostNeverActivatesShowsWindowsOrPlaysSound() async throws {
        XCTAssertEqual(TestHostQuietMode.activationPolicy(.regular), .prohibited)
        // Launch-time policy changes are applied asynchronously; let them land.
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(NSApp.activationPolicy(), .prohibited)

        let panel = NSPanel(
            contentRect: NSRect(x: 200, y: 200, width: 120, height: 60),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        panel.orderFrontRegardless()
        panel.makeKeyAndOrderFront(nil)
        panel.orderFront(nil)
        panel.setIsVisible(true)
        XCTAssertFalse(panel.isVisible, "Quiet mode must swallow every way onto the screen")
        panel.close()

        TranscriptionSoundPlayer.shared.playStartSound()
        TranscriptionSoundPlayer.shared.playStopSound()
        OnboardingSoundPlayer.shared.playWelcomeSound()
        XCTAssertEqual(TranscriptionSoundPlayer.shared.createdPlayerCount, 0)
        XCTAssertFalse(OnboardingSoundPlayer.shared.hasCreatedPlayer)

        XCTAssertEqual(Self.onScreenWindowCount(), 0, "The test host owns a window on screen")
    }

    /// Windows this process has on screen right now, as the window server sees them.
    static func onScreenWindowCount() -> Int {
        let pid = ProcessInfo.processInfo.processIdentifier
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]] ?? []
        return windows.filter { ($0[kCGWindowOwnerPID as String] as? pid_t) == pid }.count
    }
}

final class StopPathTraceTests: XCTestCase {
    func testSummaryReportsEachStageFromThePreviousMark() {
        let line = StopPathTrace.summaryLine(
            id: 7,
            trigger: .holdRelease,
            latched: false,
            marks: [
                .trigger: 100.000,
                .stopEnter: 100.002,
                .captureStopped: 100.010,
                .asrBegin: 100.030,
                .asrEnd: 100.090,
                .asrReturn: 100.095,
                .textReady: 100.096,
                .handoff: 100.100,
                .pastePosted: 100.140,
            ],
            details: ["audioMs": "2500", "chars": "17"],
            outcome: "pasted"
        )
        XCTAssertEqual(
            line,
            "STOP_SUMMARY id=7 trigger=hold_release latched=false releaseMs=2.0 captureMs=8.0 drainMs=20.0 " +
                "asrMs=60.0 returnMs=5.0 postMs=1.0 handoffMs=4.0 pasteMs=40.0 sendMs=- totalMs=140.0 lastStage=paste_posted " +
                "audioMs=2500 chars=17 outcome=pasted"
        )
    }

    func testASpokenSendReturnIsReportedAfterTheTextNotInItsTotal() {
        let line = StopPathTrace.summaryLine(
            id: 2,
            trigger: .spokenSend,
            latched: false,
            marks: [.trigger: 1.0, .stopEnter: 1.001, .handoff: 1.1, .pastePosted: 1.12, .sendKeyPosted: 1.25],
            details: [:],
            outcome: "delivered"
        )
        XCTAssertTrue(line.contains("trigger=spoken_send"), line)
        XCTAssertTrue(line.contains("pasteMs=20.0 sendMs=130.0 totalMs=120.0 lastStage=send_key_posted"), line)
    }

    func testSummaryFoldsASkippedStageIntoTheNextOne() {
        let line = StopPathTrace.summaryLine(
            id: 1,
            trigger: .toggle,
            latched: true,
            marks: [.trigger: 10.0, .stopEnter: 10.5, .asrReturn: 10.6],
            details: [:],
            outcome: "empty"
        )
        XCTAssertTrue(line.contains("releaseMs=500.0 captureMs=- drainMs=- asrMs=- returnMs=100.0 postMs=-"), line)
        XCTAssertTrue(line.hasSuffix("totalMs=600.0 lastStage=asr_return outcome=empty"), line)
    }

    func testTraceIsFinishedOnceAndDeliveryOwnsItsEnd() {
        let summaries = SummaryRecorder()
        let trace = StopPathTrace(trigger: .ui, at: 5.0) { summaries.append($0) }
        trace.mark(.stopEnter, at: 5.1)
        trace.expectDelivery()
        trace.finishUnlessDelivering(outcome: "handoff")
        trace.mark(.pastePosted, at: 5.3)
        XCTAssertEqual(trace.elapsedMilliseconds(from: .trigger, to: .pastePosted) ?? 0, 300, accuracy: 0.001)
        XCTAssertTrue(summaries.lines.isEmpty, "the typing service owns the end")
        trace.finish(outcome: "pasted")
        trace.finish(outcome: "again")
        trace.mark(.handoff, at: 5.4) // after finishing: ignored
        XCTAssertNil(trace.elapsedMilliseconds(from: .trigger, to: .handoff))
        XCTAssertEqual(summaries.lines.count, 1)
        XCTAssertTrue(summaries.lines.first?.hasSuffix("outcome=pasted") == true)
    }

    private final class SummaryRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: [String] = []
        var lines: [String] { self.lock.withLock { self.storage } }
        func append(_ line: String) { self.lock.withLock { self.storage.append(line) } }
    }
}

/// Times the real stop pipeline on the dictation fixture, N times in one test-host launch, and
/// reports median and p90 per stage. Headless and silent (TestHostQuietMode): no window on screen,
/// no sound, no focus change. Explicitly invoked, since it loads the Parakeet model:
///
///     xcodebuild ... test -only-testing:FluidDictationIntegrationTests/StopPathLatencyBenchmarkTests \
///       TEST_RUNNER_LIQUID_VOICE_STOP_BENCH=30
///
/// Optional: TEST_RUNNER_LIQUID_VOICE_STOP_BENCH_AUDIO_SECONDS (fixture tiled to this length,
/// default 8), TEST_RUNNER_LIQUID_VOICE_STOP_BENCH_JITTER (seconds of seeded random extra recording
/// per run, so stops land at different points of the streaming preview cycle; default 0),
/// TEST_RUNNER_LIQUID_VOICE_STOP_BENCH_HISTORY (history size, default 13600, the operator's
/// real history) and TEST_RUNNER_LIQUID_VOICE_STOP_BENCH_OUT (JSON results path). Each run stops at
/// the handoff to the typing service: it never types, pastes or touches the clipboard, and the
/// Debug build's history is put back afterwards.
@MainActor
final class StopPathLatencyBenchmarkTests: XCTestCase {
    func testStopPathLatencyOnFixture() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let runsValue = environment["LIQUID_VOICE_STOP_BENCH"], let runs = Int(runsValue), runs > 0 else {
            throw XCTSkip("Set TEST_RUNNER_LIQUID_VOICE_STOP_BENCH=<runs> to run the stop-path benchmark.")
        }
        let audioSeconds = environment["LIQUID_VOICE_STOP_BENCH_AUDIO_SECONDS"].flatMap(Double.init) ?? 8

        var runner = StopPathBenchmark.runDictation
        for _ in 0..<200 where runner == nil {
            try await Task.sleep(nanoseconds: 100_000_000)
            runner = StopPathBenchmark.runDictation
        }
        guard let runner else {
            throw XCTSkip("The app window never appeared, so the stop pipeline is unavailable.")
        }

        let asr = AppServices.shared.asr
        await asr.checkIfModelsExistAsync()
        guard asr.modelsExistOnDisk || asr.isAsrReady else {
            throw XCTSkip("The selected speech model (\(SettingsStore.shared.selectedSpeechModel.displayName)) is not downloaded.")
        }
        try await asr.ensureAsrReady()
        print("STOP_BENCH model=\(SettingsStore.shared.selectedSpeechModel.displayName)")

        // A long history is part of the real stop path (it is saved and summarized on each
        // dictation). Seed the Debug build's history to that size, and put it back afterwards.
        // Every benchmark entry (seeded or dictated) is recorded under StopPathBenchmark.appName,
        // so a run that was killed midway is cleaned up by the next one.
        let historySize = environment["LIQUID_VOICE_STOP_BENCH_HISTORY"].flatMap(Int.init) ?? 13_600
        let history = TranscriptionHistoryStore.shared
        let originalHistory = history.makeBackupPayload().filter { $0.appName != StopPathBenchmark.appName }
        history.restore(from: originalHistory + Self.syntheticHistory(count: historySize))
        defer {
            history.restore(from: originalHistory)
            history.flushPendingWrites()
            // Audio saved for benchmark dictations (when the Debug build keeps audio) belonged to
            // entries that are gone now.
            let referenced = Set(history.entries.compactMap { $0.audio?.fileName })
            _ = DictationAudioHistoryStore.shared.deleteUnreferencedAudioFiles(referencedFileNames: referenced)
        }

        let fixture = try AudioFixtureLoader.load16kMonoFloatSamples(named: "dictation_fixture", ext: "wav")
        var samples: [Float] = []
        while Double(samples.count) / 16_000 < audioSeconds {
            samples.append(contentsOf: fixture)
        }
        let recordingSeconds = Double(samples.count) / 16_000

        // Warm-up: first overlay presentation and first inference are not representative.
        for _ in 0..<2 {
            _ = await runner(samples, recordingSeconds)
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        let stages: [(name: String, from: StopPathTrace.Stage, to: StopPathTrace.Stage)] = [
            ("stop_enter -> capture_stopped", .stopEnter, .captureStopped),
            ("capture_stopped -> asr_begin", .captureStopped, .asrBegin),
            ("asr_begin -> asr_end (model)", .asrBegin, .asrEnd),
            ("asr_end -> asr_return", .asrEnd, .asrReturn),
            ("asr_return -> text_ready", .asrReturn, .textReady),
            ("text_ready -> handoff", .textReady, .handoff),
            ("stop_enter -> handoff (total)", .stopEnter, .handoff),
        ]
        // Optional stop-time jitter (seconds, uniform, same seeded sequence every run): without it
        // every stop lands at the same point of the streaming preview cycle.
        let jitter = environment["LIQUID_VOICE_STOP_BENCH_JITTER"].flatMap(Double.init) ?? 0
        var generator = SeededGenerator(seed: 0x5EED)
        var samplesByStage: [String: [Double]] = [:]
        for _ in 0..<runs {
            let holdSeconds = recordingSeconds + (jitter > 0 ? Double.random(in: 0..<jitter, using: &generator) : 0)
            let finished = await runner(samples, holdSeconds)
            let trace = try XCTUnwrap(finished, "A recording was already active")
            XCTAssertEqual(TestHostQuietModeTests.onScreenWindowCount(), 0, "The benchmark put a window on screen")
            for stage in stages {
                if let value = trace.elapsedMilliseconds(from: stage.from, to: stage.to) {
                    samplesByStage[stage.name, default: []].append(value)
                }
            }
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        func percentile(_ values: [Double], _ p: Double) -> Double {
            let sorted = values.sorted()
            guard !sorted.isEmpty else { return .nan }
            let rank = p * Double(sorted.count - 1)
            let lower = Int(rank.rounded(.down))
            let upper = min(lower + 1, sorted.count - 1)
            return sorted[lower] + (sorted[upper] - sorted[lower]) * (rank - Double(lower))
        }

        var report: [[String: Any]] = []
        var lines = ["STOP_BENCH runs=\(runs) audioMs=\(Int(recordingSeconds * 1000)) history=\(historySize) jitterMs=\(Int(jitter * 1000))"]
        for stage in stages {
            let values = samplesByStage[stage.name] ?? []
            let median = percentile(values, 0.5)
            let p90 = percentile(values, 0.9)
            lines.append(String(format: "STOP_BENCH %-32@ n=%3d median=%7.1f p90=%7.1f", stage.name as NSString, values.count, median, p90))
            report.append(["stage": stage.name, "n": values.count, "medianMs": median, "p90Ms": p90, "valuesMs": values])
        }
        lines.forEach { print($0) }
        DebugLogger.shared.info(lines.joined(separator: "\n"), source: "StopPathBenchmark")
        if let outPath = environment["LIQUID_VOICE_STOP_BENCH_OUT"] {
            let data = try JSONSerialization.data(withJSONObject: ["audioMs": Int(recordingSeconds * 1000), "runs": runs, "stages": report], options: [.prettyPrinted])
            try data.write(to: URL(fileURLWithPath: outPath))
        }
        XCTAssertEqual(samplesByStage["stop_enter -> handoff (total)"]?.count, runs, "Every run should reach the handoff")
        XCTAssertEqual(TranscriptionSoundPlayer.shared.createdPlayerCount, 0, "The benchmark created a sound player")
    }

    /// SplitMix64: a reproducible jitter sequence, the same for every build that is compared.
    private struct SeededGenerator: RandomNumberGenerator {
        var state: UInt64
        init(seed: UInt64) { self.state = seed }
        mutating func next() -> UInt64 {
            self.state &+= 0x9E37_79B9_7F4A_7C15
            var z = self.state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    /// Entries shaped like real dictations: about 150 characters, spread over 60 days with a
    /// busy "today".
    private static func syntheticHistory(count: Int) -> [TranscriptionHistoryEntry] {
        let sentence = "Please look at the stop path and tell me where the time goes before the text lands in the terminal window today"
        let now = Date()
        return (0..<count).map { index in
            let age = index < 200 ? Double(index) * 60 : Double(index) * 380
            return TranscriptionHistoryEntry(
                timestamp: now.addingTimeInterval(-age),
                rawText: sentence,
                processedText: sentence + " \(index).",
                appName: StopPathBenchmark.appName,
                windowTitle: "",
                wasAIProcessed: false
            )
        }
    }
}

@MainActor
final class TranscriptionHistoryPersistenceTests: XCTestCase {
    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        self.suiteName = "LiquidVoiceHistoryTests.\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: self.suiteName)
    }

    override func tearDown() {
        self.defaults.removePersistentDomain(forName: self.suiteName)
        super.tearDown()
    }

    func testEntriesAreWrittenOffTheMainThreadAndSurviveAReload() {
        let store = TranscriptionHistoryStore(defaults: self.defaults)
        store.addEntry(rawText: "first", processedText: "First one.", appName: "c11", windowTitle: "")
        store.addEntry(rawText: "second", processedText: "Second one.", appName: "c11", windowTitle: "")
        store.flushPendingWrites()

        let reloaded = TranscriptionHistoryStore(defaults: self.defaults)
        XCTAssertEqual(reloaded.entries.map(\.processedText), ["Second one.", "First one."])
    }

    func testABurstOfChangesEndsWithTheLatestHistoryOnDisk() {
        let store = TranscriptionHistoryStore(defaults: self.defaults)
        let entries = (0..<500).map {
            TranscriptionHistoryEntry(rawText: "r\($0)", processedText: "p\($0)", appName: "c11", windowTitle: "", wasAIProcessed: false)
        }
        store.restore(from: entries)
        for index in 0..<20 {
            store.addEntry(rawText: "burst", processedText: "Burst \(index).", appName: "c11", windowTitle: "")
        }
        store.deleteEntry(id: store.entries[1].id)
        store.flushPendingWrites()

        let reloaded = TranscriptionHistoryStore(defaults: self.defaults)
        XCTAssertEqual(reloaded.entries.count, 519)
        XCTAssertEqual(reloaded.entries.first?.processedText, "Burst 19.")
        XCTAssertFalse(reloaded.entries.contains { $0.processedText == "Burst 18." })
    }

    func testTodaySummaryIsCachedAndFollowsTheHistory() async {
        let store = TranscriptionHistoryStore(defaults: self.defaults)
        store.restore(from: [
            TranscriptionHistoryEntry(timestamp: Date().addingTimeInterval(-3 * 86_400), rawText: "old", processedText: "an old one here", appName: "c11", windowTitle: "", wasAIProcessed: false),
        ])
        store.addEntry(rawText: "a", processedText: "three words here", appName: "c11", windowTitle: "")
        store.addEntry(rawText: "b", processedText: "two words", appName: "c11", windowTitle: "")
        await store.waitForTodaySummary()
        XCTAssertEqual(store.todaySummary, TranscriptionHistoryStore.TodaySummary(words: 5, transcriptions: 2))

        store.deleteEntries(ids: Set(store.entries.map(\.id)))
        await store.waitForTodaySummary()
        XCTAssertEqual(store.todaySummary, TranscriptionHistoryStore.TodaySummary(words: 0, transcriptions: 0))
        store.flushPendingWrites()
    }
}

@MainActor
final class StopUIRefreshHoldTests: XCTestCase {
    func testASRChangesDuringAStopReachTheAppUIOnceWhenTheHoldEnds() {
        let asr = AppServices.shared.asr
        var forwarded = 0
        let subscription = AppServices.shared.objectWillChange.sink { forwarded += 1 }
        defer { subscription.cancel() }

        let hold = asr.holdStopUIRefresh()
        XCTAssertTrue(asr.holdsStopUIRefresh)
        asr.objectWillChange.send()
        asr.objectWillChange.send()
        XCTAssertEqual(forwarded, 0, "no whole-app rebuild while the stop pipeline runs")

        asr.releaseStopUIRefresh(hold)
        XCTAssertFalse(asr.holdsStopUIRefresh)
        XCTAssertEqual(forwarded, 1, "one refresh when the text has been handed off")

        asr.releaseStopUIRefresh(hold)
        asr.objectWillChange.send()
        XCTAssertEqual(forwarded, 2, "released twice is harmless; later changes forward as usual")
    }

    func testAnOlderHoldCannotEndANewerOne() {
        let asr = AppServices.shared.asr
        let older = asr.holdStopUIRefresh()
        let newer = asr.holdStopUIRefresh()
        asr.releaseStopUIRefresh(older)
        XCTAssertTrue(asr.holdsStopUIRefresh)
        asr.releaseStopUIRefresh(newer)
        XCTAssertFalse(asr.holdsStopUIRefresh)
    }
}

final class DictationStreamingFallbackPolicyTests: XCTestCase {
    func testOnlyAResponseTheServerCouldNotStreamIsRetriedWithoutStreaming() {
        XCTAssertTrue(DictationStreamingFallbackPolicy.shouldRetryWithoutStreaming(after: LLMError.invalidResponse))
        XCTAssertTrue(DictationStreamingFallbackPolicy.shouldRetryWithoutStreaming(after: LLMError.httpError(400, "no stream")))

        XCTAssertFalse(DictationStreamingFallbackPolicy.shouldRetryWithoutStreaming(after: LLMError.timeout(30)))
        XCTAssertFalse(DictationStreamingFallbackPolicy.shouldRetryWithoutStreaming(after: LLMError.networkError(URLError(.notConnectedToInternet))))
        XCTAssertFalse(DictationStreamingFallbackPolicy.shouldRetryWithoutStreaming(after: LLMError.invalidURL))
        XCTAssertFalse(DictationStreamingFallbackPolicy.shouldRetryWithoutStreaming(after: URLError(.timedOut)))
        XCTAssertFalse(DictationStreamingFallbackPolicy.shouldRetryWithoutStreaming(after: CancellationError()))
    }
}

@MainActor
final class TranscriptionTimeoutTests: XCTestCase {
    func testTheWaitForAStalledPreviewScalesWithTheRecording() {
        XCTAssertEqual(ASRService.streamingChunkDrainTimeoutNanoseconds(forSampleCount: 16_000 * 8), 30_000_000_000)
        XCTAssertEqual(ASRService.streamingChunkDrainTimeoutNanoseconds(forSampleCount: 16_000 * 60), 30_000_000_000)
        XCTAssertEqual(ASRService.streamingChunkDrainTimeoutNanoseconds(forSampleCount: 16_000 * 600), 300_000_000_000)
    }

    func testTheTimeoutCardOffersReprocessOnlyWhenAudioIsKept() {
        let controller = DeliveryFailureOverlayController.shared
        controller.showTranscriptionTimeout(.timedOut)
        XCTAssertEqual(controller.presentedTimeout, .timedOut)
        XCTAssertNil(controller.presentedFailure)
        controller.showTranscriptionTimeout(.recordingRefused(hasKeptAudio: false))
        XCTAssertEqual(controller.presentedTimeout, .recordingRefused(hasKeptAudio: false))
        controller.hide()
        XCTAssertNil(controller.presentedTimeout)
        XCTAssertEqual(TestHostQuietModeTests.onScreenWindowCount(), 0)
    }
}

final class KeptDictationStorageTests: XCTestCase {
    private var root: URL!
    private var store: DictationAudioHistoryStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        // Never the Debug build's own storage.
        self.root = FileManager.default.temporaryDirectory
            .appendingPathComponent("KeptDictationStorageTests-\(UUID().uuidString)", isDirectory: true)
        self.store = DictationAudioHistoryStore(rootDirectoryOverride: self.root)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: self.root)
        try super.tearDownWithError()
    }

    func testTheKeptRecordingReadsBackAsWritten() throws {
        let samples: [Float] = (0..<1600).map { Float(sin(Double($0) / 7)) * 0.5 }
        let original = DictationAudioSnapshot(samples: samples, sampleRate: 16_000, channels: 1)
        let stoppedAt = Date(timeIntervalSince1970: 1_790_000_000.123)
        self.store.saveKeptDictation(original, stoppedAt: stoppedAt)

        XCTAssertEqual(self.store.keptDictationStoppedAt()?.timeIntervalSince1970 ?? 0, stoppedAt.timeIntervalSince1970, accuracy: 0.001)
        XCTAssertTrue(FileManager.default.fileExists(atPath: self.root.appendingPathComponent("KeptDictation").path))
        let loaded = try XCTUnwrap(self.store.loadKeptDictation())
        XCTAssertEqual(loaded.sampleRate, 16_000)
        XCTAssertEqual(loaded.channels, 1)
        XCTAssertEqual(loaded.samples.count, samples.count)
        for (read, written) in zip(loaded.samples, samples) {
            XCTAssertEqual(read, written, accuracy: 1.0 / 16_000, "16-bit round trip")
        }

        self.store.deleteKeptDictation()
        XCTAssertNil(self.store.keptDictationStoppedAt())
        XCTAssertNil(self.store.loadKeptDictation())
    }

    func testANewerKeptRecordingReplacesTheOlderOne() {
        let audio = DictationAudioSnapshot(samples: [0.1, 0.2], sampleRate: 16_000, channels: 1)
        self.store.saveKeptDictation(audio, stoppedAt: Date(timeIntervalSince1970: 1_000))
        self.store.saveKeptDictation(audio, stoppedAt: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(self.store.keptDictationStoppedAt(), Date(timeIntervalSince1970: 2_000))
    }

    func testDeletingAllHistoryAudioLeavesTheKeptRecordingToTheExplicitDiscard() {
        let audio = DictationAudioSnapshot(samples: [0.1, 0.2], sampleRate: 16_000, channels: 1)
        self.store.saveKeptDictation(audio, stoppedAt: Date(timeIntervalSince1970: 3_000))
        // History audio lives in its own folder: a prune or delete-all of it never reaches the kept file.
        self.store.deleteAllAudioFiles()
        XCTAssertNotNil(self.store.keptDictationStoppedAt())

        let discarded = expectation(forNotification: DictationAudioHistoryStore.keptDictationDiscardedNotification, object: nil)
        self.store.discardKeptDictation()
        wait(for: [discarded], timeout: 2)
        XCTAssertNil(self.store.keptDictationStoppedAt())
    }
}

/// Offscreen renders of the Signal overlay's states, for comparison with the binding prototype
/// (design/visual-language/native-renders). Nothing reaches the screen: the views are hosted in
/// no window and drawn into bitmaps. Set TEST_RUNNER_LIQUID_VOICE_RENDER_DIR=<folder> to write
/// the PNGs; without it the test only checks that every state renders at the designed size.
@MainActor
final class SignalOverlayRenderTests: XCTestCase {
    private var outputFolder: URL? {
        ProcessInfo.processInfo.environment["LIQUID_VOICE_RENDER_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private var savedHistory: [TranscriptionHistoryEntry] = []

    override func setUp() {
        super.setUp()
        // The Debug test host's own history (never the installed app's), put back in tearDown.
        self.savedHistory = TranscriptionHistoryStore.shared.makeBackupPayload()
        TranscriptionHistoryStore.shared.restore(from: SignalRenderStage.sampleHistory)
    }

    override func tearDown() {
        SignalRenderStage.reset()
        TranscriptionHistoryStore.shared.restore(from: self.savedHistory)
        super.tearDown()
    }

    /// Recovery cards (DESIGN.md §15, round 6): the pill grows upward to 156 (one-line card), 210
    /// (failed) or 226 (two-line reason); the rails and the rows below the card stay where the
    /// overlay's are.
    func testRecoveryCardsGrowThePillUpward() throws {
        let transcript = "Okay, take a look at the retry admission path in the queue worker. When the same job ID lands twice inside the lease window we are admitting both and the second one clobbers the first one's checkpoint so I think the fix is to key the admission set."
        let cards: [(String, SignalCardContent, CGFloat)] = [
            ("07-failed", SignalCardContent(headline: "Couldn\u{2019}t paste into c11", reason: "No text field focused", transcript: transcript, primary: .copy, meta: "118 words"), 210),
            ("17-failed-clipboardkept", SignalCardContent(headline: "Couldn\u{2019}t paste into c11", reason: DeliveryFailureOverlayController.reasonText(failure: .pasteNotLanded, clipboard: .newerClipboardCopy, inHistory: true), transcript: transcript, primary: .copy, meta: "118 words"), 226),
            ("18-timedout", SignalCardContent(headline: "Transcription timed out", reason: "Your audio is kept", primary: .reprocess), 156),
            ("20-micoff", SignalCardContent(headline: "Microphone access is off", reason: "Allow Liquid Voice in Privacy & Security", primary: .openSystemSettings, isMicrophoneOff: true), 156),
        ]
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let theme = appearance == .darkAqua ? "dark" : "light"
            for (name, content, pillHeight) in cards {
                let card = DeliveryFailureCardView(
                    content: content,
                    icon: NSWorkspace.shared.icon(forFile: "/Applications/c11.app"),
                    timerText: "0:41",
                    microphoneName: "MacBook Pro Microphone",
                    onPrimary: {},
                    onDismiss: {},
                    onHoverChanged: { _ in }
                )
                // Padding 10 · card · gap 6 · trace row 38 · gap 4 · foot 16 · padding 8.
                XCTAssertEqual(content.height(width: 316) + 10 + 6 + 38 + 4 + 16 + 8, pillHeight, "\(name)")
                let rep = try SignalRenderStage.render(card, appearance: appearance)
                XCTAssertEqual(rep.size.height, pillHeight + 14 + 2 * SignalRenderStage.backdropMargin, "\(theme) \(name)")
                if let folder = self.outputFolder {
                    try SignalRenderStage.write(rep, to: folder.appendingPathComponent("\(theme)-\(name).png"))
                }
            }
        }
    }

    /// The menu bar mark (DESIGN.md §10): 22 x 16 template images, one per state, the same width
    /// in every state; and the menu's mono header row.
    func testMenuBarMarkStatesAndHeader() throws {
        let trace = SignalTraceModel(barCount: 39)
        trace.begin(at: 0)
        for step in 0..<60 {
            trace.ingest(level: step % 3 == 0 ? 0.95 : 0.6, at: Double(step) / 12)
        }
        let listeningBars = SignalMenuBarMark.listeningBars(from: trace, at: 59.0 / 12)
        XCTAssertEqual(listeningBars.count, 3)
        XCTAssertTrue(listeningBars.allSatisfy { $0 >= 4 && $0 <= 12 && $0.truncatingRemainder(dividingBy: 2) == 0 })

        let marks: [(String, NSImage)] = [
            ("idle", SignalMenuBarMark.image(kind: .idle, bracket: false)),
            ("idle-hover", SignalMenuBarMark.image(kind: .idle, bracket: true)),
            ("listening", SignalMenuBarMark.image(kind: .listening, bars: listeningBars, bracket: false)),
            ("listening-open", SignalMenuBarMark.image(kind: .listening, bars: listeningBars, bracket: true)),
            ("transcribing", SignalMenuBarMark.image(kind: .transcribing, bracket: false)),
        ]
        for (_, image) in marks {
            XCTAssertEqual(image.size, NSSize(width: 22, height: 16))
            XCTAssertTrue(image.isTemplate)
        }

        guard let folder = self.outputFolder else { return }
        for (theme, background, ink) in [("dark", NSColor(white: 0.16, alpha: 1), NSColor.white), ("light", NSColor(white: 0.93, alpha: 1), NSColor.black)] {
            // The marks side by side at 4x, tinted as the menu bar tints a template image.
            let scale: CGFloat = 4
            let size = NSSize(width: CGFloat(marks.count) * 34 + 6, height: 28)
            let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            rep.size = size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            background.setFill()
            NSRect(origin: .zero, size: size).fill()
            for (index, entry) in marks.enumerated() {
                let tinted = NSImage(size: entry.1.size, flipped: false) { rect in
                    entry.1.draw(in: rect)
                    ink.set()
                    rect.fill(using: .sourceAtop)
                    return true
                }
                tinted.draw(in: NSRect(x: 6 + CGFloat(index) * 34, y: 6, width: 22, height: 16))
            }
            NSGraphicsContext.restoreGraphicsState()
            try SignalRenderStage.write(rep, to: folder.appendingPathComponent("\(theme)-21-menubar-marks.png"))

            let header = SignalMenuHeaderView(frame: NSRect(x: 0, y: 0, width: 262, height: 24))
            header.stateText = "Listening 0:37"
            header.isLive = true
            let headerRep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 262 * 2, pixelsHigh: 24 * 2, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            headerRep.size = header.bounds.size
            NSGraphicsContext.saveGraphicsState()
            let headerContext = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: headerRep))
            NSGraphicsContext.current = headerContext
            // The menu's own background stands behind the row in a real menu.
            NSAppearance(named: theme == "dark" ? .darkAqua : .aqua)?.performAsCurrentDrawingAppearance {
                background.setFill()
                header.bounds.fill()
                headerContext.cgContext.translateBy(x: 0, y: header.bounds.height)
                headerContext.cgContext.scaleBy(x: 1, y: -1)
                NSGraphicsContext.current = NSGraphicsContext(cgContext: headerContext.cgContext, flipped: true)
                header.draw(header.bounds)
            }
            NSGraphicsContext.restoreGraphicsState()
            try SignalRenderStage.write(headerRep, to: folder.appendingPathComponent("\(theme)-22-menu-header.png"))
        }
    }

    func testHistoryCardRendersCentredAboveTheOverlay() throws {
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let theme = appearance == .darkAqua ? "dark" : "light"
            for (name, hoverRow) in [("09-history", nil), ("10-history-hover-row", 2)] as [(String, Int?)] {
                SignalRenderStage.reset()
                SignalRenderStage.listening()
                // The History chip stays inverted while its card is open.
                BottomOverlayHistoryMenuController.shared.holdLatchedForInspection(true)
                defer { BottomOverlayHistoryMenuController.shared.holdLatchedForInspection(false) }
                let card = SignalHistoryCard(
                    entries: SignalRenderStage.sampleHistory,
                    totalCount: 247,
                    notPasted: [SignalRenderStage.sampleHistory[2].processedText],
                    now: SignalRenderStage.sampleNow,
                    inspectionHoverRow: hoverRow,
                    isStatic: true,
                    onPick: { _ in }
                )
                // The card's box sits 6 pt above the overlay, centred on it (Atin, 2026-10-01). The
                // card view's bottom margin (8) and the overlay's top margin (6) overlap by 8.
                let insets = SignalTheme.Metrics.windowInsets
                let composite = VStack(alignment: .center, spacing: -insets.bottom) {
                    card.padding(insets).signalPalette()
                    BottomOverlayView()
                }
                let rep = try SignalRenderStage.render(composite, appearance: appearance)
                XCTAssertEqual(rep.size.width, 480 + 12 + 2 * SignalRenderStage.backdropMargin, "\(theme) \(name)")
                // The card at its 480 maximum over the overlay (161), overlapping by the 6 pt margin.
                XCTAssertLessThanOrEqual(rep.size.height, 480 + 14 + 163 - 8 + 2 * SignalRenderStage.backdropMargin, "\(theme) \(name)")
                if let folder = self.outputFolder {
                    try SignalRenderStage.write(rep, to: folder.appendingPathComponent("\(theme)-\(name).png"))
                }
            }
        }
    }

    func testOverlayStatesRenderAtTheDesignedSize() throws {
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let theme = appearance == .darkAqua ? "dark" : "light"
            for (name, setUp) in SignalRenderStage.overlayStates {
                SignalRenderStage.reset()
                setUp()
                let rep = try SignalRenderStage.render(BottomOverlayView(), appearance: appearance)
                // Rails (30 + 6) either side of the 340 pill, plus the 6 pt bracket margin.
                XCTAssertEqual(rep.size.width, 6 + 30 + 6 + 340 + 6 + 30 + 6 + 2 * SignalRenderStage.backdropMargin, "\(theme) \(name)")
                XCTAssertEqual(rep.size.height, 130 + 14 + 2 * SignalRenderStage.backdropMargin, "\(theme) \(name)")
                if let folder = self.outputFolder {
                    try SignalRenderStage.write(rep, to: folder.appendingPathComponent("\(theme)-\(name).png"))
                }
            }
        }
    }
}

/// Drives the shared overlay state into each design state, and draws hosted views to bitmaps.
@MainActor
enum SignalRenderStage {
    static let backdropMargin: CGFloat = 18
    static let sampleNow = Date()

    /// Twelve dictations like the prototype's mock history: today and yesterday, c11 mostly.
    static let sampleHistory: [TranscriptionHistoryEntry] = {
        let texts: [(String, String, Int)] = [
            ("Okay, take a look at the retry admission path in the queue worker. When the same job ID lands twice inside the lease window we are admitting both and the second one clobbers the first one's checkpoint.", "c11", 41),
            ("Yes, go ahead and merge it. Then close the worktree.", "c11", 5),
            ("Draft a reply to Marcus: the settings window gets four panes, general, microphone, hotkeys and dictionary, and the stats page goes.", "Mail", 22),
            ("Run the full suite once more and paste the summary line into the PR description.", "c11", 7),
            ("Looks good to me. One nit: the error message on line 42 says microphone unavailable but the actual cause is the permission being denied, so say that instead.", "Safari", 15),
            ("New task. A small command line tool that reads the Aranet4 over Bluetooth and prints CO2, temperature, humidity and pressure as one line, with a JSON flag for agents.", "c11", 88),
            ("Remind me to check the overnight benchmark on Atlas before standup.", "Notes", 4),
            ("Rename the lane branch to port restyle and push it.", "c11", 6),
            ("The trace should keep scrolling through silence at two points, not stop.", "c11", 9),
            ("Thanks, that works. Ship it.", "Messages", 3),
            ("Open the prototype, press three, then T, and compare the sweep with the native render.", "c11", 12),
            ("Summarize what changed in round five in three bullets.", "c11", 8),
        ]
        return texts.enumerated().map { index, item in
            let minutesAgo = index < 7 ? Double(index * 23 + 4) : Double(24 * 60 + index * 40)
            return TranscriptionHistoryEntry(
                timestamp: sampleNow.addingTimeInterval(-minutesAgo * 60),
                rawText: item.0,
                processedText: item.0,
                appName: item.1,
                windowTitle: "",
                wasAIProcessed: false,
                audio: DictationAudioMetadata(fileName: "sample-\(index).wav", durationMilliseconds: item.2 * 1000, byteCount: 0, sampleRate: 16000, channels: 1, model: nil)
            )
        }
    }()
    static let transcript = "worker sees the same job id land twice so key the admission set on job id plus lease epoch and do not touch the scheduler when you are done give me a one line summary and the diff stat and if the suite takes longer than a minute tell me which tests are"

    static let overlayStates: [(String, () -> Void)] = [
        ("01-listening", { SignalRenderStage.listening() }),
        ("02-listening-hover", { SignalRenderStage.listening(); SignalOverlayModel.shared.inspectionHover = "pill" }),
        ("03-listening-hover-cancel", { SignalRenderStage.listening(); SignalOverlayModel.shared.inspectionHover = "cancel" }),
        ("04-listening-armed", { SignalRenderStage.listening(); SignalOverlayModel.shared.inspectionPlacard = .send }),
        // While SEND shows, a click on the pill cancels the Return: the pill is clickable, so it
        // takes a bracket (DESIGN.md §7). Hovered at rest (02) it takes none.
        ("04b-listening-armed-hover", { SignalRenderStage.listening(); SignalOverlayModel.shared.inspectionPlacard = .send; SignalOverlayModel.shared.inspectionHover = "pill" }),
        ("05-transcribing", { SignalRenderStage.listening(); SignalRenderStage.stop(); NotchContentState.shared.setProcessing(true); SignalOverlayModel.shared.beginTranscribing(); SignalOverlayModel.shared.inspectionSweepProgress = 0.45 }),
        ("06-pasted", { SignalRenderStage.listening(); SignalRenderStage.stop(); SignalOverlayModel.shared.showDelivered(SignalDelivery(appName: "c11", words: 118, method: .paste, sentReturn: false)) }),
        ("13-countdown", { SignalRenderStage.listening(); SignalOverlayModel.shared.inspectionPlacard = .send; SignalOverlayModel.shared.startSendCountdown(duration: 1.5, at: Date().addingTimeInterval(-0.55)) }),
        ("14-countdown-canceled", {
            SignalRenderStage.listening()
            SignalOverlayModel.shared.startSendCountdown(duration: 1.5, at: Date().addingTimeInterval(-0.6))
            SignalOverlayModel.shared.freezeSendCountdown()
        }),
        ("15-sent", { SignalRenderStage.listening(); SignalRenderStage.stop(placard: .send); SignalOverlayModel.shared.showDelivered(SignalDelivery(appName: "c11", words: 118, method: .paste, sentReturn: true)) }),
        ("19-asrback", { SignalRenderStage.listening(); SignalRenderStage.stop(); SignalOverlayModel.shared.showNotice(.recognitionBack, frozenDuration: 41) }),
        ("19-asrback-hover-reprocess", {
            SignalRenderStage.listening()
            SignalRenderStage.stop()
            SignalOverlayModel.shared.showNotice(.recognitionBack, frozenDuration: 41)
            SignalOverlayModel.shared.inspectionHover = "notice-reprocess"
        }),
        ("16-noreturn", { SignalRenderStage.listening(); SignalOverlayModel.shared.inspectionPlacard = .noReturn }),
    ]

    static func listening() {
        let state = NotchContentState.shared
        let model = SignalOverlayModel.shared
        state.setBottomOverlayPresented(true)
        state.mode = .dictation
        state.targetAppIcon = NSWorkspace.shared.icon(forFile: "/Applications/c11.app")
        state.updateTranscription(self.transcript)
        model.ensureTraceBars(SignalOverlayGeometry.forSize(.medium).traceBars)
        model.microphoneName = "MacBook Pro Microphone"
        let now = Date()
        model.beginRecording(at: now.addingTimeInterval(-38.4), noiseThreshold: 0.4)
        // A seeded voice envelope over the last few seconds, one level per 10.7 ms like a real tap.
        var seed: UInt64 = 7
        let start = now.timeIntervalSinceReferenceDate - 4
        model.trace.begin(at: start)
        for step in 0..<Int(4 / 0.0107) {
            seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let noise = CGFloat(seed >> 33) / CGFloat(1 << 31)
            let t = Double(step) * 0.0107
            let speech = max(0, sin(t * 2.1) * 0.5 + 0.5) * (t.truncatingRemainder(dividingBy: 1.3) < 0.9 ? 1 : 0.2)
            model.trace.ingest(level: 0.35 + 0.65 * speech * (0.6 + 0.4 * noise), at: start + t)
        }
        model.trace.advance(to: now.timeIntervalSinceReferenceDate - 0.1)
    }

    static func stop(placard: SignalPlacard = .none) {
        SignalOverlayModel.shared.stopRecording(at: Date().addingTimeInterval(-1), preview: self.transcript, placard: placard)
    }

    static func reset() {
        let state = NotchContentState.shared
        state.setProcessing(false)
        state.setBottomOverlayPresented(false)
        state.updateTranscription("")
        state.targetAppIcon = nil
        let model = SignalOverlayModel.shared
        model.inspectionHover = nil
        model.inspectionPlacard = nil
        model.inspectionSweepProgress = nil
        model.reset()
    }

    /// Draws `view` at 2x over a split backdrop like the prototype's stage (a dark terminal above,
    /// the desktop below), so the brackets' knockout halo is exercised. SwiftUI's ImageRenderer
    /// keeps the transparent margin transparent (NSView.cacheDisplay paints it white).
    static func render(_ view: some View, appearance: NSAppearance.Name) throws -> NSBitmapImageRep {
        let scheme: ColorScheme = appearance == .darkAqua ? .dark : .light
        let renderer = ImageRenderer(content: view.environment(\.colorScheme, scheme))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        let content = NSSize(width: CGFloat(image.width) / 2, height: CGFloat(image.height) / 2)
        let size = NSSize(width: content.width + 2 * self.backdropMargin, height: content.height + 2 * self.backdropMargin)
        let rep = try XCTUnwrap(NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width * 2),
            pixelsHigh: Int(size.height * 2),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ))
        rep.size = size
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(srgbRed: 0.24, green: 0.29, blue: 0.40, alpha: 1).setFill()
        NSRect(origin: .zero, size: size).fill()
        NSColor(srgbRed: 0.06, green: 0.07, blue: 0.09, alpha: 1).setFill()
        NSRect(x: 0, y: size.height * 0.45, width: size.width, height: size.height * 0.55).fill()
        NSGraphicsContext.current?.cgContext.draw(
            image,
            in: CGRect(x: self.backdropMargin, y: self.backdropMargin, width: content.width, height: content.height)
        )
        NSGraphicsContext.restoreGraphicsState()
        return rep
    }

    static func write(_ rep: NSBitmapImageRep, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try XCTUnwrap(rep.representation(using: .png, properties: [:]))
        try data.write(to: url)
    }
}

/// The Signal overlay's behavior: the trace sampler, the geometry, the truthful wording, which
/// chips act when, and the delivered hold (quiet: no window reaches the screen).
@MainActor
final class SignalOverlayBehaviorTests: XCTestCase {
    private var savedOverlayPosition = SettingsStore.OverlayPosition.bottom

    override func setUp() {
        super.setUp()
        BottomOverlayWindowController.deliveredHold = 0.2
        // The pill (and its notice row) is the bottom overlay's.
        self.savedOverlayPosition = SettingsStore.shared.overlayPosition
        SettingsStore.shared.overlayPosition = .bottom
    }

    override func tearDown() {
        SettingsStore.shared.overlayPosition = self.savedOverlayPosition
        BottomOverlayWindowController.deliveredHold = SignalTheme.Motion.deliveredHold
        TypingService.dictationOutcomeHandler = { outcome in
            BottomOverlayWindowController.shared.dictationDeliveryFinished(outcome)
        }
        SignalRenderStage.reset()
        super.tearDown()
    }

    /// "Speech recognition is back" is a notice row in the pill (DESIGN.md §15), not a card: no
    /// growth, the same Reprocess, and it leaves like the pill does (fade, alpha 0, nothing painted,
    /// never ignoresMouseEvents, parked after the idle delay).
    func testRecognitionBackIsANoticeRowWithTheSameReprocess() async throws {
        let controller = BottomOverlayWindowController.shared
        let model = SignalOverlayModel.shared
        let cards = DeliveryFailureOverlayController.shared
        let savedReprocess = NotchContentState.shared.onReprocessLastRequested
        let savedParkDelay = BottomOverlayWindowController.idleParkingDelay
        var reprocesses = 0
        NotchContentState.shared.onReprocessLastRequested = { reprocesses += 1 }
        BottomOverlayWindowController.idleParkingDelay = 0
        defer {
            NotchContentState.shared.onReprocessLastRequested = savedReprocess
            BottomOverlayWindowController.idleParkingDelay = savedParkDelay
        }
        controller.prepare()
        await Task.yield()

        cards.showTranscriptionTimeout(.recovered)
        XCTAssertEqual(model.phase, .notice(.recognitionBack))
        XCTAssertTrue(NotchContentState.shared.isBottomOverlayPresented)
        XCTAssertFalse(cards.isVisible, "no card")
        XCTAssertNil(cards.presentedTimeout)
        XCTAssertEqual(controller.windowStateForTests?.alpha, 1)
        XCTAssertEqual(BottomOverlayView.display(contentState: .shared, model: model), .noticeRow(.recognitionBack))
        XCTAssertFalse(BottomOverlayView.isChipInert(.cancel, display: .noticeRow(.recognitionBack)), "Cancel dismisses it")

        // Reprocess: the same call as the chip and the card, once; the notice gives way.
        controller.reprocessFromNotice()
        XCTAssertEqual(reprocesses, 1)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(NotchContentState.shared.isBottomOverlayPresented)

        // Dismiss: the pill's fade, then nothing painted and parked.
        cards.showTranscriptionTimeout(.recovered)
        controller.dismissNotice()
        try await Task.sleep(nanoseconds: 300_000_000)
        let hidden = try XCTUnwrap(controller.windowStateForTests)
        XCTAssertFalse(NotchContentState.shared.isBottomOverlayPresented)
        XCTAssertEqual(hidden.alpha, 0)
        XCTAssertFalse(hidden.ignoresMouse)
        XCTAssertFalse(controller.contentPaintsPixelsForTests())
        XCTAssertTrue(hidden.isParkedOffscreen)
        XCTAssertEqual(model.phase, .idle)
        XCTAssertEqual(reprocesses, 1)
    }

    /// The rail's Reprocess chip and the row's Reprocess are one action on a notice row: chip, then
    /// the row, reprocesses exactly once (the kept dictation clears only after its transcription).
    func testTheChipThenTheNoticeReprocessesOnce() async throws {
        let controller = BottomOverlayWindowController.shared
        let savedReprocess = NotchContentState.shared.onReprocessLastRequested
        var reprocesses = 0
        NotchContentState.shared.onReprocessLastRequested = { reprocesses += 1 }
        defer { NotchContentState.shared.onReprocessLastRequested = savedReprocess }
        controller.prepare()
        await Task.yield()
        XCTAssertTrue(controller.presentNotice(.recognitionBack, frozenDuration: 41, pointerInside: false))
        controller.reprocessFromNotice() // the chip, on a notice row
        controller.reprocessFromNotice() // then the row's own Reprocess, before the cut lands
        try await Task.sleep(nanoseconds: 100_000_000)
        controller.reprocessFromNotice() // and after it
        XCTAssertEqual(reprocesses, 1)
        XCTAssertFalse(NotchContentState.shared.isBottomOverlayPresented)
    }

    /// A pointer already resting on the pill when the notice appears pauses its timer.
    func testAPointerRestingOnThePillPausesTheNotice() async throws {
        let controller = BottomOverlayWindowController.shared
        let savedDuration = BottomOverlayWindowController.noticeDuration
        BottomOverlayWindowController.noticeDuration = 0.2
        defer { BottomOverlayWindowController.noticeDuration = savedDuration }
        controller.prepare()
        await Task.yield()
        XCTAssertTrue(controller.presentNotice(.recognitionBack, frozenDuration: 41, pointerInside: true))
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(NotchContentState.shared.isBottomOverlayPresented, "paused from the start")
        controller.noticeHoverChanged(false)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(NotchContentState.shared.isBottomOverlayPresented, "4 s more once the pointer leaves")
        _ = await controller.hideAndWait()
    }

    /// The recognition-back card (the fallback) never takes a held pill's place.
    func testTheRecognitionBackFallbackCardNeverTakesAHeldPill() async {
        let controller = BottomOverlayWindowController.shared
        controller.prepare()
        await Task.yield()
        controller.show(audioPublisher: Just(CGFloat.zero).eraseToAnyPublisher(), mode: .dictation)
        controller.markRecordingStopped()
        XCTAssertFalse(controller.presentNotice(.recognitionBack, frozenDuration: 41), "a held pill is not free")
        DeliveryFailureOverlayController.shared.showTranscriptionTimeout(.recovered)
        XCTAssertEqual(DeliveryFailureOverlayController.shared.presentedTimeout, .recovered)
        XCTAssertTrue(NotchContentState.shared.isBottomOverlayPresented, "the held pill stays")
        XCTAssertEqual(SignalOverlayModel.shared.phase, .stopped)
        DeliveryFailureOverlayController.shared.hide()
        _ = await controller.hideAndWait()
    }

    /// The notice leaves on its own after its time, paused while the pointer is over the pill.
    func testTheNoticeRowTimesOutUnlessHovered() async throws {
        let controller = BottomOverlayWindowController.shared
        let savedDuration = BottomOverlayWindowController.noticeDuration
        BottomOverlayWindowController.noticeDuration = 0.2
        defer { BottomOverlayWindowController.noticeDuration = savedDuration }
        controller.prepare()
        await Task.yield()
        XCTAssertTrue(controller.presentNotice(.recognitionBack, frozenDuration: 41, pointerInside: false))
        controller.noticeHoverChanged(true)
        try await Task.sleep(nanoseconds: 400_000_000)
        XCTAssertTrue(NotchContentState.shared.isBottomOverlayPresented, "paused under the pointer")
        _ = await controller.hideAndWait()

        XCTAssertTrue(controller.presentNotice(.recognitionBack, frozenDuration: 41, pointerInside: false))
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertFalse(NotchContentState.shared.isBottomOverlayPresented, "left after its time")
    }

    /// A recording owns the pill: the notice falls back to the card rather than take it over.
    func testANoticeNeverTakesOverALiveRecording() async {
        let controller = BottomOverlayWindowController.shared
        controller.prepare()
        await Task.yield()
        controller.show(audioPublisher: Just(CGFloat.zero).eraseToAnyPublisher(), mode: .dictation)
        XCTAssertFalse(controller.presentNotice(.recognitionBack, frozenDuration: 41))
        XCTAssertEqual(SignalOverlayModel.shared.phase, .listening)
        DeliveryFailureOverlayController.shared.showTranscriptionTimeout(.recovered)
        XCTAssertEqual(DeliveryFailureOverlayController.shared.presentedTimeout, .recovered, "the card, as before")
        DeliveryFailureOverlayController.shared.hide()
        _ = await controller.hideAndWait()
    }

    func testBracketsMarkOnlyWhatYouCanClick() {
        // The pill at rest is not clickable as a whole: no bracket, hovered or not.
        XCTAssertFalse(BottomOverlayView.showsPillBracket(isClickable: false, isHovered: true))
        // While SEND shows a click cancels the Return: the hovered pill takes its bracket.
        XCTAssertTrue(BottomOverlayView.showsPillBracket(isClickable: true, isHovered: true))
        XCTAssertFalse(BottomOverlayView.showsPillBracket(isClickable: true, isHovered: false))
    }

    /// Feeds `level` at 94 Hz from `start` for `seconds`, with a frame at each tick like the clock.
    private func feed(_ trace: SignalTraceModel, _ level: CGFloat, from start: TimeInterval, seconds: Double) -> TimeInterval {
        var t = start
        while t < start + seconds {
            trace.ingest(level: level, at: t)
            t += 0.0107
        }
        return t
    }

    func testSilenceHoldsTheTraceStillAndSpeechAdvancesIt() {
        let trace = SignalTraceModel(barCount: 39, noiseThreshold: 0.4)
        trace.begin(at: 100)
        // A second of room tone (the ASR gates it to 0): nothing advances, nothing slides.
        var t = self.feed(trace, 0, from: 100, seconds: 1)
        trace.advance(to: t)
        XCTAssertEqual(trace.pushes, 0, "silence adds no bars")
        XCTAssertEqual(trace.scrollFraction, 0)
        XCTAssertTrue(trace.current.allSatisfy { $0 == 2 })

        // A second of speech: twelve bars, and the bars slide between pushes.
        t = self.feed(trace, 0.6, from: t, seconds: 1)
        XCTAssertEqual(trace.pushes, 12, accuracy: 1)
        XCTAssertGreaterThan(trace.current.suffix(10).filter { $0 > 2 }.count, 5)
        XCTAssertNotEqual(SignalMenuBarMark.listeningBars(from: trace, at: t), [4, 6, 4], "the menu bar mark moves with speech")
        trace.advance(to: t + 0.04)
        XCTAssertGreaterThan(trace.scrollFraction, 0, "mid-sample the bars sit part way through the pitch")

        // Silence again: the 250 ms hangover carries about three more bars, then it holds still.
        let spoken = trace.pushes
        t = self.feed(trace, 0, from: t, seconds: 2)
        XCTAssertEqual(trace.pushes - spoken, 3, accuracy: 1, "the hangover, no more")
        let held = (trace.pushes, trace.scrollFraction, trace.current)
        XCTAssertEqual(SignalMenuBarMark.listeningBars(from: trace, at: t), [4, 6, 4], "the menu bar mark rests in silence")
        t = self.feed(trace, 0, from: t, seconds: 1)
        XCTAssertEqual(trace.pushes, held.0, "silence holds the trace still")
        XCTAssertEqual(trace.scrollFraction, held.1)
        XCTAssertEqual(trace.current, held.2, "the last words stay on screen")

        // A new word: the newest bar grows from the floor, easing toward its height over ~135 ms,
        // unsnapped.
        let before = trace.pushes
        var u = t
        while trace.pushes == before {
            trace.ingest(level: 0.95, at: u)
            u += 0.0107
        }
        let pushedAt = trace.lastPush
        let pushesAtWord = trace.pushes
        let target = trace.current[38]
        XCTAssertGreaterThan(target, 10)
        // The hangover may push more bars meanwhile: follow this one as it moves left.
        func slot() -> Int { 38 - (trace.pushes - pushesAtWord) }
        trace.advance(to: pushedAt + 0.03)
        let early = trace.shownHeight(at: slot(), now: pushedAt + 0.03)
        XCTAssertGreaterThan(early, 2)
        XCTAssertLessThan(early, target - 1, "still easing at 30 ms")
        trace.advance(to: pushedAt + 0.16)
        XCTAssertEqual(trace.shownHeight(at: slot(), now: pushedAt + 0.16), target, accuracy: 1.5, "settled by ~150 ms")
        XCTAssertNotEqual(target.truncatingRemainder(dividingBy: 2), 0, "no 2 pt snapping")

        // Stop: every bar to the floor within 60 ms, and nothing moves after.
        trace.stop(at: pushedAt + 0.2)
        XCTAssertEqual(trace.shownHeight(at: 38, now: pushedAt + 0.27), 2)
        let pushed = trace.pushes
        trace.advance(to: pushedAt + 5)
        XCTAssertEqual(trace.pushes, pushed)
    }

    func testTheMediumPillIsTheDesignedGeometry() {
        let medium = SignalOverlayGeometry.forSize(.medium)
        XCTAssertEqual(medium.pillWidth, 340)
        // Round 6 (Atin, 2026-10-01): 10 · preview 48 · 6 · trace row 38 · 4 · foot 16 · 8.
        XCTAssertEqual(medium.pillHeight, 130)
        XCTAssertEqual(medium.railHeight, 130)
        XCTAssertEqual(medium.innerWidth, 316)
        // The trace takes the icon's and the placard's room: trace + >=12 + readout = 316.
        XCTAssertEqual(medium.traceBars, 63, "round 6: 63 bars, 5.25 s")
        XCTAssertEqual(SignalTraceModel.width(forBars: 63), 250)
        XCTAssertGreaterThanOrEqual(316 - 250 - medium.readoutWidth, 12)
        XCTAssertLessThan(316 - 250 - medium.readoutWidth, 16, "no room left for another bar")
        // Rails: two chips spaced evenly on the 130 pt rail, 23 pt above and below, 24 between.
        XCTAssertEqual(SignalRail<EmptyView, EmptyView, EmptyView>.gap(height: 130), 23)
        // Every other size keeps the rows and only reserves fewer or more preview lines.
        XCTAssertEqual(SignalOverlayGeometry.forSize(.small).pillHeight, 130 - 32)
        XCTAssertTrue(SignalOverlayGeometry.forSize(.small).isCompactTop)
        XCTAssertFalse(medium.isCompactTop)
        XCTAssertGreaterThanOrEqual(SignalOverlayGeometry.forSize(.pill).railHeight, 90)
    }

    func testTheOutcomeNamesOnlyWhatWasDone() {
        XCTAssertEqual(SignalDelivery(appName: "c11", words: 118, method: .paste, sentReturn: false).headline, "Pasted into c11")
        XCTAssertEqual(SignalDelivery(appName: "TextEdit", words: 3, method: .keystrokes, sentReturn: false).headline, "Typed into TextEdit")
        XCTAssertEqual(SignalDelivery(appName: "Notes", words: 3, method: .accessibility, sentReturn: false).headline, "Inserted into Notes")
        let sent = SignalDelivery(appName: "c11", words: 118, method: .paste, sentReturn: true)
        XCTAssertEqual(sent.headline, "Sent to c11")
        XCTAssertEqual(sent.meta, "118 words · Return")
        XCTAssertEqual(SignalDelivery(appName: nil, words: 1, method: .paste, sentReturn: false).headline, "Pasted")
        XCTAssertEqual(TypingService.deliveryMethod(for: .clipboardToPID), .paste)
        XCTAssertEqual(TypingService.deliveryMethod(for: .characterByCharacter), .keystrokes)
        XCTAssertEqual(TypingService.deliveryMethod(for: .accessibility), .accessibility)
    }

    func testChipsNeverActDuringTheDeliveredHold() {
        let delivered = BottomOverlayView.Display.delivered(SignalDelivery(appName: "c11", words: 2, method: .paste, sentReturn: false))
        for role in [BottomOverlayView.ChipRole.history, .cancel, .historyAction] {
            XCTAssertTrue(BottomOverlayView.isChipInert(role, display: delivered))
            XCTAssertFalse(BottomOverlayView.isChipInert(role, display: .listening))
        }
        // After the stop only History acts: Copy and Reprocess wait for the final pass, and Cancel
        // could no longer stop the paste.
        XCTAssertTrue(BottomOverlayView.isChipInert(.historyAction, display: .stopped))
        XCTAssertTrue(BottomOverlayView.isChipInert(.cancel, display: .stopped))
        XCTAssertTrue(BottomOverlayView.isChipInert(.cancel, display: .transcribing))
        XCTAssertFalse(BottomOverlayView.isChipInert(.history, display: .stopped))
        // While SEND shows, Cancel still has a Return to drop after the stop.
        XCTAssertFalse(BottomOverlayView.isChipInert(.cancel, display: .stopped, cancelHasWork: true))
        XCTAssertFalse(BottomOverlayView.isChipInert(.cancel, display: .transcribing, cancelHasWork: true))
        XCTAssertTrue(BottomOverlayView.isChipInert(.cancel, display: delivered, cancelHasWork: true))
        // Transcribing: they dim instead.
        XCTAssertFalse(BottomOverlayView.isChipEnabled(.historyAction, display: .transcribing, hasHistory: true))
        XCTAssertTrue(BottomOverlayView.isChipEnabled(.historyAction, display: .listening, hasHistory: true))
        XCTAssertFalse(BottomOverlayView.isChipEnabled(.historyAction, display: .listening, hasHistory: false))
    }

    func testSpokenSendPlacardAndSweepSteps() {
        XCTAssertEqual(SignalOverlayModel.placard(indicator: .hidden, sendsInApp: true), SignalPlacard.none)
        XCTAssertEqual(SignalOverlayModel.placard(indicator: .armed, sendsInApp: true), .send)
        XCTAssertEqual(SignalOverlayModel.placard(indicator: .countingDown, sendsInApp: true), .send)
        XCTAssertEqual(SignalOverlayModel.placard(indicator: .armed, sendsInApp: false), .noReturn)
        XCTAssertEqual(SignalOverlayModel.placard(indicator: .canceled, sendsInApp: true), .noSend)
        let drain = SignalDrain(startedAt: Date(timeIntervalSinceReferenceDate: 0), duration: 1.5)
        XCTAssertEqual(drain.remaining(at: Date(timeIntervalSinceReferenceDate: 0.6)), 0.9, accuracy: 0.0001)
        var canceled = drain
        canceled.frozenRemaining = 0.9
        XCTAssertEqual(canceled.remaining(at: Date(timeIntervalSinceReferenceDate: 5)), 0.9)
        XCTAssertFalse(canceled.isRunning)

        let steps = SignalSweepView.steps(traceWidth: 154, reducesMotion: false)
        XCTAssertTrue(steps.allSatisfy { ($0.x - 1).truncatingRemainder(dividingBy: 4) == 0 }, "stepped on the 4 pt pitch")
        XCTAssertEqual(steps.first?.time, 0)
        XCTAssertEqual(SignalSweepView.steps(traceWidth: 154, reducesMotion: true).count, 4, "reduced motion holds four positions")
    }

    func testThePreviewKeepsTheNewestWords() {
        let font = SignalTheme.Typography.preview.nsFont
        let text = (1...80).map { "word\($0)" }.joined(separator: " ")
        let fitted = SignalTextFitting.newestWords(of: text, wasCut: false, font: font, width: 304, lines: 3)
        XCTAssertTrue(fitted.hasPrefix("…"))
        XCTAssertTrue(fitted.hasSuffix("word80"))
        XCTAssertLessThanOrEqual(SignalTextFitting.lineCount(fitted, font: font, width: 304), 3)
        XCTAssertEqual(SignalTextFitting.newestWords(of: "short", wasCut: false, font: font, width: 304, lines: 3), "short")
    }

    /// The hold never starts before the outcome, shows it once the paste is posted, then fades and
    /// parks; the margin still paints nothing once hidden, and ignoresMouseEvents is never set.
    func testTheDeliveredHoldShowsTheOutcomeThenDismisses() async throws {
        let controller = BottomOverlayWindowController.shared
        let model = SignalOverlayModel.shared
        controller.prepare()
        await Task.yield()
        controller.show(audioPublisher: Just(CGFloat.zero).eraseToAnyPublisher(), mode: .dictation)
        controller.markRecordingStopped()
        XCTAssertEqual(model.phase, .stopped)

        controller.awaitDelivery(traceID: 4242, appName: "c11", words: 7, failureReported: false)
        XCTAssertEqual(model.phase, .stopped, "no outcome yet: the hold has not begun")

        // Another dictation's outcome is ignored.
        controller.dictationDeliveryFinished(DictationDeliveryOutcome(traceID: 1, result: .dispatched, method: .paste, sentReturn: false))
        XCTAssertEqual(model.phase, .stopped)

        controller.dictationDeliveryFinished(DictationDeliveryOutcome(traceID: 4242, result: .dispatched, method: .paste, sentReturn: false))
        XCTAssertEqual(model.phase, .delivered(SignalDelivery(appName: "c11", words: 7, method: .paste, sentReturn: false)))
        XCTAssertTrue(NotchContentState.shared.isBottomOverlayPresented)
        XCTAssertEqual(controller.windowStateForTests?.alpha, 1)

        // The hold (1.2 s; 0.2 s here), the 120 ms fade, then hidden: alpha 0, nothing painted,
        // never ignoresMouseEvents.
        try await Task.sleep(nanoseconds: 600_000_000)
        XCTAssertFalse(NotchContentState.shared.isBottomOverlayPresented)
        let hidden = try XCTUnwrap(controller.windowStateForTests)
        XCTAssertEqual(hidden.alpha, 0)
        XCTAssertFalse(hidden.ignoresMouse)
        XCTAssertFalse(controller.contentPaintsPixelsForTests())
        XCTAssertEqual(model.phase, .idle)
    }

    /// The live history card sizes to its rows through the panel's fitting size, and scrolls past
    /// 480 pt, so the panel sits 6 pt above the History chip however many entries there are.
    func testTheHistoryCardSizesToItsRows() {
        func height(_ count: Int) -> CGFloat {
            let card = SignalHistoryCard(
                entries: Array(SignalRenderStage.sampleHistory.prefix(count)),
                totalCount: count,
                notPasted: [],
                onPick: { _ in }
            )
            return NSHostingView(rootView: card.signalPalette()).fittingSize.height
        }
        let two = height(2)
        XCTAssertGreaterThan(two, 36 + 28 + 28 + 2 * 60, "header, footer, a day row and two rows")
        XCTAssertLessThan(two, 300)
        XCTAssertEqual(height(12), 480, accuracy: 1, "capped at 480; the list scrolls")
    }

    /// The history card centres on the overlay (DESIGN.md §4, Atin 2026-10-01), 6 pt above its
    /// visible top, not on the History chip's leading edge; the screen's visible frame clamps it.
    func testTheHistoryCardCentresOnTheOverlay() {
        let insets = SignalTheme.Metrics.windowInsets
        let panel = CGSize(width: 480 + insets.leading + insets.trailing, height: 300 + insets.top + insets.bottom)
        let overlay = CGRect(x: 700, y: 80, width: 412, height: 149)
        let screen = CGRect(x: 0, y: 0, width: 1800, height: 1100)
        let frame = BottomOverlayHistoryMenuController.cardFrame(panelSize: panel, overlayFrame: overlay, gap: 6, insets: insets, visibleFrame: screen)
        XCTAssertEqual(frame.midX, overlay.midX, accuracy: 0.5, "centred on the overlay")
        XCTAssertEqual(frame.minY + insets.bottom, overlay.maxY + 6, "the card's box 6 pt above the overlay's top")
        XCTAssertEqual(frame.size, panel)

        // A recovery card grows the pill upward: the card clears it.
        let grown = CGRect(x: 700, y: 80, width: 412, height: 231)
        let overGrown = BottomOverlayHistoryMenuController.cardFrame(panelSize: panel, overlayFrame: grown, gap: 6, insets: insets, visibleFrame: screen)
        XCTAssertEqual(overGrown.minY + insets.bottom, grown.maxY + 6)

        // An overlay dragged to the screen's left edge: the card stays 8 pt inside.
        let atEdge = CGRect(x: 0, y: 80, width: 412, height: 149)
        let clamped = BottomOverlayHistoryMenuController.cardFrame(panelSize: panel, overlayFrame: atEdge, gap: 6, insets: insets, visibleFrame: screen)
        XCTAssertEqual(clamped.minX, 8)
        let top = CGRect(x: 700, y: 1000, width: 412, height: 149)
        let clampedTop = BottomOverlayHistoryMenuController.cardFrame(panelSize: panel, overlayFrame: top, gap: 6, insets: insets, visibleFrame: screen)
        XCTAssertEqual(clampedTop.maxY, screen.maxY - 8)

        // The overlay's content rect (top-left origin in its hosting view) maps to the screen.
        let window = NSPanel(contentRect: NSRect(x: 600, y: 72, width: 424, height: 163), styleMask: [.borderless], backing: .buffered, defer: true)
        window.contentView = NSHostingView(rootView: Color.clear)
        let anchor = SignalOverlayAnchor()
        anchor.frameInContent = CGRect(x: 6, y: 6, width: 412, height: 149)
        XCTAssertEqual(anchor.frameInScreen(window: window), CGRect(x: 606, y: 80, width: 412, height: 149))
        XCTAssertEqual(SignalOverlayAnchor().frameInScreen(window: window), .zero, "not laid out yet")
    }

    /// The live word count (round 6, Atin 2026-10-01): the whole live text, not the stored tail;
    /// status words keep the count. The counters (DESIGN.md §16, Atin 2026-10-01) show from 0 while
    /// live, stopped, transcribing or counting down, and freeze at the stop.
    func testTheLiveCountersCountTheWholeTextFromZeroAndHideOnOutcomes() {
        let state = NotchContentState.shared
        let model = SignalOverlayModel.shared
        defer {
            state.updateTranscription("")
            model.reset()
        }
        let long = Array(repeating: "word", count: 400).joined(separator: " ")
        state.updateTranscription(long)
        XCTAssertEqual(state.liveWordCount, 400, "counts past the 800-character stored tail")
        state.updateTranscription("Transcribing")
        XCTAssertEqual(state.liveWordCount, 400, "a status word keeps the count")
        state.updateTranscription("")
        XCTAssertEqual(state.liveWordCount, 0)

        func input(_ display: BottomOverlayView.Display, live: Int, preview: Bool = true) -> SignalCounterInput? {
            BottomOverlayView.counterInput(display: display, model: model, live: live, streamingPreview: preview)
        }
        model.reset()
        let start = Date().addingTimeInterval(-12)
        model.beginRecording(at: start, noiseThreshold: 0.4)
        XCTAssertEqual(input(.listening, live: 0), SignalCounterInput(recording: start, words: 0, clock: .running(start)), "0 from the start")
        XCTAssertEqual(input(.listening, live: 12)?.words, 12)
        XCTAssertNil(input(.listening, live: 12, preview: false), "no live text arrives with the streaming preview off")
        XCTAssertNil(input(.delivered(SignalDelivery(appName: "c11", words: 118, method: .paste, sentReturn: false)), live: 118))
        XCTAssertNil(input(.noticeRow(.recognitionBack), live: 0))

        state.updateTranscription("one two three four five six seven")
        model.stopRecording(at: start.addingTimeInterval(10), preview: "")
        state.updateTranscription("")
        XCTAssertEqual(input(.stopped, live: 0), SignalCounterInput(recording: start, words: 7, clock: .frozen(10)), "frozen at the stop")
        XCTAssertEqual(input(.transcribing, live: 0)?.words, 7)

        model.reset()
        model.beginTranscribing()
        XCTAssertNil(input(.transcribing, live: 0), "a reprocess has no recording behind it")
    }

    /// The word count steps up one word at a time toward the truth (DESIGN.md §16, Atin 2026-10-01).
    func testTheWordCountStepsThroughABurstAndNeverPassesTheTruth() {
        XCTAssertEqual(SignalCounterSmoother.stepInterval(remaining: 1), 0.110, accuracy: 1e-9, "a single word waits 110 ms")
        XCTAssertEqual(SignalCounterSmoother.stepInterval(remaining: 5), 0.090, accuracy: 1e-9, "450 / 5")
        XCTAssertEqual(SignalCounterSmoother.stepInterval(remaining: 40), 0.030, accuracy: 1e-9, "never faster than 30 ms")

        var counter = SignalCounterSmoother()
        XCTAssertEqual(counter.displayedWords, 0)
        XCTAssertEqual(counter.displayedWPM, 0)
        // A burst of 8 words lands at t = 2 s; a 60 Hz frame clock plays it out.
        var t = 2.0
        var firstFull: Double?
        var previous = 0
        while t < 3 {
            counter.advance(to: t, words: 8, elapsed: t, snaps: false)
            XCTAssertLessThanOrEqual(counter.displayedWords, 8, "never past the truth")
            XCTAssertLessThanOrEqual(counter.displayedWords - previous, 1, "one word a step")
            previous = counter.displayedWords
            if counter.displayedWords == 8, firstFull == nil { firstFull = t }
            t += 1.0 / 60
        }
        // The first word lands at once, then each waits its interval (on the 60 Hz frame grid):
        // the burst plays out in well under a second, not in one jump.
        let playedOut = (firstFull ?? 99) - 2
        let intervals = (1...7).map { SignalCounterSmoother.stepInterval(remaining: $0) }.reduce(0, +)
        XCTAssertGreaterThanOrEqual(playedOut, intervals - 1e-9)
        XCTAssertLessThanOrEqual(playedOut, intervals + 7.0 / 60)

        // A large burst steps at the 30 ms floor, so 40 words take about 1.5 s, never a jump.
        var big = SignalCounterSmoother()
        big.advance(to: 0, words: 40, elapsed: 8, snaps: false)
        XCTAssertEqual(big.displayedWords, 1)
        big.advance(to: 0.45, words: 40, elapsed: 8, snaps: false)
        XCTAssertEqual(big.displayedWords, 2, "one step per frame at most")

        // A revised partial lowers the true count: the shown count drops at once.
        counter.advance(to: t, words: 5, elapsed: t, snaps: false)
        XCTAssertEqual(counter.displayedWords, 5)

        // Snap (Reduce Motion) shows the truth at once.
        counter.advance(to: t + 0.016, words: 30, elapsed: t, snaps: true)
        XCTAssertEqual(counter.displayedWords, 30)
    }

    /// WPM: words x 60 / max(6, elapsed), eased with a 0.7 s time constant (DESIGN.md §16).
    func testWordsPerMinuteFloorsAtSixSecondsAndEases() {
        XCTAssertEqual(SignalCounterSmoother.wpmTarget(words: 10, elapsed: 2), 100, "the first 6 s count as 6")
        XCTAssertEqual(SignalCounterSmoother.wpmTarget(words: 10, elapsed: 6), 100)
        XCTAssertEqual(SignalCounterSmoother.wpmTarget(words: 60, elapsed: 30), 120)
        XCTAssertEqual(SignalCounterSmoother(words: 0, elapsed: 0).displayedWPM, 0, "a start shows 0")
        XCTAssertEqual(SignalCounterSmoother(words: 60, elapsed: 30).displayedWPM, 120, "joining a recording starts at the truth")

        var counter = SignalCounterSmoother()
        counter.advance(to: 10, words: 60, elapsed: 30, snaps: false)
        // One time constant (0.7 s, in 0.1 s frames) covers 1 - 1/e of the way to 120.
        var t = 10.0
        for _ in 0..<7 {
            t += 0.1
            counter.advance(to: t, words: 60, elapsed: 30, snaps: false)
        }
        let eased = 120 * (1 - exp(-(0.7 + 0.016) / 0.7))
        XCTAssertEqual(counter.shownWPM, eased, accuracy: 0.01)
        // A frame gap longer than 0.1 s eases as 0.1 s: no jump after a stall.
        let before = counter.shownWPM
        counter.advance(to: t + 5, words: 60, elapsed: 30, snaps: false)
        XCTAssertEqual(counter.shownWPM, before + (120 - before) * (1 - exp(-0.1 / 0.7)), accuracy: 1e-9)
        // Through silence the target falls as elapsed grows, and the shown WPM drifts down.
        var silent = SignalCounterSmoother(words: 60, elapsed: 30)
        var s = 0.0
        for _ in 0..<120 {
            s += 1.0 / 60
            silent.advance(to: s, words: 60, elapsed: 30 + s, snaps: false)
        }
        XCTAssertLessThan(silent.displayedWPM, 120)
        XCTAssertGreaterThan(silent.displayedWPM, Int(SignalCounterSmoother.wpmTarget(words: 60, elapsed: 32)) - 1)
    }

    /// Fixed boxes (DESIGN.md §16, Atin 2026-10-01): words 4 digits, WPM 3, right-aligned, unused
    /// leading places blank, clamped at 9999 and 999, so the labels never move.
    func testCountersSitInFixedBoxesWithBlankLeadingPlacesAndClamp() {
        XCTAssertEqual(SignalCounterSmoother.padded(0, places: 4), "   0")
        XCTAssertEqual(SignalCounterSmoother.padded(7, places: 4), "   7")
        XCTAssertEqual(SignalCounterSmoother.padded(53, places: 4), "  53")
        XCTAssertEqual(SignalCounterSmoother.padded(169, places: 3), "169")
        XCTAssertEqual(SignalCounterSmoother.padded(12_345, places: 4), "9999")
        XCTAssertEqual(SignalCounterSmoother.padded(1_200, places: 3), "999")

        var counter = SignalCounterSmoother(words: 12_000, elapsed: 60)
        XCTAssertEqual(counter.displayedWords, 9999)
        XCTAssertEqual(counter.displayedWPM, 999)
        counter.advance(to: 1, words: 12_000, elapsed: 60, snaps: true)
        XCTAssertEqual(counter.displayedWords, 9999)

        // A blank place is as wide as a digit in the counters' face: the label never moves.
        let role = SignalTheme.Typography.micLabel
        let widths = [0, 7, 53, 418, 9999].map { role.width(of: SignalCounterSmoother.padded($0, places: 4)) }
        XCTAssertEqual(Set(widths).count, 1, "\(widths)")
        let wpmWidths = [0, 9, 88, 169].map { role.width(of: SignalCounterSmoother.padded($0, places: 3) + " WPM") }
        XCTAssertEqual(Set(wpmWidths).count, 1, "\(wpmWidths)")
        XCTAssertLessThanOrEqual(wpmWidths[0], SignalTheme.Metrics.placardWidth, "WPM fits the placard's 7-character slot")
    }

    /// HISTORY_OPEN times the click on the History chip to its action, and the action to the card.
    func testHistoryOpenSummaryLine() {
        XCTAssertEqual(
            BottomOverlayHistoryMenuController.openSummary(clickToActionMs: 4, actionToShownMs: 9, actionToVisibleMs: 12, trigger: .leftMouseUp),
            "HISTORY_OPEN click_to_action_ms=4 action_to_shown_ms=9 action_to_visible_ms=12 trigger=mouseUp"
        )
        XCTAssertEqual(
            BottomOverlayHistoryMenuController.openSummary(clickToActionMs: nil, actionToShownMs: 9, actionToVisibleMs: 12, trigger: nil),
            "HISTORY_OPEN click_to_action_ms=- action_to_shown_ms=9 action_to_visible_ms=12 trigger=none"
        )
        XCTAssertNil(BottomOverlayHistoryMenuController.clickToActionMs(trigger: nil, actionAt: 10))
        let keyDown = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 9.5, windowNumber: 0, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)
        XCTAssertNil(BottomOverlayHistoryMenuController.clickToActionMs(trigger: keyDown, actionAt: 10), "only a mouse click is timed")
        let mouseUp = NSEvent.mouseEvent(with: .leftMouseUp, location: .zero, modifierFlags: [], timestamp: 9.65, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 0)
        XCTAssertEqual(BottomOverlayHistoryMenuController.clickToActionMs(trigger: mouseUp, actionAt: 10), 350)
    }

    /// Double-click resets the overlay's position in AppKit, away from its buttons, so no SwiftUI
    /// double-tap holds back a chip's single click (the ~350 ms History lag, 2026-10-01).
    func testADoubleClickResetsThePositionOnlyAwayFromButtons() throws {
        // Listening with a history, so all four chips are live: a dimmed or inert chip acts on
        // nothing and is not a target.
        let savedHistory = TranscriptionHistoryStore.shared.makeBackupPayload()
        TranscriptionHistoryStore.shared.restore(from: SignalRenderStage.sampleHistory)
        SignalRenderStage.listening()
        defer { TranscriptionHistoryStore.shared.restore(from: savedHistory) }
        let targets = SignalClickTargets()
        let host = NSHostingView(rootView: BottomOverlayView(clickTargets: targets))
        host.frame = CGRect(origin: .zero, size: host.fittingSize)
        host.layoutSubtreeIfNeeded()
        let chip = SignalTheme.Metrics.chip
        XCTAssertEqual(targets.rects.filter { $0.width == chip && $0.height == chip }.count, 4, "the four chips report themselves")

        let insets = SignalTheme.Metrics.windowInsets
        let geometry = SignalOverlayGeometry.forSize(SettingsStore.shared.overlaySize)
        let pillCentre = CGPoint(x: insets.leading + chip + SignalTheme.Metrics.railGap + geometry.pillWidth / 2, y: insets.top + geometry.railHeight - geometry.pillHeight / 2)
        let leftRail = targets.rects.filter { $0.width == chip && $0.minX == insets.leading }
        XCTAssertEqual(leftRail.count, 2, "History and Copy")
        let historyFrame = try XCTUnwrap(leftRail.min { $0.minY < $1.minY })
        XCTAssertEqual(historyFrame.minY, insets.top + geometry.railHeight - geometry.pillHeight + SignalRail<EmptyView, EmptyView, EmptyView>.gap(height: geometry.railHeight), "spaced evenly down the rail (round 6)")
        let historyChip = CGPoint(x: historyFrame.midX, y: historyFrame.midY)
        XCTAssertTrue(SignalClickTargets.isPositionResetClick(clickCount: 2, at: pillCentre, targets: targets.rects))
        XCTAssertFalse(SignalClickTargets.isPositionResetClick(clickCount: 1, at: pillCentre, targets: targets.rects), "a single click never resets")
        XCTAssertFalse(SignalClickTargets.isPositionResetClick(clickCount: 2, at: historyChip, targets: targets.rects), "a double-click on a chip is the chip's")
        XCTAssertFalse(SignalClickTargets.isPositionResetClick(clickCount: 3, at: pillCentre, targets: targets.rects))

        // Idle (the delivered hold, a hidden overlay): every chip is inert, so none is a target.
        SignalRenderStage.reset()
        host.layoutSubtreeIfNeeded()
        XCTAssertTrue(targets.rects.isEmpty, "inert chips act on nothing")
    }

    /// A card for another dictation never takes over a held outcome, and a failure that is not a
    /// dictation's (a history paste) never does either.
    func testALateCardForAnotherDictationDoesNotTakeOverTheHold() async {
        let controller = BottomOverlayWindowController.shared
        controller.prepare()
        await Task.yield()
        controller.show(audioPublisher: Just(CGFloat.zero).eraseToAnyPublisher(), mode: .dictation)
        controller.markRecordingStopped()
        controller.awaitDelivery(traceID: 9, appName: "c11", words: 2, failureReported: false)
        XCTAssertNil(controller.heldDictationAppName(forDictation: 8), "another dictation never borrows the name")
        XCTAssertFalse(controller.yieldToCard(forDictation: 8))
        XCTAssertFalse(controller.yieldToCard(forDictation: nil))
        XCTAssertTrue(NotchContentState.shared.isBottomOverlayPresented)
        _ = await controller.hideAndWait()
    }

    /// A late Paste Check miss for the dictation whose Pasted is on screen replaces it with its
    /// card, instead of showing Pasted and Couldn't paste at once.
    func testALatePasteCheckMissReplacesThatDictationsPasted() async throws {
        let controller = BottomOverlayWindowController.shared
        controller.prepare()
        await Task.yield()
        controller.show(audioPublisher: Just(CGFloat.zero).eraseToAnyPublisher(), mode: .dictation)
        controller.markRecordingStopped()
        controller.awaitDelivery(traceID: 31, appName: "TextEdit", words: 4, failureReported: false)
        controller.dictationDeliveryFinished(DictationDeliveryOutcome(traceID: 31, result: .dispatched, method: .paste, sentReturn: false))
        XCTAssertTrue(SignalOverlayModel.shared.isDelivered)
        XCTAssertEqual(controller.heldDictationAppName(forDictation: 31), "TextEdit")
        XCTAssertTrue(controller.yieldToCard(forDictation: 31))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(NotchContentState.shared.isBottomOverlayPresented, "a cut: the card takes the pill's place")
    }

    /// The transcription timed out while the pill was held after the stop: the timeout card takes
    /// its place (a cut) instead of sitting above a frozen pill.
    func testATimeoutCardReplacesTheHeldPill() async throws {
        let controller = BottomOverlayWindowController.shared
        controller.prepare()
        await Task.yield()
        controller.show(audioPublisher: Just(CGFloat.zero).eraseToAnyPublisher(), mode: .dictation)
        XCTAssertFalse(controller.yieldToNoticeCard(), "a live recording stays")
        controller.markRecordingStopped()
        DeliveryFailureOverlayController.shared.showTranscriptionTimeout(.timedOut)
        defer { DeliveryFailureOverlayController.shared.hide() }
        XCTAssertEqual(DeliveryFailureOverlayController.shared.presentedTimeout, .timedOut)
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(NotchContentState.shared.isBottomOverlayPresented)
        XCTAssertEqual(controller.windowStateForTests?.alpha, 0)
        XCTAssertEqual(TestHostQuietModeTests.onScreenWindowCount(), 0)
    }

    /// A start refused while the model recovers: the pill shown for it gives way to the card; a
    /// "recognition is back" notice never hides a pill that is not held after a stop.
    func testARefusedStartCardReplacesItsPillButOtherNoticesDoNot() async throws {
        let controller = BottomOverlayWindowController.shared
        controller.prepare()
        await Task.yield()
        controller.show(audioPublisher: Just(CGFloat.zero).eraseToAnyPublisher(), mode: .dictation)
        XCTAssertFalse(controller.yieldToNoticeCard(refusedStart: false))
        XCTAssertTrue(NotchContentState.shared.isBottomOverlayPresented)
        XCTAssertTrue(controller.yieldToNoticeCard(refusedStart: true), "no capture ever started")
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(NotchContentState.shared.isBottomOverlayPresented)
    }

    /// Once the stop decides, the held pill's placard follows the decision: SEND only when the
    /// Return will follow, NO SEND in ink for a cancel, dim when no Return goes there.
    func testThePlacardFollowsTheSendDecision() async {
        let controller = BottomOverlayWindowController.shared
        let model = SignalOverlayModel.shared
        controller.prepare()
        await Task.yield()
        controller.show(audioPublisher: Just(CGFloat.zero).eraseToAnyPublisher(), mode: .dictation)
        controller.markRecordingStopped()
        model.setStopPlacard(.send)
        controller.spokenSendDecided(.canceled)
        XCTAssertEqual(model.stopPlacard, .noSend, "a cancel reads NO SEND in ink")
        controller.spokenSendDecided(.returnFollows)
        XCTAssertEqual(model.stopPlacard, .send)
        controller.spokenSendDecided(.noReturn)
        XCTAssertEqual(model.stopPlacard, .noReturn, "a terminal without Return stays dim")
        controller.spokenSendDecided(.noPhrase)
        XCTAssertEqual(model.stopPlacard, SignalPlacard.none)
        _ = await controller.hideAndWait()
    }

    /// A new recording during the hold or the fade cancels the old timers: nothing from the
    /// previous dictation hides the new pill.
    func testShowDuringTheHoldOrFadeCancelsTheOldTimers() async throws {
        let controller = BottomOverlayWindowController.shared
        let publisher = Just(CGFloat.zero).eraseToAnyPublisher()
        controller.prepare()
        await Task.yield()
        // During the hold.
        controller.show(audioPublisher: publisher, mode: .dictation)
        controller.markRecordingStopped()
        controller.awaitDelivery(traceID: 51, appName: "c11", words: 1, failureReported: false)
        controller.dictationDeliveryFinished(DictationDeliveryOutcome(traceID: 51, result: .dispatched, method: .paste, sentReturn: false))
        controller.show(audioPublisher: publisher, mode: .dictation)
        try await Task.sleep(nanoseconds: 500_000_000)
        XCTAssertTrue(NotchContentState.shared.isBottomOverlayPresented, "the old hold's end must not hide the new pill")
        XCTAssertEqual(SignalOverlayModel.shared.phase, .listening)
        // During the fade.
        controller.markRecordingStopped()
        let fade = Task { @MainActor in await controller.hideAndWait() }
        await Task.yield()
        controller.show(audioPublisher: publisher, mode: .dictation)
        let outcome = await fade.value
        XCTAssertEqual(outcome, .superseded)
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(NotchContentState.shared.isBottomOverlayPresented)
        XCTAssertFalse(SignalOverlayModel.shared.isFading)
        XCTAssertEqual(controller.windowStateForTests?.alpha, 1)
        _ = await controller.hideAndWait()
    }

    /// A failed paste hands the overlay to the recovery card at once (a cut), so the card reads as
    /// the pill growing; a live recording is never taken over.
    func testAFailedPasteYieldsToTheCardButALiveRecordingDoesNot() async throws {
        let controller = BottomOverlayWindowController.shared
        controller.prepare()
        await Task.yield()
        controller.show(audioPublisher: Just(CGFloat.zero).eraseToAnyPublisher(), mode: .dictation)
        XCTAssertFalse(controller.yieldToCard(forDictation: 77), "a live recording stays; the card sits above it")
        XCTAssertTrue(NotchContentState.shared.isBottomOverlayPresented)

        controller.markRecordingStopped()
        controller.awaitDelivery(traceID: 77, appName: "c11", words: 3, failureReported: false)
        controller.dictationDeliveryFinished(DictationDeliveryOutcome(traceID: 77, result: .recoverableFailure(.pasteNotLanded), method: nil, sentReturn: false))
        XCTAssertEqual(SignalOverlayModel.shared.phase, .stopped, "waits for the card, never shows an outcome")
        XCTAssertEqual(controller.heldDictationAppName(forDictation: 77), "c11")
        XCTAssertTrue(controller.yieldToCard(forDictation: 77))
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(NotchContentState.shared.isBottomOverlayPresented, "a cut, no 120 ms fade")
        XCTAssertEqual(controller.windowStateForTests?.alpha, 0)
    }
}

/// Opt-in: where the offscreen park lands relative to a start about 1.5 s after a paste, and how
/// long the start and the main thread take around it. TEST_RUNNER_LIQUID_VOICE_PARK_BENCH=<delay>
/// sets the idle parking delay in seconds (0 reproduces the old park right after the handoff).
/// The test host's panel is never on screen (quiet mode), so the WindowServer fence itself cannot
/// occur here; the probe measures the timing and the main-thread cost that can be measured.
@MainActor
final class OverlayParkTimingBenchmarkTests: XCTestCase {
    func testWhereTheParkLandsAroundTheNextStart() async throws {
        guard let value = ProcessInfo.processInfo.environment["LIQUID_VOICE_PARK_BENCH"], let delay = Double(value) else {
            throw XCTSkip("Set TEST_RUNNER_LIQUID_VOICE_PARK_BENCH=<idle parking delay> to run.")
        }
        let controller = BottomOverlayWindowController.shared
        let publisher = Just(CGFloat.zero).eraseToAnyPublisher()
        let savedDelay = BottomOverlayWindowController.idleParkingDelay
        BottomOverlayWindowController.idleParkingDelay = delay
        defer { BottomOverlayWindowController.idleParkingDelay = savedDelay }
        controller.prepare()
        await Task.yield()

        var showMs: [Double] = []
        var stallMs: [Double] = []
        var parkedBeforeStart = 0
        for run in 0..<5 {
            controller.show(audioPublisher: publisher, mode: .dictation)
            controller.markRecordingStopped()
            controller.awaitDelivery(traceID: 7000 + run, appName: "c11", words: 3, failureReported: false)
            let pastedAt = ProcessInfo.processInfo.systemUptime
            controller.dictationDeliveryFinished(DictationDeliveryOutcome(traceID: 7000 + run, result: .dispatched, method: .paste, sentReturn: false))

            // Watch the main thread from 1.2 s to 1.8 s after the paste: a 1 ms timer's lateness.
            var worstLateness = 0.0
            var last = ProcessInfo.processInfo.systemUptime
            let probe = Timer(timeInterval: 0.001, repeats: true) { _ in
                let now = ProcessInfo.processInfo.systemUptime
                if now - pastedAt > 1.2, now - pastedAt < 1.8 { worstLateness = max(worstLateness, now - last - 0.001) }
                last = now
            }
            RunLoop.main.add(probe, forMode: .common)
            while ProcessInfo.processInfo.systemUptime - pastedAt < 1.5 {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            if controller.windowStateForTests?.isParkedOffscreen == true { parkedBeforeStart += 1 }
            // The hotkey: the overlay's part of the start path.
            let started = ProcessInfo.processInfo.systemUptime
            controller.show(audioPublisher: publisher, mode: .dictation)
            showMs.append((ProcessInfo.processInfo.systemUptime - started) * 1000)
            while ProcessInfo.processInfo.systemUptime - pastedAt < 1.8 {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            probe.invalidate()
            stallMs.append(worstLateness * 1000)
            _ = await controller.hideAndWait()
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        func median(_ values: [Double]) -> Double { values.sorted()[values.count / 2] }
        let line = String(
            format: "PARK_BENCH idleDelay=%.1fs runs=5 parkedBeforeStartAt1.5s=%d showMedianMs=%.2f showMaxMs=%.2f mainStallMedianMs=%.2f mainStallMaxMs=%.2f",
            delay, parkedBeforeStart, median(showMs), showMs.max() ?? 0, median(stallMs), stallMs.max() ?? 0
        )
        print(line)
        DebugLogger.shared.info(line, source: "OverlayParkBenchmark")
    }
}

/// The voice trace keeps moving on every dictation: levels go through the same path a real
/// capture uses (the ASR's level publisher, delivered on main, into the window controller's
/// subscription), across two dictations with the outcome hold and the fade between them.
///
/// The levels are a quiet microphone's: Atin's fifine USB microphone kept every window of a
/// 62 s dictation under about 0.43 (-31 dBFS). With the old fixed gate at 0.4 its trace sat at the
/// 2 pt floor, one 4 pt bar in four seconds of speech, while the frame clock and the feed ran
/// (captured from the installed build, 2026-09-29). The trace now calibrates to the recording.
@MainActor
final class SignalTraceLifecycleTests: XCTestCase {
    /// A quiet microphone's speech, one level per 512-frame buffer (10.7 ms): 150 ms of room tone
    /// the ASR gates to 0, then 300 ms of syllables between 0.28 and 0.42, repeating.
    static func quietSpeech(step: Int) -> CGFloat {
        guard (step / 14) % 3 != 0 else { return 0 }
        var seed = UInt64(truncatingIfNeeded: step &* 2_654_435_761)
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return 0.28 + 0.14 * CGFloat(seed >> 40) / CGFloat(1 << 24)
    }

    private func speak(into subject: PassthroughSubject<CGFloat, Never>, seconds: Double, snapshots: inout [[CGFloat]]) async throws {
        let end = Date().addingTimeInterval(seconds)
        var step = 0
        while Date() < end {
            // Like AudioCapturePipeline.onLevel: hopped to main, one level per 512-frame buffer.
            let level = Self.quietSpeech(step: step)
            DispatchQueue.main.async { subject.send(level) }
            step += 1
            if step % 14 == 0 { snapshots.append(SignalOverlayModel.shared.trace.current) }
            try await Task.sleep(nanoseconds: 10_700_000)
        }
        try await Task.sleep(nanoseconds: 30_000_000)
        snapshots.append(SignalOverlayModel.shared.trace.current)
    }

    private func dictate(_ controller: BottomOverlayWindowController, subject: PassthroughSubject<CGFloat, Never>, trace id: Int) async throws -> (snapshots: [[CGFloat]], stats: SignalTraceModel.Stats, menuBars: [CGFloat]) {
        controller.show(audioPublisher: subject.eraseToAnyPublisher(), mode: .dictation)
        var snapshots: [[CGFloat]] = []
        try await self.speak(into: subject, seconds: 0.6, snapshots: &snapshots)
        let stats = SignalOverlayModel.shared.trace.stats
        let menuBars = SignalMenuBarMark.listeningBars(from: SignalOverlayModel.shared.trace)
        controller.markRecordingStopped()
        controller.awaitDelivery(traceID: id, appName: "c11", words: 3, failureReported: false)
        controller.dictationDeliveryFinished(DictationDeliveryOutcome(traceID: id, result: .dispatched, method: .paste, sentReturn: false))
        return (snapshots, stats, menuBars)
    }

    private func assertMoved(_ run: (snapshots: [[CGFloat]], stats: SignalTraceModel.Stats, menuBars: [CGFloat]), _ label: String) {
        let raisedBars = run.snapshots.map { $0.filter { $0 > 2 }.count }
        XCTAssertGreaterThanOrEqual(raisedBars.max() ?? 0, 2, "\(label): the quiet speech draws above the floor")
        XCTAssertGreaterThan(Set(run.snapshots).count, 2, "\(label): the bars change from moment to moment")
        XCTAssertGreaterThanOrEqual(run.snapshots.flatMap { $0 }.max() ?? 0, 12, "\(label): syllables stretch tall")
        // A third of this speech is room tone: under the old fixed gate this is 0.
        XCTAssertGreaterThan(Double(run.stats.raised) / Double(max(run.stats.windows, 1)), 0.25, "\(label): \(run.stats)")
        XCTAssertEqual(run.menuBars.count, 3)
    }

    func testTheTraceMovesOnTheSecondDictationAfterAHoldAndFade() async throws {
        let controller = BottomOverlayWindowController.shared
        let subject = PassthroughSubject<CGFloat, Never>()
        // A short hold keeps the default suite fast; the hold's length is not under test here.
        let savedHold = BottomOverlayWindowController.deliveredHold
        BottomOverlayWindowController.deliveredHold = 0.05
        defer { BottomOverlayWindowController.deliveredHold = savedHold }
        controller.prepare()
        await Task.yield()

        let first = try await self.dictate(controller, subject: subject, trace: 91)
        self.assertMoved(first, "first dictation")
        // The hold, then the fade.
        try await Task.sleep(nanoseconds: UInt64((BottomOverlayWindowController.deliveredHold + SignalTheme.Motion.dismiss + 0.1) * 1_000_000_000))
        XCTAssertFalse(NotchContentState.shared.isBottomOverlayPresented)

        let second = try await self.dictate(controller, subject: subject, trace: 92)
        self.assertMoved(second, "second dictation")
        _ = await controller.hideAndWait()
    }

    /// Feeds `seconds` of levels, one per 10.7 ms, and returns every bar pushed meanwhile.
    private func pushedHeights(_ trace: SignalTraceModel, seconds: Double, from start: TimeInterval, level: (Int) -> CGFloat) -> [CGFloat] {
        var pushed: [CGFloat] = []
        var lastPush = trace.lastPush
        for step in 0..<Int(seconds / 0.0107) {
            trace.ingest(level: level(step), at: start + Double(step) * 0.0107)
            if trace.lastPush != lastPush {
                lastPush = trace.lastPush
                pushed.append(trace.current.last ?? 0)
            }
        }
        return pushed
    }

    func testTheTraceCalibratesToTheRecordingNotAFixedGate() {
        // A quiet microphone: its speech stretches tall, its gaps stay on the floor.
        let quiet = SignalTraceModel(barCount: 39, noiseThreshold: 0.4)
        quiet.begin(at: 0)
        let quietBars = self.pushedHeights(quiet, seconds: 4, from: 0, level: Self.quietSpeech)
        XCTAssertGreaterThan(quietBars.filter { $0 > 2 }.count, quietBars.count / 2, "\(quietBars)")
        XCTAssertGreaterThanOrEqual(quietBars.max() ?? 0, 16)
        XCTAssertEqual(quiet.quietFloor ?? -1, 0, accuracy: 0.05, "the gaps set the floor")

        // A loud microphone in a noisy room: speech tall, the room (0.3) under the gate.
        let loud = SignalTraceModel(barCount: 39, noiseThreshold: 0.4)
        loud.begin(at: 0)
        let loudBars = self.pushedHeights(loud, seconds: 4, from: 0) { step in
            (step / 14) % 3 == 2 ? 0.3 : 0.62 + 0.3 * Self.quietSpeech(step: step) / 0.42
        }
        XCTAssertGreaterThanOrEqual(loudBars.max() ?? 0, 20)
        XCTAssertGreaterThan(loudBars.filter { $0 > 2 }.count, loudBars.count / 2)

        // A steady background settles under the gate within seconds; then it is silence: the
        // trace holds still.
        let steady = SignalTraceModel(barCount: 39, noiseThreshold: 0.4)
        steady.begin(at: 0)
        _ = self.pushedHeights(steady, seconds: 1, from: 0) { _ in 0.1 }
        _ = self.pushedHeights(steady, seconds: 12, from: 1) { _ in 0.5 }
        let settled = self.pushedHeights(steady, seconds: 2, from: 13) { _ in 0.5 }
        XCTAssertTrue(settled.isEmpty, "a settled background adds no bars: \(settled)")

        // Sensitivity "Less" asks for more above the floor than the default.
        let less = SignalTraceModel(barCount: 39, noiseThreshold: 0.8)
        less.begin(at: 0)
        let lessBars = self.pushedHeights(less, seconds: 4, from: 0, level: Self.quietSpeech)
        XCTAssertLessThan(lessBars.reduce(0, +), quietBars.reduce(0, +))
        XCTAssertGreaterThan(less.gate, quiet.gate)
    }
}

/// The floating shadow (DESIGN.md §6, Atin 2026-09-29): a click-through child panel under each
/// Signal surface that draws only the soft shadow, and nothing at all when the surface is hidden.
@MainActor
final class SignalFloatShadowTests: XCTestCase {
    private var outputFolder: URL? {
        ProcessInfo.processInfo.environment["LIQUID_VOICE_RENDER_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    override func tearDown() {
        SignalRenderStage.reset()
        super.tearDown()
    }

    /// Lets queued main-queue turns run (the shadow's deferred present, withdraw and alpha).
    private func mainTurns() async throws {
        try await Task.sleep(nanoseconds: 60_000_000)
    }

    func testTheShadowPanelIsAClickThroughChildUnderTheOverlayThatFollowsIt() async throws {
        let controller = BottomOverlayWindowController.shared
        let savedParkingDelay = BottomOverlayWindowController.idleParkingDelay
        let savedHold = BottomOverlayWindowController.deliveredHold
        BottomOverlayWindowController.idleParkingDelay = 0.05
        defer {
            BottomOverlayWindowController.idleParkingDelay = savedParkingDelay
            BottomOverlayWindowController.deliveredHold = savedHold
        }
        controller.prepare()
        let floatShadow = controller.floatShadow
        let shadow = floatShadow.panelForTests
        XCTAssertTrue(shadow.ignoresMouseEvents, "the shadow never takes a click")
        XCTAssertFalse(shadow.hasShadow)
        XCTAssertNil(shadow.parent, "a parked, hidden pill has no shadow in the window list")

        let margin = SignalFloatShadow.margin
        let geometry = SignalOverlayGeometry.forSize(SettingsStore.shared.overlaySize)
        let insets = SignalTheme.Metrics.windowInsets
        let pillBox = CGRect(x: insets.leading + SignalTheme.Metrics.chip + SignalTheme.Metrics.railGap, y: insets.top, width: geometry.pillWidth, height: geometry.pillHeight)
        for pass in ["first show", "show after the idle park"] {
            controller.show(audioPublisher: Just(CGFloat.zero).eraseToAnyPublisher(), mode: .dictation)
            // The start path moves and orders the pill alone; the shadow follows on a later turn.
            XCTAssertNil(shadow.parent, "\(pass): the show orders one window")
            XCTAssertFalse(floatShadow.isPresented)
            try await self.mainTurns()
            let overlay = try XCTUnwrap(shadow.parent, "\(pass): the shadow is a child of the overlay")
            XCTAssertTrue(overlay.childWindows?.contains(shadow) == true)
            XCTAssertEqual(shadow.frame, overlay.frame.insetBy(dx: -margin, dy: -margin), "\(pass): under the pill, not where it was parked")
            XCTAssertEqual(shadow.alphaValue, 1)
            XCTAssertEqual(floatShadow.state.surface, pillBox, "\(pass): the pill reports its own box")

            _ = await controller.hideAndWait()
            try await self.mainTurns()
            XCTAssertEqual(overlay.alphaValue, 0)
            XCTAssertEqual(shadow.alphaValue, 0, "\(pass): alpha 0 casts nothing")
            XCTAssertNil(shadow.parent, "\(pass): withdrawn once hidden")
            // Idle past the parking delay: the pill parks offscreen alone.
            try await Task.sleep(nanoseconds: 150_000_000)
            XCTAssertEqual(controller.windowStateForTests?.isParkedOffscreen, true, "\(pass): parked")
            XCTAssertNil(shadow.parent)
        }
    }

    /// Dark floats more (Atin, 2026-10-01): black 0.55, radius 18, y 9; light stays 0.16, 12, 5.
    /// The shadow panel's margin holds the deepest blur.
    func testTheFloatingShadowIsPerAppearanceAndNeverClipped() {
        let dark = SignalTheme.Palette.dark
        let light = SignalTheme.Palette.light
        XCTAssertEqual(dark.floatShadowRadius, 18)
        XCTAssertEqual(dark.floatShadowY, 9)
        XCTAssertEqual(light.floatShadowRadius, 12)
        XCTAssertEqual(light.floatShadowY, 5)
        XCTAssertEqual(SignalFloatShadow.margin, 48)
        for palette in [dark, light] {
            XCTAssertGreaterThanOrEqual(SignalFloatShadow.margin, 2 * palette.floatShadowRadius + palette.floatShadowY)
        }
    }

    func testTheShadowPanelIsNeverClampedOntoAScreen() {
        let panel = SignalFloatShadow.Panel(contentRect: .zero, styleMask: [.borderless], backing: .buffered, defer: true)
        let parked = NSRect(x: 100_000, y: 100_000, width: 488, height: 227)
        XCTAssertEqual(panel.constrainFrameRect(parked, to: NSScreen.screens.first), parked)
    }


    func testARecoveryCardCastsItsOwnShadowFromItsGrownPill() async throws {
        let cards = DeliveryFailureOverlayController.shared
        cards.showTranscriptionTimeout(.timedOut)
        defer { cards.hide() }
        try await Task.sleep(nanoseconds: 100_000_000)
        let shadow = cards.floatShadow.panelForTests
        XCTAssertNotNil(shadow.parent, "attached under the card's panel")
        XCTAssertTrue(shadow.ignoresMouseEvents)
        let surface = try XCTUnwrap(cards.floatShadow.state.surface, "the card reports its grown pill")
        XCTAssertEqual(surface.height, 156, "the one-line card: the pill grown upward to 156")
        XCTAssertEqual(surface.minX, SignalTheme.Metrics.windowInsets.leading + SignalTheme.Metrics.chip + SignalTheme.Metrics.railGap)
    }

    func testTheShadowFollowsItsSurfaceAlphaThroughAFade() async throws {
        let parent = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 200, height: 100), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        let floatShadow = SignalFloatShadow { state in SignalFloatShadowView(state: state) }
        floatShadow.attach(to: parent)
        defer { floatShadow.detach() }
        let margin = SignalFloatShadow.margin
        XCTAssertEqual(floatShadow.panelForTests.frame, NSRect(x: 0, y: 0, width: 200, height: 100).insetBy(dx: -margin, dy: -margin))
        parent.setFrame(NSRect(x: 10, y: 20, width: 300, height: 120), display: false)
        XCTAssertEqual(floatShadow.panelForTests.frame, NSRect(x: 10, y: 20, width: 300, height: 120).insetBy(dx: -margin, dy: -margin), "follows a resize")
        await withCheckedContinuation { continuation in
            NSAnimationContext.runAnimationGroup { context in
                context.duration = SignalTheme.Motion.dismiss
                parent.animator().alphaValue = 0
            } completionHandler: {
                continuation.resume()
            }
        }
        try await self.mainTurns()
        XCTAssertEqual(floatShadow.panelForTests.alphaValue, 0, "a card's fade takes its shadow along")
        parent.alphaValue = 1
        try await self.mainTurns()
        XCTAssertEqual(floatShadow.panelForTests.alphaValue, 1)
        parent.setFrameOrigin(NSPoint(x: 100_000, y: 100_000))
        XCTAssertEqual(floatShadow.panelForTests.frame.origin, NSPoint(x: 100_000 - margin, y: 100_000 - margin), "follows a move, parked included")
    }

    private static func pixels(_ view: some View, size: CGSize) throws -> (cg: CGImage, alphaAt: (Int, Int) -> UInt8) {
        let renderer = ImageRenderer(content: view.frame(width: size.width, height: size.height))
        renderer.scale = 1
        let image = try XCTUnwrap(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: image)
        return (image, { x, y in UInt8(((rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) * 255).rounded()) })
    }

    func testTheShadowPaintsOnlyOutsideTheSurfaceAndNothingWhileHidden() throws {
        let margin = SignalFloatShadow.margin
        let surface = CGRect(x: 42, y: 6, width: 340, height: 130)
        let size = CGSize(width: 424 + 2 * margin, height: 144 + 2 * margin)
        let state = SignalFloatShadow.State()
        state.surface = surface

        SignalRenderStage.listening()
        let shown = try Self.pixels(BottomOverlayShadowView(state: state), size: size)
        // Under the box: nothing (a fading surface never shows a dark box through).
        XCTAssertEqual(shown.alphaAt(Int(margin + surface.midX), Int(margin + surface.midY)), 0)
        // Just below the box: the shadow, deepest there; well clear of it: nothing.
        let below = shown.alphaAt(Int(margin + surface.midX), Int(margin + surface.maxY + 3))
        XCTAssertGreaterThan(below, 20)
        XCTAssertLessThan(below, 110, "subtle")
        XCTAssertEqual(shown.alphaAt(2, 2), 0)

        NotchContentState.shared.setBottomOverlayPresented(false)
        let hidden = try Self.pixels(BottomOverlayShadowView(state: state), size: size)
        let rep = NSBitmapImageRep(cgImage: hidden.cg)
        var painted = 0
        for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 2) where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0 {
                painted += 1
            }
        }
        XCTAssertEqual(painted, 0, "a hidden overlay's shadow paints nothing")
    }

    /// The listening pill and a failed card over their shadow panels, as the window server stacks
    /// them, beside the same surfaces without it (design/visual-language/native-renders/shadow).
    func testFloatingShadowRenders() throws {
        let margin = SignalFloatShadow.margin
        let transcript = "Okay, take a look at the retry admission path in the queue worker. When the same job ID lands twice inside the lease window we are admitting both and the second one clobbers the first one's checkpoint so I think the fix is to key the admission set."
        for appearance in [NSAppearance.Name.darkAqua, .aqua] {
            let theme = appearance == .darkAqua ? "dark" : "light"
            SignalRenderStage.reset()
            SignalRenderStage.listening()
            let pillShadow = SignalFloatShadow.State()
            pillShadow.surface = CGRect(x: 42, y: 6, width: 340, height: 130)
            let card = DeliveryFailureCardView(
                content: SignalCardContent(headline: "Couldn\u{2019}t paste into c11", reason: "No text field focused", transcript: transcript, primary: .copy, meta: "118 words"),
                icon: NSWorkspace.shared.icon(forFile: "/Applications/c11.app"),
                timerText: "0:41",
                microphoneName: "MacBook Pro Microphone",
                onPrimary: {},
                onDismiss: {},
                onHoverChanged: { _ in }
            )
            let cardShadow = SignalFloatShadow.State()
            cardShadow.surface = CGRect(x: 42, y: 6, width: 340, height: 210)
            let surfaces: [(String, AnyView, SignalFloatShadow.State)] = [
                ("01-listening", AnyView(BottomOverlayView()), pillShadow),
                ("07-failed", AnyView(card), cardShadow),
            ]
            for (name, surface, state) in surfaces {
                for withShadow in [false, true] {
                    let composite = surface
                        .padding(margin)
                        .background(alignment: .topLeading) {
                            if withShadow {
                                SignalFloatShadowView(state: state).signalPalette()
                            }
                        }
                    let rep = try SignalRenderStage.render(composite, appearance: appearance)
                    XCTAssertGreaterThan(rep.size.width, 424 + 2 * margin)
                    if let folder = self.outputFolder {
                        let file = "\(theme)-\(name)-\(withShadow ? "shadow" : "flat").png"
                        try SignalRenderStage.write(rep, to: folder.appendingPathComponent("shadow").appendingPathComponent(file))
                    }
                }
            }
        }
    }
}

/// START_SUMMARY: one line per capture start, from the start hotkey, whichever start path the
/// hotkey takes. The installed build logged none: the marks sat in `ContentView.startRecording()`,
/// which the hotkey's dictation path (`beginDictationRecording`) never calls. They now sit in the
/// hotkey's start action and in `ASRService.start` (entry and first PCM).
@MainActor
final class StartPathTraceTests: XCTestCase {
    private var lines: [String] = []
    private var savedEmit: ((String) -> Void)?

    override func setUp() async throws {
        try await super.setUp()
        self.savedEmit = StartPathTrace.emit
        StartPathTrace.emit = { [unowned self] line in self.lines.append(line) }
    }

    override func tearDown() async throws {
        if let savedEmit { StartPathTrace.emit = savedEmit }
        _ = await BottomOverlayWindowController.shared.hideAndWait()
        try await super.tearDown()
    }

    /// What `ASRService.start` does around a capture start: its entry mark, then the first PCM.
    private static func emulatedCaptureStart() -> HotkeyCaptureStartTask {
        Task { @MainActor in
            StartPathTrace.captureRequested()
            try? await Task.sleep(nanoseconds: 20_000_000)
            StartPathTrace.captureStarted()
        }
    }

    func testAHotkeyStartEmitsExactlyOneStartSummary() async throws {
        let asr = ASRService()
        let start: () async -> HotkeyCaptureStartTask? = {
            // As ContentView.beginDictationRecording: the pill first, then the capture start.
            BottomOverlayWindowController.shared.show(audioPublisher: Just(CGFloat.zero).eraseToAnyPublisher(), mode: .dictation)
            return Self.emulatedCaptureStart()
        }
        let manager = GlobalHotkeyManager(
            asrService: asr,
            primaryShortcuts: [HotkeyShortcut(keyCode: 96, modifierFlags: [])],
            promptModeShortcut: HotkeyShortcut(keyCode: 97, modifierFlags: []),
            commandModeShortcut: nil,
            rewriteModeShortcut: HotkeyShortcut(keyCode: 98, modifierFlags: []),
            promptModeShortcutEnabled: false,
            commandModeShortcutEnabled: false,
            rewriteModeShortcutEnabled: false,
            startRecordingCallback: start,
            dictationModeCallback: start
        )
        BottomOverlayWindowController.shared.prepare()
        let down = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 96, keyDown: true))
        down.flags = []
        _ = manager.handleKeyEventForTests(down, type: CGEventType.keyDown)
        for _ in 0..<50 where self.lines.isEmpty {
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        let up = try XCTUnwrap(CGEvent(keyboardEventSource: nil, virtualKey: 96, keyDown: false))
        up.flags = []
        _ = manager.handleKeyEventForTests(up, type: CGEventType.keyUp)

        XCTAssertEqual(self.lines.count, 1, "\(self.lines)")
        let line = try XCTUnwrap(self.lines.first)
        XCTAssertTrue(line.hasPrefix("START_SUMMARY trigger=hotkey hotkeyToCaptureMs="), line)
        XCTAssertFalse(line.contains("overlayVisibleMs=-"), "the pill's show is in it: \(line)")
        XCTAssertTrue(line.contains("overlayWasParked="), line)
        // A second first-PCM for the same start logs nothing.
        StartPathTrace.captureStarted()
        XCTAssertEqual(self.lines.count, 1)
    }

    func testAStartWithoutAHotkeyStillLogsOnce() {
        StartPathTrace.overlayShown(visibleMs: 7, wasParked: false)
        StartPathTrace.captureRequested(at: ProcessInfo.processInfo.systemUptime + 5)
        StartPathTrace.captureStarted(at: ProcessInfo.processInfo.systemUptime + 5.12)
        StartPathTrace.captureStarted()
        XCTAssertEqual(self.lines.count, 1)
        XCTAssertTrue(self.lines.first?.hasPrefix("START_SUMMARY trigger=other hotkeyToCaptureMs=120") == true, "\(self.lines)")
    }

    func testTheStartSummaryNamesEveryField() {
        XCTAssertEqual(
            StartPathTrace.summary(trigger: "hotkey", captureMs: 142, overlayVisibleMs: 9, overlayWasParked: true, shadowAfterMs: 21),
            "START_SUMMARY trigger=hotkey hotkeyToCaptureMs=142 overlayVisibleMs=9 overlayWasParked=true shadowAfterMs=21"
        )
    }
}
