import SwiftData

@MainActor
enum MonthlyMoneyRepositoryBootstrap {
    static func makeRepository() throws -> AccountRepository {
        let plan = MonthlyMoneyPersistencePlan.defaultPlan()
        return try MonthlyMoneyPersistenceFactory.makeRepository(plan: plan, schema: schema)
    }

    private static var schema: Schema {
        Schema([
            Budget.self,
            Account.self,
            PlannedItem.self,
            PopulatedMonthRecord.self,
            Transaction.self,
            ImportedTransactionRecord.self,
            WheelOfMoneyItem.self
        ])
    }
}
