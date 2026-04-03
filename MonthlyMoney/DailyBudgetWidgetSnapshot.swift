import Foundation

enum DailyBudgetWidgetChipTone: String, Codable, Equatable {
    case negative
    case neutral
    case positive
}

struct DailyBudgetWidgetChipSnapshot: Codable, Equatable {
    let title: String
    let value: String
    let tone: DailyBudgetWidgetChipTone
}

struct DailyBudgetWidgetSnapshot: Codable, Equatable {
    let updatedAt: Date
    let chips: [DailyBudgetWidgetChipSnapshot]
}

protocol DailyBudgetWidgetSnapshotSyncing: AnyObject {
    func sync(_ snapshot: DailyBudgetWidgetSnapshot)
}

struct DailyBudgetWidgetSnapshotStore {
    private let defaults: UserDefaults
    private let decoder = JSONDecoder()

    init(defaults: UserDefaults = DailyBudgetSharedStorage.sharedDefaults ?? .standard) {
        self.defaults = defaults
    }

    func load() -> DailyBudgetWidgetSnapshot? {
        guard let data = defaults.data(forKey: DailyBudgetSharedStorage.widgetSnapshotKey) else {
            return nil
        }
        return try? decoder.decode(DailyBudgetWidgetSnapshot.self, from: data)
    }

    func save(_ snapshot: DailyBudgetWidgetSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: DailyBudgetSharedStorage.widgetSnapshotKey)
    }
}
