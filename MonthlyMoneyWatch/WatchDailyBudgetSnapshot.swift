import Foundation

enum WatchDailyBudgetSnapshotKey {
    static let applicationContextKey = DailyBudgetSharedStorage.watchSnapshotKey
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

    init(defaults: UserDefaults = DailyBudgetSharedStorage.sharedDefaults ?? .standard) {
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

extension DailyBudgetWidgetSnapshot {
    init?(watchSnapshot: WatchDailyBudgetSnapshot) {
        guard watchSnapshot.chips.count >= 5 else { return nil }

        self.init(
            updatedAt: watchSnapshot.updatedAt,
            chips: [
                DailyBudgetWidgetChipSnapshot(
                    title: watchSnapshot.chips[3].title,
                    value: watchSnapshot.chips[3].value,
                    tone: Self.tone(from: watchSnapshot.chips[3].tone)
                ),
                DailyBudgetWidgetChipSnapshot(
                    title: watchSnapshot.chips[4].title,
                    value: watchSnapshot.chips[4].value,
                    tone: Self.tone(from: watchSnapshot.chips[4].tone)
                )
            ]
        )
    }

    private static func tone(from tone: WatchDailyBudgetChipTone) -> DailyBudgetWidgetChipTone {
        switch tone {
        case .negative:
            return .negative
        case .neutral, .plain:
            return .neutral
        case .positive:
            return .positive
        }
    }
}
