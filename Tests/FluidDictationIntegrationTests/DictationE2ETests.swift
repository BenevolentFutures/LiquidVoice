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

    override func tearDown() {
        SignalRenderStage.reset()
        super.tearDown()
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
                XCTAssertEqual(rep.size.height, 149 + 12 + 2 * SignalRenderStage.backdropMargin, "\(theme) \(name)")
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
    static let transcript = "worker sees the same job id land twice so key the admission set on job id plus lease epoch and do not touch the scheduler when you are done give me a one line summary and the diff stat and if the suite takes longer than a minute tell me which tests are"

    static let overlayStates: [(String, () -> Void)] = [
        ("01-listening", { SignalRenderStage.listening() }),
        ("02-listening-hover", { SignalRenderStage.listening(); SignalOverlayModel.shared.inspectionHover = "pill" }),
        ("03-listening-hover-cancel", { SignalRenderStage.listening(); SignalOverlayModel.shared.inspectionHover = "cancel" }),
        ("04-listening-armed", { SignalRenderStage.listening(); SignalOverlayModel.shared.inspectionPlacard = .send }),
        ("05-transcribing", { SignalRenderStage.listening(); SignalRenderStage.stop(); NotchContentState.shared.setProcessing(true); SignalOverlayModel.shared.beginTranscribing() }),
        ("06-pasted", { SignalRenderStage.listening(); SignalRenderStage.stop(); SignalOverlayModel.shared.showDelivered(SignalDelivery(appName: "c11", words: 118, method: .paste, sentReturn: false)) }),
        ("13-countdown", { SignalRenderStage.listening(); SignalOverlayModel.shared.inspectionPlacard = .send; SignalOverlayModel.shared.startSendCountdown(duration: 1.5, at: Date().addingTimeInterval(-0.55)) }),
        ("14-countdown-canceled", {
            SignalRenderStage.listening()
            SignalOverlayModel.shared.startSendCountdown(duration: 1.5, at: Date().addingTimeInterval(-0.6))
            SignalOverlayModel.shared.freezeSendCountdown()
        }),
        ("15-sent", { SignalRenderStage.listening(); SignalRenderStage.stop(placard: .send); SignalOverlayModel.shared.showDelivered(SignalDelivery(appName: "c11", words: 118, method: .paste, sentReturn: true)) }),
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
