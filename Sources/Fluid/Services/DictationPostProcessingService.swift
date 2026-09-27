import Foundation

struct DictationProviderRoute: Equatable {
    let providerID: String
    let providerKey: String
    let baseURL: String
    let model: String
    let apiKey: String

    static func resolve(
        settings: SettingsStore,
        dictationSlot: SettingsStore.DictationShortcutSlot? = nil,
        appBundleID: String? = nil
    ) -> Self {
        let selectedProviderID: String
        let configuredModel: String?

        if let dictationSlot {
            let selection = self.effectivePromptSelection(
                settings: settings,
                dictationSlot: dictationSlot,
                appBundleID: appBundleID
            )
            if selection == .off {
                return Self(providerID: "", providerKey: "", baseURL: "", model: "", apiKey: "")
            }

            let configuration = settings.dictationPromptConfiguration(for: selection)
            let providerID = configuration.providerID.trimmingCharacters(in: .whitespacesAndNewlines)
            let model = configuration.modelName.trimmingCharacters(in: .whitespacesAndNewlines)
            // A prompt pinned to a retired provider fails closed (raw text). It must never fall
            // back to the main provider, which may be a cloud service the user never chose for it.
            if SettingsStore.isRetiredProviderID(providerID) {
                return Self(providerID: "", providerKey: "", baseURL: "", model: "", apiKey: "")
            }
            if !providerID.isEmpty, !model.isEmpty {
                selectedProviderID = providerID
                configuredModel = model
            } else {
                selectedProviderID = settings.selectedProviderID
                configuredModel = nil
            }
        } else {
            selectedProviderID = settings.selectedProviderID
            configuredModel = nil
        }

        guard !SettingsStore.isRetiredProviderID(selectedProviderID) else {
            return Self(providerID: "", providerKey: "", baseURL: "", model: "", apiKey: "")
        }

        let selectedModels = settings.selectedModelByProvider
        let providerKeys = settings.providerAPIKeys

        if let saved = settings.savedProviders.first(where: { $0.id == selectedProviderID }) {
            let key = "custom:\(saved.id)"
            return Self(
                providerID: selectedProviderID,
                providerKey: key,
                baseURL: saved.baseURL,
                model: configuredModel ?? selectedModels[key] ?? saved.models.first ?? "",
                apiKey: providerKeys[key] ?? providerKeys[selectedProviderID] ?? ""
            )
        }

        if ModelRepository.shared.isBuiltIn(selectedProviderID) {
            return Self(
                providerID: selectedProviderID,
                providerKey: selectedProviderID,
                baseURL: ModelRepository.shared.defaultBaseURL(for: selectedProviderID),
                model: configuredModel ?? selectedModels[selectedProviderID] ?? ModelRepository.shared.defaultModels(for: selectedProviderID).first ?? "",
                apiKey: providerKeys[selectedProviderID] ?? ""
            )
        }

        return Self(
            providerID: selectedProviderID,
            providerKey: selectedProviderID,
            baseURL: "",
            model: configuredModel ?? selectedModels[selectedProviderID] ?? "",
            apiKey: providerKeys[selectedProviderID] ?? ""
        )
    }

    static func resolveForPostProcessing(
        settings: SettingsStore,
        dictationSlot: SettingsStore.DictationShortcutSlot
    ) -> Self {
        if settings.promptRoutingScope(for: .dictate) == .selectedAppsOnly {
            return self.resolve(settings: settings)
        }
        return self.resolve(settings: settings, dictationSlot: dictationSlot)
    }

    private static func effectivePromptSelection(
        settings: SettingsStore,
        dictationSlot: SettingsStore.DictationShortcutSlot,
        appBundleID: String?
    ) -> SettingsStore.DictationPromptSelection {
        let selection = settings.dictationPromptSelection(for: dictationSlot)
        guard selection != .off else { return selection }

        let usesOnlyAppBindings = settings.promptRoutingScope(for: .dictate) == .selectedAppsOnly
        guard usesOnlyAppBindings || selection == .default else { return selection }
        guard let binding = settings.appPromptBinding(for: .dictate, appBundleID: appBundleID) else {
            return usesOnlyAppBindings ? .off : selection
        }
        guard let promptID = binding.promptID,
              settings.dictationPromptProfiles.contains(where: {
                  $0.id == promptID && $0.mode.normalized == .dictate
              })
        else {
            return .default
        }
        return .profile(promptID)
    }
}

@MainActor
final class DictationPostProcessingService {
    static let shared = DictationPostProcessingService()

    private init() {}

    struct Result {
        let text: String
        let providerID: String
        let model: String
    }

    func process(_ inputText: String, dictationSlot: SettingsStore.DictationShortcutSlot = .primary) async throws -> Result {
        let trimmed = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return Result(text: "", providerID: SettingsStore.shared.selectedProviderID, model: "")
        }

        let settings = SettingsStore.shared
        let resolved = DictationProviderRoute.resolveForPostProcessing(
            settings: settings,
            dictationSlot: dictationSlot
        )
        guard !resolved.providerID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProcessingError.noVerifiedProvider
        }
        DebugLogger.shared.debug(
            "DictationPostProcessingService using provider=\(resolved.providerKey), model=\(resolved.model)",
            source: "DictationPostProcessingService"
        )

        let promptText = settings.effectiveDictationSystemPrompt(for: dictationSlot, appBundleID: nil)
        let systemPrompt = ""
        let userMessageContent = SettingsStore.renderDictationUserMessage(
            promptText: promptText,
            transcript: trimmed
        )

        guard !resolved.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw AIProcessingError.missingModel(provider: resolved.providerKey)
        }

        let isLocal = ModelRepository.shared.isLocalEndpoint(resolved.baseURL)
        if !isLocal, resolved.apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw AIProcessingError.missingAPIKey(provider: resolved.providerKey)
        }

        var extraParams: [String: Any] = [:]
        if let config = settings.getReasoningConfig(forModel: resolved.model, provider: resolved.providerKey), config.isEnabled {
            extraParams[config.parameterName] = config.parameterName == "enable_thinking"
                ? (config.parameterValue == "true")
                : config.parameterValue
        }

        var messages: [[String: Any]] = []
        if !systemPrompt.isEmpty {
            messages.append(["role": "system", "content": systemPrompt])
        }
        messages.append(["role": "user", "content": userMessageContent])

        var config = LLMClient.Config(
            messages: messages,
            model: resolved.model,
            baseURL: resolved.baseURL,
            apiKey: resolved.apiKey,
            streaming: false,
            tools: [],
            temperature: settings.isTemperatureUnsupported(resolved.model) ? nil : 0.2,
            extraParameters: extraParams
        )
        config.timeoutSeconds = 120

        let response = try await LLMClient.shared.call(config)
        guard !response.content.isEmpty else {
            throw AIProcessingError.emptyResponse
        }
        return Result(
            text: ASRService.applyGAAVFormatting(response.content),
            providerID: resolved.providerID,
            model: resolved.model
        )
    }
}
