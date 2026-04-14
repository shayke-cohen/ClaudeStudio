import Foundation

struct GroupWaveMetadata: Sendable {
    let rootMessageId: UUID
    let waveId: Int
    let triggerMessageId: UUID
    let transcriptBoundaryMessageId: UUID?
    let recipientSessionIds: Set<UUID>
}

/// Budget and deduplication for automatic peer `session.message` fan-out in group chats.
actor GroupPeerFanOutContext {
    let rootMessageId: UUID
    private var additionalTurnsRemaining: Int
    private var deliveredNotifyKeys: Set<String> = []
    private var nextWaveId: Int = 1

    init(rootMessageId: UUID, maxAdditionalSidecarTurns: Int = 12) {
        self.rootMessageId = rootMessageId
        self.additionalTurnsRemaining = maxAdditionalSidecarTurns
    }

    func makeRootWave(
        triggerMessageId: UUID,
        transcriptBoundaryMessageId: UUID?,
        recipientSessionIds: [UUID]
    ) -> GroupWaveMetadata {
        let wave = GroupWaveMetadata(
            rootMessageId: rootMessageId,
            waveId: nextWaveId,
            triggerMessageId: triggerMessageId,
            transcriptBoundaryMessageId: transcriptBoundaryMessageId,
            recipientSessionIds: Set(recipientSessionIds)
        )
        nextWaveId += 1
        return wave
    }

    /// Reserves recipients for a peer-notify wave.
    ///
    /// Mentioned recipients bypass the additional-turn budget, but every
    /// `(target, trigger)` pair is still delivered at most once.
    func reservePeerWave(
        triggerMessageId: UUID,
        transcriptBoundaryMessageId: UUID?,
        candidateSessionIds: [UUID],
        prioritySessionIds: Set<UUID> = []
    ) -> GroupWaveMetadata? {
        var recipients: [UUID] = []

        for targetSessionId in candidateSessionIds {
            let key = "\(targetSessionId.uuidString)|\(triggerMessageId.uuidString)"
            guard !deliveredNotifyKeys.contains(key) else { continue }

            if prioritySessionIds.contains(targetSessionId) {
                deliveredNotifyKeys.insert(key)
                recipients.append(targetSessionId)
                continue
            }

            guard additionalTurnsRemaining > 0 else { continue }
            additionalTurnsRemaining -= 1
            deliveredNotifyKeys.insert(key)
            recipients.append(targetSessionId)
        }

        guard !recipients.isEmpty else { return nil }

        let wave = GroupWaveMetadata(
            rootMessageId: rootMessageId,
            waveId: nextWaveId,
            triggerMessageId: triggerMessageId,
            transcriptBoundaryMessageId: transcriptBoundaryMessageId,
            recipientSessionIds: Set(recipients)
        )
        nextWaveId += 1
        return wave
    }

    /// Returns IDs of silent-observer sessions that should receive transcript context.
    /// Budget impact: none. Deduplication: each (observer, trigger) pair delivered at most once.
    func reserveSilentObserverTranscript(
        triggerMessageId: UUID,
        silentObserverSessionIds: [UUID]
    ) -> [UUID] {
        var result: [UUID] = []
        for sessionId in silentObserverSessionIds {
            let key = "\(sessionId.uuidString)|\(triggerMessageId.uuidString)"
            guard !deliveredNotifyKeys.contains(key) else { continue }
            deliveredNotifyKeys.insert(key)
            result.append(sessionId)
        }
        return result
    }
}
