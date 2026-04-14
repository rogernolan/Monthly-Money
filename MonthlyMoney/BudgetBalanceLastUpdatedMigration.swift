import Foundation

@MainActor
enum BudgetBalanceLastUpdatedMigration {
    static func migrateIfNeeded(repository: AccountRepository) throws {
        guard let budget = try repository.activeBudget() else { return }
        guard budget.monthlyBalanceLastUpdatedAt == nil || budget.dailyBalanceLastUpdatedAt == nil else {
            return
        }

        let fallbackDate = budget.updatedAt == .distantPast ? budget.createdAt : budget.updatedAt
        if budget.monthlyBalanceLastUpdatedAt == nil {
            budget.monthlyBalanceLastUpdatedAt = fallbackDate
        }
        if budget.dailyBalanceLastUpdatedAt == nil {
            budget.dailyBalanceLastUpdatedAt = fallbackDate
        }

        try repository.saveBudget(budget, updateModifiedAt: false)
    }
}
