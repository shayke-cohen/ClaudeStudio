import Foundation

// MARK: - File-Backed Config DTOs
//
// These DTOs represent the on-disk JSON/markdown format for user-created file-backed entities.
// They are distinct from the bundled catalog-parsing DTOs in ConfigFileManager.swift:
//   - Catalog DTOs (AgentConfigDTO, GroupConfigDTO, MCPConfigDTO, …) parse Odyssey's
//     built-in bundle format (skillNames, mcpServerNames, permissionSetName, etc.).
//   - File-backed DTOs below (AgentConfigFileDTO, GroupConfigFileDTO, etc.) parse the
//     user-editable files under ~/.odyssey/config/ that reference other entities by slug.

// Note: these DTOs use camelCase JSON keys (Swift default). Files must use camelCase,
// not snake_case, for compound field names (e.g. "maxTurns", "autoReplyEnabled").

// MARK: AgentConfigFileDTO — mirrors agents/{slug}/config.json

struct AgentConfigFileDTO: Codable {
    var name: String
    var description: String?
    var model: String
    var provider: String?
    var resident: Bool?
    var icon: String?
    var color: String?
    var skills: [String]           // slugs → skills/{slug}.md
    var mcps: [String]             // slugs → mcps/{slug}.json
    var permissions: String?       // slug → permissions/{slug}.json
    var maxTurns: Int?
    var maxBudget: Double?
    var maxThinkingTokens: Int?
    var instancePolicy: String?    // "spawn" | "singleton" | "pool"
    var instancePolicyPoolMax: Int?
    var defaultWorkingDirectory: String?
    var isShared: Bool?
}

// MARK: GroupConfigFileDTO — mirrors groups/{slug}/config.json

struct GroupConfigFileDTO: Codable {
    var name: String
    var description: String?
    var agents: [String]           // slugs → agents/{slug}/
    var workingDirectory: String?
    var model: String?
    var mcps: [String]?              // slugs; omit or [] when group has no MCPs
    var icon: String?
    var color: String?
    var autoReplyEnabled: Bool?
    var autonomousCapable: Bool?
    var coordinator: String?       // agent slug
    var routingMode: String?       // "mentionAware" | "broad"
    var roles: [String: String]?   // agentSlug → roleName
}

// MARK: WorkflowStepFileDTO — one step in groups/{slug}/workflow.json array

struct WorkflowStepFileDTO: Codable {
    var id: String
    var agent: String              // agent slug
    var instruction: String
    var stepLabel: String?
    var autoAdvance: Bool?           // defaults to false when absent
    var condition: String?
    var artifactGate: WorkflowArtifactGateFileDTO?
}

struct WorkflowArtifactGateFileDTO: Codable {
    var profile: String
    var approvalRequired: Bool
    var publishRepoDoc: Bool
    var blockedDownstreamAgentNames: [String]
}

// MARK: SkillFileDTO — frontmatter of skills/{slug}.md

struct SkillFileDTO: Codable {
    var name: String
    var category: String?
    var triggers: [String]?
}

// MARK: MCPConfigFileDTO — mirrors mcps/{slug}.json
//
// Supports two on-disk transport encodings:
//   Flat (new user-config format):    "transport": "stdio", "command": "...", "args": [...]
//   Nested (catalog entry format):    "transport": { "kind": "stdio", "command": "...", "args": [...] }

struct MCPConfigFileDTO: Codable {
    var name: String
    var description: String?
    var transport: String          // "stdio" | "http"
    var command: String?
    var args: [String]?
    var env: [String: String]?
    var url: String?
    var headers: [String: String]?

    private enum CodingKeys: String, CodingKey {
        case name, description, transport, command, args, env, url, headers
    }

    private struct NestedTransport: Decodable {
        let kind: String
        let command: String?
        let args: [String]?
        let env: [String: String]?
        let url: String?
        let headers: [String: String]?
    }

    init(name: String, description: String? = nil, transport: String,
         command: String? = nil, args: [String]? = nil, env: [String: String]? = nil,
         url: String? = nil, headers: [String: String]? = nil) {
        self.name = name
        self.description = description
        self.transport = transport
        self.command = command
        self.args = args
        self.env = env
        self.url = url
        self.headers = headers
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        url = try c.decodeIfPresent(String.self, forKey: .url)
        headers = try c.decodeIfPresent([String: String].self, forKey: .headers)

        // Transport can be a plain string ("stdio") or a nested object ({ "kind": "stdio", ... })
        if let nested = try? c.decode(NestedTransport.self, forKey: .transport) {
            transport = nested.kind
            command = nested.command
            args = nested.args
            env = nested.env
            if url == nil { url = nested.url }
            if headers == nil { headers = nested.headers }
        } else {
            transport = try c.decode(String.self, forKey: .transport)
            command = try c.decodeIfPresent(String.self, forKey: .command)
            args = try c.decodeIfPresent([String].self, forKey: .args)
            env = try c.decodeIfPresent([String: String].self, forKey: .env)
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
        try c.encodeIfPresent(description, forKey: .description)
        try c.encode(transport, forKey: .transport)
        try c.encodeIfPresent(command, forKey: .command)
        try c.encodeIfPresent(args, forKey: .args)
        try c.encodeIfPresent(env, forKey: .env)
        try c.encodeIfPresent(url, forKey: .url)
        try c.encodeIfPresent(headers, forKey: .headers)
    }
}
