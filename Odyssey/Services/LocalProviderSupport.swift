import Foundation

#if canImport(FoundationModels)
import FoundationModels
#endif

struct LocalProviderStatusReport: Equatable {
    let hostSummary: String
    let hostBinaryPath: String?
    let packagePath: String?
    let foundationAvailable: Bool
    let foundationSummary: String
    let mlxAvailable: Bool
    let mlxSummary: String
    let mlxRunnerPath: String?
    let mlxDownloadDirectory: String
    let installedMLXModels: [ManagedInstalledMLXModel]
    let ollamaEnabled: Bool
    let ollamaBaseURL: String
    let ollamaAvailable: Bool
    let ollamaSummary: String
    let ollamaModels: [OllamaCachedModel]
}

enum LocalProviderSupport {
    static let bundledHostRelativePath = "local-agent/bin/OdysseyLocalAgentHost"
    static let bundledMLXRunnerRelativePath = "local-agent/bin/llm-tool"
    static let packageRelativePath = "Packages/OdysseyLocalAgent"
    static let sidecarRelativePath = "sidecar/src/index.ts"
    static let bundledBunName = "odyssey-bun"
    static let sidecarJSBundleName = "odyssey-sidecar.js"
    static let sourceRootInfoKey = "ODYSSEY_SOURCE_ROOT"

    static func resolveHostBinaryPath(
        bundleResourcePath: String? = Bundle.main.resourcePath,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        projectRootOverride: String? = nil,
        hostOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.localAgentHostPathOverrideKey)
    ) -> String? {
        if let override = normalizedFilePath(hostOverride) {
            return override
        }

        if let bundleResourcePath {
            let bundled = URL(fileURLWithPath: bundleResourcePath)
                .appendingPathComponent(bundledHostRelativePath)
                .path
            if FileManager.default.isExecutableFile(atPath: bundled) {
                return bundled
            }
        }

        return nil
    }

    static func resolvePackagePath(
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        projectRootOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.sidecarPathKey),
        bundledSourceRoot: String? = preferredBundledSourceRoot(),
        fallbackProjectRoots: [String]? = nil
    ) -> String? {
        let fileManager = FileManager.default
        let candidates = preferredProjectRoots(
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride,
            bundledSourceRoot: bundledSourceRoot,
            fallbackProjectRoots: fallbackProjectRoots
        )
            .map { URL(fileURLWithPath: $0).appendingPathComponent(packageRelativePath).path }

        for candidate in candidates where fileManager.fileExists(atPath: candidate) {
            return candidate
        }

        return nil
    }

    static func resolveSidecarPath(
        bundleResourcePath: String? = Bundle.main.resourcePath,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        projectRootOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.sidecarPathKey),
        bundledSourceRoot: String? = preferredBundledSourceRoot(),
        fallbackProjectRoots: [String]? = nil
    ) -> String? {
        let fileManager = FileManager.default

        if let bundleResourcePath {
            let bundledSidecarPath = URL(fileURLWithPath: bundleResourcePath)
                .appendingPathComponent(sidecarRelativePath)
                .path
            if fileManager.fileExists(atPath: bundledSidecarPath) {
                return bundledSidecarPath
            }
        }

        let candidatePaths = preferredProjectRoots(
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride,
            bundledSourceRoot: bundledSourceRoot,
            fallbackProjectRoots: fallbackProjectRoots
        )
            .map { URL(fileURLWithPath: $0).appendingPathComponent(sidecarRelativePath).path }

        for candidate in candidatePaths where fileManager.fileExists(atPath: candidate) {
            return candidate
        }

        return candidatePaths.first
    }

    /// Returns `(bunPath, jsPath)` when a bundled bun runtime + JS bundle are present
    /// in the app resources — used for distribution builds where the sidecar TypeScript
    /// source is not available on the target machine.
    static func resolveBundledSidecar(
        bundleResourcePath: String? = Bundle.main.resourcePath
    ) -> (bunPath: String, jsPath: String)? {
        guard let resourcePath = bundleResourcePath else { return nil }
        let base = URL(fileURLWithPath: resourcePath)
        let bunPath = base.appendingPathComponent(bundledBunName).path
        let jsPath = base.appendingPathComponent(sidecarJSBundleName).path
        guard FileManager.default.isExecutableFile(atPath: bunPath),
              FileManager.default.fileExists(atPath: jsPath) else { return nil }
        return (bunPath, jsPath)
    }

    static func resolveMLXRunnerPath(
        bundleResourcePath: String? = Bundle.main.resourcePath,
        runnerOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.mlxRunnerPathOverrideKey),
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory,
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) -> String? {
        if let override = normalizedExecutablePath(runnerOverride) {
            return override
        }

        if let bundleResourcePath {
            let bundled = URL(fileURLWithPath: bundleResourcePath)
                .appendingPathComponent(bundledMLXRunnerRelativePath)
                .path
            if let resolved = normalizedExecutablePath(bundled) {
                return resolved
            }
        }

        if let managed = normalizedExecutablePath(
            LocalProviderInstaller.managedMLXRunnerInstallPath(dataDirectoryPath: dataDirectoryPath)
        ) {
            return managed
        }

        return resolveExecutable(named: "llm-tool", pathEnvironment: pathEnvironment)
    }

    static func environmentValues(
        bundleResourcePath: String? = Bundle.main.resourcePath,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        projectRootOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.sidecarPathKey),
        hostOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.localAgentHostPathOverrideKey),
        mlxRunnerOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.mlxRunnerPathOverrideKey),
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> [String: String] {
        var environment: [String: String] = [:]
        if let hostBinaryPath = resolveHostBinaryPath(
            bundleResourcePath: bundleResourcePath,
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride,
            hostOverride: hostOverride
        ) {
            environment["ODYSSEY_LOCAL_AGENT_HOST_BINARY"] = hostBinaryPath
            environment["CLAUDESTUDIO_LOCAL_AGENT_HOST_BINARY"] = hostBinaryPath
        }

        if let packagePath = resolvePackagePath(
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride
        ) {
            environment["ODYSSEY_LOCAL_AGENT_PACKAGE_PATH"] = packagePath
            environment["CLAUDESTUDIO_LOCAL_AGENT_PACKAGE_PATH"] = packagePath
        }

        if let mlxRunnerPath = resolveMLXRunnerPath(
            bundleResourcePath: bundleResourcePath,
            runnerOverride: mlxRunnerOverride,
            dataDirectoryPath: dataDirectoryPath
        ) {
            environment["ODYSSEY_MLX_RUNNER"] = mlxRunnerPath
            environment["CLAUDESTUDIO_MLX_RUNNER"] = mlxRunnerPath
        }
        let downloadDirectory = LocalProviderInstaller.managedMLXDownloadDirectory(dataDirectoryPath: dataDirectoryPath)
        environment["ODYSSEY_MLX_DOWNLOAD_DIR"] = downloadDirectory
        environment["CLAUDESTUDIO_MLX_DOWNLOAD_DIR"] = downloadDirectory
        let ollamaBaseURL = OllamaCatalogService.normalizedBaseURL(
            InstanceConfig.userDefaults.string(forKey: AppSettings.ollamaBaseURLKey)
        )
        let ollamaEnabled = OllamaCatalogService.modelsEnabled(defaults: InstanceConfig.userDefaults)
        environment["ODYSSEY_OLLAMA_BASE_URL"] = ollamaBaseURL
        environment["CLAUDESTUDIO_OLLAMA_BASE_URL"] = ollamaBaseURL
        environment["ODYSSEY_OLLAMA_MODELS_ENABLED"] = ollamaEnabled ? "1" : "0"
        environment["CLAUDESTUDIO_OLLAMA_MODELS_ENABLED"] = ollamaEnabled ? "1" : "0"

        return environment
    }

    static func statusReport(
        bundleResourcePath: String? = Bundle.main.resourcePath,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        projectRootOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.sidecarPathKey),
        hostOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.localAgentHostPathOverrideKey),
        mlxRunnerOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.mlxRunnerPathOverrideKey),
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory,
        defaultMLXModel: String = InstanceConfig.userDefaults.string(forKey: AppSettings.defaultMLXModelKey) ?? AppSettings.defaultMLXModel,
        ollamaBaseURL: String = OllamaCatalogService.normalizedBaseURL(
            InstanceConfig.userDefaults.string(forKey: AppSettings.ollamaBaseURLKey)
        ),
        ollamaEnabled: Bool = OllamaCatalogService.modelsEnabled(defaults: InstanceConfig.userDefaults)
    ) -> LocalProviderStatusReport {
        let hostBinaryPath = resolveHostBinaryPath(
            bundleResourcePath: bundleResourcePath,
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride,
            hostOverride: hostOverride
        )
        let packagePath = resolvePackagePath(
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride
        )
        let mlxRunnerPath = resolveMLXRunnerPath(
            bundleResourcePath: bundleResourcePath,
            runnerOverride: mlxRunnerOverride,
            dataDirectoryPath: dataDirectoryPath
        )
        let mlxDownloadDirectory = LocalProviderInstaller.managedMLXDownloadDirectory(
            dataDirectoryPath: dataDirectoryPath
        )
        let installedMLXModels = LocalProviderInstaller.installedMLXModels(
            dataDirectoryPath: dataDirectoryPath
        )
        let hostSummary: String = {
            if let hostBinaryPath {
                return "Bundled local-agent host: \(hostBinaryPath)"
            }
            if let packagePath {
                return "Development package available at \(packagePath)"
            }
            return "Local-agent host not found. Build the app bundle or set a host override."
        }()

        let foundationStatus = foundationAvailability(hostBinaryPath: hostBinaryPath, packagePath: packagePath)
        let mlxStatus = mlxAvailability(
            hostBinaryPath: hostBinaryPath,
            packagePath: packagePath,
            mlxRunnerPath: mlxRunnerPath,
            defaultMLXModel: defaultMLXModel,
            installedModels: installedMLXModels,
            downloadDirectory: mlxDownloadDirectory
        )
        let cachedOllamaStatus = OllamaCatalogService.cachedStatus(defaults: InstanceConfig.userDefaults)
        let cachedOllamaModels = ollamaEnabled && cachedOllamaStatus?.baseURL == ollamaBaseURL
            ? OllamaCatalogService.cachedModels(defaults: InstanceConfig.userDefaults)
            : []
        let resolvedOllamaSummary: String = {
            guard ollamaEnabled else {
                return "Ollama-backed Claude models are disabled."
            }
            guard let cachedOllamaStatus else {
                return "Ollama status has not been checked yet. Refresh the Models tab to detect local models."
            }
            guard cachedOllamaStatus.baseURL == ollamaBaseURL else {
                return "Ollama base URL changed to \(ollamaBaseURL). Refresh to load models from the new endpoint."
            }
            return cachedOllamaStatus.summary
        }()
        let resolvedOllamaAvailable = ollamaEnabled
            && cachedOllamaStatus?.baseURL == ollamaBaseURL
            && cachedOllamaStatus?.available == true

        return LocalProviderStatusReport(
            hostSummary: hostSummary,
            hostBinaryPath: hostBinaryPath,
            packagePath: packagePath,
            foundationAvailable: foundationStatus.available,
            foundationSummary: foundationStatus.summary,
            mlxAvailable: mlxStatus.available,
            mlxSummary: mlxStatus.summary,
            mlxRunnerPath: mlxRunnerPath,
            mlxDownloadDirectory: mlxDownloadDirectory,
            installedMLXModels: installedMLXModels,
            ollamaEnabled: ollamaEnabled,
            ollamaBaseURL: ollamaBaseURL,
            ollamaAvailable: resolvedOllamaAvailable,
            ollamaSummary: resolvedOllamaSummary,
            ollamaModels: cachedOllamaModels
        )
    }

    private static func foundationAvailability(hostBinaryPath: String?, packagePath: String?) -> (available: Bool, summary: String) {
        guard hostBinaryPath != nil || packagePath != nil else {
            return (false, "Local-agent host is not available yet.")
        }

        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) {
            let model = SystemLanguageModel.default
            if model.isAvailable {
                return (true, "Foundation Models is available on this Mac.")
            }

            return (false, foundationReason(for: model.availability))
        }
        #endif

        return (false, "Requires macOS 26+ with Apple Foundation Models support.")
    }

    private static func mlxAvailability(
        hostBinaryPath: String?,
        packagePath: String?,
        mlxRunnerPath: String?,
        defaultMLXModel: String,
        installedModels: [ManagedInstalledMLXModel],
        downloadDirectory: String
    ) -> (available: Bool, summary: String) {
        guard hostBinaryPath != nil || packagePath != nil else {
            return (false, "Local-agent host is not available yet.")
        }
        guard let mlxRunnerPath else {
            return (false, "Install the MLX runner from Settings or configure an existing llm-tool path.")
        }

        let trimmedModel = defaultMLXModel.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModel.isEmpty else {
            return (false, "Set a default MLX model identifier or local path in Settings.")
        }

        if looksLikeLocalModelPath(trimmedModel) {
            let resolvedPath = normalizedDirectoryPath(trimmedModel) ?? trimmedModel
            guard FileManager.default.fileExists(atPath: resolvedPath) else {
                return (false, "Configured MLX model path does not exist: \(resolvedPath)")
            }
            return (true, "MLX is ready using runner \(mlxRunnerPath) and local model path \(resolvedPath).")
        }

        if installedModels.contains(where: { $0.modelIdentifier == trimmedModel }) {
            return (true, "MLX is ready using runner \(mlxRunnerPath) with cached model \(trimmedModel).")
        }

        return (true, "MLX is configured with runner \(mlxRunnerPath). The model \(trimmedModel) will download into \(downloadDirectory) on first use, or you can install it now from Settings.")
    }

    private static func normalizedFilePath(_ path: String?) -> String? {
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        let expanded = NSString(string: trimmed).expandingTildeInPath
        let standardized = URL(fileURLWithPath: expanded).standardizedFileURL.path
        return FileManager.default.fileExists(atPath: standardized) ? standardized : nil
    }

    private static func normalizedExecutablePath(_ path: String?) -> String? {
        guard let normalized = normalizedFilePath(path) else {
            return nil
        }

        return isRunnableExecutable(atPath: normalized) ? normalized : nil
    }

    private static func normalizedDirectoryPath(_ path: String?) -> String? {
        guard let trimmed = path?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else {
            return nil
        }

        return URL(fileURLWithPath: NSString(string: trimmed).expandingTildeInPath)
            .standardizedFileURL
            .path
    }

    private static func preferredBundledSourceRoot(bundle: Bundle = .main) -> String? {
        normalizedDirectoryPath(bundle.object(forInfoDictionaryKey: sourceRootInfoKey) as? String)
    }

    private static func preferredProjectRoots(
        currentDirectoryPath: String,
        projectRootOverride: String?,
        bundledSourceRoot: String?,
        fallbackProjectRoots: [String]?
    ) -> [String] {
        let rawFallbacks = fallbackProjectRoots ?? [
            NSHomeDirectory().appending("/Odyssey"),
            NSHomeDirectory().appending("/ClaudPeer"),
        ]
        let rawCandidates = [
            projectRootOverride,
            bundledSourceRoot,
            currentDirectoryPath,
        ] + rawFallbacks

        var seen = Set<String>()
        return rawCandidates
            .compactMap { normalizedDirectoryPath($0) }
            .filter { seen.insert($0).inserted }
    }

    private static func looksLikeLocalModelPath(_ path: String) -> Bool {
        path.hasPrefix("/")
            || path.hasPrefix("~/")
            || path.hasPrefix("./")
            || path.hasPrefix("../")
    }

    private static func resolveExecutable(named executableName: String, pathEnvironment: String) -> String? {
        for entry in pathEnvironment.split(separator: ":") {
            let candidate = URL(fileURLWithPath: String(entry)).appendingPathComponent(executableName).path
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

    #if canImport(FoundationModels)
    @available(macOS 26.0, *)
    private static func foundationReason(for availability: SystemLanguageModel.Availability) -> String {
        switch availability {
        case .available:
            return "Foundation Models is available on this Mac."
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This Mac is not eligible for Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Turn on Apple Intelligence to use Foundation Models."
            case .modelNotReady:
                return "The Apple on-device model is still preparing."
            @unknown default:
                return "Foundation Models is unavailable on this Mac."
            }
        }
    }
    #endif
}
