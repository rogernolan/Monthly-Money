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
}

extension AccountDataStore {
    func awaitInitialCloudImport(timeout: Duration) async throws {
        _ = timeout
    }

    func acceptShareInvitations(_ metadata: [CKShare.Metadata]) async throws {
        _ = metadata
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
        try store(for: budget.sharingState).upsertBudget(budget)
    }

    func activeBudget() throws -> Budget? {
        if let local = try preferredBudget(
            from: privateStore.fetchBudgets(),
            sharingState: .local
        ) {
            return local
        }
        return try preferredBudget(
            from: sharedStore.fetchBudgets(),
            sharingState: .shared
        )
    }

    func awaitInitialPrivateCloudImport(timeout: Duration) async throws {
        try await privateStore.awaitInitialCloudImport(timeout: timeout)
    }

    func prepareShareSession(forSharedBudgetID budgetID: UUID) async throws -> BudgetShareSession {
        guard let sharedStore = sharedStore as? CoreDataAccountDataStore else {
            throw BudgetShareCoordinatorError.sharingUnavailable
        }
        return try await sharedStore.prepareShareSession(
            for: budgetID,
            containerIdentifier: MonthlyMoneyPersistenceFactory.cloudKitContainerIdentifier
        )
    }

    func acceptIncomingSharedBudgetInvitations(_ metadata: [CKShare.Metadata]) async throws {
        guard !metadata.isEmpty else { return }
        try await sharedStore.acceptShareInvitations(metadata)
        try await sharedStore.awaitInitialCloudImport(timeout: .seconds(10))
    }

    func createAccount(name: String, role: AccountRole, type: AccountType, ownerParticipantID: String) throws -> Account {
        let budget = try ensureLocalBudget(ownerParticipantID: ownerParticipantID)
        let account = Account(budgetID: budget.id, name: name, role: role, type: type, ownerParticipantID: ownerParticipantID)
        try store(for: budget.sharingState).upsertAccount(account)
        try touchBudget(id: budget.id, in: store(for: budget.sharingState))
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

    func accounts() throws -> [Account] {
        guard let budget = try activeBudget() else { return [] }
        return try store(for: budget.sharingState).fetchAccounts().filter { $0.budgetID == budget.id }
    }

    func plannedItems(for month: YearMonth? = nil) throws -> [PlannedItem] {
        guard let budget = try activeBudget() else { return [] }
        let accountIDs = Set(try accounts().map(\.id))
        guard !accountIDs.isEmpty else { return [] }
        return try store(for: budget.sharingState).fetchPlannedItems(accountIDs: accountIDs, monthKey: month)
            .filter { $0.budgetID == budget.id }
    }

    func localBudget() throws -> Budget? {
        try preferredBudget(from: privateStore.fetchBudgets(), sharingState: .local)
    }

    @discardableResult
    func reconcileDuplicateLocalBudgets() throws -> Int {
        let localBudgets = try privateStore.fetchBudgets()
            .filter { $0.sharingState == .local }
            .sorted(by: Self.budgetSort)
        guard let canonicalBudget = localBudgets.first else { return 0 }

        var removed = 0
        for duplicate in localBudgets.dropFirst() where duplicate.id != canonicalBudget.id {
            try deleteLocalBudget(id: duplicate.id)
            removed += 1
        }
        return removed
    }

    func sharedBudget() throws -> Budget? {
        try preferredBudget(from: sharedStore.fetchBudgets(), sharingState: .shared)
    }

    func localBudgetSnapshot() throws -> (budget: Budget, accounts: [Account], plannedItems: [PlannedItem], transactions: [Transaction])? {
        guard let budget = try localBudget() else { return nil }
        let accounts = try privateStore.fetchAccounts().filter { $0.budgetID == budget.id }
        let accountIDs = Set(accounts.map(\.id))
        let plannedItems = try privateStore.fetchPlannedItems(accountIDs: accountIDs, monthKey: nil)
            .filter { $0.budgetID == budget.id }
        let transactions = try privateStore.fetchTransactions(accountIDs: accountIDs)
            .filter { $0.budgetID == budget.id }
        return (budget, accounts, plannedItems, transactions)
    }

    func insertShared(budget: Budget, accounts: [Account], plannedItems: [PlannedItem], transactions: [Transaction]) throws {
        try sharedStore.upsertBudget(budget)
        for account in accounts {
            try sharedStore.upsertAccount(account)
        }
        try sharedStore.upsertPlannedItems(plannedItems)
        try sharedStore.upsertTransactions(transactions)
    }

    func deleteLocalBudget(id: UUID) throws {
        let accounts = try privateStore.fetchAccounts().filter { $0.budgetID == id }
        for account in accounts {
            try privateStore.deletePlannedItems(accountID: account.id)
            try privateStore.deleteTransactions(accountID: account.id)
            try privateStore.deleteAccount(id: account.id)
        }
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

    private func preferredBudget(from budgets: [Budget], sharingState: BudgetSharingState) -> Budget? {
        budgets
            .filter { $0.sharingState == sharingState }
            .sorted(by: Self.budgetSort)
            .first
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
}
