import CoreData
import Foundation

@MainActor
final class CoreDataAccountDataStore: AccountDataStore {
    let implementationKind: DataStoreImplementationKind = .coreData
    private let persistentContainer: NSPersistentContainer
    private var context: NSManagedObjectContext { persistentContainer.viewContext }
    var mergesRemoteChangesAutomatically: Bool { context.automaticallyMergesChangesFromParent }

    init(persistentContainer: NSPersistentContainer) {
        self.persistentContainer = persistentContainer
        self.context.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        self.context.automaticallyMergesChangesFromParent = true
    }

    func awaitInitialCloudImport(timeout: Duration) async throws {
        guard let cloudContainer = persistentContainer as? NSPersistentCloudKitContainer else {
            return
        }

        let center = NotificationCenter.default
        let eventName = NSPersistentCloudKitContainer.eventChangedNotification
        let userInfoKey = NSPersistentCloudKitContainer.eventNotificationUserInfoKey

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await Task.sleep(for: timeout)
            }

            group.addTask {
                for await notification in center.notifications(named: eventName, object: cloudContainer) {
                    guard let event = notification.userInfo?[userInfoKey] as? NSPersistentCloudKitContainer.Event,
                          event.type == .import,
                          event.endDate != nil else {
                        continue
                    }
                    return
                }
            }

            try await group.next()
            group.cancelAll()
        }
    }

    static func makeInMemory() throws -> CoreDataAccountDataStore {
        let model = CoreDataModelBuilder.sharedModel
        let container = NSPersistentContainer(name: "MonthlyMoneyCoreData", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        return CoreDataAccountDataStore(persistentContainer: container)
    }

    static func makePersistentCloudKitPrivate(url: URL, containerIdentifier: String) throws -> CoreDataAccountDataStore {
        let container = NSPersistentCloudKitContainer(
            name: "MonthlyMoneyCoreData",
            managedObjectModel: CoreDataModelBuilder.sharedModel
        )
        let description = CoreDataCloudKitProbe.makeStoreDescription(
            url: url,
            scope: .privateDatabase,
            containerIdentifier: containerIdentifier
        )
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        return CoreDataAccountDataStore(persistentContainer: container)
    }

    static func makePersistentCloudKitShared(url: URL, containerIdentifier: String) throws -> CoreDataAccountDataStore {
        let container = NSPersistentCloudKitContainer(
            name: "MonthlyMoneyCoreData",
            managedObjectModel: CoreDataModelBuilder.sharedModel
        )
        let description = CoreDataCloudKitProbe.makeStoreDescription(
            url: url,
            scope: .sharedDatabase,
            containerIdentifier: containerIdentifier
        )
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        return CoreDataAccountDataStore(persistentContainer: container)
    }

    func fetchBudgets() throws -> [Budget] {
        try fetch(entityName: CoreDataEntityName.budget).map(CoreDataMapping.budget(from:))
    }

    func fetchBudget(id: UUID) throws -> Budget? {
        try fetchFirst(entityName: CoreDataEntityName.budget, id: id).map(CoreDataMapping.budget(from:))
    }

    func managedBudgetObjectID(for id: UUID) throws -> NSManagedObjectID? {
        try fetchFirst(entityName: CoreDataEntityName.budget, id: id)?.objectID
    }

    func upsertBudget(_ budget: Budget) throws {
        let managedObject = try fetchFirst(entityName: CoreDataEntityName.budget, id: budget.id)
            ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.budget, into: context)
        CoreDataMapping.apply(budget, to: managedObject)
        try save()
    }

    func deleteBudget(id: UUID) throws {
        if let budget = try fetchFirst(entityName: CoreDataEntityName.budget, id: id) {
            context.delete(budget)
            try save()
        }
    }

    func fetchAccounts() throws -> [Account] {
        try fetch(entityName: CoreDataEntityName.account).map(CoreDataMapping.account(from:))
    }

    func fetchAccount(id: UUID) throws -> Account? {
        try fetchFirst(entityName: CoreDataEntityName.account, id: id).map(CoreDataMapping.account(from:))
    }

    func upsertAccount(_ account: Account) throws {
        let managedObject = try fetchFirst(entityName: CoreDataEntityName.account, id: account.id)
            ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.account, into: context)
        CoreDataMapping.apply(account, to: managedObject)
        try save()
    }

    func deleteAccount(id: UUID) throws {
        if let account = try fetchFirst(entityName: CoreDataEntityName.account, id: id) {
            context.delete(account)
            try save()
        }
    }

    func fetchPlannedItems() throws -> [PlannedItem] {
        try fetch(entityName: CoreDataEntityName.plannedItem).map(CoreDataMapping.plannedItem(from:))
    }

    func fetchPlannedItem(id: UUID) throws -> PlannedItem? {
        try fetchFirst(entityName: CoreDataEntityName.plannedItem, id: id).map(CoreDataMapping.plannedItem(from:))
    }

    func fetchPlannedItems(accountIDs: Set<UUID>, monthKey: YearMonth?) throws -> [PlannedItem] {
        let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.plannedItem)
        var predicates: [NSPredicate] = [
            NSPredicate(format: "accountID IN %@", Array(accountIDs))
        ]
        if let monthKey {
            predicates.append(NSPredicate(format: "monthKey == %@", monthKey.rawValue))
        }
        request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        return try context.fetch(request).map(CoreDataMapping.plannedItem(from:))
    }

    func upsertPlannedItems(_ items: [PlannedItem]) throws {
        for item in items {
            let managedObject = try fetchFirst(entityName: CoreDataEntityName.plannedItem, id: item.id)
                ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.plannedItem, into: context)
            CoreDataMapping.apply(item, to: managedObject)
        }
        try save()
    }

    func deletePlannedItem(id: UUID) throws {
        if let item = try fetchFirst(entityName: CoreDataEntityName.plannedItem, id: id) {
            context.delete(item)
            try save()
        }
    }

    func deletePlannedItems(accountID: UUID) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.plannedItem)
        request.predicate = NSPredicate(format: "accountID == %@", accountID as CVarArg)
        try context.fetch(request).forEach(context.delete)
        try save()
    }

    func fetchTransactions() throws -> [Transaction] {
        try fetch(entityName: CoreDataEntityName.transaction).map(CoreDataMapping.transaction(from:))
    }

    func fetchTransactions(accountIDs: Set<UUID>) throws -> [Transaction] {
        let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.transaction)
        request.predicate = NSPredicate(format: "accountID IN %@", Array(accountIDs))
        return try context.fetch(request).map(CoreDataMapping.transaction(from:))
    }

    func upsertTransactions(_ transactions: [Transaction]) throws {
        for transaction in transactions {
            let managedObject = try fetchFirst(entityName: CoreDataEntityName.transaction, id: transaction.id)
                ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.transaction, into: context)
            CoreDataMapping.apply(transaction, to: managedObject)
        }
        try save()
    }

    func deleteTransactions(accountID: UUID) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.transaction)
        request.predicate = NSPredicate(format: "accountID == %@", accountID as CVarArg)
        try context.fetch(request).forEach(context.delete)
        try save()
    }

    private func save() throws {
        if context.hasChanges {
            try context.save()
        }
    }

    private func fetch(entityName: String) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        return try context.fetch(request)
    }

    private func fetchFirst(entityName: String, id: UUID) throws -> NSManagedObject? {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.fetchLimit = 1
        request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        return try context.fetch(request).first
    }
}
