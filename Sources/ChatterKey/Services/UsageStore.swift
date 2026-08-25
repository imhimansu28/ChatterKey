import Foundation

nonisolated enum UsageStore {
    private static let storageKey = "usage-records-v1"
    private static let maximumRecords = 1_000

    static func load() -> [UsageRecord] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let records = try? JSONDecoder().decode([UsageRecord].self, from: data) else { return [] }
        return records
    }

    static func save(_ records: [UsageRecord]) {
        guard let data = try? JSONEncoder().encode(Array(records.prefix(maximumRecords))) else { return }
        UserDefaults.standard.set(data, forKey: storageKey)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
