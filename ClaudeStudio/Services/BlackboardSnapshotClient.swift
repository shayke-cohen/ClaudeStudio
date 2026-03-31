import Foundation

enum BlackboardInspectorScope: String, CaseIterable, Identifiable {
    case relevant = "Relevant"
    case all = "All"

    var id: String { rawValue }
}

struct BlackboardSnapshotEntry: Codable, Equatable, Sendable, Identifiable {
    let key: String
    let value: String
    let writtenBy: String
    let workspaceId: String?
    let createdAt: Date
    let updatedAt: Date

    var id: String { key }
}

enum BlackboardSnapshotClientError: Error, Equatable, LocalizedError {
    case sidecarUnavailable
    case invalidResponse
    case requestFailed(statusCode: Int)
    case decodingFailed

    var errorDescription: String? {
        switch self {
        case .sidecarUnavailable:
            return "The sidecar blackboard is unavailable right now."
        case .invalidResponse:
            return "The sidecar returned an invalid response."
        case .requestFailed(let statusCode):
            return "The sidecar blackboard request failed with status \(statusCode)."
        case .decodingFailed:
            return "The blackboard response could not be decoded."
        }
    }
}

struct BlackboardSnapshotClient {
    let baseURL: URL
    var session: URLSession = .shared

    static func live(port: Int, session: URLSession = .shared) -> BlackboardSnapshotClient? {
        guard port > 0, let baseURL = URL(string: "http://127.0.0.1:\(port)") else {
            return nil
        }
        return BlackboardSnapshotClient(baseURL: baseURL, session: session)
    }

    func fetchAllEntries() async throws -> [BlackboardSnapshotEntry] {
        var components = URLComponents(
            url: baseURL.appending(path: "blackboard/query"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "pattern", value: "*")]

        guard let url = components?.url else {
            throw BlackboardSnapshotClientError.invalidResponse
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(from: url)
        } catch {
            throw BlackboardSnapshotClientError.sidecarUnavailable
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw BlackboardSnapshotClientError.invalidResponse
        }

        guard (200 ..< 300).contains(httpResponse.statusCode) else {
            throw BlackboardSnapshotClientError.requestFailed(statusCode: httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let entries = try decoder.decode([BlackboardSnapshotEntry].self, from: data)
            return entries.sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
        } catch {
            throw BlackboardSnapshotClientError.decodingFailed
        }
    }
}

enum BlackboardSnapshotFilter {
    static func filteredEntries(
        _ entries: [BlackboardSnapshotEntry],
        scope: BlackboardInspectorScope,
        searchText: String,
        relevantKeys: Set<String>,
        relevantWriters: Set<String>
    ) -> [BlackboardSnapshotEntry] {
        let scopedEntries: [BlackboardSnapshotEntry]
        switch scope {
        case .all:
            scopedEntries = entries
        case .relevant:
            scopedEntries = entries.filter { entry in
                isRelevant(entry, relevantKeys: relevantKeys, relevantWriters: relevantWriters)
            }
        }

        let trimmedSearch = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedSearch.isEmpty else { return scopedEntries }

        return scopedEntries.filter { entry in
            matchesSearch(entry: entry, searchText: trimmedSearch)
        }
    }

    static func isRelevant(
        _ entry: BlackboardSnapshotEntry,
        relevantKeys: Set<String>,
        relevantWriters: Set<String>
    ) -> Bool {
        relevantKeys.contains(entry.key) || relevantWriters.contains(entry.writtenBy.lowercased())
    }

    private static func matchesSearch(entry: BlackboardSnapshotEntry, searchText: String) -> Bool {
        let needle = searchText.lowercased()
        return entry.key.lowercased().contains(needle)
            || entry.writtenBy.lowercased().contains(needle)
            || entry.value.lowercased().contains(needle)
    }
}
