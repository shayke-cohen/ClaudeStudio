import Foundation

extension String {
    func appendToFile(path: String) throws {
        let fm = FileManager.default
        let dir = (path as NSString).deletingLastPathComponent
        if !fm.fileExists(atPath: dir) {
            try fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        }
        if let data = self.data(using: .utf8) {
            if fm.fileExists(atPath: path) {
                let handle = try FileHandle(forWritingTo: URL(fileURLWithPath: path))
                handle.seekToEndOfFile()
                handle.write(data)
                handle.closeFile()
            } else {
                try data.write(to: URL(fileURLWithPath: path))
            }
        }
    }
}
