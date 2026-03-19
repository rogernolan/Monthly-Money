import CloudKit
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

    func prepareShareSession(for budgetID: UUID, containerIdentifier: String) async throws -> BudgetShareSession {
        guard let cloudContainer = persistentContainer as? NSPersistentCloudKitContainer else {
            throw BudgetShareCoordinatorError.sharingUnavailable
        }
        guard let objectID = try managedBudgetObjectID(for: budgetID) else {
            throw BudgetShareCoordinatorError.missingSharedBudgetRoot
        }

        try repairBudgetRelationships(for: budgetID)

        if let existingShare = try existingShare(for: objectID, in: cloudContainer) {
            return BudgetShareSession(
                budgetID: budgetID,
                share: existingShare,
                containerIdentifier: containerIdentifier
            )
        }

        let managedObject = try context.existingObject(with: objectID)
        return try await withCheckedThrowingContinuation { continuation in
            cloudContainer.share([managedObject], to: nil) { _, share, cloudKitContainer, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let share, let cloudKitContainer else {
                    continuation.resume(throwing: BudgetShareCoordinatorError.sharePreparationFailed)
                    return
                }
                continuation.resume(returning: BudgetShareSession(
                    budgetID: budgetID,
                    share: share,
                    containerIdentifier: cloudKitContainer.containerIdentifier ?? containerIdentifier
                ))
            }
        }
    }

    func acceptShareInvitations(_ metadata: [CKShare.Metadata]) async throws {
        guard let cloudContainer = persistentContainer as? NSPersistentCloudKitContainer,
              let persistentStore = persistentContainer.persistentStoreCoordinator.persistentStores.first else {
            throw BudgetShareCoordinatorError.sharingUnavailable
        }
        guard !metadata.isEmpty else { return }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            cloudContainer.acceptShareInvitations(from: metadata, into: persistentStore) { _, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: ())
            }
        }
    }

    func hasActiveShare(for budgetID: UUID) throws -> Bool {
        guard let cloudContainer = persistentContainer as? NSPersistentCloudKitContainer,
              let objectID = try managedBudgetObjectID(for: budgetID) else {
            return false
        }
        return try existingShare(for: objectID, in: cloudContainer) != nil
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
        try attachToBudgetRelationship(managedObject: managedObject, budgetID: account.budgetID)
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
            try attachToBudgetRelationship(managedObject: managedObject, budgetID: item.budgetID)
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
            try attachToBudgetRelationship(managedObject: managedObject, budgetID: transaction.budgetID)
        }
        try save()
    }

    func budgetRelationshipCounts(for budgetID: UUID) throws -> (accounts: Int, plannedItems: Int, transactions: Int) {
        guard let budget = try fetchFirst(entityName: CoreDataEntityName.budget, id: budgetID) else {
            return (0, 0, 0)
        }

        let accounts = (budget.value(forKey: "accounts") as? NSSet)?.count ?? 0
        let plannedItems = (budget.value(forKey: "plannedItems") as? NSSet)?.count ?? 0
        let transactions = (budget.value(forKey: "transactions") as? NSSet)?.count ?? 0
        return (accounts, plannedItems, transactions)
    }

    func repairBudgetRelationships(for budgetID: UUID) throws {
        guard let budget = try fetchFirst(entityName: CoreDataEntityName.budget, id: budgetID) else {
            return
        }

        try fetchObjects(entityName: CoreDataEntityName.account, budgetID: budgetID).forEach {
            $0.setValue(budget, forKey: "budget")
        }
        try fetchObjects(entityName: CoreDataEntityName.plannedItem, budgetID: budgetID).forEach {
            $0.setValue(budget, forKey: "budget")
        }
        try fetchObjects(entityName: CoreDataEntityName.transaction, budgetID: budgetID).forEach {
            $0.setValue(budget, forKey: "budget")
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

    private func fetchObjects(entityName: String, budgetID: UUID) throws -> [NSManagedObject] {
        let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
        request.predicate = NSPredicate(format: "budgetID == %@", budgetID as CVarArg)
        return try context.fetch(request)
    }

    private func attachToBudgetRelationship(managedObject: NSManagedObject, budgetID: UUID) throws {
        guard let budget = try fetchFirst(entityName: CoreDataEntityName.budget, id: budgetID) else {
            return
        }
        managedObject.setValue(budget, forKey: "budget")
    }

    private func existingShare(
        for objectID: NSManagedObjectID,
        in container: NSPersistentCloudKitContainer
    ) throws -> CKShare? {
        let shares = try container.fetchShares(matching: [objectID])
        return shares[objectID]
    }
}
