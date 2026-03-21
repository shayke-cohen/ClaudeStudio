import Foundation

enum FileSystemService {

    static let defaultIgnoredDirectories: Set<String> = [
        ".git", "node_modules", ".build", "DerivedData", "__pycache__",
        ".next", "dist", "build", ".swiftpm", ".Trash", ".cache",
        "Pods", ".gradle", ".idea", ".vscode"
    ]

    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd"]

    static func listDirectory(at url: URL, showHidden: Bool = false) -> [FileNode] {
        let fm = FileManager.default
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey, .isHiddenKey]

        guard let contents = try? fm.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: keys,
            options: showHidden ? [] : [.skipsHiddenFiles]
        ) else {
            return []
        }

        var nodes: [FileNode] = []
        for itemURL in contents {
            let values = try? itemURL.resourceValues(forKeys: Set(keys))
            let isDir = values?.isDirectory ?? false
            let name = itemURL.lastPathComponent

            if !showHidden && isDir && defaultIgnoredDirectories.contains(name) {
                continue
            }

            nodes.append(FileNode(
                name: name,
                url: itemURL,
                isDirectory: isDir,
                size: Int64(values?.fileSize ?? 0),
                modifiedDate: values?.contentModificationDate
            ))
        }

        return nodes.sorted { a, b in
            if a.isDirectory != b.isDirectory {
                return a.isDirectory
            }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    static func readFileContents(at url: URL, maxBytes: Int = 512_000) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: maxBytes) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func isBinaryFile(at url: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }

        guard let data = try? handle.read(upToCount: 8192) else { return false }
        return data.contains(0)
    }

    static func fileIcon(for ext: String) -> String {
        switch ext.lowercased() {
        case "swift":                               return "swift"
        case "ts", "tsx":                            return "t.square"
        case "js", "jsx", "mjs", "cjs":             return "j.square"
        case "py":                                   return "p.square"
        case "rb":                                   return "r.square"
        case "go":                                   return "g.square"
        case "rs":                                   return "r.square"
        case "java", "kt", "kts":                    return "cup.and.saucer"
        case "c", "h":                               return "c.square"
        case "cpp", "cc", "cxx", "hpp":              return "c.square.fill"
        case "json":                                 return "curlybraces"
        case "yaml", "yml":                          return "list.bullet.indent"
        case "xml", "html", "htm", "xhtml":          return "chevron.left.forwardslash.chevron.right"
        case "css", "scss", "sass", "less":          return "paintbrush"
        case "md", "markdown", "mdown":              return "doc.richtext"
        case "txt", "log":                           return "doc.text"
        case "sh", "bash", "zsh", "fish":            return "terminal"
        case "toml", "ini", "cfg", "conf":           return "gearshape"
        case "png", "jpg", "jpeg", "gif", "svg", "webp", "ico": return "photo"
        case "pdf":                                  return "doc.fill"
        case "zip", "tar", "gz", "bz2", "xz", "7z": return "doc.zipper"
        case "lock":                                 return "lock"
        case "env":                                  return "key"
        case "sql":                                  return "cylinder"
        case "proto":                                return "doc.badge.gearshape"
        case "gitignore", "dockerignore":            return "eye.slash"
        case "dockerfile":                           return "shippingbox"
        default:                                     return "doc"
        }
    }

    static func isMarkdownFile(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        return markdownExtensions.contains(ext)
    }

    static func languageForExtension(_ ext: String) -> String? {
        switch ext.lowercased() {
        case "swift":                          return "swift"
        case "ts", "tsx":                      return "typescript"
        case "js", "jsx", "mjs", "cjs":        return "javascript"
        case "py":                             return "python"
        case "rb":                             return "ruby"
        case "go":                             return "go"
        case "rs":                             return "rust"
        case "java":                           return "java"
        case "kt", "kts":                      return "kotlin"
        case "c", "h":                         return "c"
        case "cpp", "cc", "cxx", "hpp":        return "cpp"
        case "json":                           return "json"
        case "yaml", "yml":                    return "yaml"
        case "xml":                            return "xml"
        case "html", "htm", "xhtml":           return "html"
        case "css":                            return "css"
        case "scss", "sass":                   return "scss"
        case "md", "markdown":                 return "markdown"
        case "sh", "bash", "zsh":              return "bash"
        case "sql":                            return "sql"
        case "toml":                           return "toml"
        case "dockerfile":                     return "dockerfile"
        case "proto":                          return "protobuf"
        case "graphql", "gql":                 return "graphql"
        case "lua":                            return "lua"
        case "r":                              return "r"
        case "dart":                           return "dart"
        case "php":                            return "php"
        default:                               return nil
        }
    }

    static func formatFileSize(_ bytes: Int64) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        let kb = Double(bytes) / 1024
        if kb < 1024 { return String(format: "%.1f KB", kb) }
        let mb = kb / 1024
        return String(format: "%.1f MB", mb)
    }
}
