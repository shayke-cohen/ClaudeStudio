import Foundation
import SwiftData

enum PromptTemplateOwnerKind: String, Sendable, Hashable {
    case agent
    case group
}

@Model
final class PromptTemplate {
    var id: UUID
    var name: String
    var prompt: String
    var sortOrder: Int
    var isBuiltin: Bool
    var createdAt: Date
    var updatedAt: Date

    /// Disk identity: "<ownerKind-plural>/<ownerSlug>/<templateSlug>"
    /// e.g. "agents/coder/review-pr" or "groups/security-audit/full-codebase-audit".
    var configSlug: String?

    /// Exactly one of these is non-nil. Nullable relationships give us cascade delete.
    var agent: Agent?
    var group: AgentGroup?

    init(
        name: String,
        prompt: String,
        sortOrder: Int = 0,
        isBuiltin: Bool = false,
        agent: Agent? = nil,
        group: AgentGroup? = nil,
        configSlug: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.prompt = prompt
        self.sortOrder = sortOrder
        self.isBuiltin = isBuiltin
        self.agent = agent
        self.group = group
        self.configSlug = configSlug
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    @Transient
    var ownerKind: PromptTemplateOwnerKind? {
        if agent != nil { return .agent }
        if group != nil { return .group }
        return nil
    }

    @Transient
    var ownerSlugComponent: String? {
        guard let slug = configSlug else { return nil }
        let parts = slug.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return String(parts[1])
    }

    @Transient
    var templateSlugComponent: String? {
        guard let slug = configSlug else { return nil }
        let parts = slug.split(separator: "/")
        guard parts.count >= 3 else { return nil }
        return String(parts[2])
    }
}
