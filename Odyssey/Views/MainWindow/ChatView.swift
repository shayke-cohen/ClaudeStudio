import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import AppKit
import OSLog

// MARK: - Quick Actions

enum QuickAction: String, CaseIterable, Identifiable {
    case fixIt
    case continueWork
    case commitAndPush
    case runTests
    case undo
    case tldr
    case doubleCheck
    case openIt
    case visualOptions
    case showVisual

    var id: String { rawValue }

    var label: String {
        switch self {
        case .tldr: return "TL;DR"
        case .visualOptions: return "Visual Options"
        case .doubleCheck: return "Double Check"
        case .showVisual: return "Show Visual"
        case .openIt: return "Open It"
        case .commitAndPush: return "Commit & Push"
        case .fixIt: return "Fix It"
        case .runTests: return "Run Tests"
        case .continueWork: return "Continue"
        case .undo: return "Undo"
        }
    }

    var icon: String {
        switch self {
        case .tldr: return "bolt.fill"
        case .visualOptions: return "paintpalette.fill"
        case .doubleCheck: return "checkmark.seal.fill"
        case .showVisual: return "eye.fill"
        case .openIt: return "link"
        case .commitAndPush: return "paperplane.fill"
        case .fixIt: return "wrench.and.screwdriver.fill"
        case .runTests: return "flask.fill"
        case .continueWork: return "play.fill"
        case .undo: return "arrow.uturn.backward"
        }
    }

    var prompt: String {
        switch self {
        case .tldr: return "Give me a TL;DR summary of what we've done and where we are"
        case .visualOptions: return "Show me visual options for this — present alternatives I can choose from"
        case .doubleCheck: return "Double check your last response — verify it's correct and nothing is missing"
        case .showVisual: return "Show me this in a visual way — diagram, mockup, or illustration"
        case .openIt: return "Open it — launch, run, or preview what we just built"
        case .commitAndPush: return "Commit all changes and push to the remote"
        case .fixIt: return "Fix the error above"
        case .runTests: return "Run the tests and show me the results"
        case .continueWork: return "Continue where you left off"
        case .undo: return "Undo the last changes you made — revert them"
        }
    }

    /// Default popularity order (used until 10 total uses accumulated)
    static let defaultPopularityOrder: [QuickAction] = [
        .fixIt, .continueWork, .commitAndPush, .runTests, .undo,
        .tldr, .doubleCheck, .openIt, .visualOptions, .showVisual,
    ]

    /// Minimum total uses before switching to usage-based ordering
    static let usageThreshold = 10
}

// MARK: - Quick Action Usage Tracker

@MainActor
final class QuickActionUsageTracker: ObservableObject {
    @Published private(set) var orderedActions: [QuickAction] = QuickAction.defaultPopularityOrder
    @AppStorage(AppSettings.quickActionUsageOrderKey, store: AppSettings.store) private var usageOrderEnabled = true

    private let defaults = AppSettings.store

    init() {
        recomputeOrder()
    }

    var isUsageOrderEnabled: Bool {
        get { usageOrderEnabled }
        set {
            usageOrderEnabled = newValue
            recomputeOrder()
        }
    }

    func recordUsage(_ action: QuickAction) {
        var counts = loadCounts()
        counts[action.rawValue, default: 0] += 1
        defaults.set(counts, forKey: AppSettings.quickActionUsageCountsKey)
        recomputeOrder()
    }

    func recomputeOrder() {
        guard usageOrderEnabled else {
            orderedActions = QuickAction.defaultPopularityOrder
            return
        }

        let counts = loadCounts()
        let total = counts.values.reduce(0, +)

        guard total >= QuickAction.usageThreshold else {
            orderedActions = QuickAction.defaultPopularityOrder
            return
        }

        // Sort by usage count descending, break ties by default popularity
        let defaultOrder = QuickAction.defaultPopularityOrder
        orderedActions = QuickAction.allCases.sorted { a, b in
            let ca = counts[a.rawValue] ?? 0
            let cb = counts[b.rawValue] ?? 0
            if ca != cb { return ca > cb }
            let ia = defaultOrder.firstIndex(of: a) ?? 0
            let ib = defaultOrder.firstIndex(of: b) ?? 0
            return ia < ib
        }
    }

    private func loadCounts() -> [String: Int] {
        (defaults.dictionary(forKey: AppSettings.quickActionUsageCountsKey) as? [String: Int]) ?? [:]
    }
}

private struct ChatScrollOffsetPreferenceKey: PreferenceKey {
    static let defaultValue: CGFloat = .greatestFiniteMagnitude

    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

private struct ChatVisibleMessageFrame: Equatable {
    let id: UUID
    let minY: CGFloat
    let maxY: CGFloat
}

private struct ChatVisibleMessageFramesPreferenceKey: PreferenceKey {
    static let defaultValue: [ChatVisibleMessageFrame] = []

    static func reduce(value: inout [ChatVisibleMessageFrame], nextValue: () -> [ChatVisibleMessageFrame]) {
        value.append(contentsOf: nextValue())
    }
}

// MARK: - Quick Actions Row (Hybrid Layout)

/// Shows quick action buttons in a single row. Left-side buttons show icon+text labels;
/// once horizontal space runs out, remaining buttons fold to icon-only with tooltips.
private struct QuickActionsRow: View {
    let actions: [QuickAction]
    let isProcessing: Bool
    let onAction: (QuickAction) -> Void

    /// Approximate width of a text-label capsule (icon + text + padding)
    private func estimatedLabelWidth(for action: QuickAction) -> CGFloat {
        // ~7pt per character + 22pt icon + 22pt horizontal padding
        CGFloat(action.label.count) * 7 + 44
    }

    /// Width of an icon-only button
    private let iconOnlyWidth: CGFloat = 30

    /// Horizontal padding + spacing overhead
    private let rowPadding: CGFloat = 28 + 10 // 14px each side + some buffer

    /// Compute how many actions get text labels given available width
    private func textLabelCount(for totalWidth: CGFloat) -> Int {
        var remaining = totalWidth - rowPadding
        var textCount = 0
        for (i, action) in actions.enumerated() {
            let labelW = estimatedLabelWidth(for: action)
            let iconW = iconOnlyWidth + 4 // icon + spacing
            let restAsIcons = CGFloat(actions.count - i - 1) * iconW
            if remaining >= labelW + restAsIcons {
                remaining -= labelW + 5 // 5pt spacing
                textCount += 1
            } else {
                break
            }
        }
        return textCount
    }

    var body: some View {
        GeometryReader { geo in
            let textCount = textLabelCount(for: geo.size.width)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                        let showText = index < textCount
                        Button {
                            onAction(action)
                        } label: {
                            if showText {
                                Label(action.label, systemImage: action.icon)
                                    .font(.caption)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 5)
                                    .background(Color.purple.opacity(0.12))
                                    .foregroundStyle(Color.purple)
                                    .clipShape(Capsule())
                            } else {
                                Image(systemName: action.icon)
                                    .font(.system(size: 11))
                                    .frame(width: 26, height: 26)
                                    .background(Color.purple.opacity(0.12))
                                    .foregroundStyle(Color.purple)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            }
                        }
                        .buttonStyle(.plain)
                        .xrayId("chat.quickAction.\(action.rawValue)")
                        .accessibilityLabel(action.label)
                        .help(action.prompt)
                        .disabled(isProcessing)
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .frame(height: 30)
    }
}

enum ChatComposerSubmitAction: Equatable {
    case sendNewMessage(interruptsCurrentTurn: Bool)
    case answerPendingQuestion(sessionId: String, questionId: String)
}

struct ChatComposerAvailability {
    static func submitAction(
        trimmedText: String,
        hasAttachments: Bool,
        isProcessing: Bool,
        pendingQuestions: [AppState.AgentQuestion],
        hasPendingConfirmations: Bool
    ) -> ChatComposerSubmitAction? {
        let hasText = !trimmedText.isEmpty
        guard hasText || hasAttachments else { return nil }

        if hasText,
           !hasAttachments,
           pendingQuestions.count == 1,
           !hasPendingConfirmations,
           let question = pendingQuestions.first {
            return .answerPendingQuestion(sessionId: question.sessionId, questionId: question.id)
        }

        if isProcessing {
            guard pendingQuestions.isEmpty, !hasPendingConfirmations else { return nil }
            return .sendNewMessage(interruptsCurrentTurn: true)
        }

        return .sendNewMessage(interruptsCurrentTurn: false)
    }
}

enum AutonomousModeLaunchPlan: Equatable {
    case none
    case useCurrentDraft
    case useSavedMission(String)
}

enum ChatExecutionModeSwitchPlanner {
    static func launchPlan(savedMission: String?, draftText: String) -> AutonomousModeLaunchPlan {
        let trimmedMission = savedMission?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmedMission.isEmpty else { return .none }

        let trimmedDraft = draftText.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedDraft == trimmedMission {
            return .useCurrentDraft
        }

        return .useSavedMission(trimmedMission)
    }
}

struct ChatView: View {
    let selectedConversation: Conversation
    @Environment(\.modelContext) private var modelContext
    @Environment(\.appTextScale) private var appTextScale
    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var appState: AppState
    @EnvironmentObject private var sharedRoomService: SharedRoomService
    @Environment(WindowState.self) private var windowState: WindowState
    @AppStorage(AppSettings.useLegacyChatChromeKey, store: AppSettings.store) private var useLegacyChatChrome = false
    @StateObject private var quickActionTracker = QuickActionUsageTracker()
    @State private var inputText = ""
    @State private var inputHeight: CGFloat = PasteableTextField.minHeight
    @State private var isProcessing = false
    @State private var isManagingWaveResponses = false
    @State private var activeWaveTask: Task<Void, Never>?
    @State private var lastTokenTimes: [String: Date] = [:]
    @State private var processingStartTimes: [String: Date] = [:]
    @State private var isEditingTopic = false
    @State private var editedTopic = ""
    @State private var isEditingMission = false
    @State private var editedMission = ""
    @State private var isMissionExpanded = false
    @State private var showClearConfirmation = false
    @State private var pendingAttachments: [(id: UUID, data: Data, mediaType: String, fileName: String)] = []
    @State private var showFileImporter = false
    @State private var previewAttachment: MessageAttachment?
    @State private var previewImageFromPending: (data: Data, mediaType: String)?
    @State private var expandedStreamingThinkingSessionKeys: Set<String> = []
    @State private var activeStreamingSessionKeys: Set<String> = []
    @State private var activeStreamingDisplayNames: [String: String] = [:]
    @State private var lastStreamingTextLengths: [String: Int] = [:]
    @State private var queuedPeerDeliveriesBySession: [UUID: [QueuedPeerDelivery]] = [:]
    @State private var showSlashHelp = false
    @State private var showUnknownSlash = false
    @State private var unknownSlashName = ""
    @State private var showMentionError = false
    @State private var enabledPeerCategories: Set<PeerChannelCategory> = Set(PeerChannelCategory.allCases)
    @State private var mentionErrorDetail = ""
    @State private var showRecoveryError = false
    @State private var recoveryErrorDetail = ""
    @State private var showAutonomousSwitchConfirmation = false
    @State private var showAddAgentsSheet = false
    @State private var showingScheduleEditor = false
    @State private var scheduleDraft = ScheduledMissionDraft()
    /// Retained while the system share sheet is visible so temp export files can be cleaned up.
    @State private var shareCoordinator: ShareTempFileCoordinator?
    @State private var showAllDoneBanner = false
    @State private var allDoneBannerTimer: Task<Void, Never>?
    @State private var isNearBottom = true
    @State private var shouldAutoScroll = true
    @State private var didPerformInitialScrollRestore = false
    @State private var isRestoringScrollPosition = true
    private var planModeEnabled: Bool {
        conversation?.planModeEnabled ?? false
    }
    /// The ID of the last assistant message produced while plan mode was active (for showing the Execute Plan action bar).
    @State private var lastPlanResponseMessageId: UUID?
    @FocusState private var topicFieldFocused: Bool
    @FocusState private var missionFieldFocused: Bool

    @Query private var allAgents: [Agent]
    @Query private var allGroups: [AgentGroup]
    @Query(sort: \Session.startedAt) private var allSessions: [Session]

    private let autoScrollThreshold: CGFloat = 120
    private let bottomScrollAnchor = "chat.bottomAnchor"

    private var conversationId: UUID {
        selectedConversation.id
    }

    private var conversation: Conversation? {
        selectedConversation
    }

    private var captionFont: Font {
        .system(size: 12 * appTextScale)
    }

    private var caption2Font: Font {
        .system(size: 11 * appTextScale)
    }

    private var title3Font: Font {
        .system(size: 20 * appTextScale, weight: .semibold)
    }

    private var interruptedSessions: [Session] {
        conversationSessions.filter { $0.status == .interrupted }
    }

    /// Sessions for this conversation — relationship first, manual query fallback.
    private var conversationSessions: [Session] {
        let relSessions = conversation?.sessions ?? []
        if !relSessions.isEmpty { return relSessions }
        return allSessions.filter { session in
            session.conversations.contains { $0.id == conversationId }
        }
    }

    private var sortedMessages: [ConversationMessage] {
        (conversation?.messages ?? []).sorted { $0.timestamp < $1.timestamp }
    }

    private var displayMessages: [ConversationMessage] {
        let allEnabled = enabledPeerCategories.count == PeerChannelCategory.allCases.count
        if allEnabled { return sortedMessages }
        return sortedMessages.filter { msg in
            guard let category = msg.type.peerChannelCategory else { return true }
            return enabledPeerCategories.contains(category)
        }
    }

    private var hasUserChatMessages: Bool {
        sortedMessages.contains { $0.type == .chat }
    }

    private var primarySession: Session? {
        conversationSessions.min { $0.startedAt < $1.startedAt }
    }

    private var hasRecoverableInterruption: Bool {
        interruptedSessions.contains { $0.claudeSessionId != nil }
    }

    private var currentModel: String? {
        primarySession?.model ?? primarySession?.agent?.model
    }

    private var inspectorWorkspaceRoot: String? {
        if let worktreePath = conversation?.worktreePath,
           WorktreeManager.isUsableWorktree(at: worktreePath) {
            return worktreePath
        }

        let trimmedProjectDirectory = windowState.projectDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmedProjectDirectory.isEmpty ? nil : trimmedProjectDirectory
    }

    private var aggregatedLiveCost: Double {
        guard let convo = conversation else { return 0 }
        var sum = 0.0
        for s in convo.sessions {
            sum += appState.activeSessions[s.id]?.cost ?? s.totalCost
        }
        return sum
    }

    private var liveCost: Double? {
        let c = aggregatedLiveCost
        return c > 0 ? c : nil
    }

    private var streamSessionKeyForUI: String? {
        activeStreamSessionKey ?? primarySession?.id.uuidString
    }

    private var activeStreamSessionKey: String? {
        activeStreamingSessionOrder.first
    }

    private var activeStreamingSessionOrder: [String] {
        guard let convo = conversation else { return activeStreamingSessionKeys.sorted() }
        let orderedConversationKeys = convo.sessions
            .sorted { $0.startedAt < $1.startedAt }
            .map { $0.id.uuidString }
        let orderedActive = orderedConversationKeys.filter { activeStreamingSessionKeys.contains($0) }
        let extraKeys = activeStreamingSessionKeys.subtracting(Set(orderedConversationKeys)).sorted()
        return orderedActive + extraKeys
    }

    private var streamingContentVersion: Int {
        activeStreamingSessionOrder.reduce(0) { partial, key in
            partial
                + (appState.streamingText[key]?.count ?? 0)
                + (appState.thinkingText[key]?.count ?? 0)
        }
    }

    private var mentionAutocompleteAgents: [Agent] {
        guard let r = inputText.range(of: #"@([^@\n]*)$"#, options: .regularExpression) else { return [] }
        let rawToken = String(inputText[r]).dropFirst()
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if rawToken.last?.isWhitespace == true &&
            (allAgents.contains(where: { $0.name.caseInsensitiveCompare(token) == .orderedSame }) ||
             ChatSendRouting.isMentionAllToken(token)) {
            return []
        }
        guard !token.isEmpty else { return Array(allAgents.prefix(8)) }
        return allAgents.filter { $0.name.lowercased().hasPrefix(token) }.prefix(8).map { $0 }
    }

    private var mentionAutocompleteToken: String? {
        guard let r = inputText.range(of: #"@([^@\n]*)$"#, options: .regularExpression) else { return nil }
        let rawToken = String(inputText[r]).dropFirst()
        let token = rawToken.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if rawToken.last?.isWhitespace == true &&
            (allAgents.contains(where: { $0.name.caseInsensitiveCompare(token) == .orderedSame }) ||
             ChatSendRouting.isMentionAllToken(token)) {
            return nil
        }
        return token
    }

    private var shouldShowMentionAllSuggestion: Bool {
        guard let token = mentionAutocompleteToken else { return false }
        return token.isEmpty || ChatSendRouting.mentionAllToken.hasPrefix(token)
    }

    private var sendingToSubtitle: String? {
        guard let convo = conversation, convo.sessions.count > 1,
              let plan = routingPreviewPlan else { return nil }
        let mode = convo.routingMode.displayName
        let recipients = plan.recipientAgentNames.joined(separator: ", ")
        switch plan.deliveryReason {
        case .directMention:
            if convo.routingMode == .mentionAware {
                return "\(mode) — sending to @\(plan.mentionedAgentNames.joined(separator: ", @"))"
            }
            return "\(mode) — sending to everyone, highlighting @\(plan.mentionedAgentNames.joined(separator: ", @"))"
        case .broadcast:
            return "\(mode) — broadcasting to everyone: \(recipients)"
        case .coordinatorLead:
            let coordinator = plan.coordinatorAgentName ?? recipients
            if convo.executionMode != .interactive {
                return "\(mode) — \(convo.executionMode.rawValue.capitalized) mode routes this turn to @\(coordinator) first"
            }
            return "\(mode) — no mention, so @\(coordinator) leads first"
        case .implicitFallback:
            return "\(mode) — no coordinator, so sending to everyone: \(recipients)"
        case .broad:
            return "\(mode) — sending to everyone: \(recipients)"
        }
    }

    private var groupRoutingModeForConversation: GroupRoutingMode {
        conversation?.routingMode ?? .mentionAware
    }

    private var routingPreviewPlan: GroupRoutingPlanner.UserWavePlan? {
        guard let convo = conversation, convo.sessions.count > 1 else { return nil }
        let mentionNames = ChatSendRouting.mentionedAgentNames(in: inputText, agents: allAgents)
        let mentionedAll = ChatSendRouting.containsMentionAll(in: inputText)
        let (resolvedMentionAgents, _) = ChatSendRouting.resolveMentionedAgents(
            names: mentionNames,
            agents: allAgents
        )
        return GroupRoutingPlanner.planUserWave(
            executionMode: convo.executionMode,
            routingMode: convo.routingMode,
            sessions: conversationSessions,
            sourceGroup: sourceGroup(for: convo),
            mentionedAgents: resolvedMentionAgents,
            mentionedAll: mentionedAll
        )
    }

    /// Maps participantId → AgentAppearance for multi-agent conversations. `nil` for single-agent.
    private var participantAppearanceMap: [UUID: AgentAppearance]? {
        guard let convo = conversation, convo.sessions.count > 1 else { return nil }
        var map: [UUID: AgentAppearance] = [:]
        for participant in convo.participants {
            if let sessionId = participant.typeSessionId,
               let session = convo.sessions.first(where: { $0.id == sessionId }),
               let agent = session.agent {
                map[participant.id] = AgentAppearance(
                    color: Color.fromAgentColor(agent.color),
                    icon: agent.icon
                )
            }
        }
        return map.isEmpty ? nil : map
    }

    private func streamingDisplayName(for sidecarKey: String) -> String {
        if let name = activeStreamingDisplayNames[sidecarKey] {
            return name
        }
        guard let convo = conversation,
              let sessionId = UUID(uuidString: sidecarKey),
              let session = convo.sessions.first(where: { $0.id == sessionId }) else {
            return AgentDefaults.displayName(forProvider: nil)
        }
        return session.agent?.name ?? AgentDefaults.displayName(forProvider: session.provider)
    }

    private func streamingAppearance(for sidecarKey: String) -> AgentAppearance? {
        guard let convo = conversation, convo.sessions.count > 1,
              let sessionId = UUID(uuidString: sidecarKey),
              let session = convo.sessions.first(where: { $0.id == sessionId }),
              let agent = session.agent else {
            return nil
        }
        return AgentAppearance(color: Color.fromAgentColor(agent.color), icon: agent.icon)
    }

    private func setGroupRoutingMode(_ mode: GroupRoutingMode) {
        conversation?.routingMode = mode
        try? modelContext.save()
    }

    @ViewBuilder
    private var routingModeMenuItems: some View {
        ForEach(GroupRoutingMode.allCases, id: \.self) { mode in
            Button {
                setGroupRoutingMode(mode)
            } label: {
                Label(
                    mode.displayName,
                    systemImage: groupRoutingModeForConversation == mode ? "checkmark.circle.fill" : "circle"
                )
            }
            .xrayId("chat.groupSettings.routingMode.\(mode.rawValue)")
        }
    }

    private var streamingAppendix: ChatTranscriptStreamingAppendix? {
        guard isProcessing else { return nil }
        let key = streamSessionKeyForUI ?? ""
        let text = appState.streamingText[key] ?? ""
        let thinking = appState.thinkingText[key] ?? ""
        let iconName = conversation?
            .sessions
            .first(where: { $0.id.uuidString == key })?
            .agent?
            .icon
        let colorName = conversation?
            .sessions
            .first(where: { $0.id.uuidString == key })?
            .agent?
            .color
        let app = ChatTranscriptStreamingAppendix(
            text: text,
            thinking: thinking,
            displayName: streamingDisplayName(for: key),
            iconName: iconName,
            colorName: colorName
        )
        return app.isEmpty ? nil : app
    }

    private var canExportChat: Bool {
        !sortedMessages.isEmpty || streamingAppendix != nil
    }

    private var activeChatHeader: some View {
        Group {
            if useLegacyChatChrome {
                legacyChatHeader
            } else {
                simplifiedChatHeader
            }
        }
    }

    private var activeInputArea: some View {
        Group {
            if useLegacyChatChrome {
                legacyInputArea
            } else {
                simplifiedInputArea
            }
        }
    }

    private var currentMissionText: String? {
        let trimmed = primarySession?.mission?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private var supportsExecutionModeToggle: Bool {
        guard let convo = conversation else { return false }
        return convo.executionMode != .worker
    }

    private var isAutonomousModeEnabled: Bool {
        conversation?.executionMode == .autonomous
    }

    private var executionModeButtonLabel: String {
        isAutonomousModeEnabled ? "Autonomous" : "Interactive"
    }

    private var executionModeButtonIcon: String {
        isAutonomousModeEnabled ? "bolt.fill" : "person.fill"
    }

    private var executionModeButtonTint: Color {
        isAutonomousModeEnabled ? .orange : .secondary
    }

    private var canLaunchSavedMissionFromModeSwitch: Bool {
        currentMissionText != nil
    }

    private var pendingAutonomousLaunchPlan: AutonomousModeLaunchPlan {
        ChatExecutionModeSwitchPlanner.launchPlan(
            savedMission: currentMissionText,
            draftText: inputText
        )
    }

    private var shouldShowContextualQuickActions: Bool {
        guard !isProcessing,
              mentionAutocompleteAgents.isEmpty,
              inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              pendingAttachments.isEmpty else {
            return false
        }
        return !hasUserChatMessages || latestNonUserChatMessage != nil
    }

    private var latestNonUserChatMessage: ConversationMessage? {
        sortedMessages.reversed().first { message in
            guard message.type == .chat,
                  let senderId = message.senderParticipantId,
                  let sender = conversation?.participants.first(where: { $0.id == senderId }) else {
                return false
            }
            return sender.type != .user
        }
    }

    private var shouldShowJumpToLatest: Bool {
        !isNearBottom && (!displayMessages.isEmpty || isProcessing)
    }

    private func chatExportSnapshot() -> ChatTranscriptSnapshot? {
        guard let convo = conversation else { return nil }
        let appendix = streamingAppendix
        if sortedMessages.isEmpty, appendix == nil { return nil }
        return ChatTranscriptExport.snapshot(
            conversation: convo,
            messages: sortedMessages,
            participants: convo.participants,
            streamingAppendix: appendix,
            theme: ChatTranscriptExportTheme(
                appearance: colorScheme == .dark ? .dark : .light,
                textScale: Double(appTextScale)
            )
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            activeChatHeader
            Divider()
            messageList
            Divider()
            activeInputArea
        }
        .task {
            try? await Task.sleep(for: .milliseconds(300))
            checkForPendingResponse()
        }
        .onReceive(appState.$lastSessionEvent) { events in
            restoreStreamingStateFromAppState()
            checkForCompletion(events: events)
        }
        .onReceive(appState.$streamingText) { texts in
            for key in activeStreamingSessionKeys {
                let newCount = texts[key]?.count ?? 0
                let previousCount = lastStreamingTextLengths[key] ?? 0
                if newCount > previousCount {
                    lastTokenTimes[key] = Date()
                }
                lastStreamingTextLengths[key] = newCount
            }
            restoreStreamingStateFromAppState()
        }
        .onReceive(appState.$thinkingText) { _ in
            restoreStreamingStateFromAppState()
        }
        .onReceive(appState.$sidecarStatus) { status in
            if status != .connected && isProcessing {
                isProcessing = false
                processingStartTimes.removeAll()
                activeStreamingSessionKeys.removeAll()
                activeStreamingDisplayNames.removeAll()
                queuedPeerDeliveriesBySession.removeAll()
            }
        }
        .onReceive(Timer.publish(every: 5, on: .main, in: .common).autoconnect()) { _ in
            guard isProcessing else { return }
            for key in activeStreamingSessionKeys {
                guard let start = processingStartTimes[key] else { continue }
                let elapsed = Date().timeIntervalSince(start)
                let activity = appState.sessionActivity[key] ?? .idle
                if ChatSessionWatchdog.shouldTriggerNoResponseTimeout(
                    elapsed: elapsed,
                    hasVisibleOutput: hasVisibleOutput(for: key, since: start),
                    activity: activity
                ) {
                    Log.chat.warning("Timeout: no response after \(Int(elapsed))s for \(key, privacy: .public)")
                    appState.lastSessionEvent[key] = .error("No response received (timeout)")
                    processingStartTimes.removeValue(forKey: key)
                }
            }
        }
        .onChange(of: sortedMessages.count) { oldCount, newCount in
            if oldCount == 0, newCount > 0 {
                checkForPendingResponse()
            }
        }
        .onChange(of: windowState.autoSendText) { _, _ in consumeAutoSendText() }
        .onAppear {
            consumeAutoSendText()
            restoreStreamingStateFromAppState()
        }
        .onChange(of: appState.sessionActivity) { _, _ in
            restoreStreamingStateFromAppState()
            if let convo = conversation {
                let summary = appState.conversationActivity(for: convo)
                if case .allDone = summary.aggregate, summary.totalSessions > 0, !showAllDoneBanner {
                    withAnimation(.easeInOut(duration: 0.3)) { showAllDoneBanner = true }
                    allDoneBannerTimer?.cancel()
                    allDoneBannerTimer = Task {
                        try? await Task.sleep(for: .seconds(5))
                        guard !Task.isCancelled else { return }
                        await MainActor.run {
                            withAnimation(.easeInOut(duration: 0.5)) { showAllDoneBanner = false }
                        }
                    }
                }
            }
        }
        .task(id: isProcessing) {
            guard isProcessing else { return }
            while isProcessing {
                try? await Task.sleep(for: .seconds(3))
                guard isProcessing else { return }
                guard !isManagingWaveResponses else { continue }
                let key = streamSessionKeyForUI ?? ""
                let hasText = appState.streamingText[key] != nil
                let stale = lastTokenTimes[key].map { Date().timeIntervalSince($0) > 3 } ?? false
                if hasText && stale {
                    collectResponseIfSingle()
                    return
                }
            }
        }
        .alert("Clear Messages?", isPresented: $showClearConfirmation) {
            Button("Clear All", role: .destructive) { clearMessages() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All messages in this conversation will be deleted. The conversation will remain.")
        }
        .sheet(item: $previewAttachment) { attachment in
            ImagePreviewOverlay(attachment: attachment)
        }
        .sheet(isPresented: Binding(
            get: { previewImageFromPending != nil },
            set: { if !$0 { previewImageFromPending = nil } }
        )) {
            if let pending = previewImageFromPending {
                ImagePreviewOverlay(imageData: pending.data, mediaType: pending.mediaType)
            }
        }
        .fileImporter(
            isPresented: $showFileImporter,
            allowedContentTypes: AttachmentStore.supportedContentTypes,
            allowsMultipleSelection: true
        ) { result in
            handleFileImport(result)
        }
        .sheet(isPresented: $showAddAgentsSheet) {
            AddAgentsToChatSheet(conversationId: conversationId)
                .environmentObject(appState)
                .environment(\.modelContext, modelContext)
        }
        .task(id: conversationId) {
            if let conversation, conversation.isSharedRoom {
                try? await sharedRoomService.refreshConversation(conversation)
            }
        }
        .sheet(isPresented: $showingScheduleEditor) {
            ScheduleEditorView(schedule: nil, draft: scheduleDraft)
                .environmentObject(appState)
                .environment(\.modelContext, modelContext)
        }
        .alert("Commands", isPresented: $showSlashHelp) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("/help — this list\n/topic <name> or /rename <name> — rename conversation\n/agents — add agents to this chat\n@AgentName — add that agent to the group if missing; everyone still receives each message")
        }
        .alert("Unknown command", isPresented: $showUnknownSlash) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Unknown command /\(unknownSlashName). Try /help.")
        }
        .alert("Mention", isPresented: $showMentionError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(mentionErrorDetail)
        }
        .alert("Recovery", isPresented: $showRecoveryError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(recoveryErrorDetail)
        }
        .confirmationDialog(
            "Enable Autonomous Mode?",
            isPresented: $showAutonomousSwitchConfirmation,
            titleVisibility: .visible
        ) {
            Button("Switch mode only") {
                applyExecutionModeChange(.autonomous)
            }
            if canLaunchSavedMissionFromModeSwitch {
                Button("Switch and launch saved goal now") {
                    applyExecutionModeChange(.autonomous, launchSavedMission: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            if canLaunchSavedMissionFromModeSwitch {
                Text("Autonomous mode avoids follow-up questions unless progress is blocked. You can switch modes only, or switch and launch the saved goal.")
            } else {
                Text("Autonomous mode avoids follow-up questions unless progress is blocked. The next turn will run autonomously after you switch.")
            }
        }
    }

    // MARK: - Chat Header

    @ViewBuilder
    private var legacyChatHeader: some View {
        VStack(spacing: 4) {
            HStack(alignment: .center, spacing: 8) {
                agentIconButton

                if isEditingTopic {
                    TextField("Conversation name", text: $editedTopic)
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)
                        .focused($topicFieldFocused)
                        .frame(maxWidth: 300)
                        .onSubmit { commitRename() }
                        .onExitCommand { cancelRename() }
                        .xrayId("chat.topicField")
                } else {
                    Text(conversation?.topic ?? "Chat")
                        .font(.headline)
                        .lineLimit(1)
                        .xrayId("chat.topicTitle")
                }

                Spacer()

                if planModeEnabled {
                    Text("Plan Mode")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.orange, in: Capsule())
                        .xrayId("chat.planModeBadge")
                }

                if let convo = conversation, convo.isSharedRoom {
                    Text(sharedRoomStatusLabel(for: convo))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(sharedRoomStatusColor(for: convo), in: Capsule())
                        .xrayId("chat.sharedRoomStatusBadge")
                }

                executionModeToggleButton

                if conversationSessions.count > 1 {
                    Menu {
                        let allEnabled = enabledPeerCategories.count == PeerChannelCategory.allCases.count
                        Button {
                            if allEnabled {
                                enabledPeerCategories.removeAll()
                            } else {
                                enabledPeerCategories = Set(PeerChannelCategory.allCases)
                            }
                        } label: {
                            Label(allEnabled ? "Hide All" : "Show All",
                                  systemImage: allEnabled ? "eye.slash" : "eye")
                        }
                        Divider()
                        ForEach(PeerChannelCategory.allCases, id: \.self) { category in
                            Button {
                                if enabledPeerCategories.contains(category) {
                                    enabledPeerCategories.remove(category)
                                } else {
                                    enabledPeerCategories.insert(category)
                                }
                            } label: {
                                Label {
                                    Text(category.rawValue)
                                } icon: {
                                    Image(systemName: enabledPeerCategories.contains(category)
                                        ? "checkmark.circle.fill" : "circle")
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: enabledPeerCategories.isEmpty
                                ? "line.3.horizontal.decrease.circle"
                                : "line.3.horizontal.decrease.circle.fill")
                            Text("Comms")
                        }
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(enabledPeerCategories.isEmpty ? AnyShapeStyle(.quaternary) : AnyShapeStyle(.blue.opacity(0.15)))
                        .clipShape(Capsule())
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .xrayId("chat.peerChannelFilter")
                }

                Button {
                    windowState.openInspector(tab: .blackboard)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: windowState.inspectorVisible && windowState.selectedInspectorTab == .blackboard
                            ? "square.grid.2x2.fill"
                            : "square.grid.2x2")
                        Text("Board")
                    }
                    .font(.caption2)
                    .fontWeight(.medium)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(windowState.inspectorVisible && windowState.selectedInspectorTab == .blackboard
                        ? AnyShapeStyle(.teal.opacity(0.15))
                        : AnyShapeStyle(.quaternary))
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("Open blackboard")
                .xrayId("chat.openBlackboardButton")
                .accessibilityLabel("Open blackboard")

                if let model = currentModel {
                    Text(modelShortName(model))
                        .font(.caption2)
                        .fontWeight(.medium)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary)
                        .clipShape(Capsule())
                        .xrayId("chat.modelPill")
                }

                if let cost = liveCost, cost > 0 {
                    Text(String(format: "$%.4f", cost))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .xrayId("chat.liveCostLabel")
                }

                if let convo = conversation {
                    legacyHeaderActions(convo)
                }
            }

            if let mission = primarySession?.mission, !mission.isEmpty {
                HStack {
                    Text(mission)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .xrayId("chat.missionPreview")
                    Spacer()
                }
            }

            if hasRecoverableInterruption {
                recoveryBanner
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private var recoveryBanner: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Interrupted during restart")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text("Context can be restored, but any in-flight work may need to be retried explicitly.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 8) {
                Button("Restore Context") {
                    restoreInterruptedSessions()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .xrayId("chat.recoveryBanner.restoreButton")
                .accessibilityLabel("Restore context")

                Button("Retry Last Turn") {
                    retryLastInterruptedTurn()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(latestUserChatMessage == nil || isProcessing)
                .xrayId("chat.recoveryBanner.retryButton")
                .accessibilityLabel("Retry last turn")

                Button("Continue From Interruption") {
                    continueFromInterruption()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isProcessing)
                .xrayId("chat.recoveryBanner.continueButton")
                .accessibilityLabel("Continue from interruption")

                Spacer()
            }
        }
        .padding(12)
        .background(Color.orange.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.orange.opacity(0.18), lineWidth: 0.8)
        )
        .xrayId("chat.recoveryBanner")
        .accessibilityLabel("Interrupted session recovery options")
    }

    @ViewBuilder
    private var agentIconButton: some View {
        if let convo = conversation, convo.sessions.count > 1 {
            HStack(spacing: -6) {
                ForEach(convo.sessions.prefix(4), id: \.id) { s in
                    if let ag = s.agent {
                        Image(systemName: ag.icon)
                            .foregroundStyle(Color.fromAgentColor(ag.color))
                            .font(.caption)
                            .padding(4)
                            .background(.ultraThinMaterial, in: Circle())
                    }
                }
                if convo.sessions.count > 4 {
                    Text("+\(convo.sessions.count - 4)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .xrayId("chat.groupAgentIcons")
        } else if let agent = primarySession?.agent {
            Button {
                windowState.openLibrary(.build, buildSection: .agents)
            } label: {
                Image(systemName: agent.icon)
                    .foregroundStyle(Color.fromAgentColor(agent.color))
                    .font(.title3)
            }
            .buttonStyle(.plain)
            .help("Open agent: \(agent.name)")
            .xrayId("chat.agentIconButton")
            .accessibilityLabel("Open agent \(agent.name)")
        } else {
            Image(systemName: "bubble.left.and.bubble.right.fill")
                .foregroundStyle(.blue)
                .font(.title3)
                .xrayId("chat.chatIcon")
        }
    }

    @ViewBuilder
    private func legacyHeaderActions(_ convo: Conversation) -> some View {
        HStack(spacing: 6) {
            let sessionKeys = convo.sessions.map(\.id.uuidString)
            let hasLiveActivity = sessionKeys.contains { appState.sessionActivity[$0]?.isActive == true }
            let hasInterruptedSessions = convo.sessions.contains { $0.status == .interrupted }

            if hasLiveActivity {
                Button { pauseSession() } label: {
                    Image(systemName: "stop.fill")
                }
                .help("Stop agent")
                .xrayId("chat.stopButton")
                .accessibilityLabel("Stop agent")
            } else if hasInterruptedSessions {
                Button { restoreInterruptedSessions() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Restore agent context")
                .xrayId("chat.restoreContextButton")
                .accessibilityLabel("Restore agent context")
            }

            Menu {
                if !convo.sessions.isEmpty {
                    Button { forkConversation() } label: {
                        Label("Fork Conversation", systemImage: "arrow.branch")
                    }
                    .xrayId("chat.moreOptions.fork")
                }
                if convo.status == .active {
                    Button { closeConversation(convo) } label: {
                        Label("Close Conversation", systemImage: "xmark.circle")
                    }
                    .xrayId("chat.moreOptions.closeConversation")
                    .accessibilityLabel("Close conversation")
                }
                Divider()
                Button {
                    editedTopic = convo.topic ?? ""
                    isEditingTopic = true
                    topicFieldFocused = true
                } label: {
                    Label("Rename", systemImage: "pencil")
                }
                .xrayId("chat.moreOptions.rename")
                Button {
                    scheduleDraft = makeScheduleDraft(from: latestUserChatMessage)
                    showingScheduleEditor = true
                } label: {
                    Label("Schedule This Mission", systemImage: "clock.badge")
                }
                .xrayId("chat.moreOptions.scheduleMission")
                .accessibilityLabel("Schedule This Mission")
                Button { duplicateConversation(convo) } label: {
                    Label("Duplicate", systemImage: "doc.on.doc")
                }
                .xrayId("chat.moreOptions.duplicate")
                Divider()
                Menu {
                    Button {
                        Task { await exportChatTranscript(kind: .markdown, destination: .save) }
                    } label: {
                        Label("Markdown…", systemImage: "doc.richtext")
                    }
                    .disabled(!canExportChat)
                    .xrayId("chat.export.markdown")
                    Button {
                        Task { await exportChatTranscript(kind: .html, destination: .save) }
                    } label: {
                        Label("HTML…", systemImage: "doc.richtext")
                    }
                    .disabled(!canExportChat)
                    .xrayId("chat.export.html")
                    Button {
                        Task { await exportChatTranscript(kind: .pdf, destination: .save) }
                    } label: {
                        Label("PDF…", systemImage: "doc.fill")
                    }
                    .disabled(!canExportChat)
                    .xrayId("chat.export.pdf")
                } label: {
                    Label("Export", systemImage: "square.and.arrow.down")
                }
                .disabled(!canExportChat)
                .xrayId("chat.exportSubmenu")
                .accessibilityLabel("Export chat")
                Menu {
                    Button {
                        Task { await exportChatTranscript(kind: .markdown, destination: .share) }
                    } label: {
                        Label("Markdown", systemImage: "doc.richtext")
                    }
                    .disabled(!canExportChat)
                    .xrayId("chat.share.markdown")
                    Button {
                        Task { await exportChatTranscript(kind: .html, destination: .share) }
                    } label: {
                        Label("HTML", systemImage: "doc.richtext")
                    }
                    .disabled(!canExportChat)
                    .xrayId("chat.share.html")
                    Button {
                        Task { await exportChatTranscript(kind: .pdf, destination: .share) }
                    } label: {
                        Label("PDF", systemImage: "doc.fill")
                    }
                    .disabled(!canExportChat)
                    .xrayId("chat.share.pdf")
                } label: {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(!canExportChat)
                .xrayId("chat.shareSubmenu")
                .accessibilityLabel("Share chat")
                Divider()
                Toggle(isOn: Binding(
                    get: { AppSettings.store.object(forKey: AppSettings.notificationsEnabledKey) as? Bool ?? true },
                    set: { AppSettings.store.set($0, forKey: AppSettings.notificationsEnabledKey) }
                )) {
                    Label("Notifications", systemImage: "bell")
                }
                .xrayId("chat.moreOptions.notificationsToggle")
                Toggle(isOn: Binding(
                    get: { AppSettings.store.object(forKey: AppSettings.notificationSoundEnabledKey) as? Bool ?? true },
                    set: { AppSettings.store.set($0, forKey: AppSettings.notificationSoundEnabledKey) }
                )) {
                    Label("Sound", systemImage: "speaker.wave.2")
                }
                .xrayId("chat.moreOptions.soundToggle")
                Divider()
                Button { showClearConfirmation = true } label: {
                    Label("Clear Messages", systemImage: "trash")
                }
                .xrayId("chat.moreOptions.clearMessages")
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 20)
            .help("More options")
            .xrayId("chat.moreOptionsMenu")
            .accessibilityLabel("More options")
        }
        .buttonStyle(.borderless)
    }

    @ViewBuilder
    private var simplifiedChatHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 10) {
                agentIconButton

                if isEditingTopic {
                    TextField("Conversation name", text: $editedTopic)
                        .textFieldStyle(.roundedBorder)
                        .font(.headline)
                        .focused($topicFieldFocused)
                        .frame(maxWidth: 320)
                        .onSubmit { commitRename() }
                        .onExitCommand { cancelRename() }
                        .xrayId("chat.topicField")
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(conversation?.topic ?? "Chat")
                            .font(.headline)
                            .lineLimit(1)
                            .xrayId("chat.topicTitle")

                        if let subtitle = sendingToSubtitle {
                            Text(subtitle)
                                .font(caption2Font)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .xrayId("chat.sendingToHint")
                        }
                    }
                }

                Spacer()

                simplifiedHeaderStatusPills

                if let convo = conversation {
                    simplifiedSessionMenu(convo)
                }
            }

            simplifiedMissionSection

            if hasRecoverableInterruption {
                recoveryBanner
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)
    }

    @ViewBuilder
    private var simplifiedHeaderStatusPills: some View {
        HStack(spacing: 6) {
            if planModeEnabled {
                Text("Plan Mode")
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.orange, in: Capsule())
                    .xrayId("chat.planModeBadge")
            }

            if let convo = conversation, convo.isSharedRoom {
                Text(sharedRoomStatusLabel(for: convo))
                    .font(.caption2)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(sharedRoomStatusColor(for: convo), in: Capsule())
                    .xrayId("chat.sharedRoomStatusBadge")
            }

            if let convo = conversation {
                let sessionKeys = convo.sessions.map(\.id.uuidString)
                let hasLiveActivity = sessionKeys.contains { appState.sessionActivity[$0]?.isActive == true }
                let hasInterruptedSessions = convo.sessions.contains { $0.status == .interrupted }

                if hasLiveActivity {
                    Button {
                        pauseSession()
                    } label: {
                        Label("Stop", systemImage: "stop.fill")
                            .font(captionFont.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .xrayId("chat.stopButton")
                    .accessibilityLabel("Stop agent")
                } else if hasInterruptedSessions {
                    Button {
                        restoreInterruptedSessions()
                    } label: {
                        Label("Restore", systemImage: "arrow.clockwise")
                            .font(captionFont.weight(.medium))
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .xrayId("chat.restoreContextButton")
                    .accessibilityLabel("Restore agent context")
                }
            }

            executionModeToggleButton
        }
    }

    @ViewBuilder
    private var simplifiedMissionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            if isEditingMission {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Describe the mission for this thread", text: $editedMission, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .focused($missionFieldFocused)
                        .lineLimit(2...5)
                        .onSubmit { commitMissionEdit() }
                        .xrayId("chat.missionEditor")

                    HStack(spacing: 8) {
                        Button("Save") { commitMissionEdit() }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                            .xrayId("chat.missionSaveButton")

                        Button("Cancel") { cancelMissionEdit() }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .xrayId("chat.missionCancelButton")
                    }
                }
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(.quaternary, lineWidth: 1)
                )
                .xrayId("chat.missionCard")
            } else if let mission = currentMissionText {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .top, spacing: 8) {
                        Label("Mission", systemImage: "scope")
                            .font(captionFont.weight(.semibold))
                            .foregroundStyle(.primary)
                            .xrayId("chat.missionCard.label")

                        Spacer()

                        Button(isMissionExpanded ? "Collapse" : "Expand") {
                            withAnimation(.easeInOut(duration: 0.18)) {
                                isMissionExpanded.toggle()
                            }
                        }
                        .buttonStyle(.borderless)
                        .font(caption2Font)
                        .xrayId("chat.missionToggleButton")

                        Button("Edit") { beginMissionEdit() }
                            .buttonStyle(.borderless)
                            .font(caption2Font)
                            .xrayId("chat.missionEditButton")

                        Button("Schedule") {
                            scheduleDraft = makeScheduleDraft(from: latestUserChatMessage)
                            showingScheduleEditor = true
                        }
                        .buttonStyle(.borderless)
                        .font(caption2Font)
                        .xrayId("chat.missionScheduleButton")
                    }

                    Text(mission)
                        .font(captionFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(isMissionExpanded ? nil : 2)
                        .truncationMode(.tail)
                        .xrayId("chat.missionPreview")
                }
                .padding(12)
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
                )
                .xrayId("chat.missionCard")
            } else {
                HStack(spacing: 10) {
                    Label("No mission yet", systemImage: "scope")
                        .font(captionFont.weight(.medium))
                        .foregroundStyle(.secondary)

                    Spacer()

                    Button("Add mission") { beginMissionEdit() }
                        .buttonStyle(.borderless)
                        .font(caption2Font)
                        .xrayId("chat.missionAddButton")

                    Button("Schedule") {
                        scheduleDraft = makeScheduleDraft(from: latestUserChatMessage)
                        showingScheduleEditor = true
                    }
                    .buttonStyle(.borderless)
                    .font(caption2Font)
                    .xrayId("chat.missionScheduleButton")
                }
                .padding(12)
                .background(Color.secondary.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
                .xrayId("chat.missionCard")
            }
        }
    }

    @ViewBuilder
    private func simplifiedSessionMenu(_ convo: Conversation) -> some View {
        Menu {
            Button {
                windowState.openInspector(tab: .blackboard)
            } label: {
                Label("Open Blackboard", systemImage: "square.grid.2x2")
            }
            .xrayId("chat.sessionMenu.openBlackboard")

            if let model = currentModel {
                Button {} label: {
                    Label("Model: \(modelShortName(model))", systemImage: "cpu")
                }
                .disabled(true)
                .xrayId("chat.sessionMenu.model")
            }

            if let cost = liveCost, cost > 0 {
                Button {} label: {
                    Label(String(format: "Cost: $%.4f", cost), systemImage: "dollarsign.circle")
                }
                .disabled(true)
                .xrayId("chat.sessionMenu.cost")
            }

            if conversationSessions.count > 1 {
                Divider()
                groupSettingsMenuContent
            }

            Divider()

            if !convo.sessions.isEmpty {
                Button { forkConversation() } label: {
                    Label("Fork Conversation", systemImage: "arrow.branch")
                }
                .xrayId("chat.moreOptions.fork")
            }
            if convo.status == .active {
                Button { closeConversation(convo) } label: {
                    Label("Close Conversation", systemImage: "xmark.circle")
                }
                .xrayId("chat.moreOptions.closeConversation")
                .accessibilityLabel("Close conversation")
            }

            Divider()

            Button {
                editedTopic = convo.topic ?? ""
                isEditingTopic = true
                topicFieldFocused = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .xrayId("chat.moreOptions.rename")

            Button {
                beginMissionEdit()
            } label: {
                Label("Edit Mission", systemImage: "scope")
            }
            .xrayId("chat.sessionMenu.editMission")

            Button {
                scheduleDraft = makeScheduleDraft(from: latestUserChatMessage)
                showingScheduleEditor = true
            } label: {
                Label("Schedule This Mission", systemImage: "clock.badge")
            }
            .xrayId("chat.moreOptions.scheduleMission")
            .accessibilityLabel("Schedule This Mission")

            Button { duplicateConversation(convo) } label: {
                Label("Duplicate", systemImage: "doc.on.doc")
            }
            .xrayId("chat.moreOptions.duplicate")

            Divider()

            Menu {
                Button {
                    Task { await exportChatTranscript(kind: .markdown, destination: .save) }
                } label: {
                    Label("Markdown…", systemImage: "doc.richtext")
                }
                .disabled(!canExportChat)
                .xrayId("chat.export.markdown")

                Button {
                    Task { await exportChatTranscript(kind: .html, destination: .save) }
                } label: {
                    Label("HTML…", systemImage: "doc.richtext")
                }
                .disabled(!canExportChat)
                .xrayId("chat.export.html")

                Button {
                    Task { await exportChatTranscript(kind: .pdf, destination: .save) }
                } label: {
                    Label("PDF…", systemImage: "doc.fill")
                }
                .disabled(!canExportChat)
                .xrayId("chat.export.pdf")
            } label: {
                Label("Export", systemImage: "square.and.arrow.down")
            }
            .disabled(!canExportChat)
            .xrayId("chat.exportSubmenu")
            .accessibilityLabel("Export chat")

            Menu {
                Button {
                    Task { await exportChatTranscript(kind: .markdown, destination: .share) }
                } label: {
                    Label("Markdown", systemImage: "doc.richtext")
                }
                .disabled(!canExportChat)
                .xrayId("chat.share.markdown")

                Button {
                    Task { await exportChatTranscript(kind: .html, destination: .share) }
                } label: {
                    Label("HTML", systemImage: "doc.richtext")
                }
                .disabled(!canExportChat)
                .xrayId("chat.share.html")

                Button {
                    Task { await exportChatTranscript(kind: .pdf, destination: .share) }
                } label: {
                    Label("PDF", systemImage: "doc.fill")
                }
                .disabled(!canExportChat)
                .xrayId("chat.share.pdf")
            } label: {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(!canExportChat)
            .xrayId("chat.shareSubmenu")
            .accessibilityLabel("Share chat")

            Divider()

            Toggle(isOn: Binding(
                get: { AppSettings.store.object(forKey: AppSettings.notificationsEnabledKey) as? Bool ?? true },
                set: { AppSettings.store.set($0, forKey: AppSettings.notificationsEnabledKey) }
            )) {
                Label("Notifications", systemImage: "bell")
            }
            .xrayId("chat.moreOptions.notificationsToggle")

            Toggle(isOn: Binding(
                get: { AppSettings.store.object(forKey: AppSettings.notificationSoundEnabledKey) as? Bool ?? true },
                set: { AppSettings.store.set($0, forKey: AppSettings.notificationSoundEnabledKey) }
            )) {
                Label("Sound", systemImage: "speaker.wave.2")
            }
            .xrayId("chat.moreOptions.soundToggle")

            Divider()

            Button { showClearConfirmation = true } label: {
                Label("Clear Messages", systemImage: "trash")
            }
            .xrayId("chat.moreOptions.clearMessages")
        } label: {
            Label("Session", systemImage: "slider.horizontal.3")
                .font(captionFont.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .xrayId("chat.sessionMenu")
        .accessibilityLabel("Session menu")
    }

    @ViewBuilder
    private var executionModeToggleButton: some View {
        if supportsExecutionModeToggle {
            Button {
                handleExecutionModeToggle()
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: executionModeButtonIcon)
                    Text(executionModeButtonLabel)
                }
                .font(.caption2)
                .fontWeight(.medium)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(
                    isAutonomousModeEnabled
                        ? AnyShapeStyle(executionModeButtonTint.opacity(0.18))
                        : AnyShapeStyle(.quaternary)
                )
                .foregroundStyle(
                    isAutonomousModeEnabled
                        ? AnyShapeStyle(executionModeButtonTint)
                        : AnyShapeStyle(.secondary)
                )
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .help(isAutonomousModeEnabled ? "Switch this thread back to interactive mode" : "Switch this thread to autonomous mode")
            .xrayId("chat.executionModeToggle")
            .accessibilityLabel(isAutonomousModeEnabled ? "Switch thread to interactive mode" : "Switch thread to autonomous mode")
        }
    }

    @ViewBuilder
    private var groupSettingsMenuContent: some View {
        Menu {
            routingModeMenuItems

            Divider()

            let allEnabled = enabledPeerCategories.count == PeerChannelCategory.allCases.count
            Button {
                if allEnabled {
                    enabledPeerCategories.removeAll()
                } else {
                    enabledPeerCategories = Set(PeerChannelCategory.allCases)
                }
            } label: {
                Label(allEnabled ? "Hide All Comms" : "Show All Comms",
                      systemImage: allEnabled ? "eye.slash" : "eye")
            }
            .xrayId("chat.groupSettings.toggleAllComms")

            ForEach(PeerChannelCategory.allCases, id: \.self) { category in
                Button {
                    if enabledPeerCategories.contains(category) {
                        enabledPeerCategories.remove(category)
                    } else {
                        enabledPeerCategories.insert(category)
                    }
                } label: {
                    Label(category.rawValue,
                          systemImage: enabledPeerCategories.contains(category)
                            ? "checkmark.circle.fill"
                            : "circle")
                }
            }
        } label: {
            Label("Group Settings", systemImage: "person.3.sequence")
        }
        .fixedSize()
        .xrayId("chat.groupSettingsMenu")
        .accessibilityLabel("Group settings")
    }

    // MARK: - Message List

    @ViewBuilder
    private var messageList: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .bottomTrailing) {
                GeometryReader { scrollGeometry in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            if !hasUserChatMessages && !isProcessing {
                                chatEmptyState
                            }

                            ForEach(displayMessages) { message in
                                MessageBubble(
                                    message: message,
                                    participants: conversation?.participants ?? [],
                                    agentAppearances: participantAppearanceMap,
                                    onTapAttachment: { attachment in
                                        handleAttachmentTap(attachment)
                                    },
                                    onOpenLocalReference: { reference in
                                        openLocalFileReference(reference)
                                    },
                                    onForkFromHere: {
                                        forkFromMessage(message)
                                    },
                                    onScheduleFromMessage: {
                                        scheduleDraft = makeScheduleDraft(from: message)
                                        showingScheduleEditor = true
                                    }
                                )
                                .id(message.id)
                                .background(
                                    GeometryReader { messageGeometry in
                                        let frame = messageGeometry.frame(in: .named("chat.messageScrollView"))
                                        Color.clear.preference(
                                            key: ChatVisibleMessageFramesPreferenceKey.self,
                                            value: [ChatVisibleMessageFrame(
                                                id: message.id,
                                                minY: frame.minY,
                                                maxY: frame.maxY
                                            )]
                                        )
                                    }
                                )

                                if message.id == lastPlanResponseMessageId, !isProcessing {
                                    planActionBar
                                }
                            }

                            if let convo = conversation, convo.sessions.count > 1 {
                                AgentActivityBar(
                                    sessions: convo.sessions,
                                    sessionActivity: appState.sessionActivity,
                                    participants: convo.participants
                                )
                                .id("agentActivityBar")
                            }

                            if isProcessing {
                                streamingBubble
                                    .id("streaming")
                            }

                            ForEach(pendingQuestionsForCurrentConversation) { question in
                                AgentQuestionBubble(
                                    question: question,
                                    agentName: agentNameForQuestion(question),
                                    agentColor: agentColorForQuestion(question)
                                ) { answer, selectedOptions in
                                    appState.answerQuestion(
                                        sessionId: question.sessionId,
                                        questionId: question.id,
                                        answer: answer,
                                        selectedOptions: selectedOptions
                                    )
                                }
                                .id("agentQuestion-\(question.id)")
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            ForEach(pendingConfirmationsForCurrentConversation) { confirmation in
                                AgentConfirmationBubble(
                                    confirmation: confirmation,
                                    agentName: agentNameForConfirmation(confirmation),
                                    agentColor: agentColorForConfirmation(confirmation)
                                ) { approved in
                                    appState.answerConfirmation(
                                        sessionId: confirmation.sessionId,
                                        confirmationId: confirmation.id,
                                        approved: approved
                                    )
                                }
                                .id("agentConfirmation-\(confirmation.id)")
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                            }

                            if showAllDoneBanner {
                                SessionSummaryCard(
                                    sessions: sessionsForSummary,
                                    toolCalls: toolCallsForSummary,
                                    duration: summaryDuration,
                                    workspaceRoot: inspectorWorkspaceRoot,
                                    onOpenFile: { path in
                                        openLocalFileReference(path)
                                    }
                                )
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                                .id("allDoneBanner")
                            }

                            Color.clear
                                .frame(height: 1)
                                .id(bottomScrollAnchor)
                                .background(
                                    GeometryReader { marker in
                                        Color.clear.preference(
                                            key: ChatScrollOffsetPreferenceKey.self,
                                            value: marker.frame(in: .named("chat.messageScrollView")).maxY - scrollGeometry.size.height
                                        )
                                    }
                                )
                        }
                        .padding()
                    }
                    .coordinateSpace(name: "chat.messageScrollView")
                    .xrayId("chat.messageScrollView")
                    .onAppear {
                        performInitialScrollRestoreIfNeeded(proxy)
                    }
                    .onPreferenceChange(ChatScrollOffsetPreferenceKey.self) { distanceFromBottom in
                        let nearBottom = distanceFromBottom <= autoScrollThreshold
                        isNearBottom = nearBottom
                        guard !isRestoringScrollPosition else { return }
                        shouldAutoScroll = nearBottom
                        if nearBottom {
                            windowState.setChatScrollAnchor(nil, for: conversationId)
                        }
                    }
                    .onPreferenceChange(ChatVisibleMessageFramesPreferenceKey.self) { frames in
                        updateStoredScrollAnchor(from: frames, viewportHeight: scrollGeometry.size.height)
                    }
                    .onChange(of: sortedMessages.count) { _, _ in
                        guard shouldAutoScroll else { return }
                        scrollToBottom(proxy, animated: true)
                    }
                    .onChange(of: streamingContentVersion) { _, _ in
                        guard isProcessing, shouldAutoScroll else { return }
                        scrollToBottom(proxy, animated: false)
                    }
                    .onChange(of: isProcessing) { _, processing in
                        if processing {
                            shouldAutoScroll = true
                            windowState.setChatScrollAnchor(nil, for: conversationId)
                            scrollToBottom(proxy, animated: false)
                        }
                    }
                }

                if shouldShowJumpToLatest {
                    Button {
                        jumpToLatest(proxy)
                    } label: {
                        Label("Latest", systemImage: "arrow.down.circle.fill")
                            .font(captionFont.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(.ultraThinMaterial, in: Capsule())
                            .overlay(
                                Capsule()
                                    .strokeBorder(.quaternary, lineWidth: 0.8)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 18)
                    .padding(.bottom, 16)
                    .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
                    .xrayId("chat.jumpToLatestButton")
                    .accessibilityLabel("Jump to latest message")
                    .help("Jump to latest message")
                }
            }
        }
    }

    // MARK: - Input Area

    private var composerSubmitAction: ChatComposerSubmitAction? {
        ChatComposerAvailability.submitAction(
            trimmedText: inputText.trimmingCharacters(in: .whitespacesAndNewlines),
            hasAttachments: !pendingAttachments.isEmpty,
            isProcessing: isProcessing,
            pendingQuestions: pendingQuestionsForCurrentConversation,
            hasPendingConfirmations: !pendingConfirmationsForCurrentConversation.isEmpty
        )
    }

    private var canSend: Bool {
        composerSubmitAction != nil
    }

    @ViewBuilder
    private var legacyInputArea: some View {
        VStack(spacing: 0) {
            if !pendingAttachments.isEmpty {
                pendingAttachmentStrip
            }

            if let sub = sendingToSubtitle {
                Text(sub)
                    .font(caption2Font)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 6)
                    .xrayId("chat.sendingToHint")
            }

            if shouldShowMentionAllSuggestion || !mentionAutocompleteAgents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if shouldShowMentionAllSuggestion {
                            Button {
                                insertMentionCompletion(agentName: ChatSendRouting.mentionAllToken)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("@all")
                                        .font(captionFont)
                                    Text("Broadcast to everyone in chat")
                                        .font(caption2Font)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .xrayId("chat.mentionSuggestion.all")
                        }

                        ForEach(mentionAutocompleteAgents) { agent in
                            Button {
                                insertMentionCompletion(agentName: agent.name)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name)
                                        .font(captionFont)
                                    Text(agentMentionHint(for: agent))
                                        .font(caption2Font)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .xrayId("chat.mentionSuggestion.\(agent.id.uuidString)")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .xrayId("chat.mentionSuggestions")
            }

            if !hasUserChatMessages && !isProcessing && mentionAutocompleteAgents.isEmpty {
                actionChipsStrip
            }

            // Taller text input
            PasteableTextField(
                text: $inputText,
                desiredHeight: $inputHeight,
                onImagePaste: { data, mediaType in
                    guard AttachmentStore.validate(data: data, mediaType: mediaType) else { return }
                    pendingAttachments.append((id: UUID(), data: data, mediaType: mediaType, fileName: "pasted.png"))
                },
                onSubmit: { if canSend { sendMessage() } },
                canSubmitOnReturn: { canSend }
            )
            .frame(height: inputHeight)
            .xrayId("chat.messageInput")
            .accessibilityIdentifier("chat.messageInput")
            .help("Return sends when there is text or attachments. Shift-Return inserts a new line. Sending during an active turn interrupts it. ⌘↩ also sends.")
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Row 1: Quick action capsules (hybrid: left=text labels, right=icon-only)
            QuickActionsRow(
                actions: quickActionTracker.orderedActions,
                isProcessing: isProcessing,
                onAction: { sendQuickAction($0) }
            )
            .xrayId("chat.quickActions")

            // Row 2: Input tools + Send
            HStack(spacing: 6) {
                Button {
                    showAddAgentsSheet = true
                } label: {
                    Label(conversation?.isSharedRoom == true ? "My Agents" : "Add", systemImage: "plus.circle")
                        .font(captionFont)
                }
                .buttonStyle(.borderless)
                .xrayId("chat.addParticipantsButton")
                .accessibilityLabel(conversation?.isSharedRoom == true ? "Add my agents" : "Add agents or groups")
                .help(conversation?.isSharedRoom == true ? "Add your local agents to this shared room" : "Add agents or groups to this thread")
                .disabled(isProcessing)

                Button {
                    windowState.sharedRoomInviteConversationId = conversationId
                    windowState.showSharedRoomInviteSheet = true
                } label: {
                    Label(conversation?.isSharedRoom == true ? "Add People" : "Share Room", systemImage: "person.badge.plus")
                        .font(captionFont)
                }
                .buttonStyle(.borderless)
                .xrayId("chat.shareRoomButton")
                .accessibilityLabel(conversation?.isSharedRoom == true ? "Add people to room" : "Share this conversation as a room")
                .help(conversation?.isSharedRoom == true ? "Invite people to this shared room" : "Convert this conversation into a shared room and invite people")
                .disabled(isProcessing)

                Button {
                    showFileImporter = true
                } label: {
                    Label("Attach", systemImage: "paperclip")
                        .font(captionFont)
                }
                .buttonStyle(.borderless)
                .xrayId("chat.attachButton")
                .accessibilityLabel("Attach file")
                .help("Attach file")
                .disabled(isProcessing)

                Button {
                    conversation?.planModeEnabled.toggle()
                    try? modelContext.save()
                } label: {
                    Label("Plan", systemImage: "doc.text.magnifyingglass")
                        .font(captionFont)
                        .foregroundStyle(planModeEnabled ? .orange : .secondary)
                }
                .buttonStyle(.borderless)
                .xrayId("chat.planModeToggle")
                .accessibilityLabel("Toggle plan mode")
                .help(planModeEnabled ? "Plan mode on — agent will read and plan only" : "Plan mode off — agent can make changes")
                .disabled(isProcessing)

                if conversation?.sessions.count ?? 0 > 1 {
                    Menu {
                        routingModeMenuItems
                    } label: {
                        Label(groupRoutingModeForConversation.shortLabel, systemImage: "arrow.triangle.branch")
                            .font(captionFont)
                            .foregroundStyle(groupRoutingModeForConversation == .mentionAware ? .green : .secondary)
                    }
                    .menuStyle(.borderlessButton)
                    .xrayId("chat.routingModeMenu")
                    .accessibilityLabel("Choose routing mode")
                    .help(
                        groupRoutingModeForConversation == .mentionAware
                        ? "Mention-aware routing: @mentions target specific agents, otherwise the coordinator leads if one exists"
                        : "Broad routing: user turns go to everyone and peer replies may fan out across the group"
                    )
                    .disabled(isProcessing)
                }

                Spacer()

                Button {
                    sendMessage()
                } label: {
                    Text("Send ↵")
                        .font(.system(size: 12 * appTextScale, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .xrayId("chat.sendButton")
                .accessibilityIdentifier("chat.sendButton")
                .accessibilityLabel("Send message")
                .appXrayTapProxy(id: "chat.sendButton") { sendMessage() }
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send message. If agents are still working, this interrupts the current turn and starts a new one. (Return or ⌘Return)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 6)
            .padding(.bottom, 4)
        }
        .background(.bar)
        .onDrop(of: [.image, .fileURL, .plainText, .pdf], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
    }

    @ViewBuilder
    private var simplifiedInputArea: some View {
        VStack(spacing: 0) {
            if !pendingAttachments.isEmpty {
                pendingAttachmentStrip
            }

            if shouldShowMentionAllSuggestion || !mentionAutocompleteAgents.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        if shouldShowMentionAllSuggestion {
                            Button {
                                insertMentionCompletion(agentName: ChatSendRouting.mentionAllToken)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("@all")
                                        .font(captionFont)
                                    Text("Broadcast to everyone in chat")
                                        .font(caption2Font)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .xrayId("chat.mentionSuggestion.all")
                        }

                        ForEach(mentionAutocompleteAgents) { agent in
                            Button {
                                insertMentionCompletion(agentName: agent.name)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(agent.name)
                                        .font(captionFont)
                                    Text(agentMentionHint(for: agent))
                                        .font(caption2Font)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .xrayId("chat.mentionSuggestion.\(agent.id.uuidString)")
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                }
                .xrayId("chat.mentionSuggestions")
            }

            PasteableTextField(
                text: $inputText,
                desiredHeight: $inputHeight,
                onImagePaste: { data, mediaType in
                    guard AttachmentStore.validate(data: data, mediaType: mediaType) else { return }
                    pendingAttachments.append((id: UUID(), data: data, mediaType: mediaType, fileName: "pasted.png"))
                },
                onSubmit: { if canSend { sendMessage() } },
                canSubmitOnReturn: { canSend }
            )
            .frame(height: inputHeight)
            .xrayId("chat.messageInput")
            .help("Return sends when there is text or attachments. Shift-Return inserts a new line. Sending during an active turn interrupts it. ⌘↩ also sends.")
            .padding(.horizontal, 14)
            .padding(.top, 10)
            .padding(.bottom, 6)

            if shouldShowContextualQuickActions {
                QuickActionsRow(
                    actions: quickActionTracker.orderedActions,
                    isProcessing: isProcessing,
                    onAction: { sendQuickAction($0) }
                )
                .xrayId("chat.quickActions")
            }

            HStack(spacing: 8) {
                Menu {
                    Button {
                        showAddAgentsSheet = true
                    } label: {
                        Label(conversation?.isSharedRoom == true ? "Add My Agents" : "Add Agents or Groups",
                              systemImage: "plus.circle")
                    }

                    Button {
                        windowState.sharedRoomInviteConversationId = conversationId
                        windowState.showSharedRoomInviteSheet = true
                    } label: {
                        Label(conversation?.isSharedRoom == true ? "Add People" : "Share Room",
                              systemImage: "person.badge.plus")
                    }

                    Button {
                        showFileImporter = true
                    } label: {
                        Label("Attach File", systemImage: "paperclip")
                    }
                } label: {
                    Label("Tools", systemImage: "plus")
                        .font(captionFont.weight(.medium))
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .disabled(isProcessing)
                .xrayId("chat.toolsMenu")
                .accessibilityLabel("Tools")

                Button {
                    conversation?.planModeEnabled.toggle()
                    try? modelContext.save()
                } label: {
                    Label("Plan", systemImage: "doc.text.magnifyingglass")
                        .font(captionFont.weight(.medium))
                        .foregroundStyle(planModeEnabled ? .orange : .secondary)
                }
                .buttonStyle(.borderless)
                .xrayId("chat.planModeToggle")
                .accessibilityLabel("Toggle plan mode")
                .help(planModeEnabled ? "Plan mode on — agent will read and plan only" : "Plan mode off — agent can make changes")
                .disabled(isProcessing)

                if conversation?.sessions.count ?? 0 > 1 {
                    groupSettingsMenuContent
                        .menuStyle(.borderlessButton)
                        .disabled(isProcessing)
                }

                Spacer()

                Button {
                    sendMessage()
                } label: {
                    Text("Send ↵")
                        .font(.system(size: 12 * appTextScale, weight: .semibold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 5)
                        .background(Color.accentColor)
                        .foregroundStyle(.white)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .xrayId("chat.sendButton")
                .accessibilityIdentifier("chat.sendButton")
                .accessibilityLabel("Send message")
                .appXrayTapProxy(id: "chat.sendButton") { sendMessage() }
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
                .help("Send message. If agents are still working, this interrupts the current turn and starts a new one. (Return or ⌘Return)")
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .padding(.bottom, 4)
        }
        .background(.bar)
        .onDrop(of: [.image, .fileURL, .plainText, .pdf], isTargeted: nil) { providers in
            handleDrop(providers)
            return true
        }
    }

    /// The completed plan for the current session, if the agent called ExitPlanMode.
    private var completedPlan: AppState.CompletedPlan? {
        guard let key = streamSessionKeyForUI else { return nil }
        return appState.completedPlans[key]
    }

    @ViewBuilder
    private var planActionBar: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Show plan text if captured from ExitPlanMode
            if let planText = completedPlan?.plan, !planText.isEmpty {
                DisclosureGroup {
                    ScrollView {
                        Text(LocalizedStringKey(planText))
                            .font(captionFont)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 200)
                } label: {
                    Label("Plan", systemImage: "doc.text")
                        .font(captionFont)
                        .fontWeight(.medium)
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .xrayId("chat.planCard")
            }

            // Show allowed prompts as pills
            if let prompts = completedPlan?.allowedPrompts, !prompts.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        Text("Needs:")
                            .font(caption2Font)
                            .foregroundStyle(.secondary)
                        ForEach(prompts) { prompt in
                            Text(prompt.prompt)
                                .font(caption2Font)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(.orange.opacity(0.15))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 12)
                .xrayId("chat.planCard.allowedPrompts")
            }

            // Action buttons
            HStack(spacing: 12) {
                Button {
                    executePlan()
                } label: {
                    Label("Execute Plan", systemImage: "play.fill")
                        .font(captionFont)
                        .fontWeight(.medium)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .xrayId("chat.executePlanButton")

                Button {
                    // Keep plan mode on, just clear the action bar so user can type a follow-up
                    lastPlanResponseMessageId = nil
                } label: {
                    Label("Refine Plan", systemImage: "pencil")
                        .font(captionFont)
                }
                .buttonStyle(.bordered)
                .xrayId("chat.refinePlanButton")

                Button {
                    discardPlan()
                } label: {
                    Label("Discard", systemImage: "trash")
                        .font(captionFont)
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.secondary)
                .xrayId("chat.discardPlanButton")
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var pendingAttachmentStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(pendingAttachments.enumerated()), id: \.element.id) { index, item in
                    ZStack(alignment: .topTrailing) {
                        if item.mediaType.hasPrefix("image/"), let nsImage = NSImage(data: item.data) {
                            Image(nsImage: nsImage)
                                .resizable()
                                .aspectRatio(contentMode: .fill)
                                .frame(width: 60, height: 60)
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                                .onTapGesture {
                                    previewImageFromPending = (data: item.data, mediaType: item.mediaType)
                                }
                                .xrayId("chat.pendingAttachment.\(index)")
                        } else {
                            VStack(spacing: 2) {
                                Image(systemName: iconForMediaType(item.mediaType))
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text(item.fileName)
                                    .font(.caption2)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .frame(maxWidth: 56)
                            }
                            .frame(width: 60, height: 60)
                            .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary))
                            .xrayId("chat.pendingAttachment.\(index)")
                        }

                        Button {
                            pendingAttachments.removeAll { $0.id == item.id }
                        } label: {
                                Image(systemName: "xmark.circle.fill")
                                .font(captionFont)
                                .foregroundStyle(.white)
                                .background(Circle().fill(.black.opacity(0.6)))
                        }
                        .buttonStyle(.borderless)
                        .offset(x: 4, y: -4)
                        .xrayId("chat.pendingAttachment.remove.\(index)")
                        .accessibilityLabel("Remove attachment")
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .xrayId("chat.pendingAttachments")
    }


    private func iconForMediaType(_ mediaType: String) -> String {
        switch mediaType {
        case "text/plain", "text/markdown": return "doc.text"
        case "application/pdf": return "doc.richtext"
        default: return mediaType.hasPrefix("image/") ? "photo" : "doc"
        }
    }

    // MARK: - Chat Empty State

    private var sourceGroup: AgentGroup? {
        guard let gid = conversation?.sourceGroupId else { return nil }
        return allGroups.first { $0.id == gid }
    }

    private var emptyStateSuggestions: AgentSuggestions.SuggestionSet {
        if let group = sourceGroup {
            return AgentSuggestions.groupSuggestions(for: group)
        }
        if let agent = primarySession?.agent {
            return AgentSuggestions.suggestions(for: agent)
        }
        return AgentSuggestions.freeformSuggestions
    }

    @ViewBuilder
    private var chatEmptyState: some View {
        VStack(spacing: 16) {
            if let group = sourceGroup {
                groupEmptyStateHeader(group)
            } else if let agent = primarySession?.agent {
                VStack(spacing: 8) {
                    Image(systemName: agent.icon)
                        .font(.system(size: 36))
                        .foregroundStyle(Color.fromAgentColor(agent.color))
                        .frame(width: 64, height: 64)
                        .background(Color.fromAgentColor(agent.color).opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16))

                    Text(agent.name)
                        .font(title3Font)
                        .fontWeight(.semibold)

                    if !agent.agentDescription.isEmpty {
                        Text(agent.agentDescription)
                            .font(captionFont)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .frame(maxWidth: 400)
                    }
                }
                .xrayId("chat.emptyState.agentInfo")
            } else {
                VStack(spacing: 8) {
                    Image(systemName: "bubble.left.and.bubble.right.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.blue)
                        .frame(width: 64, height: 64)
                        .background(Color.blue.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 16))
                    Text("Quick Chat")
                        .font(title3Font)
                        .fontWeight(.semibold)
                    Text("Ask anything \u{2014} no agent profile attached.")
                        .font(captionFont)
                        .foregroundStyle(.secondary)
                }
                .xrayId("chat.emptyState.freeformInfo")
            }

            let suggestions = emptyStateSuggestions

            VStack(spacing: 8) {
                Text("Try asking")
                    .font(captionFont)
                    .fontWeight(.medium)
                    .foregroundStyle(.tertiary)

                VStack(spacing: 6) {
                    ForEach(Array(suggestions.starters.prefix(4).enumerated()), id: \.offset) { index, prompt in
                        Button {
                            inputText = prompt
                        } label: {
                            HStack {
                                Text(prompt)
                                    .font(.callout)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(captionFont)
                                    .foregroundStyle(.tertiary)
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 10)
                            .background(.background)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .overlay(RoundedRectangle(cornerRadius: 10).stroke(.quaternary, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .xrayId("chat.emptyState.starter.\(index)")
                    }
                }
                .frame(maxWidth: 440)
            }
            .xrayId("chat.emptyState.suggestions")
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .padding(.bottom, 20)
        .xrayId("chat.emptyState")
    }

    @ViewBuilder
    private func groupEmptyStateHeader(_ group: AgentGroup) -> some View {
        VStack(spacing: 8) {
            Text(group.icon)
                .font(.system(size: 40))
                .frame(width: 64, height: 64)
                .background(Color.fromAgentColor(group.color).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 16))

            Text(group.name)
                .font(title3Font)
                .fontWeight(.semibold)

            if !group.groupDescription.isEmpty {
                Text(group.groupDescription)
                    .font(captionFont)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .frame(maxWidth: 400)
            }

            let agentNames = group.agentIds.compactMap { agentId in
                allAgents.first { $0.id == agentId }?.name
            }
            if !agentNames.isEmpty {
                HStack(spacing: 4) {
                    Image(systemName: "person.3")
                        .font(caption2Font)
                        .foregroundStyle(.tertiary)
                    Text(agentNames.joined(separator: ", "))
                        .font(caption2Font)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
            }
        }
        .xrayId("chat.emptyState.groupInfo")
    }

    // MARK: - Action Chips

    @ViewBuilder
    private var actionChipsStrip: some View {
        let suggestions = emptyStateSuggestions

        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(suggestions.chips, id: \.self) { chip in
                    Button {
                        inputText = chip
                    } label: {
                        Text(chip)
                            .font(captionFont)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.accentColor.opacity(0.1))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .xrayId("chat.actionChip.\(chip.lowercased().replacingOccurrences(of: " ", with: "-"))")
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
        }
        .xrayId("chat.actionChips")
    }

    // MARK: - Image Input Handlers

    private func handleDrop(_ providers: [NSItemProvider]) {
        for provider in providers {
            if provider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                loadImageFromProvider(provider)
            } else if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier) { data, _ in
                    guard let urlData = data as? Data,
                          let url = URL(dataRepresentation: urlData, relativeTo: nil) else { return }
                    let ext = url.pathExtension.lowercased()
                    guard AttachmentStore.supportedExtensions.contains(ext) else { return }
                    guard let fileData = try? Data(contentsOf: url) else { return }
                    let mediaType = AttachmentStore.mediaTypeForURL(url)
                    guard AttachmentStore.validate(data: fileData, mediaType: mediaType) else { return }
                    DispatchQueue.main.async {
                        pendingAttachments.append((id: UUID(), data: fileData, mediaType: mediaType, fileName: url.lastPathComponent))
                    }
                }
            }
        }
    }

    private func loadImageFromProvider(_ provider: NSItemProvider) {
        let imageTypes: [UTType] = [.png, .jpeg, .tiff, .gif]
        for type in imageTypes {
            if provider.hasItemConformingToTypeIdentifier(type.identifier) {
                provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, _ in
                    guard let data, AttachmentStore.validate(data: data, mediaType: "image/png") else { return }
                    let resolved: (Data, String)
                    if type == .tiff {
                        guard let nsImage = NSImage(data: data),
                              let converted = AttachmentStore.mediaTypeFromNSImage(nsImage) else { return }
                        resolved = converted
                    } else {
                        resolved = (data, AttachmentStore.mediaTypeFromData(data))
                    }
                    DispatchQueue.main.async {
                        pendingAttachments.append((id: UUID(), data: resolved.0, mediaType: resolved.1, fileName: "pasted.png"))
                    }
                }
                return
            }
        }
    }

    private func handleFileImport(_ result: Result<[URL], Error>) {
        guard case .success(let urls) = result else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }
            guard let data = try? Data(contentsOf: url) else { continue }
            let mediaType = AttachmentStore.mediaTypeForURL(url)
            guard AttachmentStore.validate(data: data, mediaType: mediaType) else { continue }
            pendingAttachments.append((id: UUID(), data: data, mediaType: mediaType, fileName: url.lastPathComponent))
        }
    }

    // MARK: - Streaming Bubble

    @ViewBuilder
    private var streamingBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(activeStreamingSessionOrder, id: \.self) { sidecarKey in
                streamingBubble(for: sidecarKey)
                    .id("streaming-\(sidecarKey)")
            }
        }
        .xrayId("chat.streamingBubble")
    }

    @ViewBuilder
    private func streamingBubble(for sidecarKey: String) -> some View {
        let appearance = streamingAppearance(for: sidecarKey)
        let thinking = appState.thinkingText[sidecarKey]
        let text = appState.streamingText[sidecarKey]

        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: appearance?.icon ?? "cpu")
                        .font(caption2Font)
                        .foregroundStyle(appearance?.color ?? .purple)
                    Text(streamingDisplayName(for: sidecarKey))
                        .font(captionFont)
                        .foregroundStyle(appearance?.color ?? .secondary)
                    if let state = appState.sessionActivity[sidecarKey] {
                        Text(state.displayLabel)
                            .font(caption2Font)
                            .foregroundStyle(state.displayColor.opacity(0.8))
                    }
                }

                if let thinking, !thinking.isEmpty {
                    streamingThinkingSection(thinking, sidecarKey: sidecarKey)
                }

                if let text, !text.isEmpty {
                    MarkdownContent(text: text, onOpenLocalReference: openLocalFileReference)
                } else if thinking?.isEmpty != false {
                    StreamingIndicator()
                }
            }
            .padding(.horizontal, appearance != nil ? 10 : 0)
            .padding(.vertical, appearance != nil ? 6 : 0)
            .background(appearance.map { $0.color.opacity(0.08) } ?? Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: appearance != nil ? 12 : 0))

            Spacer(minLength: 60)
        }
    }

    @ViewBuilder
    private func streamingThinkingSection(_ thinking: String, sidecarKey: String) -> some View {
        let isExpanded = expandedStreamingThinkingSessionKeys.contains(sidecarKey)
        VStack(alignment: .leading, spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isExpanded {
                        expandedStreamingThinkingSessionKeys.remove(sidecarKey)
                    } else {
                        expandedStreamingThinkingSessionKeys.insert(sidecarKey)
                    }
                }
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "brain")
                        .font(caption2Font)
                        .foregroundStyle(.indigo)
                    Text("Thinking...")
                        .font(captionFont)
                        .fontWeight(.medium)
                        .foregroundStyle(.indigo)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .font(caption2Font)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
            }
            .buttonStyle(.plain)
            .xrayId("chat.streamingThinkingToggle.\(sidecarKey)")
            .accessibilityLabel(isExpanded ? "Collapse thinking" : "Expand thinking")

            if isExpanded {
                Divider()
                ScrollView {
                    Text(thinking)
                        .font(captionFont)
                        .foregroundStyle(.secondary)
                        .italic()
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                }
                .frame(maxHeight: 200)
            }
        }
        .background(.indigo.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(.indigo.opacity(0.15), lineWidth: 0.5)
        )
    }

    // MARK: - Session Summary Helpers

    private var sessionsForSummary: [AppState.SessionInfo] {
        guard let convo = conversation else { return [] }
        return convo.sessions.compactMap { session in
            appState.activeSessions[session.id]
        }
    }

    private var toolCallsForSummary: [String: [AppState.ToolCallInfo]] {
        guard let convo = conversation else { return [:] }
        var result: [String: [AppState.ToolCallInfo]] = [:]
        for session in convo.sessions {
            let key = session.id.uuidString
            if let calls = appState.toolCalls[key] {
                result[key] = calls
            }
        }
        return result
    }

    private var summaryDuration: TimeInterval? {
        guard let start = processingStartTimes.values.min() else { return nil }
        return Date().timeIntervalSince(start)
    }

    // MARK: - Agent Question Helpers

    private var pendingQuestionsForCurrentConversation: [AppState.AgentQuestion] {
        guard let convo = conversation else { return [] }
        return convo.sessions.compactMap { session in
            appState.pendingQuestions[session.id.uuidString]
        }
    }

    private func agentNameForQuestion(_ question: AppState.AgentQuestion) -> String {
        guard let convo = conversation else { return "Agent" }
        if let session = convo.sessions.first(where: { $0.id.uuidString == question.sessionId }) {
            return session.agent?.name ?? "Agent"
        }
        return "Agent"
    }

    private func agentColorForQuestion(_ question: AppState.AgentQuestion) -> Color? {
        guard let convo = conversation, convo.sessions.count > 1,
              let session = convo.sessions.first(where: { $0.id.uuidString == question.sessionId }),
              let agent = session.agent else { return nil }
        return Color.fromAgentColor(agent.color)
    }

    private var pendingConfirmationsForCurrentConversation: [AppState.AgentConfirmation] {
        guard let convo = conversation else { return [] }
        return convo.sessions.compactMap { session in
            appState.pendingConfirmations[session.id.uuidString]
        }
    }

    private func agentNameForConfirmation(_ confirmation: AppState.AgentConfirmation) -> String {
        guard let convo = conversation else { return "Agent" }
        if let session = convo.sessions.first(where: { $0.id.uuidString == confirmation.sessionId }) {
            return session.agent?.name ?? "Agent"
        }
        return "Agent"
    }

    private func agentColorForConfirmation(_ confirmation: AppState.AgentConfirmation) -> Color? {
        guard let convo = conversation, convo.sessions.count > 1,
              let session = convo.sessions.first(where: { $0.id.uuidString == confirmation.sessionId }),
              let agent = session.agent else { return nil }
        return Color.fromAgentColor(agent.color)
    }

    // MARK: - Helpers

    private func scrollToBottom(_ proxy: ScrollViewProxy, animated: Bool) {
        let scrollAction = {
            proxy.scrollTo(bottomScrollAnchor, anchor: .bottom)
        }

        if animated {
            withAnimation {
                scrollAction()
            }
        } else {
            var transaction = Transaction()
            transaction.animation = nil
            withTransaction(transaction) {
                scrollAction()
            }
        }
    }

    private func performInitialScrollRestoreIfNeeded(_ proxy: ScrollViewProxy) {
        guard !didPerformInitialScrollRestore else { return }
        didPerformInitialScrollRestore = true
        isRestoringScrollPosition = true

        let savedAnchorId = windowState.chatScrollAnchor(for: conversationId)
        let restoredAnchorId = savedAnchorId.flatMap { anchorId in
            displayMessages.contains(where: { $0.id == anchorId }) ? anchorId : nil
        }

        if savedAnchorId != nil, restoredAnchorId == nil {
            windowState.setChatScrollAnchor(nil, for: conversationId)
        }

        shouldAutoScroll = restoredAnchorId == nil

        Task { @MainActor in
            await Task.yield()
            if let restoredAnchorId {
                var transaction = Transaction()
                transaction.animation = nil
                withTransaction(transaction) {
                    proxy.scrollTo(restoredAnchorId, anchor: .top)
                }
            } else {
                scrollToBottom(proxy, animated: false)
            }
            await Task.yield()
            isRestoringScrollPosition = false
        }
    }

    private func updateStoredScrollAnchor(from frames: [ChatVisibleMessageFrame], viewportHeight: CGFloat) {
        guard !isRestoringScrollPosition else { return }
        guard !isNearBottom else {
            windowState.setChatScrollAnchor(nil, for: conversationId)
            return
        }

        let visibleFrames = frames
            .filter { $0.maxY > 0 && $0.minY < viewportHeight }
            .sorted { lhs, rhs in
                if lhs.minY == rhs.minY {
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                return lhs.minY < rhs.minY
            }

        guard let topVisibleMessageId = visibleFrames.first?.id else { return }
        windowState.setChatScrollAnchor(topVisibleMessageId, for: conversationId)
    }

    private func jumpToLatest(_ proxy: ScrollViewProxy) {
        shouldAutoScroll = true
        isNearBottom = true
        windowState.setChatScrollAnchor(nil, for: conversationId)
        scrollToBottom(proxy, animated: true)
    }

    private var participantSummary: String {
        guard let convo = conversation else { return "" }
        let names = convo.participants.map(\.displayName)
        return names.joined(separator: " + ")
    }

    private func modelShortName(_ model: String) -> String {
        AgentDefaults.label(for: model)
    }

    private func commitRename() {
        let name = editedTopic.trimmingCharacters(in: .whitespacesAndNewlines)
        if !name.isEmpty, let convo = conversation {
            convo.topic = name
            try? modelContext.save()
        }
        isEditingTopic = false
    }

    private func cancelRename() {
        isEditingTopic = false
    }

    private func beginMissionEdit() {
        editedMission = currentMissionText ?? ""
        isEditingMission = true
        isMissionExpanded = true
        Task { @MainActor in
            missionFieldFocused = true
        }
    }

    private func commitMissionEdit() {
        let mission = editedMission.trimmingCharacters(in: .whitespacesAndNewlines)
        for session in conversationSessions {
            session.mission = mission.isEmpty ? nil : mission
        }
        try? modelContext.save()
        isEditingMission = false
    }

    private func cancelMissionEdit() {
        editedMission = currentMissionText ?? ""
        isEditingMission = false
    }

    // MARK: - Auto Naming

    private func autoNameConversation(_ convo: Conversation, firstMessage: String) {
        guard convo.topic == "New Chat" || convo.topic == nil else { return }

        let trimmed = firstMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        let truncated: String
        if trimmed.count <= 50 {
            truncated = trimmed
        } else {
            let cutoff = trimmed.index(trimmed.startIndex, offsetBy: 50)
            let substring = trimmed[..<cutoff]
            if let lastSpace = substring.lastIndex(of: " ") {
                truncated = String(substring[..<lastSpace]) + "..."
            } else {
                truncated = String(substring) + "..."
            }
        }

        let agentName = convo.primarySession?.agent?.name
        convo.topic = agentName.map { "\($0): \(truncated)" } ?? truncated
    }

    private func agentMentionHint(for agent: Agent) -> String {
        conversation?.sessions.contains(where: { $0.agent?.id == agent.id }) == true ? "In chat" : "Adds on send"
    }

    private func insertMentionCompletion(agentName: String) {
        guard let r = inputText.range(of: #"@([^@\n]*)$"#, options: .regularExpression) else { return }
        inputText.replaceSubrange(r, with: "@\(agentName) ")
    }

    /// Freeform / quick chat: ensure one `Session` + Claude participant exist before first model call.
    private func ensureFreeformSidecarSession(in convo: Conversation) -> Session? {
        if let existing = convo.primarySession, convo.sessions.count == 1, existing.agent == nil {
            syncFreeformParticipantDisplayName(for: existing, in: convo)
            return existing
        }
        if let s = convo.primarySession, s.agent != nil { return s }
        let session = Session(
            agent: nil,
            mission: currentMissionText,
            mode: .interactive,
            workingDirectory: windowState.projectDirectory.isEmpty ? NSHomeDirectory() : windowState.projectDirectory
        )
        session.conversations = [convo]
        convo.sessions.append(session)
        let agentParticipant = Participant(
            type: .agentSession(sessionId: session.id),
            displayName: AgentDefaults.displayName(forProvider: session.provider)
        )
        agentParticipant.conversation = convo
        convo.participants.append(agentParticipant)
        modelContext.insert(session)
        modelContext.insert(agentParticipant)
        try? modelContext.save()
        return session
    }

    private func syncFreeformParticipantDisplayName(for session: Session, in convo: Conversation) {
        guard session.agent == nil,
              let participant = participantForSession(session, in: convo) else { return }
        let expectedName = AgentDefaults.displayName(forProvider: session.provider)
        guard participant.displayName != expectedName else { return }
        participant.displayName = expectedName
        try? modelContext.save()
    }

    private func participantForSession(_ session: Session, in convo: Conversation) -> Participant? {
        convo.participants.first {
            if case .agentSession(let sid) = $0.type { return sid == session.id }
            return false
        }
    }

    // MARK: - Quick Actions

    private func sendQuickAction(_ action: QuickAction) {
        quickActionTracker.recordUsage(action)
        inputText = action.prompt
        sendMessage()
    }

    // MARK: - Plan Mode Actions

    private func executePlan() {
        conversation?.planModeEnabled = false
        try? modelContext.save()
        lastPlanResponseMessageId = nil
        if let key = streamSessionKeyForUI {
            appState.completedPlans.removeValue(forKey: key)
        }
        inputText = "Execute the plan above. Proceed with implementation."
        sendMessage()
    }

    private func discardPlan() {
        conversation?.planModeEnabled = false
        try? modelContext.save()
        lastPlanResponseMessageId = nil
        if let key = streamSessionKeyForUI {
            appState.completedPlans.removeValue(forKey: key)
        }
    }

    // MARK: - Auto-Send from Launch Intent

    private func consumeAutoSendText() {
        guard let text = windowState.autoSendText else { return }
        windowState.autoSendText = nil
        inputText = text
        Task { @MainActor in
            for _ in 0..<30 {
                if appState.sidecarStatus == .connected && !isProcessing { break }
                try? await Task.sleep(for: .milliseconds(500))
            }
            if appState.sidecarStatus == .connected && !isProcessing {
                sendMessage()
            }
        }
    }

    private func handleExecutionModeToggle() {
        guard let convo = conversation else { return }

        switch convo.executionMode {
        case .interactive:
            showAutonomousSwitchConfirmation = true
        case .autonomous:
            applyExecutionModeChange(.interactive)
        case .worker:
            break
        }
    }

    private func applyExecutionModeChange(
        _ executionMode: ConversationExecutionMode,
        launchSavedMission: Bool = false
    ) {
        guard let convo = conversation else { return }

        Task { @MainActor in
            await appState.updateExecutionMode(executionMode, for: convo)
            guard launchSavedMission else { return }
            queueAutonomousMissionLaunch()
        }
    }

    private func queueAutonomousMissionLaunch() {
        switch pendingAutonomousLaunchPlan {
        case .none:
            return
        case .useCurrentDraft:
            let trimmedDraft = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedDraft.isEmpty else { return }
            windowState.autoSendText = trimmedDraft
        case .useSavedMission(let mission):
            windowState.autoSendText = mission
        }
        consumeAutoSendText()
    }

    private var latestUserChatMessage: ConversationMessage? {
        sortedMessages.reversed().first { message in
            guard message.type == .chat, let senderId = message.senderParticipantId else { return false }
            return conversation?.participants.first(where: { $0.id == senderId })?.type == .user
        }
    }

    private func makeScheduleDraft(from message: ConversationMessage?) -> ScheduledMissionDraft {
        let prompt = (
            message?.text
                ?? primarySession?.mission
                ?? inputText
        ).trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedPrompt = prompt.isEmpty
            ? "Check the current repository and continue this recurring mission."
            : prompt

        if let groupId = conversation?.sourceGroupId {
            var draft = ScheduledMissionDraft(
                name: (conversation?.topic ?? "Group mission") + " schedule",
                targetKind: .group,
                projectDirectory: windowState.projectDirectory,
                promptTemplate: resolvedPrompt
            )
            draft.targetGroupId = groupId
            draft.targetConversationId = conversation?.id
            draft.sourceConversationId = conversation?.id
            draft.sourceMessageId = message?.id
            draft.usesAutonomousMode = conversation?.isAutonomous ?? false
            return draft
        }

        if let agentId = primarySession?.agent?.id, conversationSessions.count == 1 {
            var draft = ScheduledMissionDraft(
                name: (conversation?.topic ?? primarySession?.agent?.name ?? "Agent mission") + " schedule",
                targetKind: .agent,
                projectDirectory: windowState.projectDirectory,
                promptTemplate: resolvedPrompt
            )
            draft.targetAgentId = agentId
            draft.targetConversationId = conversation?.id
            draft.sourceConversationId = conversation?.id
            draft.sourceMessageId = message?.id
            return draft
        }

        var draft = ScheduledMissionDraft(
            name: (conversation?.topic ?? "Conversation mission") + " schedule",
            targetKind: .conversation,
            projectDirectory: windowState.projectDirectory,
            promptTemplate: resolvedPrompt
        )
        draft.runMode = ScheduledMissionRunMode.reuseConversation
        draft.targetConversationId = conversation?.id
        draft.sourceConversationId = conversation?.id
        draft.sourceMessageId = message?.id
        return draft
    }

    // MARK: - Send Message

    private func sendMessage() {
        let rawInput = inputText
        let text = rawInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let attachments = pendingAttachments
        guard let submitAction = composerSubmitAction,
              let convo = conversation else {
            return
        }

        if case .answerPendingQuestion(let sessionId, let questionId) = submitAction {
            inputText = ""
            pendingAttachments = []
            appState.answerQuestion(
                sessionId: sessionId,
                questionId: questionId,
                answer: text
            )
            return
        }

        guard !text.isEmpty || !attachments.isEmpty else { return }

        if text.first == "/", !text.hasPrefix("//"), let slash = ChatSendRouting.parseSlashCommand(rawInput) {
            switch slash {
            case .help:
                showSlashHelp = true
            case .topic(let title):
                let t = title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !t.isEmpty {
                    convo.topic = t
                    try? modelContext.save()
                }
            case .agents:
                showAddAgentsSheet = true
            case .unknown(let name):
                unknownSlashName = name
                showUnknownSlash = true
            }
            if case .topic = slash, text.split(separator: " ").count <= 1, slash != .help {
                // /topic with no title — still consume input? skip clear
            }
            inputText = ""
            pendingAttachments = []
            return
        }

        if case .sendNewMessage(let interruptsCurrentTurn) = submitAction, interruptsCurrentTurn {
            interruptActiveWaveForNewTurn()
        }

        inputText = ""
        pendingAttachments = []

        let mentionNames = ChatSendRouting.mentionedAgentNames(in: text, agents: allAgents)
        let mentionedAll = ChatSendRouting.containsMentionAll(in: text)
        let (resolvedMentionAgents, unknownMentions) = ChatSendRouting.resolveMentionedAgents(
            names: mentionNames,
            agents: allAgents
        )
        if !unknownMentions.isEmpty {
            mentionErrorDetail = "Unknown agent(s): \(unknownMentions.joined(separator: ", "))"
            showMentionError = true
            return
        }

        for ag in resolvedMentionAgents {
            if convo.sessions.contains(where: { $0.agent?.id == ag.id }) { continue }
            let primaryWd = (convo.primarySession?.workingDirectory ?? "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let wd = !primaryWd.isEmpty ? primaryWd : ""
            let session = Session(
                agent: ag,
                mission: convo.primarySession?.mission,
                mode: convo.primarySession?.mode ?? .interactive,
                workingDirectory: wd
            )
            session.conversations = [convo]
            convo.sessions.append(session)
            let p = Participant(type: .agentSession(sessionId: session.id), displayName: ag.name)
            p.conversation = convo
            convo.participants.append(p)
            modelContext.insert(session)
            modelContext.insert(p)
        }
        // Ensure all sessions have a working directory.
        // Resident agents (defaultWorkingDirectory set) run in their own home folder;
        // everyone else falls back to the project root.
        for session in convo.sessions where session.workingDirectory.isEmpty {
            if let dir = session.agent?.defaultWorkingDirectory, !dir.isEmpty {
                session.workingDirectory = dir
            } else {
                session.workingDirectory = windowState.projectDirectory
            }
        }
        try? modelContext.save()

        var targetSessions: [Session] = conversationSessions.sorted(by: { $0.startedAt < $1.startedAt })
        if targetSessions.isEmpty {
            if let s = ensureFreeformSidecarSession(in: convo) {
                targetSessions = [s]
            }
        }

        guard !targetSessions.isEmpty || convo.isSharedRoom else {
            mentionErrorDetail = "No agent session to send to. Pick an agent or use New Session."
            showMentionError = true
            return
        }

        for session in targetSessions {
            appState.leaveWorkerStandby(sessionId: session.id.uuidString)
        }

        for session in targetSessions where session.agent == nil {
            syncFreeformParticipantDisplayName(for: session, in: convo)
        }

        let userParticipant = convo.participants.first { $0.type == .user }
        let isFirstChat = convo.messages.filter({ $0.type == .chat }).isEmpty

        let message = ConversationMessage(
            senderParticipantId: userParticipant?.id,
            text: text,
            type: .chat,
            conversation: convo
        )

        var wireAttachments: [WireAttachment] = []
        for item in attachments {
            let attachment = AttachmentStore.save(data: item.data, mediaType: item.mediaType, fileName: item.fileName)
            attachment.message = message
            message.attachments.append(attachment)
            modelContext.insert(attachment)
            wireAttachments.append(WireAttachment(
                data: item.data.base64EncodedString(),
                mediaType: item.mediaType,
                fileName: item.fileName
            ))
        }

        convo.messages.append(message)
        modelContext.insert(message)
        if isFirstChat {
            let nameHint: String
            if text.isEmpty {
                let fileCount = attachments.count
                nameHint = "Shared \(fileCount) file\(fileCount == 1 ? "" : "s")"
            } else {
                nameHint = text
            }
            autoNameConversation(convo, firstMessage: nameHint)
        }

        try? modelContext.save()
        appState.notifyUserMessageAppended(conversationId: convo.id, message: message)

        if convo.isSharedRoom {
            Task {
                await sharedRoomService.publishLocalParticipants(for: convo)
                await sharedRoomService.publishLocalMessage(message, in: convo)
            }
        }

        if targetSessions.isEmpty, convo.isSharedRoom {
            isProcessing = false
            isManagingWaveResponses = false
            return
        }

        guard appState.sidecarStatus == .connected,
              let manager = appState.sidecarManager else {
            if convo.isSharedRoom {
                isProcessing = false
                isManagingWaveResponses = false
                return
            }
            isProcessing = false
            mentionErrorDetail = "Sidecar not connected. Check the connection status and try again."
            showMentionError = true
            return
        }

        isProcessing = true
        isManagingWaveResponses = true
        activeStreamingSessionKeys.removeAll()
        activeStreamingDisplayNames.removeAll()
        processingStartTimes.removeAll()
        lastTokenTimes.removeAll()
        lastStreamingTextLengths.removeAll()
        expandedStreamingThinkingSessionKeys.removeAll()
        queuedPeerDeliveriesBySession.removeAll()

        let userWavePlan = GroupRoutingPlanner.planUserWave(
            executionMode: convo.executionMode,
            routingMode: convo.routingMode,
            sessions: targetSessions,
            sourceGroup: sourceGroup(for: convo),
            mentionedAgents: resolvedMentionAgents,
            mentionedAll: mentionedAll
        )
        let currentPlanMode = planModeEnabled
        activeWaveTask?.cancel()
        activeWaveTask = Task { @MainActor in
            await runParallelAgentTurns(
                convo: convo,
                rootMessage: message,
                targetSessions: targetSessions,
                latestUserText: text,
                isFirstInteractiveUserTurn: isFirstChat,
                userWavePlan: userWavePlan,
                wireAttachments: wireAttachments,
                manager: manager,
                planMode: currentPlanMode
            )
        }
    }

    private struct PendingGroupCompletion: Sendable {
        let sessionId: UUID
        let sidecarKey: String
        let seenThroughMessageId: UUID?
        let wave: GroupWaveMetadata
        let planMode: Bool
    }

    private struct QueuedPeerDelivery {
        let prompt: String
        let seenThroughMessageId: UUID?
        let wave: GroupWaveMetadata
    }

    @MainActor
    private func runParallelAgentTurns(
        convo: Conversation,
        rootMessage: ConversationMessage,
        targetSessions: [Session],
        latestUserText: String,
        isFirstInteractiveUserTurn: Bool,
        userWavePlan: GroupRoutingPlanner.UserWavePlan,
        wireAttachments: [WireAttachment],
        manager: SidecarManager,
        planMode: Bool = false
    ) async {
        let worktreePath = await WorktreeManager.ensureWorktree(
            for: convo,
            projectDirectory: windowState.projectDirectory,
            modelContext: modelContext
        )
        for session in targetSessions where session.workingDirectory != worktreePath {
            session.workingDirectory = worktreePath
        }
        try? modelContext.save()

        let participants = convo.participants
        let provisioner = AgentProvisioner(modelContext: modelContext)
        let fanOutContext = GroupPeerFanOutContext(rootMessageId: rootMessage.id)
        let rootWave = await fanOutContext.makeRootWave(
            triggerMessageId: rootMessage.id,
            transcriptBoundaryMessageId: rootMessage.id,
            recipientSessionIds: Array(userWavePlan.recipientSessionIds)
        )
        let initialPending = await launchUserWave(
            convo: convo,
            targetSessions: targetSessions,
            latestUserText: latestUserText,
            isFirstInteractiveUserTurn: isFirstInteractiveUserTurn,
            userWavePlan: userWavePlan,
            wireAttachments: wireAttachments,
            manager: manager,
            provisioner: provisioner,
            worktreePath: worktreePath,
            wave: rootWave,
            planMode: planMode
        )
        await processPendingGroupCompletions(
            initialPending: initialPending,
            convo: convo,
            manager: manager,
            provisioner: provisioner,
            participants: participants,
            context: fanOutContext
        )

        guard !Task.isCancelled else { return }
        isManagingWaveResponses = false
        isProcessing = false
        activeWaveTask = nil
    }

    private func makeFreeformAgentConfig(for session: Session) -> AgentConfig {
        var systemPrompt = AgentDefaults.defaultFreeformSystemPrompt
        if let mission = session.mission?.trimmingCharacters(in: .whitespacesAndNewlines),
           !mission.isEmpty {
            systemPrompt += "\n\n# Current Mission\n\(mission)\n"
        }
        return AgentDefaults.makeFreeformAgentConfig(
            provider: session.provider,
            model: session.model,
            workingDirectory: session.workingDirectory.isEmpty
                ? (windowState.projectDirectory.isEmpty ? NSHomeDirectory() : windowState.projectDirectory)
                : session.workingDirectory,
            systemPrompt: systemPrompt,
            interactive: session.mode == .interactive ? true : nil,
            instancePolicy: {
                switch session.mode {
                case .interactive:
                    return nil
                case .autonomous:
                    return "spawn"
                case .worker:
                    return "singleton"
                }
            }(),
            instancePolicyPoolMax: nil,
        )
    }

    @MainActor
    private func beginStreamingState(for session: Session) {
        let sidecarKey = session.id.uuidString
        activeStreamingSessionKeys.insert(sidecarKey)
        activeStreamingDisplayNames[sidecarKey] = session.agent?.name ?? AgentDefaults.displayName(forProvider: session.provider)
        appState.streamingText.removeValue(forKey: sidecarKey)
        appState.thinkingText.removeValue(forKey: sidecarKey)
        appState.lastSessionEvent.removeValue(forKey: sidecarKey)
        appState.sessionActivity[sidecarKey] = .waitingForResult
        processingStartTimes[sidecarKey] = Date()
        lastTokenTimes.removeValue(forKey: sidecarKey)
        lastStreamingTextLengths[sidecarKey] = 0
    }

    @MainActor
    private func finishStreamingState(for sidecarKey: String) {
        activeStreamingSessionKeys.remove(sidecarKey)
        activeStreamingDisplayNames.removeValue(forKey: sidecarKey)
        processingStartTimes.removeValue(forKey: sidecarKey)
        lastTokenTimes.removeValue(forKey: sidecarKey)
        lastStreamingTextLengths.removeValue(forKey: sidecarKey)
        expandedStreamingThinkingSessionKeys.remove(sidecarKey)
    }

    @MainActor
    private func interruptActiveWaveForNewTurn() {
        activeWaveTask?.cancel()
        activeWaveTask = nil
        isManagingWaveResponses = false
        isProcessing = false
        activeStreamingSessionKeys.removeAll()
        activeStreamingDisplayNames.removeAll()
        processingStartTimes.removeAll()
        lastTokenTimes.removeAll()
        lastStreamingTextLengths.removeAll()
        expandedStreamingThinkingSessionKeys.removeAll()
        queuedPeerDeliveriesBySession.removeAll()
    }

    @MainActor
    private func sourceGroup(for convo: Conversation) -> AgentGroup? {
        guard let gid = convo.sourceGroupId else { return nil }
        let desc = FetchDescriptor<AgentGroup>(predicate: #Predicate { $0.id == gid })
        return try? modelContext.fetch(desc).first
    }

    private func groupRole(for session: Session, sourceGroup: AgentGroup?) -> GroupRole? {
        guard let group = sourceGroup, let agentId = session.agent?.id else { return nil }
        return group.roleFor(agentId: agentId)
    }

    private func teamMembers(
        excluding session: Session,
        in convo: Conversation,
        sourceGroup: AgentGroup?
    ) -> [GroupPromptBuilder.TeamMemberInfo] {
        convo.sessions
            .filter { $0.id != session.id }
            .compactMap { other in
                guard let agent = other.agent else { return nil }
                let role = sourceGroup?.roleFor(agentId: agent.id) ?? .participant
                return .init(name: agent.name, description: agent.agentDescription, role: role)
            }
    }

    @MainActor
    private func sendPrompt(
        to session: Session,
        prompt: String,
        attachments: [WireAttachment],
        manager: SidecarManager,
        provisioner: AgentProvisioner,
        worktreePath: String? = nil,
        planMode: Bool,
        errorPrefix: String,
        seenThroughMessageId: UUID?,
        wave: GroupWaveMetadata
    ) async -> PendingGroupCompletion? {
        let sidecarKey = session.id.uuidString
        beginStreamingState(for: session)

        var createConfig: AgentConfig?
        if !appState.createdSessions.contains(sidecarKey) {
            if session.agent != nil {
                if let worktreePath {
                    session.workingDirectory = session.workingDirectory.isEmpty ? worktreePath : session.workingDirectory
                }
                createConfig = provisioner.config(for: session)
            } else {
                createConfig = makeFreeformAgentConfig(for: session)
            }
        }

        do {
            session.status = .active
            if let config = createConfig {
                try await manager.send(.sessionCreate(
                    conversationId: sidecarKey,
                    agentConfig: config
                ))
                appState.createdSessions.insert(sidecarKey)
            }
            try await manager.send(.sessionMessage(
                sessionId: sidecarKey,
                text: prompt,
                attachments: attachments,
                planMode: planMode
            ))
            return PendingGroupCompletion(
                sessionId: session.id,
                sidecarKey: sidecarKey,
                seenThroughMessageId: seenThroughMessageId,
                wave: wave,
                planMode: planMode
            )
        } catch {
            appState.lastSessionEvent[sidecarKey] = .error("\(errorPrefix): \(error.localizedDescription)")
            finishStreamingState(for: sidecarKey)
            return nil
        }
    }

    @MainActor
    private func flushQueuedPeerDelivery(
        for session: Session,
        manager: SidecarManager,
        provisioner: AgentProvisioner
    ) async -> PendingGroupCompletion? {
        guard var queued = queuedPeerDeliveriesBySession[session.id], !queued.isEmpty else { return nil }
        let next = queued.removeFirst()
        if queued.isEmpty {
            queuedPeerDeliveriesBySession.removeValue(forKey: session.id)
        } else {
            queuedPeerDeliveriesBySession[session.id] = queued
        }
        return await sendPrompt(
            to: session,
            prompt: next.prompt,
            attachments: [],
            manager: manager,
            provisioner: provisioner,
            planMode: false,
            errorPrefix: "Peer notify failed",
            seenThroughMessageId: next.seenThroughMessageId,
            wave: next.wave
        )
    }

    @MainActor
    private func launchUserWave(
        convo: Conversation,
        targetSessions: [Session],
        latestUserText: String,
        isFirstInteractiveUserTurn: Bool,
        userWavePlan: GroupRoutingPlanner.UserWavePlan,
        wireAttachments: [WireAttachment],
        manager: SidecarManager,
        provisioner: AgentProvisioner,
        worktreePath: String,
        wave: GroupWaveMetadata,
        planMode: Bool
    ) async -> [PendingGroupCompletion] {
        let sourceGroup = sourceGroup(for: convo)
        let groupInstruction = sourceGroup?.groupInstruction
        let participants = convo.participants
        var pending: [PendingGroupCompletion] = []

        for session in targetSessions where wave.recipientSessionIds.contains(session.id) {
            let basePrompt = GroupPromptBuilder.buildMessageText(
                conversation: convo,
                targetSession: session,
                latestUserMessageText: latestUserText,
                participants: participants,
                highlightedMentionAgentNames: userWavePlan.mentionedAgentNames,
                mentionedAll: userWavePlan.mentionedAll,
                routingMode: convo.routingMode,
                deliveryReason: userWavePlan.deliveryReason,
                transcriptBoundaryMessageId: wave.transcriptBoundaryMessageId,
                allowNoReply: true,
                groupInstruction: groupInstruction,
                role: groupRole(for: session, sourceGroup: sourceGroup),
                teamMembers: teamMembers(excluding: session, in: convo, sourceGroup: sourceGroup)
            )
            let promptText = convo.sessions.count > 1
                ? ExecutionModePromptBuilder.wrapCoordinatorPrompt(
                    basePrompt,
                    mode: convo.executionMode,
                    coordinatorName: userWavePlan.coordinatorAgentName,
                    mission: session.mission,
                    isFirstInteractiveTurn: isFirstInteractiveUserTurn
                )
                : ExecutionModePromptBuilder.wrapDirectPrompt(
                    basePrompt,
                    mode: convo.executionMode,
                    mission: session.mission,
                    isFirstInteractiveTurn: isFirstInteractiveUserTurn
                )

            if let launched = await sendPrompt(
                to: session,
                prompt: promptText,
                attachments: wireAttachments,
                manager: manager,
                provisioner: provisioner,
                worktreePath: worktreePath,
                planMode: planMode,
                errorPrefix: "Failed to send",
                seenThroughMessageId: wave.transcriptBoundaryMessageId,
                wave: wave
            ) {
                pending.append(launched)
            }
        }

        return pending
    }

    @MainActor
    private func launchPeerWave(
        fromSession: Session,
        triggerMessage: ConversationMessage,
        convo: Conversation,
        manager: SidecarManager,
        provisioner: AgentProvisioner,
        participants: [Participant],
        context: GroupPeerFanOutContext
    ) async -> [PendingGroupCompletion] {
        guard convo.sessions.count > 1 else { return [] }

        let sourceGroup = sourceGroup(for: convo)
        if let group = sourceGroup, !group.autoReplyEnabled { return [] }

        let senderLabel = GroupPromptBuilder.senderDisplayLabel(for: triggerMessage, participants: participants)
        let sortedOthers = convo.sessions
            .filter { $0.id != fromSession.id }
            .sorted { $0.startedAt < $1.startedAt }
        guard let peerPlan = GroupRoutingPlanner.planPeerWave(
            routingMode: convo.routingMode,
            triggerText: triggerMessage.text,
            otherSessions: sortedOthers,
            participants: participants
        ) else {
            return []
        }
        let candidateSessions = sortedOthers.filter { peerPlan.candidateSessionIds.contains($0.id) }

        // Dispatch silent observer transcript context (no budget impact).
        let silentIds = await context.reserveSilentObserverTranscript(
            triggerMessageId: triggerMessage.id,
            silentObserverSessionIds: peerPlan.silentObserverSessionIds
        )
        let silentObserverSessions = sortedOthers.filter { silentIds.contains($0.id) }
        if !silentObserverSessions.isEmpty {
            // Sentinel wave with empty recipientSessionIds: the response is stored in the
            // session's history but NOT broadcast to the conversation UI.
            let silentWave = GroupWaveMetadata(
                rootMessageId: context.rootMessageId,
                waveId: 0,
                triggerMessageId: triggerMessage.id,
                transcriptBoundaryMessageId: nil,
                recipientSessionIds: []
            )
            for observer in silentObserverSessions {
                let observerPrompt = GroupPromptBuilder.buildSilentObserverContextPrompt(
                    senderLabel: senderLabel,
                    triggerText: triggerMessage.text
                )
                // Fire-and-forget: do NOT add to `pending` so the response is never broadcast.
                Task {
                    _ = await sendPrompt(
                        to: observer,
                        prompt: observerPrompt,
                        attachments: [],
                        manager: manager,
                        provisioner: provisioner,
                        planMode: false,
                        errorPrefix: "Silent observer notify failed",
                        seenThroughMessageId: triggerMessage.id,
                        wave: silentWave
                    )
                }
            }
        }

        guard let wave = await context.reservePeerWave(
            triggerMessageId: triggerMessage.id,
            transcriptBoundaryMessageId: triggerMessage.id,
            candidateSessionIds: candidateSessions.map(\.id),
            prioritySessionIds: peerPlan.prioritySessionIds
        ) else {
            return []
        }

        var pending: [PendingGroupCompletion] = []
        for other in candidateSessions where wave.recipientSessionIds.contains(other.id) {
            let key = other.id.uuidString

            let deliveryReason = peerPlan.deliveryReasons[other.id] ?? .generic

            let prompt = GroupPromptBuilder.buildPeerNotifyPrompt(
                senderLabel: senderLabel,
                peerMessageText: triggerMessage.text,
                recipientSession: other,
                deliveryReason: deliveryReason,
                routingMode: convo.routingMode,
                allowNoReply: true,
                role: groupRole(for: other, sourceGroup: sourceGroup),
                teamMembers: teamMembers(excluding: other, in: convo, sourceGroup: sourceGroup)
            )

            if activeStreamingSessionKeys.contains(key) {
                queuedPeerDeliveriesBySession[other.id, default: []].append(
                    QueuedPeerDelivery(
                        prompt: prompt,
                        seenThroughMessageId: triggerMessage.id,
                        wave: wave
                    )
                )
                continue
            }

            if let launched = await sendPrompt(
                to: other,
                prompt: prompt,
                attachments: [],
                manager: manager,
                provisioner: provisioner,
                planMode: false,
                errorPrefix: "Peer notify failed",
                seenThroughMessageId: triggerMessage.id,
                wave: wave
            ) {
                pending.append(launched)
            }
        }

        return pending
    }

    @MainActor
    private func processPendingGroupCompletions(
        initialPending: [PendingGroupCompletion],
        convo: Conversation,
        manager: SidecarManager,
        provisioner: AgentProvisioner,
        participants: [Participant],
        context: GroupPeerFanOutContext
    ) async {
        guard !initialPending.isEmpty else { return }

        await withTaskGroup(of: PendingGroupCompletion.self) { group in
            for pending in initialPending {
                group.addTask {
                    await waitForSessionCompletion(sidecarKey: pending.sidecarKey)
                    return pending
                }
            }

            while let completion = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }

                guard let session = convo.sessions.first(where: { $0.id == completion.sessionId }) else {
                    finishStreamingState(for: completion.sidecarKey)
                    continue
                }
                let seenThroughMessage = completion.seenThroughMessageId.flatMap { messageId in
                    convo.messages.first(where: { $0.id == messageId })
                }

                if let reply = finalizeAssistantStreamIntoMessage(
                    convo: convo,
                    session: session,
                    sidecarKey: completion.sidecarKey,
                    seenThroughMessage: seenThroughMessage
                ) {
                    if convo.executionMode == .worker {
                        appState.enterWorkerStandby(sessionId: completion.sidecarKey)
                    }
                    if completion.planMode {
                        lastPlanResponseMessageId = reply.id
                    }

                    let followUps = await launchPeerWave(
                        fromSession: session,
                        triggerMessage: reply,
                        convo: convo,
                        manager: manager,
                        provisioner: provisioner,
                        participants: participants,
                        context: context
                    )
                    for pending in followUps {
                        group.addTask {
                            await waitForSessionCompletion(sidecarKey: pending.sidecarKey)
                            return pending
                        }
                    }
                }

                finishStreamingState(for: completion.sidecarKey)
                if let queued = await flushQueuedPeerDelivery(
                    for: session,
                    manager: manager,
                    provisioner: provisioner
                ) {
                    group.addTask {
                        await waitForSessionCompletion(sidecarKey: queued.sidecarKey)
                        return queued
                    }
                }
            }
        }
    }

    private func waitForSessionCompletion(sidecarKey: String) async {
        let maxWait = 1_200
        var iterations = 0
        while iterations < maxWait {
            if Task.isCancelled {
                return
            }
            if let ev = await MainActor.run(body: { appState.lastSessionEvent[sidecarKey] }) {
                switch ev {
                case .result, .error:
                    return
                }
            }
            try? await Task.sleep(for: .milliseconds(100))
            iterations += 1
        }
    }

    // MARK: - Session Events

    private func checkForPendingResponse() {
        guard !isManagingWaveResponses else { return }
        guard let key = streamSessionKeyForUI else { return }
        if let event = appState.lastSessionEvent[key] {
            isProcessing = true
            switch event {
            case .result:
                collectResponseIfSingle()
            case .error(let msg):
                collectResponseIfSingle(errorMessage: msg)
            }
            return
        }

        if let text = appState.streamingText[key], !text.isEmpty, !isProcessing {
            isProcessing = true
        }
    }

    @MainActor
    private func restoreStreamingStateFromAppState() {
        guard let convo = conversation else {
            isProcessing = false
            activeStreamingSessionKeys.removeAll()
            activeStreamingDisplayNames.removeAll()
            processingStartTimes.removeAll()
            lastTokenTimes.removeAll()
            lastStreamingTextLengths.removeAll()
            expandedStreamingThinkingSessionKeys.removeAll()
            return
        }

        let now = Date()
        var restoredKeys: Set<String> = []
        var restoredDisplayNames: [String: String] = [:]

        for session in convo.sessions {
            let sidecarKey = session.id.uuidString
            let hasStreamingText = !(appState.streamingText[sidecarKey]?.isEmpty ?? true)
            let hasThinkingText = !(appState.thinkingText[sidecarKey]?.isEmpty ?? true)

            let shouldTrack = ChatSessionWatchdog.shouldTrackSession(
                activity: appState.sessionActivity[sidecarKey] ?? .idle,
                hasStreamingText: hasStreamingText,
                hasThinkingText: hasThinkingText
            )

            guard shouldTrack else { continue }

            restoredKeys.insert(sidecarKey)
            restoredDisplayNames[sidecarKey] = session.agent?.name ?? AgentDefaults.displayName(forProvider: session.provider)
            processingStartTimes[sidecarKey] = processingStartTimes[sidecarKey] ?? now
            lastStreamingTextLengths[sidecarKey] = appState.streamingText[sidecarKey]?.count ?? 0
        }

        let removedKeys = activeStreamingSessionKeys.subtracting(restoredKeys)
        for key in removedKeys {
            processingStartTimes.removeValue(forKey: key)
            lastTokenTimes.removeValue(forKey: key)
            lastStreamingTextLengths.removeValue(forKey: key)
            expandedStreamingThinkingSessionKeys.remove(key)
        }

        activeStreamingSessionKeys = restoredKeys
        activeStreamingDisplayNames = restoredDisplayNames
        isProcessing = !restoredKeys.isEmpty
    }

    private func hasVisibleOutput(for sidecarKey: String, since start: Date) -> Bool {
        if !(appState.streamingText[sidecarKey]?.isEmpty ?? true) { return true }
        if !(appState.thinkingText[sidecarKey]?.isEmpty ?? true) { return true }
        if appState.progressTrackers[sidecarKey] != nil { return true }
        if !(appState.pendingSuggestions[sidecarKey]?.isEmpty ?? true) { return true }
        if appState.completedPlans[sidecarKey] != nil { return true }

        guard let convo = conversation,
              let session = convo.sessions.first(where: { $0.id.uuidString == sidecarKey }),
              let participant = participantForSession(session, in: convo) else {
            return false
        }

        return convo.messages.contains { message in
            message.senderParticipantId == participant.id &&
            message.type == .richContent &&
            message.timestamp >= start
        }
    }

    private func checkForCompletion(events: [String: AppState.SessionEventKind]? = nil) {
        guard !isManagingWaveResponses else { return }
        guard let key = streamSessionKeyForUI else { return }
        let source = events ?? appState.lastSessionEvent
        guard let event = source[key] else { return }

        isProcessing = true
        switch event {
        case .result:
            collectResponseIfSingle()
        case .error(let msg):
            collectResponseIfSingle(errorMessage: msg)
        }
    }

    /// Legacy path when not using sequential multi-send (e.g. recovery).
    private func collectResponseIfSingle(errorMessage: String? = nil) {
        guard let key = streamSessionKeyForUI,
              let convo = conversation,
              let session = convo.sessions.first(where: { $0.id.uuidString == key }) else {
            isProcessing = false
            return
        }
        _ = finalizeAssistantStreamIntoMessage(convo: convo, session: session, sidecarKey: key, errorMessage: errorMessage)
        if errorMessage == nil, convo.executionMode == .worker {
            appState.enterWorkerStandby(sessionId: key)
        } else {
            appState.leaveWorkerStandby(sessionId: key)
        }
        isProcessing = false
        finishStreamingState(for: key)
    }

    @discardableResult
    private func finalizeAssistantStreamIntoMessage(
        convo: Conversation,
        session: Session,
        sidecarKey: String,
        errorMessage: String? = nil,
        seenThroughMessage: ConversationMessage? = nil
    ) -> ConversationMessage? {
        var err = errorMessage
        if err == nil, case .error(let m) = appState.lastSessionEvent[sidecarKey] {
            err = m
        }
        let streamedText = appState.streamingText[sidecarKey] ?? ""
        let hasImages = !(appState.streamingImages[sidecarKey]?.isEmpty ?? true)
        let hasFileCards = !(appState.streamingFileCards[sidecarKey]?.isEmpty ?? true)
        guard !streamedText.isEmpty || err != nil || hasImages || hasFileCards else {
            return nil
        }
        let responseText = !streamedText.isEmpty ? streamedText : (err ?? "")

        if err == nil,
           !hasImages,
           !hasFileCards,
           GroupPromptBuilder.isNoReplySentinel(responseText) {
            GroupPromptBuilder.markSessionCaughtUp(session: session, through: seenThroughMessage)
            clearFinishedStreamState(for: sidecarKey)
            return nil
        }

        let agentParticipant = participantForSession(session, in: convo)
        let response = ConversationMessage(
            senderParticipantId: agentParticipant?.id,
            text: responseText,
            type: .chat,
            conversation: convo
        )
        let thinking = appState.thinkingText[sidecarKey]
        if let thinking, !thinking.isEmpty {
            response.thinkingText = thinking
        }
        convo.messages.append(response)
        modelContext.insert(response)
        GroupPromptBuilder.advanceWatermark(session: session, assistantMessage: response)

        // Finalize accumulated agent images into MessageAttachment records
        if let images = appState.streamingImages[sidecarKey] {
            for img in images {
                guard let data = Data(base64Encoded: img.data) else { continue }
                let ext = img.mediaType.components(separatedBy: "/").last ?? "png"
                let name = "agent-image-\(UUID().uuidString.prefix(8)).\(ext)"
                let attachment = AttachmentStore.save(data: data, mediaType: img.mediaType, fileName: name)
                attachment.message = response
                modelContext.insert(attachment)
                response.attachments.append(attachment)
            }
            appState.streamingImages.removeValue(forKey: sidecarKey)
        }

        // Finalize accumulated file cards into MessageAttachment records
        if let cards = appState.streamingFileCards[sidecarKey] {
            for card in cards {
                let mt = card.type == "html" ? "text/html" : "application/pdf"
                let attachment = MessageAttachment(mediaType: mt, fileName: card.name, fileSize: 0)
                attachment.localFilePath = card.path
                attachment.message = response
                modelContext.insert(attachment)
                response.attachments.append(attachment)
            }
            appState.streamingFileCards.removeValue(forKey: sidecarKey)
        }

        try? modelContext.save()
        if convo.isSharedRoom {
            Task {
                await sharedRoomService.publishLocalMessage(response, in: convo)
            }
        }
        clearFinishedStreamState(for: sidecarKey)
        return response
    }

    private func clearFinishedStreamState(for sidecarKey: String) {
        appState.streamingText.removeValue(forKey: sidecarKey)
        appState.thinkingText.removeValue(forKey: sidecarKey)
        appState.lastSessionEvent.removeValue(forKey: sidecarKey)
        expandedStreamingThinkingSessionKeys.remove(sidecarKey)
    }

    private func handleAttachmentTap(_ attachment: MessageAttachment) {
        if attachment.isImage {
            previewAttachment = attachment
            return
        }

        if let localFilePath = attachment.localFilePath, !localFilePath.isEmpty {
            openLocalFileReference(localFilePath)
        } else {
            NSWorkspace.shared.open(AttachmentStore.url(for: attachment))
        }
    }

    private func openLocalFileReference(_ reference: String) {
        LocalFileReferenceSupport.open(
            rawReference: reference,
            workspaceRoot: inspectorWorkspaceRoot,
            windowState: windowState
        )
    }

    private func sharedRoomStatusLabel(for conversation: Conversation) -> String {
        switch conversation.roomStatus {
        case .live:
            return conversation.roomTransportMode == .direct ? "Live" : "Synced via CloudKit"
        case .syncing:
            return "Syncing room history…"
        case .unavailable:
            return "Room unavailable"
        case .localOnly:
            return "Local only"
        }
    }

    private func sharedRoomStatusColor(for conversation: Conversation) -> Color {
        switch conversation.roomStatus {
        case .live:
            return conversation.roomTransportMode == .direct ? .green : .blue
        case .syncing:
            return .orange
        case .unavailable:
            return .red
        case .localOnly:
            return .gray
        }
    }

    // MARK: - Actions

    private enum ChatTranscriptExportKind {
        case markdown, html, pdf
    }

    private enum ChatTranscriptExportDestination {
        case save, share
    }

    private func exportChatTranscript(kind: ChatTranscriptExportKind, destination: ChatTranscriptExportDestination) async {
        guard let snap = chatExportSnapshot() else { return }
        let base = ChatTranscriptExport.suggestedBaseFileName(for: snap)
        switch (kind, destination) {
        case (.markdown, .save):
            let md = ChatTranscriptExport.markdown(snap)
            guard let url = await ChatExportPresenters.runSavePanel(
                suggestedFileName: "\(base).md",
                allowedTypes: [ChatExportPresenters.markdownType]
            ) else { return }
            do {
                try Data(md.utf8).write(to: url, options: .atomic)
            } catch {
                Log.chat.error("Export markdown failed: \(error)")
            }
        case (.html, .save):
            let html = ChatTranscriptExport.html(snap)
            guard let url = await ChatExportPresenters.runSavePanel(
                suggestedFileName: "\(base).html",
                allowedTypes: [.html]
            ) else { return }
            do {
                try Data(html.utf8).write(to: url, options: .atomic)
            } catch {
                Log.chat.error("Export HTML failed: \(error)")
            }
        case (.pdf, .save):
            let html = ChatTranscriptExport.html(snap)
            let renderer = ChatTranscriptPDFRenderer()
            do {
                let data = try await renderer.renderPDF(html: html)
                guard let url = await ChatExportPresenters.runSavePanel(
                    suggestedFileName: "\(base).pdf",
                    allowedTypes: [.pdf]
                ) else { return }
                try data.write(to: url, options: .atomic)
            } catch {
                Log.chat.error("Export PDF failed: \(error)")
            }
        case (.markdown, .share):
            let md = ChatTranscriptExport.markdown(snap)
            let data = Data(md.utf8)
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).md")
            do {
                try data.write(to: temp, options: .atomic)
                let coord = ShareTempFileCoordinator(url: temp) { self.shareCoordinator = nil }
                shareCoordinator = coord
                ChatExportPresenters.presentSharePicker(for: temp, coordinator: coord)
            } catch {
                Log.chat.error("Share markdown failed: \(error)")
            }
        case (.html, .share):
            let html = ChatTranscriptExport.html(snap)
            let data = Data(html.utf8)
            let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).html")
            do {
                try data.write(to: temp, options: .atomic)
                let coord = ShareTempFileCoordinator(url: temp) { self.shareCoordinator = nil }
                shareCoordinator = coord
                ChatExportPresenters.presentSharePicker(for: temp, coordinator: coord)
            } catch {
                Log.chat.error("Share HTML failed: \(error)")
            }
        case (.pdf, .share):
            let html = ChatTranscriptExport.html(snap)
            let renderer = ChatTranscriptPDFRenderer()
            do {
                let data = try await renderer.renderPDF(html: html)
                let temp = FileManager.default.temporaryDirectory.appendingPathComponent("\(UUID().uuidString).pdf")
                try data.write(to: temp, options: .atomic)
                let coord = ShareTempFileCoordinator(url: temp) { self.shareCoordinator = nil }
                shareCoordinator = coord
                ChatExportPresenters.presentSharePicker(for: temp, coordinator: coord)
            } catch {
                Log.chat.error("Share PDF failed: \(error)")
            }
        }
    }

    private func forkConversation() {
        guard let newConvo = cloneConversationForFork(from: conversation, throughMessage: nil),
              let oldPrimary = conversation?.primarySession,
              let newPrimary = newConvo.primarySession else { return }
        windowState.selectedConversationId = newConvo.id
        Task {
            try? await appState.sidecarManager?.send(.sessionFork(
                parentSessionId: oldPrimary.id.uuidString,
                childSessionId: newPrimary.id.uuidString
            ))
        }
    }

    private func forkFromMessage(_ pivot: ConversationMessage) {
        guard let newConvo = cloneConversationForFork(from: conversation, throughMessage: pivot),
              let oldPrimary = conversation?.primarySession,
              let newPrimary = newConvo.primarySession else { return }
        windowState.selectedConversationId = newConvo.id
        Task {
            try? await appState.sidecarManager?.send(.sessionFork(
                parentSessionId: oldPrimary.id.uuidString,
                childSessionId: newPrimary.id.uuidString
            ))
        }
    }

    /// Duplicate conversation structure and optionally copy messages up to `throughMessage` (inclusive).
    private func cloneConversationForFork(from source: Conversation?, throughMessage: ConversationMessage?) -> Conversation? {
        guard let source else { return nil }
        let topicBase = source.topic ?? "Chat"
        let newConvo = Conversation(
            topic: topicBase + " (fork)",
            projectId: source.projectId,
            threadKind: source.threadKind
        )
        newConvo.routingMode = source.routingMode
        newConvo.parentConversationId = source.id

        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = newConvo
        newConvo.participants.append(userParticipant)

        var oldToNewSession: [UUID: Session] = [:]
        for oldSession in source.sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let newSession = Session(
                agent: oldSession.agent,
                mission: oldSession.mission,
                mode: oldSession.mode,
                workingDirectory: oldSession.workingDirectory
            )
            let agent = oldSession.agent
            newSession.conversations = [newConvo]
            newConvo.sessions.append(newSession)
            oldToNewSession[oldSession.id] = newSession

            let p = Participant(type: .agentSession(sessionId: newSession.id), displayName: agent?.name ?? "Agent")
            p.conversation = newConvo
            newConvo.participants.append(p)
            modelContext.insert(newSession)
        }

        let ordered = source.messages.sorted { $0.timestamp < $1.timestamp }
        let slice: [ConversationMessage]
        if let pivot = throughMessage, let idx = ordered.firstIndex(where: { $0.id == pivot.id }) {
            slice = Array(ordered[...idx])
        } else {
            slice = ordered
        }

        for oldMsg in slice where oldMsg.type == .chat {
            let newSender: UUID? = {
                guard let sid = oldMsg.senderParticipantId,
                      let oldP = source.participants.first(where: { $0.id == sid }) else { return userParticipant.id }
                if oldP.type == .user { return userParticipant.id }
                if case .agentSession(let osid) = oldP.type,
                   let ns = oldToNewSession[osid],
                   let np = participantForSession(ns, in: newConvo) {
                    return np.id
                }
                return userParticipant.id
            }()
            let nm = ConversationMessage(senderParticipantId: newSender, text: oldMsg.text, type: .chat, conversation: newConvo)
            nm.timestamp = oldMsg.timestamp
            nm.thinkingText = oldMsg.thinkingText
            newConvo.messages.append(nm)
            modelContext.insert(nm)
        }

        modelContext.insert(newConvo)
        try? modelContext.save()
        return newConvo
    }

    private func pauseSession() {
        guard let convo = conversation else { return }
        for session in convo.sessions {
            let key = session.id.uuidString
            appState.sendToSidecar(.sessionPause(sessionId: key))
            appState.markSessionPausedLocally(key)
            session.status = .paused
        }
        try? modelContext.save()
    }

    private func restoreInterruptedSessions() {
        Task { @MainActor in
            _ = await restoreSessionContexts(
                interruptedSessions,
                resultingStatus: .paused,
                emptySelectionMessage: "No interrupted sessions are available to restore."
            )
        }
    }

    @MainActor
    private func restoreSessionContexts(
        _ sessions: [Session],
        resultingStatus: SessionStatus,
        emptySelectionMessage: String
    ) async -> Bool {
        guard !sessions.isEmpty else {
            recoveryErrorDetail = emptySelectionMessage
            showRecoveryError = true
            return false
        }

        do {
            for session in sessions {
                guard let claudeSessionId = session.claudeSessionId else { continue }
                try await appState.restoreSessionContextAwait(
                    sessionId: session.id.uuidString,
                    claudeSessionId: claudeSessionId
                )
                appState.sessionActivity[session.id.uuidString] = .idle
                session.status = resultingStatus
            }
            conversation?.status = .active
            try? modelContext.save()
            return true
        } catch {
            recoveryErrorDetail = "Couldn't restore the interrupted session context. \(error.localizedDescription)"
            showRecoveryError = true
            return false
        }
    }

    private func retryLastInterruptedTurn() {
        guard let lastUserMessage = latestUserChatMessage?.text.trimmingCharacters(in: .whitespacesAndNewlines),
              !lastUserMessage.isEmpty else {
            recoveryErrorDetail = "There isn't a previous user turn to retry in this conversation."
            showRecoveryError = true
            return
        }

        Task { @MainActor in
            guard await restoreSessionContexts(
                interruptedSessions,
                resultingStatus: .paused,
                emptySelectionMessage: "No interrupted sessions are available to retry."
            ) else { return }
            inputText = lastUserMessage
            sendMessage()
        }
    }

    private func continueFromInterruption() {
        Task { @MainActor in
            guard await restoreSessionContexts(
                interruptedSessions,
                resultingStatus: .paused,
                emptySelectionMessage: "No interrupted sessions are available to continue."
            ) else { return }
            inputText = interruptedContinuationPrompt
            sendMessage()
        }
    }

    private var interruptedContinuationPrompt: String {
        """
        The app restarted during your previous turn. Continue from the last completed step, avoid repeating side effects, and briefly say what you believe was already finished before you continue.
        """
    }

    private func closeConversation(_ convo: Conversation) {
        convo.status = .closed
        convo.closedAt = Date()
        for session in convo.sessions {
            let key = session.id.uuidString
            appState.sendToSidecar(.sessionPause(sessionId: key))
            appState.markSessionPausedLocally(key)
            session.status = .paused
        }
        try? modelContext.save()
    }

    private func clearMessages() {
        guard let convo = conversation else { return }
        for message in convo.messages {
            modelContext.delete(message)
        }
        convo.messages.removeAll()
        try? modelContext.save()
    }

    private func duplicateConversation(_ convo: Conversation) {
        let newConvo = Conversation(
            topic: (convo.topic ?? "Untitled") + " (copy)",
            projectId: convo.projectId,
            threadKind: convo.threadKind
        )
        newConvo.routingMode = convo.routingMode
        let userParticipant = Participant(type: .user, displayName: "You")
        userParticipant.conversation = newConvo
        newConvo.participants.append(userParticipant)

        for session in convo.sessions.sorted(by: { $0.startedAt < $1.startedAt }) {
            let newSession = Session(
                agent: session.agent,
                mission: session.mission,
                mode: session.mode,
                workingDirectory: session.workingDirectory
            )
            newSession.conversations = [newConvo]
            newConvo.sessions.append(newSession)

            let displayName = session.agent?.name ?? "Agent"
            let agentParticipant = Participant(
                type: .agentSession(sessionId: newSession.id),
                displayName: displayName
            )
            agentParticipant.conversation = newConvo
            newConvo.participants.append(agentParticipant)
            modelContext.insert(newSession)
        }

        modelContext.insert(newConvo)
        try? modelContext.save()
        windowState.selectedConversationId = newConvo.id
    }
}
