import Foundation
import SwiftData

/// Recommends the best agent team for a given task by analyzing agent descriptions.
@MainActor
final class GroupAssembler {

    struct AssemblyRecommendation {
        let agentIds: [UUID]
        let suggestedName: String
        let suggestedInstruction: String
        let reasoning: String
    }

    /// Local heuristic assembly — matches task keywords against agent descriptions.
    /// For a smarter version, this could call the sidecar to use Claude.
    static func assembleGroup(task: String, availableAgents: [Agent]) -> AssemblyRecommendation {
        let taskLower = task.lowercased()
        var scored: [(agent: Agent, score: Int)] = []

        for agent in availableAgents {
            var score = 0
            let desc = (agent.agentDescription + " " + agent.name + " " + agent.systemPrompt).lowercased()

            // Keyword matching against task
            let taskWords = taskLower.components(separatedBy: .whitespacesAndNewlines)
                .filter { $0.count > 3 }

            for word in taskWords {
                if desc.contains(word) { score += 1 }
            }

            // Boost for common roles
            if taskLower.contains("code") || taskLower.contains("implement") || taskLower.contains("build") {
                if desc.contains("code") || desc.contains("engineer") || desc.contains("implement") { score += 3 }
            }
            if taskLower.contains("review") || taskLower.contains("quality") {
                if desc.contains("review") || desc.contains("quality") { score += 3 }
            }
            if taskLower.contains("test") || taskLower.contains("qa") || taskLower.contains("bug") {
                if desc.contains("test") || desc.contains("validate") { score += 3 }
            }
            if taskLower.contains("design") || taskLower.contains("ux") || taskLower.contains("ui") {
                if desc.contains("design") || desc.contains("ux") || desc.contains("ui") { score += 3 }
            }
            if taskLower.contains("research") || taskLower.contains("analyze") || taskLower.contains("investigate") {
                if desc.contains("research") || desc.contains("analy") { score += 3 }
            }
            if taskLower.contains("plan") || taskLower.contains("coordinate") || taskLower.contains("manage") {
                if desc.contains("orchestrat") || desc.contains("coordinat") || desc.contains("product") { score += 3 }
            }
            if taskLower.contains("write") || taskLower.contains("document") || taskLower.contains("content") {
                if desc.contains("writ") || desc.contains("document") || desc.contains("content") { score += 3 }
            }
            if taskLower.contains("deploy") || taskLower.contains("infra") || taskLower.contains("ci") || taskLower.contains("devops") {
                if desc.contains("devops") || desc.contains("deploy") || desc.contains("infra") { score += 3 }
            }

            scored.append((agent: agent, score: score))
        }

        // Pick top agents (at least 2, at most 5)
        let sorted = scored.sorted { $0.score > $1.score }
        let threshold = max(1, sorted.first?.score ?? 1)
        let recommended = sorted.filter { $0.score >= threshold / 2 }.prefix(5)
        let selected = recommended.count >= 2 ? Array(recommended) : Array(sorted.prefix(3))

        let agentIds = selected.map(\.agent.id)
        let agentNames = selected.map(\.agent.name).joined(separator: ", ")

        let reasoning = selected.map { item in
            "\(item.agent.name) (score: \(item.score)): \(item.agent.agentDescription.prefix(80))"
        }.joined(separator: "\n")

        let firstWord = task.components(separatedBy: .whitespacesAndNewlines).first ?? "Team"
        let suggestedName = "\(firstWord.capitalized) Team"

        return AssemblyRecommendation(
            agentIds: agentIds,
            suggestedName: suggestedName,
            suggestedInstruction: "This group was assembled for the task: \(task)",
            reasoning: reasoning
        )
    }
}
