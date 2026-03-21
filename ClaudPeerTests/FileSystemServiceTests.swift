import XCTest
@testable import ClaudPeer

@MainActor
final class FileSystemServiceTests: XCTestCase {

    private var tempDir: URL!

    override func setUp() {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ClaudPeerTests-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempDir)
        tempDir = nil
    }

    // MARK: - Helpers

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

    // MARK: - listDirectory

    func testListDirectoryReturnsFilesAndDirs() {
        createFile("hello.txt", content: "world")
        createDir("subdir")

        let nodes = FileSystemService.listDirectory(at: tempDir)
        XCTAssertEqual(nodes.count, 2)
    }

    func testListDirectorySortsDirectoriesFirst() {
        createFile("z_file.txt")
        createDir("a_dir")
        createFile("a_file.txt")
        createDir("z_dir")

        let nodes = FileSystemService.listDirectory(at: tempDir)
        XCTAssertEqual(nodes.count, 4)
        XCTAssertTrue(nodes[0].isDirectory, "First item should be a directory")
        XCTAssertTrue(nodes[1].isDirectory, "Second item should be a directory")
        XCTAssertFalse(nodes[2].isDirectory, "Third item should be a file")
        XCTAssertFalse(nodes[3].isDirectory, "Fourth item should be a file")
    }

    func testListDirectorySortsAlphabeticallyWithinGroup() {
        createFile("beta.txt")
        createFile("alpha.txt")
        createDir("gamma")
        createDir("delta")

        let nodes = FileSystemService.listDirectory(at: tempDir)
        XCTAssertEqual(nodes[0].name, "delta")
        XCTAssertEqual(nodes[1].name, "gamma")
        XCTAssertEqual(nodes[2].name, "alpha.txt")
        XCTAssertEqual(nodes[3].name, "beta.txt")
    }

    func testListDirectoryHidesHiddenFilesByDefault() {
        createFile(".hidden")
        createFile("visible.txt")

        let nodes = FileSystemService.listDirectory(at: tempDir, showHidden: false)
        XCTAssertEqual(nodes.count, 1)
        XCTAssertEqual(nodes[0].name, "visible.txt")
    }

    func testListDirectoryShowsHiddenWhenRequested() {
        createFile(".hidden")
        createFile("visible.txt")

        let nodes = FileSystemService.listDirectory(at: tempDir, showHidden: true)
        XCTAssertGreaterThanOrEqual(nodes.count, 2)
        XCTAssertTrue(nodes.contains(where: { $0.name == ".hidden" }))
    }

    func testListDirectoryFiltersIgnoredDirs() {
        createDir("node_modules")
        createDir(".git")
        createDir("src")

        let nodes = FileSystemService.listDirectory(at: tempDir, showHidden: false)
        let names = nodes.map(\.name)
        XCTAssertTrue(names.contains("src"))
        XCTAssertFalse(names.contains("node_modules"))
        XCTAssertFalse(names.contains(".git"))
    }

    func testListDirectoryShowsIgnoredDirsWhenShowHidden() {
        createDir("node_modules")
        createDir("src")

        let nodes = FileSystemService.listDirectory(at: tempDir, showHidden: true)
        let names = nodes.map(\.name)
        XCTAssertTrue(names.contains("src"))
        XCTAssertTrue(names.contains("node_modules"))
    }

    func testListDirectoryReturnsEmptyForNonexistent() {
        let fakeURL = tempDir.appendingPathComponent("nonexistent")
        let nodes = FileSystemService.listDirectory(at: fakeURL)
        XCTAssertTrue(nodes.isEmpty)
    }

    func testListDirectorySetsFileSize() {
        let content = "Hello, World!"
        createFile("sized.txt", content: content)

        let nodes = FileSystemService.listDirectory(at: tempDir)
        let file = nodes.first { $0.name == "sized.txt" }
        XCTAssertNotNil(file)
        XCTAssertGreaterThan(file!.size, 0)
    }

    func testListDirectorySetsModifiedDate() {
        createFile("dated.txt")

        let nodes = FileSystemService.listDirectory(at: tempDir)
        let file = nodes.first { $0.name == "dated.txt" }
        XCTAssertNotNil(file?.modifiedDate)
    }

    // MARK: - readFileContents

    func testReadFileContentsReturnsContent() {
        createFile("test.txt", content: "Hello, ClaudPeer!")
        let url = tempDir.appendingPathComponent("test.txt")

        let content = FileSystemService.readFileContents(at: url)
        XCTAssertEqual(content, "Hello, ClaudPeer!")
    }

    func testReadFileContentsRespectsMaxBytes() {
        let longContent = String(repeating: "A", count: 1000)
        createFile("long.txt", content: longContent)
        let url = tempDir.appendingPathComponent("long.txt")

        let content = FileSystemService.readFileContents(at: url, maxBytes: 100)
        XCTAssertNotNil(content)
        XCTAssertEqual(content?.count, 100)
    }

    func testReadFileContentsReturnsNilForNonexistent() {
        let url = tempDir.appendingPathComponent("ghost.txt")
        XCTAssertNil(FileSystemService.readFileContents(at: url))
    }

    // MARK: - isBinaryFile

    func testIsBinaryFileReturnsFalseForText() {
        createFile("text.swift", content: "import Foundation\nprint(\"hello\")\n")
        let url = tempDir.appendingPathComponent("text.swift")
        XCTAssertFalse(FileSystemService.isBinaryFile(at: url))
    }

    func testIsBinaryFileReturnsTrueForBinary() {
        let url = tempDir.appendingPathComponent("binary.bin")
        var data = Data("header".utf8)
        data.append(contentsOf: [0x00, 0x01, 0x02])
        data.append(Data("trailer".utf8))
        try? data.write(to: url)

        XCTAssertTrue(FileSystemService.isBinaryFile(at: url))
    }

    func testIsBinaryFileReturnsFalseForNonexistent() {
        let url = tempDir.appendingPathComponent("ghost.bin")
        XCTAssertFalse(FileSystemService.isBinaryFile(at: url))
    }

    // MARK: - fileIcon

    func testFileIconReturnsSwiftForSwift() {
        XCTAssertEqual(FileSystemService.fileIcon(for: "swift"), "swift")
    }

    func testFileIconReturnsExpectedForCommonTypes() {
        XCTAssertEqual(FileSystemService.fileIcon(for: "ts"), "t.square")
        XCTAssertEqual(FileSystemService.fileIcon(for: "js"), "j.square")
        XCTAssertEqual(FileSystemService.fileIcon(for: "py"), "p.square")
        XCTAssertEqual(FileSystemService.fileIcon(for: "json"), "curlybraces")
        XCTAssertEqual(FileSystemService.fileIcon(for: "md"), "doc.richtext")
        XCTAssertEqual(FileSystemService.fileIcon(for: "sh"), "terminal")
        XCTAssertEqual(FileSystemService.fileIcon(for: "png"), "photo")
        XCTAssertEqual(FileSystemService.fileIcon(for: "lock"), "lock")
    }

    func testFileIconIsCaseInsensitive() {
        XCTAssertEqual(FileSystemService.fileIcon(for: "SWIFT"), "swift")
        XCTAssertEqual(FileSystemService.fileIcon(for: "Ts"), "t.square")
    }

    func testFileIconReturnsDocForUnknown() {
        XCTAssertEqual(FileSystemService.fileIcon(for: "xyz"), "doc")
        XCTAssertEqual(FileSystemService.fileIcon(for: ""), "doc")
    }

    // MARK: - isMarkdownFile

    func testIsMarkdownFileForCommonExtensions() {
        XCTAssertTrue(FileSystemService.isMarkdownFile("README.md"))
        XCTAssertTrue(FileSystemService.isMarkdownFile("notes.markdown"))
        XCTAssertTrue(FileSystemService.isMarkdownFile("doc.mdown"))
        XCTAssertTrue(FileSystemService.isMarkdownFile("spec.mkd"))
    }

    func testIsMarkdownFileReturnsFalseForNonMd() {
        XCTAssertFalse(FileSystemService.isMarkdownFile("code.swift"))
        XCTAssertFalse(FileSystemService.isMarkdownFile("data.json"))
        XCTAssertFalse(FileSystemService.isMarkdownFile("notes.txt"))
        XCTAssertFalse(FileSystemService.isMarkdownFile("noext"))
    }

    // MARK: - languageForExtension

    func testLanguageForExtensionReturnsExpected() {
        XCTAssertEqual(FileSystemService.languageForExtension("swift"), "swift")
        XCTAssertEqual(FileSystemService.languageForExtension("ts"), "typescript")
        XCTAssertEqual(FileSystemService.languageForExtension("tsx"), "typescript")
        XCTAssertEqual(FileSystemService.languageForExtension("js"), "javascript")
        XCTAssertEqual(FileSystemService.languageForExtension("py"), "python")
        XCTAssertEqual(FileSystemService.languageForExtension("go"), "go")
        XCTAssertEqual(FileSystemService.languageForExtension("rs"), "rust")
        XCTAssertEqual(FileSystemService.languageForExtension("html"), "html")
        XCTAssertEqual(FileSystemService.languageForExtension("css"), "css")
        XCTAssertEqual(FileSystemService.languageForExtension("json"), "json")
        XCTAssertEqual(FileSystemService.languageForExtension("yaml"), "yaml")
        XCTAssertEqual(FileSystemService.languageForExtension("sh"), "bash")
    }

    func testLanguageForExtensionReturnsNilForUnknown() {
        XCTAssertNil(FileSystemService.languageForExtension("xyz"))
        XCTAssertNil(FileSystemService.languageForExtension(""))
    }

    func testLanguageForExtensionIsCaseInsensitive() {
        XCTAssertEqual(FileSystemService.languageForExtension("SWIFT"), "swift")
        XCTAssertEqual(FileSystemService.languageForExtension("Py"), "python")
    }

    // MARK: - formatFileSize

    func testFormatFileSizeBytes() {
        XCTAssertEqual(FileSystemService.formatFileSize(0), "0 B")
        XCTAssertEqual(FileSystemService.formatFileSize(512), "512 B")
        XCTAssertEqual(FileSystemService.formatFileSize(1023), "1023 B")
    }

    func testFormatFileSizeKilobytes() {
        XCTAssertEqual(FileSystemService.formatFileSize(1024), "1.0 KB")
        XCTAssertEqual(FileSystemService.formatFileSize(1536), "1.5 KB")
        XCTAssertEqual(FileSystemService.formatFileSize(1024 * 512), "512.0 KB")
    }

    func testFormatFileSizeMegabytes() {
        XCTAssertEqual(FileSystemService.formatFileSize(1024 * 1024), "1.0 MB")
        XCTAssertEqual(FileSystemService.formatFileSize(1024 * 1024 * 5), "5.0 MB")
    }

    // MARK: - defaultIgnoredDirectories

    func testDefaultIgnoredDirectoriesContainsExpected() {
        let ignored = FileSystemService.defaultIgnoredDirectories
        XCTAssertTrue(ignored.contains(".git"))
        XCTAssertTrue(ignored.contains("node_modules"))
        XCTAssertTrue(ignored.contains(".build"))
        XCTAssertTrue(ignored.contains("DerivedData"))
        XCTAssertTrue(ignored.contains("__pycache__"))
    }
}
