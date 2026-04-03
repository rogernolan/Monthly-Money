import Foundation

enum DailyBudgetSharedStorage {
    static let appGroupIdentifier = "group.com.diffeng.MonthlyMoney"
    static let watchSnapshotKey = "dailyBudgetWatchSnapshot"
    static let widgetSnapshotKey = "dailyBudgetWidgetSnapshot"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}
