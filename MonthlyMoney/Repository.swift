import Foundation
import SwiftData

enum ViewScope {
    case myView
    case sharedView
}

enum RepositoryError: Error, Equatable {
    case accountNotFound
    case invalidCrossScopeReference
}

protocol AccountDataStore {
    var scope: StorageScope { get }

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

final class InMemoryAccountDataStore: AccountDataStore {
    let scope: StorageScope

    private var accountsByID: [UUID: Account] = [:]
    private var plannedItemsByID: [UUID: PlannedItem] = [:]
    private var transactionsByID: [UUID: Transaction] = [:]

    init(scope: StorageScope) {
        self.scope = scope
    }

    func fetchAccounts() throws -> [Account] {
        Array(accountsByID.values).map(cloneAccount)
    }

    func fetchAccount(id: UUID) throws -> Account? {
        accountsByID[id].map(cloneAccount)
    }

    func upsertAccount(_ account: Account) throws {
        accountsByID[account.id] = cloneAccount(account)
    }

    func deleteAccount(id: UUID) throws {
        accountsByID[id] = nil
    }

    func fetchPlannedItems() throws -> [PlannedItem] {
        Array(plannedItemsByID.values).map(clonePlannedItem)
    }

    func fetchPlannedItem(id: UUID) throws -> PlannedItem? {
        plannedItemsByID[id].map(clonePlannedItem)
    }

    func fetchPlannedItems(accountIDs: Set<UUID>, monthKey: YearMonth?) throws -> [PlannedItem] {
        Array(plannedItemsByID.values).filter { item in
            accountIDs.contains(item.accountID) && (monthKey == nil || item.monthKey == monthKey?.rawValue)
        }.map(clonePlannedItem)
    }

    func upsertPlannedItems(_ items: [PlannedItem]) throws {
        for item in items {
            plannedItemsByID[item.id] = clonePlannedItem(item)
        }
    }

    func deletePlannedItem(id: UUID) throws {
        plannedItemsByID[id] = nil
    }

    func deletePlannedItems(accountID: UUID) throws {
        plannedItemsByID = plannedItemsByID.filter { $0.value.accountID != accountID }
    }

    func fetchTransactions() throws -> [Transaction] {
        Array(transactionsByID.values).map(cloneTransaction)
    }

    func fetchTransactions(accountIDs: Set<UUID>) throws -> [Transaction] {
        Array(transactionsByID.values).filter { accountIDs.contains($0.accountID) }.map(cloneTransaction)
    }

    func upsertTransactions(_ transactions: [Transaction]) throws {
        for transaction in transactions {
            transactionsByID[transaction.id] = cloneTransaction(transaction)
        }
    }

    func deleteTransactions(accountID: UUID) throws {
        transactionsByID = transactionsByID.filter { $0.value.accountID != accountID }
    }

    private func cloneAccount(_ account: Account) -> Account {
        Account(
            id: account.id,
            name: account.name,
            role: account.role,
            type: account.type,
            ownerParticipantID: account.ownerParticipantID,
            accessMode: account.accessMode,
            sharedWithParticipantIDs: account.sharedWithParticipantIDs,
            storageScope: account.storageScope
        )
    }

    private func clonePlannedItem(_ item: PlannedItem) -> PlannedItem {
        guard let monthKey = YearMonth(rawValue: item.monthKey) else {
            preconditionFailure("Invalid monthKey in in-memory store: \(item.monthKey)")
        }
        return PlannedItem(
            id: item.id,
            accountID: item.accountID,
            monthKey: monthKey,
            type: item.type,
            label: item.label,
            amount: item.amount,
            dueDay: item.dueDay,
            dueText: item.dueText,
            isPaid: item.isPaid,
            notes: item.notes
        )
    }

    private func cloneTransaction(_ transaction: Transaction) -> Transaction {
        guard let monthKey = YearMonth(rawValue: transaction.monthKey) else {
            preconditionFailure("Invalid monthKey in in-memory store: \(transaction.monthKey)")
        }
        return Transaction(
            id: transaction.id,
            accountID: transaction.accountID,
            monthKey: monthKey,
            amount: transaction.amount,
            note: transaction.note
        )
    }
}

final class SwiftDataAccountDataStore: AccountDataStore {
    let scope: StorageScope
    private let modelContainer: ModelContainer
    private let modelContext: ModelContext

    init(scope: StorageScope, modelContainer: ModelContainer) {
        self.scope = scope
        self.modelContainer = modelContainer
        self.modelContext = ModelContext(modelContainer)
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

    init(privateStore: AccountDataStore, sharedStore: AccountDataStore) {
        self.privateStore = privateStore
        self.sharedStore = sharedStore
    }

    func createAccount(name: String, role: AccountRole, type: AccountType, ownerParticipantID: String) throws -> Account {
        let account = Account(name: name, role: role, type: type, ownerParticipantID: ownerParticipantID)
        try privateStore.upsertAccount(account)
        return account
    }

    func createPlannedItem(_ item: PlannedItem, in scope: StorageScope) throws {
        let store = store(for: scope)
        guard try store.fetchAccount(id: item.accountID) != nil else {
            throw RepositoryError.invalidCrossScopeReference
        }
        try store.upsertPlannedItems([item])
    }

    func plannedItem(id: UUID) throws -> PlannedItem? {
        if let privateItem = try privateStore.fetchPlannedItem(id: id) {
            return privateItem
        }
        return try sharedStore.fetchPlannedItem(id: id)
    }

    func savePlannedItem(_ item: PlannedItem) throws {
        if try privateStore.fetchAccount(id: item.accountID) != nil {
            try privateStore.upsertPlannedItems([item])
            try sharedStore.deletePlannedItem(id: item.id)
            return
        }
        if try sharedStore.fetchAccount(id: item.accountID) != nil {
            try sharedStore.upsertPlannedItems([item])
            try privateStore.deletePlannedItem(id: item.id)
            return
        }
        throw RepositoryError.invalidCrossScopeReference
    }

    func deletePlannedItem(id: UUID) throws {
        try privateStore.deletePlannedItem(id: id)
        try sharedStore.deletePlannedItem(id: id)
    }

    func createTransaction(_ transaction: Transaction, in scope: StorageScope) throws {
        let store = store(for: scope)
        guard try store.fetchAccount(id: transaction.accountID) != nil else {
            throw RepositoryError.invalidCrossScopeReference
        }
        try store.upsertTransactions([transaction])
    }

    func accounts(for scope: ViewScope) throws -> [Account] {
        switch scope {
        case .myView:
            return deduplicatedAccounts(try privateStore.fetchAccounts() + sharedStore.fetchAccounts())
        case .sharedView:
            return try sharedStore.fetchAccounts()
        }
    }

    func accountIDs(for scope: ViewScope) throws -> Set<UUID> {
        switch scope {
        case .myView:
            let privateIDs = try privateStore.fetchAccounts().map(\.id)
            let sharedIDs = try sharedStore.fetchAccounts().map(\.id)
            return Set(privateIDs).union(sharedIDs)
        case .sharedView:
            return Set(try sharedStore.fetchAccounts().map(\.id))
        }
    }

    func plannedItems(for month: YearMonth? = nil, scope: ViewScope) throws -> [PlannedItem] {
        let accountIDs = Set(try accounts(for: scope).map(\ .id))
        guard !accountIDs.isEmpty else { return [] }

        switch scope {
        case .myView:
            return deduplicatedPlannedItems(
                try privateStore.fetchPlannedItems(accountIDs: accountIDs, monthKey: month)
                + sharedStore.fetchPlannedItems(accountIDs: accountIDs, monthKey: month)
            )
        case .sharedView:
            return try sharedStore.fetchPlannedItems(accountIDs: accountIDs, monthKey: month)
        }
    }

    func transactions(scope: ViewScope) throws -> [Transaction] {
        let accountIDs = Set(try accounts(for: scope).map(\ .id))
        guard !accountIDs.isEmpty else { return [] }

        switch scope {
        case .myView:
            return deduplicatedTransactions(
                try privateStore.fetchTransactions(accountIDs: accountIDs)
                + sharedStore.fetchTransactions(accountIDs: accountIDs)
            )
        case .sharedView:
            return try sharedStore.fetchTransactions(accountIDs: accountIDs)
        }
    }

    func privateAccount(id: UUID) throws -> Account? {
        try privateStore.fetchAccount(id: id)
    }

    func sharedAccount(id: UUID) throws -> Account? {
        try sharedStore.fetchAccount(id: id)
    }

    func privateDependents(accountID: UUID) throws -> (plannedItems: [PlannedItem], transactions: [Transaction]) {
        let accountIDs: Set<UUID> = [accountID]
        return (
            try privateStore.fetchPlannedItems(accountIDs: accountIDs, monthKey: nil),
            try privateStore.fetchTransactions(accountIDs: accountIDs)
        )
    }

    func insertShared(account: Account, plannedItems: [PlannedItem], transactions: [Transaction]) throws {
        try sharedStore.upsertAccount(account)
        try sharedStore.upsertPlannedItems(plannedItems)
        try sharedStore.upsertTransactions(transactions)
    }

    func deletePrivate(accountID: UUID) throws {
        try privateStore.deletePlannedItems(accountID: accountID)
        try privateStore.deleteTransactions(accountID: accountID)
        try privateStore.deleteAccount(id: accountID)
    }

    private func store(for scope: StorageScope) -> AccountDataStore {
        switch scope {
        case .privateScope:
            return privateStore
        case .sharedScope:
            return sharedStore
        }
    }

    private func deduplicatedAccounts(_ values: [Account]) -> [Account] {
        var seen: Set<UUID> = []
        var result: [Account] = []
        result.reserveCapacity(values.count)
        for value in values where !seen.contains(value.id) {
            seen.insert(value.id)
            result.append(value)
        }
        return result
    }

    private func deduplicatedPlannedItems(_ values: [PlannedItem]) -> [PlannedItem] {
        var seen: Set<UUID> = []
        var result: [PlannedItem] = []
        result.reserveCapacity(values.count)
        for value in values where !seen.contains(value.id) {
            seen.insert(value.id)
            result.append(value)
        }
        return result
    }

    private func deduplicatedTransactions(_ values: [Transaction]) -> [Transaction] {
        var seen: Set<UUID> = []
        var result: [Transaction] = []
        result.reserveCapacity(values.count)
        for value in values where !seen.contains(value.id) {
            seen.insert(value.id)
            result.append(value)
        }
        return result
    }
}
