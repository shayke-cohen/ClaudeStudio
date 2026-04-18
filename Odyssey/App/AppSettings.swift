import SwiftUI
import AppKit

enum AppSettings {
    // MARK: - General
    static let appearanceKey = "odyssey.appearance"
    static let textSizeKey = "odyssey.textSize"
    static let defaultModelKey = "odyssey.defaultModel"
    static let defaultProviderKey = "odyssey.defaultProvider"
    static let defaultClaudeModelKey = defaultModelKey
    static let defaultCodexModelKey = "odyssey.defaultCodexModel"
    static let defaultFoundationModelKey = "odyssey.defaultFoundationModel"
    static let defaultMLXModelKey = "odyssey.defaultMLXModel"
    static let ollamaModelsEnabledKey = "odyssey.ollamaModelsEnabled"
    static let ollamaBaseURLKey = "odyssey.ollamaBaseURL"
    static let ollamaCachedModelsKey = "odyssey.ollamaCachedModels"
    static let ollamaCachedStatusKey = "odyssey.ollamaCachedStatus"
    static let defaultMaxTurnsKey = "odyssey.defaultMaxTurns"
    static let defaultMaxBudgetKey = "odyssey.defaultMaxBudget"
    static let autoConnectSidecarKey = "odyssey.autoConnectSidecar"

    // MARK: - Connection
    static let wsPortKey = "odyssey.wsPort"
    static let httpPortKey = "odyssey.httpPort"
    static let bunPathOverrideKey = "odyssey.bunPathOverride"
    static let sidecarPathKey = "odyssey.projectPath"
    static let localAgentHostPathOverrideKey = "odyssey.localAgentHostPathOverride"
    static let mlxRunnerPathOverrideKey = "odyssey.mlxRunnerPathOverride"
    static let connectorBrokerBaseURLKey = "odyssey.connectorBrokerBaseURL"
    static let xClientIdKey = "odyssey.connectorXClientId"
    static let linkedinClientIdKey = "odyssey.connectorLinkedInClientId"

    // MARK: - Instance
    static let instanceWorkingDirectoryKey = "odyssey.instanceWorkingDirectory"

    // MARK: - Layout
    static let inspectorWidthKey = "odyssey.inspectorWidth"

    // MARK: - Notifications
    static let notificationsEnabledKey = "odyssey.notifications.enabled"
    static let notificationSoundEnabledKey = "odyssey.notifications.sound"

    // MARK: - Chat Display
    static let renderMermaidKey = "odyssey.chat.renderMermaid"
    static let renderHTMLKey = "odyssey.chat.renderHTML"
    static let renderDiffsKey = "odyssey.chat.renderDiffs"
    static let renderTerminalKey = "odyssey.chat.renderTerminal"
    static let renderAdmonitionsKey = "odyssey.chat.renderAdmonitions"
    static let renderPDFKey = "odyssey.chat.renderPDF"
    static let showSessionSummaryKey = "odyssey.chat.showSessionSummary"
    static let showSuggestionChipsKey = "odyssey.chat.showSuggestionChips"
    // MARK: - Quick Actions
    static let quickActionUsageOrderKey  = "odyssey.chat.quickActionUsageOrder"
    static let quickActionUsageCountsKey = "odyssey.chat.quickActionUsageCounts"
    static let quickActionConfigsKey     = "odyssey.chat.quickActionConfigs"    // ← add this

    // MARK: - TURN Relay
    static let turnEnabledKey = "odyssey.turnEnabled"
    static let turnURLKey = "odyssey.turnURL"
    static let turnUsernameKey = "odyssey.turnUsername"
    static let turnCredentialKey = "odyssey.turnCredential"

    // MARK: - Advanced
    static let dataDirectoryKey = "odyssey.dataDirectory"
    static let logLevelKey = "odyssey.logLevel"
    static let builtInConfigOverridePolicyKey = "odyssey.configSync.builtInOverridePolicy"
    static let sharedRoomUserIdKey = "odyssey.sharedRoom.userId"
    static let sharedRoomDisplayNameKey = "odyssey.sharedRoom.displayName"
    static let nostrRelaysKey = "nostrRelays"

    // MARK: - Defaults
    static let defaultWsPort = 9849
    static let defaultHttpPort = 9850
    static let defaultMaxTurns = 30
    static let defaultMaxBudget = 0.0
    static let defaultProvider = ProviderSelection.claude.rawValue
    static let defaultClaudeModel = ClaudeModel.sonnet.rawValue
    static let defaultCodexModel = CodexModel.gpt5Codex.rawValue
    static let defaultFoundationModel = FoundationModel.system.rawValue
    static let defaultMLXModel = MLXModel.defaultModel.rawValue
    static let defaultOllamaModelsEnabled = true
    static let defaultOllamaBaseURL = "http://127.0.0.1:11434"
    static let defaultTextSize = AppTextSize.standard.rawValue
    static let defaultDataDirectory = "~/.odyssey"
    static let defaultLogLevel = "info"
    static let defaultBuiltInConfigOverridePolicy = BuiltInConfigOverridePolicy.yes.rawValue
    static let defaultTurnURL = "turn:openrelay.metered.ca:443?transport=tcp"
    static let defaultTurnUsername = "openrelayproject"
    static let defaultTurnCredential = "openrelayproject"

    /// Per-instance UserDefaults store for use with `@AppStorage(_:store:)`.
    nonisolated(unsafe) static let store: UserDefaults = InstanceConfig.userDefaults

    static var allKeys: [String] {
        [
            appearanceKey, textSizeKey, defaultProviderKey, defaultClaudeModelKey,
            defaultCodexModelKey, defaultFoundationModelKey, defaultMLXModelKey,
            ollamaModelsEnabledKey, ollamaBaseURLKey, ollamaCachedModelsKey, ollamaCachedStatusKey,
            defaultMaxTurnsKey,
            defaultMaxBudgetKey, autoConnectSidecarKey,
            instanceWorkingDirectoryKey,
            wsPortKey, httpPortKey, bunPathOverrideKey, sidecarPathKey,
            localAgentHostPathOverrideKey, mlxRunnerPathOverrideKey,
            connectorBrokerBaseURLKey, xClientIdKey, linkedinClientIdKey,
            notificationsEnabledKey, notificationSoundEnabledKey,
            renderMermaidKey, renderHTMLKey, renderDiffsKey, renderTerminalKey,
            renderAdmonitionsKey, renderPDFKey, showSessionSummaryKey, showSuggestionChipsKey,
            quickActionUsageOrderKey, quickActionUsageCountsKey, quickActionConfigsKey,
            dataDirectoryKey, logLevelKey, builtInConfigOverridePolicyKey,
            sharedRoomUserIdKey, sharedRoomDisplayNameKey,
            turnEnabledKey, turnURLKey, turnUsernameKey, turnCredentialKey,
        ] + FeatureFlags.all
    }

    static func resetAll() {
        let defaults = InstanceConfig.userDefaults
        for key in allKeys {
            defaults.removeObject(forKey: key)
        }
    }
}

enum BuiltInConfigOverridePolicy: String, CaseIterable, Identifiable {
    case yes
    case no
    case ask

    var id: String { rawValue }

    var label: String {
        switch self {
        case .yes: "Yes"
        case .no: "No"
        case .ask: "Ask"
        }
    }

    var summary: String {
        switch self {
        case .yes: "Always refresh bundled built-in prompts, skills, MCPs, and related defaults."
        case .no: "Keep local built-in copies unless they are missing entirely."
        case .ask: "Prompt before replacing local built-in copies that differ from the app bundle."
        }
    }
}

enum AppAppearance: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

enum AppTextSize: Int, CaseIterable, Identifiable {
    case smaller = -2
    case small = -1
    case standard = 0
    case large = 1
    case larger = 2

    var id: Int { rawValue }

    var label: String {
        switch self {
        case .smaller: "Smaller"
        case .small: "Small"
        case .standard: "Standard"
        case .large: "Large"
        case .larger: "Larger"
        }
    }

    var dynamicTypeSize: DynamicTypeSize {
        switch self {
        case .smaller: .xSmall
        case .small: .small
        case .standard: .large
        case .large: .xLarge
        case .larger: .xxLarge
        }
    }

    var scaleFactor: CGFloat {
        switch self {
        case .smaller: 0.85
        case .small: 0.93
        case .standard: 1.0
        case .large: 1.12
        case .larger: 1.24
        }
    }

    var canIncrease: Bool { self != Self.maximum }
    var canDecrease: Bool { self != Self.minimum }

    func increased() -> AppTextSize {
        AppTextSize(rawValue: rawValue + 1) ?? self
    }

    func decreased() -> AppTextSize {
        AppTextSize(rawValue: rawValue - 1) ?? self
    }

    static var minimum: AppTextSize { .smaller }
    static var maximum: AppTextSize { .larger }
}

private struct AppTextScaleKey: EnvironmentKey {
    static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
    var appTextScale: CGFloat {
        get { self[AppTextScaleKey.self] }
        set { self[AppTextScaleKey.self] = newValue }
    }
}

@MainActor
final class AppTextSizeShortcutMonitor {
    static let shared = AppTextSizeShortcutMonitor()

    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
            guard flags == [.command] || flags == [.command, .shift] else {
                return event
            }

            let keys = Set([event.charactersIgnoringModifiers, event.characters].compactMap { $0 })

            if keys.contains("-") {
                Self.update { $0.decreased() }
                return nil
            }

            if keys.contains("0") {
                AppSettings.store.set(AppTextSize.standard.rawValue, forKey: AppSettings.textSizeKey)
                return nil
            }

            if keys.contains("=") || keys.contains("+") {
                Self.update { $0.increased() }
                return nil
            }

            return event
        }
    }

    private static func update(_ transform: (AppTextSize) -> AppTextSize) {
        let rawValue = AppSettings.store.object(forKey: AppSettings.textSizeKey) as? Int ?? AppSettings.defaultTextSize
        let current = AppTextSize(rawValue: rawValue) ?? .standard
        AppSettings.store.set(transform(current).rawValue, forKey: AppSettings.textSizeKey)
    }
}

enum ClaudeModel: String, CaseIterable, Identifiable {
    case sonnet = "claude-sonnet-4-6"
    case opus = "claude-opus-4-6"
    case haiku = "claude-haiku-4-5-20251001"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sonnet: "Claude Sonnet 4.6"
        case .opus: "Claude Opus 4.6"
        case .haiku: "Claude Haiku 4.5"
        }
    }
}

enum FoundationModel: String, CaseIterable, Identifiable {
    case system = "foundation.system"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "Apple Foundation Model"
        }
    }
}

enum MLXModel: String, CaseIterable, Identifiable {
    case defaultModel = "mlx-community/Qwen3-4B-Instruct-2507-4bit"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .defaultModel: "Qwen3 4B Instruct 2507"
        }
    }
}

enum LogLevel: String, CaseIterable, Identifiable {
    case debug, info, warn, error

    var id: String { rawValue }

    var label: String { rawValue.capitalized }
}
