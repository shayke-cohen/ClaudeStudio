import Foundation
import XCTest
@testable import Odyssey

final class OllamaCatalogServiceTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        MockOllamaURLProtocol.requestHandler = nil
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockOllamaURLProtocol.self]
        session = URLSession(configuration: config)
        clearOllamaDefaults()
    }

    override func tearDown() {
        session.invalidateAndCancel()
        session = nil
        MockOllamaURLProtocol.requestHandler = nil
        clearOllamaDefaults()
        super.tearDown()
    }

    func testRefreshCachesDownloadedModelsFromTags() async throws {
        MockOllamaURLProtocol.requestHandler = { request in
            XCTAssertEqual(request.url?.path, "/api/tags")
            let body = """
            {
              "models": [
                { "name": "qwen3-coder:latest", "size": 1234 },
                { "name": "deepseek-r1:8b", "size": 2345 },
                { "name": "qwen3-coder:latest", "size": 1234 }
              ]
            }
            """
            return (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data(body.utf8)
            )
        }

        let snapshot = await OllamaCatalogService.refresh(
            baseURL: "http://127.0.0.1:11434/",
            session: session,
            defaults: AppSettings.store
        )

        XCTAssertTrue(snapshot.available)
        XCTAssertEqual(snapshot.baseURL, "http://127.0.0.1:11434")
        XCTAssertEqual(snapshot.models.map(\.name), ["deepseek-r1:8b", "qwen3-coder:latest"])
        XCTAssertEqual(snapshot.models.map(\.selectionValue), ["ollama:deepseek-r1:8b", "ollama:qwen3-coder:latest"])
        XCTAssertTrue(snapshot.summary.contains("2 downloaded models"))

        let cachedStatus = OllamaCatalogService.cachedStatus(defaults: AppSettings.store)
        XCTAssertEqual(cachedStatus?.baseURL, "http://127.0.0.1:11434")
        XCTAssertEqual(cachedStatus?.available, true)
        XCTAssertEqual(cachedStatus?.hasModels, true)
        XCTAssertEqual(OllamaCatalogService.cachedModels(defaults: AppSettings.store), snapshot.models)
    }

    func testRefreshFallsBackToVersionWhenTagsCannotBeLoaded() async throws {
        MockOllamaURLProtocol.requestHandler = { request in
            switch request.url?.path {
            case "/api/tags":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!,
                    Data("{}".utf8)
                )
            case "/api/version":
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                    Data(#"{"version":"0.7.0"}"#.utf8)
                )
            default:
                XCTFail("Unexpected path: \(request.url?.path ?? "nil")")
                throw URLError(.badURL)
            }
        }

        let snapshot = await OllamaCatalogService.refresh(
            baseURL: "http://127.0.0.1:11434",
            session: session,
            defaults: AppSettings.store
        )

        XCTAssertTrue(snapshot.available)
        XCTAssertTrue(snapshot.models.isEmpty)
        XCTAssertTrue(snapshot.summary.contains("0.7.0"))
        XCTAssertEqual(OllamaCatalogService.cachedStatus(defaults: AppSettings.store)?.available, true)
        XCTAssertTrue(OllamaCatalogService.cachedModels(defaults: AppSettings.store).isEmpty)
    }

    func testRefreshMarksUnavailableWhenOllamaCannotBeReached() async throws {
        MockOllamaURLProtocol.requestHandler = { _ in
            throw URLError(.cannotConnectToHost)
        }

        let snapshot = await OllamaCatalogService.refresh(
            baseURL: "http://127.0.0.1:11434",
            session: session,
            defaults: AppSettings.store
        )

        XCTAssertFalse(snapshot.available)
        XCTAssertTrue(snapshot.models.isEmpty)
        XCTAssertTrue(snapshot.summary.contains("unavailable"))
        XCTAssertEqual(OllamaCatalogService.cachedStatus(defaults: AppSettings.store)?.available, false)
        XCTAssertTrue(OllamaCatalogService.cachedModels(defaults: AppSettings.store).isEmpty)
    }

    func testModelsEnabledDefaultsToTrueAndCanBeDisabled() {
        XCTAssertTrue(OllamaCatalogService.modelsEnabled(defaults: AppSettings.store))
        AppSettings.store.set(false, forKey: AppSettings.ollamaModelsEnabledKey)
        XCTAssertFalse(OllamaCatalogService.modelsEnabled(defaults: AppSettings.store))
    }

    private func clearOllamaDefaults() {
        AppSettings.store.removeObject(forKey: AppSettings.ollamaModelsEnabledKey)
        AppSettings.store.removeObject(forKey: AppSettings.ollamaBaseURLKey)
        AppSettings.store.removeObject(forKey: AppSettings.ollamaCachedModelsKey)
        AppSettings.store.removeObject(forKey: AppSettings.ollamaCachedStatusKey)
    }
}

private final class MockOllamaURLProtocol: URLProtocol {
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
