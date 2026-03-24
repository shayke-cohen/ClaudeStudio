import Foundation

struct WorkflowStep: Codable, Sendable, Identifiable {
    var id: UUID = UUID()
    var agentId: UUID
    var instruction: String
    var condition: String?
    var autoAdvance: Bool
    var stepLabel: String?
}
