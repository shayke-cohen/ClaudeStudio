import Foundation
import XCTest
@testable import Odyssey

final class LocalProviderSupportTests: XCTestCase {
    private var tempDirectory: URL!

    override func setUp() {
        super.setUp()
        tempDirectory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }

    override func tearDown() {
        if let tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        tempDirectory = nil
        super.tearDown()
    }

    func testResolveHostBinaryPathPrefersBundledExecutable() throws {
        let resourceDirectory = tempDirectory.appendingPathComponent("Resources")
        let hostDirectory = resourceDirectory.appendingPathComponent("local-agent/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: hostDirectory, withIntermediateDirectories: true)
        let hostPath = hostDirectory.appendingPathComponent("OdysseyLocalAgentHost")
        FileManager.default.createFile(atPath: hostPath.path, contents: Data("echo host".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hostPath.path)

        let resolved = LocalProviderSupport.resolveHostBinaryPath(
            bundleResourcePath: resourceDirectory.path,
            currentDirectoryPath: tempDirectory.path,
            projectRootOverride: nil,
            hostOverride: nil
        )

        XCTAssertEqual(resolved, hostPath.path)
    }

    func testResolvePackagePathFindsPackageUnderProjectOverride() throws {
        let projectRoot = tempDirectory.appendingPathComponent("Project")
        let packageDirectory = projectRoot.appendingPathComponent("Packages/OdysseyLocalAgent", isDirectory: true)
        try FileManager.default.createDirectory(at: packageDirectory, withIntermediateDirectories: true)

        let resolved = LocalProviderSupport.resolvePackagePath(
            currentDirectoryPath: "/tmp/does-not-exist",
            projectRootOverride: projectRoot.path
        )

        XCTAssertEqual(resolved, packageDirectory.path)
    }

    func testResolvePackagePathPrefersBundledSourceRootOverFallbackRoots() throws {
        let fallbackRoot = tempDirectory.appendingPathComponent("LegacyWorkspace")
        let bundledRoot = tempDirectory.appendingPathComponent("CurrentWorkspace")
        try FileManager.default.createDirectory(
            at: fallbackRoot.appendingPathComponent("Packages/OdysseyLocalAgent", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: bundledRoot.appendingPathComponent("Packages/OdysseyLocalAgent", isDirectory: true),
            withIntermediateDirectories: true
        )

        let resolved = LocalProviderSupport.resolvePackagePath(
            currentDirectoryPath: "/tmp/does-not-exist",
            projectRootOverride: nil,
            bundledSourceRoot: bundledRoot.path,
            fallbackProjectRoots: [fallbackRoot.path]
        )

        XCTAssertEqual(
            resolved,
            bundledRoot.appendingPathComponent("Packages/OdysseyLocalAgent").path
        )
    }

    func testResolveSidecarPathPrefersBundledSourceRootOverFallbackRoots() throws {
        let fallbackRoot = tempDirectory.appendingPathComponent("LegacyWorkspace")
        let bundledRoot = tempDirectory.appendingPathComponent("CurrentWorkspace")
        try makeSidecarWorkspace(at: fallbackRoot)
        try makeSidecarWorkspace(at: bundledRoot)

        let resolved = LocalProviderSupport.resolveSidecarPath(
            bundleResourcePath: nil,
            currentDirectoryPath: "/tmp/does-not-exist",
            projectRootOverride: nil,
            bundledSourceRoot: bundledRoot.path,
            fallbackProjectRoots: [fallbackRoot.path]
        )

        XCTAssertEqual(
            resolved,
            bundledRoot.appendingPathComponent("sidecar/src/index.ts").path
        )
    }

    func testEnvironmentValuesIncludeDetectedAssets() throws {
        AppSettings.store.set(false, forKey: AppSettings.ollamaModelsEnabledKey)
        AppSettings.store.set("http://127.0.0.1:22434", forKey: AppSettings.ollamaBaseURLKey)
        defer {
            AppSettings.store.removeObject(forKey: AppSettings.ollamaModelsEnabledKey)
            AppSettings.store.removeObject(forKey: AppSettings.ollamaBaseURLKey)
        }

        let resourceDirectory = tempDirectory.appendingPathComponent("Resources")
        let hostDirectory = resourceDirectory.appendingPathComponent("local-agent/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: hostDirectory, withIntermediateDirectories: true)
        let hostPath = hostDirectory.appendingPathComponent("OdysseyLocalAgentHost")
        FileManager.default.createFile(atPath: hostPath.path, contents: Data("echo host".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hostPath.path)

        let runnerPath = hostDirectory.appendingPathComponent("llm-tool")
        FileManager.default.createFile(atPath: runnerPath.path, contents: Data("echo runner".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runnerPath.path)

        let environment = LocalProviderSupport.environmentValues(
            bundleResourcePath: resourceDirectory.path,
            currentDirectoryPath: tempDirectory.path,
            projectRootOverride: nil,
            hostOverride: nil,
            mlxRunnerOverride: nil,
            dataDirectoryPath: tempDirectory.path
        )

        XCTAssertEqual(environment["ODYSSEY_LOCAL_AGENT_HOST_BINARY"], hostPath.path)
        XCTAssertEqual(environment["ODYSSEY_MLX_RUNNER"], runnerPath.path)
        XCTAssertEqual(
            environment["ODYSSEY_MLX_DOWNLOAD_DIR"],
            LocalProviderInstaller.managedMLXDownloadDirectory(dataDirectoryPath: tempDirectory.path)
        )
        XCTAssertEqual(environment["ODYSSEY_OLLAMA_BASE_URL"], "http://127.0.0.1:22434")
        XCTAssertEqual(environment["ODYSSEY_OLLAMA_MODELS_ENABLED"], "0")
    }

    func testResolveMLXRunnerPathPrefersManagedInstallLocation() throws {
        let managedRunnerPath = URL(fileURLWithPath: LocalProviderInstaller.managedMLXRunnerInstallPath(
            dataDirectoryPath: tempDirectory.path
        ))
        try FileManager.default.createDirectory(
            at: managedRunnerPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: managedRunnerPath.path, contents: Data("echo runner".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: managedRunnerPath.path)

        let resolved = LocalProviderSupport.resolveMLXRunnerPath(
            bundleResourcePath: nil,
            runnerOverride: nil,
            dataDirectoryPath: tempDirectory.path,
            pathEnvironment: ""
        )

        XCTAssertEqual(resolved, managedRunnerPath.path)
    }

    func testResolveMLXRunnerPathPrefersBundledExecutableOverManagedInstall() throws {
        let resourceDirectory = tempDirectory.appendingPathComponent("Resources")
        let bundledRunnerDirectory = resourceDirectory.appendingPathComponent("local-agent/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: bundledRunnerDirectory, withIntermediateDirectories: true)
        let bundledRunnerPath = bundledRunnerDirectory.appendingPathComponent("llm-tool")
        FileManager.default.createFile(atPath: bundledRunnerPath.path, contents: Data("echo bundled".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundledRunnerPath.path)

        let managedRunnerPath = URL(fileURLWithPath: LocalProviderInstaller.managedMLXRunnerInstallPath(
            dataDirectoryPath: tempDirectory.path
        ))
        try FileManager.default.createDirectory(
            at: managedRunnerPath.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: managedRunnerPath.path, contents: Data("echo managed".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: managedRunnerPath.path)

        let resolved = LocalProviderSupport.resolveMLXRunnerPath(
            bundleResourcePath: resourceDirectory.path,
            runnerOverride: nil,
            dataDirectoryPath: tempDirectory.path,
            pathEnvironment: ""
        )

        XCTAssertEqual(resolved, bundledRunnerPath.path)
    }

    func testResolveMLXRunnerPathIgnoresDirectoryNamedLikeRunner() throws {
        let fakeToolsDirectory = tempDirectory.appendingPathComponent("fake-bin", isDirectory: true)
        let fakeRunnerDirectory = fakeToolsDirectory.appendingPathComponent("llm-tool", isDirectory: true)
        try FileManager.default.createDirectory(at: fakeRunnerDirectory, withIntermediateDirectories: true)

        let resolved = LocalProviderSupport.resolveMLXRunnerPath(
            bundleResourcePath: nil,
            runnerOverride: fakeRunnerDirectory.path,
            dataDirectoryPath: tempDirectory.path,
            pathEnvironment: fakeToolsDirectory.path
        )

        XCTAssertNil(resolved)
    }

    func testManagedMLXModelsDirectoryUsesManagedRoot() {
        XCTAssertEqual(
            LocalProviderInstaller.managedMLXModelsDirectory(dataDirectoryPath: tempDirectory.path),
            tempDirectory.appendingPathComponent("local-agent/models").path
        )
    }

    func testManagedMLXDownloadedBytesReadsCurrentManagedPathLayout() throws {
        let modelPath = tempDirectory
            .appendingPathComponent("local-agent/models/huggingface/models/mlx-community/Qwen3-14B-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: modelPath, withIntermediateDirectories: true)
        let weightsURL = modelPath.appendingPathComponent("weights.safetensors")
        let payload = Data(repeating: 7, count: 4_096)
        FileManager.default.createFile(atPath: weightsURL.path, contents: payload)

        XCTAssertEqual(
            LocalProviderInstaller.managedMLXDownloadedBytes(
                for: "mlx-community/Qwen3-14B-4bit",
                dataDirectoryPath: tempDirectory.path
            ),
            Int64(payload.count)
        )
    }

    func testManagedMLXDownloadedBytesCountsHiddenCachePayloads() throws {
        let modelPath = tempDirectory
            .appendingPathComponent("local-agent/models/huggingface/models/mlx-community/Qwen3-8B-4bit/.cache/huggingface/download", isDirectory: true)
        try FileManager.default.createDirectory(at: modelPath, withIntermediateDirectories: true)
        let partialURL = modelPath.appendingPathComponent("model-partial.bin")
        let payload = Data(repeating: 3, count: 8_192)
        FileManager.default.createFile(atPath: partialURL.path, contents: payload)

        XCTAssertEqual(
            LocalProviderInstaller.managedMLXDownloadedBytes(
                for: "mlx-community/Qwen3-8B-4bit",
                dataDirectoryPath: tempDirectory.path
            ),
            Int64(payload.count)
        )
    }

    func testNormalizedMLXModelIdentifierAcceptsHuggingFaceURL() {
        let normalized = LocalProviderInstaller.normalizedMLXModelIdentifier(
            "https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit"
        )

        XCTAssertEqual(normalized, "mlx-community/Qwen2.5-1.5B-Instruct-4bit")
    }

    func testNormalizedMLXModelIdentifierRejectsInvalidURL() {
        XCTAssertNil(LocalProviderInstaller.normalizedMLXModelIdentifier("https://example.com/not-hugging-face"))
    }

    func testNormalizedMLXModelIdentifierRejectsArchiveURL() {
        XCTAssertNil(
            LocalProviderInstaller.normalizedMLXModelIdentifier(
                "https://example.com/models/local-model.tar.gz"
            )
        )
    }

    func testInstallSourceAcceptsRepoIDsAndURLs() {
        let archiveURL = tempDirectory.appendingPathComponent("qwen3-archive.tar.gz")

        XCTAssertEqual(
            LocalProviderInstaller.installSource(from: "mlx-community/Qwen3-4B-Instruct-2507-4bit")?.kind,
            .modelIdentifier
        )
        XCTAssertEqual(
            LocalProviderInstaller.installSource(
                from: "https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit"
            )?.kind,
            .huggingFaceURL
        )
        XCTAssertEqual(
            LocalProviderInstaller.installSource(from: archiveURL.absoluteString)?.kind,
            .archiveURL
        )
    }

    func testInstallSourceRejectsUnsupportedInputs() throws {
        let localModelDirectory = tempDirectory.appendingPathComponent("local-model", isDirectory: true)
        try FileManager.default.createDirectory(at: localModelDirectory, withIntermediateDirectories: true)

        XCTAssertNil(LocalProviderInstaller.installSource(from: "https://example.com/model.bin"))
        XCTAssertNil(LocalProviderInstaller.installSource(from: localModelDirectory.path))
        XCTAssertNil(LocalProviderInstaller.installSource(from: "not a model"))
    }

    func testRecommendedMLXPresetsExposeGuidanceFields() {
        let presets = LocalProviderInstaller.recommendedMLXPresets()

        XCTAssertFalse(presets.isEmpty)
        XCTAssertTrue(presets.allSatisfy { !$0.parameterSize.isEmpty })
        XCTAssertTrue(presets.allSatisfy { !$0.downloadSize.isEmpty })
        XCTAssertTrue(presets.allSatisfy { !$0.bestFor.isEmpty })
        XCTAssertTrue(presets.allSatisfy { !$0.agentSuitability.isEmpty })
    }

    func testRecommendedMLXPresetsMatchCuratedList() {
        XCTAssertEqual(
            LocalProviderInstaller.recommendedMLXPresets().map(\.modelIdentifier),
            [
                "mlx-community/Qwen3-4B-Instruct-2507-4bit",
                "mlx-community/Qwen3-8B-4bit",
                "mlx-community/Qwen2.5-7B-Instruct-4bit",
                "mlx-community/Qwen2.5-Coder-7B-Instruct-4bit",
            ]
        )
    }

    func testInstalledMLXModelsHealHuggingFaceManagedPathLayout() throws {
        let downloadDirectory = LocalProviderInstaller.managedMLXDownloadDirectory(dataDirectoryPath: tempDirectory.path)
        let actualManagedPath = URL(fileURLWithPath: downloadDirectory)
            .appendingPathComponent("models/mlx-community/Qwen3-4B-Instruct-2507-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: actualManagedPath, withIntermediateDirectories: true)

        let manifest = ManagedInstalledMLXManifest(installed: [
            ManagedInstalledMLXModel(
                modelIdentifier: "mlx-community/Qwen3-4B-Instruct-2507-4bit",
                downloadDirectory: downloadDirectory,
                installedAt: Date(),
                sourceURL: "https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit",
                managedPath: URL(fileURLWithPath: downloadDirectory)
                    .appendingPathComponent("mlx-community/Qwen3-4B-Instruct-2507-4bit", isDirectory: true)
                    .path
            )
        ])
        let manifestURL = URL(fileURLWithPath: LocalProviderInstaller.managedMLXManifestPath(dataDirectoryPath: tempDirectory.path))
        try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(manifest).write(to: manifestURL)

        let installed = LocalProviderInstaller.installedMLXModels(dataDirectoryPath: tempDirectory.path)
        XCTAssertEqual(installed.first?.managedPath, actualManagedPath.path)
    }

    func testSmokeTestMLXModelReturnsPreviewOnSuccess() async throws {
        let runnerPath = tempDirectory.appendingPathComponent("llm-tool")
        FileManager.default.createFile(atPath: runnerPath.path, contents: Data("echo runner".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runnerPath.path)

        let fakeHostPath = tempDirectory.appendingPathComponent("fake-local-agent-host")
        let fakeHostScript = """
        #!/bin/sh
        set -e

        if [ "$1" = "run" ]; then
          printf '%s\n' '{"backendSessionId":"smoke-session","resultText":"odyssey mlx smoke test ok","inputTokens":1,"outputTokens":1,"numTurns":1,"events":[]}'
          exit 0
        fi

        echo "unexpected command: $1" >&2
        exit 1
        """
        try fakeHostScript.write(to: fakeHostPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeHostPath.path)

        let result = try await LocalProviderInstaller.smokeTestMLXModel(
            modelReference: "archive/qwen3-demo",
            dataDirectoryPath: tempDirectory.path,
            bundleResourcePath: nil,
            currentDirectoryPath: tempDirectory.path,
            projectRootOverride: tempDirectory.path,
            hostOverride: fakeHostPath.path,
            runnerOverride: runnerPath.path
        )

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.outputPreview, "odyssey mlx smoke test ok")
        XCTAssertNil(result.errorMessage)
        XCTAssertGreaterThanOrEqual(result.durationSeconds, 0)
    }

    func testSmokeTestMLXModelReturnsFailureDetails() async throws {
        let runnerPath = tempDirectory.appendingPathComponent("llm-tool")
        FileManager.default.createFile(atPath: runnerPath.path, contents: Data("echo runner".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runnerPath.path)

        let fakeHostPath = tempDirectory.appendingPathComponent("fake-local-agent-host")
        let fakeHostScript = """
        #!/bin/sh
        echo "simulated smoke test failure" >&2
        exit 1
        """
        try fakeHostScript.write(to: fakeHostPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeHostPath.path)

        let result = try await LocalProviderInstaller.smokeTestMLXModel(
            modelReference: "archive/qwen3-demo",
            dataDirectoryPath: tempDirectory.path,
            bundleResourcePath: nil,
            currentDirectoryPath: tempDirectory.path,
            projectRootOverride: tempDirectory.path,
            hostOverride: fakeHostPath.path,
            runnerOverride: runnerPath.path
        )

        XCTAssertFalse(result.success)
        XCTAssertNil(result.outputPreview)
        XCTAssertTrue(result.errorMessage?.contains("simulated smoke test failure") == true)
    }

    func testStatusReportMarksCachedManagedModelAsReady() throws {
        let resourceDirectory = tempDirectory.appendingPathComponent("Resources")
        let hostDirectory = resourceDirectory.appendingPathComponent("local-agent/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: hostDirectory, withIntermediateDirectories: true)
        let hostPath = hostDirectory.appendingPathComponent("OdysseyLocalAgentHost")
        FileManager.default.createFile(atPath: hostPath.path, contents: Data("echo host".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hostPath.path)

        let runnerPath = tempDirectory.appendingPathComponent("llm-tool")
        FileManager.default.createFile(atPath: runnerPath.path, contents: Data("echo runner".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runnerPath.path)

        let manifest = ManagedInstalledMLXManifest(installed: [
            ManagedInstalledMLXModel(
                modelIdentifier: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                downloadDirectory: LocalProviderInstaller.managedMLXDownloadDirectory(dataDirectoryPath: tempDirectory.path),
                installedAt: Date()
            )
        ])
        let manifestData = try JSONEncoder().encode(manifest)
        let manifestURL = URL(fileURLWithPath: LocalProviderInstaller.managedMLXManifestPath(dataDirectoryPath: tempDirectory.path))
        try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manifestData.write(to: manifestURL)

        let report = LocalProviderSupport.statusReport(
            bundleResourcePath: resourceDirectory.path,
            currentDirectoryPath: tempDirectory.path,
            projectRootOverride: nil,
            hostOverride: nil,
            mlxRunnerOverride: runnerPath.path,
            dataDirectoryPath: tempDirectory.path,
            defaultMLXModel: "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
        )

        XCTAssertTrue(report.mlxAvailable)
        XCTAssertTrue(report.mlxSummary.contains("cached model"))
        XCTAssertEqual(report.installedMLXModels.map(\.modelIdentifier), ["mlx-community/Qwen2.5-1.5B-Instruct-4bit"])
    }

    func testDeleteMLXModelUpdatesStatusReport() async throws {
        let resourceDirectory = tempDirectory.appendingPathComponent("Resources")
        let hostDirectory = resourceDirectory.appendingPathComponent("local-agent/bin", isDirectory: true)
        try FileManager.default.createDirectory(at: hostDirectory, withIntermediateDirectories: true)
        let hostPath = hostDirectory.appendingPathComponent("OdysseyLocalAgentHost")
        FileManager.default.createFile(atPath: hostPath.path, contents: Data("echo host".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: hostPath.path)

        let runnerPath = tempDirectory.appendingPathComponent("llm-tool")
        FileManager.default.createFile(atPath: runnerPath.path, contents: Data("echo runner".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: runnerPath.path)

        let fakeHostPath = tempDirectory.appendingPathComponent("fake-local-agent-host")
        let fakeHostScript = """
        #!/bin/sh
        set -e

        MODEL=""
        DOWNLOAD_DIR=""

        while [ "$#" -gt 0 ]; do
          case "$1" in
            remove-model)
              shift
              ;;
            --model)
              MODEL="$2"
              shift 2
              ;;
            --download-dir)
              DOWNLOAD_DIR="$2"
              shift 2
              ;;
            --json)
              shift
              ;;
            *)
              shift
              ;;
          esac
        done

        case "$MODEL" in
          https://huggingface.co/*)
            MODEL="${MODEL#https://huggingface.co/}"
            ;;
        esac

        MODEL_PATH="$DOWNLOAD_DIR/$MODEL"
        MANIFEST_PATH="$(dirname "$DOWNLOAD_DIR")/managed-models.json"

        rm -rf "$MODEL_PATH"
        mkdir -p "$(dirname "$MANIFEST_PATH")"
        printf '{"installed":[]}' > "$MANIFEST_PATH"
        printf '{"modelIdentifier":"%s","downloadDirectory":"%s","manifestPath":"%s","deletedPaths":["%s"],"alreadyRemoved":false}\\n' "$MODEL" "$DOWNLOAD_DIR" "$MANIFEST_PATH" "$MODEL_PATH"
        """
        try fakeHostScript.write(to: fakeHostPath, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fakeHostPath.path)

        let managedModelPath = tempDirectory
            .appendingPathComponent("local-agent/models/huggingface/mlx-community/Qwen2.5-1.5B-Instruct-4bit", isDirectory: true)
        try FileManager.default.createDirectory(at: managedModelPath, withIntermediateDirectories: true)
        try "weights".write(
            to: managedModelPath.appendingPathComponent("config.json"),
            atomically: true,
            encoding: .utf8
        )

        let manifest = ManagedInstalledMLXManifest(installed: [
            ManagedInstalledMLXModel(
                modelIdentifier: "mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                downloadDirectory: LocalProviderInstaller.managedMLXDownloadDirectory(dataDirectoryPath: tempDirectory.path),
                installedAt: Date(),
                sourceURL: "https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit",
                managedPath: managedModelPath.path
            )
        ])
        let manifestData = try JSONEncoder().encode(manifest)
        let manifestURL = URL(fileURLWithPath: LocalProviderInstaller.managedMLXManifestPath(dataDirectoryPath: tempDirectory.path))
        try FileManager.default.createDirectory(at: manifestURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try manifestData.write(to: manifestURL)

        let beforeDelete = LocalProviderSupport.statusReport(
            bundleResourcePath: resourceDirectory.path,
            currentDirectoryPath: tempDirectory.path,
            projectRootOverride: tempDirectory.path,
            hostOverride: nil,
            mlxRunnerOverride: runnerPath.path,
            dataDirectoryPath: tempDirectory.path,
            defaultMLXModel: "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
        )
        XCTAssertEqual(beforeDelete.installedMLXModels.count, 1)

        let deleteResult = try await LocalProviderInstaller.deleteMLXModel(
            modelIdentifier: "https://huggingface.co/mlx-community/Qwen2.5-1.5B-Instruct-4bit",
            dataDirectoryPath: tempDirectory.path,
            bundleResourcePath: nil,
            currentDirectoryPath: tempDirectory.path,
            projectRootOverride: tempDirectory.path,
            hostOverride: fakeHostPath.path
        )

        XCTAssertEqual(deleteResult.modelIdentifier, "mlx-community/Qwen2.5-1.5B-Instruct-4bit")
        XCTAssertFalse(FileManager.default.fileExists(atPath: managedModelPath.path))

        let afterDelete = LocalProviderSupport.statusReport(
            bundleResourcePath: resourceDirectory.path,
            currentDirectoryPath: tempDirectory.path,
            projectRootOverride: tempDirectory.path,
            hostOverride: nil,
            mlxRunnerOverride: runnerPath.path,
            dataDirectoryPath: tempDirectory.path,
            defaultMLXModel: "mlx-community/Qwen2.5-1.5B-Instruct-4bit"
        )

        XCTAssertTrue(afterDelete.installedMLXModels.isEmpty)
        XCTAssertTrue(afterDelete.mlxAvailable)
        XCTAssertTrue(afterDelete.mlxSummary.contains("will download into"))
    }

    func testInstallBuiltMLXRunnerProductsCreatesManagedWrapperAndRuntime() throws {
        let builtProducts = tempDirectory.appendingPathComponent("BuildProducts", isDirectory: true)
        try FileManager.default.createDirectory(at: builtProducts, withIntermediateDirectories: true)

        let builtBinary = builtProducts.appendingPathComponent("llm-tool")
        FileManager.default.createFile(atPath: builtBinary.path, contents: Data("#!/bin/sh\necho live-runner\n".utf8))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: builtBinary.path)

        let packageFrameworks = builtProducts.appendingPathComponent("PackageFrameworks", isDirectory: true)
        try FileManager.default.createDirectory(at: packageFrameworks, withIntermediateDirectories: true)
        let frameworkMarker = packageFrameworks.appendingPathComponent("marker.txt")
        try "framework".write(to: frameworkMarker, atomically: true, encoding: .utf8)

        let bundle = builtProducts.appendingPathComponent("mlx-swift_Cmlx.bundle", isDirectory: true)
        try FileManager.default.createDirectory(at: bundle, withIntermediateDirectories: true)
        try "bundle".write(
            to: bundle.appendingPathComponent("payload.txt"),
            atomically: true,
            encoding: .utf8
        )

        let installPath = LocalProviderInstaller.managedMLXRunnerInstallPath(dataDirectoryPath: tempDirectory.path)
        try LocalProviderInstaller.installBuiltMLXRunnerProducts(
            builtProductsDirectory: builtProducts.path,
            installPath: installPath,
            dataDirectoryPath: tempDirectory.path
        )

        let runtimeDirectory = URL(fileURLWithPath: LocalProviderInstaller.managedMLXRuntimeDirectory(dataDirectoryPath: tempDirectory.path))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: installPath))
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: runtimeDirectory.appendingPathComponent("llm-tool").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeDirectory.appendingPathComponent("PackageFrameworks/marker.txt").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: runtimeDirectory.appendingPathComponent("mlx-swift_Cmlx.bundle/payload.txt").path))

        let wrapperScript = try String(contentsOfFile: installPath, encoding: .utf8)
        XCTAssertTrue(wrapperScript.contains("DYLD_FRAMEWORK_PATH"))
        XCTAssertTrue(wrapperScript.contains("../runtime/llm-tool-release"))
    }

    private func makeSidecarWorkspace(at root: URL) throws {
        let sidecarDirectory = root.appendingPathComponent("sidecar/src", isDirectory: true)
        try FileManager.default.createDirectory(at: sidecarDirectory, withIntermediateDirectories: true)
        FileManager.default.createFile(
            atPath: sidecarDirectory.appendingPathComponent("index.ts").path,
            contents: Data("export {};".utf8)
        )
    }
}
