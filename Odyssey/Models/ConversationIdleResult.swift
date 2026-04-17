import Foundation

struct ConversationIdleResult: Equatable, Sendable {
    enum Status: String, Codable, Sendable {
        case complete
        case needsMore
        case failed
    }
    let status: Status
    let reason: String
}
