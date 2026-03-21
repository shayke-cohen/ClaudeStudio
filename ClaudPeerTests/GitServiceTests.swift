import XCTest
@testable import ClaudPeer

final class GitServiceTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudPeerGitTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    // MARK: - Helpers

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

    private func createAndCommitFile(_ name: String, content: String = "initial") {
        let url = tempDir.appendingPathComponent(name)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
        shell("git add '\(name)'")
        shell("git commit -m 'add \(name)'")
    }

    private func writeFile(_ name: String, content: String) {
        let url = tempDir.appendingPathComponent(name)
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? content.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - isGitRepo

    func testIsGitRepoReturnsTrueForRepo() {
        initGitRepo()
        XCTAssertTrue(GitService.isGitRepo(at: tempDir))
    }

    func testIsGitRepoReturnsFalseForNonRepo() {
        XCTAssertFalse(GitService.isGitRepo(at: tempDir))
    }

    func testIsGitRepoReturnsFalseForNonexistent() {
        let fakeURL = tempDir.appendingPathComponent("nonexistent")
        XCTAssertFalse(GitService.isGitRepo(at: fakeURL))
    }

    // MARK: - status

    func testStatusReturnsEmptyForCleanRepo() {
        initGitRepo()
        createAndCommitFile("clean.txt", content: "clean")

        let statuses = GitService.status(in: tempDir)
        XCTAssertTrue(statuses.isEmpty)
    }

    func testStatusDetectsModifiedFile() {
        initGitRepo()
        createAndCommitFile("file.txt", content: "original")
        writeFile("file.txt", content: "modified")

        let statuses = GitService.status(in: tempDir)
        XCTAssertEqual(statuses["file.txt"], .modified)
    }

    func testStatusDetectsUntrackedFile() {
        initGitRepo()
        createAndCommitFile("tracked.txt")
        writeFile("new.txt", content: "untracked")

        let statuses = GitService.status(in: tempDir)
        XCTAssertEqual(statuses["new.txt"], .untracked)
    }

    func testStatusDetectsAddedFile() {
        initGitRepo()
        createAndCommitFile("existing.txt")
        writeFile("staged.txt", content: "new file")
        shell("git add staged.txt")

        let statuses = GitService.status(in: tempDir)
        XCTAssertEqual(statuses["staged.txt"], .added)
    }

    func testStatusDetectsDeletedFile() {
        initGitRepo()
        createAndCommitFile("doomed.txt")
        shell("git rm doomed.txt")

        let statuses = GitService.status(in: tempDir)
        XCTAssertEqual(statuses["doomed.txt"], .deleted)
    }

    func testStatusHandlesSubdirectories() {
        initGitRepo()
        createAndCommitFile("src/index.ts", content: "export {}")
        writeFile("src/index.ts", content: "export default {}")

        let statuses = GitService.status(in: tempDir)
        XCTAssertEqual(statuses["src/index.ts"], .modified)
    }

    func testStatusReturnsEmptyForNonRepo() {
        let statuses = GitService.status(in: tempDir)
        XCTAssertTrue(statuses.isEmpty)
    }

    func testStatusHandlesMultipleFiles() {
        initGitRepo()
        createAndCommitFile("a.txt", content: "a")
        createAndCommitFile("b.txt", content: "b")
        writeFile("a.txt", content: "a modified")
        writeFile("c.txt", content: "new")

        let statuses = GitService.status(in: tempDir)
        XCTAssertEqual(statuses["a.txt"], .modified)
        XCTAssertEqual(statuses["c.txt"], .untracked)
        XCTAssertNil(statuses["b.txt"])
    }

    // MARK: - diff

    func testDiffReturnsContentForModifiedFile() {
        initGitRepo()
        createAndCommitFile("file.txt", content: "line1\nline2\n")
        writeFile("file.txt", content: "line1\nmodified\n")

        let diff = GitService.diff(file: "file.txt", in: tempDir)
        XCTAssertNotNil(diff)
        XCTAssertTrue(diff!.contains("-line2"))
        XCTAssertTrue(diff!.contains("+modified"))
    }

    func testDiffReturnsNilForCleanFile() {
        initGitRepo()
        createAndCommitFile("clean.txt", content: "clean")

        let diff = GitService.diff(file: "clean.txt", in: tempDir)
        XCTAssertTrue(diff?.isEmpty ?? true)
    }

    func testDiffReturnsNilForNonexistentFile() {
        initGitRepo()
        let diff = GitService.diff(file: "ghost.txt", in: tempDir)
        XCTAssertTrue(diff?.isEmpty ?? true)
    }

    // MARK: - diffCached

    func testDiffCachedReturnsContentForStagedFile() {
        initGitRepo()
        createAndCommitFile("file.txt", content: "original\n")
        writeFile("file.txt", content: "staged change\n")
        shell("git add file.txt")

        let diff = GitService.diffCached(file: "file.txt", in: tempDir)
        XCTAssertNotNil(diff)
        XCTAssertFalse(diff!.isEmpty)
        XCTAssertTrue(diff!.contains("+staged change"))
    }

    // MARK: - diffSummary

    func testDiffSummaryCountsLines() {
        initGitRepo()
        createAndCommitFile("file.txt", content: "line1\nline2\nline3\n")
        writeFile("file.txt", content: "line1\nchanged\nline3\nextra1\nextra2\n")

        let summary = GitService.diffSummary(file: "file.txt", in: tempDir)
        XCTAssertGreaterThan(summary.added, 0)
        XCTAssertGreaterThan(summary.removed, 0)
    }

    func testDiffSummaryReturnsZeroForCleanFile() {
        initGitRepo()
        createAndCommitFile("clean.txt", content: "clean")

        let summary = GitService.diffSummary(file: "clean.txt", in: tempDir)
        XCTAssertEqual(summary.added, 0)
        XCTAssertEqual(summary.removed, 0)
    }

    // MARK: - fullDiff

    func testFullDiffPrefersWorkTreeOverCached() {
        initGitRepo()
        createAndCommitFile("file.txt", content: "original\n")
        writeFile("file.txt", content: "worktree change\n")

        let diff = GitService.fullDiff(file: "file.txt", in: tempDir)
        XCTAssertNotNil(diff)
        XCTAssertTrue(diff!.contains("+worktree change"))
    }

    func testFullDiffFallsToCachedWhenWorkTreeClean() {
        initGitRepo()
        createAndCommitFile("file.txt", content: "original\n")
        writeFile("file.txt", content: "staged\n")
        shell("git add file.txt")

        let diff = GitService.fullDiff(file: "file.txt", in: tempDir)
        XCTAssertNotNil(diff)
        XCTAssertFalse(diff!.isEmpty)
    }

    // MARK: - GitFileStatus labels

    func testGitFileStatusLabels() {
        XCTAssertEqual(GitFileStatus.modified.label, "Modified")
        XCTAssertEqual(GitFileStatus.added.label, "Added")
        XCTAssertEqual(GitFileStatus.deleted.label, "Deleted")
        XCTAssertEqual(GitFileStatus.renamed.label, "Renamed")
        XCTAssertEqual(GitFileStatus.untracked.label, "Untracked")
        XCTAssertEqual(GitFileStatus.copied.label, "Copied")
    }

    func testGitFileStatusRawValues() {
        XCTAssertEqual(GitFileStatus.modified.rawValue, "M")
        XCTAssertEqual(GitFileStatus.added.rawValue, "A")
        XCTAssertEqual(GitFileStatus.deleted.rawValue, "D")
        XCTAssertEqual(GitFileStatus.renamed.rawValue, "R")
        XCTAssertEqual(GitFileStatus.untracked.rawValue, "?")
        XCTAssertEqual(GitFileStatus.copied.rawValue, "C")
    }
}
