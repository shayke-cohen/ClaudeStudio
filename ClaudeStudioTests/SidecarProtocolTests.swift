import XCTest
@testable import ClaudeStudio

final class SidecarProtocolTests: XCTestCase {

    // MARK: - Command Encoding

    func testDelegateTaskEncoding() throws {
        let command = SidecarCommand.delegateTask(
            sessionId: "conv-123",
            toAgent: "Coder",
            task: "implement login",
            context: "Use OAuth 2.0",
            waitForResult: true
        )
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "delegate.task")
        XCTAssertEqual(json["sessionId"] as? String, "conv-123")
        XCTAssertEqual(json["toAgent"] as? String, "Coder")
        XCTAssertEqual(json["task"] as? String, "implement login")
        XCTAssertEqual(json["context"] as? String, "Use OAuth 2.0")
        XCTAssertEqual(json["waitForResult"] as? Bool, true)
    }

    func testSessionCreateEncoding() throws {
        let config = AgentConfig(
            name: "TestBot",
            systemPrompt: "Say hi",
            allowedTools: ["Read"],
            mcpServers: [
                AgentConfig.MCPServerConfig(name: "Octocode", command: "npx", args: ["-y", "octocode-mcp"], env: ["DEBUG": "1"], url: nil),
            ],
            provider: "codex",
            model: "gpt-5-codex",
            maxTurns: 5,
            maxBudget: nil,
            maxThinkingTokens: nil,
            workingDirectory: "/tmp",
            skills: [
                AgentConfig.SkillContent(name: "Skill A", content: "Follow the skill."),
            ]
        )
        let command = SidecarCommand.sessionCreate(conversationId: "conv-456", agentConfig: config)
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "session.create")
        XCTAssertEqual(json["conversationId"] as? String, "conv-456")
        let agentConfig = json["agentConfig"] as? [String: Any]
        XCTAssertEqual(agentConfig?["name"] as? String, "TestBot")
        XCTAssertEqual(agentConfig?["provider"] as? String, "codex")
        XCTAssertEqual(agentConfig?["model"] as? String, "gpt-5-codex")
        let mcpServers = try XCTUnwrap(agentConfig?["mcpServers"] as? [[String: Any]])
        XCTAssertEqual(mcpServers.count, 1)
        XCTAssertEqual(mcpServers[0]["name"] as? String, "Octocode")
        let skills = try XCTUnwrap(agentConfig?["skills"] as? [[String: Any]])
        XCTAssertEqual(skills.count, 1)
        XCTAssertEqual(skills[0]["name"] as? String, "Skill A")
        XCTAssertEqual(skills[0]["content"] as? String, "Follow the skill.")
    }

    func testAgentRegisterEncodingPreservesStructuredSkillsAndMCPs() throws {
        let config = AgentConfig(
            name: "Worker",
            systemPrompt: "Base prompt",
            allowedTools: ["Read", "Write"],
            mcpServers: [
                AgentConfig.MCPServerConfig(name: "AppXray", command: "npx", args: ["-y", "@wix/appxray-mcp-server"], env: nil, url: nil),
                AgentConfig.MCPServerConfig(name: "Octocode", command: "npx", args: ["-y", "octocode-mcp"], env: nil, url: nil),
            ],
            provider: "claude",
            model: "claude-sonnet-4-6",
            maxTurns: 3,
            maxBudget: nil,
            maxThinkingTokens: nil,
            workingDirectory: "/tmp/worker",
            skills: [
                AgentConfig.SkillContent(name: "Review", content: "Review carefully."),
                AgentConfig.SkillContent(name: "Test", content: "Test thoroughly."),
            ]
        )

        let command = SidecarCommand.agentRegister(agents: [
            AgentDefinitionWire(name: "Worker", config: config),
        ])
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "agent.register")
        let agents = try XCTUnwrap(json["agents"] as? [[String: Any]])
        XCTAssertEqual(agents.count, 1)
        let encodedConfig = try XCTUnwrap(agents[0]["config"] as? [String: Any])
        XCTAssertEqual(encodedConfig["systemPrompt"] as? String, "Base prompt")
        let skills = try XCTUnwrap(encodedConfig["skills"] as? [[String: Any]])
        XCTAssertEqual(skills.map { $0["name"] as? String }, ["Review", "Test"])
        let mcps = try XCTUnwrap(encodedConfig["mcpServers"] as? [[String: Any]])
        XCTAssertEqual(mcps.map { $0["name"] as? String }, ["AppXray", "Octocode"])
    }

    func testSessionMessageEncoding() throws {
        let command = SidecarCommand.sessionMessage(sessionId: "sess-789", text: "Hello agent")
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "session.message")
        XCTAssertEqual(json["sessionId"] as? String, "sess-789")
        XCTAssertEqual(json["text"] as? String, "Hello agent")
    }

    func testSessionBulkResumeEncoding() throws {
        let config = AgentConfig(
            name: "RecoveryBot",
            systemPrompt: "Resume safely",
            allowedTools: ["Read"],
            mcpServers: [],
            provider: "codex",
            model: "gpt-5-codex",
            maxTurns: 5,
            maxBudget: 1.5,
            maxThinkingTokens: 8000,
            workingDirectory: "/tmp/recovery",
            skills: []
        )
        let command = SidecarCommand.sessionBulkResume(sessions: [
            SessionBulkResumeEntry(
                sessionId: "session-a",
                claudeSessionId: "claude-a",
                agentConfig: config
            ),
            SessionBulkResumeEntry(
                sessionId: "session-b",
                claudeSessionId: "claude-b",
                agentConfig: config
            ),
        ])

        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "session.bulkResume")
        let sessions = try XCTUnwrap(json["sessions"] as? [[String: Any]])
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0]["sessionId"] as? String, "session-a")
        XCTAssertEqual(sessions[0]["claudeSessionId"] as? String, "claude-a")
        let firstConfig = try XCTUnwrap(sessions[0]["agentConfig"] as? [String: Any])
        XCTAssertEqual(firstConfig["name"] as? String, "RecoveryBot")
        XCTAssertEqual(firstConfig["provider"] as? String, "codex")
        XCTAssertEqual(firstConfig["workingDirectory"] as? String, "/tmp/recovery")
    }

    func testSessionForkEncoding() throws {
        let command = SidecarCommand.sessionFork(parentSessionId: "parent-1", childSessionId: "child-2")
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "session.fork")
        XCTAssertEqual(json["sessionId"] as? String, "parent-1")
        XCTAssertEqual(json["childSessionId"] as? String, "child-2")
    }

    func testSessionForkedDecoding() throws {
        let jsonStr = """
        {"type":"session.forked","parentSessionId":"p1","childSessionId":"c2"}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .sessionForked(let p, let c) = event {
            XCTAssertEqual(p, "p1")
            XCTAssertEqual(c, "c2")
        } else {
            XCTFail("Expected .sessionForked, got \(String(describing: event))")
        }
    }

    // MARK: - Incoming Wire Message Decoding

    func testPeerChatDecoding() throws {
        let jsonStr = """
        {"type":"peer.chat","sessionId":"sess-1","channelId":"ch-1","from":"AgentA","message":"discuss design"}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .peerChat(let sessionId, let channelId, let from, let message) = event {
            XCTAssertEqual(sessionId, "sess-1")
            XCTAssertEqual(channelId, "ch-1")
            XCTAssertEqual(from, "AgentA")
            XCTAssertEqual(message, "discuss design")
        } else {
            XCTFail("Expected .peerChat event, got \(String(describing: event))")
        }
    }

    func testPeerDelegateDecoding() throws {
        let jsonStr = """
        {"type":"peer.delegate","sessionId":"sess-2","from":"Orchestrator","to":"Coder","text":"implement feature"}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .peerDelegate(let sessionId, let from, let to, let task) = event {
            XCTAssertEqual(sessionId, "sess-2")
            XCTAssertEqual(from, "Orchestrator")
            XCTAssertEqual(to, "Coder")
            XCTAssertEqual(task, "implement feature")
        } else {
            XCTFail("Expected .peerDelegate event, got \(String(describing: event))")
        }
    }

    func testBlackboardUpdateDecoding() throws {
        let jsonStr = """
        {"type":"blackboard.update","sessionId":"sess-3","key":"pipeline.phase","value":"research","writtenBy":"Orchestrator"}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .blackboardUpdate(let sessionId, let key, let value, let writtenBy) = event {
            XCTAssertEqual(sessionId, "sess-3")
            XCTAssertEqual(key, "pipeline.phase")
            XCTAssertEqual(value, "research")
            XCTAssertEqual(writtenBy, "Orchestrator")
        } else {
            XCTFail("Expected .blackboardUpdate event, got \(String(describing: event))")
        }
    }

    func testUnknownTypeReturnsNil() throws {
        let jsonStr = """
        {"type":"unknown.event","sessionId":"123"}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        XCTAssertNil(wire.toEvent())
    }

    // MARK: - Task Board Command Encoding

    func testTaskCreateEncoding() throws {
        let task = TaskWireSwift(
            id: "task-1",
            projectId: nil,
            title: "Fix bug",
            description: "Login broken",
            status: "ready",
            priority: "high",
            labels: ["auth"],
            result: nil,
            parentTaskId: nil,
            assignedAgentId: nil,
            assignedAgentName: nil,
            assignedGroupId: nil,
            conversationId: nil,
            createdAt: "2026-03-25T00:00:00Z",
            startedAt: nil,
            completedAt: nil
        )
        let command = SidecarCommand.taskCreate(task: task)
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "task.create")
        let taskJson = json["task"] as? [String: Any]
        XCTAssertEqual(taskJson?["id"] as? String, "task-1")
        XCTAssertEqual(taskJson?["title"] as? String, "Fix bug")
        XCTAssertEqual(taskJson?["status"] as? String, "ready")
        XCTAssertEqual(taskJson?["priority"] as? String, "high")
        XCTAssertEqual(taskJson?["labels"] as? [String], ["auth"])
    }

    func testTaskClaimEncoding() throws {
        let command = SidecarCommand.taskClaim(taskId: "task-42", agentName: "Orchestrator")
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "task.claim")
        XCTAssertEqual(json["taskId"] as? String, "task-42")
        XCTAssertEqual(json["agentName"] as? String, "Orchestrator")
    }

    func testTaskListEncoding() throws {
        let command = SidecarCommand.taskList(filter: TaskListFilter(status: "ready"))
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "task.list")
        let filter = json["filter"] as? [String: Any]
        XCTAssertEqual(filter?["status"] as? String, "ready")
    }

    func testTaskListEncodingNoFilter() throws {
        let command = SidecarCommand.taskList(filter: nil)
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "task.list")
    }

    // MARK: - Task Board Event Decoding

    func testTaskCreatedDecoding() throws {
        let jsonStr = """
        {"type":"task.created","task":{"id":"t-1","title":"Fix bug","description":"","status":"ready","priority":"high","labels":["auth"],"createdAt":"2026-03-25T00:00:00Z"}}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .taskCreated(_, let task) = event {
            XCTAssertEqual(task.id, "t-1")
            XCTAssertEqual(task.title, "Fix bug")
            XCTAssertEqual(task.status, "ready")
            XCTAssertEqual(task.priority, "high")
            XCTAssertEqual(task.labels, ["auth"])
        } else {
            XCTFail("Expected .taskCreated event, got \(String(describing: event))")
        }
    }

    func testTaskUpdatedDecoding() throws {
        let jsonStr = """
        {"type":"task.updated","task":{"id":"t-2","title":"Deploy","description":"","status":"done","priority":"medium","labels":[],"result":"Deployed v2.1","createdAt":"2026-03-25T00:00:00Z","completedAt":"2026-03-25T01:00:00Z"}}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .taskUpdated(_, let task) = event {
            XCTAssertEqual(task.id, "t-2")
            XCTAssertEqual(task.status, "done")
            XCTAssertEqual(task.result, "Deployed v2.1")
            XCTAssertEqual(task.completedAt, "2026-03-25T01:00:00Z")
        } else {
            XCTFail("Expected .taskUpdated event, got \(String(describing: event))")
        }
    }

    func testTaskListResultDecoding() throws {
        let jsonStr = """
        {"type":"task.list.result","tasks":[{"id":"t-1","title":"A","description":"","status":"ready","priority":"low","labels":[],"createdAt":"2026-03-25T00:00:00Z"},{"id":"t-2","title":"B","description":"","status":"done","priority":"high","labels":["x"],"createdAt":"2026-03-25T00:00:00Z"}]}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .taskListResult(let tasks) = event {
            XCTAssertEqual(tasks.count, 2)
            XCTAssertEqual(tasks[0].title, "A")
            XCTAssertEqual(tasks[1].title, "B")
        } else {
            XCTFail("Expected .taskListResult event, got \(String(describing: event))")
        }
    }

    func testTaskListResultEmptyDecoding() throws {
        let jsonStr = """
        {"type":"task.list.result"}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .taskListResult(let tasks) = event {
            XCTAssertEqual(tasks.count, 0)
        } else {
            XCTFail("Expected .taskListResult event, got \(String(describing: event))")
        }
    }
}
