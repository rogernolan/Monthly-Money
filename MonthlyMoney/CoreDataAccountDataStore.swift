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

    static func makePersistentLocal(url: URL) throws -> CoreDataAccountDataStore {
        try migrateV2StoreIfNeeded(at: url)
        let container = NSPersistentContainer(
            name: "MonthlyMoneyCoreData",
            managedObjectModel: CoreDataModelBuilder.sharedModel
        )
        let description = NSPersistentStoreDescription(url: url)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        description.shouldMigrateStoreAutomatically = false
        description.shouldInferMappingModelAutomatically = false
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
        try migrateV2StoreIfNeeded(at: url)
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
        description.shouldMigrateStoreAutomatically = false
        description.shouldInferMappingModelAutomatically = false
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
        try migrateV2StoreIfNeeded(at: url)
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
        description.shouldMigrateStoreAutomatically = false
        description.shouldInferMappingModelAutomatically = false
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

    private static func migrateV2StoreIfNeeded(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: url,
            options: nil
        )
        guard CoreDataModelBuilder.legacyModel.isConfiguration(
            withName: nil,
            compatibleWithStoreMetadata: metadata
        ) else {
            return
        }

        let migrationDirectory = fileManager.temporaryDirectory
            .appendingPathComponent("MonthlyMoney-v2-migration-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: migrationDirectory, withIntermediateDirectories: true)
        let destinationURL = migrationDirectory.appendingPathComponent("Store.sqlite")
        try copyV2StoreContents(from: url, to: destinationURL)

        for suffix in ["", "-shm", "-wal"] {
            let oldURL = URL(fileURLWithPath: url.path + suffix)
            if fileManager.fileExists(atPath: oldURL.path) {
                try fileManager.removeItem(at: oldURL)
            }
            let migratedURL = URL(fileURLWithPath: destinationURL.path + suffix)
            if fileManager.fileExists(atPath: migratedURL.path) {
                try fileManager.moveItem(at: migratedURL, to: oldURL)
            }
        }
        try? fileManager.removeItem(at: migrationDirectory)
    }

    private static func copyV2StoreContents(from sourceURL: URL, to destinationURL: URL) throws {
        let sourceContainer = NSPersistentContainer(
            name: "MonthlyMoneyCoreData",
            managedObjectModel: CoreDataModelBuilder.legacyModel
        )
        let sourceDescription = NSPersistentStoreDescription(url: sourceURL)
        sourceDescription.type = NSSQLiteStoreType
        sourceDescription.shouldAddStoreAsynchronously = false
        sourceContainer.persistentStoreDescriptions = [sourceDescription]
        try load(sourceContainer)

        let destinationContainer = NSPersistentContainer(
            name: "MonthlyMoneyCoreData",
            managedObjectModel: CoreDataModelBuilder.sharedModel
        )
        let destinationDescription = NSPersistentStoreDescription(url: destinationURL)
        destinationDescription.type = NSSQLiteStoreType
        destinationDescription.shouldAddStoreAsynchronously = false
        destinationContainer.persistentStoreDescriptions = [destinationDescription]
        try load(destinationContainer)

        let sourceContext = sourceContainer.viewContext
        let destinationContext = destinationContainer.viewContext
        let entityNames = [
            CoreDataEntityName.budget,
            CoreDataEntityName.account,
            CoreDataEntityName.plannedItem,
            CoreDataEntityName.transaction,
            CoreDataEntityName.importedTransactionRecord,
            CoreDataEntityName.wheelOfMoneyItem
        ]
        for entityName in entityNames {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            for source in try sourceContext.fetch(request) {
                let destination = NSEntityDescription.insertNewObject(
                    forEntityName: entityName,
                    into: destinationContext
                )
                for (name, _) in source.entity.attributesByName {
                    guard destination.entity.attributesByName[name] != nil else { continue }
                    destination.setValue(source.value(forKey: name), forKey: name)
                }
                if entityName == CoreDataEntityName.plannedItem {
                    let dueDay = (source.value(forKey: "dueDay") as? NSNumber)?.intValue
                    let repeatDays = (source.value(forKey: "repeatDays") as? NSNumber)?.intValue
                    let copiesAutomatically = source.value(forKey: "copiesToNextMonthAutomatically") as? Bool ?? true
                    if dueDay == nil && repeatDays == nil && copiesAutomatically {
                        let seriesKey = CoreDataV2ToV3MigrationPolicy.legacySeriesKey(for: source)
                        destination.setValue(1, forKey: "dueDay")
                        destination.setValue(28, forKey: "repeatDays")
                        destination.setValue(
                            CoreDataV2ToV3MigrationPolicy.stableRecurrenceID(for: seriesKey),
                            forKey: "recurrenceID"
                        )
                        destination.setValue(RepeatMode.periodic.rawValue, forKey: "repeatModeRaw")
                    } else {
                        let mode: RepeatMode = repeatDays != nil
                            ? .periodic
                            : (dueDay != nil && copiesAutomatically ? .calendar : .oneOff)
                        destination.setValue(mode.rawValue, forKey: "repeatModeRaw")
                    }
                }
            }
        }
        try destinationContext.save()
        if let sourceStore = sourceContainer.persistentStoreCoordinator.persistentStores.first {
            try sourceContainer.persistentStoreCoordinator.remove(sourceStore)
        }
        if let destinationStore = destinationContainer.persistentStoreCoordinator.persistentStores.first {
            try destinationContainer.persistentStoreCoordinator.remove(destinationStore)
        }
    }

    private static func load(_ container: NSPersistentContainer) throws {
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
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
            try deletePopulatedMonths(budgetID: id)
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

    func fetchPopulatedMonths(budgetID: UUID) throws -> [PopulatedMonth] {
        try fetchObjects(entityName: CoreDataEntityName.populatedMonth, budgetID: budgetID)
            .map(CoreDataMapping.populatedMonth(from:))
    }

    func upsertPopulatedMonths(_ months: [PopulatedMonth]) throws {
        for month in months {
            let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.populatedMonth)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "budgetID == %@", month.budgetID as CVarArg),
                NSPredicate(format: "monthKey == %@", month.monthKey.rawValue)
            ])
            let managedObject = try context.fetch(request).first
                ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.populatedMonth, into: context)
            CoreDataMapping.apply(month, to: managedObject)
            try attachToBudgetRelationship(managedObject: managedObject, budgetID: month.budgetID)
        }
        try save()
    }

    func deletePopulatedMonths(budgetID: UUID) throws {
        try fetchObjects(entityName: CoreDataEntityName.populatedMonth, budgetID: budgetID).forEach(context.delete)
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

    func fetchImportedTransactionRecords(accountIDs: Set<UUID>) throws -> [ImportedTransactionRecord] {
        let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.importedTransactionRecord)
        request.predicate = NSPredicate(format: "accountID IN %@", Array(accountIDs))
        return try context.fetch(request).map(CoreDataMapping.importedTransactionRecord(from:))
    }

    func upsertImportedTransactionRecords(_ records: [ImportedTransactionRecord]) throws {
        for record in records {
            let managedObject = try fetchFirst(entityName: CoreDataEntityName.importedTransactionRecord, id: record.id)
                ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.importedTransactionRecord, into: context)
            CoreDataMapping.apply(record, to: managedObject)
            try attachToBudgetRelationship(managedObject: managedObject, budgetID: record.budgetID)
        }
        try save()
    }

    func deleteImportedTransactionRecords(accountID: UUID) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.importedTransactionRecord)
        request.predicate = NSPredicate(format: "accountID == %@", accountID as CVarArg)
        try context.fetch(request).forEach(context.delete)
        try save()
    }

    func fetchWheelOfMoneyItems() throws -> [WheelOfMoneyItem] {
        try fetch(entityName: CoreDataEntityName.wheelOfMoneyItem).map(CoreDataMapping.wheelOfMoneyItem(from:))
    }

    func fetchWheelOfMoneyItem(id: UUID) throws -> WheelOfMoneyItem? {
        try fetchFirst(entityName: CoreDataEntityName.wheelOfMoneyItem, id: id).map(CoreDataMapping.wheelOfMoneyItem(from:))
    }

    func fetchWheelOfMoneyItems(budgetID: UUID) throws -> [WheelOfMoneyItem] {
        let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.wheelOfMoneyItem)
        request.predicate = NSPredicate(format: "budgetID == %@", budgetID as CVarArg)
        return try context.fetch(request).map(CoreDataMapping.wheelOfMoneyItem(from:))
    }

    func upsertWheelOfMoneyItems(_ items: [WheelOfMoneyItem]) throws {
        for item in items {
            let managedObject = try fetchFirst(entityName: CoreDataEntityName.wheelOfMoneyItem, id: item.id)
                ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.wheelOfMoneyItem, into: context)
            CoreDataMapping.apply(item, to: managedObject)
            try attachToBudgetRelationship(managedObject: managedObject, budgetID: item.budgetID)
        }
        try save()
    }

    func deleteWheelOfMoneyItem(id: UUID) throws {
        if let item = try fetchFirst(entityName: CoreDataEntityName.wheelOfMoneyItem, id: id) {
            context.delete(item)
            try save()
        }
    }

    func deleteWheelOfMoneyItems(budgetID: UUID) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.wheelOfMoneyItem)
        request.predicate = NSPredicate(format: "budgetID == %@", budgetID as CVarArg)
        try context.fetch(request).forEach(context.delete)
        try save()
    }

    func budgetRelationshipCounts(for budgetID: UUID) throws -> (accounts: Int, plannedItems: Int, transactions: Int, importedTransactionRecords: Int, wheelOfMoneyItems: Int) {
        guard let budget = try fetchFirst(entityName: CoreDataEntityName.budget, id: budgetID) else {
            return (0, 0, 0, 0, 0)
        }

        let accounts = (budget.value(forKey: "accounts") as? NSSet)?.count ?? 0
        let plannedItems = (budget.value(forKey: "plannedItems") as? NSSet)?.count ?? 0
        let transactions = (budget.value(forKey: "transactions") as? NSSet)?.count ?? 0
        let importedTransactionRecords = (budget.value(forKey: "importedTransactionRecords") as? NSSet)?.count ?? 0
        let wheelOfMoneyItems = (budget.value(forKey: "wheelOfMoneyItems") as? NSSet)?.count ?? 0
        return (accounts, plannedItems, transactions, importedTransactionRecords, wheelOfMoneyItems)
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
        try fetchObjects(entityName: CoreDataEntityName.importedTransactionRecord, budgetID: budgetID).forEach {
            $0.setValue(budget, forKey: "budget")
        }
        try fetchObjects(entityName: CoreDataEntityName.wheelOfMoneyItem, budgetID: budgetID).forEach {
            $0.setValue(budget, forKey: "budget")
        }
        try fetchObjects(entityName: CoreDataEntityName.populatedMonth, budgetID: budgetID).forEach {
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

    func deleteTransaction(id: UUID) throws {
        if let transaction = try fetchFirst(entityName: CoreDataEntityName.transaction, id: id) {
            context.delete(transaction)
            try save()
        }
    }

    func deleteImportedTransactionRecord(id: UUID) throws {
        if let record = try fetchFirst(entityName: CoreDataEntityName.importedTransactionRecord, id: id) {
            context.delete(record)
            try save()
        }
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
