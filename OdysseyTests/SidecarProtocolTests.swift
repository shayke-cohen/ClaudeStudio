import XCTest
@testable import Odyssey

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
            model: "gpt-5.4",
            maxTurns: 5,
            maxBudget: nil,
            maxThinkingTokens: nil,
            workingDirectory: "/tmp",
            skills: [
                AgentConfig.SkillContent(name: "Skill A", content: "Follow the skill."),
            ],
            interactive: nil,
            instancePolicy: "spawn",
            instancePolicyPoolMax: nil
        )
        let command = SidecarCommand.sessionCreate(conversationId: "conv-456", agentConfig: config)
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "session.create")
        XCTAssertEqual(json["conversationId"] as? String, "conv-456")
        let agentConfig = json["agentConfig"] as? [String: Any]
        XCTAssertEqual(agentConfig?["name"] as? String, "TestBot")
        XCTAssertEqual(agentConfig?["provider"] as? String, "codex")
        XCTAssertEqual(agentConfig?["model"] as? String, "gpt-5.4")
        XCTAssertEqual(agentConfig?["instancePolicy"] as? String, "spawn")
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
            AgentDefinitionWire(name: "Worker", config: config, instancePolicy: "singleton"),
        ])
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "agent.register")
        let agents = try XCTUnwrap(json["agents"] as? [[String: Any]])
        XCTAssertEqual(agents.count, 1)
        let encodedConfig = try XCTUnwrap(agents[0]["config"] as? [String: Any])
        XCTAssertEqual(agents[0]["instancePolicy"] as? String, "singleton")
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
            model: "gpt-5.4",
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

    func testSessionUpdateModeEncoding() throws {
        let command = SidecarCommand.sessionUpdateMode(
            sessionId: "session-42",
            interactive: false,
            instancePolicy: "spawn",
            instancePolicyPoolMax: nil
        )
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "session.updateMode")
        XCTAssertEqual(json["sessionId"] as? String, "session-42")
        XCTAssertEqual(json["interactive"] as? Bool, false)
        XCTAssertEqual(json["instancePolicy"] as? String, "spawn")
        XCTAssertNil(json["instancePolicyPoolMax"])
    }

    func testConfigSetOllamaEncoding() throws {
        let command = SidecarCommand.configSetOllama(
            enabled: true,
            baseURL: "http://127.0.0.1:11434/"
        )
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "config.setOllama")
        XCTAssertEqual(json["enabled"] as? Bool, true)
        XCTAssertEqual(json["baseURL"] as? String, "http://127.0.0.1:11434/")
    }

    func testConnectorCompleteAuthEncodingRedactsIntoStructuredFields() throws {
        let connection = ConnectorWire(
            id: "conn-1",
            provider: "x",
            installScope: "system",
            displayName: "X Sandbox",
            accountId: "acct-1",
            accountHandle: "@sandbox",
            accountMetadataJSON: nil,
            grantedScopes: ["users.read", "tweet.write"],
            authMode: "pkce-native",
            writePolicy: "require-approval",
            status: "connected",
            statusMessage: "Ready",
            brokerReference: nil,
            auditSummary: nil,
            lastAuthenticatedAt: nil,
            lastCheckedAt: nil
        )
        let credentials = ConnectorCredentialsWire(
            accessToken: "token-value",
            refreshToken: "refresh-value",
            tokenType: "Bearer",
            expiresAt: "2026-04-02T10:00:00Z",
            brokerReference: nil
        )

        let command = SidecarCommand.connectorCompleteAuth(connection: connection, credentials: credentials)
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "connector.completeAuth")
        let encodedConnection = try XCTUnwrap(json["connection"] as? [String: Any])
        XCTAssertEqual(encodedConnection["provider"] as? String, "x")
        XCTAssertEqual(encodedConnection["writePolicy"] as? String, "require-approval")
        let encodedCredentials = try XCTUnwrap(json["credentials"] as? [String: Any])
        XCTAssertEqual(encodedCredentials["tokenType"] as? String, "Bearer")
        XCTAssertEqual(encodedCredentials["accessToken"] as? String, "token-value")
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

    func testConnectorStatusChangedDecoding() throws {
        let jsonStr = """
        {"type":"connector.statusChanged","connection":{"id":"conn-1","provider":"slack","installScope":"system","displayName":"Slack","grantedScopes":["chat:write"],"authMode":"brokered","writePolicy":"require-approval","status":"connected"}}
        """
        let data = jsonStr.data(using: .utf8)!
        let wire = try JSONDecoder().decode(IncomingWireMessage.self, from: data)
        let event = wire.toEvent()

        if case .connectorStatusChanged(let connection) = event {
            XCTAssertEqual(connection.id, "conn-1")
            XCTAssertEqual(connection.provider, "slack")
            XCTAssertEqual(connection.status, "connected")
        } else {
            XCTFail("Expected .connectorStatusChanged event, got \(String(describing: event))")
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

    // MARK: - Slash Command Command Encoding

    func testConversationClearEncoding() throws {
        let command = SidecarCommand.conversationClear(conversationId: "conv-abc-123")
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "conversation.clear")
        XCTAssertEqual(json["conversationId"] as? String, "conv-abc-123")
    }

    func testConversationClearPreservesConversationId() throws {
        let uuid = UUID().uuidString
        let command = SidecarCommand.conversationClear(conversationId: uuid)
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["conversationId"] as? String, uuid)
    }

    func testSessionUpdateModelEncoding() throws {
        let command = SidecarCommand.sessionUpdateModel(
            sessionId: "sess-xyz", model: "claude-opus-4-7")
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "session.updateModel")
        XCTAssertEqual(json["sessionId"] as? String, "sess-xyz")
        XCTAssertEqual(json["model"] as? String, "claude-opus-4-7")
    }

    func testSessionUpdateModelWithHaiku() throws {
        let command = SidecarCommand.sessionUpdateModel(
            sessionId: "sess-1", model: "claude-haiku-4-5")
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(json["model"] as? String, "claude-haiku-4-5")
    }

    func testSessionUpdateEffortEncoding() throws {
        let command = SidecarCommand.sessionUpdateEffort(
            sessionId: "sess-abc", effort: "high")
        let data = try command.encodeToJSON()
        let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

        XCTAssertEqual(json["type"] as? String, "session.updateEffort")
        XCTAssertEqual(json["sessionId"] as? String, "sess-abc")
        XCTAssertEqual(json["effort"] as? String, "high")
    }

    func testSessionUpdateEffortAllLevels() throws {
        let levels = ["low", "medium", "high", "max"]
        for level in levels {
            let command = SidecarCommand.sessionUpdateEffort(sessionId: "s1", effort: level)
            let data = try command.encodeToJSON()
            let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]
            XCTAssertEqual(json["effort"] as? String, level,
                "effort='\(level)' should be preserved in encoded JSON")
        }
    }

    // MARK: - Slash Command Event Decoding

    func testConversationClearedEventDecoding() {
        let payload: [String: Any] = [
            "type": "conversation.cleared",
            "conversationId": "conv-test-456"
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let wire = try? JSONDecoder().decode(IncomingWireMessage.self, from: data) else {
            XCTFail("Failed to decode conversation.cleared payload")
            return
        }

        if case .conversationCleared(let cid) = wire.toEvent() {
            XCTAssertEqual(cid, "conv-test-456")
        } else {
            XCTFail("Expected .conversationCleared event")
        }
    }

    func testNostrInjectCommand_encodesInnerCommand() throws {
        let inner = SidecarCommand.sessionPause(sessionId: "s-abc")
        let outer = SidecarCommand.nostrInjectCommand(command: inner)
        let data = try outer.encodeToJSON()
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["type"] as? String, "nostr.injectCommand")
        let innerObj = try XCTUnwrap(json["command"] as? [String: Any])
        XCTAssertEqual(innerObj["type"] as? String, "session.pause")
        XCTAssertEqual(innerObj["sessionId"] as? String, "s-abc")
    }

    func testConversationClearedPreservesId() {
        let uuid = UUID().uuidString
        let payload: [String: Any] = ["type": "conversation.cleared", "conversationId": uuid]
        guard let data = try? JSONSerialization.data(withJSONObject: payload),
              let wire = try? JSONDecoder().decode(IncomingWireMessage.self, from: data) else {
            XCTFail("Failed to decode")
            return
        }
        if case .conversationCleared(let cid) = wire.toEvent() {
            XCTAssertEqual(cid, uuid)
        } else {
            XCTFail("Expected .conversationCleared event")
        }
    }
}
