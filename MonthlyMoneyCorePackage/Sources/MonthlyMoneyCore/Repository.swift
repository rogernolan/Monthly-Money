import Foundation

public enum ViewScope {
    case myView
    case sharedView
}

public enum RepositoryError: Error, Equatable {
    case invalidCrossScopeReference
}

public protocol AccountDataStore {
    var scope: StorageScope { get }

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
    public let scope: StorageScope

    private var accountsByID: [UUID: Account] = [:]
    private var plannedItemsByID: [UUID: PlannedItem] = [:]
    private var transactionsByID: [UUID: Transaction] = [:]

    public init(scope: StorageScope) {
        self.scope = scope
    }

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

    public func createAccount(name: String, role: AccountRole, type: AccountType, ownerParticipantID: String) throws -> Account {
        let account = Account(name: name, role: role, type: type, ownerParticipantID: ownerParticipantID)
        try privateStore.upsertAccount(account)
        return account
    }

    public func createPlannedItem(_ item: PlannedItem, in scope: StorageScope) throws {
        let store = scope == .privateScope ? privateStore : sharedStore
        guard try store.fetchAccount(id: item.accountID) != nil else {
            throw RepositoryError.invalidCrossScopeReference
        }
        try store.upsertPlannedItems([item])
    }

    public func deletePlannedItem(id: UUID) throws {
        try privateStore.deletePlannedItem(id: id)
        try sharedStore.deletePlannedItem(id: id)
    }

    public func accounts(for scope: ViewScope) throws -> [Account] {
        switch scope {
        case .myView:
            return try privateStore.fetchAccounts() + sharedStore.fetchAccounts()
        case .sharedView:
            return try sharedStore.fetchAccounts()
        }
    }

    public func accountIDs(for scope: ViewScope) throws -> Set<UUID> {
        Set(try accounts(for: scope).map(\.id))
    }

    public func plannedItems(for month: YearMonth? = nil, scope: ViewScope) throws -> [PlannedItem] {
        let ids = try accountIDs(for: scope)
        guard !ids.isEmpty else { return [] }
        switch scope {
        case .myView:
            return try privateStore.fetchPlannedItems(accountIDs: ids, monthKey: month)
                + sharedStore.fetchPlannedItems(accountIDs: ids, monthKey: month)
        case .sharedView:
            return try sharedStore.fetchPlannedItems(accountIDs: ids, monthKey: month)
        }
    }

    public func privateAccount(id: UUID) throws -> Account? { try privateStore.fetchAccount(id: id) }
    public func sharedAccount(id: UUID) throws -> Account? { try sharedStore.fetchAccount(id: id) }

    public func privateDependents(accountID: UUID) throws -> (plannedItems: [PlannedItem], transactions: [Transaction]) {
        let ids: Set<UUID> = [accountID]
        return (
            try privateStore.fetchPlannedItems(accountIDs: ids, monthKey: nil),
            try privateStore.fetchTransactions(accountIDs: ids)
        )
    }

    public func insertShared(account: Account, plannedItems: [PlannedItem], transactions: [Transaction]) throws {
        try sharedStore.upsertAccount(account)
        try sharedStore.upsertPlannedItems(plannedItems)
        try sharedStore.upsertTransactions(transactions)
    }

    public func deletePrivate(accountID: UUID) throws {
        try privateStore.deletePlannedItems(accountID: accountID)
        try privateStore.deleteTransactions(accountID: accountID)
        try privateStore.deleteAccount(id: accountID)
    }
}
