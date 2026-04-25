import Foundation

public struct ManagedMLXModelPreset: Codable, Sendable, Equatable, Identifiable {
    public var id: String { modelIdentifier }
    public var modelIdentifier: String
    public var label: String
    public var summary: String
    public var parameterSize: String
    public var downloadSize: String
    public var bestFor: String
    public var agentSuitability: String
    public var recommended: Bool

    public init(
        modelIdentifier: String,
        label: String,
        summary: String,
        parameterSize: String = "",
        downloadSize: String = "",
        bestFor: String = "",
        agentSuitability: String = "",
        recommended: Bool
    ) {
        self.modelIdentifier = modelIdentifier
        self.label = label
        self.summary = summary
        self.parameterSize = parameterSize
        self.downloadSize = downloadSize
        self.bestFor = bestFor
        self.agentSuitability = agentSuitability
        self.recommended = recommended
    }
}

public struct ManagedMLXInstalledModel: Codable, Sendable, Equatable, Identifiable {
    public var id: String { modelIdentifier }
    public var modelIdentifier: String
    public var downloadDirectory: String
    public var installedAt: Date
    public var sourceURL: String?
    public var managedPath: String?

    public init(
        modelIdentifier: String,
        downloadDirectory: String,
        installedAt: Date,
        sourceURL: String? = nil,
        managedPath: String? = nil
    ) {
        self.modelIdentifier = modelIdentifier
        self.downloadDirectory = downloadDirectory
        self.installedAt = installedAt
        self.sourceURL = sourceURL
        self.managedPath = managedPath
    }
}

public struct MLXModelsListParams: Codable, Sendable, Equatable {
    public var downloadDirectory: String?
    public var runnerPath: String?

    public init(downloadDirectory: String? = nil, runnerPath: String? = nil) {
        self.downloadDirectory = downloadDirectory
        self.runnerPath = runnerPath
    }
}

public struct MLXModelsListResult: Codable, Sendable, Equatable {
    public var downloadDirectory: String
    public var manifestPath: String
    public var runnerPath: String?
    public var presets: [ManagedMLXModelPreset]
    public var installed: [ManagedMLXInstalledModel]

    public init(
        downloadDirectory: String,
        manifestPath: String,
        runnerPath: String?,
        presets: [ManagedMLXModelPreset],
        installed: [ManagedMLXInstalledModel]
    ) {
        self.downloadDirectory = downloadDirectory
        self.manifestPath = manifestPath
        self.runnerPath = runnerPath
        self.presets = presets
        self.installed = installed
    }
}

public struct InstallMLXModelParams: Codable, Sendable, Equatable {
    public var modelIdentifier: String
    public var downloadDirectory: String?
    public var runnerPath: String?

    public init(modelIdentifier: String, downloadDirectory: String? = nil, runnerPath: String? = nil) {
        self.modelIdentifier = modelIdentifier
        self.downloadDirectory = downloadDirectory
        self.runnerPath = runnerPath
    }
}

public struct RemoveMLXModelParams: Codable, Sendable, Equatable {
    public var modelIdentifier: String
    public var downloadDirectory: String?

    public init(modelIdentifier: String, downloadDirectory: String? = nil) {
        self.modelIdentifier = modelIdentifier
        self.downloadDirectory = downloadDirectory
    }
}

public struct InstallMLXModelResult: Codable, Sendable, Equatable {
    public var modelIdentifier: String
    public var downloadDirectory: String
    public var manifestPath: String
    public var runnerPath: String
    public var alreadyInstalled: Bool
    public var output: String
    public var installedAt: Date

    public init(
        modelIdentifier: String,
        downloadDirectory: String,
        manifestPath: String,
        runnerPath: String,
        alreadyInstalled: Bool,
        output: String,
        installedAt: Date
    ) {
        self.modelIdentifier = modelIdentifier
        self.downloadDirectory = downloadDirectory
        self.manifestPath = manifestPath
        self.runnerPath = runnerPath
        self.alreadyInstalled = alreadyInstalled
        self.output = output
        self.installedAt = installedAt
    }
}

public struct RemoveMLXModelResult: Codable, Sendable, Equatable {
    public var modelIdentifier: String
    public var downloadDirectory: String
    public var manifestPath: String
    public var deletedPaths: [String]
    public var alreadyRemoved: Bool

    public init(
        modelIdentifier: String,
        downloadDirectory: String,
        manifestPath: String,
        deletedPaths: [String],
        alreadyRemoved: Bool
    ) {
        self.modelIdentifier = modelIdentifier
        self.downloadDirectory = downloadDirectory
        self.manifestPath = manifestPath
        self.deletedPaths = deletedPaths
        self.alreadyRemoved = alreadyRemoved
    }
}

public enum ManagedMLXModelsError: LocalizedError {
    case missingRunner
    case invalidModelIdentifier
    case installFailed(String)
    case removeFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .missingRunner:
            return "MLX runner not found. Install llm-tool or set ODYSSEY_MLX_RUNNER."
        case .invalidModelIdentifier:
            return "Enter a Hugging Face repo id, a Hugging Face URL, or a direct archive URL ending in .zip, .tar, .tar.gz, or .tgz."
        case .installFailed(let output):
            return output.isEmpty ? "Failed to install the MLX model." : output
        case .removeFailed(let output):
            return output.isEmpty ? "Failed to remove the MLX model." : output
        case .cancelled:
            return "MLX generation was cancelled."
        }
    }
}

actor ManagedMLXProcessRegistry {
    static let shared = ManagedMLXProcessRegistry()

    private var processes: [String: Process] = [:]

    func register(sessionId: String, process: Process) {
        processes[sessionId] = process
    }

    func unregister(sessionId: String, process: Process) {
        guard let current = processes[sessionId], current === process else { return }
        processes.removeValue(forKey: sessionId)
    }

    func cancel(sessionId: String) {
        guard let process = processes[sessionId] else { return }
        if process.isRunning {
            process.terminate()
        }
        processes.removeValue(forKey: sessionId)
    }
}

private struct ManagedMLXManifest: Codable {
    var installed: [ManagedMLXInstalledModel] = []
}

private enum ManagedMLXInstallSource {
    case modelIdentifier(String)
    case huggingFaceURL(rawValue: String, normalizedIdentifier: String)
    case archiveURL(URL)

    var manifestIdentifier: String? {
        switch self {
        case .modelIdentifier(let value), .huggingFaceURL(_, let value):
            return value
        case .archiveURL:
            return nil
        }
    }

    var sourceURL: String? {
        switch self {
        case .modelIdentifier:
            return nil
        case .huggingFaceURL(let rawValue, _):
            return rawValue
        case .archiveURL(let url):
            return url.absoluteString
        }
    }
}

public enum ManagedMLXModels {
    public static let downloadDirectoryEnvironmentKey = "ODYSSEY_MLX_DOWNLOAD_DIR"
    public static let legacyDownloadDirectoryEnvironmentKey = "CLAUDESTUDIO_MLX_DOWNLOAD_DIR"

    public static func presets() -> [ManagedMLXModelPreset] {
        [
            ManagedMLXModelPreset(
                modelIdentifier: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
                label: "Qwen3 4B Instruct 2507",
                summary: "Recommended default for everyday local Odyssey work with strong reasoning and tool use.",
                parameterSize: "4B params",
                downloadSize: "~2.6 GB",
                bestFor: "Daily local agent work, repo navigation, coding help, and tool use.",
                agentSuitability: "Strong for agents",
                recommended: true
            ),
            ManagedMLXModelPreset(
                modelIdentifier: "mlx-community/Qwen3-8B-4bit",
                label: "Qwen3 8B",
                summary: "A stronger Qwen3 option when you want better reasoning and can afford more memory.",
                parameterSize: "8B params",
                downloadSize: "~4.9 GB",
                bestFor: "Heavier local agent sessions, stronger reasoning, and longer tasks.",
                agentSuitability: "Very strong for agents",
                recommended: false
            ),
            ManagedMLXModelPreset(
                modelIdentifier: "mlx-community/Qwen2.5-7B-Instruct-4bit",
                label: "Qwen2.5 7B Instruct",
                summary: "Stronger local reasoning and tool use when you can afford a larger model.",
                parameterSize: "7B params",
                downloadSize: "~4.3 GB",
                bestFor: "Longer reasoning, stronger coding help, and beefier Macs.",
                agentSuitability: "Strong for agents",
                recommended: false
            ),
            ManagedMLXModelPreset(
                modelIdentifier: "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
                label: "Qwen2.5 Coder 7B Instruct",
                summary: "Code-focused local model for heavier repository work.",
                parameterSize: "7B params",
                downloadSize: "~4.3 GB",
                bestFor: "Code edits, debugging, and coding-focused local sessions.",
                agentSuitability: "Strong for coding agents",
                recommended: false
            ),
            ManagedMLXModelPreset(
                modelIdentifier: "mlx-community/gemma-4-e2b-it-4bit",
                label: "Gemma 4 E2B Instruct",
                summary: "Google's lightweight edge model with vision capability, fits comfortably on any Apple Silicon Mac.",
                parameterSize: "2B params",
                downloadSize: "~3.6 GB",
                bestFor: "Quick local tasks, image understanding, and low-memory setups.",
                agentSuitability: "Basic agent tool use",
                recommended: false
            ),
            ManagedMLXModelPreset(
                modelIdentifier: "mlx-community/gemma-4-e4b-it-4bit",
                label: "Gemma 4 E4B Instruct",
                summary: "Google's any-to-any edge model — handles text and images with stronger reasoning than E2B.",
                parameterSize: "4B params",
                downloadSize: "~5.2 GB",
                bestFor: "Multimodal local tasks, image analysis, and general assistant work.",
                agentSuitability: "Moderate agent tool use",
                recommended: false
            ),
            ManagedMLXModelPreset(
                modelIdentifier: "mlx-community/gemma-4-26b-a4b-it-4bit",
                label: "Gemma 4 26B MoE Instruct",
                summary: "Google's sparse mixture-of-experts model — large capacity with only 4B active params per token.",
                parameterSize: "26B total / 4B active",
                downloadSize: "~15.6 GB",
                bestFor: "High-quality reasoning with the memory footprint of a 4B model.",
                agentSuitability: "Strong for agents",
                recommended: false
            ),
            ManagedMLXModelPreset(
                modelIdentifier: "mlx-community/gemma-4-31b-it-4bit",
                label: "Gemma 4 31B Instruct",
                summary: "Google's dense 31B flagship — best local quality for complex reasoning and long context on M2 Ultra / M3 Max+.",
                parameterSize: "31B params",
                downloadSize: "~18.4 GB",
                bestFor: "Complex reasoning, long-form tasks, and Macs with 32GB+ unified memory.",
                agentSuitability: "Very strong for agents",
                recommended: false
            ),
        ]
    }

    public static func listModels(
        downloadDirectory explicitDownloadDirectory: String? = nil,
        runnerPath explicitRunnerPath: String? = nil
    ) -> MLXModelsListResult {
        let downloadDirectory = resolveDownloadDirectory(explicitDownloadDirectory)
        return MLXModelsListResult(
            downloadDirectory: downloadDirectory,
            manifestPath: manifestPath(for: downloadDirectory),
            runnerPath: resolveRunner(explicitRunnerPath),
            presets: presets(),
            installed: installedModels(downloadDirectory: downloadDirectory)
        )
    }

    public static func installModel(
        modelIdentifier: String,
        downloadDirectory explicitDownloadDirectory: String? = nil,
        runnerPath explicitRunnerPath: String? = nil
    ) throws -> InstallMLXModelResult {
        let trimmedModelIdentifier = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let installSource = parseInstallSource(trimmedModelIdentifier) else {
            throw ManagedMLXModelsError.invalidModelIdentifier
        }

        guard let runnerPath = resolveRunner(explicitRunnerPath) else {
            throw ManagedMLXModelsError.missingRunner
        }

        let downloadDirectory = resolveDownloadDirectory(explicitDownloadDirectory)
        let manifestPath = manifestPath(for: downloadDirectory)

        try FileManager.default.createDirectory(
            at: URL(fileURLWithPath: downloadDirectory),
            withIntermediateDirectories: true
        )

        switch installSource {
        case .modelIdentifier(let normalizedModelIdentifier),
             .huggingFaceURL(_, let normalizedModelIdentifier):
            let manifest = loadManifest(at: manifestPath)
            if let installed = manifest.installed.first(where: {
                normalizeModelIdentifier($0.modelIdentifier) == normalizedModelIdentifier
            }) {
                return InstallMLXModelResult(
                    modelIdentifier: normalizedModelIdentifier,
                    downloadDirectory: downloadDirectory,
                    manifestPath: manifestPath,
                    runnerPath: runnerPath,
                    alreadyInstalled: true,
                    output: "Model already installed.",
                    installedAt: installed.installedAt
                )
            }

            let output = try runProcess(
                executable: runnerPath,
                arguments: [
                    "eval",
                    "--model", normalizedModelIdentifier,
                    "--download", downloadDirectory,
                    "--prompt", "Hello",
                    "--max-tokens", "1",
                    "--quiet",
                ],
                extraEnvironment: [downloadDirectoryEnvironmentKey: downloadDirectory],
                timeout: nil
            )

            let installedAt = Date()
            let managedPath = firstExistingManagedPath(
                for: normalizedModelIdentifier,
                downloadDirectory: downloadDirectory
            ) ?? preferredManagedPath(
                for: normalizedModelIdentifier,
                downloadDirectory: downloadDirectory
            )
            var updatedManifest = manifest
            updatedManifest.installed.removeAll {
                normalizeModelIdentifier($0.modelIdentifier) == normalizedModelIdentifier
            }
            updatedManifest.installed.append(
                ManagedMLXInstalledModel(
                    modelIdentifier: normalizedModelIdentifier,
                    downloadDirectory: downloadDirectory,
                    installedAt: installedAt,
                    sourceURL: installSource.sourceURL,
                    managedPath: managedPath
                )
            )
            updatedManifest.installed.sort { $0.modelIdentifier.localizedCaseInsensitiveCompare($1.modelIdentifier) == .orderedAscending }
            try saveManifest(updatedManifest, to: manifestPath)

            return InstallMLXModelResult(
                modelIdentifier: normalizedModelIdentifier,
                downloadDirectory: downloadDirectory,
                manifestPath: manifestPath,
                runnerPath: runnerPath,
                alreadyInstalled: false,
                output: output,
                installedAt: installedAt
            )

        case .archiveURL(let archiveURL):
            return try installArchiveModel(
                archiveURL: archiveURL,
                downloadDirectory: downloadDirectory,
                manifestPath: manifestPath,
                runnerPath: runnerPath
            )
        }
    }

    public static func removeModel(
        modelIdentifier: String,
        downloadDirectory explicitDownloadDirectory: String? = nil
    ) throws -> RemoveMLXModelResult {
        let trimmedModelIdentifier = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedModelIdentifier = normalizeModelIdentifier(trimmedModelIdentifier)

        let downloadDirectory = resolveDownloadDirectory(explicitDownloadDirectory)
        let manifestPath = manifestPath(for: downloadDirectory)
        var manifest = loadManifest(at: manifestPath)
        let exactMatch = manifest.installed.first {
            $0.modelIdentifier == trimmedModelIdentifier
        }
        let existing = exactMatch ?? manifest.installed.first {
            guard let normalizedModelIdentifier else { return false }
            return normalizeModelIdentifier($0.modelIdentifier) == normalizedModelIdentifier
        }
        let resolvedModelIdentifier = existing?.modelIdentifier ?? normalizedModelIdentifier
        guard let resolvedModelIdentifier else {
            throw ManagedMLXModelsError.invalidModelIdentifier
        }
        let alreadyRemoved = existing == nil

        var candidatePathGroups: [[String]] = [
            [existing?.managedPath].compactMap { $0 },
            managedPathCandidates(for: resolvedModelIdentifier, downloadDirectory: downloadDirectory),
        ]
        if let normalizedModelIdentifier {
            candidatePathGroups.append(
                managedPathCandidates(for: normalizedModelIdentifier, downloadDirectory: downloadDirectory)
            )
        }
        let candidatePaths = Array(Set(candidatePathGroups.flatMap { $0 }.map(standardizedPath)))

        let allowedRoots = [
            standardizedPath(downloadDirectory),
            standardizedPath(URL(fileURLWithPath: downloadDirectory).deletingLastPathComponent().path),
        ]

        var deletedPaths: [String] = []
        for candidate in candidatePaths {
            guard isDescendant(candidate, ofAny: allowedRoots),
                  FileManager.default.fileExists(atPath: candidate) else {
                continue
            }

            do {
                try FileManager.default.removeItem(atPath: candidate)
                deletedPaths.append(candidate)
                removeEmptyAncestorDirectories(afterDeleting: candidate, stopAt: allowedRoots)
            } catch {
                throw ManagedMLXModelsError.removeFailed(error.localizedDescription)
            }
        }

        manifest.installed.removeAll {
            $0.modelIdentifier == resolvedModelIdentifier
                || (normalizedModelIdentifier != nil && normalizeModelIdentifier($0.modelIdentifier) == normalizedModelIdentifier)
        }
        try saveManifest(manifest, to: manifestPath)

        return RemoveMLXModelResult(
            modelIdentifier: resolvedModelIdentifier,
            downloadDirectory: downloadDirectory,
            manifestPath: manifestPath,
            deletedPaths: deletedPaths.sorted(),
            alreadyRemoved: alreadyRemoved
        )
    }

    public static func installedModels(downloadDirectory explicitDownloadDirectory: String? = nil) -> [ManagedMLXInstalledModel] {
        let downloadDirectory = resolveDownloadDirectory(explicitDownloadDirectory)
        return loadManifest(at: manifestPath(for: downloadDirectory)).installed.map {
            normalizedInstalledModel($0, downloadDirectory: downloadDirectory)
        }
    }

    public static func resolveDownloadDirectory(_ explicitDownloadDirectory: String? = nil) -> String {
        if let explicitDownloadDirectory, !explicitDownloadDirectory.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return standardizedPath(explicitDownloadDirectory)
        }

        if let configured = ProcessInfo.processInfo.environment[downloadDirectoryEnvironmentKey]
            ?? ProcessInfo.processInfo.environment[legacyDownloadDirectoryEnvironmentKey],
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return standardizedPath(configured)
        }

        return standardizedPath("~/.odyssey/local-agent/models/huggingface")
    }

    public static func manifestPath(for downloadDirectory: String) -> String {
        let root = URL(fileURLWithPath: standardizedPath(downloadDirectory))
            .deletingLastPathComponent()
        return root.appendingPathComponent("managed-models.json").path
    }

    public static func resolveRunner(_ explicitRunnerPath: String? = nil) -> String? {
        if let explicitRunnerPath {
            let standardized = standardizedPath(explicitRunnerPath)
            if isRunnableExecutable(atPath: standardized) {
                return standardized
            }
        }

        if let configured = ProcessInfo.processInfo.environment["ODYSSEY_MLX_RUNNER"]
           ?? ProcessInfo.processInfo.environment["CLAUDESTUDIO_MLX_RUNNER"],
           !configured.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let standardized = standardizedPath(configured)
            if isRunnableExecutable(atPath: standardized) {
                return standardized
            }
        }

        let managedRunnerPath = standardizedPath("~/.odyssey/local-agent/bin/llm-tool")
        if isRunnableExecutable(atPath: managedRunnerPath) {
            return managedRunnerPath
        }

        return resolveExecutable(named: "llm-tool")
    }

    public static func looksLikeLocalModelPath(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") || trimmed.hasPrefix("./") || trimmed.hasPrefix("../") {
            return true
        }
        return FileManager.default.fileExists(atPath: standardizedPath(trimmed))
    }

    public static func normalizeModelIdentifier(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !looksLikeLocalModelPath(trimmed) else {
            return nil
        }

        if let url = URL(string: trimmed),
           let host = url.host?.lowercased(),
           ["huggingface.co", "www.huggingface.co", "hf.co"].contains(host) {
            return normalizeHuggingFaceURL(url)
        }

        return normalizePlainModelIdentifier(trimmed)
    }

    private static func parseInstallSource(_ value: String) -> ManagedMLXInstallSource? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !looksLikeLocalModelPath(trimmed) else {
            return nil
        }

        if let url = URL(string: trimmed),
           let scheme = url.scheme?.lowercased(),
           ["http", "https", "file"].contains(scheme) {
            let host = url.host?.lowercased()
            if let host, ["huggingface.co", "www.huggingface.co", "hf.co"].contains(host),
               let normalizedIdentifier = normalizeHuggingFaceURL(url) {
                return .huggingFaceURL(rawValue: trimmed, normalizedIdentifier: normalizedIdentifier)
            }
            guard isSupportedArchiveURL(url) else {
                return nil
            }
            return .archiveURL(url)
        }

        guard let normalizedIdentifier = normalizePlainModelIdentifier(trimmed) else {
            return nil
        }
        return .modelIdentifier(normalizedIdentifier)
    }

    private static func normalizeHuggingFaceURL(_ url: URL) -> String? {
        let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
        guard components.count >= 2 else {
            return nil
        }
        return "\(components[0])/\(components[1])"
    }

    private static func normalizePlainModelIdentifier(_ value: String) -> String? {
        let slashComponents = value.split(separator: "/").map(String.init)
        guard slashComponents.count == 2,
              slashComponents.allSatisfy({ component in
                  !component.isEmpty &&
                  component.rangeOfCharacter(from: .whitespacesAndNewlines) == nil
              }) else {
            return nil
        }
        return "\(slashComponents[0])/\(slashComponents[1])"
    }

    private static func isSupportedArchiveURL(_ url: URL) -> Bool {
        let lowercasedPath = url.path.lowercased()
        return lowercasedPath.hasSuffix(".zip")
            || lowercasedPath.hasSuffix(".tar")
            || lowercasedPath.hasSuffix(".tar.gz")
            || lowercasedPath.hasSuffix(".tgz")
    }

    @discardableResult
    public static func runProcess(
        executable: String,
        arguments: [String],
        currentDirectory: String? = nil,
        extraEnvironment: [String: String] = [:],
        timeout: TimeInterval? = 60
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = environment["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? environment["PATH"]
            : "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        final class OutputBox: @unchecked Sendable {
            var data = Data()
        }
        let outputBox = OutputBox()
        let readerGroup = DispatchGroup()
        readerGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputBox.data = pipe.fileHandleForReading.readDataToEndOfFile()
            readerGroup.leave()
        }

        try process.run()
        if let timeout {
            let deadline = Date().addingTimeInterval(timeout)
            while process.isRunning && Date() < deadline {
                Thread.sleep(forTimeInterval: 0.05)
            }

            if process.isRunning {
                process.terminate()
                _ = readerGroup.wait(timeout: .now() + 2)
                throw ManagedMLXModelsError.installFailed(
                    "Process timed out after \(Int(timeout))s: \(URL(fileURLWithPath: executable).lastPathComponent) \(arguments.joined(separator: " "))"
                )
            }
        } else {
            process.waitUntilExit()
        }

        readerGroup.wait()
        let output = String(decoding: outputBox.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus == 0 else {
            throw ManagedMLXModelsError.installFailed(output)
        }
        return output
    }

    @discardableResult
    public static func runProcessForSession(
        executable: String,
        arguments: [String],
        sessionId: String,
        currentDirectory: String? = nil,
        extraEnvironment: [String: String] = [:],
        timeout: TimeInterval? = 60
    ) async throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let currentDirectory {
            process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)
        }

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = environment["PATH"]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
            ? environment["PATH"]
            : "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        process.environment = environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        final class OutputBox: @unchecked Sendable {
            var data = Data()
        }
        let outputBox = OutputBox()
        let readerGroup = DispatchGroup()
        readerGroup.enter()
        DispatchQueue.global(qos: .userInitiated).async {
            outputBox.data = pipe.fileHandleForReading.readDataToEndOfFile()
            readerGroup.leave()
        }

        try process.run()
        await ManagedMLXProcessRegistry.shared.register(sessionId: sessionId, process: process)
        defer {
            Task {
                await ManagedMLXProcessRegistry.shared.unregister(sessionId: sessionId, process: process)
            }
        }

        let startedAt = Date()
        while process.isRunning {
            try Task.checkCancellation()

            if let timeout, Date().timeIntervalSince(startedAt) >= timeout {
                process.terminate()
                _ = readerGroup.wait(timeout: .now() + 2)
                throw ManagedMLXModelsError.installFailed(
                    "Process timed out after \(Int(timeout))s: \(URL(fileURLWithPath: executable).lastPathComponent) \(arguments.joined(separator: " "))"
                )
            }

            try await Task.sleep(for: .milliseconds(50))
        }

        readerGroup.wait()
        let output = String(decoding: outputBox.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        if Task.isCancelled {
            throw ManagedMLXModelsError.cancelled
        }
        guard process.terminationStatus == 0 else {
            throw ManagedMLXModelsError.installFailed(output)
        }
        return output
    }

    public static func cancelSessionProcess(sessionId: String) async {
        await ManagedMLXProcessRegistry.shared.cancel(sessionId: sessionId)
    }

    private static func installArchiveModel(
        archiveURL: URL,
        downloadDirectory: String,
        manifestPath: String,
        runnerPath: String
    ) throws -> InstallMLXModelResult {
        let manifest = loadManifest(at: manifestPath)
        let tempRoot = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempRoot, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempRoot) }

        let localArchivePath = try localArchivePath(for: archiveURL, tempRoot: tempRoot)
        let extractionDirectory = tempRoot.appendingPathComponent("extracted", isDirectory: true)
        try FileManager.default.createDirectory(at: extractionDirectory, withIntermediateDirectories: true)
        try extractArchive(at: localArchivePath, to: extractionDirectory.path)

        let extractedModelPath = try locateExtractedModelDirectory(in: extractionDirectory.path)
        let archiveModelIdentifier = archiveIdentifier(from: archiveURL, extractedModelPath: extractedModelPath)

        if let installed = manifest.installed.first(where: {
            $0.modelIdentifier == archiveModelIdentifier || $0.sourceURL == archiveURL.absoluteString
        }) {
            return InstallMLXModelResult(
                modelIdentifier: installed.modelIdentifier,
                downloadDirectory: downloadDirectory,
                manifestPath: manifestPath,
                runnerPath: runnerPath,
                alreadyInstalled: true,
                output: "Model already installed.",
                installedAt: installed.installedAt
            )
        }

        let installedAt = Date()
        let managedPath = preferredManagedPath(for: archiveModelIdentifier, downloadDirectory: downloadDirectory)
        let managedURL = URL(fileURLWithPath: managedPath)
        try FileManager.default.createDirectory(at: managedURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: managedPath) {
            try FileManager.default.removeItem(atPath: managedPath)
        }
        try FileManager.default.moveItem(atPath: extractedModelPath, toPath: managedPath)

        var updatedManifest = manifest
        updatedManifest.installed.removeAll {
            $0.modelIdentifier == archiveModelIdentifier || $0.sourceURL == archiveURL.absoluteString
        }
        updatedManifest.installed.append(
            ManagedMLXInstalledModel(
                modelIdentifier: archiveModelIdentifier,
                downloadDirectory: downloadDirectory,
                installedAt: installedAt,
                sourceURL: archiveURL.absoluteString,
                managedPath: managedPath
            )
        )
        updatedManifest.installed.sort { $0.modelIdentifier.localizedCaseInsensitiveCompare($1.modelIdentifier) == .orderedAscending }
        try saveManifest(updatedManifest, to: manifestPath)

        return InstallMLXModelResult(
            modelIdentifier: archiveModelIdentifier,
            downloadDirectory: downloadDirectory,
            manifestPath: manifestPath,
            runnerPath: runnerPath,
            alreadyInstalled: false,
            output: "Imported archive into \(managedPath).",
            installedAt: installedAt
        )
    }

    private static func localArchivePath(for archiveURL: URL, tempRoot: URL) throws -> String {
        if archiveURL.isFileURL {
            return archiveURL.standardizedFileURL.path
        }

        let archiveFileName = archiveURL.lastPathComponent.isEmpty ? "imported-model.archive" : archiveURL.lastPathComponent
        let destinationURL = tempRoot.appendingPathComponent(archiveFileName)
        let data = try Data(contentsOf: archiveURL)
        try data.write(to: destinationURL, options: .atomic)
        return destinationURL.path
    }

    private static func extractArchive(at archivePath: String, to destinationDirectory: String) throws {
        let lowercasedPath = archivePath.lowercased()
        if lowercasedPath.hasSuffix(".zip") {
            _ = try runProcess(
                executable: "/usr/bin/unzip",
                arguments: ["-qq", archivePath, "-d", destinationDirectory],
                timeout: 300
            )
            return
        }

        let tarArguments: [String]
        if lowercasedPath.hasSuffix(".tar.gz") || lowercasedPath.hasSuffix(".tgz") {
            tarArguments = ["-xzf", archivePath, "-C", destinationDirectory]
        } else {
            tarArguments = ["-xf", archivePath, "-C", destinationDirectory]
        }
        _ = try runProcess(executable: "/usr/bin/tar", arguments: tarArguments, timeout: 300)
    }

    private static func locateExtractedModelDirectory(in rootDirectory: String) throws -> String {
        if directoryLooksLikeMLXTextModel(at: rootDirectory) {
            return rootDirectory
        }

        var candidates: [String] = []
        let rootURL = URL(fileURLWithPath: rootDirectory)
        let enumerator = FileManager.default.enumerator(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        while let next = enumerator?.nextObject() as? URL {
            let resourceValues = try next.resourceValues(forKeys: [.isDirectoryKey])
            guard resourceValues.isDirectory == true else {
                continue
            }
            if directoryLooksLikeMLXTextModel(at: next.path) {
                candidates.append(next.path)
            }
        }

        guard let bestCandidate = candidates.sorted(by: { $0.count < $1.count }).first else {
            throw ManagedMLXModelsError.installFailed("The archive did not contain a recognizable MLX text model.")
        }
        return bestCandidate
    }

    private static func directoryLooksLikeMLXTextModel(at path: String) -> Bool {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: URL(fileURLWithPath: path).appendingPathComponent("config.json").path) else {
            return false
        }

        guard let enumerator = fileManager.enumerator(atPath: path) else {
            return false
        }

        var hasWeights = false
        var hasTokenizer = false
        for case let entry as String in enumerator {
            let lowercasedEntry = entry.lowercased()
            if lowercasedEntry.hasSuffix(".safetensors") || lowercasedEntry.hasSuffix("/model.bin") {
                hasWeights = true
            }
            if lowercasedEntry.hasSuffix("tokenizer.json")
                || lowercasedEntry.hasSuffix("tokenizer.model")
                || lowercasedEntry.hasSuffix("tokenizer_config.json") {
                hasTokenizer = true
            }
        }
        return hasWeights && hasTokenizer
    }

    private static func archiveIdentifier(from archiveURL: URL, extractedModelPath: String) -> String {
        let extractedName = URL(fileURLWithPath: extractedModelPath).lastPathComponent
        let candidate = extractedName.isEmpty ? archiveURL.deletingPathExtension().lastPathComponent : extractedName
        return "archive/\(slugifiedIdentifierComponent(candidate))"
    }

    private static func slugifiedIdentifierComponent(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let replaced = trimmed.replacingOccurrences(of: #"[^a-z0-9]+"#, with: "-", options: .regularExpression)
        let collapsed = replaced.replacingOccurrences(of: #"(^-+|-+$)"#, with: "", options: .regularExpression)
        return collapsed.isEmpty ? "imported-model" : collapsed
    }

    private static func loadManifest(at manifestPath: String) -> ManagedMLXManifest {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
              let manifest = try? JSONDecoder().decode(ManagedMLXManifest.self, from: data) else {
            return ManagedMLXManifest()
        }
        return manifest
    }

    private static func saveManifest(_ manifest: ManagedMLXManifest, to manifestPath: String) throws {
        let manifestURL = URL(fileURLWithPath: manifestPath)
        try FileManager.default.createDirectory(
            at: manifestURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(manifest).write(to: manifestURL, options: .atomic)
    }

    private static func standardizedPath(_ path: String) -> String {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath).standardizedFileURL.path
    }

    private static func sourceURL(from value: String) -> String? {
        guard let url = URL(string: value.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host?.lowercased(),
              ["huggingface.co", "www.huggingface.co", "hf.co"].contains(host) else {
            return nil
        }
        return url.absoluteString
    }

    private static func preferredManagedPath(for modelIdentifier: String, downloadDirectory: String) -> String {
        let components = modelIdentifier.split(separator: "/").map(String.init)
        return components.reduce(standardizedPath(downloadDirectory)) { partial, component in
            URL(fileURLWithPath: partial).appendingPathComponent(component).path
        }
    }

    private static func huggingFaceManagedPath(for modelIdentifier: String, downloadDirectory: String) -> String {
        let components = modelIdentifier.split(separator: "/").map(String.init)
        return components.reduce(
            URL(fileURLWithPath: standardizedPath(downloadDirectory)).appendingPathComponent("models").path
        ) { partial, component in
            URL(fileURLWithPath: partial).appendingPathComponent(component).path
        }
    }

    private static func managedPathCandidates(for modelIdentifier: String, downloadDirectory: String) -> [String] {
        let standardizedDownloadDirectory = standardizedPath(downloadDirectory)
        let rootDirectory = standardizedPath(
            URL(fileURLWithPath: standardizedDownloadDirectory).deletingLastPathComponent().path
        )
        let namespacedCacheDirectory = "models--" + modelIdentifier.replacingOccurrences(of: "/", with: "--")
        return Array(Set([
            huggingFaceManagedPath(for: modelIdentifier, downloadDirectory: standardizedDownloadDirectory),
            preferredManagedPath(for: modelIdentifier, downloadDirectory: standardizedDownloadDirectory),
            URL(fileURLWithPath: standardizedDownloadDirectory).appendingPathComponent(namespacedCacheDirectory).path,
            URL(fileURLWithPath: rootDirectory).appendingPathComponent(namespacedCacheDirectory).path,
        ]))
    }

    private static func firstExistingManagedPath(for modelIdentifier: String, downloadDirectory: String) -> String? {
        managedPathCandidates(for: modelIdentifier, downloadDirectory: downloadDirectory)
            .first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    private static func normalizedInstalledModel(
        _ model: ManagedMLXInstalledModel,
        downloadDirectory: String
    ) -> ManagedMLXInstalledModel {
        let recordedManagedPath = model.managedPath.map(standardizedPath)
        if let recordedManagedPath, FileManager.default.fileExists(atPath: recordedManagedPath) {
            return model
        }

        guard let resolvedManagedPath = firstExistingManagedPath(
            for: model.modelIdentifier,
            downloadDirectory: downloadDirectory
        ) else {
            return model
        }

        return ManagedMLXInstalledModel(
            modelIdentifier: model.modelIdentifier,
            downloadDirectory: model.downloadDirectory,
            installedAt: model.installedAt,
            sourceURL: model.sourceURL,
            managedPath: resolvedManagedPath
        )
    }

    private static func isDescendant(_ path: String, ofAny roots: [String]) -> Bool {
        let standardized = standardizedPath(path)
        return roots.contains { root in
            let standardizedRoot = standardizedPath(root)
            return standardized == standardizedRoot || standardized.hasPrefix(standardizedRoot + "/")
        }
    }

    private static func removeEmptyAncestorDirectories(afterDeleting deletedPath: String, stopAt roots: [String]) {
        let fileManager = FileManager.default
        var current = URL(fileURLWithPath: deletedPath).deletingLastPathComponent().path

        while isDescendant(current, ofAny: roots) && !roots.map(standardizedPath).contains(standardizedPath(current)) {
            let contents = (try? fileManager.contentsOfDirectory(atPath: current)) ?? []
            guard contents.isEmpty else {
                break
            }
            try? fileManager.removeItem(atPath: current)
            current = URL(fileURLWithPath: current).deletingLastPathComponent().path
        }
    }

    private static func resolveExecutable(named command: String) -> String? {
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"
        for entry in path.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(entry)).appendingPathComponent(command).path
            if isRunnableExecutable(atPath: candidate) {
                return candidate
            }
        }
        return nil
    }

    private static func isRunnableExecutable(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: path)
    }
}
