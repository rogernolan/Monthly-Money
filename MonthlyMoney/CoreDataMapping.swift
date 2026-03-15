import CoreData
import Foundation

enum CoreDataEntityName {
    static let budget = "CDBudget"
    static let account = "CDAccount"
    static let plannedItem = "CDPlannedItem"
    static let transaction = "CDTransaction"
}

enum CoreDataModelBuilder {
    static let sharedModel: NSManagedObjectModel = makeModel()

    static func makeModel() -> NSManagedObjectModel {
        let model = NSManagedObjectModel()
        model.entities = [
            makeBudgetEntity(),
            makeAccountEntity(),
            makePlannedItemEntity(),
            makeTransactionEntity()
        ]
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
            attribute("usesSeparateAccountForDailyBudget", .booleanAttributeType, defaultValue: false),
            attribute("dailyBudgetAmount", .decimalAttributeType, defaultValue: NSDecimalNumber.zero),
            attribute("dailyBudgetPaydayDay", .integer16AttributeType, defaultValue: 1),
            attribute("dailyBudgetSeparateAccountBalance", .decimalAttributeType, defaultValue: NSDecimalNumber.zero),
            attribute("monthBalancesPayload", .stringAttributeType, defaultValue: "{}")
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
            attribute("amount", .decimalAttributeType, defaultValue: NSDecimalNumber.zero),
            attribute("dueDay", .integer16AttributeType, isOptional: true),
            attribute("dueText", .stringAttributeType, isOptional: true),
            attribute("isPaid", .booleanAttributeType, defaultValue: false),
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
            attribute("note", .stringAttributeType, defaultValue: "")
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
}

enum CoreDataMapping {
    static func apply(_ budget: Budget, to managedObject: NSManagedObject) {
        managedObject.setValue(budget.id, forKey: "id")
        managedObject.setValue(budget.name, forKey: "name")
        managedObject.setValue(budget.ownerParticipantID, forKey: "ownerParticipantID")
        managedObject.setValue(budget.sharingState.rawValue, forKey: "sharingStateRaw")
        managedObject.setValue(budget.createdAt, forKey: "createdAt")
        managedObject.setValue(budget.updatedAt, forKey: "updatedAt")
        managedObject.setValue(budget.usesSeparateAccountForDailyBudget, forKey: "usesSeparateAccountForDailyBudget")
        managedObject.setValue(budget.dailyBudgetAmount as NSDecimalNumber, forKey: "dailyBudgetAmount")
        managedObject.setValue(Int16(budget.dailyBudgetPaydayDay), forKey: "dailyBudgetPaydayDay")
        managedObject.setValue(budget.dailyBudgetSeparateAccountBalance as NSDecimalNumber, forKey: "dailyBudgetSeparateAccountBalance")
        managedObject.setValue(budget.monthBalancesPayload, forKey: "monthBalancesPayload")
    }

    static func budget(from managedObject: NSManagedObject) -> Budget {
        Budget(
            id: managedObject.value(forKey: "id") as? UUID ?? UUID(),
            name: managedObject.value(forKey: "name") as? String ?? "",
            ownerParticipantID: managedObject.value(forKey: "ownerParticipantID") as? String ?? "",
            sharingState: BudgetSharingState(rawValue: managedObject.value(forKey: "sharingStateRaw") as? String ?? "") ?? .local,
            createdAt: managedObject.value(forKey: "createdAt") as? Date ?? .distantPast,
            updatedAt: managedObject.value(forKey: "updatedAt") as? Date ?? .distantPast,
            usesSeparateAccountForDailyBudget: managedObject.value(forKey: "usesSeparateAccountForDailyBudget") as? Bool ?? false,
            dailyBudgetAmount: (managedObject.value(forKey: "dailyBudgetAmount") as? NSDecimalNumber)?.decimalValue ?? 0,
            dailyBudgetPaydayDay: Int(managedObject.value(forKey: "dailyBudgetPaydayDay") as? Int16 ?? 1),
            dailyBudgetSeparateAccountBalance: (managedObject.value(forKey: "dailyBudgetSeparateAccountBalance") as? NSDecimalNumber)?.decimalValue ?? 0,
            monthBalancesPayload: managedObject.value(forKey: "monthBalancesPayload") as? String ?? "{}"
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
        managedObject.setValue(item.amount as NSDecimalNumber, forKey: "amount")
        managedObject.setValue(item.dueDay.map(NSNumber.init(value:)), forKey: "dueDay")
        managedObject.setValue(item.dueText, forKey: "dueText")
        managedObject.setValue(item.isPaid, forKey: "isPaid")
        managedObject.setValue(item.copiesToNextMonthAutomatically, forKey: "copiesToNextMonthAutomatically")
        managedObject.setValue(item.notes, forKey: "notes")
    }

    static func plannedItem(from managedObject: NSManagedObject) -> PlannedItem {
        PlannedItem(
            id: managedObject.value(forKey: "id") as? UUID ?? UUID(),
            budgetID: managedObject.value(forKey: "budgetID") as? UUID ?? UUID(),
            accountID: managedObject.value(forKey: "accountID") as? UUID ?? UUID(),
            monthKey: YearMonth(rawValue: managedObject.value(forKey: "monthKey") as? String ?? "") ?? YearMonth(year: 2000, month: 1),
            type: PlannedItemType(rawValue: managedObject.value(forKey: "typeRaw") as? String ?? "") ?? .fixedDebit,
            label: managedObject.value(forKey: "label") as? String ?? "",
            amount: (managedObject.value(forKey: "amount") as? NSDecimalNumber)?.decimalValue ?? 0,
            dueDay: (managedObject.value(forKey: "dueDay") as? NSNumber)?.intValue,
            dueText: managedObject.value(forKey: "dueText") as? String,
            isPaid: managedObject.value(forKey: "isPaid") as? Bool ?? false,
            copiesToNextMonthAutomatically: managedObject.value(forKey: "copiesToNextMonthAutomatically") as? Bool ?? true,
            notes: managedObject.value(forKey: "notes") as? String ?? ""
        )
    }

    static func apply(_ transaction: Transaction, to managedObject: NSManagedObject) {
        managedObject.setValue(transaction.id, forKey: "id")
        managedObject.setValue(transaction.budgetID, forKey: "budgetID")
        managedObject.setValue(transaction.accountID, forKey: "accountID")
        managedObject.setValue(transaction.monthKey, forKey: "monthKey")
        managedObject.setValue(transaction.amount as NSDecimalNumber, forKey: "amount")
        managedObject.setValue(transaction.note, forKey: "note")
    }

    static func transaction(from managedObject: NSManagedObject) -> Transaction {
        Transaction(
            id: managedObject.value(forKey: "id") as? UUID ?? UUID(),
            budgetID: managedObject.value(forKey: "budgetID") as? UUID ?? UUID(),
            accountID: managedObject.value(forKey: "accountID") as? UUID ?? UUID(),
            monthKey: YearMonth(rawValue: managedObject.value(forKey: "monthKey") as? String ?? "") ?? YearMonth(year: 2000, month: 1),
            amount: (managedObject.value(forKey: "amount") as? NSDecimalNumber)?.decimalValue ?? 0,
            note: managedObject.value(forKey: "note") as? String ?? ""
        )
    }
}
