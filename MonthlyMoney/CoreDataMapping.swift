import CoreData
import Foundation

enum CoreDataEntityName {
    static let budget = "CDBudget"
    static let account = "CDAccount"
    static let plannedItem = "CDPlannedItem"
    static let populatedMonth = "CDPopulatedMonth"
    static let transaction = "CDTransaction"
    static let importedTransactionRecord = "CDImportedTransactionRecord"
    static let wheelOfMoneyItem = "CDWheelOfMoneyItem"
    static let periodicRepeat = "CDPeriodicRepeat"
    static let periodicRepeatRevision = "CDPeriodicRepeatRevision"
    static let periodicRepeatSkip = "CDPeriodicRepeatSkip"
    static let periodicOccurrence = "CDPeriodicOccurrence"
}

enum CoreDataModelBuilder {
    static let legacyModel: NSManagedObjectModel = makeModel(includeEveryNDaysAttributes: true, includeRepeatMode: false, includePopulatedMonth: false, includeImportedPostedAt: false, versionIdentifier: "MonthlyMoney.v2")
    static let v3Model: NSManagedObjectModel = makeModel(includeEveryNDaysAttributes: true, includeRepeatMode: true, includePopulatedMonth: true, includeImportedPostedAt: false, versionIdentifier: "MonthlyMoney.v3")
    static let v4Model: NSManagedObjectModel = makeModel(includeEveryNDaysAttributes: true, includeRepeatMode: true, includePopulatedMonth: true, includeImportedPostedAt: true, versionIdentifier: "MonthlyMoney.v4")
    static let sharedModel: NSManagedObjectModel = makeModel(includeEveryNDaysAttributes: true, includeRepeatMode: true, includePopulatedMonth: true, includeImportedPostedAt: true, includeAllowsPreviousMonthEditing: true, versionIdentifier: "MonthlyMoney.v5")
    static let v6Model: NSManagedObjectModel = makeModel(includeEveryNDaysAttributes: true, includeRepeatMode: true, includePopulatedMonth: true, includeImportedPostedAt: true, includeAllowsPreviousMonthEditing: true, includePeriodicRepeats: true, versionIdentifier: "MonthlyMoney.v6")

    static func makeModel(
        includeEveryNDaysAttributes: Bool = true,
        includeRepeatMode: Bool = true,
        includePopulatedMonth: Bool = true,
        includeImportedPostedAt: Bool = true,
        includeAllowsPreviousMonthEditing: Bool = false,
        includePeriodicRepeats: Bool = false,
        versionIdentifier: String = "MonthlyMoney.v4"
    ) -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let budgetEntity = makeBudgetEntity()
        if includeAllowsPreviousMonthEditing {
            budgetEntity.properties.append(attribute("allowsPreviousMonthEditing", .booleanAttributeType, defaultValue: false))
        }
        let accountEntity = makeAccountEntity()
        let plannedItemEntity = makePlannedItemEntity(includeImportedPostedAt: includeImportedPostedAt)
        let transactionEntity = makeTransactionEntity()
        let importedTransactionRecordEntity = makeImportedTransactionRecordEntity()
        let wheelOfMoneyItemEntity = makeWheelOfMoneyItemEntity()
        let populatedMonthEntity = makePopulatedMonthEntity()
        let periodicRepeatEntity = includePeriodicRepeats ? makePeriodicRepeatEntity() : nil
        let periodicRepeatRevisionEntity = includePeriodicRepeats ? makePeriodicRepeatRevisionEntity() : nil
        let periodicRepeatSkipEntity = includePeriodicRepeats ? makePeriodicRepeatSkipEntity() : nil
        let periodicOccurrenceEntity = includePeriodicRepeats ? makePeriodicOccurrenceEntity() : nil

        let budgetAccounts = relationship(
            "accounts",
            destination: accountEntity,
            minCount: 0,
            maxCount: 0,
            deleteRule: .cascadeDeleteRule
        )
        let accountBudget = relationship(
            "budget",
            destination: budgetEntity,
            minCount: 0,
            maxCount: 1,
            deleteRule: .nullifyDeleteRule
        )
        budgetAccounts.inverseRelationship = accountBudget
        accountBudget.inverseRelationship = budgetAccounts

        let budgetPlannedItems = relationship(
            "plannedItems",
            destination: plannedItemEntity,
            minCount: 0,
            maxCount: 0,
            deleteRule: .cascadeDeleteRule
        )
        let plannedItemBudget = relationship(
            "budget",
            destination: budgetEntity,
            minCount: 0,
            maxCount: 1,
            deleteRule: .nullifyDeleteRule
        )
        budgetPlannedItems.inverseRelationship = plannedItemBudget
        plannedItemBudget.inverseRelationship = budgetPlannedItems

        let budgetTransactions = relationship(
            "transactions",
            destination: transactionEntity,
            minCount: 0,
            maxCount: 0,
            deleteRule: .cascadeDeleteRule
        )
        let transactionBudget = relationship(
            "budget",
            destination: budgetEntity,
            minCount: 0,
            maxCount: 1,
            deleteRule: .nullifyDeleteRule
        )
        budgetTransactions.inverseRelationship = transactionBudget
        transactionBudget.inverseRelationship = budgetTransactions

        let budgetImportedTransactionRecords = relationship(
            "importedTransactionRecords",
            destination: importedTransactionRecordEntity,
            minCount: 0,
            maxCount: 0,
            deleteRule: .cascadeDeleteRule
        )
        let importedTransactionRecordBudget = relationship(
            "budget",
            destination: budgetEntity,
            minCount: 0,
            maxCount: 1,
            deleteRule: .nullifyDeleteRule
        )
        budgetImportedTransactionRecords.inverseRelationship = importedTransactionRecordBudget
        importedTransactionRecordBudget.inverseRelationship = budgetImportedTransactionRecords

        let budgetWheelOfMoneyItems = relationship(
            "wheelOfMoneyItems",
            destination: wheelOfMoneyItemEntity,
            minCount: 0,
            maxCount: 0,
            deleteRule: .cascadeDeleteRule
        )
        let wheelOfMoneyItemBudget = relationship(
            "budget",
            destination: budgetEntity,
            minCount: 0,
            maxCount: 1,
            deleteRule: .nullifyDeleteRule
        )
        budgetWheelOfMoneyItems.inverseRelationship = wheelOfMoneyItemBudget
        wheelOfMoneyItemBudget.inverseRelationship = budgetWheelOfMoneyItems

        let budgetPopulatedMonths = relationship(
            "populatedMonths",
            destination: populatedMonthEntity,
            minCount: 0,
            maxCount: 0,
            deleteRule: .cascadeDeleteRule
        )
        let populatedMonthBudget = relationship(
            "budget",
            destination: budgetEntity,
            minCount: 0,
            maxCount: 1,
            deleteRule: .nullifyDeleteRule
        )
        budgetPopulatedMonths.inverseRelationship = populatedMonthBudget
        populatedMonthBudget.inverseRelationship = budgetPopulatedMonths

        budgetEntity.properties.append(contentsOf: [budgetAccounts, budgetPlannedItems, budgetTransactions, budgetImportedTransactionRecords, budgetWheelOfMoneyItems])
        accountEntity.properties.append(accountBudget)
        plannedItemEntity.properties.append(plannedItemBudget)
        transactionEntity.properties.append(transactionBudget)
        importedTransactionRecordEntity.properties.append(importedTransactionRecordBudget)
        wheelOfMoneyItemEntity.properties.append(wheelOfMoneyItemBudget)

        if includePopulatedMonth {
            budgetEntity.properties.append(budgetPopulatedMonths)
            populatedMonthEntity.properties.append(populatedMonthBudget)
        }

        if let periodicRepeatEntity,
           let periodicRepeatRevisionEntity,
           let periodicRepeatSkipEntity,
           let periodicOccurrenceEntity {
            let budgetRepeats = relationship("periodicRepeats", destination: periodicRepeatEntity, minCount: 0, maxCount: 0, deleteRule: .cascadeDeleteRule)
            let repeatBudget = relationship("budget", destination: budgetEntity, minCount: 0, maxCount: 1, deleteRule: .nullifyDeleteRule)
            budgetRepeats.inverseRelationship = repeatBudget
            repeatBudget.inverseRelationship = budgetRepeats

            let repeatRevisions = relationship("revisions", destination: periodicRepeatRevisionEntity, minCount: 0, maxCount: 0, deleteRule: .cascadeDeleteRule)
            let revisionRepeat = relationship("repeat", destination: periodicRepeatEntity, minCount: 0, maxCount: 1, deleteRule: .nullifyDeleteRule)
            repeatRevisions.inverseRelationship = revisionRepeat
            revisionRepeat.inverseRelationship = repeatRevisions

            let repeatSkips = relationship("skips", destination: periodicRepeatSkipEntity, minCount: 0, maxCount: 0, deleteRule: .cascadeDeleteRule)
            let skipRepeat = relationship("repeat", destination: periodicRepeatEntity, minCount: 0, maxCount: 1, deleteRule: .nullifyDeleteRule)
            repeatSkips.inverseRelationship = skipRepeat
            skipRepeat.inverseRelationship = repeatSkips

            let repeatOccurrences = relationship("occurrences", destination: periodicOccurrenceEntity, minCount: 0, maxCount: 0, deleteRule: .cascadeDeleteRule)
            let occurrenceRepeat = relationship("repeat", destination: periodicRepeatEntity, minCount: 0, maxCount: 1, deleteRule: .nullifyDeleteRule)
            repeatOccurrences.inverseRelationship = occurrenceRepeat
            occurrenceRepeat.inverseRelationship = repeatOccurrences

            budgetEntity.properties.append(budgetRepeats)
            periodicRepeatEntity.properties.append(contentsOf: [repeatBudget, repeatRevisions, repeatSkips, repeatOccurrences])
            periodicRepeatRevisionEntity.properties.append(revisionRepeat)
            periodicRepeatSkipEntity.properties.append(skipRepeat)
            periodicOccurrenceEntity.properties.append(occurrenceRepeat)
        }

        if includeRepeatMode {
            plannedItemEntity.properties.append(attribute("repeatModeRaw", .stringAttributeType, isOptional: true))
        }

        if !includeEveryNDaysAttributes {
            plannedItemEntity.properties.removeAll { property in
                guard let attribute = property as? NSAttributeDescription else { return false }
                return attribute.name == "repeatDays" || attribute.name == "recurrenceID"
            }
        }
        var entities = [budgetEntity, accountEntity, plannedItemEntity, transactionEntity, importedTransactionRecordEntity, wheelOfMoneyItemEntity]
        if includePopulatedMonth { entities.append(populatedMonthEntity) }
        if let periodicRepeatEntity,
           let periodicRepeatRevisionEntity,
           let periodicRepeatSkipEntity,
           let periodicOccurrenceEntity {
            entities.append(contentsOf: [periodicRepeatEntity, periodicRepeatRevisionEntity, periodicRepeatSkipEntity, periodicOccurrenceEntity])
        }
        model.entities = entities
        model.versionIdentifiers = [versionIdentifier]
        return model
    }

    static func inferredEveryNDaysMigrationModel() throws -> NSMappingModel {
        try NSMappingModel.inferredMappingModel(
            forSourceModel: legacyModel,
            destinationModel: sharedModel
        )
    }

    static func explicitEveryNDaysMigrationModel() throws -> NSMappingModel {
        let mapping = try inferredEveryNDaysMigrationModel()
        guard let plannedItemMapping = mapping.entityMappings.first(where: {
            $0.sourceEntityName == CoreDataEntityName.plannedItem
        }) else {
            throw CoreDataMigrationError.missingPlannedItemMapping
        }
        plannedItemMapping.entityMigrationPolicyClassName = NSStringFromClass(CoreDataV2ToV3MigrationPolicy.self)
        plannedItemMapping.attributeMappings = []
        plannedItemMapping.mappingType = .customEntityMappingType
        return mapping
    }

    private static func makeBudgetEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = CoreDataEntityName.budget
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: UUID()),
            attribute("name", .stringAttributeType, defaultValue: ""),
            attribute("ownerParticipantID", .stringAttributeType, defaultValue: ""),
            attribute("sharingStateRaw", .stringAttributeType, defaultValue: BudgetSharingState.local.rawValue),
            attribute("createdAt", .dateAttributeType, defaultValue: Date()),
            attribute("updatedAt", .dateAttributeType, defaultValue: Date()),
            attribute("monthlyBalanceLastUpdatedAt", .dateAttributeType, isOptional: true),
            attribute("dailyBalanceLastUpdatedAt", .dateAttributeType, isOptional: true),
            attribute("usesSeparateAccountForDailyBudget", .booleanAttributeType, defaultValue: false),
            attribute("dailyBudgetAmount", .decimalAttributeType, defaultValue: NSDecimalNumber.zero),
            attribute("dailyBudgetPaydayDay", .integer16AttributeType, defaultValue: 1),
            attribute("dailyBudgetSeparateAccountBalance", .decimalAttributeType, defaultValue: NSDecimalNumber.zero),
            attribute("autoGenerateWoMSavingsEveryMonth", .booleanAttributeType, defaultValue: false),
            attribute("monthBalancesPayload", .stringAttributeType, defaultValue: "{}"),
            attribute("hiddenDailyAccountID", .UUIDAttributeType, isOptional: true)
        ]
        return entity
    }

    private static func makeAccountEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = CoreDataEntityName.account
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: UUID()),
            attribute("budgetID", .UUIDAttributeType, defaultValue: UUID()),
            attribute("name", .stringAttributeType, defaultValue: ""),
            attribute("roleRaw", .stringAttributeType, defaultValue: AccountRole.regular.rawValue),
            attribute("typeRaw", .stringAttributeType, defaultValue: AccountType.current.rawValue),
            attribute("ownerParticipantID", .stringAttributeType, defaultValue: "")
        ]
        return entity
    }

    private static func makePlannedItemEntity(includeImportedPostedAt: Bool) -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = CoreDataEntityName.plannedItem
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: UUID()),
            attribute("budgetID", .UUIDAttributeType, defaultValue: UUID()),
            attribute("accountID", .UUIDAttributeType, defaultValue: UUID()),
            attribute("monthKey", .stringAttributeType, defaultValue: YearMonth(year: 2000, month: 1).rawValue),
            attribute("typeRaw", .stringAttributeType, defaultValue: PlannedItemType.fixedDebit.rawValue),
            attribute("label", .stringAttributeType, defaultValue: ""),
            attribute("matchingString", .stringAttributeType, isOptional: true),
            attribute("amount", .decimalAttributeType, defaultValue: NSDecimalNumber.zero),
            attribute("dueDay", .integer16AttributeType, isOptional: true),
            attribute("dueText", .stringAttributeType, isOptional: true),
            attribute("repeatDays", .integer16AttributeType, isOptional: true),
            attribute("recurrenceID", .UUIDAttributeType, isOptional: true),
            attribute("isPaid", .booleanAttributeType, defaultValue: false),
            attribute("sourceRaw", .stringAttributeType, defaultValue: PlannedItemSource.manual.rawValue),
            attribute("copiesToNextMonthAutomatically", .booleanAttributeType, defaultValue: true),
            attribute("notes", .stringAttributeType, defaultValue: "")
        ]
        if includeImportedPostedAt {
            entity.properties.append(attribute("importedPostedAt", .dateAttributeType, isOptional: true))
        }
        return entity
    }

    private static func makeTransactionEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = CoreDataEntityName.transaction
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: UUID()),
            attribute("budgetID", .UUIDAttributeType, defaultValue: UUID()),
            attribute("accountID", .UUIDAttributeType, defaultValue: UUID()),
            attribute("monthKey", .stringAttributeType, defaultValue: YearMonth(year: 2000, month: 1).rawValue),
            attribute("amount", .decimalAttributeType, defaultValue: NSDecimalNumber.zero),
            attribute("note", .stringAttributeType, defaultValue: ""),
            attribute("sourceKind", .stringAttributeType, defaultValue: ""),
            attribute("sourceExternalTransactionID", .stringAttributeType, defaultValue: ""),
            attribute("sourcePostedAt", .dateAttributeType, isOptional: true)
        ]
        return entity
    }

    private static func makeImportedTransactionRecordEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = CoreDataEntityName.importedTransactionRecord
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: UUID()),
            attribute("budgetID", .UUIDAttributeType, defaultValue: UUID()),
            attribute("accountID", .UUIDAttributeType, defaultValue: UUID()),
            attribute("sourceKind", .stringAttributeType, defaultValue: ""),
            attribute("sourceAccountIdentifier", .stringAttributeType, defaultValue: ""),
            attribute("externalTransactionID", .stringAttributeType, defaultValue: ""),
            attribute("postedAt", .dateAttributeType, defaultValue: Date()),
            attribute("amount", .decimalAttributeType, defaultValue: NSDecimalNumber.zero),
            attribute("payee", .stringAttributeType, defaultValue: ""),
            attribute("transactionType", .stringAttributeType, defaultValue: ""),
            attribute("rawSourcePayload", .stringAttributeType, defaultValue: ""),
            attribute("importedAt", .dateAttributeType, defaultValue: Date()),
            attribute("appliedPlannedItemID", .UUIDAttributeType, isOptional: true),
            attribute("createdTransactionID", .UUIDAttributeType, isOptional: true)
        ]
        return entity
    }

    private static func makeWheelOfMoneyItemEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = CoreDataEntityName.wheelOfMoneyItem
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: UUID()),
            attribute("budgetID", .UUIDAttributeType, defaultValue: UUID()),
            attribute("title", .stringAttributeType, defaultValue: ""),
            attribute("amount", .decimalAttributeType, defaultValue: NSDecimalNumber.zero),
            attribute("month", .integer16AttributeType, defaultValue: Int16(WheelOfMoneyMonth.january.rawValue)),
            attribute("isPaid", .booleanAttributeType, defaultValue: false),
            attribute("notes", .stringAttributeType, defaultValue: ""),
            attribute("isAutoGeneratedSavingsEntry", .booleanAttributeType, defaultValue: false)
        ]
        return entity
    }

    private static func makePopulatedMonthEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = CoreDataEntityName.populatedMonth
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: UUID()),
            attribute("budgetID", .UUIDAttributeType, defaultValue: UUID()),
            attribute("monthKey", .stringAttributeType, defaultValue: YearMonth(year: 2000, month: 1).rawValue)
        ]
        return entity
    }

    private static func makePeriodicRepeatEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = CoreDataEntityName.periodicRepeat
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: UUID()),
            attribute("budgetID", .UUIDAttributeType, defaultValue: UUID()),
            attribute("accountID", .UUIDAttributeType, defaultValue: UUID()),
            attribute("endDateRaw", .stringAttributeType, isOptional: true)
        ]
        return entity
    }

    private static func makePeriodicRepeatRevisionEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = CoreDataEntityName.periodicRepeatRevision
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: UUID()),
            attribute("repeatID", .UUIDAttributeType, defaultValue: UUID()),
            attribute("effectiveDateRaw", .stringAttributeType, defaultValue: "2000-01-01"),
            attribute("anchorDateRaw", .stringAttributeType, defaultValue: "2000-01-01"),
            attribute("repeatDays", .integer32AttributeType, defaultValue: 1),
            attribute("typeRaw", .stringAttributeType, defaultValue: PlannedItemType.fixedDebit.rawValue),
            attribute("label", .stringAttributeType, defaultValue: ""),
            attribute("matchingString", .stringAttributeType, isOptional: true),
            attribute("amount", .decimalAttributeType, defaultValue: NSDecimalNumber.zero),
            attribute("notes", .stringAttributeType, defaultValue: "")
        ]
        return entity
    }

    private static func makePeriodicRepeatSkipEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = CoreDataEntityName.periodicRepeatSkip
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute("id", .UUIDAttributeType, defaultValue: UUID()),
            attribute("repeatID", .UUIDAttributeType, defaultValue: UUID()),
            attribute("scheduledDateRaw", .stringAttributeType, defaultValue: "2000-01-01")
        ]
        return entity
    }

    private static func makePeriodicOccurrenceEntity() -> NSEntityDescription {
        let entity = NSEntityDescription()
        entity.name = CoreDataEntityName.periodicOccurrence
        entity.managedObjectClassName = NSStringFromClass(NSManagedObject.self)
        entity.properties = [
            attribute("plannedItemID", .UUIDAttributeType, defaultValue: UUID()),
            attribute("budgetID", .UUIDAttributeType, defaultValue: UUID()),
            attribute("repeatID", .UUIDAttributeType, isOptional: true),
            attribute("scheduledDateRaw", .stringAttributeType, defaultValue: "2000-01-01"),
            attribute("dueDateRaw", .stringAttributeType, defaultValue: "2000-01-01"),
            attribute("isOverride", .booleanAttributeType, defaultValue: false)
        ]
        return entity
    }

    private static func attribute(
        _ name: String,
        _ type: NSAttributeType,
        isOptional: Bool = false,
        defaultValue: Any? = nil
    ) -> NSAttributeDescription {
        let attribute = NSAttributeDescription()
        attribute.name = name
        attribute.attributeType = type
        attribute.isOptional = isOptional
        attribute.defaultValue = defaultValue
        return attribute
    }

    private static func relationship(
        _ name: String,
        destination: NSEntityDescription,
        minCount: Int,
        maxCount: Int,
        deleteRule: NSDeleteRule
    ) -> NSRelationshipDescription {
        let relationship = NSRelationshipDescription()
        relationship.name = name
        relationship.destinationEntity = destination
        relationship.minCount = minCount
        relationship.maxCount = maxCount
        relationship.deleteRule = deleteRule
        relationship.isOptional = true
        return relationship
    }
}

enum CoreDataMigrationError: Error {
    case missingPlannedItemMapping
}

final class CoreDataV2ToV3MigrationPolicy: NSEntityMigrationPolicy {
    override func createDestinationInstances(
        forSource sourceInstance: NSManagedObject,
        in mapping: NSEntityMapping,
        manager: NSMigrationManager
    ) throws {
        guard let destinationEntityName = mapping.destinationEntityName else {
            throw CoreDataMigrationError.missingPlannedItemMapping
        }
        let destination = NSEntityDescription.insertNewObject(
            forEntityName: destinationEntityName,
            into: manager.destinationContext
        )

        for (name, _) in sourceInstance.entity.attributesByName {
            guard destination.entity.attributesByName[name] != nil else { continue }
            destination.setValue(sourceInstance.value(forKey: name), forKey: name)
        }

        let dueDay = (sourceInstance.value(forKey: "dueDay") as? NSNumber)?.intValue
        let repeatDays = (sourceInstance.value(forKey: "repeatDays") as? NSNumber)?.intValue
        let copiesAutomatically = sourceInstance.value(forKey: "copiesToNextMonthAutomatically") as? Bool ?? true
        let mode: RepeatMode = (repeatDays ?? 0) > 0
            ? .periodic
            : (dueDay != nil && copiesAutomatically ? .calendar : .oneOff)
        destination.setValue(mode.rawValue, forKey: "repeatModeRaw")

        manager.associate(
            sourceInstance: sourceInstance,
            withDestinationInstance: destination,
            for: mapping
        )
    }

    static func legacySeriesKey(for sourceInstance: NSManagedObject) -> String {
        let budgetID = (sourceInstance.value(forKey: "budgetID") as? UUID)?.uuidString ?? ""
        let accountID = (sourceInstance.value(forKey: "accountID") as? UUID)?.uuidString ?? ""
        let amount = (sourceInstance.value(forKey: "amount") as? NSDecimalNumber)?.stringValue ?? ""
        return [
            budgetID,
            accountID,
            sourceInstance.value(forKey: "typeRaw") as? String ?? "",
            sourceInstance.value(forKey: "label") as? String ?? "",
            amount
        ].joined(separator: "\u{1f}")
    }

    static func stableRecurrenceID(for seriesKey: String) -> UUID {
        let bytes = Array(seriesKey.utf8)
        var first: UInt64 = 14_695_981_039_346_656_037
        var second: UInt64 = 10_995_116_282_111
        for byte in bytes {
            first ^= UInt64(byte)
            first &*= 1_099_511_628_211
            second ^= UInt64(byte)
            second &*= 1_099_511_628_211
        }
        let firstBytes = withUnsafeBytes(of: first.bigEndian, Array.init)
        let secondBytes = withUnsafeBytes(of: second.bigEndian, Array.init)
        return UUID(uuid: (
            firstBytes[0], firstBytes[1], firstBytes[2], firstBytes[3],
            firstBytes[4], firstBytes[5], firstBytes[6], firstBytes[7],
            secondBytes[0], secondBytes[1], secondBytes[2], secondBytes[3],
            secondBytes[4], secondBytes[5], secondBytes[6], secondBytes[7]
        ))
    }
}

enum CoreDataMapping {
    static func apply(_ budget: Budget, to managedObject: NSManagedObject) {
        managedObject.setValue(budget.id, forKey: "id")
        managedObject.setValue(budget.name, forKey: "name")
        managedObject.setValue(budget.ownerParticipantID, forKey: "ownerParticipantID")
        managedObject.setValue(budget.sharingState.rawValue, forKey: "sharingStateRaw")
        managedObject.setValue(budget.createdAt, forKey: "createdAt")
        managedObject.setValue(budget.updatedAt, forKey: "updatedAt")
        managedObject.setValue(budget.monthlyBalanceLastUpdatedAt, forKey: "monthlyBalanceLastUpdatedAt")
        managedObject.setValue(budget.dailyBalanceLastUpdatedAt, forKey: "dailyBalanceLastUpdatedAt")
        managedObject.setValue(budget.usesSeparateAccountForDailyBudget, forKey: "usesSeparateAccountForDailyBudget")
        managedObject.setValue(budget.dailyBudgetAmount as NSDecimalNumber, forKey: "dailyBudgetAmount")
        managedObject.setValue(Int16(budget.dailyBudgetPaydayDay), forKey: "dailyBudgetPaydayDay")
        managedObject.setValue(budget.dailyBudgetSeparateAccountBalance as NSDecimalNumber, forKey: "dailyBudgetSeparateAccountBalance")
        managedObject.setValue(budget.autoGenerateWoMSavingsEveryMonth, forKey: "autoGenerateWoMSavingsEveryMonth")
        managedObject.setValue(budget.allowsPreviousMonthEditing, forKey: "allowsPreviousMonthEditing")
        managedObject.setValue(budget.monthBalancesPayload, forKey: "monthBalancesPayload")
        managedObject.setValue(budget.hiddenDailyAccountID, forKey: "hiddenDailyAccountID")
    }

    static func budget(from managedObject: NSManagedObject) -> Budget {
        Budget(
            id: managedObject.value(forKey: "id") as? UUID ?? UUID(),
            name: managedObject.value(forKey: "name") as? String ?? "",
            ownerParticipantID: managedObject.value(forKey: "ownerParticipantID") as? String ?? "",
            sharingState: BudgetSharingState(rawValue: managedObject.value(forKey: "sharingStateRaw") as? String ?? "") ?? .local,
            createdAt: managedObject.value(forKey: "createdAt") as? Date ?? .distantPast,
            updatedAt: managedObject.value(forKey: "updatedAt") as? Date ?? .distantPast,
            monthlyBalanceLastUpdatedAt: managedObject.value(forKey: "monthlyBalanceLastUpdatedAt") as? Date,
            dailyBalanceLastUpdatedAt: managedObject.value(forKey: "dailyBalanceLastUpdatedAt") as? Date,
            usesSeparateAccountForDailyBudget: managedObject.value(forKey: "usesSeparateAccountForDailyBudget") as? Bool ?? false,
            dailyBudgetAmount: (managedObject.value(forKey: "dailyBudgetAmount") as? NSDecimalNumber)?.decimalValue ?? 0,
            dailyBudgetPaydayDay: Int(managedObject.value(forKey: "dailyBudgetPaydayDay") as? Int16 ?? 1),
            dailyBudgetSeparateAccountBalance: (managedObject.value(forKey: "dailyBudgetSeparateAccountBalance") as? NSDecimalNumber)?.decimalValue ?? 0,
            autoGenerateWoMSavingsEveryMonth: managedObject.value(forKey: "autoGenerateWoMSavingsEveryMonth") as? Bool ?? false,
            allowsPreviousMonthEditing: managedObject.value(forKey: "allowsPreviousMonthEditing") as? Bool ?? false,
            monthBalancesPayload: managedObject.value(forKey: "monthBalancesPayload") as? String ?? "{}",
            hiddenDailyAccountID: managedObject.value(forKey: "hiddenDailyAccountID") as? UUID
        )
    }

    static func apply(_ account: Account, to managedObject: NSManagedObject) {
        managedObject.setValue(account.id, forKey: "id")
        managedObject.setValue(account.budgetID, forKey: "budgetID")
        managedObject.setValue(account.name, forKey: "name")
        managedObject.setValue(account.role.rawValue, forKey: "roleRaw")
        managedObject.setValue(account.type.rawValue, forKey: "typeRaw")
        managedObject.setValue(account.ownerParticipantID, forKey: "ownerParticipantID")
    }

    static func account(from managedObject: NSManagedObject) -> Account {
        Account(
            id: managedObject.value(forKey: "id") as? UUID ?? UUID(),
            budgetID: managedObject.value(forKey: "budgetID") as? UUID ?? UUID(),
            name: managedObject.value(forKey: "name") as? String ?? "",
            role: AccountRole(rawValue: managedObject.value(forKey: "roleRaw") as? String ?? "") ?? .regular,
            type: AccountType(rawValue: managedObject.value(forKey: "typeRaw") as? String ?? "") ?? .current,
            ownerParticipantID: managedObject.value(forKey: "ownerParticipantID") as? String ?? ""
        )
    }

    static func apply(_ item: PlannedItem, to managedObject: NSManagedObject) {
        managedObject.setValue(item.id, forKey: "id")
        managedObject.setValue(item.budgetID, forKey: "budgetID")
        managedObject.setValue(item.accountID, forKey: "accountID")
        managedObject.setValue(item.monthKey, forKey: "monthKey")
        managedObject.setValue(item.type.rawValue, forKey: "typeRaw")
        managedObject.setValue(item.label, forKey: "label")
        managedObject.setValue(item.matchingString, forKey: "matchingString")
        managedObject.setValue(item.amount as NSDecimalNumber, forKey: "amount")
        managedObject.setValue(item.dueDay.map(NSNumber.init(value:)), forKey: "dueDay")
        managedObject.setValue(item.dueText, forKey: "dueText")
        managedObject.setValue(item.repeatDays.map(NSNumber.init(value:)), forKey: "repeatDays")
        managedObject.setValue(item.recurrenceID, forKey: "recurrenceID")
        if managedObject.entity.attributesByName["repeatModeRaw"] != nil {
            managedObject.setValue(item.repeatMode.rawValue, forKey: "repeatModeRaw")
        }
        if managedObject.entity.attributesByName["importedPostedAt"] != nil {
            managedObject.setValue(item.importedPostedAt, forKey: "importedPostedAt")
        }
        managedObject.setValue(item.isPaid, forKey: "isPaid")
        managedObject.setValue(item.source.rawValue, forKey: "sourceRaw")
        managedObject.setValue(item.copiesToNextMonthAutomatically, forKey: "copiesToNextMonthAutomatically")
        managedObject.setValue(item.notes, forKey: "notes")
    }

    static func plannedItem(from managedObject: NSManagedObject) -> PlannedItem {
        let id = managedObject.value(forKey: "id") as? UUID ?? UUID()
        let budgetID = managedObject.value(forKey: "budgetID") as? UUID ?? UUID()
        let accountID = managedObject.value(forKey: "accountID") as? UUID ?? UUID()
        let monthKey = YearMonth(rawValue: managedObject.value(forKey: "monthKey") as? String ?? "") ?? YearMonth(year: 2000, month: 1)
        let type = PlannedItemType(rawValue: managedObject.value(forKey: "typeRaw") as? String ?? "") ?? .fixedDebit
        let label = managedObject.value(forKey: "label") as? String ?? ""
        let matchingString = managedObject.value(forKey: "matchingString") as? String
        let amount = (managedObject.value(forKey: "amount") as? NSDecimalNumber)?.decimalValue ?? 0
        let dueDay = (managedObject.value(forKey: "dueDay") as? NSNumber)?.intValue
        let dueText = managedObject.value(forKey: "dueText") as? String
        let repeatDays = (managedObject.value(forKey: "repeatDays") as? NSNumber)?.intValue
        let recurrenceID = managedObject.value(forKey: "recurrenceID") as? UUID
        let storedRepeatMode = managedObject.entity.attributesByName["repeatModeRaw"] != nil
            ? managedObject.value(forKey: "repeatModeRaw") as? String
            : nil
        let importedPostedAt = managedObject.entity.attributesByName["importedPostedAt"] != nil
            ? managedObject.value(forKey: "importedPostedAt") as? Date
            : nil
        let isPaid = managedObject.value(forKey: "isPaid") as? Bool ?? false
        let source = PlannedItemSource(rawValue: managedObject.value(forKey: "sourceRaw") as? String ?? "") ?? .manual
        let copiesToNextMonthAutomatically = managedObject.value(forKey: "copiesToNextMonthAutomatically") as? Bool ?? true
        let notes = managedObject.value(forKey: "notes") as? String ?? ""

        return PlannedItem(
            id: id,
            budgetID: budgetID,
            accountID: accountID,
            monthKey: monthKey,
            type: type,
            source: source,
            label: label,
            amount: amount,
            matchingString: matchingString,
            dueDay: dueDay,
            dueText: dueText,
            repeatDays: repeatDays,
            recurrenceID: recurrenceID,
            repeatMode: RepeatMode(rawValue: storedRepeatMode ?? "") ?? ((repeatDays ?? 0) > 0 ? .periodic : (dueDay != nil && copiesToNextMonthAutomatically ? .calendar : .oneOff)),
            importedPostedAt: importedPostedAt,
            isPaid: isPaid,
            copiesToNextMonthAutomatically: copiesToNextMonthAutomatically,
            notes: notes
        )
    }

    static func apply(_ marker: PopulatedMonth, to managedObject: NSManagedObject) {
        managedObject.setValue(marker.id, forKey: "id")
        managedObject.setValue(marker.budgetID, forKey: "budgetID")
        managedObject.setValue(marker.monthKey.rawValue, forKey: "monthKey")
    }

    static func populatedMonth(from managedObject: NSManagedObject) -> PopulatedMonth {
        PopulatedMonth(
            id: managedObject.value(forKey: "id") as? UUID ?? UUID(),
            budgetID: managedObject.value(forKey: "budgetID") as? UUID ?? UUID(),
            monthKey: YearMonth(rawValue: managedObject.value(forKey: "monthKey") as? String ?? "") ?? YearMonth(year: 2000, month: 1)
        )
    }

    static func apply(_ transaction: Transaction, to managedObject: NSManagedObject) {
        managedObject.setValue(transaction.id, forKey: "id")
        managedObject.setValue(transaction.budgetID, forKey: "budgetID")
        managedObject.setValue(transaction.accountID, forKey: "accountID")
        managedObject.setValue(transaction.monthKey, forKey: "monthKey")
        managedObject.setValue(transaction.amount as NSDecimalNumber, forKey: "amount")
        managedObject.setValue(transaction.note, forKey: "note")
        managedObject.setValue(transaction.sourceKind, forKey: "sourceKind")
        managedObject.setValue(transaction.sourceExternalTransactionID, forKey: "sourceExternalTransactionID")
        managedObject.setValue(transaction.sourcePostedAt, forKey: "sourcePostedAt")
    }

    static func transaction(from managedObject: NSManagedObject) -> Transaction {
        Transaction(
            id: managedObject.value(forKey: "id") as? UUID ?? UUID(),
            budgetID: managedObject.value(forKey: "budgetID") as? UUID ?? UUID(),
            accountID: managedObject.value(forKey: "accountID") as? UUID ?? UUID(),
            monthKey: YearMonth(rawValue: managedObject.value(forKey: "monthKey") as? String ?? "") ?? YearMonth(year: 2000, month: 1),
            amount: (managedObject.value(forKey: "amount") as? NSDecimalNumber)?.decimalValue ?? 0,
            note: managedObject.value(forKey: "note") as? String ?? "",
            sourceKind: managedObject.value(forKey: "sourceKind") as? String ?? "",
            sourceExternalTransactionID: managedObject.value(forKey: "sourceExternalTransactionID") as? String ?? "",
            sourcePostedAt: managedObject.value(forKey: "sourcePostedAt") as? Date
        )
    }

    static func apply(_ record: ImportedTransactionRecord, to managedObject: NSManagedObject) {
        managedObject.setValue(record.id, forKey: "id")
        managedObject.setValue(record.budgetID, forKey: "budgetID")
        managedObject.setValue(record.accountID, forKey: "accountID")
        managedObject.setValue(record.sourceKind, forKey: "sourceKind")
        managedObject.setValue(record.sourceAccountIdentifier, forKey: "sourceAccountIdentifier")
        managedObject.setValue(record.externalTransactionID, forKey: "externalTransactionID")
        managedObject.setValue(record.postedAt, forKey: "postedAt")
        managedObject.setValue(record.amount as NSDecimalNumber, forKey: "amount")
        managedObject.setValue(record.payee, forKey: "payee")
        managedObject.setValue(record.transactionType, forKey: "transactionType")
        managedObject.setValue(record.rawSourcePayload, forKey: "rawSourcePayload")
        managedObject.setValue(record.importedAt, forKey: "importedAt")
        managedObject.setValue(record.appliedPlannedItemID, forKey: "appliedPlannedItemID")
        managedObject.setValue(record.createdTransactionID, forKey: "createdTransactionID")
    }

    static func importedTransactionRecord(from managedObject: NSManagedObject) -> ImportedTransactionRecord {
        ImportedTransactionRecord(
            id: managedObject.value(forKey: "id") as? UUID ?? UUID(),
            budgetID: managedObject.value(forKey: "budgetID") as? UUID ?? UUID(),
            accountID: managedObject.value(forKey: "accountID") as? UUID ?? UUID(),
            sourceKind: managedObject.value(forKey: "sourceKind") as? String ?? "",
            sourceAccountIdentifier: managedObject.value(forKey: "sourceAccountIdentifier") as? String ?? "",
            externalTransactionID: managedObject.value(forKey: "externalTransactionID") as? String ?? "",
            postedAt: managedObject.value(forKey: "postedAt") as? Date ?? .distantPast,
            amount: (managedObject.value(forKey: "amount") as? NSDecimalNumber)?.decimalValue ?? 0,
            payee: managedObject.value(forKey: "payee") as? String ?? "",
            transactionType: managedObject.value(forKey: "transactionType") as? String ?? "",
            rawSourcePayload: managedObject.value(forKey: "rawSourcePayload") as? String ?? "",
            importedAt: managedObject.value(forKey: "importedAt") as? Date ?? .distantPast,
            appliedPlannedItemID: managedObject.value(forKey: "appliedPlannedItemID") as? UUID,
            createdTransactionID: managedObject.value(forKey: "createdTransactionID") as? UUID
        )
    }

    static func apply(_ item: WheelOfMoneyItem, to managedObject: NSManagedObject) {
        managedObject.setValue(item.id, forKey: "id")
        managedObject.setValue(item.budgetID, forKey: "budgetID")
        managedObject.setValue(item.title, forKey: "title")
        managedObject.setValue(item.amount as NSDecimalNumber, forKey: "amount")
        managedObject.setValue(Int16(item.month), forKey: "month")
        managedObject.setValue(item.isPaid, forKey: "isPaid")
        managedObject.setValue(item.notes, forKey: "notes")
        managedObject.setValue(item.isAutoGeneratedSavingsEntry, forKey: "isAutoGeneratedSavingsEntry")
    }

    static func wheelOfMoneyItem(from managedObject: NSManagedObject) -> WheelOfMoneyItem {
        WheelOfMoneyItem(
            id: managedObject.value(forKey: "id") as? UUID ?? UUID(),
            budgetID: managedObject.value(forKey: "budgetID") as? UUID ?? UUID(),
            title: managedObject.value(forKey: "title") as? String ?? "",
            amount: (managedObject.value(forKey: "amount") as? NSDecimalNumber)?.decimalValue ?? 0,
            month: Int(managedObject.value(forKey: "month") as? Int16 ?? Int16(WheelOfMoneyMonth.january.rawValue)),
            isPaid: managedObject.value(forKey: "isPaid") as? Bool ?? false,
            notes: managedObject.value(forKey: "notes") as? String ?? "",
            isAutoGeneratedSavingsEntry: managedObject.value(forKey: "isAutoGeneratedSavingsEntry") as? Bool ?? false
        )
    }

    static func apply(_ repeatRecord: PeriodicRepeat, to object: NSManagedObject) {
        object.setValue(repeatRecord.id, forKey: "id")
        object.setValue(repeatRecord.budgetID, forKey: "budgetID")
        object.setValue(repeatRecord.accountID, forKey: "accountID")
        object.setValue(repeatRecord.endDateRaw, forKey: "endDateRaw")
    }

    static func periodicRepeat(from object: NSManagedObject) -> PeriodicRepeat {
        PeriodicRepeat(
            id: object.value(forKey: "id") as? UUID ?? UUID(),
            budgetID: object.value(forKey: "budgetID") as? UUID ?? UUID(),
            accountID: object.value(forKey: "accountID") as? UUID ?? UUID(),
            endDate: (object.value(forKey: "endDateRaw") as? String).flatMap(CivilDate.init(rawValue:))
        )
    }

    static func apply(_ revision: PeriodicRepeatRevision, to object: NSManagedObject) {
        object.setValue(revision.id, forKey: "id")
        object.setValue(revision.repeatID, forKey: "repeatID")
        object.setValue(revision.effectiveDateRaw, forKey: "effectiveDateRaw")
        object.setValue(revision.anchorDateRaw, forKey: "anchorDateRaw")
        object.setValue(Int32(revision.repeatDays), forKey: "repeatDays")
        object.setValue(revision.type.rawValue, forKey: "typeRaw")
        object.setValue(revision.label, forKey: "label")
        object.setValue(revision.matchingString, forKey: "matchingString")
        object.setValue(revision.amount as NSDecimalNumber, forKey: "amount")
        object.setValue(revision.notes, forKey: "notes")
    }

    static func periodicRepeatRevision(from object: NSManagedObject) -> PeriodicRepeatRevision? {
        guard let effective = CivilDate(rawValue: object.value(forKey: "effectiveDateRaw") as? String ?? ""),
              let anchor = CivilDate(rawValue: object.value(forKey: "anchorDateRaw") as? String ?? "") else { return nil }
        return PeriodicRepeatRevision(
            id: object.value(forKey: "id") as? UUID ?? UUID(),
            repeatID: object.value(forKey: "repeatID") as? UUID ?? UUID(),
            effectiveDate: effective,
            anchorDate: anchor,
            repeatDays: Int(object.value(forKey: "repeatDays") as? Int32 ?? 1),
            type: PlannedItemType(rawValue: object.value(forKey: "typeRaw") as? String ?? "") ?? .fixedDebit,
            label: object.value(forKey: "label") as? String ?? "",
            matchingString: object.value(forKey: "matchingString") as? String,
            amount: (object.value(forKey: "amount") as? NSDecimalNumber)?.decimalValue ?? 0,
            notes: object.value(forKey: "notes") as? String ?? ""
        )
    }

    static func apply(_ skip: PeriodicRepeatSkip, to object: NSManagedObject) {
        object.setValue(skip.id, forKey: "id")
        object.setValue(skip.repeatID, forKey: "repeatID")
        object.setValue(skip.scheduledDateRaw, forKey: "scheduledDateRaw")
    }

    static func periodicRepeatSkip(from object: NSManagedObject) -> PeriodicRepeatSkip? {
        guard let date = CivilDate(rawValue: object.value(forKey: "scheduledDateRaw") as? String ?? "") else { return nil }
        return PeriodicRepeatSkip(
            id: object.value(forKey: "id") as? UUID ?? UUID(),
            repeatID: object.value(forKey: "repeatID") as? UUID ?? UUID(),
            scheduledDate: date
        )
    }

    static func apply(_ occurrence: PeriodicOccurrenceRecord, to object: NSManagedObject) {
        object.setValue(occurrence.plannedItemID, forKey: "plannedItemID")
        object.setValue(occurrence.budgetID, forKey: "budgetID")
        object.setValue(occurrence.repeatID, forKey: "repeatID")
        object.setValue(occurrence.scheduledDateRaw, forKey: "scheduledDateRaw")
        object.setValue(occurrence.dueDateRaw, forKey: "dueDateRaw")
        object.setValue(occurrence.isOverride, forKey: "isOverride")
    }

    static func periodicOccurrence(from object: NSManagedObject) -> PeriodicOccurrenceRecord? {
        guard let scheduledDate = CivilDate(rawValue: object.value(forKey: "scheduledDateRaw") as? String ?? ""),
              let dueDate = CivilDate(rawValue: object.value(forKey: "dueDateRaw") as? String ?? "") else { return nil }
        return PeriodicOccurrenceRecord(
            plannedItemID: object.value(forKey: "plannedItemID") as? UUID ?? UUID(),
            budgetID: object.value(forKey: "budgetID") as? UUID ?? UUID(),
            repeatID: object.value(forKey: "repeatID") as? UUID,
            scheduledDate: scheduledDate,
            dueDate: dueDate,
            isOverride: object.value(forKey: "isOverride") as? Bool ?? false
        )
    }
}
