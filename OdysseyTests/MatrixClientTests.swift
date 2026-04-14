// OdysseyTests/MatrixClientTests.swift
import XCTest
@testable import Odyssey

// MARK: - URLProtocol stub

final class MatrixStubProtocol: URLProtocol {
    static var handlers: [(check: (URLRequest) -> Bool, response: (URLRequest) -> (Data, Int))] = []

    static func register(when check: @escaping (URLRequest) -> Bool,
                         respond: @escaping (URLRequest) -> (Data, Int)) {
        handlers.append((check: check, response: respond))
    }
    static func reset() { handlers = [] }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let handler = Self.handlers.first { $0.check(request) }
        let (data, statusCode) = handler?.response(request) ?? (Data(), 404)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: data)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

// MARK: - Tests

@MainActor
final class MatrixClientTests: XCTestCase {
    private var stubSession: URLSession!
    private let homeserver = URL(string: "https://matrix.example.com")!
    private var client: MatrixClient!

    override func setUp() {
        super.setUp()
        MatrixStubProtocol.reset()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MatrixStubProtocol.self]
        stubSession = URLSession(configuration: config)
        client = MatrixClient(homeserver: homeserver, credentials: nil, session: stubSession)
    }

    func testLoginRequestFormat() async throws {
        var capturedRequest: URLRequest?
        MatrixStubProtocol.register(when: { $0.url?.path.contains("/login") == true }) { req in
            capturedRequest = req
            let body = """
            {"access_token":"tok","device_id":"dev1","user_id":"@alice:example.com"}
            """.data(using: .utf8)!
            return (body, 200)
        }
        _ = try await client.login(username: "alice", password: "s3cret")
        let body = try XCTUnwrap(capturedRequest?.httpBody)
        let json = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        XCTAssertEqual(json["type"] as? String, "m.login.password")
        let identifier = json["identifier"] as? [String: Any]
        XCTAssertEqual(identifier?["user"] as? String, "alice")
    }

    func testSyncParsesRoomEvents() async throws {
        let syncJSON = """
        {
          "next_batch": "batch_001",
          "rooms": {
            "join": {
              "!room1:example.com": {
                "timeline": {
                  "events": [
                    {
                      "event_id": "$ev1",
                      "sender": "@bob:example.com",
                      "type": "m.room.message",
                      "origin_server_ts": 1700000000000,
                      "content": {
                        "msgtype": "m.text",
                        "body": "hello",
                        "odyssey": {
                          "messageId": "msg-1",
                          "senderId": "bob",
                          "participantType": "user"
                        }
                      }
                    }
                  ]
                }
              }
            }
          }
        }
        """.data(using: .utf8)!
        MatrixStubProtocol.register(when: { $0.url?.path.contains("/sync") == true }) { _ in
            return (syncJSON, 200)
        }
        client.credentials = MatrixCredentials(
            accessToken: "tok", refreshToken: nil,
            deviceId: "dev1", userId: "@alice:example.com", homeserver: homeserver
        )
        let response = try await client.sync(since: nil)
        XCTAssertEqual(response.nextBatch, "batch_001")
        XCTAssertEqual(response.rooms.count, 1)
        XCTAssertEqual(response.rooms[0].events.count, 1)
        XCTAssertEqual(response.rooms[0].events[0].eventId, "$ev1")
    }

    func testSendEventBuildsTxnId() async throws {
        var capturedPaths: [String] = []
        MatrixStubProtocol.register(when: { $0.url?.path.contains("/send/") == true }) { req in
            capturedPaths.append(req.url!.path)
            return (#"{"event_id":"$ev1"}"#.data(using: .utf8)!, 200)
        }
        client.credentials = MatrixCredentials(
            accessToken: "tok", refreshToken: nil,
            deviceId: "dev1", userId: "@alice:example.com", homeserver: homeserver
        )
        _ = try await client.sendEvent(roomId: "!room:example.com", type: "m.room.message", content: ["msgtype": "m.text", "body": "a"])
        _ = try await client.sendEvent(roomId: "!room:example.com", type: "m.room.message", content: ["msgtype": "m.text", "body": "b"])
        XCTAssertEqual(capturedPaths.count, 2)
        let txn1 = capturedPaths[0].components(separatedBy: "/").last!
        let txn2 = capturedPaths[1].components(separatedBy: "/").last!
        XCTAssertNotEqual(txn1, txn2)
    }

    func testPresenceUpdateRequest() async throws {
        var capturedMethod: String?
        var capturedBody: [String: Any]?
        MatrixStubProtocol.register(when: { $0.url?.path.contains("/presence/") == true }) { req in
            capturedMethod = req.httpMethod
            capturedBody = (try? JSONSerialization.jsonObject(with: req.httpBody ?? Data()) as? [String: Any])
            return (Data(), 200)
        }
        client.credentials = MatrixCredentials(
            accessToken: "tok", refreshToken: nil,
            deviceId: "dev1", userId: "@alice:example.com", homeserver: homeserver
        )
        try await client.setPresence(status: "online", statusMsg: nil)
        XCTAssertEqual(capturedMethod, "PUT")
        XCTAssertEqual(capturedBody?["presence"] as? String, "online")
    }

    func testSyncBackoffOnError() async throws {
        MatrixStubProtocol.register(when: { $0.url?.path.contains("/sync") == true }) { _ in
            return (#"{"errcode":"M_INTERNAL","error":"server error"}"#.data(using: .utf8)!, 500)
        }
        client.credentials = MatrixCredentials(
            accessToken: "tok", refreshToken: nil,
            deviceId: "dev1", userId: "@alice:example.com", homeserver: homeserver
        )
        do {
            _ = try await client.sync(since: nil)
            XCTFail("Expected sync to throw on 5xx")
        } catch MatrixError.httpError(let code, _, _) {
            XCTAssertEqual(code, 500, "Should receive HTTP 500 error")
        }
    }

    func testSyncResumeFromToken() async throws {
        var capturedQueryItems: [[URLQueryItem]] = []
        MatrixStubProtocol.register(when: { $0.url?.path.contains("/sync") == true }) { req in
            let comps = URLComponents(url: req.url!, resolvingAgainstBaseURL: false)
            capturedQueryItems.append(comps?.queryItems ?? [])
            let batch = capturedQueryItems.count == 1 ? "batch_001" : "batch_002"
            return ("{\"next_batch\":\"\(batch)\",\"rooms\":{}}".data(using: .utf8)!, 200)
        }
        client.credentials = MatrixCredentials(
            accessToken: "tok", refreshToken: nil,
            deviceId: "dev1", userId: "@alice:example.com", homeserver: homeserver
        )
        let first = try await client.sync(since: nil)
        let second = try await client.sync(since: first.nextBatch)
        let sinceItem = capturedQueryItems[1].first(where: { $0.name == "since" })
        XCTAssertEqual(sinceItem?.value, "batch_001")
        _ = second
    }

    func testTokenRefreshOnM_UNKNOWN_TOKEN() async throws {
        MatrixStubProtocol.register(when: { $0.url?.path.contains("/sync") == true }) { _ in
            return (#"{"errcode":"M_UNKNOWN_TOKEN","error":"expired"}"#.data(using: .utf8)!, 401)
        }
        MatrixStubProtocol.register(when: { $0.url?.path.contains("/refresh") == true }) { _ in
            return (#"{"access_token":"new_tok","refresh_token":"new_ref"}"#.data(using: .utf8)!, 200)
        }
        client.credentials = MatrixCredentials(
            accessToken: "old_tok", refreshToken: "ref_tok",
            deviceId: "dev1", userId: "@alice:example.com", homeserver: homeserver
        )
        do {
            _ = try await client.sync(since: nil)
            XCTFail("Expected unknownToken error")
        } catch MatrixError.unknownToken {
            // Expected
        }
        let refreshed = try await client.refreshToken("ref_tok")
        XCTAssertEqual(refreshed.accessToken, "new_tok")
    }
}
