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

    func fetchTransactions() throws -> [Transaction]
    func fetchTransactions(accountIDs: Set<UUID>) throws -> [Transaction]
    func upsertTransactions(_ transactions: [Transaction]) throws
    func deleteTransactions(accountID: UUID) throws

    func fetchImportedTransactionRecords(accountIDs: Set<UUID>) throws -> [ImportedTransactionRecord]
    func upsertImportedTransactionRecords(_ records: [ImportedTransactionRecord]) throws
    func deleteImportedTransactionRecords(accountID: UUID) throws

    func fetchWheelOfMoneyItems() throws -> [WheelOfMoneyItem]
    func fetchWheelOfMoneyItem(id: UUID) throws -> WheelOfMoneyItem?
    func fetchWheelOfMoneyItems(budgetID: UUID) throws -> [WheelOfMoneyItem]
    func upsertWheelOfMoneyItems(_ items: [WheelOfMoneyItem]) throws
    func deleteWheelOfMoneyItem(id: UUID) throws
    func deleteWheelOfMoneyItems(budgetID: UUID) throws
}

extension AccountDataStore {
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

@MainActor
final class InMemoryAccountDataStore: AccountDataStore {
    let implementationKind: DataStoreImplementationKind = .inMemory
    private var budgetsByID: [UUID: Budget] = [:]
    private var accountsByID: [UUID: Account] = [:]
    private var plannedItemsByID: [UUID: PlannedItem] = [:]
    private var transactionsByID: [UUID: Transaction] = [:]
    private var importedTransactionRecordsByID: [UUID: ImportedTransactionRecord] = [:]
    private var wheelOfMoneyItemsByID: [UUID: WheelOfMoneyItem] = [:]

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
        budgetsByID[id] = nil
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
    }

    func deletePlannedItems(accountID: UUID) throws {
        plannedItemsByID = plannedItemsByID.filter { $0.value.accountID != accountID }
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
            existing.usesSeparateAccountForDailyBudget = budget.usesSeparateAccountForDailyBudget
            existing.dailyBudgetAmount = budget.dailyBudgetAmount
            existing.dailyBudgetPaydayDay = budget.dailyBudgetPaydayDay
            existing.dailyBudgetSeparateAccountBalance = budget.dailyBudgetSeparateAccountBalance
            existing.autoGenerateWoMSavingsEveryMonth = budget.autoGenerateWoMSavingsEveryMonth
            existing.monthBalancesPayload = budget.monthBalancesPayload
        } else {
            modelContext.insert(budget)
        }
        try modelContext.save()
    }

    func deleteBudget(id: UUID) throws {
        let descriptor = FetchDescriptor<Budget>(predicate: #Predicate { $0.id == id })
        if let budget = try modelContext.fetch(descriptor).first {
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
                existing.label = item.label
                existing.amount = item.amount
                existing.dueDay = item.dueDay
                existing.dueText = item.dueText
                existing.isPaid = item.isPaid
                existing.notes = item.notes
            } else {
                modelContext.insert(item)
            }
        }
        try modelContext.save()
    }

    func deletePlannedItem(id: UUID) throws {
        let descriptor = FetchDescriptor<PlannedItem>(predicate: #Predicate { $0.id == id })
        if let item = try modelContext.fetch(descriptor).first {
            modelContext.delete(item)
            try modelContext.save()
        }
    }

    func deletePlannedItems(accountID: UUID) throws {
        let descriptor = FetchDescriptor<PlannedItem>(predicate: #Predicate { $0.accountID == accountID })
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

final class AccountRepository {
    private let privateStore: AccountDataStore
    private let sharedStore: AccountDataStore
    let privateStoreSyncMode: StoreSyncMode
    let sharedStoreSyncMode: StoreSyncMode
    let privateStoreImplementationKind: DataStoreImplementationKind
    let sharedStoreImplementationKind: DataStoreImplementationKind

    init(
        privateStore: AccountDataStore,
        sharedStore: AccountDataStore,
        privateStoreSyncMode: StoreSyncMode = .localOnly,
        sharedStoreSyncMode: StoreSyncMode = .localOnly
    ) {
        self.privateStore = privateStore
        self.sharedStore = sharedStore
        self.privateStoreSyncMode = privateStoreSyncMode
        self.sharedStoreSyncMode = sharedStoreSyncMode
        self.privateStoreImplementationKind = privateStore.implementationKind
        self.sharedStoreImplementationKind = sharedStore.implementationKind
    }

    @discardableResult
    func createBudget(name: String, ownerParticipantID: String, sharingState: BudgetSharingState = .local) throws -> Budget {
        let now = Date()
        let budget = Budget(
            name: name,
            ownerParticipantID: ownerParticipantID,
            sharingState: sharingState,
            createdAt: now,
            updatedAt: now
        )
        try store(for: sharingState).upsertBudget(budget)
        return budget
    }

    func saveBudget(_ budget: Budget) throws {
        budget.updatedAt = Date()
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
        return try store.fetchAccounts().filter { $0.budgetID == budget.id }
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

    func localBudgetSnapshot() throws -> (budget: Budget, accounts: [Account], plannedItems: [PlannedItem], transactions: [Transaction], wheelOfMoneyItems: [WheelOfMoneyItem])? {
        guard let budget = try localBudget() else { return nil }
        let accounts = try privateStore.fetchAccounts().filter { $0.budgetID == budget.id }
        let accountIDs = Set(accounts.map(\.id))
        let plannedItems = try privateStore.fetchPlannedItems(accountIDs: accountIDs, monthKey: nil)
            .filter { $0.budgetID == budget.id }
        let transactions = try privateStore.fetchTransactions(accountIDs: accountIDs)
            .filter { $0.budgetID == budget.id }
        let wheelOfMoneyItems = try privateStore.fetchWheelOfMoneyItems(budgetID: budget.id)
            .filter { $0.budgetID == budget.id }
        return (budget, accounts, plannedItems, transactions, wheelOfMoneyItems)
    }

    func insertShared(budget: Budget, accounts: [Account], plannedItems: [PlannedItem], transactions: [Transaction], wheelOfMoneyItems: [WheelOfMoneyItem]) throws {
        try sharedStore.upsertBudget(budget)
        for account in accounts {
            try sharedStore.upsertAccount(account)
        }
        try sharedStore.upsertPlannedItems(plannedItems)
        try sharedStore.upsertTransactions(transactions)
        let importedRecords = try privateStore.fetchImportedTransactionRecords(accountIDs: Set(accounts.map(\.id)))
        try sharedStore.upsertImportedTransactionRecords(importedRecords)
        try sharedStore.upsertWheelOfMoneyItems(wheelOfMoneyItems)
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
        budget.updatedAt = Date()
        try store.upsertBudget(budget)
    }

    private static func budgetSort(lhs: Budget, rhs: Budget) -> Bool {
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

    private static func importedTransactionSort(_ lhs: ImportedTransactionRecord, _ rhs: ImportedTransactionRecord) -> Bool {
        if lhs.postedAt != rhs.postedAt {
            return lhs.postedAt < rhs.postedAt
        }
        if lhs.externalTransactionID != rhs.externalTransactionID {
            return lhs.externalTransactionID < rhs.externalTransactionID
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
