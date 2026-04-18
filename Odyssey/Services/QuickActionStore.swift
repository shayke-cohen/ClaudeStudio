import Foundation

@MainActor
final class QuickActionStore: ObservableObject {

    static let shared = QuickActionStore()

    @Published private(set) var configs: [QuickActionConfig] = []
    @Published var usageOrderEnabled: Bool
    @Published private var usageVersion: Int = 0

    let configDirectory: URL
    private let defaults: UserDefaults

    private var watchSource: DispatchSourceFileSystemObject?
    private var reloadWorkItem: DispatchWorkItem?

    init(
        configDirectory: URL = ConfigFileManager.configDirectory,
        defaults: UserDefaults = AppSettings.store
    ) {
        self.configDirectory = configDirectory
        self.defaults = defaults
        self.usageOrderEnabled = (defaults.object(forKey: AppSettings.quickActionUsageOrderKey) as? Bool) ?? true

        // Load order: file → migrate from UserDefaults → factory defaults + seed file
        let fileURL = configDirectory.appendingPathComponent("quick-actions.json")
        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode([QuickActionConfig].self, from: data),
           !loaded.isEmpty {
            self.configs = loaded
        } else {
            let legacyKey = "odyssey.chat.quickActionConfigs"
            if let data = defaults.data(forKey: legacyKey),
               let legacy = try? JSONDecoder().decode([QuickActionConfig].self, from: data),
               !legacy.isEmpty {
                self.configs = legacy
                defaults.removeObject(forKey: legacyKey)
                try? Self.writeFile(legacy, to: fileURL, in: configDirectory)
            } else {
                self.configs = QuickActionConfig.defaults
                try? Self.writeFile(QuickActionConfig.defaults, to: fileURL, in: configDirectory)
            }
        }

        startDirectoryWatcher()
    }

    deinit {
        watchSource?.cancel()
    }

    // MARK: - Derived order (used by ChatView)

    var orderedConfigs: [QuickActionConfig] {
        guard usageOrderEnabled else { return configs }
        let counts = loadUsageCounts()
        let total = counts.values.reduce(0, +)
        guard total >= QuickActionConfig.usageThreshold else { return configs }
        return configs.sorted { a, b in
            let ca = counts[a.id.uuidString] ?? 0
            let cb = counts[b.id.uuidString] ?? 0
            if ca != cb { return ca > cb }
            let ia = configs.firstIndex(where: { $0.id == a.id }) ?? 0
            let ib = configs.firstIndex(where: { $0.id == b.id }) ?? 0
            return ia < ib
        }
    }

    // MARK: - Mutations

    func add(_ config: QuickActionConfig) {
        configs.append(config)
        save()
    }

    func update(_ config: QuickActionConfig) {
        guard let i = configs.firstIndex(where: { $0.id == config.id }) else { return }
        configs[i] = config
        save()
    }

    func delete(id: UUID) {
        configs.removeAll { $0.id == id }
        save()
    }

    func move(fromOffsets: IndexSet, toOffset: Int) {
        configs.move(fromOffsets: fromOffsets, toOffset: toOffset)
        save()
    }

    func resetToDefaults() {
        configs = QuickActionConfig.defaults
        defaults.removeObject(forKey: AppSettings.quickActionUsageCountsKey)
        save()
    }

    func setUsageOrderEnabled(_ enabled: Bool) {
        usageOrderEnabled = enabled
        defaults.set(enabled, forKey: AppSettings.quickActionUsageOrderKey)
    }

    // MARK: - Usage tracking

    func recordUsage(id: UUID) {
        var counts = loadUsageCounts()
        counts[id.uuidString, default: 0] += 1
        defaults.set(counts, forKey: AppSettings.quickActionUsageCountsKey)
        usageVersion += 1
    }

    // MARK: - Persistence

    private func save() {
        let fileURL = configDirectory.appendingPathComponent("quick-actions.json")
        try? Self.writeFile(configs, to: fileURL, in: configDirectory)
    }

    // Mirrors ConfigFileManager.writeQuickActions but accepts an explicit directory
    // for testability (injected configDirectory instead of ConfigFileManager.configDirectory).
    private static func writeFile(_ configs: [QuickActionConfig], to url: URL, in directory: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(configs)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    private func loadUsageCounts() -> [String: Int] {
        (defaults.dictionary(forKey: AppSettings.quickActionUsageCountsKey) as? [String: Int]) ?? [:]
    }

    // MARK: - Directory watcher

    private func startDirectoryWatcher() {
        try? FileManager.default.createDirectory(at: configDirectory, withIntermediateDirectories: true)
        let fd = open(configDirectory.path, O_EVTONLY)
        guard fd != -1 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: .write,
            queue: .main
        )
        source.setEventHandler { [weak self] in self?.scheduleFileReload() }
        source.setCancelHandler { close(fd) }
        source.resume()

        watchSource = source
    }

    private func scheduleFileReload() {
        reloadWorkItem?.cancel()
        let fileURL = configDirectory.appendingPathComponent("quick-actions.json")
        let item = DispatchWorkItem {
            guard let data = try? Data(contentsOf: fileURL),
                  let loaded = try? JSONDecoder().decode([QuickActionConfig].self, from: data),
                  !loaded.isEmpty
            else { return }
            Task { @MainActor [weak self] in
                guard let self, loaded != self.configs else { return }
                self.configs = loaded
            }
        }
        reloadWorkItem = item
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 0.3, execute: item)
    }
}
