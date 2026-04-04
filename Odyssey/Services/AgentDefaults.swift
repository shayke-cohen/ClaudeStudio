import Foundation

enum ProviderSelection: String, CaseIterable, Identifiable {
    case system
    case claude
    case codex
    case foundation
    case mlx

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .claude: "Claude"
        case .codex: "Codex"
        case .foundation: "Foundation"
        case .mlx: "MLX"
        }
    }

    var concreteProvider: String? {
        switch self {
        case .system: nil
        case .claude, .codex, .foundation, .mlx: rawValue
        }
    }
}

enum CodexModel: String, CaseIterable, Identifiable {
    case gpt5Codex = "gpt-5-codex"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .gpt5Codex: "GPT-5 Codex"
        }
    }
}

struct ModelChoice: Identifiable, Equatable {
    let id: String
    let label: String
}

enum AgentDefaults {
    static let inheritMarker = ProviderSelection.system.rawValue
    static let defaultFreeformSystemPrompt = "You are a helpful assistant. Be concise and clear."
    static let ollamaModelPrefix = "ollama:"

    static func normalizedProviderSelection(_ value: String?) -> ProviderSelection {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case ProviderSelection.claude.rawValue:
            .claude
        case ProviderSelection.codex.rawValue:
            .codex
        case ProviderSelection.foundation.rawValue:
            .foundation
        case ProviderSelection.mlx.rawValue:
            .mlx
        default:
            .system
        }
    }

    static func defaultProvider() -> String {
        normalizedProviderSelection(
            AppSettings.store.string(forKey: AppSettings.defaultProviderKey) ?? AppSettings.defaultProvider
        ).concreteProvider ?? AppSettings.defaultProvider
    }

    static func concreteProvider(from value: String?) -> String {
        normalizedProviderSelection(value).concreteProvider ?? defaultProvider()
    }

    static func defaultModel(for provider: String) -> String {
        switch provider {
        case ProviderSelection.codex.rawValue:
            let stored = AppSettings.store.string(forKey: AppSettings.defaultCodexModelKey)
            let normalized = normalizedModelSelection(stored ?? AppSettings.defaultCodexModel)
            return isModel(normalized, compatibleWith: provider) ? normalized : AppSettings.defaultCodexModel
        case ProviderSelection.foundation.rawValue:
            let stored = AppSettings.store.string(forKey: AppSettings.defaultFoundationModelKey)
            let normalized = normalizedModelSelection(stored ?? AppSettings.defaultFoundationModel)
            return isModel(normalized, compatibleWith: provider) ? normalized : AppSettings.defaultFoundationModel
        case ProviderSelection.mlx.rawValue:
            let stored = AppSettings.store.string(forKey: AppSettings.defaultMLXModelKey)
            let normalized = normalizedModelSelection(stored ?? AppSettings.defaultMLXModel)
            return isAgentSuitableMLXSelection(normalized) ? normalized : AppSettings.defaultMLXModel
        default:
            let stored = AppSettings.store.string(forKey: AppSettings.defaultClaudeModelKey)
            let normalized = normalizedModelSelection(stored ?? AppSettings.defaultClaudeModel)
            return isModel(normalized, compatibleWith: ProviderSelection.claude.rawValue)
                ? normalized
                : AppSettings.defaultClaudeModel
        }
    }

    static func normalizedModelSelection(_ value: String?) -> String {
        switch value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case nil, "", "default", "inherit", "system", "provider_default":
            inheritMarker
        case "sonnet":
            ClaudeModel.sonnet.rawValue
        case "opus":
            ClaudeModel.opus.rawValue
        case "haiku":
            ClaudeModel.haiku.rawValue
        default:
            value ?? inheritMarker
        }
    }

    static func resolveEffectiveProvider(
        sessionOverride: String? = nil,
        agentSelection: String? = nil
    ) -> String {
        normalizedProviderSelection(sessionOverride).concreteProvider
            ?? normalizedProviderSelection(agentSelection).concreteProvider
            ?? defaultProvider()
    }

    static func resolveEffectiveModel(
        sessionOverride: String? = nil,
        agentSelection: String? = nil,
        provider: String
    ) -> String {
        let sessionCandidate = explicitModelSelection(from: sessionOverride)
        if let sessionCandidate, isModel(sessionCandidate, compatibleWith: provider) {
            return sessionCandidate
        }

        let agentCandidate = explicitModelSelection(from: agentSelection)
        if let agentCandidate, isModel(agentCandidate, compatibleWith: provider) {
            return agentCandidate
        }

        return defaultModel(for: provider)
    }

    static func isModel(_ model: String, compatibleWith provider: String) -> Bool {
        let normalized = normalizedModelSelection(model)
        if normalized == inheritMarker {
            return true
        }

        switch provider {
        case ProviderSelection.codex.rawValue:
            return CodexModel.allCases.contains { $0.rawValue == normalized }
        case ProviderSelection.foundation.rawValue:
            return FoundationModel.allCases.contains { $0.rawValue == normalized }
        case ProviderSelection.mlx.rawValue:
            return isCompatibleMLXModelSelection(normalized)
        default:
            return ClaudeModel.allCases.contains { $0.rawValue == normalized }
                || isOllamaBackedClaudeModel(normalized)
        }
    }

    static func defaultModelChoiceLabel(for provider: String) -> String {
        "Default (\(label(for: defaultModel(for: provider))))"
    }

    static func availableAgentModelChoices(
        for providerSelection: String,
        preserving currentSelection: String? = nil
    ) -> [ModelChoice] {
        let selection = normalizedProviderSelection(providerSelection)
        var choices = [ModelChoice(id: inheritMarker, label: selection == .system ? "System Default" : "Default for \(selection.label)")]

        switch selection {
        case .claude:
            choices.append(contentsOf: claudeModelChoices())
        case .codex:
            choices.append(contentsOf: CodexModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) })
        case .foundation:
            choices.append(contentsOf: FoundationModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) })
        case .mlx:
            choices.append(contentsOf: mlxConfiguredModelChoices())
        case .system:
            choices.append(contentsOf: ClaudeModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) })
            choices.append(contentsOf: CodexModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) })
            choices.append(contentsOf: FoundationModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) })
            choices.append(contentsOf: mlxConfiguredModelChoices())
        }

        return preserveUnavailableSelection(currentSelection, in: choices)
    }

    static func availableThreadModelChoices(
        for provider: String,
        inheritLabel: String = "Inherit from Agent",
        preserving currentSelection: String? = nil
    ) -> [ModelChoice] {
        var choices = [ModelChoice(id: inheritMarker, label: inheritLabel)]
        switch provider {
        case ProviderSelection.codex.rawValue:
            choices.append(contentsOf: CodexModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) })
        case ProviderSelection.foundation.rawValue:
            choices.append(contentsOf: FoundationModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) })
        case ProviderSelection.mlx.rawValue:
            choices.append(contentsOf: mlxConfiguredModelChoices())
        default:
            choices.append(contentsOf: claudeModelChoices())
        }
        return preserveUnavailableSelection(currentSelection, in: choices)
    }

    static func availableDefaultModelChoices(
        for provider: String,
        preserving currentSelection: String? = nil
    ) -> [ModelChoice] {
        let choices: [ModelChoice]
        switch provider {
        case ProviderSelection.codex.rawValue:
            choices = CodexModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) }
        case ProviderSelection.foundation.rawValue:
            choices = FoundationModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) }
        case ProviderSelection.mlx.rawValue:
            choices = mlxConfiguredModelChoices()
        default:
            choices = claudeModelChoices()
        }
        return preserveUnavailableSelection(currentSelection, in: choices)
    }

    static func preferredModelSelection(_ current: String?, providerSelection: String) -> String {
        let normalized = normalizedModelSelection(current)
        let selection = normalizedProviderSelection(providerSelection)
        let choices = availableAgentModelChoices(for: selection.rawValue)
        return choices.contains(where: { $0.id == normalized }) ? normalized : inheritMarker
    }

    static func label(for model: String?) -> String {
        let normalized = normalizedModelSelection(model)
        if normalized == inheritMarker {
            return "System Default"
        }
        if let match = ClaudeModel.allCases.first(where: { $0.rawValue == normalized }) {
            return match.label
        }
        if isOllamaBackedClaudeModel(normalized) {
            return ollamaLabel(for: normalized)
        }
        if let match = CodexModel.allCases.first(where: { $0.rawValue == normalized }) {
            return match.label
        }
        if let match = FoundationModel.allCases.first(where: { $0.rawValue == normalized }) {
            return match.label
        }
        if let match = mlxModelChoice(for: normalized) {
            return match.label
        }
        if let pathLabel = inferredMLXPathLabel(for: normalized) {
            return pathLabel
        }
        return model ?? inheritMarker
    }

    static func displayName(forProvider provider: String?) -> String {
        switch concreteProvider(from: provider) {
        case ProviderSelection.codex.rawValue:
            return ProviderSelection.codex.label
        case ProviderSelection.foundation.rawValue:
            return ProviderSelection.foundation.label
        case ProviderSelection.mlx.rawValue:
            return ProviderSelection.mlx.label
        default:
            return ProviderSelection.claude.label
        }
    }

    static func makeFreeformAgentConfig(
        provider: String?,
        model: String?,
        workingDirectory: String,
        systemPrompt: String = defaultFreeformSystemPrompt,
        maxTurns: Int? = 5,
        maxBudget: Double? = nil,
        maxThinkingTokens: Int? = 10000,
        interactive: Bool? = true,
        instancePolicy: String? = nil,
        instancePolicyPoolMax: Int? = nil
    ) -> AgentConfig {
        let resolvedProvider = concreteProvider(from: provider)
        let resolvedModel = {
            let normalized = normalizedModelSelection(model)
            if normalized != inheritMarker, isModel(normalized, compatibleWith: resolvedProvider) {
                return normalized
            }
            return defaultModel(for: resolvedProvider)
        }()

        return AgentConfig(
            name: displayName(forProvider: resolvedProvider),
            systemPrompt: systemPrompt,
            allowedTools: [],
            mcpServers: [],
            provider: resolvedProvider,
            model: resolvedModel,
            maxTurns: maxTurns,
            maxBudget: maxBudget,
            maxThinkingTokens: maxThinkingTokens,
            workingDirectory: workingDirectory,
            skills: [],
            interactive: interactive,
            instancePolicy: instancePolicy,
            instancePolicyPoolMax: instancePolicyPoolMax
        )
    }

    static func isOllamaBackedClaudeModel(_ selection: String?) -> Bool {
        let trimmed = selection?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.lowercased().hasPrefix(ollamaModelPrefix)
            && trimmed.count > ollamaModelPrefix.count
    }

    static func stripOllamaPrefix(from selection: String?) -> String? {
        guard let selection, isOllamaBackedClaudeModel(selection) else { return nil }
        return String(selection.dropFirst(ollamaModelPrefix.count))
    }

    private static func explicitModelSelection(from value: String?) -> String? {
        let normalized = normalizedModelSelection(value)
        return normalized == inheritMarker ? nil : normalized
    }

    private static func claudeModelChoices() -> [ModelChoice] {
        var choices = ClaudeModel.allCases.map { ModelChoice(id: $0.rawValue, label: $0.label) }
        if OllamaCatalogService.modelsEnabled() {
            choices.append(contentsOf: OllamaCatalogService.cachedModels().map { cachedModel in
                ModelChoice(id: cachedModel.selectionValue, label: cachedModel.label)
            })
        }
        return deduplicatedModelChoices(choices, appending: nil)
    }

    private static func mlxConfiguredModelChoices() -> [ModelChoice] {
        let configured = normalizedModelSelection(
            AppSettings.store.string(forKey: AppSettings.defaultMLXModelKey) ?? AppSettings.defaultMLXModel
        )
        let installedChoices = installedMLXModelChoices(agentSuitableOnly: true)
        let fallbackChoice = ModelChoice(
            id: AppSettings.defaultMLXModel,
            label: label(forInstalledOrKnownMLXSelection: AppSettings.defaultMLXModel)
        )

        guard configured != inheritMarker else {
            return installedChoices.isEmpty
                ? [fallbackChoice]
                : installedChoices
        }

        if let matchingInstalledChoice = installedChoices.first(where: { $0.id == configured }) {
            return uniqueModelChoices(installedChoices, appending: matchingInstalledChoice)
        }

        guard isAgentSuitableMLXSelection(configured) else {
            return installedChoices.isEmpty ? [fallbackChoice] : installedChoices
        }

        let configuredChoice = ModelChoice(
            id: configured,
            label: "Configured MLX Model (\(label(forInstalledOrKnownMLXSelection: configured)))"
        )
        return uniqueModelChoices(installedChoices, appending: configuredChoice)
    }

    static func isLikelyMLXModelSelection(_ value: String?) -> Bool {
        let normalized = normalizedModelSelection(value)
        guard normalized != inheritMarker else { return false }
        return isCompatibleMLXModelSelection(normalized)
    }

    private static func installedMLXModelChoices(agentSuitableOnly: Bool = false) -> [ModelChoice] {
        let dataDirectory = AppSettings.store.string(forKey: AppSettings.dataDirectoryKey) ?? AppSettings.defaultDataDirectory
        let presetLookup = Dictionary(
            uniqueKeysWithValues: LocalProviderInstaller.recommendedMLXPresets().map { ($0.modelIdentifier, $0) }
        )

        return LocalProviderInstaller.installedMLXModels(dataDirectoryPath: dataDirectory)
            .filter { installedModel in
                !agentSuitableOnly || isAgentSuitableInstalledMLXModel(installedModel, presetLookup: presetLookup)
            }
            .map { installedModel in
                let choiceId = mlxSelectionValue(for: installedModel)
                let label = label(forInstalledModel: installedModel, presetLookup: presetLookup)
                return ModelChoice(id: choiceId, label: label)
            }
            .sorted { $0.label.localizedCaseInsensitiveCompare($1.label) == .orderedAscending }
    }

    private static func isCompatibleMLXModelSelection(_ selection: String) -> Bool {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }

        if mlxModelChoice(for: trimmed) != nil || inferredMLXPathLabel(for: trimmed) != nil {
            return true
        }

        let lowercased = trimmed.lowercased()
        if lowercased == FoundationModel.system.rawValue {
            return false
        }

        if ClaudeModel.allCases.contains(where: { $0.rawValue == trimmed }) || CodexModel.allCases.contains(where: { $0.rawValue == trimmed }) {
            return false
        }

        // Treat Hugging Face-style repo identifiers and local-style paths as valid MLX selections.
        if trimmed.contains("/") {
            return true
        }

        return false
    }

    private static func ollamaLabel(for selection: String) -> String {
        if let cachedModel = OllamaCatalogService.cachedModels().first(where: { $0.selectionValue == selection }) {
            return cachedModel.label
        }
        if let stripped = stripOllamaPrefix(from: selection) {
            return "Ollama: \(stripped)"
        }
        return selection
    }

    private static func preserveUnavailableSelection(
        _ currentSelection: String?,
        in choices: [ModelChoice]
    ) -> [ModelChoice] {
        guard let currentSelection else { return choices }
        let normalized = normalizedModelSelection(currentSelection)
        guard normalized != inheritMarker else { return choices }
        guard !choices.contains(where: { $0.id == normalized }) else { return choices }
        return deduplicatedModelChoices(
            choices,
            appending: ModelChoice(id: normalized, label: "\(label(for: normalized)) (Unavailable)")
        )
    }

    private static func deduplicatedModelChoices(_ choices: [ModelChoice], appending extraChoice: ModelChoice?) -> [ModelChoice] {
        var seen = Set<String>()
        var ordered = [ModelChoice]()

        for choice in choices {
            if seen.insert(choice.id).inserted {
                ordered.append(choice)
            }
        }

        if let extraChoice, seen.insert(extraChoice.id).inserted {
            ordered.append(extraChoice)
        }

        return ordered
    }

    private static func isAgentSuitableMLXSelection(_ selection: String) -> Bool {
        let trimmed = selection.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isCompatibleMLXModelSelection(trimmed) else { return false }

        if let preset = LocalProviderInstaller.recommendedMLXPresets().first(where: { $0.modelIdentifier == trimmed }) {
            return isAgentSuitableMLXPreset(preset)
        }

        if let pathLabel = inferredMLXPathLabel(for: trimmed), !pathLabel.isEmpty {
            return true
        }

        return !looksTooSmallForAgentUse(trimmed.lowercased())
    }

    private static func isAgentSuitableInstalledMLXModel(
        _ installedModel: ManagedInstalledMLXModel,
        presetLookup: [String: ManagedMLXModelPreset]
    ) -> Bool {
        if let preset = presetLookup[installedModel.modelIdentifier] {
            return isAgentSuitableMLXPreset(preset)
        }

        return isAgentSuitableMLXSelection(mlxSelectionValue(for: installedModel))
    }

    private static func isAgentSuitableMLXPreset(_ preset: ManagedMLXModelPreset) -> Bool {
        !looksTooSmallForAgentUse(preset.modelIdentifier.lowercased())
    }

    private static func looksTooSmallForAgentUse(_ lowercasedSelection: String) -> Bool {
        let tinySizeMarkers = ["-0.5b", "-0.6b", "-1b", "-1.5b", "-1.7b", "-2b", "-3b"]
        return tinySizeMarkers.contains(where: { lowercasedSelection.contains($0) })
    }

    private static func mlxModelChoice(for selection: String) -> ModelChoice? {
        if let installedChoice = installedMLXModelChoices().first(where: { $0.id == selection }) {
            return installedChoice
        }

        if let preset = LocalProviderInstaller.recommendedMLXPresets().first(where: { $0.modelIdentifier == selection }) {
            return ModelChoice(id: selection, label: presetLabel(for: preset))
        }

        return nil
    }

    private static func mlxSelectionValue(for installedModel: ManagedInstalledMLXModel) -> String {
        guard shouldUseManagedPathSelection(for: installedModel),
              let managedPath = installedModel.managedPath else {
            return installedModel.modelIdentifier
        }
        return managedPath
    }

    private static func shouldUseManagedPathSelection(for installedModel: ManagedInstalledMLXModel) -> Bool {
        guard let sourceURL = installedModel.sourceURL,
              let url = URL(string: sourceURL) else {
            return false
        }
        let host = url.host?.lowercased()
        return !["huggingface.co", "www.huggingface.co", "hf.co"].contains(host ?? "")
    }

    private static func label(forInstalledModel installedModel: ManagedInstalledMLXModel, presetLookup: [String: ManagedMLXModelPreset]) -> String {
        if let preset = presetLookup[installedModel.modelIdentifier] {
            return presetLabel(for: preset)
        }
        return label(forInstalledOrKnownMLXSelection: mlxSelectionValue(for: installedModel))
    }

    private static func label(forInstalledOrKnownMLXSelection selection: String) -> String {
        if let inferredPathLabel = inferredMLXPathLabel(for: selection) {
            return inferredPathLabel
        }
        return inferredMLXIdentifierLabel(for: selection)
    }

    private static func presetLabel(for preset: ManagedMLXModelPreset) -> String {
        if preset.parameterSize.isEmpty {
            return preset.label
        }
        return "\(preset.label) • \(preset.parameterSize)"
    }

    private static func inferredMLXPathLabel(for value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") else { return nil }
        let name = URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath).lastPathComponent
        guard !name.isEmpty else { return nil }
        return inferredMLXIdentifierLabel(for: name)
    }

    private static func inferredMLXIdentifierLabel(for value: String) -> String {
        let tail = value.split(separator: "/").last.map(String.init) ?? value
        return tail
            .replacingOccurrences(of: "-4bit", with: "")
            .replacingOccurrences(of: "-", with: " ")
    }

    private static func uniqueModelChoices(_ base: [ModelChoice], appending extra: ModelChoice) -> [ModelChoice] {
        if base.contains(where: { $0.id == extra.id }) {
            return base
        }
        return base + [extra]
    }
}
