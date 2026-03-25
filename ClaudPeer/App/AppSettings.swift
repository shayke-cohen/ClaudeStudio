import SwiftUI

enum AppSettings {
    // MARK: - General
    static let appearanceKey = "claudpeer.appearance"
    static let defaultModelKey = "claudpeer.defaultModel"
    static let defaultMaxTurnsKey = "claudpeer.defaultMaxTurns"
    static let defaultMaxBudgetKey = "claudpeer.defaultMaxBudget"
    static let autoConnectSidecarKey = "claudpeer.autoConnectSidecar"

    // MARK: - Connection
    static let wsPortKey = "claudpeer.wsPort"
    static let httpPortKey = "claudpeer.httpPort"
    static let bunPathOverrideKey = "claudpeer.bunPathOverride"
    static let sidecarPathKey = "claudpeer.projectPath"

    // MARK: - Instance
    static let instanceWorkingDirectoryKey = "claudpeer.instanceWorkingDirectory"

    // MARK: - Layout
    static let inspectorWidthKey = "claudpeer.inspectorWidth"

    // MARK: - Notifications
    static let notificationsEnabledKey = "claudpeer.notifications.enabled"
    static let notificationSoundEnabledKey = "claudpeer.notifications.sound"

    // MARK: - Chat Display
    static let renderMermaidKey = "claudpeer.chat.renderMermaid"
    static let renderHTMLKey = "claudpeer.chat.renderHTML"
    static let renderDiffsKey = "claudpeer.chat.renderDiffs"
    static let renderTerminalKey = "claudpeer.chat.renderTerminal"
    static let renderAdmonitionsKey = "claudpeer.chat.renderAdmonitions"
    static let renderPDFKey = "claudpeer.chat.renderPDF"
    static let showSessionSummaryKey = "claudpeer.chat.showSessionSummary"
    static let showSuggestionChipsKey = "claudpeer.chat.showSuggestionChips"

    // MARK: - Advanced
    static let dataDirectoryKey = "claudpeer.dataDirectory"
    static let logLevelKey = "claudpeer.logLevel"

    // MARK: - Defaults
    static let defaultWsPort = 9849
    static let defaultHttpPort = 9850
    static let defaultMaxTurns = 30
    static let defaultMaxBudget = 0.0
    static let defaultModel = "claude-sonnet-4-6"
    static let defaultDataDirectory = "~/.claudpeer"
    static let defaultLogLevel = "info"

    /// Per-instance UserDefaults store for use with `@AppStorage(_:store:)`.
    nonisolated(unsafe) static let store: UserDefaults = InstanceConfig.userDefaults

    static var allKeys: [String] {
        [
            appearanceKey, defaultModelKey, defaultMaxTurnsKey,
            defaultMaxBudgetKey, autoConnectSidecarKey,
            instanceWorkingDirectoryKey,
            wsPortKey, httpPortKey, bunPathOverrideKey, sidecarPathKey,
            notificationsEnabledKey, notificationSoundEnabledKey,
            renderMermaidKey, renderHTMLKey, renderDiffsKey, renderTerminalKey,
            renderAdmonitionsKey, renderPDFKey, showSessionSummaryKey, showSuggestionChipsKey,
            dataDirectoryKey, logLevelKey,
        ]
    }

    static func resetAll() {
        let defaults = InstanceConfig.userDefaults
        for key in allKeys {
            defaults.removeObject(forKey: key)
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

enum LogLevel: String, CaseIterable, Identifiable {
    case debug, info, warn, error

    var id: String { rawValue }

    var label: String { rawValue.capitalized }
}
