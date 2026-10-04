import Foundation

enum DailyBudgetSharedStorage {
    #if MONTHLYMONEY_DEVELOPMENT
    static let appGroupIdentifier = "group.com.diffeng.MonthlyMoney.dev"
    #else
    static let appGroupIdentifier = "group.com.diffeng.MonthlyMoney"
    #endif
    static let watchSnapshotKey = "dailyBudgetWatchSnapshot"
    static let widgetSnapshotKey = "dailyBudgetWidgetSnapshot"

    static var sharedDefaults: UserDefaults? {
        UserDefaults(suiteName: appGroupIdentifier)
    }
}
