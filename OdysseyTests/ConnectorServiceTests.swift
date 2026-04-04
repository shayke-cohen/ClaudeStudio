import SwiftData
import XCTest
@testable import Odyssey

@MainActor
final class ConnectorServiceTests: XCTestCase {
    private var container: ModelContainer!
    private var context: ModelContext!

    override func setUp() async throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try ModelContainer(for: Connection.self, configurations: config)
        context = container.mainContext
        AppSettings.store.removeObject(forKey: AppSettings.connectorBrokerBaseURLKey)
        AppSettings.store.removeObject(forKey: AppSettings.xClientIdKey)
        AppSettings.store.removeObject(forKey: AppSettings.linkedinClientIdKey)
    }

    override func tearDown() async throws {
        ConnectorService.httpTransport = { request in
            try await URLSession.shared.data(for: request)
        }
        ConnectorService.openExternalURL = { url in
            NSWorkspace.shared.open(url)
        }
        AppSettings.store.removeObject(forKey: AppSettings.connectorBrokerBaseURLKey)
        AppSettings.store.removeObject(forKey: AppSettings.xClientIdKey)
        AppSettings.store.removeObject(forKey: AppSettings.linkedinClientIdKey)
        container = nil
        context = nil
    }

    func testHandleCallbackExchangesXAuthorizationCodeAndStoresCredentials() async throws {
        AppSettings.store.set("x-client-id", forKey: AppSettings.xClientIdKey)
        let connection = ConnectorService.upsertConnection(provider: .x, in: context)
        connection.authMode = .pkceNative
        connection.grantedScopes = ["users.read", "tweet.write"]
        try ConnectionVault.saveCredentials(
            .init(
                accessToken: nil,
                refreshToken: nil,
                tokenType: nil,
                expiresAt: nil,
                brokerReference: nil,
                authorizationCode: nil,
                codeVerifier: "verifier-123"
            ),
            connectionId: connection.id
        )
        AppSettings.store.set("state-123", forKey: "connector.pendingState.\(connection.id.uuidString)")

        ConnectorService.httpTransport = { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.x.com/2/oauth2/token")
            XCTAssertEqual(request.httpMethod, "POST")
            let body = String(data: try XCTUnwrap(request.httpBody), encoding: .utf8)
            XCTAssertTrue(body?.contains("grant_type=authorization_code") == true)
            XCTAssertTrue(body?.contains("code=auth-code") == true)
            XCTAssertTrue(body?.contains("client_id=x-client-id") == true)
            XCTAssertTrue(body?.contains("code_verifier=verifier-123") == true)
            let payload = """
            {"access_token":"access-123","refresh_token":"refresh-456","token_type":"Bearer","expires_in":3600}
            """
            let data = Data(payload.utf8)
            let response = try XCTUnwrap(HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil))
            return (data, response)
        }

        let handled = ConnectorService.handleCallback(
            URL(string: "odyssey://connector-auth/x?code=auth-code&state=state-123")!,
            in: context,
            appState: nil
        )

        XCTAssertTrue(handled)
        try await waitUntil {
            let storedCredentials = try ConnectionVault.loadCredentials(connectionId: connection.id)
            return storedCredentials?.accessToken == "access-123"
                && storedCredentials?.refreshToken == "refresh-456"
                && storedCredentials?.codeVerifier == nil
                && connection.status == .connected
                && connection.statusMessage == "Authorization complete."
        }

        let storedCredentials = try ConnectionVault.loadCredentials(connectionId: connection.id)
        XCTAssertEqual(storedCredentials?.accessToken, "access-123")
        XCTAssertEqual(storedCredentials?.refreshToken, "refresh-456")
        XCTAssertNil(storedCredentials?.codeVerifier)
        XCTAssertEqual(connection.status, .connected)
        XCTAssertEqual(connection.statusMessage, "Authorization complete.")
    }

    func testHandleCallbackRejectsStateMismatch() throws {
        AppSettings.store.set("x-client-id", forKey: AppSettings.xClientIdKey)
        let connection = ConnectorService.upsertConnection(provider: .x, in: context)
        connection.authMode = .pkceNative
        AppSettings.store.set("expected-state", forKey: "connector.pendingState.\(connection.id.uuidString)")

        let handled = ConnectorService.handleCallback(
            URL(string: "odyssey://connector-auth/x?code=auth-code&state=wrong-state")!,
            in: context,
            appState: nil
        )

        XCTAssertTrue(handled)
        XCTAssertEqual(connection.status, .failed)
        XCTAssertEqual(connection.statusMessage, "Connector authorization state validation failed.")
    }

    func testBeginAuthBuildsPKCEURLAndStoresVerifier() throws {
        AppSettings.store.set("x-client-id", forKey: AppSettings.xClientIdKey)
        var openedURL: URL?
        ConnectorService.openExternalURL = { url in
            openedURL = url
        }

        try ConnectorService.beginAuth(provider: .x, in: context, appState: nil)

        let connection = ConnectorService.upsertConnection(provider: .x, in: context)
        XCTAssertEqual(connection.status, .authorizing)
        XCTAssertEqual(connection.grantedScopes, ConnectorCatalog.definition(for: .x).defaultScopes)

        let credentials = try ConnectionVault.loadCredentials(connectionId: connection.id)
        XCTAssertNotNil(credentials?.codeVerifier)
        XCTAssertNil(credentials?.accessToken)

        let resolvedURL = try XCTUnwrap(openedURL)
        let components = try XCTUnwrap(URLComponents(url: resolvedURL, resolvingAgainstBaseURL: false))
        XCTAssertTrue(resolvedURL.absoluteString.starts(with: "https://"))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "client_id" })?.value, "x-client-id")
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "redirect_uri" })?.value,
            ConnectorCatalog.callbackURL(for: .x)
        )
        XCTAssertEqual(
            components.queryItems?.first(where: { $0.name == "scope" })?.value,
            ConnectorCatalog.definition(for: .x).defaultScopes.joined(separator: " ")
        )
        XCTAssertNotNil(components.queryItems?.first(where: { $0.name == "code_challenge" })?.value)
    }

    func testSaveManualConnectionFallsBackToProviderDefaultScopes() throws {
        try ConnectorService.saveManualConnection(
            provider: .linkedin,
            displayName: "  ",
            scopes: [],
            authMode: .pkceNative,
            writePolicy: .requireApproval,
            accountId: nil,
            accountHandle: nil,
            brokerReference: nil,
            accessToken: nil,
            refreshToken: nil,
            tokenType: nil,
            expiresAt: nil,
            in: context,
            appState: nil
        )

        let connection = ConnectorService.upsertConnection(provider: .linkedin, in: context)
        XCTAssertEqual(connection.displayName, ConnectionProvider.linkedin.displayName)
        XCTAssertEqual(connection.grantedScopes, ConnectorCatalog.definition(for: .linkedin).defaultScopes)
        XCTAssertEqual(connection.status, .disconnected)
        XCTAssertEqual(connection.statusMessage, "Connection saved without runtime credentials.")
    }

    func testBeginAuthBrokeredRequiresBrokerBaseURL() {
        XCTAssertThrowsError(try ConnectorService.beginAuth(provider: .slack, in: context, appState: nil)) { error in
            XCTAssertTrue(error.localizedDescription.contains("broker URL"))
        }
    }

    func testMissingConfigurationReportsBrokerAndClientRequirements() {
        XCTAssertEqual(ConnectorCatalog.missingConfiguration(for: .slack), ["Broker Base URL"])
        XCTAssertEqual(ConnectorCatalog.missingConfiguration(for: .x), ["Client ID"])
        XCTAssertEqual(ConnectorCatalog.missingConfiguration(for: .linkedin), ["Client ID"])

        AppSettings.store.set("https://broker.example.com", forKey: AppSettings.connectorBrokerBaseURLKey)
        AppSettings.store.set("x-client-id", forKey: AppSettings.xClientIdKey)
        AppSettings.store.set("linkedin-client-id", forKey: AppSettings.linkedinClientIdKey)

        XCTAssertEqual(ConnectorCatalog.missingConfiguration(for: .slack), [])
        XCTAssertEqual(ConnectorCatalog.missingConfiguration(for: .x), [])
        XCTAssertEqual(ConnectorCatalog.missingConfiguration(for: .linkedin), [])
    }

    private func waitUntil(
        timeout: TimeInterval = 2.0,
        interval: UInt64 = 50_000_000,
        _ condition: () throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if try condition() {
                return
            }
            try await Task.sleep(nanoseconds: interval)
        }
        XCTAssertTrue(try condition(), "Timed out waiting for async connector callback to finish")
    }
}
