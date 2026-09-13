import ChatterKeyCore
import Foundation

nonisolated enum HistoryStore {
    private static let storageKey = "dictation-history-v1"

    static func load(retentionDays: Int, defaults: UserDefaults = .standard) -> [DictationHistoryItem] {
        guard let data = defaults.data(forKey: storageKey),
              let values = try? JSONDecoder().decode([DictationHistoryItem].self, from: data) else {
            return []
        }
        let retained = pruned(values, retentionDays: retentionDays)
        if retained.count != values.count { save(retained, defaults: defaults) }
        return retained
    }

    static func pruned(_ values: [DictationHistoryItem], retentionDays: Int, now: Date = Date()) -> [DictationHistoryItem] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -max(1, retentionDays), to: now) ?? .distantPast
        return Array(values.filter { $0.createdAt >= cutoff }.prefix(50))
    }

    static func save(_ values: [DictationHistoryItem], defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(Array(values.prefix(50))) {
            defaults.set(data, forKey: storageKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
