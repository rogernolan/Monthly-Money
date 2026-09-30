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

enum MonthlyMoneySchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            Budget.self, Account.self, PlannedItem.self, PopulatedMonthRecord.self,
            Transaction.self, ImportedTransactionRecord.self, WheelOfMoneyItem.self,
            PeriodicRepeat.self, PeriodicRepeatRevision.self, PeriodicRepeatSkip.self,
            PeriodicOccurrenceRecord.self
        ]
    }
}

enum MonthlyMoneySchemaMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [MonthlyMoneySchemaV1.self, MonthlyMoneySchemaV2.self, MonthlyMoneySchemaV3.self]
    }

    static var stages: [MigrationStage] {
        [
            MigrationStage.lightweight(fromVersion: MonthlyMoneySchemaV1.self, toVersion: MonthlyMoneySchemaV2.self),
            MigrationStage.custom(
                fromVersion: MonthlyMoneySchemaV2.self,
                toVersion: MonthlyMoneySchemaV3.self,
                willMigrate: nil,
                didMigrate: migratePeriodicRepeats
            )
        ]
    }

    private struct LegacyRepeatKey: Hashable {
        let budgetID: UUID
        let accountID: UUID
        let recurrenceID: UUID
    }

    private static func migratePeriodicRepeats(in context: ModelContext) throws {
        let budgets = try context.fetch(FetchDescriptor<Budget>())
        let budgetsByID = Dictionary(uniqueKeysWithValues: budgets.map { ($0.id, $0) })
        let items = try context.fetch(FetchDescriptor<PlannedItem>())
        var groups: [LegacyRepeatKey: [(PlannedItem, CivilDate)]] = [:]

        for item in items {
            guard item.repeatMode == .periodic,
                  let interval = item.repeatDays, interval > 0,
                  let recurrenceID = item.recurrenceID,
                  let budget = budgetsByID[item.budgetID],
                  let date = legacyConcreteDate(for: item, paydayDay: budget.dailyBudgetPaydayDay) else {
                continue
            }
            let key = LegacyRepeatKey(
                budgetID: item.budgetID,
                accountID: item.accountID,
                recurrenceID: recurrenceID
            )
            groups[key, default: []].append((item, date))
        }

        for (key, rows) in groups {
            let ordered = rows.sorted {
                if $0.1 != $1.1 { return $0.1 < $1.1 }
                return $0.0.id.uuidString < $1.0.id.uuidString
            }
            guard let latest = ordered.last,
                  let interval = latest.0.repeatDays else { continue }
            let repeatRecord = PeriodicRepeat(
                id: key.recurrenceID,
                budgetID: key.budgetID,
                accountID: key.accountID
            )
            let revision = PeriodicRepeatRevision(
                repeatID: repeatRecord.id,
                effectiveDate: latest.1,
                anchorDate: latest.1,
                repeatDays: interval,
                type: latest.0.type,
                label: latest.0.label,
                matchingString: latest.0.matchingString,
                amount: latest.0.amount,
                notes: latest.0.notes
            )
            context.insert(repeatRecord)
            context.insert(revision)

            for (item, date) in ordered {
                let differsFromDefinition = item.type != latest.0.type
                    || item.label != latest.0.label
                    || item.matchingString != latest.0.matchingString
                    || item.amount != latest.0.amount
                    || item.repeatDays != latest.0.repeatDays
                    || item.notes != latest.0.notes
                context.insert(PeriodicOccurrenceRecord(
                    plannedItemID: item.id,
                    budgetID: item.budgetID,
                    repeatID: repeatRecord.id,
                    scheduledDate: date,
                    dueDate: date,
                    isOverride: differsFromDefinition
                ))
            }
        }
        try context.save()
    }

    private static func legacyConcreteDate(for item: PlannedItem, paydayDay: Int) -> CivilDate? {
        guard let month = YearMonth(rawValue: item.monthKey),
              let dueDay = item.dueDay,
              (1...31).contains(dueDay) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let payday = min(max(paydayDay, 1), 31)
        let dueMonth: YearMonth
        if payday <= 1 || dueDay < min(payday, daysInMonth(month, calendar: calendar)) {
            dueMonth = month
        } else {
            dueMonth = month.month == 1
                ? YearMonth(year: month.year - 1, month: 12)
                : YearMonth(year: month.year, month: month.month - 1)
        }
        let day = min(dueDay, daysInMonth(dueMonth, calendar: calendar))
        return CivilDate(year: dueMonth.year, month: dueMonth.month, day: day)
    }

    private static func daysInMonth(_ month: YearMonth, calendar: Calendar) -> Int {
        let date = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1))!
        return calendar.range(of: .day, in: .month, for: date)!.count
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
