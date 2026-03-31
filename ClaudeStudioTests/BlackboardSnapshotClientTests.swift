import Foundation
import XCTest
@testable import ClaudeStudio

final class BlackboardSnapshotClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockURLProtocol.requestHandler = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        MockURLProtocol.requestHandler = nil
        super.tearDown()
    }

    func testFetchAllEntriesDecodesAndSortsByUpdatedAtDescending() async throws {
        MockURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/blackboard/query")
            XCTAssertEqual(URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, "*")

            let body = """
            [
              {
                "key": "impl.status",
                "value": "{\\"state\\":\\"waiting\\"}",
                "writtenBy": "Coder",
                "workspaceId": null,
                "createdAt": "2026-03-31T09:00:00Z",
                "updatedAt": "2026-03-31T10:00:00Z"
              },
              {
                "key": "research.findings",
                "value": "Done",
                "writtenBy": "Researcher",
                "workspaceId": null,
                "createdAt": "2026-03-31T08:00:00Z",
                "updatedAt": "2026-03-31T11:00:00Z"
              }
            ]
            """
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }

        let client = BlackboardSnapshotClient(
            baseURL: URL(string: "http://127.0.0.1:9850")!,
            session: session
        )

        let entries = try await client.fetchAllEntries()
        XCTAssertEqual(entries.map(\.key), ["research.findings", "impl.status"])
    }

    func testFetchAllEntriesReturnsEmptyList() async throws {
        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("[]".utf8)
            )
        }

        let client = BlackboardSnapshotClient(
            baseURL: URL(string: "http://127.0.0.1:9850")!,
            session: session
        )

        let entries = try await client.fetchAllEntries()
        XCTAssertTrue(entries.isEmpty)
    }

    func testFetchAllEntriesThrowsOnMalformedResponse() async {
        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("{\"broken\":true}".utf8)
            )
        }

        let client = BlackboardSnapshotClient(
            baseURL: URL(string: "http://127.0.0.1:9850")!,
            session: session
        )

        do {
            _ = try await client.fetchAllEntries()
            XCTFail("Expected decoding failure")
        } catch {
            XCTAssertEqual(error as? BlackboardSnapshotClientError, .decodingFailed)
        }
    }

    func testFetchAllEntriesThrowsOnNon200Status() async {
        MockURLProtocol.requestHandler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!,
                Data("{}".utf8)
            )
        }

        let client = BlackboardSnapshotClient(
            baseURL: URL(string: "http://127.0.0.1:9850")!,
            session: session
        )

        do {
            _ = try await client.fetchAllEntries()
            XCTFail("Expected request failure")
        } catch {
            XCTAssertEqual(error as? BlackboardSnapshotClientError, .requestFailed(statusCode: 503))
        }
    }

    func testFetchAllEntriesThrowsWhenSidecarUnavailable() async {
        MockURLProtocol.requestHandler = { _ in
            throw URLError(.cannotConnectToHost)
        }

        let client = BlackboardSnapshotClient(
            baseURL: URL(string: "http://127.0.0.1:9850")!,
            session: session
        )

        do {
            _ = try await client.fetchAllEntries()
            XCTFail("Expected sidecar unavailable failure")
        } catch {
            XCTAssertEqual(error as? BlackboardSnapshotClientError, .sidecarUnavailable)
        }
    }

    func testRelevantFilterIncludesTouchedKeysAndConversationWriters() {
        let entries = [
            makeEntry(key: "research.findings", value: "top 3", writtenBy: "Planner"),
            makeEntry(key: "impl.status", value: "ready for review", writtenBy: "Coder"),
            makeEntry(key: "ops.deploy", value: "green", writtenBy: "DevOps"),
        ]

        let filtered = BlackboardSnapshotFilter.filteredEntries(
            entries,
            scope: .relevant,
            searchText: "",
            relevantKeys: ["research.findings"],
            relevantWriters: ["coder"]
        )

        XCTAssertEqual(filtered.map(\.key), ["research.findings", "impl.status"])
    }

    func testAllFilterSearchMatchesKeyWriterAndValue() {
        let entries = [
            makeEntry(key: "research.findings", value: "needs review", writtenBy: "Planner"),
            makeEntry(key: "impl.status", value: "waiting", writtenBy: "Coder"),
            makeEntry(key: "ops.deploy", value: "green", writtenBy: "DevOps"),
        ]

        let keyMatch = BlackboardSnapshotFilter.filteredEntries(
            entries,
            scope: .all,
            searchText: "findings",
            relevantKeys: [],
            relevantWriters: []
        )
        XCTAssertEqual(keyMatch.map(\.key), ["research.findings"])

        let writerMatch = BlackboardSnapshotFilter.filteredEntries(
            entries,
            scope: .all,
            searchText: "devops",
            relevantKeys: [],
            relevantWriters: []
        )
        XCTAssertEqual(writerMatch.map(\.key), ["ops.deploy"])

        let valueMatch = BlackboardSnapshotFilter.filteredEntries(
            entries,
            scope: .all,
            searchText: "review",
            relevantKeys: [],
            relevantWriters: []
        )
        XCTAssertEqual(valueMatch.map(\.key), ["research.findings"])
    }

    private func makeEntry(key: String, value: String, writtenBy: String) -> BlackboardSnapshotEntry {
        BlackboardSnapshotEntry(
            key: key,
            value: value,
            writtenBy: writtenBy,
            workspaceId: nil,
            createdAt: Date(timeIntervalSince1970: 0),
            updatedAt: Date(timeIntervalSince1970: 1)
        )
    }
}

private final class MockURLProtocol: URLProtocol {
    nonisolated(unsafe) static var requestHandler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.requestHandler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
