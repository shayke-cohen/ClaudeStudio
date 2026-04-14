import Foundation

enum GroupRoutingPlanner {
    enum UserDeliveryReason: Sendable, Equatable, Hashable {
        case broad
        case directMention
        case broadcast
        case coordinatorLead
        case implicitFallback
    }

    enum PeerDeliveryReason: Sendable, Equatable, Hashable {
        case generic
        case directMention
        case broadcast
    }

    struct UserWavePlan: Sendable, Equatable {
        let recipientSessionIds: Set<UUID>
        let recipientAgentNames: [String]
        let mentionedAgentNames: [String]
        let mentionedAll: Bool
        let deliveryReason: UserDeliveryReason
        let coordinatorAgentName: String?
    }

    struct PeerWavePlan: Sendable, Equatable {
        let candidateSessionIds: [UUID]
        let prioritySessionIds: Set<UUID>
        let deliveryReasons: [UUID: PeerDeliveryReason]
        let silentObserverSessionIds: [UUID]
    }

    static func planUserWave(
        executionMode: ConversationExecutionMode = .interactive,
        routingMode: GroupRoutingMode,
        sessions: [Session],
        sourceGroup: AgentGroup?,
        mentionedAgents: [Agent],
        mentionedAll: Bool
    ) -> UserWavePlan {
        let sortedSessions = sessions.sorted { $0.startedAt < $1.startedAt }
        let mentionedAgentIds = Set(mentionedAgents.map(\.id))
        let mentionedNames = mentionedAgents.map(\.name)

        let recipients: [Session]
        let deliveryReason: UserDeliveryReason
        let coordinatorAgentName: String?

        if executionMode != .interactive {
            let coordinatorSession = coordinatorSession(in: sortedSessions, sourceGroup: sourceGroup) ?? sortedSessions.first
            recipients = coordinatorSession.map { [$0] } ?? []
            deliveryReason = .coordinatorLead
            coordinatorAgentName = coordinatorSession?.agent?.name
        } else if mentionedAll {
            recipients = sortedSessions
            deliveryReason = .broadcast
            coordinatorAgentName = nil
        } else if !mentionedAgentIds.isEmpty {
            if routingMode == .mentionAware {
                recipients = sortedSessions.filter { session in
                    guard let agentId = session.agent?.id else { return false }
                    return mentionedAgentIds.contains(agentId)
                }
            } else {
                recipients = sortedSessions
            }
            deliveryReason = .directMention
            coordinatorAgentName = nil
        } else if routingMode == .mentionAware,
                  let coordinatorSession = coordinatorSession(in: sortedSessions, sourceGroup: sourceGroup) {
            recipients = [coordinatorSession]
            deliveryReason = .coordinatorLead
            coordinatorAgentName = coordinatorSession.agent?.name
        } else {
            recipients = sortedSessions
            deliveryReason = routingMode == .mentionAware ? .implicitFallback : .broad
            coordinatorAgentName = nil
        }

        return UserWavePlan(
            recipientSessionIds: Set(recipients.map(\.id)),
            recipientAgentNames: recipients.map { $0.agent?.name ?? "Assistant" },
            mentionedAgentNames: mentionedNames,
            mentionedAll: mentionedAll,
            deliveryReason: deliveryReason,
            coordinatorAgentName: coordinatorAgentName
        )
    }

    static func planPeerWave(
        routingMode: GroupRoutingMode,
        triggerText: String,
        otherSessions: [Session],
        participants: [Participant] = []
    ) -> PeerWavePlan? {
        let sortedOthers = otherSessions.sorted { $0.startedAt < $1.startedAt }

        // Build O(1) session → role lookup to avoid O(N×P) nested scan.
        let sessionRoles: [UUID: ParticipantRole] = Dictionary(uniqueKeysWithValues:
            participants.compactMap { p -> (UUID, ParticipantRole)? in
                if case .agentSession(let sid) = p.type { return (sid, p.role) }
                return nil
            }
        )
        // Split silent observers from active candidates.
        let silentObserverSessionIds: Set<UUID> = Set(
            sortedOthers.compactMap { session -> UUID? in
                sessionRoles[session.id] == .silentObserver ? session.id : nil
            }
        )
        let activeSortedOthers = sortedOthers.filter { !silentObserverSessionIds.contains($0.id) }

        let isAllMention = ChatSendRouting.containsMentionAll(in: triggerText)
        let mentionNames = ChatSendRouting.mentionedAgentNames(
            in: triggerText,
            agents: sortedOthers.compactMap(\.agent)
        )
        let filteredNames = mentionNames.filter { !$0.isEmpty && !ChatSendRouting.isMentionAllToken($0) }

        let mentionedSessionIds: Set<UUID>
        if isAllMention {
            mentionedSessionIds = Set(sortedOthers.map(\.id))
        } else {
            mentionedSessionIds = Set(sortedOthers.filter { session in
                guard let agentName = session.agent?.name else { return false }
                return filteredNames.contains { $0.caseInsensitiveCompare(agentName) == .orderedSame }
            }.map(\.id))
        }

        // Elevate mentioned silent observers to active candidates.
        let mentionedSilentObservers = silentObserverSessionIds.intersection(mentionedSessionIds)
        let passiveSilentObserverIds = silentObserverSessionIds.subtracting(mentionedSilentObservers)

        // Build candidate pool: active sessions + any mentioned silent observers.
        let elevatedSessions = sortedOthers.filter { mentionedSilentObservers.contains($0.id) }
        let candidateSessions: [Session]
        if routingMode == .mentionAware {
            guard isAllMention || !mentionedSessionIds.isEmpty else {
                // No active mentions, but passive observers still exist — return nil for active wave.
                if passiveSilentObserverIds.isEmpty { return nil }
                return PeerWavePlan(
                    candidateSessionIds: [],
                    prioritySessionIds: [],
                    deliveryReasons: [:],
                    silentObserverSessionIds: Array(passiveSilentObserverIds)
                )
            }
            candidateSessions = activeSortedOthers.filter { mentionedSessionIds.contains($0.id) } + elevatedSessions
        } else {
            candidateSessions = activeSortedOthers + elevatedSessions
        }

        guard !candidateSessions.isEmpty || !passiveSilentObserverIds.isEmpty else { return nil }

        var deliveryReasons: [UUID: PeerDeliveryReason] = [:]
        for session in candidateSessions {
            if mentionedSessionIds.contains(session.id) {
                deliveryReasons[session.id] = isAllMention ? .broadcast : .directMention
            } else {
                deliveryReasons[session.id] = .generic
            }
        }

        return PeerWavePlan(
            candidateSessionIds: candidateSessions.map(\.id),
            prioritySessionIds: mentionedSessionIds,
            deliveryReasons: deliveryReasons,
            silentObserverSessionIds: Array(passiveSilentObserverIds)
        )
    }

    private static func coordinatorSession(
        in sessions: [Session],
        sourceGroup: AgentGroup?
    ) -> Session? {
        guard let coordinatorId = sourceGroup?.coordinatorAgentId else { return nil }
        return sessions.first(where: { $0.agent?.id == coordinatorId })
    }
}
