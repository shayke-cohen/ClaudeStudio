import Foundation

struct OllamaCachedModel: Codable, Equatable, Identifiable {
    let name: String
    let size: Int64?

    var id: String { name }
    var selectionValue: String { "\(AgentDefaults.ollamaModelPrefix)\(name)" }
    var label: String { "Ollama: \(name)" }
}

struct OllamaCachedStatus: Codable, Equatable {
    let baseURL: String
    let available: Bool
    let hasModels: Bool
    let summary: String
    let checkedAt: Date
}

struct OllamaCatalogSnapshot: Equatable {
    let baseURL: String
    let available: Bool
    let models: [OllamaCachedModel]
    let summary: String

    var hasModels: Bool { !models.isEmpty }
}

enum OllamaCatalogService {
    private struct OllamaTagsResponse: Decodable {
        let models: [OllamaTag]
    }

    private struct OllamaTag: Decodable {
        let name: String
        let size: Int64?
    }

    private struct OllamaVersionResponse: Decodable {
        let version: String?
    }

    static func normalizedBaseURL(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let candidate = trimmed.isEmpty ? AppSettings.defaultOllamaBaseURL : trimmed
        return candidate.hasSuffix("/") ? String(candidate.dropLast()) : candidate
    }

    static func modelsEnabled(defaults: UserDefaults = AppSettings.store) -> Bool {
        if defaults.object(forKey: AppSettings.ollamaModelsEnabledKey) == nil {
            return AppSettings.defaultOllamaModelsEnabled
        }
        return defaults.bool(forKey: AppSettings.ollamaModelsEnabledKey)
    }

    static func cachedModels(defaults: UserDefaults = AppSettings.store) -> [OllamaCachedModel] {
        guard let data = defaults.data(forKey: AppSettings.ollamaCachedModelsKey) else { return [] }
        return (try? JSONDecoder().decode([OllamaCachedModel].self, from: data)) ?? []
    }

    static func cachedStatus(defaults: UserDefaults = AppSettings.store) -> OllamaCachedStatus? {
        guard let data = defaults.data(forKey: AppSettings.ollamaCachedStatusKey) else { return nil }
        return try? JSONDecoder().decode(OllamaCachedStatus.self, from: data)
    }

    static func cache(snapshot: OllamaCatalogSnapshot, defaults: UserDefaults = AppSettings.store) {
        let encoder = JSONEncoder()
        let modelsData = try? encoder.encode(snapshot.models)
        let statusData = try? encoder.encode(
            OllamaCachedStatus(
                baseURL: snapshot.baseURL,
                available: snapshot.available,
                hasModels: snapshot.hasModels,
                summary: snapshot.summary,
                checkedAt: Date()
            )
        )

        defaults.set(modelsData, forKey: AppSettings.ollamaCachedModelsKey)
        defaults.set(statusData, forKey: AppSettings.ollamaCachedStatusKey)
    }

    static func refresh(
        baseURL: String? = nil,
        timeout: TimeInterval = 2.0,
        session: URLSession = .shared,
        defaults: UserDefaults = AppSettings.store
    ) async -> OllamaCatalogSnapshot {
        let resolvedBaseURL = normalizedBaseURL(baseURL ?? defaults.string(forKey: AppSettings.ollamaBaseURLKey))

        do {
            let models = try await fetchModels(baseURL: resolvedBaseURL, timeout: timeout, session: session)
            let summary = models.isEmpty
                ? "Ollama is reachable at \(resolvedBaseURL), but no local models are downloaded yet."
                : "Ollama is ready at \(resolvedBaseURL) with \(models.count) downloaded model\(models.count == 1 ? "" : "s")."
            let snapshot = OllamaCatalogSnapshot(
                baseURL: resolvedBaseURL,
                available: true,
                models: models,
                summary: summary
            )
            cache(snapshot: snapshot, defaults: defaults)
            return snapshot
        } catch {
            do {
                let version = try await fetchVersion(baseURL: resolvedBaseURL, timeout: timeout, session: session)
                let versionSuffix = version.isEmpty ? "" : " (\(version))"
                let snapshot = OllamaCatalogSnapshot(
                    baseURL: resolvedBaseURL,
                    available: true,
                    models: [],
                    summary: "Ollama is reachable at \(resolvedBaseURL)\(versionSuffix), but the model list could not be loaded."
                )
                cache(snapshot: snapshot, defaults: defaults)
                return snapshot
            } catch {
                let snapshot = OllamaCatalogSnapshot(
                    baseURL: resolvedBaseURL,
                    available: false,
                    models: [],
                    summary: "Ollama is unavailable at \(resolvedBaseURL). Start the Ollama app or daemon and refresh."
                )
                cache(snapshot: snapshot, defaults: defaults)
                return snapshot
            }
        }
    }

    private static func fetchModels(
        baseURL: String,
        timeout: TimeInterval,
        session: URLSession
    ) async throws -> [OllamaCachedModel] {
        let data = try await fetchJSON(path: "/api/tags", baseURL: baseURL, timeout: timeout, session: session)
        let decoded = try JSONDecoder().decode(OllamaTagsResponse.self, from: data)
        var seen = Set<String>()
        return decoded.models.compactMap { model in
            let trimmedName = model.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedName.isEmpty, seen.insert(trimmedName).inserted else { return nil }
            return OllamaCachedModel(name: trimmedName, size: model.size)
        }
        .sorted { lhs, rhs in
            lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private static func fetchVersion(
        baseURL: String,
        timeout: TimeInterval,
        session: URLSession
    ) async throws -> String {
        let data = try await fetchJSON(path: "/api/version", baseURL: baseURL, timeout: timeout, session: session)
        let decoded = try JSONDecoder().decode(OllamaVersionResponse.self, from: data)
        return decoded.version?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    private static func fetchJSON(
        path: String,
        baseURL: String,
        timeout: TimeInterval,
        session: URLSession
    ) async throws -> Data {
        guard let url = URL(string: baseURL + path) else {
            throw URLError(.badURL)
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
