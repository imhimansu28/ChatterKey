import Foundation

nonisolated enum HistoryStore {
    private static let storageKey = "dictation-history-v1"

    static func load(retentionDays: Int) -> [DictationHistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let values = try? JSONDecoder().decode([DictationHistoryItem].self, from: data) else {
            return []
        }
        let cutoff = Calendar.current.date(byAdding: .day, value: -max(1, retentionDays), to: Date()) ?? .distantPast
        return values.filter { $0.createdAt >= cutoff }.prefix(50).map { $0 }
    }

    static func save(_ values: [DictationHistoryItem]) {
        if let data = try? JSONEncoder().encode(Array(values.prefix(50))) {
            UserDefaults.standard.set(data, forKey: storageKey)
        }
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: storageKey)
    }
}
