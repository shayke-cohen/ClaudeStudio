import Foundation
import Combine

@MainActor
final class QuickActionStore: ObservableObject {

    static let shared = QuickActionStore()

    @Published private(set) var configs: [QuickActionConfig] = []
    @Published var usageOrderEnabled: Bool

    private let defaults: UserDefaults

    init(defaults: UserDefaults = AppSettings.store) {
        self.defaults = defaults
        self.usageOrderEnabled = (defaults.object(forKey: AppSettings.quickActionUsageOrderKey) as? Bool) ?? true
        self.configs = Self.loadConfigs(from: defaults)
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
        objectWillChange.send()
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(configs) else { return }
        defaults.set(data, forKey: AppSettings.quickActionConfigsKey)
    }

    private func loadUsageCounts() -> [String: Int] {
        (defaults.dictionary(forKey: AppSettings.quickActionUsageCountsKey) as? [String: Int]) ?? [:]
    }

    private static func loadConfigs(from defaults: UserDefaults) -> [QuickActionConfig] {
        guard
            let data = defaults.data(forKey: AppSettings.quickActionConfigsKey),
            let configs = try? JSONDecoder().decode([QuickActionConfig].self, from: data),
            !configs.isEmpty
        else {
            return QuickActionConfig.defaults
        }
        return configs
    }
}
