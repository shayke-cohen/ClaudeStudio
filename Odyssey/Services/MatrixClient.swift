// Odyssey/Services/MatrixClient.swift
import Foundation
import OSLog

private let logger = Logger(subsystem: "com.odyssey.app", category: "MatrixClient")

// MARK: - Credential types

struct MatrixCredentials: Codable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let deviceId: String     // must persist to avoid orphaned Matrix devices
    let userId: String       // "@user:homeserver"
    let homeserver: URL
}

struct MatrixUser: Sendable {
    let userId: String
    let displayName: String?
    let avatarURL: String?
}

struct MatrixPresence: Sendable {
    let userId: String
    let presence: String   // "online" | "unavailable" | "offline"
    let statusMsg: String?
    let lastActiveAgo: Int?
}

// MARK: - Sync response shapes

struct MatrixSyncResponse: Sendable {
    let nextBatch: String
    let rooms: [MatrixRoomEvents]
}

struct MatrixRoomEvents: Sendable {
    let roomId: String
    let events: [MatrixRoomEvent]
}

struct MatrixRoomEvent: @unchecked Sendable {
    let eventId: String
    let sender: String
    let type: String
    let content: [String: Any]
    let originServerTs: Int64
}

// MARK: - Errors

enum MatrixError: Error, LocalizedError {
    case httpError(statusCode: Int, errcode: String?, error: String?)
    case unknownToken          // M_UNKNOWN_TOKEN → trigger refresh
    case decodingFailed(String)
    case missingField(String)

    var errorDescription: String? {
        switch self {
        case .httpError(let code, let errcode, let msg):
            return "Matrix HTTP \(code): \(errcode ?? "?") — \(msg ?? "no message")"
        case .unknownToken:
            return "Matrix access token expired (M_UNKNOWN_TOKEN)"
        case .decodingFailed(let detail):
            return "Matrix response decode error: \(detail)"
        case .missingField(let field):
            return "Matrix response missing field: \(field)"
        }
    }
}

// MARK: - Client

final class MatrixClient: @unchecked Sendable {
    let homeserver: URL
    private let session: URLSession

    // Mutable credential storage — uses a lock to satisfy Sendable with URLSession
    private let credentialLock = NSLock()
    private var _credentials: MatrixCredentials?
    var credentials: MatrixCredentials? {
        get { credentialLock.withLock { _credentials } }
        set { credentialLock.withLock { _credentials = newValue } }
    }

    init(homeserver: URL, credentials: MatrixCredentials? = nil, session: URLSession = .shared) {
        self.homeserver = homeserver
        self._credentials = credentials
        self.session = session
    }

    // MARK: Authentication

    func register(
        username: String,
        password: String,
        registrationToken: String? = nil
    ) async throws -> MatrixCredentials {
        var body: [String: Any] = [
            "kind": "user",
            "username": username,
            "password": password,
            "auth": ["type": "m.login.dummy"]
        ]
        if let token = registrationToken {
            body["registration_token"] = token
        }
        let json = try await post(path: "/_matrix/client/v3/register", body: body, authenticated: false)
        return try extractCredentials(from: json, homeserver: homeserver)
    }

    func login(username: String, password: String) async throws -> MatrixCredentials {
        let body: [String: Any] = [
            "type": "m.login.password",
            "identifier": ["type": "m.id.user", "user": username],
            "password": password,
            "device_id": credentials?.deviceId ?? UUID().uuidString
        ]
        let json = try await post(path: "/_matrix/client/v3/login", body: body, authenticated: false)
        return try extractCredentials(from: json, homeserver: homeserver)
    }

    func refreshToken(_ refreshToken: String) async throws -> MatrixCredentials {
        let body: [String: Any] = ["refresh_token": refreshToken]
        let json = try await post(path: "/_matrix/client/v3/refresh", body: body, authenticated: false)
        guard let accessToken = json["access_token"] as? String,
              let deviceId = credentials?.deviceId,
              let userId = credentials?.userId else {
            throw MatrixError.missingField("access_token / deviceId / userId")
        }
        let newRefresh = json["refresh_token"] as? String
        let updated = MatrixCredentials(
            accessToken: accessToken,
            refreshToken: newRefresh ?? refreshToken,
            deviceId: deviceId,
            userId: userId,
            homeserver: homeserver
        )
        return updated
    }

    // MARK: Sync

    func sync(since: String?, timeout: Int = 30_000) async throws -> MatrixSyncResponse {
        var components = URLComponents(url: homeserver, resolvingAgainstBaseURL: false)!
        components.path = "/_matrix/client/v3/sync"
        var queryItems = [URLQueryItem(name: "timeout", value: "\(timeout)")]
        if let since { queryItems.append(URLQueryItem(name: "since", value: since)) }
        components.queryItems = queryItems
        let url = components.url!
        let data = try await get(url: url)
        return try parseSyncResponse(data)
    }

    // MARK: Room operations

    func createRoom(name: String?, inviteUserIds: [String]) async throws -> String {
        var body: [String: Any] = ["preset": "private_chat"]
        if let name { body["name"] = name }
        if !inviteUserIds.isEmpty { body["invite"] = inviteUserIds }
        let json = try await post(path: "/_matrix/client/v3/createRoom", body: body)
        guard let roomId = json["room_id"] as? String else {
            throw MatrixError.missingField("room_id")
        }
        return roomId
    }

    func inviteUser(_ userId: String, to roomId: String) async throws {
        let path = "/_matrix/client/v3/rooms/\(roomId.urlPathEncoded)/invite"
        _ = try await post(path: path, body: ["user_id": userId])
    }

    func joinRoom(_ roomIdOrAlias: String) async throws {
        let path = "/_matrix/client/v3/rooms/\(roomIdOrAlias.urlPathEncoded)/join"
        _ = try await post(path: path, body: [:])
    }

    func sendEvent(roomId: String, type: String, content: [String: Any]) async throws -> String {
        let txnId = buildTxnId()
        let path = "/_matrix/client/v3/rooms/\(roomId.urlPathEncoded)/send/\(type)/\(txnId)"
        let json = try await put(path: path, body: content)
        guard let eventId = json["event_id"] as? String else {
            throw MatrixError.missingField("event_id")
        }
        return eventId
    }

    // MARK: Presence

    func setPresence(status: String, statusMsg: String?) async throws {
        guard let userId = credentials?.userId else { return }
        let path = "/_matrix/client/v3/presence/\(userId.urlPathEncoded)/status"
        var body: [String: Any] = ["presence": status]
        if let msg = statusMsg { body["status_msg"] = msg }
        _ = try await put(path: path, body: body)
    }

    func getPresence(userId: String) async throws -> MatrixPresence {
        let path = "/_matrix/client/v3/presence/\(userId.urlPathEncoded)/status"
        let url = homeserver.appendingPathComponent(path)
        let data = try await get(url: url)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let presence = json["presence"] as? String else {
            throw MatrixError.missingField("presence")
        }
        return MatrixPresence(
            userId: userId,
            presence: presence,
            statusMsg: json["status_msg"] as? String,
            lastActiveAgo: json["last_active_ago"] as? Int
        )
    }

    // MARK: User directory

    func searchUsers(query: String) async throws -> [MatrixUser] {
        let json = try await post(
            path: "/_matrix/client/v3/user_directory/search",
            body: ["search_term": query, "limit": 10]
        )
        guard let results = json["results"] as? [[String: Any]] else { return [] }
        return results.compactMap { item in
            guard let userId = item["user_id"] as? String else { return nil }
            return MatrixUser(
                userId: userId,
                displayName: item["display_name"] as? String,
                avatarURL: item["avatar_url"] as? String
            )
        }
    }

    // MARK: Push registration

    func registerPusher(
        appId: String,
        appDisplayName: String,
        deviceDisplayName: String,
        pushKey: String,   // APNS token hex string
        lang: String = "en",
        profileTag: String = "odyssey_ios",
        pushgatewayURL: URL
    ) async throws {
        let body: [String: Any] = [
            "kind": "http",
            "app_id": appId,
            "app_display_name": appDisplayName,
            "device_display_name": deviceDisplayName,
            "pushkey": pushKey,
            "lang": lang,
            "profile_tag": profileTag,
            "data": ["url": pushgatewayURL.absoluteString, "format": "event_id_only"]
        ]
        _ = try await post(path: "/_matrix/client/v3/pushers/set", body: body)
    }

    // MARK: - Private helpers

    private func buildTxnId() -> String {
        let deviceId = credentials?.deviceId ?? "unknown"
        let ts = Int64(Date().timeIntervalSince1970 * 1000)
        return "\(deviceId)-\(ts)-\(UUID().uuidString)"
    }

    private func post(path: String, body: [String: Any], authenticated: Bool = true) async throws -> [String: Any] {
        let url = homeserver.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if authenticated, let token = credentials?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await execute(request: request)
    }

    private func put(path: String, body: [String: Any]) async throws -> [String: Any] {
        let url = homeserver.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let token = credentials?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await execute(request: request)
    }

    private func get(url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        if let token = credentials?.accessToken {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await session.data(for: request)
        try checkHTTPStatus(response, data: data)
        return data
    }

    private func execute(request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        try checkHTTPStatus(response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MatrixError.decodingFailed("top-level object expected")
        }
        return json
    }

    private func checkHTTPStatus(_ response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard http.statusCode / 100 != 2 else { return }
        let json = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
        let errcode = json["errcode"] as? String
        let errorMsg = json["error"] as? String
        if errcode == "M_UNKNOWN_TOKEN" { throw MatrixError.unknownToken }
        throw MatrixError.httpError(statusCode: http.statusCode, errcode: errcode, error: errorMsg)
    }

    private func extractCredentials(from json: [String: Any], homeserver: URL) throws -> MatrixCredentials {
        guard let accessToken = json["access_token"] as? String,
              let deviceId = json["device_id"] as? String,
              let userId = json["user_id"] as? String else {
            throw MatrixError.missingField("access_token / device_id / user_id")
        }
        return MatrixCredentials(
            accessToken: accessToken,
            refreshToken: json["refresh_token"] as? String,
            deviceId: deviceId,
            userId: userId,
            homeserver: homeserver
        )
    }

    private func parseSyncResponse(_ data: Data) throws -> MatrixSyncResponse {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw MatrixError.decodingFailed("sync response not object")
        }
        guard let nextBatch = json["next_batch"] as? String else {
            throw MatrixError.missingField("next_batch")
        }
        var roomEvents: [MatrixRoomEvents] = []
        if let rooms = json["rooms"] as? [String: Any],
           let join = rooms["join"] as? [String: Any] {
            for (roomId, roomData) in join {
                guard let rd = roomData as? [String: Any],
                      let timeline = rd["timeline"] as? [String: Any],
                      let eventsRaw = timeline["events"] as? [[String: Any]] else { continue }
                let events = eventsRaw.compactMap { ev -> MatrixRoomEvent? in
                    guard let eventId = ev["event_id"] as? String,
                          let sender = ev["sender"] as? String,
                          let type = ev["type"] as? String,
                          let content = ev["content"] as? [String: Any],
                          let ts = ev["origin_server_ts"] as? Int64 else { return nil }
                    return MatrixRoomEvent(
                        eventId: eventId,
                        sender: sender,
                        type: type,
                        content: content,
                        originServerTs: ts
                    )
                }
                roomEvents.append(MatrixRoomEvents(roomId: roomId, events: events))
            }
        }
        return MatrixSyncResponse(nextBatch: nextBatch, rooms: roomEvents)
    }
}

// MARK: - URL encoding helper

private extension String {
    var urlPathEncoded: String {
        addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? self
    }
}
