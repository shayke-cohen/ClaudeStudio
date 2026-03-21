import XCTest
@testable import ClaudPeer

@MainActor
final class FileNodeTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudPeerNodeTests-\(UUID().uuidString)")
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

    // MARK: - Initialization

    func testInitSetsAllProperties() {
        let url = tempDir.appendingPathComponent("test.swift")
        let date = Date()
        let node = FileNode(
            name: "test.swift",
            url: url,
            isDirectory: false,
            size: 1024,
            modifiedDate: date
        )
        node.gitStatus = .modified

        XCTAssertEqual(node.name, "test.swift")
        XCTAssertEqual(node.url, url)
        XCTAssertFalse(node.isDirectory)
        XCTAssertEqual(node.size, 1024)
        XCTAssertEqual(node.modifiedDate, date)
        XCTAssertEqual(node.gitStatus, .modified)
    }

    func testInitDefaultValues() {
        let url = tempDir.appendingPathComponent("test.txt")
        let node = FileNode(name: "test.txt", url: url, isDirectory: false)

        XCTAssertEqual(node.size, 0)
        XCTAssertNil(node.modifiedDate)
        XCTAssertNil(node.gitStatus)
        XCTAssertNil(node.children)
        XCTAssertFalse(node.isExpanded)
    }

    func testIdIsFilePath() {
        let url = tempDir.appendingPathComponent("test.txt")
        let node = FileNode(name: "test.txt", url: url, isDirectory: false)
        XCTAssertEqual(node.id, url.path)
    }

    // MARK: - Computed Properties

    func testFileExtension() {
        let swiftURL = tempDir.appendingPathComponent("code.swift")
        let tsURL = tempDir.appendingPathComponent("index.ts")
        let noExtURL = tempDir.appendingPathComponent("Makefile")

        XCTAssertEqual(FileNode(name: "code.swift", url: swiftURL, isDirectory: false).fileExtension, "swift")
        XCTAssertEqual(FileNode(name: "index.ts", url: tsURL, isDirectory: false).fileExtension, "ts")
        XCTAssertEqual(FileNode(name: "Makefile", url: noExtURL, isDirectory: false).fileExtension, "")
    }

    func testRelativePath() {
        let url = tempDir.appendingPathComponent("src/index.ts")
        let node = FileNode(name: "index.ts", url: url, isDirectory: false)
        XCTAssertEqual(node.relativePath, "index.ts")
    }

    // MARK: - hasChanges

    func testHasChangesReturnsTrueWhenFileHasGitStatus() {
        let url = tempDir.appendingPathComponent("changed.txt")
        let node = FileNode(name: "changed.txt", url: url, isDirectory: false)
        node.gitStatus = .modified
        XCTAssertTrue(node.hasChanges)
    }

    func testHasChangesReturnsFalseWhenClean() {
        let url = tempDir.appendingPathComponent("clean.txt")
        let node = FileNode(name: "clean.txt", url: url, isDirectory: false)
        XCTAssertFalse(node.hasChanges)
    }

    func testHasChangesPropagatesFromChildren() {
        let dirURL = tempDir.appendingPathComponent("src")
        let dirNode = FileNode(name: "src", url: dirURL, isDirectory: true)

        let childClean = FileNode(
            name: "clean.txt",
            url: dirURL.appendingPathComponent("clean.txt"),
            isDirectory: false
        )
        let childDirty = FileNode(
            name: "dirty.txt",
            url: dirURL.appendingPathComponent("dirty.txt"),
            isDirectory: false
        )
        childDirty.gitStatus = .modified

        dirNode.children = [childClean, childDirty]
        XCTAssertTrue(dirNode.hasChanges)
    }

    func testHasChangesReturnsFalseForDirWithCleanChildren() {
        let dirURL = tempDir.appendingPathComponent("src")
        let dirNode = FileNode(name: "src", url: dirURL, isDirectory: true)
        dirNode.children = [
            FileNode(name: "a.txt", url: dirURL.appendingPathComponent("a.txt"), isDirectory: false),
            FileNode(name: "b.txt", url: dirURL.appendingPathComponent("b.txt"), isDirectory: false)
        ]
        XCTAssertFalse(dirNode.hasChanges)
    }

    func testHasChangesReturnsFalseForDirWithNilChildren() {
        let dirURL = tempDir.appendingPathComponent("empty")
        let dirNode = FileNode(name: "empty", url: dirURL, isDirectory: true)
        XCTAssertFalse(dirNode.hasChanges)
    }

    // MARK: - loadChildren

    func testLoadChildrenPopulatesFromDisk() {
        createDir("mydir")
        createFile("mydir/a.txt")
        createFile("mydir/b.txt")

        let dirURL = tempDir.appendingPathComponent("mydir")
        let node = FileNode(name: "mydir", url: dirURL, isDirectory: true)

        XCTAssertNil(node.children)
        node.loadChildren()
        XCTAssertNotNil(node.children)
        XCTAssertEqual(node.children?.count, 2)
    }

    func testLoadChildrenDoesNotReloadIfAlreadyLoaded() {
        createDir("mydir")
        createFile("mydir/a.txt")

        let dirURL = tempDir.appendingPathComponent("mydir")
        let node = FileNode(name: "mydir", url: dirURL, isDirectory: true)

        node.loadChildren()
        let firstChildren = node.children

        createFile("mydir/b.txt")
        node.loadChildren()

        XCTAssertEqual(node.children?.count, firstChildren?.count,
                       "loadChildren should not reload when children already exist")
    }

    func testLoadChildrenIgnoredForFile() {
        createFile("file.txt")
        let url = tempDir.appendingPathComponent("file.txt")
        let node = FileNode(name: "file.txt", url: url, isDirectory: false)

        node.loadChildren()
        XCTAssertNil(node.children)
    }

    // MARK: - reloadChildren

    func testReloadChildrenRefreshes() {
        createDir("mydir")
        createFile("mydir/a.txt")

        let dirURL = tempDir.appendingPathComponent("mydir")
        let node = FileNode(name: "mydir", url: dirURL, isDirectory: true)

        node.loadChildren()
        XCTAssertEqual(node.children?.count, 1)

        createFile("mydir/b.txt")
        node.reloadChildren()
        XCTAssertEqual(node.children?.count, 2)
    }

    func testReloadChildrenIgnoredForFile() {
        createFile("file.txt")
        let url = tempDir.appendingPathComponent("file.txt")
        let node = FileNode(name: "file.txt", url: url, isDirectory: false)

        node.reloadChildren()
        XCTAssertNil(node.children)
    }

    // MARK: - applyGitStatus

    func testApplyGitStatusSetsStatusOnFiles() {
        let rootPath = tempDir.path
        let url = tempDir.appendingPathComponent("src/index.ts")
        let node = FileNode(name: "index.ts", url: url, isDirectory: false)

        let statusMap: [String: GitFileStatus] = ["src/index.ts": .modified]
        node.applyGitStatus(statusMap, rootPath: rootPath)

        XCTAssertEqual(node.gitStatus, .modified)
    }

    func testApplyGitStatusDoesNotSetOnDirectories() {
        let rootPath = tempDir.path
        let url = tempDir.appendingPathComponent("src")
        let node = FileNode(name: "src", url: url, isDirectory: true)

        let statusMap: [String: GitFileStatus] = ["src": .modified]
        node.applyGitStatus(statusMap, rootPath: rootPath)

        XCTAssertNil(node.gitStatus)
    }

    func testApplyGitStatusRecursesToChildren() {
        let rootPath = tempDir.path
        let dirURL = tempDir.appendingPathComponent("src")
        let dirNode = FileNode(name: "src", url: dirURL, isDirectory: true)

        let childURL = dirURL.appendingPathComponent("app.ts")
        let child = FileNode(name: "app.ts", url: childURL, isDirectory: false)
        dirNode.children = [child]

        let statusMap: [String: GitFileStatus] = ["src/app.ts": .added]
        dirNode.applyGitStatus(statusMap, rootPath: rootPath)

        XCTAssertEqual(child.gitStatus, .added)
    }

    func testApplyGitStatusLeavesNilForCleanFiles() {
        let rootPath = tempDir.path
        let url = tempDir.appendingPathComponent("clean.txt")
        let node = FileNode(name: "clean.txt", url: url, isDirectory: false)

        let statusMap: [String: GitFileStatus] = ["other.txt": .modified]
        node.applyGitStatus(statusMap, rootPath: rootPath)

        XCTAssertNil(node.gitStatus)
    }

    func testApplyGitStatusHandlesNestedPaths() {
        let rootPath = tempDir.path
        let dirURL = tempDir.appendingPathComponent("src")
        let dirNode = FileNode(name: "src", url: dirURL, isDirectory: true)

        let subDirURL = dirURL.appendingPathComponent("components")
        let subDir = FileNode(name: "components", url: subDirURL, isDirectory: true)

        let fileURL = subDirURL.appendingPathComponent("Button.tsx")
        let file = FileNode(name: "Button.tsx", url: fileURL, isDirectory: false)

        subDir.children = [file]
        dirNode.children = [subDir]

        let statusMap: [String: GitFileStatus] = ["src/components/Button.tsx": .modified]
        dirNode.applyGitStatus(statusMap, rootPath: rootPath)

        XCTAssertEqual(file.gitStatus, .modified)
        XCTAssertTrue(subDir.hasChanges)
        XCTAssertTrue(dirNode.hasChanges)
    }
}
