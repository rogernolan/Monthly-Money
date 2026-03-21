import Foundation

public enum RepositoryError: Error, Equatable {
    case invalidCrossScopeReference
}

public protocol AccountDataStore {
    func fetchBudgets() throws -> [Budget]
    func fetchBudget(id: UUID) throws -> Budget?
    func upsertBudget(_ budget: Budget) throws
    func deleteBudget(id: UUID) throws

    func fetchAccounts() throws -> [Account]
    func fetchAccount(id: UUID) throws -> Account?
    func upsertAccount(_ account: Account) throws
    func deleteAccount(id: UUID) throws

    func fetchPlannedItems(accountIDs: Set<UUID>, monthKey: YearMonth?) throws -> [PlannedItem]
    func fetchPlannedItem(id: UUID) throws -> PlannedItem?
    func upsertPlannedItems(_ items: [PlannedItem]) throws
    func deletePlannedItem(id: UUID) throws
    func deletePlannedItems(accountID: UUID) throws

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

public final class InMemoryAccountDataStore: AccountDataStore {
    private var budgetsByID: [UUID: Budget] = [:]
    private var accountsByID: [UUID: Account] = [:]
    private var plannedItemsByID: [UUID: PlannedItem] = [:]
    private var transactionsByID: [UUID: Transaction] = [:]
    private var importedTransactionRecordsByID: [UUID: ImportedTransactionRecord] = [:]
    private var wheelOfMoneyItemsByID: [UUID: WheelOfMoneyItem] = [:]

    public init() {}

    public func fetchBudgets() throws -> [Budget] { Array(budgetsByID.values) }
    public func fetchBudget(id: UUID) throws -> Budget? { budgetsByID[id] }
    public func upsertBudget(_ budget: Budget) throws { budgetsByID[budget.id] = budget }
    public func deleteBudget(id: UUID) throws { budgetsByID[id] = nil }

    public func fetchAccounts() throws -> [Account] { Array(accountsByID.values) }
    public func fetchAccount(id: UUID) throws -> Account? { accountsByID[id] }
    public func upsertAccount(_ account: Account) throws { accountsByID[account.id] = account }
    public func deleteAccount(id: UUID) throws { accountsByID[id] = nil }

    public func fetchPlannedItems(accountIDs: Set<UUID>, monthKey: YearMonth?) throws -> [PlannedItem] {
        Array(plannedItemsByID.values).filter { item in
            accountIDs.contains(item.accountID) && (monthKey == nil || item.monthKey == monthKey?.rawValue)
        }
    }

    public func fetchPlannedItem(id: UUID) throws -> PlannedItem? {
        plannedItemsByID[id]
    }

    public func upsertPlannedItems(_ items: [PlannedItem]) throws {
        for item in items { plannedItemsByID[item.id] = item }
    }

    public func deletePlannedItem(id: UUID) throws {
        plannedItemsByID[id] = nil
    }

    public func deletePlannedItems(accountID: UUID) throws {
        plannedItemsByID = plannedItemsByID.filter { $0.value.accountID != accountID }
    }

    public func fetchTransactions(accountIDs: Set<UUID>) throws -> [Transaction] {
        Array(transactionsByID.values).filter { accountIDs.contains($0.accountID) }
    }

    public func upsertTransactions(_ transactions: [Transaction]) throws {
        for transaction in transactions { transactionsByID[transaction.id] = transaction }
    }

    public func deleteTransactions(accountID: UUID) throws {
        transactionsByID = transactionsByID.filter { $0.value.accountID != accountID }
    }

    public func fetchImportedTransactionRecords(accountIDs: Set<UUID>) throws -> [ImportedTransactionRecord] {
        Array(importedTransactionRecordsByID.values).filter { accountIDs.contains($0.accountID) }
    }

    public func upsertImportedTransactionRecords(_ records: [ImportedTransactionRecord]) throws {
        for record in records { importedTransactionRecordsByID[record.id] = record }
    }

    public func deleteImportedTransactionRecords(accountID: UUID) throws {
        importedTransactionRecordsByID = importedTransactionRecordsByID.filter { $0.value.accountID != accountID }
    }

    public func fetchWheelOfMoneyItems() throws -> [WheelOfMoneyItem] {
        Array(wheelOfMoneyItemsByID.values)
    }

    public func fetchWheelOfMoneyItem(id: UUID) throws -> WheelOfMoneyItem? {
        wheelOfMoneyItemsByID[id]
    }

    public func fetchWheelOfMoneyItems(budgetID: UUID) throws -> [WheelOfMoneyItem] {
        Array(wheelOfMoneyItemsByID.values).filter { $0.budgetID == budgetID }
    }

    public func upsertWheelOfMoneyItems(_ items: [WheelOfMoneyItem]) throws {
        for item in items { wheelOfMoneyItemsByID[item.id] = item }
    }

    public func deleteWheelOfMoneyItem(id: UUID) throws {
        wheelOfMoneyItemsByID[id] = nil
    }

    public func deleteWheelOfMoneyItems(budgetID: UUID) throws {
        wheelOfMoneyItemsByID = wheelOfMoneyItemsByID.filter { $0.value.budgetID != budgetID }
    }
}

public final class AccountRepository {
    private let privateStore: AccountDataStore
    private let sharedStore: AccountDataStore

    public init(privateStore: AccountDataStore, sharedStore: AccountDataStore) {
        self.privateStore = privateStore
        self.sharedStore = sharedStore
    }

    @discardableResult
    public func createBudget(name: String, ownerParticipantID: String, sharingState: BudgetSharingState = .local) throws -> Budget {
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

    public func saveBudget(_ budget: Budget) throws {
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

    public func activeBudget() throws -> Budget? {
        if let privateBudget = try preferredBudget(from: privateStore.fetchBudgets()) {
            return privateBudget
        }
        return try preferredBudget(from: sharedStore.fetchBudgets())
    }

    public func createAccount(name: String, role: AccountRole, type: AccountType, ownerParticipantID: String) throws -> Account {
        let budget = try ensureLocalBudget(ownerParticipantID: ownerParticipantID)
        let account = Account(budgetID: budget.id, name: name, role: role, type: type, ownerParticipantID: ownerParticipantID)
        let store = try storeHoldingBudget(id: budget.id) ?? store(for: budget.sharingState)
        try store.upsertAccount(account)
        try touchBudget(id: budget.id, in: store)
        return account
    }

    public func createPlannedItem(_ item: PlannedItem) throws {
        guard let (store, account) = try storeAndAccount(for: item.accountID) else {
            throw RepositoryError.invalidCrossScopeReference
        }
        item.budgetID = account.budgetID
        try store.upsertPlannedItems([item])
        try touchBudget(id: account.budgetID, in: store)
    }

    public func savePlannedItem(_ item: PlannedItem) throws {
        try createPlannedItem(item)
    }

    public func createTransaction(_ transaction: Transaction) throws {
        guard let (store, account) = try storeAndAccount(for: transaction.accountID) else {
            throw RepositoryError.invalidCrossScopeReference
        }
        transaction.budgetID = account.budgetID
        try store.upsertTransactions([transaction])
        try touchBudget(id: account.budgetID, in: store)
    }

    public func saveTransaction(_ transaction: Transaction) throws {
        try createTransaction(transaction)
    }

    public func createImportedTransactionRecord(_ record: ImportedTransactionRecord) throws {
        guard let (store, account) = try storeAndAccount(for: record.accountID) else {
            throw RepositoryError.invalidCrossScopeReference
        }
        record.budgetID = account.budgetID
        try store.upsertImportedTransactionRecords([record])
        try touchBudget(id: account.budgetID, in: store)
    }

    public func saveImportedTransactionRecord(_ record: ImportedTransactionRecord) throws {
        try createImportedTransactionRecord(record)
    }

    public func createWheelOfMoneyItem(_ item: WheelOfMoneyItem) throws {
        guard let budget = try activeBudget(),
              let store = try storeHoldingBudget(id: budget.id) else {
            throw RepositoryError.invalidCrossScopeReference
        }
        item.budgetID = budget.id
        try store.upsertWheelOfMoneyItems([item])
        try touchBudget(id: budget.id, in: store)
    }

    public func accounts() throws -> [Account] {
        guard let budget = try activeBudget() else { return [] }
        guard let store = try storeHoldingBudget(id: budget.id) else { return [] }
        return try store.fetchAccounts().filter { $0.budgetID == budget.id }
    }

    public func wheelOfMoneyItem(id: UUID) throws -> WheelOfMoneyItem? {
        if let item = try privateStore.fetchWheelOfMoneyItem(id: id) {
            return item
        }
        return try sharedStore.fetchWheelOfMoneyItem(id: id)
    }

    public func transactions(accountIDs: Set<UUID>) throws -> [Transaction] {
        let privateTransactions = try privateStore.fetchTransactions(accountIDs: accountIDs)
        let sharedTransactions = try sharedStore.fetchTransactions(accountIDs: accountIDs)
        return uniqueTransactions(from: privateTransactions + sharedTransactions)
    }

    public func importedTransactionRecords(accountIDs: Set<UUID>) throws -> [ImportedTransactionRecord] {
        let privateRecords = try privateStore.fetchImportedTransactionRecords(accountIDs: accountIDs)
        let sharedRecords = try sharedStore.fetchImportedTransactionRecords(accountIDs: accountIDs)
        return uniqueImportedTransactionRecords(from: privateRecords + sharedRecords)
    }

    public func saveWheelOfMoneyItem(_ item: WheelOfMoneyItem) throws {
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

    public func setWheelOfMoneyItemPaid(id: UUID, isPaid: Bool) throws {
        guard let item = try wheelOfMoneyItem(id: id) else { return }
        item.isPaid = isPaid
        try saveWheelOfMoneyItem(item)
    }

    public func deleteWheelOfMoneyItem(id: UUID) throws {
        if let item = try privateStore.fetchWheelOfMoneyItem(id: id) {
            try privateStore.deleteWheelOfMoneyItem(id: id)
            try touchBudget(id: item.budgetID, in: privateStore)
        }
        if let item = try sharedStore.fetchWheelOfMoneyItem(id: id) {
            try sharedStore.deleteWheelOfMoneyItem(id: id)
            try touchBudget(id: item.budgetID, in: sharedStore)
        }
    }

    public func deletePlannedItem(id: UUID) throws {
        try privateStore.deletePlannedItem(id: id)
        try sharedStore.deletePlannedItem(id: id)
    }

    public func plannedItems(for month: YearMonth? = nil) throws -> [PlannedItem] {
        let accountIDs = Set(try accounts().map(\.id))
        guard !accountIDs.isEmpty, let budget = try activeBudget() else { return [] }
        guard let store = try storeHoldingBudget(id: budget.id) else { return [] }
        return try store
            .fetchPlannedItems(accountIDs: accountIDs, monthKey: month)
            .filter { $0.budgetID == budget.id }
    }

    public func hasPlannedItem(id: UUID) throws -> Bool {
        try privateStore.fetchPlannedItem(id: id) != nil || sharedStore.fetchPlannedItem(id: id) != nil
    }

    public func plannedItem(id: UUID) throws -> PlannedItem? {
        if let privateItem = try privateStore.fetchPlannedItem(id: id) {
            return privateItem
        }
        return try sharedStore.fetchPlannedItem(id: id)
    }

    public func wheelOfMoneyItems() throws -> [WheelOfMoneyItem] {
        guard let budget = try activeBudget(),
              let store = try storeHoldingBudget(id: budget.id) else {
            return []
        }
        return try store.fetchWheelOfMoneyItems(budgetID: budget.id)
            .filter { $0.budgetID == budget.id }
    }

    public func localBudget() throws -> Budget? {
        try preferredBudget(from: privateStore.fetchBudgets())
    }

    @discardableResult
    public func reconcileDuplicateLocalBudgets() throws -> Int {
        let localBudgets = try privateStore.fetchBudgets().sorted(by: Self.budgetSort)
        guard let canonicalBudget = localBudgets.first else { return 0 }

        var removed = 0
        for duplicate in localBudgets.dropFirst() where duplicate.id != canonicalBudget.id {
            try deleteLocalBudget(id: duplicate.id)
            removed += 1
        }
        return removed
    }

    public func sharedBudget() throws -> Budget? {
        try preferredBudget(from: sharedStore.fetchBudgets())
    }

    public func localBudgetSnapshot() throws -> (budget: Budget, accounts: [Account], plannedItems: [PlannedItem], transactions: [Transaction], wheelOfMoneyItems: [WheelOfMoneyItem])? {
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

    public func insertShared(budget: Budget, accounts: [Account], plannedItems: [PlannedItem], transactions: [Transaction], wheelOfMoneyItems: [WheelOfMoneyItem]) throws {
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

    public func deleteLocalBudget(id: UUID) throws {
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

    private static func budgetSort(lhs: Budget, rhs: Budget) -> Bool {
        if lhs.updatedAt != rhs.updatedAt {
            return lhs.updatedAt > rhs.updatedAt
        }
        if lhs.createdAt != rhs.createdAt {
            return lhs.createdAt > rhs.createdAt
        }
        return lhs.id.uuidString > rhs.id.uuidString
    }

    private func touchBudget(id: UUID, in store: AccountDataStore) throws {
        guard let budget = try store.fetchBudget(id: id) else { return }
        budget.updatedAt = Date()
        try store.upsertBudget(budget)
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
