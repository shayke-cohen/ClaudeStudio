import Foundation
import SwiftData

enum DefaultsSeeder {

    static let seededKey = "claudpeer.defaultsSeeded"

    static func seedIfNeeded(container: ModelContainer) {
        guard !UserDefaults.standard.bool(forKey: seededKey) else { return }

        let context = ModelContext(container)
        let permCount = (try? context.fetchCount(FetchDescriptor<PermissionSet>())) ?? 0
        if permCount > 0 { return }

        print("[DefaultsSeeder] First launch — seeding permission presets")
        seedPermissionPresets(into: context)

        do {
            try context.save()
            UserDefaults.standard.set(true, forKey: seededKey)
            print("[DefaultsSeeder] Seeding complete")
        } catch {
            print("[DefaultsSeeder] Failed to save: \(error)")
        }
    }

    private static func seedPermissionPresets(into context: ModelContext) {
        guard let data = loadResource(name: "DefaultPermissionPresets", ext: "json") else {
            print("[DefaultsSeeder] DefaultPermissionPresets.json not found")
            return
        }

        struct PresetDTO: Decodable {
            let name: String
            let allowRules: [String]
            let denyRules: [String]
            let additionalDirectories: [String]
            let permissionMode: String
        }

        guard let dtos = try? JSONDecoder().decode([PresetDTO].self, from: data) else {
            print("[DefaultsSeeder] Failed to decode permission presets")
            return
        }

        for dto in dtos {
            let ps = PermissionSet(
                name: dto.name,
                allowRules: dto.allowRules,
                denyRules: dto.denyRules,
                permissionMode: dto.permissionMode
            )
            ps.additionalDirectories = dto.additionalDirectories
            context.insert(ps)
            print("[DefaultsSeeder]   Permission preset: \(dto.name)")
        }
    }

    private static func loadResource(name: String, ext: String) -> Data? {
        if let url = Bundle.main.url(forResource: name, withExtension: ext) {
            return try? Data(contentsOf: url)
        }
        let fallbackPaths = [
            "\(NSHomeDirectory())/ClaudPeer/ClaudPeer/Resources/\(name).\(ext)",
            "\(FileManager.default.currentDirectoryPath)/ClaudPeer/Resources/\(name).\(ext)"
        ]
        for path in fallbackPaths {
            if FileManager.default.fileExists(atPath: path) {
                return try? Data(contentsOf: URL(fileURLWithPath: path))
            }
        }
        return nil
    }
}
