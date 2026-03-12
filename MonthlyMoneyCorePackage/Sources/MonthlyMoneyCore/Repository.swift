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
    func upsertPlannedItems(_ items: [PlannedItem]) throws
    func deletePlannedItem(id: UUID) throws
    func deletePlannedItems(accountID: UUID) throws

    func fetchTransactions(accountIDs: Set<UUID>) throws -> [Transaction]
    func upsertTransactions(_ transactions: [Transaction]) throws
    func deleteTransactions(accountID: UUID) throws
}

public final class InMemoryAccountDataStore: AccountDataStore {
    private var budgetsByID: [UUID: Budget] = [:]
    private var accountsByID: [UUID: Account] = [:]
    private var plannedItemsByID: [UUID: PlannedItem] = [:]
    private var transactionsByID: [UUID: Transaction] = [:]

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
        let budget = Budget(name: name, ownerParticipantID: ownerParticipantID, sharingState: sharingState)
        try store(for: sharingState).upsertBudget(budget)
        return budget
    }

    public func saveBudget(_ budget: Budget) throws {
        try store(for: budget.sharingState).upsertBudget(budget)
    }

    public func activeBudget() throws -> Budget? {
        if let local = try privateStore.fetchBudgets().first(where: { $0.sharingState == .local }) {
            return local
        }
        return try sharedStore.fetchBudgets().first(where: { $0.sharingState == .shared })
    }

    public func createAccount(name: String, role: AccountRole, type: AccountType, ownerParticipantID: String) throws -> Account {
        let budget = try ensureLocalBudget(ownerParticipantID: ownerParticipantID)
        let account = Account(budgetID: budget.id, name: name, role: role, type: type, ownerParticipantID: ownerParticipantID)
        try store(for: budget.sharingState).upsertAccount(account)
        return account
    }

    public func createPlannedItem(_ item: PlannedItem) throws {
        guard let (store, account) = try storeAndAccount(for: item.accountID) else {
            throw RepositoryError.invalidCrossScopeReference
        }
        item.budgetID = account.budgetID
        try store.upsertPlannedItems([item])
    }

    public func createTransaction(_ transaction: Transaction) throws {
        guard let (store, account) = try storeAndAccount(for: transaction.accountID) else {
            throw RepositoryError.invalidCrossScopeReference
        }
        transaction.budgetID = account.budgetID
        try store.upsertTransactions([transaction])
    }

    public func accounts() throws -> [Account] {
        guard let budget = try activeBudget() else { return [] }
        return try store(for: budget.sharingState).fetchAccounts().filter { $0.budgetID == budget.id }
    }

    public func deletePlannedItem(id: UUID) throws {
        try privateStore.deletePlannedItem(id: id)
        try sharedStore.deletePlannedItem(id: id)
    }

    public func plannedItems(for month: YearMonth? = nil) throws -> [PlannedItem] {
        let accountIDs = Set(try accounts().map(\.id))
        guard !accountIDs.isEmpty, let budget = try activeBudget() else { return [] }
        return try store(for: budget.sharingState)
            .fetchPlannedItems(accountIDs: accountIDs, monthKey: month)
            .filter { $0.budgetID == budget.id }
    }

    public func localBudget() throws -> Budget? {
        try privateStore.fetchBudgets().first(where: { $0.sharingState == .local })
    }

    public func sharedBudget() throws -> Budget? {
        try sharedStore.fetchBudgets().first(where: { $0.sharingState == .shared })
    }

    public func localBudgetSnapshot() throws -> (budget: Budget, accounts: [Account], plannedItems: [PlannedItem], transactions: [Transaction])? {
        guard let budget = try localBudget() else { return nil }
        let accounts = try privateStore.fetchAccounts().filter { $0.budgetID == budget.id }
        let accountIDs = Set(accounts.map(\.id))
        let plannedItems = try privateStore.fetchPlannedItems(accountIDs: accountIDs, monthKey: nil)
            .filter { $0.budgetID == budget.id }
        let transactions = try privateStore.fetchTransactions(accountIDs: accountIDs)
            .filter { $0.budgetID == budget.id }
        return (budget, accounts, plannedItems, transactions)
    }

    public func insertShared(budget: Budget, accounts: [Account], plannedItems: [PlannedItem], transactions: [Transaction]) throws {
        try sharedStore.upsertBudget(budget)
        for account in accounts {
            try sharedStore.upsertAccount(account)
        }
        try sharedStore.upsertPlannedItems(plannedItems)
        try sharedStore.upsertTransactions(transactions)
    }

    public func deleteLocalBudget(id: UUID) throws {
        let accounts = try privateStore.fetchAccounts().filter { $0.budgetID == id }
        for account in accounts {
            try privateStore.deletePlannedItems(accountID: account.id)
            try privateStore.deleteTransactions(accountID: account.id)
            try privateStore.deleteAccount(id: account.id)
        }
        try privateStore.deleteBudget(id: id)
    }

    private func ensureLocalBudget(ownerParticipantID: String) throws -> Budget {
        if let budget = try activeBudget(), budget.sharingState == .local {
            return budget
        }
        return try createBudget(name: "Budget", ownerParticipantID: ownerParticipantID, sharingState: .local)
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
}
