import Foundation

enum LocalProviderInstallerError: LocalizedError {
    case missingExecutable(name: String)
    case missingHost
    case cloneFailed(String)
    case buildFailed(String)
    case binaryNotFound(String)
    case invalidModelIdentifier
    case unsupportedArchiveURL
    case installFailed(String)
    case removeFailed(String)
    case smokeTestFailed(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable(let name):
            return "Required executable not found: \(name). Install Xcode command line tools and try again."
        case .missingHost:
            return "Odyssey local-agent host is not available. Build the app bundle or configure a host override."
        case .cloneFailed(let output):
            return output.isEmpty ? "Failed to download the MLX runner sources." : output
        case .buildFailed(let output):
            return output.isEmpty ? "Failed to build the MLX runner." : output
        case .binaryNotFound(let path):
            return "Built MLX runner was not found at \(path)."
        case .invalidModelIdentifier:
            return "Enter a Hugging Face repo id, a Hugging Face URL, or a direct archive URL ending in .zip, .tar, .tar.gz, or .tgz."
        case .unsupportedArchiveURL:
            return "Archive URLs must end in .zip, .tar, .tar.gz, or .tgz."
        case .installFailed(let output):
            return output.isEmpty ? "Failed to install the MLX model." : output
        case .removeFailed(let output):
            return output.isEmpty ? "Failed to remove the MLX model." : output
        case .smokeTestFailed(let output):
            return output.isEmpty ? "Failed to run the MLX smoke test." : output
        }
    }
}

enum ManagedMLXInstallSourceKind: String, Codable, Equatable {
    case modelIdentifier
    case huggingFaceURL
    case archiveURL
}

struct ManagedMLXInstallSource: Equatable {
    let rawValue: String
    let kind: ManagedMLXInstallSourceKind
}

struct ManagedMLXModelPreset: Codable, Equatable, Identifiable {
    var id: String { modelIdentifier }
    let modelIdentifier: String
    let label: String
    let summary: String
    let parameterSize: String
    let downloadSize: String
    let bestFor: String
    let agentSuitability: String
    let recommended: Bool

    init(
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

struct ManagedInstalledMLXModel: Codable, Equatable, Identifiable {
    var id: String { modelIdentifier }
    let modelIdentifier: String
    let downloadDirectory: String
    let installedAt: Date
    let sourceURL: String?
    let managedPath: String?

    init(
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

struct ManagedInstalledMLXManifest: Codable, Equatable {
    var installed: [ManagedInstalledMLXModel] = []
}

struct ManagedMLXModelsCatalog: Codable, Equatable {
    let downloadDirectory: String
    let manifestPath: String
    let runnerPath: String?
    let presets: [ManagedMLXModelPreset]
    let installed: [ManagedInstalledMLXModel]
}

struct ManagedMLXInstallResult: Codable, Equatable {
    let modelIdentifier: String
    let downloadDirectory: String
    let manifestPath: String
    let runnerPath: String
    let alreadyInstalled: Bool
    let output: String
    let installedAt: Date
}

struct ManagedMLXDeleteResult: Codable, Equatable {
    let modelIdentifier: String
    let downloadDirectory: String
    let manifestPath: String
    let deletedPaths: [String]
    let alreadyRemoved: Bool
}

struct ManagedMLXSmokeTestResult: Codable, Equatable {
    let modelReference: String
    let durationSeconds: Double
    let success: Bool
    let outputPreview: String?
    let errorMessage: String?
}

private struct SmokeTestTurnResponse: Decodable {
    let resultText: String
}

enum LocalProviderInstaller {
    static let managedToolsRelativePath = "local-agent"
    static let managedMLXSourceRelativePath = "local-agent/mlx-swift-examples"
    static let managedMLXBinaryRelativePath = "local-agent/bin/llm-tool"
    static let managedMLXRuntimeRelativePath = "local-agent/runtime/llm-tool-release"
    static let managedMLXDownloadRelativePath = "local-agent/models/huggingface"
    static let managedMLXManifestRelativePath = "local-agent/models/managed-models.json"
    static let mlxSwiftExamplesURL = "https://github.com/ml-explore/mlx-swift-examples.git"

    static func recommendedMLXPresets() -> [ManagedMLXModelPreset] {
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

    static func managedToolsDirectory(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> String {
        expandedDirectoryPath(dataDirectoryPath)
            .appending("/\(managedToolsRelativePath)")
    }

    static func managedMLXSourceDirectory(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> String {
        expandedDirectoryPath(dataDirectoryPath)
            .appending("/\(managedMLXSourceRelativePath)")
    }

    static func managedMLXRunnerInstallPath(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> String {
        expandedDirectoryPath(dataDirectoryPath)
            .appending("/\(managedMLXBinaryRelativePath)")
    }

    static func managedMLXDownloadDirectory(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> String {
        expandedDirectoryPath(dataDirectoryPath)
            .appending("/\(managedMLXDownloadRelativePath)")
    }

    static func managedMLXModelsDirectory(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> String {
        expandedDirectoryPath(dataDirectoryPath)
            .appending("/local-agent/models")
    }

    static func managedMLXRuntimeDirectory(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> String {
        expandedDirectoryPath(dataDirectoryPath)
            .appending("/\(managedMLXRuntimeRelativePath)")
    }

    static func managedMLXManifestPath(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> String {
        expandedDirectoryPath(dataDirectoryPath)
            .appending("/\(managedMLXManifestRelativePath)")
    }

    static func installMLXRunner(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory,
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) async throws -> String {
        let fileManager = FileManager.default
        let sourceDirectory = managedMLXSourceDirectory(dataDirectoryPath: dataDirectoryPath)
        let installPath = managedMLXRunnerInstallPath(dataDirectoryPath: dataDirectoryPath)
        let installDirectory = URL(fileURLWithPath: installPath).deletingLastPathComponent().path

        try fileManager.createDirectory(atPath: installDirectory, withIntermediateDirectories: true)

        let git = try requiredExecutable(named: "git", pathEnvironment: pathEnvironment)
        let xcodebuild = try requiredExecutable(named: "xcodebuild", pathEnvironment: pathEnvironment)

        if !fileManager.fileExists(atPath: sourceDirectory) {
            let checkoutParent = URL(fileURLWithPath: sourceDirectory).deletingLastPathComponent().path
            try fileManager.createDirectory(atPath: checkoutParent, withIntermediateDirectories: true)
            let cloneOutput = try runCommand(
                executable: git,
                arguments: ["clone", "--depth", "1", mlxSwiftExamplesURL, sourceDirectory],
                currentDirectory: checkoutParent,
                pathEnvironment: pathEnvironment
            )
            if !fileManager.fileExists(atPath: sourceDirectory) {
                throw LocalProviderInstallerError.cloneFailed(cloneOutput)
            }
        }

        let derivedDataPath = URL(fileURLWithPath: sourceDirectory)
            .appendingPathComponent(".odyssey-derived")
            .path

        _ = try runCommand(
            executable: xcodebuild,
            arguments: [
                "-project", "mlx-swift-examples.xcodeproj",
                "-scheme", "llm-tool",
                "-configuration", "Release",
                "-derivedDataPath", derivedDataPath,
                "CODE_SIGNING_ALLOWED=NO",
                "CODE_SIGNING_REQUIRED=NO",
                "build",
            ],
            currentDirectory: sourceDirectory,
            pathEnvironment: pathEnvironment
        )

        let builtProductsDirectory = URL(fileURLWithPath: derivedDataPath)
            .appendingPathComponent("Build/Products/Release")
            .path
        try installBuiltMLXRunnerProducts(
            builtProductsDirectory: builtProductsDirectory,
            installPath: installPath,
            dataDirectoryPath: dataDirectoryPath
        )
        return installPath
    }

    static func installMLXModel(
        modelIdentifier: String,
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory,
        bundleResourcePath: String? = Bundle.main.resourcePath,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        projectRootOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.sidecarPathKey),
        hostOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.localAgentHostPathOverrideKey),
        runnerOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.mlxRunnerPathOverrideKey),
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) async throws -> ManagedMLXInstallResult {
        let trimmedModelIdentifier = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard installSource(from: trimmedModelIdentifier) != nil else {
            throw LocalProviderInstallerError.invalidModelIdentifier
        }

        let runnerPath = try await ensureMLXRunner(
            dataDirectoryPath: dataDirectoryPath,
            runnerOverride: runnerOverride,
            pathEnvironment: pathEnvironment
        )
        let downloadDirectory = managedMLXDownloadDirectory(dataDirectoryPath: dataDirectoryPath)

        if let hostBinaryPath = LocalProviderSupport.resolveHostBinaryPath(
            bundleResourcePath: bundleResourcePath,
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride,
            hostOverride: hostOverride
        ) {
            let output = try runCommand(
                executable: hostBinaryPath,
                arguments: [
                    "install-model",
                    "--model", trimmedModelIdentifier,
                    "--download-dir", downloadDirectory,
                    "--runner", runnerPath,
                    "--json",
                ],
                currentDirectory: currentDirectoryPath,
                pathEnvironment: pathEnvironment,
                extraEnvironment: [
                    "ODYSSEY_MLX_DOWNLOAD_DIR": downloadDirectory,
                    "CLAUDESTUDIO_MLX_DOWNLOAD_DIR": downloadDirectory,
                ]
            )

            guard let data = output.data(using: .utf8) else {
                throw LocalProviderInstallerError.installFailed(output)
            }
            return try JSONDecoder().decode(ManagedMLXInstallResult.self, from: data)
        }

        guard let packagePath = LocalProviderSupport.resolvePackagePath(
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride
        ) else {
            throw LocalProviderInstallerError.missingHost
        }

        let xcrun = try requiredExecutable(named: "xcrun", pathEnvironment: pathEnvironment)
        let output = try runCommand(
            executable: xcrun,
            arguments: [
                "swift", "run", "--package-path", packagePath, "OdysseyLocalAgentHost",
                "install-model",
                "--model", trimmedModelIdentifier,
                "--download-dir", downloadDirectory,
                "--runner", runnerPath,
                "--json",
            ],
            currentDirectory: packagePath,
            pathEnvironment: pathEnvironment,
            extraEnvironment: [
                "ODYSSEY_MLX_DOWNLOAD_DIR": downloadDirectory,
                "CLAUDESTUDIO_MLX_DOWNLOAD_DIR": downloadDirectory,
            ]
        )
        guard let data = output.data(using: .utf8) else {
            throw LocalProviderInstallerError.installFailed(output)
        }
        return try JSONDecoder().decode(ManagedMLXInstallResult.self, from: data)
    }

    static func listMLXModels(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory,
        bundleResourcePath: String? = Bundle.main.resourcePath,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        projectRootOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.sidecarPathKey),
        hostOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.localAgentHostPathOverrideKey),
        runnerOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.mlxRunnerPathOverrideKey),
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) async throws -> ManagedMLXModelsCatalog {
        let downloadDirectory = managedMLXDownloadDirectory(dataDirectoryPath: dataDirectoryPath)

        if let hostBinaryPath = LocalProviderSupport.resolveHostBinaryPath(
            bundleResourcePath: bundleResourcePath,
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride,
            hostOverride: hostOverride
        ) {
            let output = try runCommand(
                executable: hostBinaryPath,
                arguments: [
                    "models",
                    "--download-dir", downloadDirectory,
                    "--json",
                ] + mlxRunnerArguments(
                    runnerOverride: runnerOverride,
                    dataDirectoryPath: dataDirectoryPath,
                    pathEnvironment: pathEnvironment
                ),
                currentDirectory: currentDirectoryPath,
                pathEnvironment: pathEnvironment,
                extraEnvironment: [
                    "ODYSSEY_MLX_DOWNLOAD_DIR": downloadDirectory,
                    "CLAUDESTUDIO_MLX_DOWNLOAD_DIR": downloadDirectory,
                ]
            )
            guard let data = output.data(using: .utf8) else {
                throw LocalProviderInstallerError.installFailed(output)
            }
            return try JSONDecoder().decode(ManagedMLXModelsCatalog.self, from: data)
        }

        guard let packagePath = LocalProviderSupport.resolvePackagePath(
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride
        ) else {
            throw LocalProviderInstallerError.missingHost
        }

        let xcrun = try requiredExecutable(named: "xcrun", pathEnvironment: pathEnvironment)
        let output = try runCommand(
            executable: xcrun,
            arguments: [
                "swift", "run", "--package-path", packagePath, "OdysseyLocalAgentHost",
                "models",
                "--download-dir", downloadDirectory,
                "--json",
            ] + mlxRunnerArguments(
                runnerOverride: runnerOverride,
                dataDirectoryPath: dataDirectoryPath,
                pathEnvironment: pathEnvironment
            ),
            currentDirectory: packagePath,
            pathEnvironment: pathEnvironment,
            extraEnvironment: [
                "ODYSSEY_MLX_DOWNLOAD_DIR": downloadDirectory,
                "CLAUDESTUDIO_MLX_DOWNLOAD_DIR": downloadDirectory,
            ]
        )
        guard let data = output.data(using: .utf8) else {
            throw LocalProviderInstallerError.installFailed(output)
        }
        return try JSONDecoder().decode(ManagedMLXModelsCatalog.self, from: data)
    }

    static func deleteMLXModel(
        modelIdentifier: String,
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory,
        bundleResourcePath: String? = Bundle.main.resourcePath,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        projectRootOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.sidecarPathKey),
        hostOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.localAgentHostPathOverrideKey),
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) async throws -> ManagedMLXDeleteResult {
        let trimmedModelIdentifier = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidDeletionReference(trimmedModelIdentifier) else {
            throw LocalProviderInstallerError.invalidModelIdentifier
        }

        let downloadDirectory = managedMLXDownloadDirectory(dataDirectoryPath: dataDirectoryPath)

        if let hostBinaryPath = LocalProviderSupport.resolveHostBinaryPath(
            bundleResourcePath: bundleResourcePath,
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride,
            hostOverride: hostOverride
        ) {
            let output = try runCommand(
                executable: hostBinaryPath,
                arguments: [
                    "remove-model",
                    "--model", trimmedModelIdentifier,
                    "--download-dir", downloadDirectory,
                    "--json",
                ],
                currentDirectory: currentDirectoryPath,
                pathEnvironment: pathEnvironment,
                extraEnvironment: [
                    "ODYSSEY_MLX_DOWNLOAD_DIR": downloadDirectory,
                    "CLAUDESTUDIO_MLX_DOWNLOAD_DIR": downloadDirectory,
                ]
            )
            guard let data = output.data(using: .utf8) else {
                throw LocalProviderInstallerError.removeFailed(output)
            }
            return try JSONDecoder().decode(ManagedMLXDeleteResult.self, from: data)
        }

        guard let packagePath = LocalProviderSupport.resolvePackagePath(
            currentDirectoryPath: currentDirectoryPath,
            projectRootOverride: projectRootOverride
        ) else {
            throw LocalProviderInstallerError.missingHost
        }

        let xcrun = try requiredExecutable(named: "xcrun", pathEnvironment: pathEnvironment)
        let output = try runCommand(
            executable: xcrun,
            arguments: [
                "swift", "run", "--package-path", packagePath, "OdysseyLocalAgentHost",
                "remove-model",
                "--model", trimmedModelIdentifier,
                "--download-dir", downloadDirectory,
                "--json",
            ],
            currentDirectory: packagePath,
            pathEnvironment: pathEnvironment,
            extraEnvironment: [
                "ODYSSEY_MLX_DOWNLOAD_DIR": downloadDirectory,
                "CLAUDESTUDIO_MLX_DOWNLOAD_DIR": downloadDirectory,
            ]
        )
        guard let data = output.data(using: .utf8) else {
            throw LocalProviderInstallerError.removeFailed(output)
        }
        return try JSONDecoder().decode(ManagedMLXDeleteResult.self, from: data)
    }

    static func smokeTestMLXModel(
        modelReference: String,
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory,
        bundleResourcePath: String? = Bundle.main.resourcePath,
        currentDirectoryPath: String = FileManager.default.currentDirectoryPath,
        projectRootOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.sidecarPathKey),
        hostOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.localAgentHostPathOverrideKey),
        runnerOverride: String? = InstanceConfig.userDefaults.string(forKey: AppSettings.mlxRunnerPathOverrideKey),
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? ""
    ) async throws -> ManagedMLXSmokeTestResult {
        let trimmedModelReference = modelReference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedModelReference.isEmpty else {
            throw LocalProviderInstallerError.smokeTestFailed("Choose an installed MLX model to test first.")
        }

        let runnerPath = try await ensureMLXRunner(
            dataDirectoryPath: dataDirectoryPath,
            runnerOverride: runnerOverride,
            pathEnvironment: pathEnvironment
        )
        let downloadDirectory = managedMLXDownloadDirectory(dataDirectoryPath: dataDirectoryPath)
        let prompt = "Reply with the exact text: odyssey mlx smoke test ok"
        let startedAt = Date()

        func buildResult(success: Bool, output: String?, errorMessage: String?) -> ManagedMLXSmokeTestResult {
            ManagedMLXSmokeTestResult(
                modelReference: trimmedModelReference,
                durationSeconds: Date().timeIntervalSince(startedAt),
                success: success,
                outputPreview: output.flatMap(firstPreviewLine(from:)),
                errorMessage: errorMessage
            )
        }

        do {
            let output: String
            if let hostBinaryPath = LocalProviderSupport.resolveHostBinaryPath(
                bundleResourcePath: bundleResourcePath,
                currentDirectoryPath: currentDirectoryPath,
                projectRootOverride: projectRootOverride,
                hostOverride: hostOverride
            ) {
                output = try runCommand(
                    executable: hostBinaryPath,
                    arguments: [
                        "run",
                        "--provider", "mlx",
                        "--model", trimmedModelReference,
                        "--cwd", currentDirectoryPath,
                        "--system-prompt", "Reply briefly in plain text.",
                        "--prompt", prompt,
                        "--json",
                    ],
                    currentDirectory: currentDirectoryPath,
                    pathEnvironment: pathEnvironment,
                    extraEnvironment: [
                        "ODYSSEY_MLX_DOWNLOAD_DIR": downloadDirectory,
                        "CLAUDESTUDIO_MLX_DOWNLOAD_DIR": downloadDirectory,
                        "ODYSSEY_MLX_RUNNER": runnerPath,
                        "CLAUDESTUDIO_MLX_RUNNER": runnerPath,
                    ]
                )
            } else {
                guard let packagePath = LocalProviderSupport.resolvePackagePath(
                    currentDirectoryPath: currentDirectoryPath,
                    projectRootOverride: projectRootOverride
                ) else {
                    throw LocalProviderInstallerError.missingHost
                }

                let xcrun = try requiredExecutable(named: "xcrun", pathEnvironment: pathEnvironment)
                output = try runCommand(
                    executable: xcrun,
                    arguments: [
                        "swift", "run", "--package-path", packagePath, "OdysseyLocalAgentHost",
                        "run",
                        "--provider", "mlx",
                        "--model", trimmedModelReference,
                        "--cwd", currentDirectoryPath,
                        "--system-prompt", "Reply briefly in plain text.",
                        "--prompt", prompt,
                        "--json",
                    ],
                    currentDirectory: packagePath,
                    pathEnvironment: pathEnvironment,
                    extraEnvironment: [
                        "ODYSSEY_MLX_DOWNLOAD_DIR": downloadDirectory,
                        "CLAUDESTUDIO_MLX_DOWNLOAD_DIR": downloadDirectory,
                        "ODYSSEY_MLX_RUNNER": runnerPath,
                        "CLAUDESTUDIO_MLX_RUNNER": runnerPath,
                    ]
                )
            }

            guard let data = output.data(using: .utf8) else {
                return buildResult(success: false, output: nil, errorMessage: "The smoke test did not return valid JSON.")
            }

            let response = try JSONDecoder().decode(SmokeTestTurnResponse.self, from: data)
            let preview = response.resultText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !preview.isEmpty else {
                return buildResult(success: false, output: nil, errorMessage: "The smoke test finished but produced no output.")
            }
            return buildResult(success: true, output: preview, errorMessage: nil)
        } catch {
            return buildResult(success: false, output: nil, errorMessage: error.localizedDescription)
        }
    }

    static func installedMLXModels(
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> [ManagedInstalledMLXModel] {
        let downloadDirectory = managedMLXDownloadDirectory(dataDirectoryPath: dataDirectoryPath)
        let manifestPath = managedMLXManifestPath(dataDirectoryPath: dataDirectoryPath)
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: manifestPath)),
              let manifest = try? JSONDecoder().decode(ManagedInstalledMLXManifest.self, from: data) else {
            return []
        }
        return manifest.installed
            .map { normalizedInstalledModel($0, downloadDirectory: downloadDirectory) }
            .sorted { $0.modelIdentifier.localizedCaseInsensitiveCompare($1.modelIdentifier) == .orderedAscending }
    }

    static func managedMLXDownloadedBytes(
        for modelIdentifier: String,
        dataDirectoryPath: String = InstanceConfig.userDefaults.string(forKey: AppSettings.dataDirectoryKey)
            ?? AppSettings.defaultDataDirectory
    ) -> Int64 {
        let trimmedModelIdentifier = modelIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let normalizedModelIdentifier = normalizedMLXModelIdentifier(trimmedModelIdentifier) ?? archiveModelIdentifier(from: trimmedModelIdentifier),
              !normalizedModelIdentifier.isEmpty else {
            return 0
        }

        let downloadDirectory = managedMLXDownloadDirectory(dataDirectoryPath: dataDirectoryPath)
        return managedPathCandidates(for: normalizedModelIdentifier, downloadDirectory: downloadDirectory)
            .map(directorySize(atPath:))
            .max() ?? 0
    }

    private static func expandedDirectoryPath(_ path: String) -> String {
        URL(fileURLWithPath: NSString(string: path).expandingTildeInPath)
            .standardizedFileURL
            .path
    }

    private static func requiredExecutable(named name: String, pathEnvironment: String) throws -> String {
        if let resolved = resolveExecutable(named: name, pathEnvironment: pathEnvironment) {
            return resolved
        }
        throw LocalProviderInstallerError.missingExecutable(name: name)
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

    @discardableResult
    private static func runCommand(
        executable: String,
        arguments: [String],
        currentDirectory: String,
        pathEnvironment: String,
        extraEnvironment: [String: String] = [:]
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.currentDirectoryURL = URL(fileURLWithPath: currentDirectory)

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = pathEnvironment
        for (key, value) in extraEnvironment {
            environment[key] = value
        }
        process.environment = environment

        let outputPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = outputPipe

        try process.run()
        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: outputData, encoding: .utf8) ?? ""

        guard process.terminationStatus == 0 else {
            if arguments.contains("clone") {
                throw LocalProviderInstallerError.cloneFailed(output)
            }
            throw LocalProviderInstallerError.buildFailed(output)
        }

        return output
    }

    private static func ensureMLXRunner(
        dataDirectoryPath: String,
        runnerOverride: String?,
        pathEnvironment: String
    ) async throws -> String {
        if let resolved = LocalProviderSupport.resolveMLXRunnerPath(
            runnerOverride: runnerOverride,
            dataDirectoryPath: dataDirectoryPath,
            pathEnvironment: pathEnvironment
        ) {
            return resolved
        }

        return try await installMLXRunner(
            dataDirectoryPath: dataDirectoryPath,
            pathEnvironment: pathEnvironment
        )
    }

    private static func looksLikeLocalModelPath(_ value: String) -> Bool {
        if value.hasPrefix("/") || value.hasPrefix("~/") || value.hasPrefix("./") || value.hasPrefix("../") {
            return true
        }
        return FileManager.default.fileExists(atPath: expandedDirectoryPath(value))
    }

    static func normalizedMLXModelIdentifier(_ value: String) -> String? {
        guard let installSource = installSource(from: value) else {
            return nil
        }

        if installSource.kind == .archiveURL {
            return nil
        }

        let trimmed = installSource.rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: trimmed),
           let host = url.host?.lowercased(),
           ["huggingface.co", "www.huggingface.co", "hf.co"].contains(host) {
            let components = url.pathComponents.filter { $0 != "/" && !$0.isEmpty }
            guard components.count >= 2 else {
                return nil
            }
            return "\(components[0])/\(components[1])"
        }

        let components = trimmed.split(separator: "/").map(String.init)
        guard components.count == 2,
              components.allSatisfy({ !$0.isEmpty && $0.rangeOfCharacter(from: .whitespacesAndNewlines) == nil }) else {
            return nil
        }

        return "\(components[0])/\(components[1])"
    }

    static func installBuiltMLXRunnerProducts(
        builtProductsDirectory: String,
        installPath: String,
        dataDirectoryPath: String
    ) throws {
        let fileManager = FileManager.default
        let runtimeDirectory = managedMLXRuntimeDirectory(dataDirectoryPath: dataDirectoryPath)
        let builtProductsURL = URL(fileURLWithPath: builtProductsDirectory)
        let builtBinaryPath = builtProductsURL.appendingPathComponent("llm-tool").path

        guard fileManager.isExecutableFile(atPath: builtBinaryPath) else {
            throw LocalProviderInstallerError.binaryNotFound(builtBinaryPath)
        }

        let installDirectory = URL(fileURLWithPath: installPath).deletingLastPathComponent().path
        try fileManager.createDirectory(atPath: installDirectory, withIntermediateDirectories: true)

        if fileManager.fileExists(atPath: runtimeDirectory) {
            try fileManager.removeItem(atPath: runtimeDirectory)
        }
        try fileManager.createDirectory(atPath: runtimeDirectory, withIntermediateDirectories: true)

        try copyItem(at: builtBinaryPath, intoDirectory: runtimeDirectory, fileManager: fileManager)

        let builtItems = try fileManager.contentsOfDirectory(atPath: builtProductsDirectory)
        for item in builtItems where item == "PackageFrameworks" || item.hasSuffix(".bundle") {
            try copyItem(
                at: builtProductsURL.appendingPathComponent(item).path,
                intoDirectory: runtimeDirectory,
                fileManager: fileManager
            )
        }

        if fileManager.fileExists(atPath: installPath) {
            try fileManager.removeItem(atPath: installPath)
        }
        try managedMLXWrapperScript().write(
            to: URL(fileURLWithPath: installPath),
            atomically: true,
            encoding: .utf8
        )
        try fileManager.setAttributes([.posixPermissions: 0o755], ofItemAtPath: installPath)
    }

    static func managedMLXWrapperScript() -> String {
        """
        #!/bin/sh
        set -e

        SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
        RUNTIME_DIR="$SCRIPT_DIR/../runtime/llm-tool-release"

        if [ ! -x "$RUNTIME_DIR/llm-tool" ]; then
          echo "Managed MLX runner is incomplete at $RUNTIME_DIR" >&2
          exit 1
        fi

        if [ -d "$RUNTIME_DIR/PackageFrameworks" ]; then
          export DYLD_FRAMEWORK_PATH="$RUNTIME_DIR/PackageFrameworks:$RUNTIME_DIR${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
        else
          export DYLD_FRAMEWORK_PATH="$RUNTIME_DIR${DYLD_FRAMEWORK_PATH:+:$DYLD_FRAMEWORK_PATH}"
        fi

        exec "$RUNTIME_DIR/llm-tool" "$@"
        """
    }

    private static func copyItem(
        at sourcePath: String,
        intoDirectory destinationDirectory: String,
        fileManager: FileManager
    ) throws {
        let destinationPath = URL(fileURLWithPath: destinationDirectory)
            .appendingPathComponent(URL(fileURLWithPath: sourcePath).lastPathComponent)
            .path

        if fileManager.fileExists(atPath: destinationPath) {
            try fileManager.removeItem(atPath: destinationPath)
        }
        try fileManager.copyItem(atPath: sourcePath, toPath: destinationPath)
    }

    private static func isRunnableExecutable(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
              !isDirectory.boolValue else {
            return false
        }
        return FileManager.default.isExecutableFile(atPath: path)
    }

    private static func mlxRunnerArguments(
        runnerOverride: String?,
        dataDirectoryPath: String,
        pathEnvironment: String
    ) -> [String] {
        guard let resolved = LocalProviderSupport.resolveMLXRunnerPath(
            runnerOverride: runnerOverride,
            dataDirectoryPath: dataDirectoryPath,
            pathEnvironment: pathEnvironment
        ) else {
            return []
        }
        return ["--runner", resolved]
    }

    static func installSource(from value: String) -> ManagedMLXInstallSource? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !looksLikeLocalModelPath(trimmed) else { return nil }
        if let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(), ["http", "https", "file"].contains(scheme) {
            let host = url.host?.lowercased()
            if let host, ["huggingface.co", "www.huggingface.co", "hf.co"].contains(host) {
                return ManagedMLXInstallSource(rawValue: trimmed, kind: .huggingFaceURL)
            }
            guard isSupportedArchiveURL(url) else { return nil }
            return ManagedMLXInstallSource(rawValue: trimmed, kind: .archiveURL)
        }

        let components = trimmed.split(separator: "/").map(String.init)
        guard components.count == 2,
              components.allSatisfy({ !$0.isEmpty && $0.rangeOfCharacter(from: .whitespacesAndNewlines) == nil }) else { return nil }
        return ManagedMLXInstallSource(rawValue: trimmed, kind: .modelIdentifier)
    }

    private static func isSupportedArchiveURL(_ url: URL) -> Bool {
        let lowercasedPath = url.path.lowercased()
        return lowercasedPath.hasSuffix(".zip")
            || lowercasedPath.hasSuffix(".tar")
            || lowercasedPath.hasSuffix(".tar.gz")
            || lowercasedPath.hasSuffix(".tgz")
    }

    private static func isValidDeletionReference(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !looksLikeLocalModelPath(trimmed) else { return false }
        return true
    }

    private static func firstPreviewLine(from output: String) -> String? {
        let preview = output
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .first(where: { !$0.isEmpty })
        guard let preview else { return nil }
        if preview.count > 160 { return String(preview.prefix(157)) + "..." }
        return preview
    }

    private static func normalizedInstalledModel(
        _ model: ManagedInstalledMLXModel,
        downloadDirectory: String
    ) -> ManagedInstalledMLXModel {
        let recordedManagedPath = model.managedPath.map(expandedDirectoryPath)
        if let recordedManagedPath, FileManager.default.fileExists(atPath: recordedManagedPath) {
            return model
        }

        guard let resolvedManagedPath = firstExistingManagedPath(
            for: model.modelIdentifier,
            downloadDirectory: downloadDirectory
        ) else {
            return model
        }

        return ManagedInstalledMLXModel(
            modelIdentifier: model.modelIdentifier,
            downloadDirectory: model.downloadDirectory,
            installedAt: model.installedAt,
            sourceURL: model.sourceURL,
            managedPath: resolvedManagedPath
        )
    }

    private static func firstExistingManagedPath(for modelIdentifier: String, downloadDirectory: String) -> String? {
        managedPathCandidates(for: modelIdentifier, downloadDirectory: downloadDirectory)
            .first(where: { FileManager.default.fileExists(atPath: $0) })
    }

    private static func managedPathCandidates(for modelIdentifier: String, downloadDirectory: String) -> [String] {
        let standardizedDownloadDirectory = expandedDirectoryPath(downloadDirectory)
        let rootDirectory = expandedDirectoryPath(
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

    private static func preferredManagedPath(for modelIdentifier: String, downloadDirectory: String) -> String {
        let components = modelIdentifier.split(separator: "/").map(String.init)
        return components.reduce(expandedDirectoryPath(downloadDirectory)) { partial, component in
            URL(fileURLWithPath: partial).appendingPathComponent(component).path
        }
    }

    private static func huggingFaceManagedPath(for modelIdentifier: String, downloadDirectory: String) -> String {
        let components = modelIdentifier.split(separator: "/").map(String.init)
        return components.reduce(
            URL(fileURLWithPath: expandedDirectoryPath(downloadDirectory)).appendingPathComponent("models").path
        ) { partial, component in
            URL(fileURLWithPath: partial).appendingPathComponent(component).path
        }
    }

    private static func archiveModelIdentifier(from value: String) -> String? {
        guard let url = URL(string: value), isSupportedArchiveURL(url) else {
            return nil
        }
        let lastComponent = url.deletingPathExtension().lastPathComponent
            .replacingOccurrences(of: ".tar", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lastComponent.isEmpty else { return nil }
        return "archive/\(lastComponent)"
    }

    private static func directorySize(atPath path: String) -> Int64 {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) else {
            return 0
        }
        if !isDirectory.boolValue {
            let attributes = try? FileManager.default.attributesOfItem(atPath: path)
            return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        }

        guard let enumerator = FileManager.default.enumerator(
            at: URL(fileURLWithPath: path),
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [],
            errorHandler: nil
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            guard let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
                  values.isRegularFile == true,
                  let size = values.fileSize else {
                continue
            }
            total += Int64(size)
        }
        return total
    }
}
