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
        let model = CoreDataModelBuilder.v7Model
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

    private static func migrateV5StoreIfNeeded(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: url, options: nil
        )
        guard CoreDataModelBuilder.sharedModel.isConfiguration(
            withName: nil, compatibleWithStoreMetadata: metadata
        ) else { return }

        let migrationDirectory = url.deletingLastPathComponent()
            .appendingPathComponent(".MonthlyMoney-v5-migration-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: migrationDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: migrationDirectory) }
        let destinationURL = migrationDirectory.appendingPathComponent("Store.sqlite")
        let manager = NSMigrationManager(
            sourceModel: CoreDataModelBuilder.sharedModel,
            destinationModel: CoreDataModelBuilder.v6Model
        )
        let mapping = try NSMappingModel.inferredMappingModel(
            forSourceModel: CoreDataModelBuilder.sharedModel,
            destinationModel: CoreDataModelBuilder.v6Model
        )
        try manager.migrateStore(
            from: url,
            sourceType: NSSQLiteStoreType,
            options: nil,
            with: mapping,
            toDestinationURL: destinationURL,
            destinationType: NSSQLiteStoreType,
            destinationOptions: nil
        )

        let container = NSPersistentContainer(
            name: "MonthlyMoneyCoreData", managedObjectModel: CoreDataModelBuilder.v6Model
        )
        let description = NSPersistentStoreDescription(url: destinationURL)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        try load(container)
        try backfillPeriodicRepeats(in: container.viewContext)
        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try container.persistentStoreCoordinator.remove(store)
        }

        try replaceMigratedStore(from: destinationURL, at: url)
    }

    private static func migrateV6StoreIfNeeded(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }
        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: url, options: nil
        )
        guard CoreDataModelBuilder.v6Model.isConfiguration(
            withName: nil, compatibleWithStoreMetadata: metadata
        ) else { return }

        let migrationDirectory = url.deletingLastPathComponent()
            .appendingPathComponent(".MonthlyMoney-v6-migration-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: migrationDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: migrationDirectory) }
        let destinationURL = migrationDirectory.appendingPathComponent("Store.sqlite")
        let manager = NSMigrationManager(
            sourceModel: CoreDataModelBuilder.v6Model,
            destinationModel: CoreDataModelBuilder.v7Model
        )
        let mapping = try NSMappingModel.inferredMappingModel(
            forSourceModel: CoreDataModelBuilder.v6Model,
            destinationModel: CoreDataModelBuilder.v7Model
        )
        try manager.migrateStore(
            from: url, sourceType: NSSQLiteStoreType, options: nil,
            with: mapping, toDestinationURL: destinationURL,
            destinationType: NSSQLiteStoreType, destinationOptions: nil
        )
        try replaceMigratedStore(
            from: destinationURL, at: url, managedObjectModel: CoreDataModelBuilder.v7Model
        )
    }

    static func replaceMigratedStore(
        from migratedURL: URL,
        at storeURL: URL,
        managedObjectModel: NSManagedObjectModel = CoreDataModelBuilder.v6Model
    ) throws {
        let fileManager = FileManager.default
        let backupDirectory = storeURL.deletingLastPathComponent()
            .appendingPathComponent(".MonthlyMoney-store-backup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let backupURL = backupDirectory.appendingPathComponent(storeURL.lastPathComponent)
        let suffixes = ["", "-shm", "-wal"]

        do {
            for suffix in suffixes {
                let currentURL = URL(fileURLWithPath: storeURL.path + suffix)
                guard fileManager.fileExists(atPath: currentURL.path) else { continue }
                let copyURL = URL(fileURLWithPath: backupURL.path + suffix)
                try fileManager.copyItem(at: currentURL, to: copyURL)
            }
        } catch {
            try? fileManager.removeItem(at: backupDirectory)
            throw error
        }

        let coordinator = NSPersistentStoreCoordinator(managedObjectModel: managedObjectModel)
        do {
            try coordinator.replacePersistentStore(
                at: storeURL,
                destinationOptions: nil,
                withPersistentStoreFrom: migratedURL,
                sourceOptions: nil,
                type: .sqlite
            )
        } catch {
            do {
                let backupStoreExists = fileManager.fileExists(atPath: backupURL.path)
                guard backupStoreExists else { throw error }
                if fileManager.fileExists(atPath: storeURL.path) {
                    try coordinator.replacePersistentStore(
                        at: storeURL,
                        destinationOptions: nil,
                        withPersistentStoreFrom: backupURL,
                        sourceOptions: nil,
                        type: .sqlite
                    )
                } else {
                    try fileManager.copyItem(at: backupURL, to: storeURL)
                }
                for suffix in suffixes.dropFirst() {
                    let liveSidecarURL = URL(fileURLWithPath: storeURL.path + suffix)
                    let savedSidecarURL = URL(fileURLWithPath: backupURL.path + suffix)
                    if fileManager.fileExists(atPath: liveSidecarURL.path) {
                        try fileManager.removeItem(at: liveSidecarURL)
                    }
                    if fileManager.fileExists(atPath: savedSidecarURL.path) {
                        try fileManager.copyItem(at: savedSidecarURL, to: liveSidecarURL)
                    }
                }
            } catch let recoveryError {
                throw NSError(
                    domain: "MonthlyMoney.StoreMigration",
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Store replacement failed (\(error.localizedDescription)); recovery also failed (\(recoveryError.localizedDescription)). Original backup retained at \(backupDirectory.path)."]
                )
            }
            try? fileManager.removeItem(at: backupDirectory)
            throw error
        }

        try? fileManager.removeItem(at: backupDirectory)
    }

    private struct LegacyRepeatKey: Hashable {
        let budgetID: UUID
        let accountID: UUID
        let recurrenceID: UUID
    }

    func backfillLegacyPeriodicRepeatsIfNeeded() throws {
        try Self.backfillPeriodicRepeats(in: context)
    }

    private static func backfillPeriodicRepeats(in context: NSManagedObjectContext) throws {
        let budgetRequest = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.budget)
        let budgets = try context.fetch(budgetRequest)
        let budgetsByID = Dictionary(uniqueKeysWithValues: budgets.compactMap { budget in
            (budget.value(forKey: "id") as? UUID).map { ($0, budget) }
        })
        let itemRequest = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.plannedItem)
        let items = try context.fetch(itemRequest)
        let repeatRequest = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.periodicRepeat)
        var repeatsByID: [UUID: NSManagedObject] = [:]
        for repeatObject in try context.fetch(repeatRequest) {
            if let id = repeatObject.value(forKey: "id") as? UUID {
                repeatsByID[id] = repeatObject
            }
        }
        let revisionRequest = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.periodicRepeatRevision)
        var revisionsByRepeatID: [UUID: [PeriodicRepeatRevision]] = [:]
        for revisionObject in try context.fetch(revisionRequest) {
            if let revision = CoreDataMapping.periodicRepeatRevision(from: revisionObject) {
                revisionsByRepeatID[revision.repeatID, default: []].append(revision)
            }
        }
        let occurrenceRequest = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.periodicOccurrence)
        var plannedIDsWithOccurrence = Set(try context.fetch(occurrenceRequest).compactMap {
            $0.value(forKey: "plannedItemID") as? UUID
        })
        var groups: [LegacyRepeatKey: [(NSManagedObject, PlannedItem, CivilDate)]] = [:]

        for managedItem in items {
            let item = CoreDataMapping.plannedItem(from: managedItem)
            guard item.repeatMode == .periodic,
                  let days = item.repeatDays, days > 0,
                  let recurrenceID = item.recurrenceID,
                  let budget = budgetsByID[item.budgetID],
                  let date = legacyConcreteDate(for: item, paydayDay: Int(budget.value(forKey: "dailyBudgetPaydayDay") as? Int16 ?? 1)) else {
                continue
            }
            let key = LegacyRepeatKey(budgetID: item.budgetID, accountID: item.accountID, recurrenceID: recurrenceID)
            groups[key, default: []].append((managedItem, item, date))
        }

        for (key, rows) in groups {
            let ordered = rows.sorted {
                if $0.2 != $1.2 { return $0.2 < $1.2 }
                return $0.1.id.uuidString < $1.1.id.uuidString
            }
            guard let latest = ordered.last, let interval = latest.1.repeatDays,
                  let budget = budgetsByID[key.budgetID] else { continue }
            let repeatObject: NSManagedObject
            if let existing = repeatsByID[key.recurrenceID] {
                repeatObject = existing
            } else {
                repeatObject = NSEntityDescription.insertNewObject(
                    forEntityName: CoreDataEntityName.periodicRepeat, into: context
                )
                repeatObject.setValue(key.recurrenceID, forKey: "id")
                repeatObject.setValue(key.budgetID, forKey: "budgetID")
                repeatObject.setValue(key.accountID, forKey: "accountID")
                repeatObject.setValue(budget, forKey: "budget")
                repeatsByID[key.recurrenceID] = repeatObject
            }

            let repeatID = repeatObject.value(forKey: "id") as! UUID
            if revisionsByRepeatID[repeatID, default: []].isEmpty {
                let revision = NSEntityDescription.insertNewObject(
                    forEntityName: CoreDataEntityName.periodicRepeatRevision, into: context
                )
                revision.setValue(UUID(), forKey: "id")
                revision.setValue(repeatID, forKey: "repeatID")
                revision.setValue(latest.2.rawValue, forKey: "effectiveDateRaw")
                revision.setValue(latest.2.rawValue, forKey: "anchorDateRaw")
                revision.setValue(Int32(interval), forKey: "repeatDays")
                revision.setValue(latest.1.type.rawValue, forKey: "typeRaw")
                revision.setValue(latest.1.label, forKey: "label")
                revision.setValue(latest.1.matchingString, forKey: "matchingString")
                revision.setValue(latest.1.amount as NSDecimalNumber, forKey: "amount")
                revision.setValue(latest.1.notes, forKey: "notes")
                revision.setValue(repeatObject, forKey: "repeat")
                if let value = CoreDataMapping.periodicRepeatRevision(from: revision) {
                    revisionsByRepeatID[repeatID, default: []].append(value)
                }
            }

            for (managedItem, item, date) in ordered {
                guard plannedIDsWithOccurrence.insert(item.id).inserted else { continue }
                let activeRevision = revisionsByRepeatID[repeatID]?
                    .filter { $0.effectiveDate <= date }
                    .max { $0.effectiveDate < $1.effectiveDate }
                let isOverride = activeRevision.map { definition in
                    item.type != definition.type || item.label != definition.label
                        || item.matchingString != definition.matchingString || item.amount != definition.amount
                        || item.repeatDays != definition.repeatDays || item.notes != definition.notes
                } ?? true
                let occurrence = NSEntityDescription.insertNewObject(
                    forEntityName: CoreDataEntityName.periodicOccurrence, into: context
                )
                occurrence.setValue(item.id, forKey: "plannedItemID")
                occurrence.setValue(item.budgetID, forKey: "budgetID")
                occurrence.setValue(repeatID, forKey: "repeatID")
                occurrence.setValue(date.rawValue, forKey: "scheduledDateRaw")
                occurrence.setValue(date.rawValue, forKey: "dueDateRaw")
                occurrence.setValue(isOverride, forKey: "isOverride")
                occurrence.setValue(repeatObject, forKey: "repeat")
                _ = managedItem
            }
        }
        if context.hasChanges { try context.save() }
    }

    private static func legacyConcreteDate(for item: PlannedItem, paydayDay: Int) -> CivilDate? {
        guard let month = item.resolvedMonthKey, let dueDay = item.dueDay,
              (1...31).contains(dueDay) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let monthStart = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1))!
        let clippedPayday = min(max(paydayDay, 1), calendar.range(of: .day, in: .month, for: monthStart)!.count)
        let dueMonth: YearMonth
        if paydayDay <= 1 || dueDay < clippedPayday {
            dueMonth = month
        } else {
            dueMonth = month.month == 1 ? YearMonth(year: month.year - 1, month: 12) : YearMonth(year: month.year, month: month.month - 1)
        }
        let firstDay = calendar.date(from: DateComponents(year: dueMonth.year, month: dueMonth.month, day: 1))!
        let day = min(dueDay, calendar.range(of: .day, in: .month, for: firstDay)!.count)
        return CivilDate(year: dueMonth.year, month: dueMonth.month, day: day)
    }

    static func makePersistentLocal(url: URL) throws -> CoreDataAccountDataStore {
        try migrateV2StoreIfNeeded(at: url)
        try migrateV3StoreIfNeeded(at: url)
        try migrateV4StoreIfNeeded(at: url)
        try migrateV5StoreIfNeeded(at: url)
        try migrateV6StoreIfNeeded(at: url)
        let container = NSPersistentContainer(
            name: "MonthlyMoneyCoreData",
            managedObjectModel: CoreDataModelBuilder.v7Model
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
        try migrateV3StoreIfNeeded(at: url)
        try migrateV4StoreIfNeeded(at: url)
        try migrateV5StoreIfNeeded(at: url)
        try migrateV6StoreIfNeeded(at: url)
        let container = NSPersistentCloudKitContainer(
            name: "MonthlyMoneyCoreData",
            managedObjectModel: CoreDataModelBuilder.v7Model
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
        try migrateV3StoreIfNeeded(at: url)
        try migrateV4StoreIfNeeded(at: url)
        try migrateV5StoreIfNeeded(at: url)
        try migrateV6StoreIfNeeded(at: url)
        let container = NSPersistentCloudKitContainer(
            name: "MonthlyMoneyCoreData",
            managedObjectModel: CoreDataModelBuilder.v7Model
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

        let migrationDirectory = url.deletingLastPathComponent()
            .appendingPathComponent(".MonthlyMoney-v2-migration-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: migrationDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: migrationDirectory) }
        let destinationURL = migrationDirectory.appendingPathComponent("Store.sqlite")
        try copyV2StoreContents(from: url, to: destinationURL)

        try replaceMigratedStore(from: destinationURL, at: url)
    }

    private static func migrateV3StoreIfNeeded(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: url,
            options: nil
        )
        guard CoreDataModelBuilder.v3Model.isConfiguration(
            withName: nil,
            compatibleWithStoreMetadata: metadata
        ) else {
            return
        }

        let migrationDirectory = url.deletingLastPathComponent()
            .appendingPathComponent(".MonthlyMoney-v3-migration-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: migrationDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: migrationDirectory) }
        let destinationURL = migrationDirectory.appendingPathComponent("Store.sqlite")
        let manager = NSMigrationManager(
            sourceModel: CoreDataModelBuilder.v3Model,
            destinationModel: CoreDataModelBuilder.sharedModel
        )
        let mapping = try NSMappingModel.inferredMappingModel(
            forSourceModel: CoreDataModelBuilder.v3Model,
            destinationModel: CoreDataModelBuilder.sharedModel
        )
        try manager.migrateStore(
            from: url,
            sourceType: NSSQLiteStoreType,
            options: nil,
            with: mapping,
            toDestinationURL: destinationURL,
            destinationType: NSSQLiteStoreType,
            destinationOptions: nil
        )

        try replaceMigratedStore(from: destinationURL, at: url)
    }

    private static func migrateV4StoreIfNeeded(at url: URL) throws {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else { return }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: url,
            options: nil
        )
        guard CoreDataModelBuilder.v4Model.isConfiguration(
            withName: nil,
            compatibleWithStoreMetadata: metadata
        ) else {
            return
        }

        let migrationDirectory = url.deletingLastPathComponent()
            .appendingPathComponent(".MonthlyMoney-v4-migration-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: migrationDirectory, withIntermediateDirectories: true)
        defer { try? fileManager.removeItem(at: migrationDirectory) }
        let destinationURL = migrationDirectory.appendingPathComponent("Store.sqlite")
        try autoreleasepool {
            let manager = NSMigrationManager(
                sourceModel: CoreDataModelBuilder.v4Model,
                destinationModel: CoreDataModelBuilder.sharedModel
            )
            let mapping = try NSMappingModel.inferredMappingModel(
                forSourceModel: CoreDataModelBuilder.v4Model,
                destinationModel: CoreDataModelBuilder.sharedModel
            )
            try manager.migrateStore(
                from: url,
                sourceType: NSSQLiteStoreType,
                options: nil,
                with: mapping,
                toDestinationURL: destinationURL,
                destinationType: NSSQLiteStoreType,
                destinationOptions: nil
            )
        }

        try replaceMigratedStore(from: destinationURL, at: url)
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
                    let mode: RepeatMode = (repeatDays ?? 0) > 0
                        ? .periodic
                        : (dueDay != nil && copiesAutomatically ? .calendar : .oneOff)
                    destination.setValue(mode.rawValue, forKey: "repeatModeRaw")
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
            try deletePeriodicRepeats(budgetID: id)
            let occurrenceRequest = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.periodicOccurrence)
            occurrenceRequest.predicate = NSPredicate(format: "budgetID == %@", id as CVarArg)
            try context.fetch(occurrenceRequest).forEach(context.delete)
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
            try deletePeriodicRepeats(accountID: id)
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
            try deletePeriodicOccurrences(plannedItemIDs: [id])
            context.delete(item)
            try save()
        }
    }

    func deletePlannedItems(accountID: UUID) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.plannedItem)
        request.predicate = NSPredicate(format: "accountID == %@", accountID as CVarArg)
        let items = try context.fetch(request)
        let ids = Set(items.compactMap { $0.value(forKey: "id") as? UUID })
        try deletePeriodicOccurrences(plannedItemIDs: ids)
        items.forEach(context.delete)
        try save()
    }

    func fetchPeriodicRepeats(budgetID: UUID) throws -> [PeriodicRepeat] {
        try fetchObjects(entityName: CoreDataEntityName.periodicRepeat, budgetID: budgetID)
            .map(CoreDataMapping.periodicRepeat(from:))
    }

    func fetchPeriodicRepeatRevisions(repeatIDs: Set<UUID>) throws -> [PeriodicRepeatRevision] {
        guard !repeatIDs.isEmpty else { return [] }
        let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.periodicRepeatRevision)
        request.predicate = NSPredicate(format: "repeatID IN %@", Array(repeatIDs))
        return try context.fetch(request).compactMap(CoreDataMapping.periodicRepeatRevision(from:))
    }

    func fetchPeriodicRepeatSkips(repeatIDs: Set<UUID>) throws -> [PeriodicRepeatSkip] {
        guard !repeatIDs.isEmpty else { return [] }
        let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.periodicRepeatSkip)
        request.predicate = NSPredicate(format: "repeatID IN %@", Array(repeatIDs))
        return try context.fetch(request).compactMap(CoreDataMapping.periodicRepeatSkip(from:))
    }

    func fetchPeriodicOccurrences(plannedItemIDs: Set<UUID>) throws -> [PeriodicOccurrenceRecord] {
        guard !plannedItemIDs.isEmpty else { return [] }
        let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.periodicOccurrence)
        request.predicate = NSPredicate(format: "plannedItemID IN %@", Array(plannedItemIDs))
        return try context.fetch(request).compactMap(CoreDataMapping.periodicOccurrence(from:))
    }

    func deletePeriodicOccurrences(plannedItemIDs: Set<UUID>) throws {
        guard !plannedItemIDs.isEmpty else { return }
        let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.periodicOccurrence)
        request.predicate = NSPredicate(format: "plannedItemID IN %@", Array(plannedItemIDs))
        try context.fetch(request).forEach(context.delete)
        try save()
    }

    func upsertPeriodicRepeats(_ repeats: [PeriodicRepeat]) throws {
        for value in repeats {
            let object = try fetchFirst(entityName: CoreDataEntityName.periodicRepeat, id: value.id)
                ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.periodicRepeat, into: context)
            CoreDataMapping.apply(value, to: object)
            if let budget = try fetchFirst(entityName: CoreDataEntityName.budget, id: value.budgetID) {
                object.setValue(budget, forKey: "budget")
            }
        }
        try save()
    }

    func upsertPeriodicRepeatRevisions(_ revisions: [PeriodicRepeatRevision]) throws {
        for value in revisions {
            let object = try fetchFirst(entityName: CoreDataEntityName.periodicRepeatRevision, id: value.id)
                ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.periodicRepeatRevision, into: context)
            CoreDataMapping.apply(value, to: object)
            if let repeatObject = try fetchFirst(entityName: CoreDataEntityName.periodicRepeat, id: value.repeatID) {
                object.setValue(repeatObject, forKey: "repeat")
            }
        }
        try save()
    }

    func upsertPeriodicRepeatSkips(_ skips: [PeriodicRepeatSkip]) throws {
        for value in skips {
            let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.periodicRepeatSkip)
            request.predicate = NSCompoundPredicate(andPredicateWithSubpredicates: [
                NSPredicate(format: "repeatID == %@", value.repeatID as CVarArg),
                NSPredicate(format: "scheduledDateRaw == %@", value.scheduledDateRaw)
            ])
            let object = try context.fetch(request).first
                ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.periodicRepeatSkip, into: context)
            CoreDataMapping.apply(value, to: object)
            if let repeatObject = try fetchFirst(entityName: CoreDataEntityName.periodicRepeat, id: value.repeatID) {
                object.setValue(repeatObject, forKey: "repeat")
            }
        }
        try save()
    }

    func upsertPeriodicOccurrences(_ occurrences: [PeriodicOccurrenceRecord]) throws {
        for value in occurrences {
            let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.periodicOccurrence)
            request.predicate = NSPredicate(format: "plannedItemID == %@", value.plannedItemID as CVarArg)
            let object = try context.fetch(request).first
                ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.periodicOccurrence, into: context)
            CoreDataMapping.apply(value, to: object)
            if let repeatID = value.repeatID,
               let repeatObject = try fetchFirst(entityName: CoreDataEntityName.periodicRepeat, id: repeatID) {
                object.setValue(repeatObject, forKey: "repeat")
            } else {
                object.setValue(nil, forKey: "repeat")
            }
        }
        try save()
    }

    func upsertPlannedItemAndPeriodicOccurrence(_ item: PlannedItem, occurrence: PeriodicOccurrenceRecord) throws {
        guard item.id == occurrence.plannedItemID, item.budgetID == occurrence.budgetID else {
            throw RepositoryError.invalidCrossScopeReference
        }
        let managedItem = try fetchFirst(entityName: CoreDataEntityName.plannedItem, id: item.id)
            ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.plannedItem, into: context)
        CoreDataMapping.apply(item, to: managedItem)
        try attachToBudgetRelationship(managedObject: managedItem, budgetID: item.budgetID)
        let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.periodicOccurrence)
        request.predicate = NSPredicate(format: "plannedItemID == %@", item.id as CVarArg)
        let occurrenceObject = try context.fetch(request).first
            ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.periodicOccurrence, into: context)
        CoreDataMapping.apply(occurrence, to: occurrenceObject)
        if let repeatID = occurrence.repeatID,
           let repeatObject = try fetchFirst(entityName: CoreDataEntityName.periodicRepeat, id: repeatID) {
            occurrenceObject.setValue(repeatObject, forKey: "repeat")
        }
        try save()
    }

    func upsertDetachedPeriodicOccurrence(_ item: PlannedItem, occurrence: PeriodicOccurrenceRecord, skip: PeriodicRepeatSkip) throws {
        guard item.id == occurrence.plannedItemID, item.budgetID == occurrence.budgetID,
              item.repeatMode == .oneOff, occurrence.repeatID == nil,
              occurrence.scheduledDate == skip.scheduledDate else { throw RepositoryError.invalidCrossScopeReference }
        let managedItem = try fetchFirst(entityName: CoreDataEntityName.plannedItem, id: item.id)
            ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.plannedItem, into: context)
        CoreDataMapping.apply(item, to: managedItem)
        try attachToBudgetRelationship(managedObject: managedItem, budgetID: item.budgetID)

        let occurrenceRequest = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.periodicOccurrence)
        occurrenceRequest.predicate = NSPredicate(format: "plannedItemID == %@", item.id as CVarArg)
        let occurrenceObject = try context.fetch(occurrenceRequest).first
            ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.periodicOccurrence, into: context)
        CoreDataMapping.apply(occurrence, to: occurrenceObject)
        occurrenceObject.setValue(nil, forKey: "repeat")

        let skipObject = NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.periodicRepeatSkip, into: context)
        CoreDataMapping.apply(skip, to: skipObject)
        guard let repeatObject = try fetchFirst(entityName: CoreDataEntityName.periodicRepeat, id: skip.repeatID) else {
            throw RepositoryError.invalidCrossScopeReference
        }
        skipObject.setValue(repeatObject, forKey: "repeat")
        try save()
    }

    func createPeriodicRepeat(repeatRecord: PeriodicRepeat, revision: PeriodicRepeatRevision, item: PlannedItem, occurrence: PeriodicOccurrenceRecord) throws {
        guard repeatRecord.id == revision.repeatID, repeatRecord.id == occurrence.repeatID,
              item.id == occurrence.plannedItemID, item.budgetID == repeatRecord.budgetID,
              item.accountID == repeatRecord.accountID else { throw RepositoryError.invalidCrossScopeReference }
        let repeatObject = NSEntityDescription.insertNewObject(
            forEntityName: CoreDataEntityName.periodicRepeat, into: context
        )
        CoreDataMapping.apply(repeatRecord, to: repeatObject)
        if let budget = try fetchFirst(entityName: CoreDataEntityName.budget, id: repeatRecord.budgetID) {
            repeatObject.setValue(budget, forKey: "budget")
        }
        let revisionObject = NSEntityDescription.insertNewObject(
            forEntityName: CoreDataEntityName.periodicRepeatRevision, into: context
        )
        CoreDataMapping.apply(revision, to: revisionObject)
        revisionObject.setValue(repeatObject, forKey: "repeat")
        let itemObject = try fetchFirst(entityName: CoreDataEntityName.plannedItem, id: item.id)
            ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.plannedItem, into: context)
        CoreDataMapping.apply(item, to: itemObject)
        try attachToBudgetRelationship(managedObject: itemObject, budgetID: item.budgetID)
        let occurrenceRequest = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.periodicOccurrence)
        occurrenceRequest.predicate = NSPredicate(format: "plannedItemID == %@", item.id as CVarArg)
        let occurrenceObject = try context.fetch(occurrenceRequest).first
            ?? NSEntityDescription.insertNewObject(forEntityName: CoreDataEntityName.periodicOccurrence, into: context)
        CoreDataMapping.apply(occurrence, to: occurrenceObject)
        occurrenceObject.setValue(repeatObject, forKey: "repeat")
        try save()
    }

    func replacePeriodicRepeatRevisions(repeatID: UUID, from boundary: CivilDate, with revision: PeriodicRepeatRevision) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.periodicRepeatRevision)
        request.predicate = NSPredicate(format: "repeatID == %@ AND effectiveDateRaw >= %@", repeatID as CVarArg, boundary.rawValue)
        try context.fetch(request).forEach(context.delete)
        let object = NSEntityDescription.insertNewObject(
            forEntityName: CoreDataEntityName.periodicRepeatRevision, into: context
        )
        CoreDataMapping.apply(revision, to: object)
        if let repeatObject = try fetchFirst(entityName: CoreDataEntityName.periodicRepeat, id: repeatID) {
            object.setValue(repeatObject, forKey: "repeat")
        }
        try save()
    }

    func deletePeriodicRepeats(budgetID: UUID) throws {
        let repeats = try fetchObjects(entityName: CoreDataEntityName.periodicRepeat, budgetID: budgetID)
        let ids = Set(repeats.compactMap { $0.value(forKey: "id") as? UUID })
        try deleteRepeatDependents(ids: ids)
        repeats.forEach(context.delete)
        try save()
    }

    func deletePeriodicRepeats(accountID: UUID) throws {
        let request = NSFetchRequest<NSManagedObject>(entityName: CoreDataEntityName.periodicRepeat)
        request.predicate = NSPredicate(format: "accountID == %@", accountID as CVarArg)
        let repeats = try context.fetch(request)
        let ids = Set(repeats.compactMap { $0.value(forKey: "id") as? UUID })
        try deleteRepeatDependents(ids: ids)
        repeats.forEach(context.delete)
        try save()
    }

    private func deleteRepeatDependents(ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        for entityName in [CoreDataEntityName.periodicRepeatRevision, CoreDataEntityName.periodicRepeatSkip, CoreDataEntityName.periodicOccurrence] {
            let request = NSFetchRequest<NSManagedObject>(entityName: entityName)
            request.predicate = NSPredicate(format: "repeatID IN %@", Array(ids))
            try context.fetch(request).forEach(context.delete)
        }
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
