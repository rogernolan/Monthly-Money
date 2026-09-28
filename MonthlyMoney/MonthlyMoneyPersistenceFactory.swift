import Foundation
import SwiftData

enum MonthlyMoneySchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Budget.self, Account.self, PlannedItem.self, PopulatedMonthRecord.self, Transaction.self, ImportedTransactionRecord.self, WheelOfMoneyItem.self]
    }

    @Model
    final class Budget {
        var id: UUID = UUID()
        var name: String = ""
        var ownerParticipantID: String = ""
        var sharingState: BudgetSharingState = BudgetSharingState.local
        var createdAt: Date = Date()
        var updatedAt: Date = Date()
        var monthlyBalanceLastUpdatedAt: Date?
        var dailyBalanceLastUpdatedAt: Date?
        var usesSeparateAccountForDailyBudget: Bool = false
        var dailyBudgetAmount: Decimal = 0
        var dailyBudgetPaydayDay: Int = 1
        var dailyBudgetSeparateAccountBalance: Decimal = 0
        var autoGenerateWoMSavingsEveryMonth: Bool = false
        var monthBalancesPayload: String = "{}"
        var hiddenDailyAccountID: UUID?

        init(
            id: UUID = UUID(),
            name: String,
            ownerParticipantID: String,
            sharingState: BudgetSharingState = .local,
            createdAt: Date = Date(),
            updatedAt: Date = Date(),
            monthlyBalanceLastUpdatedAt: Date? = nil,
            dailyBalanceLastUpdatedAt: Date? = nil,
            usesSeparateAccountForDailyBudget: Bool = false,
            dailyBudgetAmount: Decimal = 0,
            dailyBudgetPaydayDay: Int = 1,
            dailyBudgetSeparateAccountBalance: Decimal = 0,
            autoGenerateWoMSavingsEveryMonth: Bool = false,
            monthBalancesPayload: String = "{}",
            hiddenDailyAccountID: UUID? = nil
        ) {
            self.id = id
            self.name = name
            self.ownerParticipantID = ownerParticipantID
            self.sharingState = sharingState
            self.createdAt = createdAt
            self.updatedAt = updatedAt
            self.monthlyBalanceLastUpdatedAt = monthlyBalanceLastUpdatedAt
            self.dailyBalanceLastUpdatedAt = dailyBalanceLastUpdatedAt
            self.usesSeparateAccountForDailyBudget = usesSeparateAccountForDailyBudget
            self.dailyBudgetAmount = dailyBudgetAmount
            self.dailyBudgetPaydayDay = dailyBudgetPaydayDay
            self.dailyBudgetSeparateAccountBalance = dailyBudgetSeparateAccountBalance
            self.autoGenerateWoMSavingsEveryMonth = autoGenerateWoMSavingsEveryMonth
            self.monthBalancesPayload = monthBalancesPayload
            self.hiddenDailyAccountID = hiddenDailyAccountID
        }
    }
}

enum MonthlyMoneySchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [Budget.self, Account.self, PlannedItem.self, PopulatedMonthRecord.self, Transaction.self, ImportedTransactionRecord.self, WheelOfMoneyItem.self]
    }
}

enum MonthlyMoneySchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MonthlyMoneySchemaV1.self, MonthlyMoneySchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [MigrationStage.lightweight(fromVersion: MonthlyMoneySchemaV1.self, toVersion: MonthlyMoneySchemaV2.self)]
    }
}

@MainActor
enum MonthlyMoneyPersistenceFactory {
    nonisolated static let cloudKitContainerIdentifier = "iCloud.com.hatbat.monthlymoney"

    static func makeRepository(
        plan: MonthlyMoneyPersistencePlan,
        schema: Schema
    ) throws -> AccountRepository {
        let privateStore: AccountDataStore
        switch plan.privateStore.backend {
        case .coreData:
            privateStore = try makeCoreDataStore(for: plan.privateStore)
        case .swiftData:
            let container = try ModelContainer(
                for: schema,
                migrationPlan: MonthlyMoneySchemaMigrationPlan.self,
                configurations: [plan.privateStore.modelConfiguration(schema: schema)]
            )
            privateStore = SwiftDataAccountDataStore(modelContainer: container)
        }

        let sharedStore: AccountDataStore
        switch plan.sharedStore.backend {
        case .swiftData:
            let container = try ModelContainer(
                for: schema,
                migrationPlan: MonthlyMoneySchemaMigrationPlan.self,
                configurations: [plan.sharedStore.modelConfiguration(schema: schema)]
            )
            sharedStore = SwiftDataAccountDataStore(modelContainer: container)
        case .coreData:
            sharedStore = try makeCoreDataStore(for: plan.sharedStore)
        }

        return AccountRepository(
            privateStore: privateStore,
            sharedStore: sharedStore,
            privateStoreSyncMode: plan.privateStore.syncMode,
            sharedStoreSyncMode: plan.sharedStore.syncMode
        )
    }

    private static func makeCoreDataStore(for plan: MonthlyMoneyStorePlan) throws -> CoreDataAccountDataStore {
        switch plan.syncMode {
        case .localOnly:
            return try CoreDataAccountDataStore.makePersistentLocal(url: plan.url)
        case .cloudPrivate:
            return try CoreDataAccountDataStore.makePersistentCloudKitPrivate(
                url: plan.url,
                containerIdentifier: cloudKitContainerIdentifier
            )
        case .cloudShared:
            return try CoreDataAccountDataStore.makePersistentCloudKitShared(
                url: plan.url,
                containerIdentifier: cloudKitContainerIdentifier
            )
        }
    }
}
