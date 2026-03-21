import XCTest
@testable import ClaudPeer

@MainActor
final class FileExplorerIntegrationTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudPeerExplorerTests-\(UUID().uuidString)")
            .standardizedFileURL
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    private func createFile(_ name: String, content: String = "hello") {
        let url = tempDir.appendingPathComponent(name)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    private func createDir(_ name: String) {
        let url = tempDir.appendingPathComponent(name)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    @discardableResult
    private func shell(_ command: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = tempDir
        process.environment = ProcessInfo.processInfo.environment
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try? process.run()
        process.waitUntilExit()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func initGitRepo() {
        shell("git init")
        shell("git config user.email 'test@test.com'")
        shell("git config user.name 'Test'")
    }

    // MARK: - GitService Dynamic Path

    func testGitServiceResolvedPathIsExecutable() {
        let gitPath = GitService.resolvedGitPath
        XCTAssertTrue(FileManager.default.isExecutableFile(atPath: gitPath),
                       "Resolved git path should be executable: \(gitPath)")
    }

    func testGitServiceResolvedPathContainsGit() {
        let gitPath = GitService.resolvedGitPath
        XCTAssertTrue(gitPath.hasSuffix("/git"), "Resolved path should end with /git")
    }

    // MARK: - FileNode @Published gitStatus

    func testFileNodeGitStatusIsPublished() {
        let url = tempDir.appendingPathComponent("test.txt")
        let node = FileNode(name: "test.txt", url: url, isDirectory: false)

        XCTAssertNil(node.gitStatus)

        var didReceiveChange = false
        let cancellable = node.objectWillChange.sink { _ in
            didReceiveChange = true
        }

        node.gitStatus = .modified
        XCTAssertTrue(didReceiveChange, "@Published gitStatus should trigger objectWillChange")
        XCTAssertEqual(node.gitStatus, .modified)
        _ = cancellable
    }

    func testFileNodeChildrenIsPublished() {
        let url = tempDir.appendingPathComponent("dir")
        let node = FileNode(name: "dir", url: url, isDirectory: true)

        var didReceiveChange = false
        let cancellable = node.objectWillChange.sink { _ in
            didReceiveChange = true
        }

        node.children = []
        XCTAssertTrue(didReceiveChange)
        _ = cancellable
    }

    // MARK: - FileNode applyGitStatus with @Published

    func testApplyGitStatusTriggersPublisher() {
        let rootPath = tempDir.path
        let url = tempDir.appendingPathComponent("file.swift")
        let node = FileNode(name: "file.swift", url: url, isDirectory: false)

        var changeCount = 0
        let cancellable = node.objectWillChange.sink { _ in
            changeCount += 1
        }

        node.applyGitStatus(["file.swift": .added], rootPath: rootPath)
        XCTAssertEqual(node.gitStatus, .added)
        XCTAssertGreaterThan(changeCount, 0)
        _ = cancellable
    }

    // MARK: - FileSystemService Edge Cases

    func testListDirectoryWithEmptyDirectory() {
        createDir("empty")
        let emptyURL = tempDir.appendingPathComponent("empty")
        let nodes = FileSystemService.listDirectory(at: emptyURL)
        XCTAssertTrue(nodes.isEmpty)
    }

    func testListDirectoryFiltersIgnoredDirectories() {
        createDir("src")
        createDir("node_modules")
        createDir(".git")
        createFile("src/index.ts")
        createFile("node_modules/foo.js")

        let nodes = FileSystemService.listDirectory(at: tempDir, showHidden: false)
        let names = nodes.map { $0.name }
        XCTAssertTrue(names.contains("src"))
        XCTAssertFalse(names.contains("node_modules"))
        XCTAssertFalse(names.contains(".git"))
    }

    func testListDirectoryShowsIgnoredWhenHidden() {
        createDir("src")
        createDir("node_modules")
        createFile("src/index.ts")
        createFile("node_modules/foo.js")
        createFile(".hidden_file")

        let nodes = FileSystemService.listDirectory(at: tempDir, showHidden: true)
        let names = nodes.map { $0.name }
        XCTAssertTrue(names.contains("node_modules"))
        XCTAssertTrue(names.contains(".hidden_file"))
    }

    func testListDirectorySortsCorrectly() {
        createDir("zdir")
        createDir("adir")
        createFile("zfile.txt")
        createFile("afile.txt")

        let nodes = FileSystemService.listDirectory(at: tempDir)
        XCTAssertTrue(nodes[0].isDirectory, "Directories should come first")
        XCTAssertTrue(nodes[1].isDirectory, "Directories should come first")
        XCTAssertFalse(nodes[2].isDirectory, "Files should come after directories")
    }

    func testListDirectoryNonexistentPath() {
        let fakeURL = tempDir.appendingPathComponent("nonexistent")
        let nodes = FileSystemService.listDirectory(at: fakeURL)
        XCTAssertTrue(nodes.isEmpty)
    }

    // MARK: - FileSystemService Language Mapping

    func testLanguageForAllCommonExtensions() {
        let expectedMappings: [String: String] = [
            "swift": "swift", "ts": "typescript", "tsx": "typescript",
            "js": "javascript", "py": "python", "rb": "ruby",
            "go": "go", "rs": "rust", "java": "java", "kt": "kotlin",
            "c": "c", "cpp": "cpp", "json": "json", "yaml": "yaml",
            "html": "html", "css": "css", "md": "markdown",
            "sh": "bash", "sql": "sql", "dart": "dart", "php": "php"
        ]

        for (ext, expected) in expectedMappings {
            XCTAssertEqual(FileSystemService.languageForExtension(ext), expected,
                           "Extension .\(ext) should map to \(expected)")
        }
    }

    func testLanguageForUnknownExtension() {
        XCTAssertNil(FileSystemService.languageForExtension("xyz"))
        XCTAssertNil(FileSystemService.languageForExtension(""))
    }

    // MARK: - File Content Reading

    func testReadFileContentsRespectsMaxBytes() {
        let bigContent = String(repeating: "a", count: 1000)
        createFile("big.txt", content: bigContent)
        let url = tempDir.appendingPathComponent("big.txt")

        let content = FileSystemService.readFileContents(at: url, maxBytes: 100)
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.count, 100)
    }

    func testReadFileContentsNonexistent() {
        let url = tempDir.appendingPathComponent("missing.txt")
        let content = FileSystemService.readFileContents(at: url)
        XCTAssertNil(content)
    }

    func testIsBinaryFileDetectsNullBytes() {
        let url = tempDir.appendingPathComponent("binary.bin")
        var data = Data([0x48, 0x65, 0x6C, 0x00, 0x6F])
        try? data.write(to: url)

        XCTAssertTrue(FileSystemService.isBinaryFile(at: url))
    }

    func testIsBinaryFileReturnsFalseForText() {
        createFile("text.txt", content: "Hello, world!")
        let url = tempDir.appendingPathComponent("text.txt")
        XCTAssertFalse(FileSystemService.isBinaryFile(at: url))
    }

    // MARK: - Markdown Detection

    func testIsMarkdownFileAllExtensions() {
        XCTAssertTrue(FileSystemService.isMarkdownFile("README.md"))
        XCTAssertTrue(FileSystemService.isMarkdownFile("doc.markdown"))
        XCTAssertTrue(FileSystemService.isMarkdownFile("notes.mdown"))
        XCTAssertTrue(FileSystemService.isMarkdownFile("info.mkd"))
        XCTAssertFalse(FileSystemService.isMarkdownFile("code.swift"))
        XCTAssertFalse(FileSystemService.isMarkdownFile("Makefile"))
    }

    // MARK: - File Size Formatting

    func testFormatFileSizeBytes() {
        XCTAssertEqual(FileSystemService.formatFileSize(0), "0 B")
        XCTAssertEqual(FileSystemService.formatFileSize(512), "512 B")
        XCTAssertEqual(FileSystemService.formatFileSize(1023), "1023 B")
    }

    func testFormatFileSizeKilobytes() {
        XCTAssertEqual(FileSystemService.formatFileSize(1024), "1.0 KB")
        XCTAssertEqual(FileSystemService.formatFileSize(1536), "1.5 KB")
    }

    func testFormatFileSizeMegabytes() {
        XCTAssertEqual(FileSystemService.formatFileSize(1_048_576), "1.0 MB")
        XCTAssertEqual(FileSystemService.formatFileSize(5_242_880), "5.0 MB")
    }

    // MARK: - Git Integration: Full Tree with Status

    func testFullTreeWithGitStatus() {
        initGitRepo()
        shell("touch committed.txt && git add committed.txt && git commit -m 'init'")
        createFile("modified.txt", content: "original")
        shell("git add modified.txt && git commit -m 'add modified'")
        createFile("modified.txt", content: "changed!")
        createFile("untracked.txt", content: "new")

        let nodes = FileSystemService.listDirectory(at: tempDir, showHidden: false)
        let statusMap = GitService.status(in: tempDir)

        for node in nodes {
            node.applyGitStatus(statusMap, rootPath: tempDir.path)
        }

        let modifiedNode = nodes.first { $0.name == "modified.txt" }
        let untrackedNode = nodes.first { $0.name == "untracked.txt" }
        let committedNode = nodes.first { $0.name == "committed.txt" }

        XCTAssertEqual(modifiedNode?.gitStatus, .modified)
        XCTAssertEqual(untrackedNode?.gitStatus, .untracked)
        XCTAssertNil(committedNode?.gitStatus)
    }

    // MARK: - FileNode hasChanges Deep Nesting

    func testHasChangesDeepNesting() {
        let root = FileNode(name: "root", url: tempDir, isDirectory: true)
        let level1 = FileNode(name: "level1", url: tempDir.appendingPathComponent("level1"), isDirectory: true)
        let level2 = FileNode(name: "level2", url: tempDir.appendingPathComponent("level1/level2"), isDirectory: true)
        let deepFile = FileNode(name: "deep.txt", url: tempDir.appendingPathComponent("level1/level2/deep.txt"), isDirectory: false)
        deepFile.gitStatus = .added

        level2.children = [deepFile]
        level1.children = [level2]
        root.children = [level1]

        XCTAssertTrue(root.hasChanges, "Root should detect deeply nested changes")
        XCTAssertTrue(level1.hasChanges, "Level1 should detect nested changes")
        XCTAssertTrue(level2.hasChanges, "Level2 should detect child changes")
        XCTAssertTrue(deepFile.hasChanges, "File with status should have changes")
    }

    // MARK: - FileNode nonisolated init

    func testFileNodeCanBeCreatedFromNonisolatedContext() async {
        let url = tempDir.appendingPathComponent("test.txt")

        let node = await Task.detached {
            FileNode(name: "test.txt", url: url, isDirectory: false, size: 42)
        }.value

        XCTAssertEqual(node.name, "test.txt")
        XCTAssertEqual(node.size, 42)
    }
}
