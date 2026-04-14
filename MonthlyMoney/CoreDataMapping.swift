import CoreData
import Foundation

enum CoreDataEntityName {
    static let budget = "CDBudget"
    static let account = "CDAccount"
    static let plannedItem = "CDPlannedItem"
    static let transaction = "CDTransaction"
    static let importedTransactionRecord = "CDImportedTransactionRecord"
    static let wheelOfMoneyItem = "CDWheelOfMoneyItem"
}

enum CoreDataModelBuilder {
    static let sharedModel: NSManagedObjectModel = makeModel()

    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        let budgetEntity = makeBudgetEntity()
        let accountEntity = makeAccountEntity()
        let plannedItemEntity = makePlannedItemEntity()
        let transactionEntity = makeTransactionEntity()
        let importedTransactionRecordEntity = makeImportedTransactionRecordEntity()
        let wheelOfMoneyItemEntity = makeWheelOfMoneyItemEntity()

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

        budgetEntity.properties.append(contentsOf: [budgetAccounts, budgetPlannedItems, budgetTransactions, budgetImportedTransactionRecords, budgetWheelOfMoneyItems])
        accountEntity.properties.append(accountBudget)
        plannedItemEntity.properties.append(plannedItemBudget)
        transactionEntity.properties.append(transactionBudget)
        importedTransactionRecordEntity.properties.append(importedTransactionRecordBudget)
        wheelOfMoneyItemEntity.properties.append(wheelOfMoneyItemBudget)

        model.entities = [budgetEntity, accountEntity, plannedItemEntity, transactionEntity, importedTransactionRecordEntity, wheelOfMoneyItemEntity]
        return model
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

    private static func makePlannedItemEntity() -> NSEntityDescription {
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
            attribute("isPaid", .booleanAttributeType, defaultValue: false),
            attribute("sourceRaw", .stringAttributeType, defaultValue: PlannedItemSource.manual.rawValue),
            attribute("copiesToNextMonthAutomatically", .booleanAttributeType, defaultValue: true),
            attribute("notes", .stringAttributeType, defaultValue: "")
        ]
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
            isPaid: isPaid,
            copiesToNextMonthAutomatically: copiesToNextMonthAutomatically,
            notes: notes
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
}
