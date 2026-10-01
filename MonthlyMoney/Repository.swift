import Foundation
import SwiftData
import CloudKit

enum RepositoryError: Error, Equatable {
    case accountNotFound
    case invalidCrossScopeReference
}

@MainActor
protocol AccountDataStore {
    var implementationKind: DataStoreImplementationKind { get }

    func awaitInitialCloudImport(timeout: Duration) async throws
    func acceptShareInvitations(_ metadata: [CKShare.Metadata]) async throws
    func hasActiveShare(for budgetID: UUID) throws -> Bool

    func fetchBudgets() throws -> [Budget]
    func fetchBudget(id: UUID) throws -> Budget?
    func upsertBudget(_ budget: Budget) throws
    func deleteBudget(id: UUID) throws

    func fetchAccounts() throws -> [Account]
    func fetchAccount(id: UUID) throws -> Account?
    func upsertAccount(_ account: Account) throws
    func deleteAccount(id: UUID) throws

    func fetchPlannedItems() throws -> [PlannedItem]
    func fetchPlannedItem(id: UUID) throws -> PlannedItem?
    func fetchPlannedItems(accountIDs: Set<UUID>, monthKey: YearMonth?) throws -> [PlannedItem]
    func upsertPlannedItems(_ items: [PlannedItem]) throws
    func deletePlannedItem(id: UUID) throws
    func deletePlannedItems(accountID: UUID) throws
    func fetchPeriodicRepeats(budgetID: UUID) throws -> [PeriodicRepeat]
    func fetchPeriodicRepeatRevisions(repeatIDs: Set<UUID>) throws -> [PeriodicRepeatRevision]
    func fetchPeriodicRepeatSkips(repeatIDs: Set<UUID>) throws -> [PeriodicRepeatSkip]
    func fetchPeriodicOccurrences(plannedItemIDs: Set<UUID>) throws -> [PeriodicOccurrenceRecord]
    func deletePeriodicOccurrences(plannedItemIDs: Set<UUID>) throws
    func upsertPeriodicRepeats(_ repeats: [PeriodicRepeat]) throws
    func upsertPeriodicRepeatRevisions(_ revisions: [PeriodicRepeatRevision]) throws
    func upsertPeriodicRepeatSkips(_ skips: [PeriodicRepeatSkip]) throws
    func upsertPeriodicOccurrences(_ occurrences: [PeriodicOccurrenceRecord]) throws
    func upsertPlannedItemAndPeriodicOccurrence(_ item: PlannedItem, occurrence: PeriodicOccurrenceRecord) throws
    func upsertDetachedPeriodicOccurrence(_ item: PlannedItem, occurrence: PeriodicOccurrenceRecord, skip: PeriodicRepeatSkip) throws
    func createPeriodicRepeat(repeatRecord: PeriodicRepeat, revision: PeriodicRepeatRevision, item: PlannedItem, occurrence: PeriodicOccurrenceRecord) throws
    func replacePeriodicRepeatRevisions(repeatID: UUID, from boundary: CivilDate, with revision: PeriodicRepeatRevision) throws
    func deletePeriodicRepeats(budgetID: UUID) throws
    func deletePeriodicRepeats(accountID: UUID) throws
    func fetchPopulatedMonths(budgetID: UUID) throws -> [PopulatedMonth]
    func upsertPopulatedMonths(_ months: [PopulatedMonth]) throws
    func deletePopulatedMonths(budgetID: UUID) throws

    func fetchTransactions() throws -> [Transaction]
    func fetchTransactions(accountIDs: Set<UUID>) throws -> [Transaction]
    func upsertTransactions(_ transactions: [Transaction]) throws
    func deleteTransactions(accountID: UUID) throws
    func deleteTransaction(id: UUID) throws

    func fetchImportedTransactionRecords(accountIDs: Set<UUID>) throws -> [ImportedTransactionRecord]
    func upsertImportedTransactionRecords(_ records: [ImportedTransactionRecord]) throws
    func deleteImportedTransactionRecords(accountID: UUID) throws
    func deleteImportedTransactionRecord(id: UUID) throws

    func fetchWheelOfMoneyItems() throws -> [WheelOfMoneyItem]
    func fetchWheelOfMoneyItem(id: UUID) throws -> WheelOfMoneyItem?
    func fetchWheelOfMoneyItems(budgetID: UUID) throws -> [WheelOfMoneyItem]
    func upsertWheelOfMoneyItems(_ items: [WheelOfMoneyItem]) throws
    func deleteWheelOfMoneyItem(id: UUID) throws
    func deleteWheelOfMoneyItems(budgetID: UUID) throws
}

extension AccountDataStore {
    func fetchPeriodicRepeats(budgetID: UUID) throws -> [PeriodicRepeat] { _ = budgetID; return [] }
    func fetchPeriodicRepeatRevisions(repeatIDs: Set<UUID>) throws -> [PeriodicRepeatRevision] { _ = repeatIDs; return [] }
    func fetchPeriodicRepeatSkips(repeatIDs: Set<UUID>) throws -> [PeriodicRepeatSkip] { _ = repeatIDs; return [] }
    func fetchPeriodicOccurrences(plannedItemIDs: Set<UUID>) throws -> [PeriodicOccurrenceRecord] { _ = plannedItemIDs; return [] }
    func deletePeriodicOccurrences(plannedItemIDs: Set<UUID>) throws { _ = plannedItemIDs }
    func upsertPeriodicRepeats(_ repeats: [PeriodicRepeat]) throws { _ = repeats }
    func upsertPeriodicRepeatRevisions(_ revisions: [PeriodicRepeatRevision]) throws { _ = revisions }
    func upsertPeriodicRepeatSkips(_ skips: [PeriodicRepeatSkip]) throws { _ = skips }
    func upsertPeriodicOccurrences(_ occurrences: [PeriodicOccurrenceRecord]) throws { _ = occurrences }
    func upsertPlannedItemAndPeriodicOccurrence(_ item: PlannedItem, occurrence: PeriodicOccurrenceRecord) throws { _ = item; _ = occurrence }
    func upsertDetachedPeriodicOccurrence(_ item: PlannedItem, occurrence: PeriodicOccurrenceRecord, skip: PeriodicRepeatSkip) throws {
        try upsertPlannedItems([item])
        try upsertPeriodicOccurrences([occurrence])
        try upsertPeriodicRepeatSkips([skip])
    }
    func createPeriodicRepeat(repeatRecord: PeriodicRepeat, revision: PeriodicRepeatRevision, item: PlannedItem, occurrence: PeriodicOccurrenceRecord) throws { _ = repeatRecord; _ = revision; _ = item; _ = occurrence }
    func replacePeriodicRepeatRevisions(repeatID: UUID, from boundary: CivilDate, with revision: PeriodicRepeatRevision) throws { _ = repeatID; _ = boundary; _ = revision }
    func deletePeriodicRepeats(budgetID: UUID) throws { _ = budgetID }
    func deletePeriodicRepeats(accountID: UUID) throws { _ = accountID }

    func fetchPopulatedMonths(budgetID: UUID) throws -> [PopulatedMonth] {
        _ = budgetID
        return []
    }

    func upsertPopulatedMonths(_ months: [PopulatedMonth]) throws {
        _ = months
    }

    func deletePopulatedMonths(budgetID: UUID) throws {
        _ = budgetID
    }

    func awaitInitialCloudImport(timeout: Duration) async throws {
        _ = timeout
    }

    func acceptShareInvitations(_ metadata: [CKShare.Metadata]) async throws {
        _ = metadata
    }

    func hasActiveShare(for budgetID: UUID) throws -> Bool {
        _ = budgetID
        return false
    }
}

enum DataStoreImplementationKind: Equatable {
    case inMemory
    case swiftData
    case coreData
}

struct PeriodicRepeatData {
    let repeats: [PeriodicRepeat]
    let revisions: [PeriodicRepeatRevision]
    let skips: [PeriodicRepeatSkip]
    let occurrences: [PeriodicOccurrenceRecord]
    let plannedItems: [PlannedItem]
}

@MainActor
final class InMemoryAccountDataStore: AccountDataStore {
    let implementationKind: DataStoreImplementationKind = .inMemory
    private var budgetsByID: [UUID: Budget] = [:]
    private var accountsByID: [UUID: Account] = [:]
    private var plannedItemsByID: [UUID: PlannedItem] = [:]
    private var populatedMonthsByID: [UUID: PopulatedMonth] = [:]
    private var transactionsByID: [UUID: Transaction] = [:]
    private var importedTransactionRecordsByID: [UUID: ImportedTransactionRecord] = [:]
    private var wheelOfMoneyItemsByID: [UUID: WheelOfMoneyItem] = [:]
    private var periodicRepeatsByID: [UUID: PeriodicRepeat] = [:]
    private var periodicRepeatRevisionsByID: [UUID: PeriodicRepeatRevision] = [:]
    private var periodicRepeatSkipsByID: [UUID: PeriodicRepeatSkip] = [:]
    private var periodicOccurrencesByPlannedItemID: [UUID: PeriodicOccurrenceRecord] = [:]

    init() {}

    func awaitInitialCloudImport(timeout: Duration) async throws {
        _ = timeout
    }

    func fetchBudgets() throws -> [Budget] {
        Array(budgetsByID.values)
    }

    func fetchBudget(id: UUID) throws -> Budget? {
        budgetsByID[id]
    }

    func upsertBudget(_ budget: Budget) throws {
        budgetsByID[budget.id] = budget
    }

    func deleteBudget(id: UUID) throws {
        try deletePeriodicRepeats(budgetID: id)
        budgetsByID[id] = nil
        try deletePopulatedMonths(budgetID: id)
    }

    func fetchAccounts() throws -> [Account] {
        Array(accountsByID.values)
    }

    func fetchAccount(id: UUID) throws -> Account? {
        accountsByID[id]
    }

    func upsertAccount(_ account: Account) throws {
        accountsByID[account.id] = account
    }

    func deleteAccount(id: UUID) throws {
        try deletePeriodicRepeats(accountID: id)
        accountsByID[id] = nil
    }

    func fetchPlannedItems() throws -> [PlannedItem] {
        Array(plannedItemsByID.values)
    }

    func fetchPlannedItem(id: UUID) throws -> PlannedItem? {
        plannedItemsByID[id]
    }

    func fetchPlannedItems(accountIDs: Set<UUID>, monthKey: YearMonth?) throws -> [PlannedItem] {
        Array(plannedItemsByID.values).filter { item in
            accountIDs.contains(item.accountID) && (monthKey == nil || item.monthKey == monthKey?.rawValue)
        }
    }

    func upsertPlannedItems(_ items: [PlannedItem]) throws {
        for item in items {
            plannedItemsByID[item.id] = item
        }
    }

    func deletePlannedItem(id: UUID) throws {
        plannedItemsByID[id] = nil
        periodicOccurrencesByPlannedItemID[id] = nil
    }

    func deletePlannedItems(accountID: UUID) throws {
        let plannedIDs = Set(plannedItemsByID.values.filter { $0.accountID == accountID }.map(\.id))
        plannedItemsByID = plannedItemsByID.filter { $0.value.accountID != accountID }
        try deletePeriodicOccurrences(plannedItemIDs: plannedIDs)
    }

    func fetchPeriodicRepeats(budgetID: UUID) throws -> [PeriodicRepeat] {
        periodicRepeatsByID.values.filter { $0.budgetID == budgetID }
    }

    func fetchPeriodicRepeatRevisions(repeatIDs: Set<UUID>) throws -> [PeriodicRepeatRevision] {
        periodicRepeatRevisionsByID.values.filter { repeatIDs.contains($0.repeatID) }
    }

    func fetchPeriodicRepeatSkips(repeatIDs: Set<UUID>) throws -> [PeriodicRepeatSkip] {
        periodicRepeatSkipsByID.values.filter { repeatIDs.contains($0.repeatID) }
    }

    func fetchPeriodicOccurrences(plannedItemIDs: Set<UUID>) throws -> [PeriodicOccurrenceRecord] {
        periodicOccurrencesByPlannedItemID.values.filter { plannedItemIDs.contains($0.plannedItemID) }
    }

    func deletePeriodicOccurrences(plannedItemIDs: Set<UUID>) throws {
        for id in plannedItemIDs { periodicOccurrencesByPlannedItemID[id] = nil }
    }

    func upsertPeriodicRepeats(_ repeats: [PeriodicRepeat]) throws {
        for value in repeats { periodicRepeatsByID[value.id] = value }
    }

    func upsertPeriodicRepeatRevisions(_ revisions: [PeriodicRepeatRevision]) throws {
        for value in revisions { periodicRepeatRevisionsByID[value.id] = value }
    }

    func upsertPeriodicRepeatSkips(_ skips: [PeriodicRepeatSkip]) throws {
        for value in skips {
            periodicRepeatSkipsByID[value.id] = value
        }
    }

    func upsertPeriodicOccurrences(_ occurrences: [PeriodicOccurrenceRecord]) throws {
        for value in occurrences { periodicOccurrencesByPlannedItemID[value.plannedItemID] = value }
    }

    func upsertPlannedItemAndPeriodicOccurrence(_ item: PlannedItem, occurrence: PeriodicOccurrenceRecord) throws {
        guard item.id == occurrence.plannedItemID, item.budgetID == occurrence.budgetID else {
            throw RepositoryError.invalidCrossScopeReference
        }
        plannedItemsByID[item.id] = item
        periodicOccurrencesByPlannedItemID[item.id] = occurrence
    }

    func upsertDetachedPeriodicOccurrence(_ item: PlannedItem, occurrence: PeriodicOccurrenceRecord, skip: PeriodicRepeatSkip) throws {
        guard item.id == occurrence.plannedItemID, item.budgetID == occurrence.budgetID,
              item.repeatMode == .oneOff, occurrence.repeatID == nil,
              occurrence.scheduledDate == skip.scheduledDate else { throw RepositoryError.invalidCrossScopeReference }
        plannedItemsByID[item.id] = item
        periodicOccurrencesByPlannedItemID[item.id] = occurrence
        periodicRepeatSkipsByID[skip.id] = skip
    }

    func createPeriodicRepeat(repeatRecord: PeriodicRepeat, revision: PeriodicRepeatRevision, item: PlannedItem, occurrence: PeriodicOccurrenceRecord) throws {
        guard repeatRecord.id == revision.repeatID, repeatRecord.id == occurrence.repeatID,
              item.id == occurrence.plannedItemID, item.budgetID == repeatRecord.budgetID,
              item.accountID == repeatRecord.accountID else { throw RepositoryError.invalidCrossScopeReference }
        periodicRepeatsByID[repeatRecord.id] = repeatRecord
        periodicRepeatRevisionsByID[revision.id] = revision
        plannedItemsByID[item.id] = item
        periodicOccurrencesByPlannedItemID[item.id] = occurrence
    }

    func replacePeriodicRepeatRevisions(repeatID: UUID, from boundary: CivilDate, with revision: PeriodicRepeatRevision) throws {
        periodicRepeatRevisionsByID = periodicRepeatRevisionsByID.filter {
            $0.value.repeatID != repeatID || $0.value.effectiveDate < boundary
        }
        periodicRepeatRevisionsByID[revision.id] = revision
    }

    func deletePeriodicRepeats(budgetID: UUID) throws {
        let repeatIDs = Set(periodicRepeatsByID.values.filter { $0.budgetID == budgetID }.map(\.id))
        periodicRepeatsByID = periodicRepeatsByID.filter { !repeatIDs.contains($0.key) }
        periodicRepeatRevisionsByID = periodicRepeatRevisionsByID.filter { !repeatIDs.contains($0.value.repeatID) }
        periodicRepeatSkipsByID = periodicRepeatSkipsByID.filter { !repeatIDs.contains($0.value.repeatID) }
        periodicOccurrencesByPlannedItemID = periodicOccurrencesByPlannedItemID.filter { $0.value.budgetID != budgetID }
    }

    func deletePeriodicRepeats(accountID: UUID) throws {
        let repeatIDs = Set(periodicRepeatsByID.values.filter { $0.accountID == accountID }.map(\.id))
        periodicRepeatsByID = periodicRepeatsByID.filter { !repeatIDs.contains($0.key) }
        periodicRepeatRevisionsByID = periodicRepeatRevisionsByID.filter { !repeatIDs.contains($0.value.repeatID) }
        periodicRepeatSkipsByID = periodicRepeatSkipsByID.filter { !repeatIDs.contains($0.value.repeatID) }
        periodicOccurrencesByPlannedItemID = periodicOccurrencesByPlannedItemID.filter {
            !repeatIDs.contains($0.value.repeatID ?? UUID())
        }
    }

    func fetchPopulatedMonths(budgetID: UUID) throws -> [PopulatedMonth] {
        populatedMonthsByID.values.filter { $0.budgetID == budgetID }
    }

    func upsertPopulatedMonths(_ months: [PopulatedMonth]) throws {
        for month in months {
            if let existing = populatedMonthsByID.values.first(where: { $0.budgetID == month.budgetID && $0.monthKey == month.monthKey }) {
                populatedMonthsByID[existing.id] = month
            } else {
                populatedMonthsByID[month.id] = month
            }
        }
    }

    func deletePopulatedMonths(budgetID: UUID) throws {
        populatedMonthsByID = populatedMonthsByID.filter { $0.value.budgetID != budgetID }
    }

    func fetchTransactions() throws -> [Transaction] {
        Array(transactionsByID.values)
    }

    func fetchTransactions(accountIDs: Set<UUID>) throws -> [Transaction] {
        Array(transactionsByID.values).filter { accountIDs.contains($0.accountID) }
    }

    func upsertTransactions(_ transactions: [Transaction]) throws {
        for transaction in transactions {
            transactionsByID[transaction.id] = transaction
        }
    }

    func deleteTransactions(accountID: UUID) throws {
        transactionsByID = transactionsByID.filter { $0.value.accountID != accountID }
    }

    func deleteTransaction(id: UUID) throws {
        transactionsByID[id] = nil
    }

    func fetchImportedTransactionRecords(accountIDs: Set<UUID>) throws -> [ImportedTransactionRecord] {
        Array(importedTransactionRecordsByID.values).filter { accountIDs.contains($0.accountID) }
    }

    func upsertImportedTransactionRecords(_ records: [ImportedTransactionRecord]) throws {
        for record in records {
            importedTransactionRecordsByID[record.id] = record
        }
    }

    func deleteImportedTransactionRecords(accountID: UUID) throws {
        importedTransactionRecordsByID = importedTransactionRecordsByID.filter { $0.value.accountID != accountID }
    }

    func deleteImportedTransactionRecord(id: UUID) throws {
        importedTransactionRecordsByID[id] = nil
    }

    func fetchWheelOfMoneyItems() throws -> [WheelOfMoneyItem] {
        Array(wheelOfMoneyItemsByID.values)
    }

    func fetchWheelOfMoneyItem(id: UUID) throws -> WheelOfMoneyItem? {
        wheelOfMoneyItemsByID[id]
    }

    func fetchWheelOfMoneyItems(budgetID: UUID) throws -> [WheelOfMoneyItem] {
        Array(wheelOfMoneyItemsByID.values).filter { $0.budgetID == budgetID }
    }

    func upsertWheelOfMoneyItems(_ items: [WheelOfMoneyItem]) throws {
        for item in items {
            wheelOfMoneyItemsByID[item.id] = item
        }
    }

    func deleteWheelOfMoneyItem(id: UUID) throws {
        wheelOfMoneyItemsByID[id] = nil
    }

    func deleteWheelOfMoneyItems(budgetID: UUID) throws {
        wheelOfMoneyItemsByID = wheelOfMoneyItemsByID.filter { $0.value.budgetID != budgetID }
    }
}

@MainActor
final class SwiftDataAccountDataStore: AccountDataStore {
    let implementationKind: DataStoreImplementationKind = .swiftData
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    init(modelContainer: ModelContainer) {
        self.modelContainer = modelContainer
        self.modelContext = ModelContext(modelContainer)
    }

    func awaitInitialCloudImport(timeout: Duration) async throws {
        _ = timeout
    }

    func fetchBudgets() throws -> [Budget] {
        try modelContext.fetch(FetchDescriptor<Budget>())
    }

    func fetchBudget(id: UUID) throws -> Budget? {
        let descriptor = FetchDescriptor<Budget>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    func upsertBudget(_ budget: Budget) throws {
        let budgetID = budget.id
        let descriptor = FetchDescriptor<Budget>(predicate: #Predicate { $0.id == budgetID })
        if let existing = try modelContext.fetch(descriptor).first {
            existing.name = budget.name
            existing.ownerParticipantID = budget.ownerParticipantID
            existing.sharingState = budget.sharingState
            existing.createdAt = budget.createdAt
            existing.updatedAt = budget.updatedAt
            existing.monthlyBalanceLastUpdatedAt = budget.monthlyBalanceLastUpdatedAt
            existing.dailyBalanceLastUpdatedAt = budget.dailyBalanceLastUpdatedAt
            existing.usesSeparateAccountForDailyBudget = budget.usesSeparateAccountForDailyBudget
            existing.dailyBudgetAmount = budget.dailyBudgetAmount
            existing.dailyBudgetPaydayDay = budget.dailyBudgetPaydayDay
            existing.dailyBudgetSeparateAccountBalance = budget.dailyBudgetSeparateAccountBalance
            existing.autoGenerateWoMSavingsEveryMonth = budget.autoGenerateWoMSavingsEveryMonth
            existing.allowsPreviousMonthEditing = budget.allowsPreviousMonthEditing
            existing.monthBalancesPayload = budget.monthBalancesPayload
            existing.hiddenDailyAccountID = budget.hiddenDailyAccountID
        } else {
            modelContext.insert(budget)
        }
        try modelContext.save()
    }

    func deleteBudget(id: UUID) throws {
        let descriptor = FetchDescriptor<Budget>(predicate: #Predicate { $0.id == id })
        if let budget = try modelContext.fetch(descriptor).first {
            try deletePopulatedMonths(budgetID: id)
            modelContext.delete(budget)
            try modelContext.save()
        }
    }

    func fetchAccounts() throws -> [Account] {
        try modelContext.fetch(FetchDescriptor<Account>())
    }

    func fetchAccount(id: UUID) throws -> Account? {
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    func upsertAccount(_ account: Account) throws {
        modelContext.insert(account)
        try modelContext.save()
    }

    func deleteAccount(id: UUID) throws {
        let descriptor = FetchDescriptor<Account>(predicate: #Predicate { $0.id == id })
        if let account = try modelContext.fetch(descriptor).first {
            try deletePeriodicRepeats(accountID: id)
            modelContext.delete(account)
            try modelContext.save()
        }
    }

    func fetchPlannedItems() throws -> [PlannedItem] {
        try modelContext.fetch(FetchDescriptor<PlannedItem>())
    }

    func fetchPlannedItem(id: UUID) throws -> PlannedItem? {
        let descriptor = FetchDescriptor<PlannedItem>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    func fetchPlannedItems(accountIDs: Set<UUID>, monthKey: YearMonth?) throws -> [PlannedItem] {
        let accountIDList = Array(accountIDs)
        if let monthRaw = monthKey?.rawValue {
            let descriptor = FetchDescriptor<PlannedItem>(predicate: #Predicate { item in
                accountIDList.contains(item.accountID) && item.monthKey == monthRaw
            })
            return try modelContext.fetch(descriptor)
        } else {
            let descriptor = FetchDescriptor<PlannedItem>(predicate: #Predicate { item in
                accountIDList.contains(item.accountID)
            })
            return try modelContext.fetch(descriptor)
        }
    }

    func upsertPlannedItems(_ items: [PlannedItem]) throws {
        for item in items {
            let itemID = item.id
            let descriptor = FetchDescriptor<PlannedItem>(predicate: #Predicate { $0.id == itemID })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.budgetID = item.budgetID
                existing.accountID = item.accountID
                existing.monthKey = item.monthKey
                existing.type = item.type
                existing.source = item.source
                existing.label = item.label
                existing.matchingString = item.matchingString
                existing.amount = item.amount
                existing.dueDay = item.dueDay
                existing.dueText = item.dueText
                existing.repeatDays = item.repeatDays
                existing.recurrenceID = item.recurrenceID
                existing.repeatMode = item.repeatMode
                existing.importedPostedAt = item.importedPostedAt
                existing.isPaid = item.isPaid
                existing.copiesToNextMonthAutomatically = item.copiesToNextMonthAutomatically
                existing.notes = item.notes
                existing.calendarContinuationPayload = item.calendarContinuationPayload
            } else {
                modelContext.insert(item)
            }
        }
        try modelContext.save()
    }

    func deletePlannedItem(id: UUID) throws {
        let descriptor = FetchDescriptor<PlannedItem>(predicate: #Predicate { $0.id == id })
        if let item = try modelContext.fetch(descriptor).first {
            try deletePeriodicOccurrences(plannedItemIDs: [id])
            modelContext.delete(item)
            try modelContext.save()
        }
    }

    func deletePlannedItems(accountID: UUID) throws {
        let descriptor = FetchDescriptor<PlannedItem>(predicate: #Predicate { $0.accountID == accountID })
        let items = try modelContext.fetch(descriptor)
        try deletePeriodicOccurrences(plannedItemIDs: Set(items.map(\.id)))
        items.forEach(modelContext.delete)
        try modelContext.save()
    }

    func fetchPeriodicRepeats(budgetID: UUID) throws -> [PeriodicRepeat] {
        let descriptor = FetchDescriptor<PeriodicRepeat>(predicate: #Predicate { $0.budgetID == budgetID })
        return try modelContext.fetch(descriptor)
    }

    func fetchPeriodicRepeatRevisions(repeatIDs: Set<UUID>) throws -> [PeriodicRepeatRevision] {
        try modelContext.fetch(FetchDescriptor<PeriodicRepeatRevision>()).filter { repeatIDs.contains($0.repeatID) }
    }

    func fetchPeriodicRepeatSkips(repeatIDs: Set<UUID>) throws -> [PeriodicRepeatSkip] {
        try modelContext.fetch(FetchDescriptor<PeriodicRepeatSkip>()).filter { repeatIDs.contains($0.repeatID) }
    }

    func fetchPeriodicOccurrences(plannedItemIDs: Set<UUID>) throws -> [PeriodicOccurrenceRecord] {
        try modelContext.fetch(FetchDescriptor<PeriodicOccurrenceRecord>()).filter { plannedItemIDs.contains($0.plannedItemID) }
    }

    func upsertPeriodicRepeats(_ repeats: [PeriodicRepeat]) throws {
        for value in repeats {
            let id = value.id
            if try modelContext.fetch(FetchDescriptor<PeriodicRepeat>(predicate: #Predicate { $0.id == id })).isEmpty {
                modelContext.insert(value)
            }
        }
        try modelContext.save()
    }

    func upsertPeriodicRepeatRevisions(_ revisions: [PeriodicRepeatRevision]) throws {
        for value in revisions {
            let id = value.id
            if try modelContext.fetch(FetchDescriptor<PeriodicRepeatRevision>(predicate: #Predicate { $0.id == id })).isEmpty {
                modelContext.insert(value)
            }
        }
        try modelContext.save()
    }

    func upsertPeriodicRepeatSkips(_ skips: [PeriodicRepeatSkip]) throws {
        for value in skips {
            let id = value.id
            if try modelContext.fetch(FetchDescriptor<PeriodicRepeatSkip>(predicate: #Predicate { $0.id == id })).isEmpty {
                modelContext.insert(value)
            }
        }
        try modelContext.save()
    }

    func upsertPeriodicOccurrences(_ occurrences: [PeriodicOccurrenceRecord]) throws {
        for value in occurrences {
            let id = value.plannedItemID
            if let existing = try modelContext.fetch(FetchDescriptor<PeriodicOccurrenceRecord>(predicate: #Predicate { $0.plannedItemID == id })).first {
                existing.repeatID = value.repeatID
                existing.scheduledDateRaw = value.scheduledDateRaw
                existing.dueDateRaw = value.dueDateRaw
                existing.isOverride = value.isOverride
            } else {
                modelContext.insert(value)
            }
        }
        try modelContext.save()
    }

    func upsertPlannedItemAndPeriodicOccurrence(_ item: PlannedItem, occurrence: PeriodicOccurrenceRecord) throws {
        guard item.id == occurrence.plannedItemID, item.budgetID == occurrence.budgetID else {
            throw RepositoryError.invalidCrossScopeReference
        }
        let itemID = item.id
        if let existing = try modelContext.fetch(FetchDescriptor<PlannedItem>(predicate: #Predicate { $0.id == itemID })).first {
            existing.budgetID = item.budgetID
            existing.accountID = item.accountID
            existing.monthKey = item.monthKey
            existing.type = item.type
            existing.source = item.source
            existing.label = item.label
            existing.matchingString = item.matchingString
            existing.amount = item.amount
            existing.dueDay = item.dueDay
            existing.dueText = item.dueText
            existing.repeatDays = item.repeatDays
            existing.recurrenceID = item.recurrenceID
            existing.repeatMode = item.repeatMode
            existing.importedPostedAt = item.importedPostedAt
            existing.isPaid = item.isPaid
            existing.copiesToNextMonthAutomatically = item.copiesToNextMonthAutomatically
            existing.notes = item.notes
            existing.calendarContinuationPayload = item.calendarContinuationPayload
        } else {
            modelContext.insert(item)
        }
        let occurrenceID = occurrence.plannedItemID
        if let existing = try modelContext.fetch(FetchDescriptor<PeriodicOccurrenceRecord>(predicate: #Predicate { $0.plannedItemID == occurrenceID })).first {
            existing.repeatID = occurrence.repeatID
            existing.scheduledDateRaw = occurrence.scheduledDateRaw
            existing.dueDateRaw = occurrence.dueDateRaw
            existing.isOverride = occurrence.isOverride
        } else {
            modelContext.insert(occurrence)
        }
        try modelContext.save()
    }

    func upsertDetachedPeriodicOccurrence(_ item: PlannedItem, occurrence: PeriodicOccurrenceRecord, skip: PeriodicRepeatSkip) throws {
        guard item.id == occurrence.plannedItemID, item.budgetID == occurrence.budgetID,
              item.repeatMode == .oneOff, occurrence.repeatID == nil,
              occurrence.scheduledDate == skip.scheduledDate else { throw RepositoryError.invalidCrossScopeReference }
        let itemID = item.id
        if let existing = try modelContext.fetch(FetchDescriptor<PlannedItem>(predicate: #Predicate { $0.id == itemID })).first {
            existing.monthKey = item.monthKey
            existing.type = item.type
            existing.label = item.label
            existing.matchingString = item.matchingString
            existing.amount = item.amount
            existing.dueDay = item.dueDay
            existing.repeatDays = nil
            existing.recurrenceID = nil
            existing.repeatMode = .oneOff
            existing.copiesToNextMonthAutomatically = false
            existing.notes = item.notes
            existing.calendarContinuationPayload = item.calendarContinuationPayload
        } else {
            modelContext.insert(item)
        }
        let occurrenceID = occurrence.plannedItemID
        if let existing = try modelContext.fetch(FetchDescriptor<PeriodicOccurrenceRecord>(predicate: #Predicate { $0.plannedItemID == occurrenceID })).first {
            existing.repeatID = nil
            existing.scheduledDateRaw = occurrence.scheduledDateRaw
            existing.dueDateRaw = occurrence.dueDateRaw
            existing.isOverride = true
        } else {
            modelContext.insert(occurrence)
        }
        modelContext.insert(skip)
        try modelContext.save()
    }

    func createPeriodicRepeat(repeatRecord: PeriodicRepeat, revision: PeriodicRepeatRevision, item: PlannedItem, occurrence: PeriodicOccurrenceRecord) throws {
        guard repeatRecord.id == revision.repeatID, repeatRecord.id == occurrence.repeatID,
              item.id == occurrence.plannedItemID, item.budgetID == repeatRecord.budgetID,
              item.accountID == repeatRecord.accountID else { throw RepositoryError.invalidCrossScopeReference }
        modelContext.insert(repeatRecord)
        modelContext.insert(revision)
        let itemID = item.id
        if let existing = try modelContext.fetch(FetchDescriptor<PlannedItem>(predicate: #Predicate { $0.id == itemID })).first {
            existing.monthKey = item.monthKey
            existing.type = item.type
            existing.label = item.label
            existing.matchingString = item.matchingString
            existing.amount = item.amount
            existing.dueDay = item.dueDay
            existing.repeatDays = item.repeatDays
            existing.recurrenceID = item.recurrenceID
            existing.repeatMode = item.repeatMode
            existing.copiesToNextMonthAutomatically = item.copiesToNextMonthAutomatically
            existing.notes = item.notes
            existing.calendarContinuationPayload = item.calendarContinuationPayload
        } else {
            modelContext.insert(item)
        }
        modelContext.insert(occurrence)
        try modelContext.save()
    }

    func replacePeriodicRepeatRevisions(repeatID: UUID, from boundary: CivilDate, with revision: PeriodicRepeatRevision) throws {
        let revisions = try modelContext.fetch(FetchDescriptor<PeriodicRepeatRevision>())
        revisions.filter { $0.repeatID == repeatID && $0.effectiveDate >= boundary }.forEach(modelContext.delete)
        modelContext.insert(revision)
        try modelContext.save()
    }

    func deletePeriodicRepeats(budgetID: UUID) throws {
        let repeats = try fetchPeriodicRepeats(budgetID: budgetID)
        let repeatIDs = Set(repeats.map(\.id))
        try modelContext.fetch(FetchDescriptor<PeriodicRepeatRevision>()).filter { repeatIDs.contains($0.repeatID) }.forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<PeriodicRepeatSkip>()).filter { repeatIDs.contains($0.repeatID) }.forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<PeriodicOccurrenceRecord>()).filter { $0.repeatID.map(repeatIDs.contains) == true }.forEach(modelContext.delete)
        repeats.forEach(modelContext.delete)
        try modelContext.save()
    }

    func deletePeriodicRepeats(accountID: UUID) throws {
        let repeats = try modelContext.fetch(FetchDescriptor<PeriodicRepeat>()).filter { $0.accountID == accountID }
        let repeatIDs = Set(repeats.map(\.id))
        try modelContext.fetch(FetchDescriptor<PeriodicRepeatRevision>()).filter { repeatIDs.contains($0.repeatID) }.forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<PeriodicRepeatSkip>()).filter { repeatIDs.contains($0.repeatID) }.forEach(modelContext.delete)
        try modelContext.fetch(FetchDescriptor<PeriodicOccurrenceRecord>()).filter { $0.repeatID.map(repeatIDs.contains) == true }.forEach(modelContext.delete)
        repeats.forEach(modelContext.delete)
        try modelContext.save()
    }

    func fetchPopulatedMonths(budgetID: UUID) throws -> [PopulatedMonth] {
        let budgetID = budgetID
        return try modelContext.fetch(FetchDescriptor<PopulatedMonthRecord>(predicate: #Predicate { $0.budgetID == budgetID }))
            .compactMap { month in
                guard let monthKey = YearMonth(rawValue: month.monthKey) else { return nil }
                return PopulatedMonth(id: month.id, budgetID: month.budgetID, monthKey: monthKey)
            }
    }

    func upsertPopulatedMonths(_ months: [PopulatedMonth]) throws {
        for month in months {
            let budgetID = month.budgetID
            let monthKey = month.monthKey.rawValue
            let descriptor = FetchDescriptor<PopulatedMonthRecord>(predicate: #Predicate { $0.budgetID == budgetID && $0.monthKey == monthKey })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.id = month.id
            } else {
                modelContext.insert(PopulatedMonthRecord(id: month.id, budgetID: month.budgetID, monthKey: month.monthKey))
            }
        }
        try modelContext.save()
    }

    func deletePopulatedMonths(budgetID: UUID) throws {
        let budgetID = budgetID
        let descriptor = FetchDescriptor<PopulatedMonthRecord>(predicate: #Predicate { $0.budgetID == budgetID })
        try modelContext.fetch(descriptor).forEach(modelContext.delete)
        try modelContext.save()
    }

    func fetchTransactions() throws -> [Transaction] {
        try modelContext.fetch(FetchDescriptor<Transaction>())
    }

    func fetchTransactions(accountIDs: Set<UUID>) throws -> [Transaction] {
        let accountIDList = Array(accountIDs)
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { accountIDList.contains($0.accountID) })
        return try modelContext.fetch(descriptor)
    }

    func upsertTransactions(_ transactions: [Transaction]) throws {
        for transaction in transactions {
            modelContext.insert(transaction)
        }
        try modelContext.save()
    }

    func deleteTransactions(accountID: UUID) throws {
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.accountID == accountID })
        try modelContext.fetch(descriptor).forEach(modelContext.delete)
        try modelContext.save()
    }

    func deleteTransaction(id: UUID) throws {
        let descriptor = FetchDescriptor<Transaction>(predicate: #Predicate { $0.id == id })
        if let transaction = try modelContext.fetch(descriptor).first {
            modelContext.delete(transaction)
            try modelContext.save()
        }
    }

    func fetchImportedTransactionRecords(accountIDs: Set<UUID>) throws -> [ImportedTransactionRecord] {
        let accountIDList = Array(accountIDs)
        let descriptor = FetchDescriptor<ImportedTransactionRecord>(predicate: #Predicate { accountIDList.contains($0.accountID) })
        return try modelContext.fetch(descriptor)
    }

    func upsertImportedTransactionRecords(_ records: [ImportedTransactionRecord]) throws {
        for record in records {
            let recordID = record.id
            let descriptor = FetchDescriptor<ImportedTransactionRecord>(predicate: #Predicate { $0.id == recordID })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.budgetID = record.budgetID
                existing.accountID = record.accountID
                existing.sourceKind = record.sourceKind
                existing.sourceAccountIdentifier = record.sourceAccountIdentifier
                existing.externalTransactionID = record.externalTransactionID
                existing.postedAt = record.postedAt
                existing.amount = record.amount
                existing.payee = record.payee
                existing.transactionType = record.transactionType
                existing.rawSourcePayload = record.rawSourcePayload
                existing.importedAt = record.importedAt
                existing.appliedPlannedItemID = record.appliedPlannedItemID
                existing.createdTransactionID = record.createdTransactionID
            } else {
                modelContext.insert(record)
            }
        }
        try modelContext.save()
    }

    func deleteImportedTransactionRecords(accountID: UUID) throws {
        let descriptor = FetchDescriptor<ImportedTransactionRecord>(predicate: #Predicate { $0.accountID == accountID })
        try modelContext.fetch(descriptor).forEach(modelContext.delete)
        try modelContext.save()
    }

    func deleteImportedTransactionRecord(id: UUID) throws {
        let descriptor = FetchDescriptor<ImportedTransactionRecord>(predicate: #Predicate { $0.id == id })
        if let record = try modelContext.fetch(descriptor).first {
            modelContext.delete(record)
            try modelContext.save()
        }
    }

    func fetchWheelOfMoneyItems() throws -> [WheelOfMoneyItem] {
        try modelContext.fetch(FetchDescriptor<WheelOfMoneyItem>())
    }

    func fetchWheelOfMoneyItem(id: UUID) throws -> WheelOfMoneyItem? {
        let descriptor = FetchDescriptor<WheelOfMoneyItem>(predicate: #Predicate { $0.id == id })
        return try modelContext.fetch(descriptor).first
    }

    func fetchWheelOfMoneyItems(budgetID: UUID) throws -> [WheelOfMoneyItem] {
        let descriptor = FetchDescriptor<WheelOfMoneyItem>(predicate: #Predicate { $0.budgetID == budgetID })
        return try modelContext.fetch(descriptor)
    }

    func upsertWheelOfMoneyItems(_ items: [WheelOfMoneyItem]) throws {
        for item in items {
            let itemID = item.id
            let descriptor = FetchDescriptor<WheelOfMoneyItem>(predicate: #Predicate { $0.id == itemID })
            if let existing = try modelContext.fetch(descriptor).first {
                existing.budgetID = item.budgetID
                existing.title = item.title
                existing.amount = item.amount
                existing.month = item.month
                existing.isPaid = item.isPaid
                existing.notes = item.notes
                existing.isAutoGeneratedSavingsEntry = item.isAutoGeneratedSavingsEntry
            } else {
                modelContext.insert(item)
            }
        }
        try modelContext.save()
    }

    func deleteWheelOfMoneyItem(id: UUID) throws {
        let descriptor = FetchDescriptor<WheelOfMoneyItem>(predicate: #Predicate { $0.id == id })
        if let item = try modelContext.fetch(descriptor).first {
            modelContext.delete(item)
            try modelContext.save()
        }
    }

    func deleteWheelOfMoneyItems(budgetID: UUID) throws {
        let descriptor = FetchDescriptor<WheelOfMoneyItem>(predicate: #Predicate { $0.budgetID == budgetID })
        try modelContext.fetch(descriptor).forEach(modelContext.delete)
        try modelContext.save()
    }
}

@MainActor
final class AccountRepository {
    private let privateStore: AccountDataStore
    private let sharedStore: AccountDataStore
    private let dateProvider: () -> Date
    private static let hiddenDailyAccountName = "Daily budget"
    let privateStoreSyncMode: StoreSyncMode
    let sharedStoreSyncMode: StoreSyncMode
    let privateStoreImplementationKind: DataStoreImplementationKind
    let sharedStoreImplementationKind: DataStoreImplementationKind

    init(
        privateStore: AccountDataStore,
        sharedStore: AccountDataStore,
        privateStoreSyncMode: StoreSyncMode = .localOnly,
        sharedStoreSyncMode: StoreSyncMode = .localOnly,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.privateStore = privateStore
        self.sharedStore = sharedStore
        self.privateStoreSyncMode = privateStoreSyncMode
        self.sharedStoreSyncMode = sharedStoreSyncMode
        self.dateProvider = dateProvider
        self.privateStoreImplementationKind = privateStore.implementationKind
        self.sharedStoreImplementationKind = sharedStore.implementationKind
    }

    @discardableResult
    func createBudget(name: String, ownerParticipantID: String, sharingState: BudgetSharingState = .local) throws -> Budget {
        let now = dateProvider()
        let budget = Budget(
            name: name,
            ownerParticipantID: ownerParticipantID,
            sharingState: sharingState,
            createdAt: now,
            updatedAt: now,
            monthlyBalanceLastUpdatedAt: now,
            dailyBalanceLastUpdatedAt: now
        )
        try store(for: sharingState).upsertBudget(budget)
        return budget
    }

    func saveBudget(_ budget: Budget, updateModifiedAt: Bool = true) throws {
        if updateModifiedAt {
            budget.updatedAt = dateProvider()
        }
        if try privateStore.fetchBudget(id: budget.id) != nil {
            try privateStore.upsertBudget(budget)
            return
        }
        if try sharedStore.fetchBudget(id: budget.id) != nil {
            try sharedStore.upsertBudget(budget)
            return
        }
        try store(for: budget.sharingState).upsertBudget(budget)
    }

    func markMonthlyBalanceUpdated(id: UUID) throws {
        try markBalanceViewsUpdated(id: id, monthly: true, daily: false)
    }

    func markDailyBalanceUpdated(id: UUID) throws {
        try markBalanceViewsUpdated(id: id, monthly: false, daily: true)
    }

    func markBalanceViewsUpdated(id: UUID, monthly: Bool, daily: Bool) throws {
        guard monthly || daily,
              let store = try storeHoldingBudget(id: id),
              let budget = try store.fetchBudget(id: id) else {
            return
        }

        let now = dateProvider()
        if monthly {
            budget.monthlyBalanceLastUpdatedAt = now
        }
        if daily {
            budget.dailyBalanceLastUpdatedAt = now
        }
        budget.updatedAt = now
        try store.upsertBudget(budget)
    }

    func activeBudget() throws -> Budget? {
        if let privateBudget = try preferredBudget(from: privateStore.fetchBudgets()) {
            return privateBudget
        }
        return try preferredBudget(from: sharedStore.fetchBudgets())
    }

    func awaitInitialPrivateCloudImport(timeout: Duration) async throws {
        try await privateStore.awaitInitialCloudImport(timeout: timeout)
    }

    func prepareShareSession(forSharedBudgetID budgetID: UUID) async throws -> BudgetShareSession {
        if let privateStore = privateStore as? CoreDataAccountDataStore,
           try privateStore.fetchBudget(id: budgetID) != nil {
            return try await privateStore.prepareShareSession(
                for: budgetID,
                containerIdentifier: MonthlyMoneyPersistenceFactory.cloudKitContainerIdentifier
            )
        }
        if let sharedStore = sharedStore as? CoreDataAccountDataStore,
           try sharedStore.fetchBudget(id: budgetID) != nil {
            return try await sharedStore.prepareShareSession(
                for: budgetID,
                containerIdentifier: MonthlyMoneyPersistenceFactory.cloudKitContainerIdentifier
            )
        }
        throw BudgetShareCoordinatorError.sharingUnavailable
    }

    func acceptIncomingSharedBudgetInvitations(_ metadata: [CKShare.Metadata]) async throws {
        guard !metadata.isEmpty else { return }
        try await sharedStore.acceptShareInvitations(metadata)
        try await sharedStore.awaitInitialCloudImport(timeout: .seconds(10))
    }

    func hasActiveShare(for budgetID: UUID) throws -> Bool {
        if try privateStore.fetchBudget(id: budgetID) != nil {
            return try privateStore.hasActiveShare(for: budgetID)
        }
        if try sharedStore.fetchBudget(id: budgetID) != nil {
            return try sharedStore.hasActiveShare(for: budgetID)
        }
        return false
    }

    func deleteBudget(id: UUID) throws {
        if try privateStore.fetchBudget(id: id) != nil {
            try deleteLocalBudget(id: id)
            return
        }

        let accounts = try sharedStore.fetchAccounts().filter { $0.budgetID == id }
        for account in accounts {
            try sharedStore.deletePlannedItems(accountID: account.id)
            try sharedStore.deleteTransactions(accountID: account.id)
            try sharedStore.deleteImportedTransactionRecords(accountID: account.id)
            try sharedStore.deleteAccount(id: account.id)
        }
        try sharedStore.deleteBudget(id: id)
    }

    func createAccount(name: String, role: AccountRole, type: AccountType, ownerParticipantID: String) throws -> Account {
        let budget = try ensureLocalBudget(ownerParticipantID: ownerParticipantID)
        let account = Account(budgetID: budget.id, name: name, role: role, type: type, ownerParticipantID: ownerParticipantID)
        let store = try storeHoldingBudget(id: budget.id) ?? store(for: budget.sharingState)
        try store.upsertAccount(account)
        try touchBudget(id: budget.id, in: store)
        return account
    }

    func createPlannedItem(_ item: PlannedItem) throws {
        guard let (store, account) = try storeAndAccount(for: item.accountID) else {
            throw RepositoryError.invalidCrossScopeReference
        }
        item.budgetID = account.budgetID
        try store.upsertPlannedItems([item])
        try touchBudget(id: account.budgetID, in: store)
    }

    func plannedItem(id: UUID) throws -> PlannedItem? {
        if let privateItem = try privateStore.fetchPlannedItem(id: id) {
            return privateItem
        }
        return try sharedStore.fetchPlannedItem(id: id)
    }

    func savePlannedItem(_ item: PlannedItem) throws {
        if let account = try privateStore.fetchAccount(id: item.accountID) {
            item.budgetID = account.budgetID
            try privateStore.upsertPlannedItems([item])
            try sharedStore.deletePlannedItem(id: item.id)
            try touchBudget(id: account.budgetID, in: privateStore)
            return
        }
        if let account = try sharedStore.fetchAccount(id: item.accountID) {
            item.budgetID = account.budgetID
            try sharedStore.upsertPlannedItems([item])
            try privateStore.deletePlannedItem(id: item.id)
            try touchBudget(id: account.budgetID, in: sharedStore)
            return
        }
        throw RepositoryError.invalidCrossScopeReference
    }

    func deletePlannedItem(id: UUID) throws {
        if let item = try privateStore.fetchPlannedItem(id: id) {
            try privateStore.deletePlannedItem(id: id)
            try touchBudget(id: item.budgetID, in: privateStore)
        }
        if let item = try sharedStore.fetchPlannedItem(id: id) {
            try sharedStore.deletePlannedItem(id: id)
            try touchBudget(id: item.budgetID, in: sharedStore)
        }
    }

    func createTransaction(_ transaction: Transaction) throws {
        guard let (store, account) = try storeAndAccount(for: transaction.accountID) else {
            throw RepositoryError.invalidCrossScopeReference
        }
        transaction.budgetID = account.budgetID
        try store.upsertTransactions([transaction])
        try touchBudget(id: account.budgetID, in: store)
    }

    func deleteTransaction(id: UUID) throws {
        if let transaction = try privateStore.fetchTransactions().first(where: { $0.id == id }) {
            try privateStore.deleteTransaction(id: id)
            try touchBudget(id: transaction.budgetID, in: privateStore)
            return
        }
        if let transaction = try sharedStore.fetchTransactions().first(where: { $0.id == id }) {
            try sharedStore.deleteTransaction(id: id)
            try touchBudget(id: transaction.budgetID, in: sharedStore)
        }
    }

    func saveTransaction(_ transaction: Transaction) throws {
        try createTransaction(transaction)
    }

    func createImportedTransactionRecord(_ record: ImportedTransactionRecord) throws {
        guard let (store, account) = try storeAndAccount(for: record.accountID) else {
            throw RepositoryError.invalidCrossScopeReference
        }
        record.budgetID = account.budgetID
        try store.upsertImportedTransactionRecords([record])
        try touchBudget(id: account.budgetID, in: store)
    }

    func deleteImportedTransactionRecord(id: UUID) throws {
        if let record = try privateStore.fetchImportedTransactionRecords(accountIDs: Set(privateStore.fetchAccounts().map(\.id))).first(where: { $0.id == id }) {
            try privateStore.deleteImportedTransactionRecord(id: id)
            try touchBudget(id: record.budgetID, in: privateStore)
            return
        }
        if let record = try sharedStore.fetchImportedTransactionRecords(accountIDs: Set(sharedStore.fetchAccounts().map(\.id))).first(where: { $0.id == id }) {
            try sharedStore.deleteImportedTransactionRecord(id: id)
            try touchBudget(id: record.budgetID, in: sharedStore)
        }
    }

    func saveImportedTransactionRecord(_ record: ImportedTransactionRecord) throws {
        try createImportedTransactionRecord(record)
    }

    func createWheelOfMoneyItem(_ item: WheelOfMoneyItem) throws {
        guard let budget = try activeBudget(),
              let store = try storeHoldingBudget(id: budget.id) else {
            throw RepositoryError.invalidCrossScopeReference
        }
        item.budgetID = budget.id
        try store.upsertWheelOfMoneyItems([item])
        try touchBudget(id: budget.id, in: store)
    }

    func accounts() throws -> [Account] {
        guard let budget = try activeBudget() else { return [] }
        guard let store = try storeHoldingBudget(id: budget.id) else { return [] }
        let hiddenDailyAccountID = budget.hiddenDailyAccountID
        let allAccounts = try store.fetchAccounts()
        var visibleAccounts: [Account] = []
        visibleAccounts.reserveCapacity(allAccounts.count)
        for account in allAccounts where account.budgetID == budget.id && account.id != hiddenDailyAccountID {
            visibleAccounts.append(account)
        }
        return visibleAccounts
    }

    func hiddenDailyAccount(for budget: Budget) throws -> Account? {
        guard budget.usesSeparateAccountForDailyBudget else { return nil }
        guard let hiddenDailyAccountID = budget.hiddenDailyAccountID,
              let store = try storeHoldingBudget(id: budget.id) else {
            return nil
        }
        return try store.fetchAccount(id: hiddenDailyAccountID)
    }

    func ensureHiddenDailyAccount(for budget: Budget) throws -> Account? {
        guard budget.usesSeparateAccountForDailyBudget else { return nil }
        if let hiddenDailyAccount = try hiddenDailyAccount(for: budget) {
            return hiddenDailyAccount
        }
        guard let store = try storeHoldingBudget(id: budget.id) else { return nil }
        let account = Account(
            budgetID: budget.id,
            name: Self.hiddenDailyAccountName,
            role: .regular,
            type: .current,
            ownerParticipantID: budget.ownerParticipantID
        )
        try store.upsertAccount(account)
        budget.hiddenDailyAccountID = account.id
        try saveBudget(budget)
        return account
    }

    func transactions(accountIDs: Set<UUID>) throws -> [Transaction] {
        let privateTransactions = try privateStore.fetchTransactions(accountIDs: accountIDs)
        let sharedTransactions = try sharedStore.fetchTransactions(accountIDs: accountIDs)
        return uniqueTransactions(from: privateTransactions + sharedTransactions)
    }

    func plannedItems(for month: YearMonth? = nil) throws -> [PlannedItem] {
        guard let budget = try activeBudget() else { return [] }
        let accountIDs = Set(try accounts().map(\.id))
        guard !accountIDs.isEmpty else { return [] }
        guard let store = try storeHoldingBudget(id: budget.id) else { return [] }
        return try store.fetchPlannedItems(accountIDs: accountIDs, monthKey: month)
            .filter { $0.budgetID == budget.id }
    }

    func populatedMonths() throws -> [PopulatedMonth] {
        guard let budget = try activeBudget(),
              let store = try storeHoldingBudget(id: budget.id) else { return [] }
        return try store.fetchPopulatedMonths(budgetID: budget.id)
            .filter { $0.budgetID == budget.id }
    }

    func isMonthPopulated(_ month: YearMonth) throws -> Bool {
        try populatedMonths().contains { $0.monthKey == month }
    }

    func markMonthPopulated(_ month: YearMonth) throws {
        guard let budget = try activeBudget(),
              let store = try storeHoldingBudget(id: budget.id) else { return }
        let marker = PopulatedMonth(budgetID: budget.id, monthKey: month)
        try store.upsertPopulatedMonths([marker])
        try touchBudget(id: budget.id, in: store)
    }

    func periodicItems(before month: YearMonth) throws -> [PlannedItem] {
        guard let budget = try activeBudget(),
              let store = try storeHoldingBudget(id: budget.id) else { return [] }
        let accountIDs = Set(try accounts().map(\.id))
        return try store.fetchPlannedItems(accountIDs: accountIDs, monthKey: nil)
            .filter { item in
                item.budgetID == budget.id && item.repeatMode == .periodic &&
                (item.repeatDays ?? 0) > 0 && item.recurrenceID != nil &&
                (item.resolvedMonthKey ?? month) < month
            }
    }

    func periodicRepeatData(for budgetID: UUID? = nil) throws -> PeriodicRepeatData {
        let budget: Budget?
        if let budgetID {
            budget = try privateStore.fetchBudget(id: budgetID) ?? sharedStore.fetchBudget(id: budgetID)
        } else {
            budget = try activeBudget()
        }
        guard let budget,
              let store = try storeHoldingBudget(id: budget.id) else {
            return PeriodicRepeatData(repeats: [], revisions: [], skips: [], occurrences: [], plannedItems: [])
        }
        let repeats = try store.fetchPeriodicRepeats(budgetID: budget.id)
        let repeatIDs = Set(repeats.map(\.id))
        let revisions = try store.fetchPeriodicRepeatRevisions(repeatIDs: repeatIDs)
        let skips = try store.fetchPeriodicRepeatSkips(repeatIDs: repeatIDs)
        let accountIDs = Set(try store.fetchAccounts().filter { $0.budgetID == budget.id }.map(\.id))
        let plannedItems = try store.fetchPlannedItems(accountIDs: accountIDs, monthKey: nil)
            .filter { $0.budgetID == budget.id }
        let plannedIDs = Set(plannedItems.map(\.id))
        let occurrences = try store.fetchPeriodicOccurrences(plannedItemIDs: plannedIDs)
        return PeriodicRepeatData(repeats: repeats, revisions: revisions, skips: skips, occurrences: occurrences, plannedItems: plannedItems)
    }

    func savePeriodicRepeat(_ repeatRecord: PeriodicRepeat) throws {
        guard let store = try storeHoldingBudget(id: repeatRecord.budgetID),
              try store.fetchAccount(id: repeatRecord.accountID)?.budgetID == repeatRecord.budgetID else {
            throw RepositoryError.invalidCrossScopeReference
        }
        try store.upsertPeriodicRepeats([repeatRecord])
        try touchBudget(id: repeatRecord.budgetID, in: store)
    }

    func createPeriodicRepeat(
        repeatRecord: PeriodicRepeat,
        revision: PeriodicRepeatRevision,
        item: PlannedItem,
        occurrence: PeriodicOccurrenceRecord
    ) throws {
        guard repeatRecord.id == revision.repeatID, repeatRecord.id == occurrence.repeatID,
              item.id == occurrence.plannedItemID,
              let (store, account) = try storeAndAccount(for: repeatRecord.accountID),
              account.budgetID == repeatRecord.budgetID, item.accountID == account.id,
              item.budgetID == repeatRecord.budgetID else { throw RepositoryError.invalidCrossScopeReference }
        try store.createPeriodicRepeat(repeatRecord: repeatRecord, revision: revision, item: item, occurrence: occurrence)
        try touchBudget(id: repeatRecord.budgetID, in: store)
    }

    func savePeriodicRepeatRevisions(_ revisions: [PeriodicRepeatRevision], budgetID: UUID) throws {
        guard let store = try storeHoldingBudget(id: budgetID) else { throw RepositoryError.invalidCrossScopeReference }
        let repeats = try store.fetchPeriodicRepeats(budgetID: budgetID)
        let repeatIDs = Set(repeats.map(\.id))
        guard revisions.allSatisfy({ repeatIDs.contains($0.repeatID) }) else { throw RepositoryError.invalidCrossScopeReference }
        try store.upsertPeriodicRepeatRevisions(revisions)
        try touchBudget(id: budgetID, in: store)
    }

    func replacePeriodicRepeatRevision(
        repeatID: UUID,
        from boundary: CivilDate,
        with revision: PeriodicRepeatRevision,
        budgetID: UUID
    ) throws {
        guard revision.repeatID == repeatID,
              let store = try storeHoldingBudget(id: budgetID),
              try store.fetchPeriodicRepeats(budgetID: budgetID).contains(where: { $0.id == repeatID }) else {
            throw RepositoryError.invalidCrossScopeReference
        }
        try store.replacePeriodicRepeatRevisions(repeatID: repeatID, from: boundary, with: revision)
        try touchBudget(id: budgetID, in: store)
    }

    func savePeriodicRepeatSkips(_ skips: [PeriodicRepeatSkip], budgetID: UUID) throws {
        guard let store = try storeHoldingBudget(id: budgetID) else { throw RepositoryError.invalidCrossScopeReference }
        let repeats = try store.fetchPeriodicRepeats(budgetID: budgetID)
        let repeatIDs = Set(repeats.map(\.id))
        guard skips.allSatisfy({ repeatIDs.contains($0.repeatID) }) else { throw RepositoryError.invalidCrossScopeReference }
        try store.upsertPeriodicRepeatSkips(skips)
        try touchBudget(id: budgetID, in: store)
    }

    func savePeriodicOccurrences(_ occurrences: [PeriodicOccurrenceRecord], budgetID: UUID) throws {
        guard let store = try storeHoldingBudget(id: budgetID) else { throw RepositoryError.invalidCrossScopeReference }
        let accountIDs = Set(try store.fetchAccounts().filter { $0.budgetID == budgetID }.map(\.id))
        let plannedIDs = Set(try store.fetchPlannedItems(accountIDs: accountIDs, monthKey: nil).map(\.id))
        guard occurrences.allSatisfy({ plannedIDs.contains($0.plannedItemID) && $0.budgetID == budgetID }) else {
            throw RepositoryError.invalidCrossScopeReference
        }
        try store.upsertPeriodicOccurrences(occurrences)
        try touchBudget(id: budgetID, in: store)
    }

    func savePeriodicOccurrence(_ item: PlannedItem, record: PeriodicOccurrenceRecord) throws {
        guard item.id == record.plannedItemID, item.budgetID == record.budgetID,
              let (store, account) = try storeAndAccount(for: item.accountID), account.budgetID == item.budgetID else {
            throw RepositoryError.invalidCrossScopeReference
        }
        if let repeatID = record.repeatID,
           try !store.fetchPeriodicRepeats(budgetID: item.budgetID).contains(where: { $0.id == repeatID }) {
            throw RepositoryError.invalidCrossScopeReference
        }
        try store.upsertPlannedItemAndPeriodicOccurrence(item, occurrence: record)
        try touchBudget(id: item.budgetID, in: store)
    }

    func saveDetachedPeriodicOccurrence(_ item: PlannedItem, record: PeriodicOccurrenceRecord, skip: PeriodicRepeatSkip) throws {
        guard item.id == record.plannedItemID, item.budgetID == record.budgetID,
              record.repeatID == nil, item.repeatMode == .oneOff,
              let (store, account) = try storeAndAccount(for: item.accountID), account.budgetID == item.budgetID,
              try store.fetchPeriodicRepeats(budgetID: item.budgetID).contains(where: { $0.id == skip.repeatID }) else {
            throw RepositoryError.invalidCrossScopeReference
        }
        try store.upsertDetachedPeriodicOccurrence(item, occurrence: record, skip: skip)
        try touchBudget(id: item.budgetID, in: store)
    }

    func hasPlannedItem(id: UUID) throws -> Bool {
        try privateStore.fetchPlannedItem(id: id) != nil || sharedStore.fetchPlannedItem(id: id) != nil
    }

    func wheelOfMoneyItem(id: UUID) throws -> WheelOfMoneyItem? {
        if let item = try privateStore.fetchWheelOfMoneyItem(id: id) {
            return item
        }
        return try sharedStore.fetchWheelOfMoneyItem(id: id)
    }

    func importedTransactionRecords(accountIDs: Set<UUID>) throws -> [ImportedTransactionRecord] {
        let privateRecords = try privateStore.fetchImportedTransactionRecords(accountIDs: accountIDs)
        let sharedRecords = try sharedStore.fetchImportedTransactionRecords(accountIDs: accountIDs)
        return uniqueImportedTransactionRecords(from: privateRecords + sharedRecords)
    }

    func wheelOfMoneyItems() throws -> [WheelOfMoneyItem] {
        guard let budget = try activeBudget(),
              let store = try storeHoldingBudget(id: budget.id) else {
            return []
        }
        return try store.fetchWheelOfMoneyItems(budgetID: budget.id)
            .filter { $0.budgetID == budget.id }
    }

    func saveWheelOfMoneyItem(_ item: WheelOfMoneyItem) throws {
        if try privateStore.fetchBudget(id: item.budgetID) != nil {
            try privateStore.upsertWheelOfMoneyItems([item])
            try sharedStore.deleteWheelOfMoneyItem(id: item.id)
            try touchBudget(id: item.budgetID, in: privateStore)
            return
        }
        if try sharedStore.fetchBudget(id: item.budgetID) != nil {
            try sharedStore.upsertWheelOfMoneyItems([item])
            try privateStore.deleteWheelOfMoneyItem(id: item.id)
            try touchBudget(id: item.budgetID, in: sharedStore)
            return
        }
        throw RepositoryError.invalidCrossScopeReference
    }

    func setWheelOfMoneyItemPaid(id: UUID, isPaid: Bool) throws {
        guard let item = try wheelOfMoneyItem(id: id) else { return }
        item.isPaid = isPaid
        try saveWheelOfMoneyItem(item)
    }

    func deleteWheelOfMoneyItem(id: UUID) throws {
        if let item = try privateStore.fetchWheelOfMoneyItem(id: id) {
            try privateStore.deleteWheelOfMoneyItem(id: id)
            try touchBudget(id: item.budgetID, in: privateStore)
        }
        if let item = try sharedStore.fetchWheelOfMoneyItem(id: id) {
            try sharedStore.deleteWheelOfMoneyItem(id: id)
            try touchBudget(id: item.budgetID, in: sharedStore)
        }
    }

    func localBudget() throws -> Budget? {
        try preferredBudget(from: privateStore.fetchBudgets())
    }

    @discardableResult
    func reconcileDuplicateLocalBudgets() throws -> Int {
        let localBudgets = try privateStore.fetchBudgets().sorted(by: Self.budgetSort)
        guard let canonicalBudget = localBudgets.first else { return 0 }

        var removed = 0
        for duplicate in localBudgets.dropFirst() where duplicate.id != canonicalBudget.id {
            try deleteLocalBudget(id: duplicate.id)
            removed += 1
        }
        return removed
    }

    func sharedBudget() throws -> Budget? {
        try preferredBudget(from: sharedStore.fetchBudgets())
    }

    func localBudgetSnapshot() throws -> (budget: Budget, accounts: [Account], plannedItems: [PlannedItem], transactions: [Transaction], wheelOfMoneyItems: [WheelOfMoneyItem], populatedMonths: [PopulatedMonth], periodicRepeats: [PeriodicRepeat], periodicRepeatRevisions: [PeriodicRepeatRevision], periodicRepeatSkips: [PeriodicRepeatSkip], periodicOccurrences: [PeriodicOccurrenceRecord])? {
        guard let budget = try localBudget() else { return nil }
        let accounts = try privateStore.fetchAccounts().filter { $0.budgetID == budget.id }
        let accountIDs = Set(accounts.map(\.id))
        let plannedItems = try privateStore.fetchPlannedItems(accountIDs: accountIDs, monthKey: nil)
            .filter { $0.budgetID == budget.id }
        let transactions = try privateStore.fetchTransactions(accountIDs: accountIDs)
            .filter { $0.budgetID == budget.id }
        let wheelOfMoneyItems = try privateStore.fetchWheelOfMoneyItems(budgetID: budget.id)
            .filter { $0.budgetID == budget.id }
        let populatedMonths = try privateStore.fetchPopulatedMonths(budgetID: budget.id)
        let periodicRepeats = try privateStore.fetchPeriodicRepeats(budgetID: budget.id)
        let repeatIDs = Set(periodicRepeats.map(\.id))
        let periodicRepeatRevisions = try privateStore.fetchPeriodicRepeatRevisions(repeatIDs: repeatIDs)
        let periodicRepeatSkips = try privateStore.fetchPeriodicRepeatSkips(repeatIDs: repeatIDs)
        let periodicOccurrences = try privateStore.fetchPeriodicOccurrences(plannedItemIDs: Set(plannedItems.map(\.id)))
        return (budget, accounts, plannedItems, transactions, wheelOfMoneyItems, populatedMonths, periodicRepeats, periodicRepeatRevisions, periodicRepeatSkips, periodicOccurrences)
    }

    func insertShared(budget: Budget, accounts: [Account], plannedItems: [PlannedItem], transactions: [Transaction], wheelOfMoneyItems: [WheelOfMoneyItem], populatedMonths: [PopulatedMonth] = [], periodicRepeats: [PeriodicRepeat] = [], periodicRepeatRevisions: [PeriodicRepeatRevision] = [], periodicRepeatSkips: [PeriodicRepeatSkip] = [], periodicOccurrences: [PeriodicOccurrenceRecord] = []) throws {
        try sharedStore.upsertBudget(budget)
        for account in accounts {
            try sharedStore.upsertAccount(account)
        }
        try sharedStore.upsertPlannedItems(plannedItems)
        try sharedStore.upsertTransactions(transactions)
        let importedRecords = try privateStore.fetchImportedTransactionRecords(accountIDs: Set(accounts.map(\.id)))
        try sharedStore.upsertImportedTransactionRecords(importedRecords)
        try sharedStore.upsertWheelOfMoneyItems(wheelOfMoneyItems)
        try sharedStore.upsertPopulatedMonths(populatedMonths)
        try sharedStore.upsertPeriodicRepeats(periodicRepeats)
        try sharedStore.upsertPeriodicRepeatRevisions(periodicRepeatRevisions)
        try sharedStore.upsertPeriodicRepeatSkips(periodicRepeatSkips)
        try sharedStore.upsertPeriodicOccurrences(periodicOccurrences)
    }

    func deleteLocalBudget(id: UUID) throws {
        let accounts = try privateStore.fetchAccounts().filter { $0.budgetID == id }
        for account in accounts {
            try privateStore.deletePlannedItems(accountID: account.id)
            try privateStore.deleteTransactions(accountID: account.id)
            try privateStore.deleteImportedTransactionRecords(accountID: account.id)
            try privateStore.deleteAccount(id: account.id)
        }
        try privateStore.deleteWheelOfMoneyItems(budgetID: id)
        try privateStore.deleteBudget(id: id)
    }

    private func store(for sharingState: BudgetSharingState) -> AccountDataStore {
        sharingState == .local ? privateStore : sharedStore
    }

    private func storeAndAccount(for accountID: UUID) throws -> (AccountDataStore, Account)? {
        if let account = try privateStore.fetchAccount(id: accountID) {
            return (privateStore, account)
        }
        if let account = try sharedStore.fetchAccount(id: accountID) {
            return (sharedStore, account)
        }
        return nil
    }

    private func ensureLocalBudget(ownerParticipantID: String) throws -> Budget {
        if let budget = try localBudget() {
            return budget
        }
        return try createBudget(name: "Budget", ownerParticipantID: ownerParticipantID, sharingState: .local)
    }

    private func preferredBudget(from budgets: [Budget]) -> Budget? {
        budgets
            .sorted(by: Self.budgetSort)
            .first
    }

    private func storeHoldingBudget(id: UUID) throws -> AccountDataStore? {
        if try privateStore.fetchBudget(id: id) != nil {
            return privateStore
        }
        if try sharedStore.fetchBudget(id: id) != nil {
            return sharedStore
        }
        return nil
    }

    private func touchBudget(id: UUID, in store: AccountDataStore) throws {
        guard let budget = try store.fetchBudget(id: id) else { return }
        budget.updatedAt = dateProvider()
        try store.upsertBudget(budget)
    }

    nonisolated private static func budgetSort(lhs: Budget, rhs: Budget) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private func uniqueImportedTransactionRecords(from records: [ImportedTransactionRecord]) -> [ImportedTransactionRecord] {
        var recordsByID: [UUID: ImportedTransactionRecord] = [:]
        for record in records {
            recordsByID[record.id] = record
        }
        return Array(recordsByID.values).sorted(by: Self.importedTransactionSort)
    }

    private func uniqueTransactions(from transactions: [Transaction]) -> [Transaction] {
        var transactionsByID: [UUID: Transaction] = [:]
        for transaction in transactions {
            transactionsByID[transaction.id] = transaction
        }
        return Array(transactionsByID.values)
    }

    nonisolated private static func importedTransactionSort(
        _ lhs: ImportedTransactionRecord,
        _ rhs: ImportedTransactionRecord
    ) -> Bool {
        if lhs.postedAt != rhs.postedAt {
            return lhs.postedAt < rhs.postedAt
        }
        if lhs.externalTransactionID != rhs.externalTransactionID {
            return lhs.externalTransactionID < rhs.externalTransactionID
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
