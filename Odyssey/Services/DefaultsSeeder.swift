import Foundation
import OSLog
import SwiftData

enum DefaultsSeeder {

    static let seededKey = "odyssey.defaultsSeeded"

    static func seedIfNeeded(container: ModelContainer) {
        guard !InstanceConfig.userDefaults.bool(forKey: seededKey) else { return }

        let context = ModelContext(container)
        let permCount = (try? context.fetchCount(FetchDescriptor<PermissionSet>())) ?? 0
        if permCount > 0 { return }

        Log.seeder.info("First launch — seeding defaults")

        let permissions = seedPermissionPresets(into: context)
        let mcpServers = seedMCPServers(into: context)
        let skills = seedSkills(into: context)
        let templates = loadSystemPromptTemplates()
        seedAgents(into: context, permissions: permissions, mcpServers: mcpServers, skills: skills, templates: templates)

        do {
            try context.save()
            InstanceConfig.userDefaults.set(true, forKey: seededKey)
            Log.seeder.info("Seeding complete")
        } catch {
            Log.seeder.error("Failed to save: \(error)")
        }
    }

    // MARK: - Group Seeding

    static let groupsSeededKey = "odyssey.groupsSeeded"

    static func seedGroupsIfNeeded(container: ModelContainer) {
        guard !InstanceConfig.userDefaults.bool(forKey: groupsSeededKey) else { return }

        let context = ModelContext(container)
        let groupCount = (try? context.fetchCount(FetchDescriptor<AgentGroup>())) ?? 0
        if groupCount > 0 {
            InstanceConfig.userDefaults.set(true, forKey: groupsSeededKey)
            return
        }

        Log.seeder.info("Seeding default groups")
        seedGroups(into: context)

        do {
            try context.save()
            InstanceConfig.userDefaults.set(true, forKey: groupsSeededKey)
            Log.seeder.info("Groups seeding complete")
        } catch {
            Log.seeder.error("Failed to save groups: \(error)")
        }
    }

    private static func seedGroups(into context: ModelContext) {
        let agents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        let agentIdByName: [String: UUID] = Dictionary(
            uniqueKeysWithValues: agents.map { ($0.name, $0.id) }
        )

        func ids(_ names: [String]) -> [UUID] {
            names.compactMap { agentIdByName[$0] }
        }

        struct GroupSpec {
            let name: String
            let description: String
            let icon: String
            let color: String
            let instruction: String
            let defaultMission: String?
            let agentNames: [String]
            let sortOrder: Int
            var workflowAgentNames: [(agent: String, instruction: String, label: String, autoAdvance: Bool, condition: String?, artifactGate: WorkflowArtifactGate?)] = []
            var roles: [String: String] = [:]  // agentName -> role
            var autonomousCapable: Bool = false
            var coordinatorAgentName: String? = nil
        }

        let specs: [GroupSpec] = [
            GroupSpec(
                name: "Dev Squad",
                description: "Core engineering trio for most coding tasks.",
                icon: "⚙️", color: "blue",
                instruction: "This is a software engineering group. Prioritize clean, tested, reviewed code. The Coder implements, the Reviewer critiques, the Tester validates.",
                defaultMission: nil,
                agentNames: ["Coder", "Reviewer", "Tester"],
                sortOrder: 0,
                workflowAgentNames: [
                    (agent: "Coder", instruction: "Implement the requested changes. Write clean, well-structured code.", label: "Implement", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Reviewer", instruction: "Review the code from the previous step. Check for bugs, style issues, and architectural concerns. List any changes needed.", label: "Review", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Tester", instruction: "Write and run tests for the implementation. Verify the code works correctly and edge cases are covered.", label: "Test", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            ),
            GroupSpec(
                name: "Full Stack Team",
                description: "Complete engineering team with DevOps.",
                icon: "🏗️", color: "purple",
                instruction: "This is a full-stack engineering team. Coder builds, Reviewer ensures quality, Tester validates, DevOps handles infrastructure and deployment.",
                defaultMission: nil,
                agentNames: ["Coder", "Reviewer", "Tester", "DevOps"],
                sortOrder: 2,
                workflowAgentNames: [
                    (agent: "Coder", instruction: "Implement the feature or fix.", label: "Implement", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Reviewer", instruction: "Review code quality, architecture, and correctness.", label: "Review", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Tester", instruction: "Write tests and validate the implementation. Present a signoff summary with risks and evidence before deployment continues.", label: "Test", autoAdvance: true, condition: nil, artifactGate: WorkflowArtifactGate(profile: "test-signoff", approvalRequired: true, publishRepoDoc: false, blockedDownstreamAgentNames: ["DevOps"])),
                    (agent: "DevOps", instruction: "Prepare deployment: update configs, CI/CD pipelines, and infrastructure as needed.", label: "Deploy", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            ),
            GroupSpec(
                name: "DevOps Pipeline",
                description: "Build, test, deploy pipeline specialists.",
                icon: "🚀", color: "orange",
                instruction: "This group focuses on CI/CD and infrastructure. Coordinate to deliver reliable builds and deployments. Coder writes pipeline code, Tester validates, DevOps deploys.",
                defaultMission: nil,
                agentNames: ["Coder", "Tester", "DevOps"],
                sortOrder: 3,
                workflowAgentNames: [
                    (agent: "Coder", instruction: "Write or update the pipeline code, scripts, or infrastructure config.", label: "Build", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Tester", instruction: "Validate the pipeline works correctly. Run smoke tests. Present a signoff summary before deployment continues.", label: "Validate", autoAdvance: true, condition: nil, artifactGate: WorkflowArtifactGate(profile: "test-signoff", approvalRequired: true, publishRepoDoc: false, blockedDownstreamAgentNames: ["DevOps"])),
                    (agent: "DevOps", instruction: "Deploy to the target environment. Verify health checks pass.", label: "Deploy", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            ),
            GroupSpec(
                name: "Security Audit",
                description: "Vulnerability analysis and hardening.",
                icon: "🔒", color: "red",
                instruction: "This group performs a security-focused review. Look for vulnerabilities, edge cases, and trust boundary violations. Coder identifies issues, Reviewer assesses risk, Tester writes exploit tests.",
                defaultMission: nil,
                agentNames: ["Coder", "Reviewer", "Tester"],
                sortOrder: 4,
                workflowAgentNames: [
                    (agent: "Coder", instruction: "Scan the codebase for security vulnerabilities: injection, auth issues, data exposure, dependency risks. List all findings.", label: "Scan", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Reviewer", instruction: "Assess the severity and risk of each finding. Prioritize by impact. Recommend mitigations.", label: "Assess", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Tester", instruction: "Write proof-of-concept tests that demonstrate each vulnerability. Verify mitigations work.", label: "Exploit Tests", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            ),
            GroupSpec(
                name: "Plan & Build",
                description: "Orchestrated implementation with QA.",
                icon: "📋", color: "indigo",
                instruction: "Orchestrator plans and coordinates the work, Coder implements each task, Tester validates the output. Follow the plan step by step.",
                defaultMission: nil,
                agentNames: ["Orchestrator", "Coder", "Tester"],
                sortOrder: 5,
                workflowAgentNames: [
                    (agent: "Orchestrator", instruction: "Break down the task into a step-by-step implementation plan. Present the plan in chat, persist it to the blackboard, and pause for explicit proceed before implementation begins.", label: "Plan", autoAdvance: true, condition: nil, artifactGate: WorkflowArtifactGate(profile: "implementation-plan", approvalRequired: false, publishRepoDoc: false, blockedDownstreamAgentNames: ["Coder"])),
                    (agent: "Coder", instruction: "Implement the plan from the previous step. Follow each step in order.", label: "Implement", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Tester", instruction: "Validate the implementation against the plan's acceptance criteria. Report pass/fail for each step.", label: "Validate", autoAdvance: false, condition: nil, artifactGate: nil),
                ],
                roles: ["Orchestrator": "coordinator"],
                autonomousCapable: true,
                coordinatorAgentName: "Orchestrator"
            ),
            GroupSpec(
                name: "Product Crew",
                description: "Discovery, research, and strategy.",
                icon: "🎯", color: "teal",
                instruction: "This is a product strategy group. PM defines goals and requirements, Researcher gathers insights and competitive analysis, Analyst interprets data and tracks metrics.",
                defaultMission: nil,
                agentNames: ["Product Manager", "Researcher", "Analyst"],
                sortOrder: 6,
                workflowAgentNames: [
                    (agent: "Researcher", instruction: "Research the topic: gather competitive insights, user needs, and market context.", label: "Research", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Analyst", instruction: "Analyze the research findings. Identify key metrics, trends, and data-driven insights.", label: "Analyze", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Product Manager", instruction: "Synthesize research and analysis into a product recommendation: goals, requirements, and success criteria.", label: "Recommend", autoAdvance: false, condition: nil, artifactGate: nil),
                ],
                roles: ["Product Manager": "coordinator"]
            ),
            GroupSpec(
                name: "PM + Dev",
                description: "Product planning to implementation.",
                icon: "🤝", color: "indigo",
                instruction: "PM defines requirements, Coder implements, Reviewer ensures quality, Tester validates the result. Bridge the gap between product vision and code.",
                defaultMission: nil,
                agentNames: ["Product Manager", "Coder", "Reviewer", "Tester"],
                sortOrder: 7,
                workflowAgentNames: [
                    (agent: "Product Manager", instruction: "Gather requirements, present a PRD and low-fidelity wireframes in chat, persist the draft artifacts to the blackboard, ask for approval, and only after approval hand off implementation.", label: "Product Spec", autoAdvance: false, condition: nil, artifactGate: WorkflowArtifactGate(profile: "product-spec", approvalRequired: true, publishRepoDoc: true, blockedDownstreamAgentNames: ["Coder"])),
                    (agent: "Coder", instruction: "Implement the requirements from the previous step.", label: "Implement", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Reviewer", instruction: "Review the implementation against the original requirements.", label: "Review", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Tester", instruction: "Test the implementation against the acceptance criteria. Report results.", label: "Test", autoAdvance: false, condition: nil, artifactGate: nil),
                ],
                roles: ["Product Manager": "coordinator"],
                autonomousCapable: true,
                coordinatorAgentName: "Product Manager"
            ),
            GroupSpec(
                name: "Content Studio",
                description: "Research, write, and review content.",
                icon: "✍️", color: "blue",
                instruction: "This is a content production group. Researcher gathers information and sources, Writer drafts content, Reviewer polishes and fact-checks.",
                defaultMission: nil,
                agentNames: ["Researcher", "Writer", "Reviewer"],
                sortOrder: 8,
                workflowAgentNames: [
                    (agent: "Researcher", instruction: "Research the topic thoroughly. Gather key facts, sources, and relevant context.", label: "Research", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Writer", instruction: "Draft the content using the research from the previous step. Write clearly and engagingly.", label: "Draft", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Reviewer", instruction: "Review the draft for accuracy, clarity, tone, and completeness. Suggest edits.", label: "Edit", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            ),
            GroupSpec(
                name: "Growth Team",
                description: "Data-driven growth and content.",
                icon: "📈", color: "green",
                instruction: "PM drives growth strategy, Analyst tracks metrics and identifies opportunities, Writer creates messaging and content. Focus on measurable growth outcomes.",
                defaultMission: nil,
                agentNames: ["Product Manager", "Analyst", "Writer"],
                sortOrder: 9,
                workflowAgentNames: [
                    (agent: "Product Manager", instruction: "Define the growth objective and strategy. What metric are we moving and how?", label: "Strategy", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Analyst", instruction: "Analyze current metrics and identify the highest-impact opportunities for the strategy.", label: "Analysis", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Writer", instruction: "Create the messaging, copy, or content needed to execute the growth strategy.", label: "Content", autoAdvance: false, condition: nil, artifactGate: nil),
                ],
                roles: ["Product Manager": "coordinator"]
            ),
            GroupSpec(
                name: "Design Review",
                description: "UX review with implementation awareness.",
                icon: "🎨", color: "pink",
                instruction: "Designer leads UX critique and evaluates usability, Coder evaluates implementation feasibility, Reviewer ensures consistency with existing patterns.",
                defaultMission: nil,
                agentNames: ["Designer", "Coder", "Reviewer"],
                sortOrder: 10,
                workflowAgentNames: [
                    (agent: "Designer", instruction: "Evaluate the UX/UI. Present a concise UX spec with flows or wireframes in chat, persist it to the blackboard, and wait for approval before feasibility or implementation continues.", label: "UX Review", autoAdvance: true, condition: nil, artifactGate: WorkflowArtifactGate(profile: "ux-spec", approvalRequired: true, publishRepoDoc: true, blockedDownstreamAgentNames: ["Coder"])),
                    (agent: "Coder", instruction: "Assess feasibility of the design recommendations. Note implementation complexity and trade-offs.", label: "Feasibility", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Reviewer", instruction: "Review for consistency with existing design patterns and code conventions. Final recommendation.", label: "Consistency", autoAdvance: false, condition: nil, artifactGate: nil),
                ]
            ),
            GroupSpec(
                name: "Dual Coder Debate",
                description: "Same problem, two models. Pick the best solution.",
                icon: "🥊", color: "blue",
                instruction: "Each coder proposes an independent solution using their respective model. The Reviewer compares both implementations and recommends the best approach or a synthesis of the two.",
                defaultMission: nil,
                agentNames: ["Coder (Codex)", "Coder", "Reviewer"],
                sortOrder: 11,
                workflowAgentNames: [
                    (agent: "Coder (Codex)", instruction: "Implement a solution to the task using your approach. Do not reference what the other Coder writes.", label: "Codex Solution", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Coder", instruction: "Implement a solution to the same task independently. Take your own approach without referencing the previous implementation.", label: "Claude Solution", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Reviewer", instruction: "Compare both implementations. Evaluate correctness, performance, readability, and maintainability. Recommend the best approach or a synthesis of the two.", label: "Judge", autoAdvance: false, condition: nil, artifactGate: nil),
                ],
                roles: ["Reviewer": "coordinator"]
            ),
            GroupSpec(
                name: "Codex Build + Claude Review",
                description: "OpenAI generates, Claude scrutinizes.",
                icon: "⚡", color: "orange",
                instruction: "Codex handles implementation for speed and code fluency. Claude Reviewer provides deep analysis and catches issues. Claude Tester writes comprehensive tests.",
                defaultMission: nil,
                agentNames: ["Coder (Codex)", "Reviewer", "Tester"],
                sortOrder: 12,
                workflowAgentNames: [
                    (agent: "Coder (Codex)", instruction: "Implement the requested feature or fix. Write complete, runnable code.", label: "Build", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Reviewer", instruction: "Review the Codex implementation thoroughly. Check for correctness, edge cases, security issues, and style. List all findings.", label: "Review", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Tester", instruction: "Write comprehensive tests targeting the implementation and the issues flagged by the Reviewer.", label: "Test", autoAdvance: false, condition: nil, artifactGate: nil),
                ],
                roles: ["Reviewer": "coordinator"]
            ),
            GroupSpec(
                name: "Cost-Tiered Squad",
                description: "Opus plans, Sonnet builds, Haiku tests. Max value per dollar.",
                icon: "💸", color: "green",
                instruction: "Use each model where it adds the most value: Orchestrator (Opus) for planning and synthesis, Coder (Sonnet) for implementation, Tester (Haiku) for fast validation. Minimize expensive model usage for routine tasks.",
                defaultMission: nil,
                agentNames: ["Orchestrator", "Coder (Sonnet)", "Tester (Haiku)"],
                sortOrder: 13,
                workflowAgentNames: [
                    (agent: "Orchestrator", instruction: "Break down the task into a clear implementation plan. Persist it to the blackboard. Delegate to Coder once the plan is ready.", label: "Plan", autoAdvance: true, condition: nil, artifactGate: WorkflowArtifactGate(profile: "implementation-plan", approvalRequired: false, publishRepoDoc: false, blockedDownstreamAgentNames: ["Coder (Sonnet)"])),
                    (agent: "Coder (Sonnet)", instruction: "Implement the plan from the previous step. Follow each step in order.", label: "Implement", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Tester (Haiku)", instruction: "Write and run tests to validate the implementation. Report pass/fail with a clear summary.", label: "Test", autoAdvance: false, condition: nil, artifactGate: nil),
                ],
                roles: ["Orchestrator": "coordinator"],
                autonomousCapable: true,
                coordinatorAgentName: "Orchestrator"
            ),
            GroupSpec(
                name: "Local First",
                description: "Draft on-device, review in cloud. Privacy-first workflow.",
                icon: "🔒", color: "gray",
                instruction: "Coder (Local) generates code entirely on-device — no data leaves your machine. Messages go to Coder (Local) by default. Use @Reviewer to explicitly route output to the cloud for review.",
                defaultMission: nil,
                agentNames: ["Coder (Local)", "Reviewer"],
                sortOrder: 14,
                roles: ["Coder (Local)": "coordinator"]
            ),
            GroupSpec(
                name: "Red Team",
                description: "Build it, then try to break it.",
                icon: "🎯", color: "red",
                instruction: "Coder builds the feature. Attacker immediately looks for ways to break, exploit, or bypass it. Tester formalizes findings as regression tests. Expect adversarial feedback — that is the point.",
                defaultMission: nil,
                agentNames: ["Coder", "Attacker", "Tester"],
                sortOrder: 15,
                workflowAgentNames: [
                    (agent: "Coder", instruction: "Implement the requested feature or component. Write production-quality code.", label: "Build", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Attacker", instruction: "Try to break the implementation. Look for vulnerabilities, edge cases, auth bypasses, injection points, and logical flaws. Be adversarial. Report all findings.", label: "Attack", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Tester", instruction: "Convert the Attacker's findings into regression tests. Each finding should become a test that validates the implementation is hardened against it.", label: "Harden", autoAdvance: false, condition: nil, artifactGate: nil),
                ],
                roles: ["Attacker": "coordinator"]
            ),
            GroupSpec(
                name: "Security & Perf Audit",
                description: "Audit for security and performance issues, then fix them.",
                icon: "🔍", color: "red",
                instruction: "Reviewer audits for security vulnerabilities. Performance agent audits for bottlenecks. Orchestrator synthesizes findings into a prioritized fix plan. Coder implements the fixes.",
                defaultMission: nil,
                agentNames: ["Reviewer", "Performance", "Orchestrator", "Coder"],
                sortOrder: 16,
                workflowAgentNames: [
                    (agent: "Reviewer", instruction: "Audit the codebase for security vulnerabilities: injection points, auth bypasses, data exposure, insecure defaults, and logical flaws. Write all findings to the blackboard under review.security.{component}. Mark critical findings as review.security.{component}.blocking = true.", label: "Security Audit", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Performance", instruction: "Audit the codebase for performance issues: algorithmic complexity, memory leaks, actor contention, SwiftUI rendering inefficiencies, and blocking I/O. Write all findings to the blackboard under perf.{component}.{finding}. Mark critical findings as perf.{component}.critical = true.", label: "Perf Audit", autoAdvance: true, condition: nil, artifactGate: nil),
                    (agent: "Orchestrator", instruction: "Read all security (review.security.*) and performance (perf.*) findings from the blackboard. Synthesize them into a prioritized fix plan ordered by severity and impact. Present the plan in chat, persist it to the blackboard under audit.fix-plan, and pause for explicit approval before Coder begins.", label: "Prioritize", autoAdvance: true, condition: nil, artifactGate: WorkflowArtifactGate(profile: "audit-report", approvalRequired: true, publishRepoDoc: true, blockedDownstreamAgentNames: ["Coder"])),
                    (agent: "Coder", instruction: "Implement the fixes from the audit fix plan. Address items in priority order. For each fix, note which finding it resolves.", label: "Fix", autoAdvance: false, condition: nil, artifactGate: nil),
                ],
                roles: ["Orchestrator": "coordinator"],
                autonomousCapable: true,
                coordinatorAgentName: "Orchestrator"
            ),
        ]

        for spec in specs {
            let group = AgentGroup(
                name: spec.name,
                groupDescription: spec.description,
                icon: spec.icon,
                color: spec.color,
                groupInstruction: spec.instruction,
                defaultMission: spec.defaultMission,
                agentIds: ids(spec.agentNames),
                sortOrder: spec.sortOrder
            )
            group.origin = .builtin

            // Workflow
            if !spec.workflowAgentNames.isEmpty {
                group.workflow = spec.workflowAgentNames.map { step in
                    WorkflowStep(
                        agentId: agentIdByName[step.agent] ?? UUID(),
                        instruction: step.instruction,
                        condition: step.condition,
                        autoAdvance: step.autoAdvance,
                        stepLabel: step.label,
                        artifactGate: step.artifactGate
                    )
                }
            }

            // Roles
            if !spec.roles.isEmpty {
                var roleMap: [UUID: String] = [:]
                for (agentName, role) in spec.roles {
                    if let aid = agentIdByName[agentName] {
                        roleMap[aid] = role
                    }
                }
                group.agentRoles = roleMap
            }

            // Autonomous
            group.autonomousCapable = spec.autonomousCapable
            if let coordName = spec.coordinatorAgentName {
                group.coordinatorAgentId = agentIdByName[coordName]
            }

            context.insert(group)
            let wfCount = spec.workflowAgentNames.count
            let extras = [
                wfCount > 0 ? "\(wfCount)-step workflow" : nil,
                spec.autonomousCapable ? "autonomous" : nil,
                !spec.roles.isEmpty ? "roles" : nil,
            ].compactMap { $0 }.joined(separator: ", ")
            let suffix = extras.isEmpty ? "" : " [\(extras)]"
            Log.seeder.info("Group: \(spec.name, privacy: .public) (\(spec.agentNames.count) agents)\(suffix, privacy: .public)")
        }
    }

    // MARK: - Permission Presets

    @discardableResult
    private static func seedPermissionPresets(into context: ModelContext) -> [String: PermissionSet] {
        guard let data = loadResource(name: "DefaultPermissionPresets", ext: "json") else {
            Log.seeder.error("DefaultPermissionPresets.json not found")
            return [:]
        }

        struct PresetDTO: Decodable {
            let name: String
            let allowRules: [String]
            let denyRules: [String]
            let additionalDirectories: [String]
            let permissionMode: String
        }

        guard let dtos = try? JSONDecoder().decode([PresetDTO].self, from: data) else {
            Log.seeder.error("Failed to decode permission presets")
            return [:]
        }

        var map: [String: PermissionSet] = [:]
        for dto in dtos {
            let ps = PermissionSet(
                name: dto.name,
                allowRules: dto.allowRules,
                denyRules: dto.denyRules,
                permissionMode: dto.permissionMode
            )
            ps.additionalDirectories = dto.additionalDirectories
            context.insert(ps)
            map[dto.name] = ps
            Log.seeder.debug("Permission preset: \(dto.name, privacy: .public)")
        }
        return map
    }

    // MARK: - MCP Servers

    private static func seedMCPServers(into context: ModelContext) -> [String: MCPServer] {
        guard let data = loadResource(name: "DefaultMCPs", ext: "json") else {
            Log.seeder.error("DefaultMCPs.json not found")
            return [:]
        }

        struct MCPDTO: Decodable {
            let name: String
            let serverDescription: String
            let transportKind: String
            let transportCommand: String?
            let transportArgs: [String]?
            let transportEnv: [String: String]?
            let transportUrl: String?
            let transportHeaders: [String: String]?
        }

        guard let dtos = try? JSONDecoder().decode([MCPDTO].self, from: data) else {
            Log.seeder.error("Failed to decode MCP servers")
            return [:]
        }

        var map: [String: MCPServer] = [:]
        for dto in dtos {
            let transport: MCPTransport
            if dto.transportKind == "stdio" {
                transport = .stdio(
                    command: dto.transportCommand ?? "",
                    args: dto.transportArgs ?? [],
                    env: dto.transportEnv ?? [:]
                )
            } else {
                transport = .http(
                    url: dto.transportUrl ?? "",
                    headers: dto.transportHeaders ?? [:]
                )
            }
            let server = MCPServer(name: dto.name, serverDescription: dto.serverDescription, transport: transport)
            context.insert(server)
            map[dto.name] = server
            Log.seeder.debug("MCP server: \(dto.name, privacy: .public)")
        }
        return map
    }

    // MARK: - Incremental Skill Seeding

    /// Ensures newly added builtin skills are inserted into existing databases.
    /// Runs on every launch — compares the canonical skill list against what's in SwiftData.
    static func ensureNewSkills(container: ModelContainer) {
        let context = ModelContext(container)
        let existingSkills = (try? context.fetch(FetchDescriptor<Skill>())) ?? []
        let existingNames = Set(existingSkills.map(\.name))

        let allSkillNames = [
            "peer-collaboration",
            "blackboard-patterns",
            "delegation-patterns",
            "workspace-collaboration",
            "agent-identity",
            "artifact-handoff-gate",
            "product-artifact-gate",
            "config-editing",
            "github-workflow"
        ]

        let missingNames = allSkillNames.filter { !existingNames.contains($0) }
        guard !missingNames.isEmpty else { return }

        Log.seeder.info("Incremental skill seeding: adding \(missingNames.count) new skill(s): \(missingNames.joined(separator: ", "), privacy: .public)")

        var newSkills: [String: Skill] = [:]
        for skillName in missingNames {
            guard let content = loadSkillContent(name: skillName) else {
                Log.seeder.warning("Skill not found: \(skillName, privacy: .public)")
                continue
            }
            let metadata = parseSkillFrontmatter(content)
            let skill = Skill(
                name: metadata.name ?? skillName,
                skillDescription: metadata.description ?? "",
                category: metadata.category ?? "Odyssey",
                content: content
            )
            skill.triggers = metadata.triggers
            skill.source = .builtin
            context.insert(skill)
            newSkills[skillName] = skill
            Log.seeder.info("Seeded new skill: \(skillName, privacy: .public)")
        }

        // Attach new skills to agents that reference them
        let agents = (try? context.fetch(FetchDescriptor<Agent>())) ?? []
        for (skillName, skill) in newSkills {
            let agentsNeedingSkill = agentNamesForSkill(skillName)
            for agent in agents where agentsNeedingSkill.contains(agent.name) {
                if !agent.skillIds.contains(skill.id) {
                    agent.skillIds.append(skill.id)
                    Log.seeder.info("Attached \(skillName, privacy: .public) to agent \(agent.name, privacy: .public)")
                }
            }
        }

        do {
            try context.save()
            Log.seeder.info("Incremental skill seeding complete")
        } catch {
            Log.seeder.error("Failed to save incremental skills: \(error)")
        }
    }

    /// Maps skill names to the agent names that should have them.
    private static func agentNamesForSkill(_ skillName: String) -> Set<String> {
        switch skillName {
        case "artifact-handoff-gate":
            return [
                "API Designer",
                "Analyst",
                "Coder",
                "Coder (Codex)",
                "Coder (Sonnet)",
                "Designer",
                "DevOps",
                "Documentation Lead",
                "Orchestrator",
                "Product Manager",
                "Release Manager",
                "Researcher",
                "Reviewer",
                "Technical Lead",
                "Technical Writer",
                "Tester",
                "Tester (Haiku)",
                "UX Designer",
                "Writer"
            ]
        case "product-artifact-gate":
            return ["Product Manager"]
        case "github-workflow":
            return ["Coder", "Coder (Codex)", "Coder (Sonnet)", "Reviewer", "DevOps", "Product Manager", "Orchestrator", "Release Manager", "Tester", "Tester (Haiku)"]
        case "peer-collaboration", "blackboard-patterns", "agent-identity":
            return ["Coder", "Coder (Codex)", "Coder (Sonnet)", "Attacker", "Reviewer", "DevOps", "Product Manager", "Orchestrator", "Tester", "Tester (Haiku)", "Researcher", "Writer", "Designer", "Analyst"]
        default:
            return []
        }
    }

    // MARK: - Skills

    private static func seedSkills(into context: ModelContext) -> [String: Skill] {
        let skillNames = [
            "peer-collaboration",
            "blackboard-patterns",
            "delegation-patterns",
            "workspace-collaboration",
            "agent-identity",
            "artifact-handoff-gate",
            "product-artifact-gate",
            "config-editing",
            "github-workflow",
            "task-board-patterns",
            "personal-context"
        ]

        var map: [String: Skill] = [:]
        for skillName in skillNames {
            guard let content = loadSkillContent(name: skillName) else {
                Log.seeder.warning("Skill not found: \(skillName, privacy: .public)")
                continue
            }

            let metadata = parseSkillFrontmatter(content)
            let skill = Skill(
                name: metadata.name ?? skillName,
                skillDescription: metadata.description ?? "",
                category: metadata.category ?? "Odyssey",
                content: content
            )
            skill.triggers = metadata.triggers
            skill.source = .builtin
            context.insert(skill)
            map[skillName] = skill
            Log.seeder.debug("Skill: \(skillName, privacy: .public)")
        }
        if map["github-workflow"] != nil {
            Log.seeder.info("github-workflow skill loaded successfully")
        } else {
            Log.seeder.error("github-workflow skill FAILED to load — check DefaultSkills/github-workflow/SKILL.md")
        }
        return map
    }

    // MARK: - System Prompt Templates

    private static func loadSystemPromptTemplates() -> [String: String] {
        let templateNames = ["specialist", "worker", "coordinator"]
        var templates: [String: String] = [:]
        for name in templateNames {
            if let content = loadTemplateContent(name: name) {
                templates[name] = content
                Log.seeder.debug("Template loaded: \(name, privacy: .public)")
            } else {
                Log.seeder.warning("Template not found: \(name, privacy: .public)")
            }
        }
        return templates
    }

    // MARK: - Agents

    private static func seedAgents(
        into context: ModelContext,
        permissions: [String: PermissionSet],
        mcpServers: [String: MCPServer],
        skills: [String: Skill],
        templates: [String: String]
    ) {
        let agentFiles = ["orchestrator", "coder", "reviewer", "researcher", "tester", "devops", "writer", "product-manager", "analyst", "designer", "config-agent", "friday", "coder-codex", "attacker-codex", "coder-sonnet", "tester-haiku", "coder-local"]

        for fileName in agentFiles {
            guard let data = loadAgentResource(name: fileName) else {
                Log.seeder.warning("Agent JSON not found: \(fileName, privacy: .public)")
                continue
            }

            guard let dto = try? JSONDecoder().decode(AgentDTO.self, from: data) else {
                Log.seeder.error("Failed to decode agent: \(fileName, privacy: .public)")
                continue
            }

            let systemPrompt = resolveSystemPrompt(dto: dto, templates: templates)
            let agent = Agent(
                name: dto.name,
                agentDescription: dto.agentDescription,
                systemPrompt: systemPrompt,
                provider: dto.provider ?? ProviderSelection.system.rawValue,
                model: dto.model,
                icon: dto.icon,
                color: dto.color
            )

            agent.maxTurns = dto.maxTurns
            agent.maxBudget = dto.maxBudget
            if let policyRaw = dto.instancePolicy,
               let policy = AgentInstancePolicy(rawValue: policyRaw) {
                agent.instancePolicy = policy
            }
            agent.defaultWorkingDirectory = dto.defaultWorkingDirectory
            agent.origin = .builtin

            agent.skillIds = dto.skillNames.compactMap { skills[$0]?.id }
            agent.extraMCPServerIds = dto.mcpServerNames.compactMap { mcpServers[$0]?.id }
            if let ps = permissions[dto.permissionSetName] {
                agent.permissionSetId = ps.id
            }

            context.insert(agent)
            Log.seeder.debug("Agent: \(dto.name, privacy: .public) (skills: \(agent.skillIds.count), MCPs: \(agent.extraMCPServerIds.count))")
        }
    }

    // MARK: - Template Resolution

    private static func resolveSystemPrompt(dto: AgentDTO, templates: [String: String]) -> String {
        guard let templateName = dto.systemPromptTemplate,
              let template = templates[templateName] else {
            return ""
        }

        var prompt = template
        for (key, value) in dto.systemPromptVariables ?? [:] {
            prompt = prompt.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        prompt = prompt.replacingOccurrences(of: "{{constraints}}", with: "")
        prompt = prompt.replacingOccurrences(of: "{{polling_interval}}", with: "30000")
        return prompt
    }

    // MARK: - DTOs

    private struct AgentDTO: Decodable {
        let name: String
        let agentDescription: String
        let provider: String?
        let model: String
        let icon: String
        let color: String
        let skillNames: [String]
        let mcpServerNames: [String]
        let permissionSetName: String
        let systemPromptTemplate: String?
        let systemPromptVariables: [String: String]?
        let maxTurns: Int?
        let maxBudget: Double?
        let instancePolicy: String?
        let defaultWorkingDirectory: String?
    }

    private struct SkillFrontmatter {
        var name: String?
        var description: String?
        var category: String?
        var triggers: [String] = []
    }

    // MARK: - Frontmatter Parsing

    private static func parseSkillFrontmatter(_ content: String) -> SkillFrontmatter {
        var fm = SkillFrontmatter()
        guard content.hasPrefix("---") else { return fm }
        let parts = content.components(separatedBy: "---")
        guard parts.count >= 3 else { return fm }
        let yaml = parts[1]

        for line in yaml.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("name:") {
                fm.name = trimmed.dropFirst(5).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("description:") {
                fm.description = trimmed.dropFirst(12).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("category:") {
                fm.category = trimmed.dropFirst(9).trimmingCharacters(in: .whitespaces)
            } else if trimmed.hasPrefix("- ") && !trimmed.contains(":") {
                fm.triggers.append(trimmed.dropFirst(2).trimmingCharacters(in: .whitespaces))
            }
        }
        return fm
    }

    // MARK: - Resource Loading

    private static func loadResource(name: String, ext: String) -> Data? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return try? Data(contentsOf: url)
        }
        let fallbackPaths = [
            "\(NSHomeDirectory())/Odyssey/Odyssey/Resources/\(name).\(ext)",
            "\(FileManager.default.currentDirectoryPath)/Odyssey/Resources/\(name).\(ext)"
        ]
        for path in fallbackPaths {
            if FileManager.default.fileExists(atPath: path) {
                return try? Data(contentsOf: URL(fileURLWithPath: path))
            }
        }
        return nil
    }

    private static func loadSkillContent(name: String) -> String? {
        if let url = Bundle.main.url(forResource: "SKILL", withExtension: "md", subdirectory: "DefaultSkills/\(name)") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        if let resourceURL = Bundle.main.resourceURL {
            let url = resourceURL.appendingPathComponent("DefaultSkills/\(name)/SKILL.md")
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        let fallbackPaths = [
            "\(NSHomeDirectory())/Odyssey/Odyssey/Resources/DefaultSkills/\(name)/SKILL.md",
            "\(FileManager.default.currentDirectoryPath)/Odyssey/Resources/DefaultSkills/\(name)/SKILL.md"
        ]
        for path in fallbackPaths {
            if FileManager.default.fileExists(atPath: path) {
                return try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            }
        }
        return nil
    }

    private static func loadAgentResource(name: String) -> Data? {
        // Try subdirectory lookup first (works with group references)
        if let url = Bundle.main.url(forResource: name, withExtension: "json", subdirectory: "DefaultAgents") {
            return try? Data(contentsOf: url)
        }
        // Try direct path in bundle resources (works with folder references)
        if let resourceURL = Bundle.main.resourceURL {
            let url = resourceURL.appendingPathComponent("DefaultAgents/\(name).json")
            if let data = try? Data(contentsOf: url) {
                return data
            }
        }
        let fallbackPaths = [
            "\(NSHomeDirectory())/Odyssey/Odyssey/Resources/DefaultAgents/\(name).json",
            "\(FileManager.default.currentDirectoryPath)/Odyssey/Resources/DefaultAgents/\(name).json"
        ]
        for path in fallbackPaths {
            if FileManager.default.fileExists(atPath: path) {
                return try? Data(contentsOf: URL(fileURLWithPath: path))
            }
        }
        return nil
    }

    private static func loadTemplateContent(name: String) -> String? {
        if let url = Bundle.main.url(forResource: name, withExtension: "md", subdirectory: "SystemPromptTemplates") {
            return try? String(contentsOf: url, encoding: .utf8)
        }
        if let resourceURL = Bundle.main.resourceURL {
            let url = resourceURL.appendingPathComponent("SystemPromptTemplates/\(name).md")
            if let content = try? String(contentsOf: url, encoding: .utf8) {
                return content
            }
        }
        let fallbackPaths = [
            "\(NSHomeDirectory())/Odyssey/Odyssey/Resources/SystemPromptTemplates/\(name).md",
            "\(FileManager.default.currentDirectoryPath)/Odyssey/Resources/SystemPromptTemplates/\(name).md"
        ]
        for path in fallbackPaths {
            if FileManager.default.fileExists(atPath: path) {
                return try? String(contentsOf: URL(fileURLWithPath: path), encoding: .utf8)
            }
        }
        return nil
    }
}
