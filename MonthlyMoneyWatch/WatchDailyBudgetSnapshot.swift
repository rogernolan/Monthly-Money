import Foundation

enum WatchDailyBudgetSnapshotKey {
    static let applicationContextKey = "dailyBudgetWatchSnapshot"
}

enum WatchDailyBudgetChipTone: String, Codable {
    case plain
    case negative
    case neutral
    case positive
}

struct WatchDailyBudgetChipSnapshot: Codable, Equatable {
    let title: String
    let value: String
    let tone: WatchDailyBudgetChipTone
}

struct WatchDailyBudgetSnapshot: Codable, Equatable {
    let updatedAt: Date
    let chips: [WatchDailyBudgetChipSnapshot]
}

struct WatchDailyBudgetSnapshotStore {
    private let defaults: UserDefaults
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> WatchDailyBudgetSnapshot? {
        guard let data = defaults.data(forKey: WatchDailyBudgetSnapshotKey.applicationContextKey) else {
            return nil
        }
        return try? decoder.decode(WatchDailyBudgetSnapshot.self, from: data)
    }

    func save(_ data: Data) {
        defaults.set(data, forKey: WatchDailyBudgetSnapshotKey.applicationContextKey)
    }
}
