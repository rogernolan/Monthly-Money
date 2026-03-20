import Foundation
import SwiftData

public enum AccountRole: String, Codable, CaseIterable {
    case regular
    case variable
    case other
}

public enum AccountType: String, Codable, CaseIterable {
    case current
    case credit
    case cash
    case other
}

public enum BudgetSharingState: String, Codable, CaseIterable {
    case local
    case shared
}

public enum PlannedItemType: String, Codable, CaseIterable {
    case fixedDebit
    case credit
    case transfer
}

public enum PlannedItemSource: String, Codable, CaseIterable {
    case manual
    case copiedFromPreviousMonth
    case importedUnplanned
}

public enum WheelOfMoneyMonth: Int, Codable, CaseIterable {
    case january = 1
    case february = 2
    case march = 3
    case april = 4
    case may = 5
    case june = 6
    case july = 7
    case august = 8
    case september = 9
    case october = 10
    case november = 11
    case december = 12
}

public struct YearMonth: Codable, Hashable, Comparable, CustomStringConvertible {
    public let year: Int
    public let month: Int

    public init(year: Int, month: Int) {
        precondition((1...12).contains(month), "Month must be 1...12")
        self.year = year
        self.month = month
    }

    public init?(rawValue: String) {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month) else {
            return nil
        }
        self.year = year
        self.month = month
    }

    public var rawValue: String { String(format: "%04d-%02d", year, month) }
    public var description: String { rawValue }

    public static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        lhs.year == rhs.year ? lhs.month < rhs.month : lhs.year < rhs.year
    }
}

@Model
public final class Budget {
    public var id: UUID = UUID()
    public var name: String = ""
    public var ownerParticipantID: String = ""
    public var sharingState: BudgetSharingState = BudgetSharingState.local
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var usesSeparateAccountForDailyBudget: Bool = false
    public var dailyBudgetAmount: Decimal = 0
    public var dailyBudgetPaydayDay: Int = 1
    public var dailyBudgetSeparateAccountBalance: Decimal = 0
    public var autoGenerateWoMSavingsEveryMonth: Bool = false
    public var monthBalancesPayload: String = "{}"

    public init(
        id: UUID = UUID(),
        name: String,
        ownerParticipantID: String,
        sharingState: BudgetSharingState = .local,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        usesSeparateAccountForDailyBudget: Bool = false,
        dailyBudgetAmount: Decimal = 0,
        dailyBudgetPaydayDay: Int = 1,
        dailyBudgetSeparateAccountBalance: Decimal = 0,
        autoGenerateWoMSavingsEveryMonth: Bool = false,
        monthBalancesPayload: String = "{}"
    ) {
        self.id = id
        self.name = name
        self.ownerParticipantID = ownerParticipantID
        self.sharingState = sharingState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.usesSeparateAccountForDailyBudget = usesSeparateAccountForDailyBudget
        self.dailyBudgetAmount = dailyBudgetAmount
        self.dailyBudgetPaydayDay = dailyBudgetPaydayDay
        self.dailyBudgetSeparateAccountBalance = dailyBudgetSeparateAccountBalance
        self.autoGenerateWoMSavingsEveryMonth = autoGenerateWoMSavingsEveryMonth
        self.monthBalancesPayload = monthBalancesPayload
    }
}

@Model
public final class Account {
    public var id: UUID = UUID()
    public var budgetID: UUID = UUID()
    public var name: String = ""
    public var role: AccountRole = AccountRole.regular
    public var type: AccountType = AccountType.current
    public var ownerParticipantID: String = ""

    public init(
        id: UUID = UUID(),
        budgetID: UUID = UUID(),
        name: String,
        role: AccountRole,
        type: AccountType,
        ownerParticipantID: String = ""
    ) {
        self.id = id
        self.budgetID = budgetID
        self.name = name
        self.role = role
        self.type = type
        self.ownerParticipantID = ownerParticipantID
    }
}

@Model
public final class PlannedItem {
    public var id: UUID = UUID()
    public var budgetID: UUID = UUID()
    public var accountID: UUID = UUID()
    public var monthKey: String = YearMonth(year: 2000, month: 1).rawValue
    public var type: PlannedItemType = PlannedItemType.fixedDebit
    public var source: PlannedItemSource = PlannedItemSource.manual
    public var label: String = ""
    public var matchingString: String?
    public var amount: Decimal = 0
    public var dueDay: Int?
    public var dueText: String?
    public var isPaid: Bool = false
    public var copiesToNextMonthAutomatically: Bool = true
    public var notes: String = ""

    public init(
        id: UUID = UUID(),
        budgetID: UUID = UUID(),
        accountID: UUID,
        monthKey: YearMonth,
        type: PlannedItemType,
        source: PlannedItemSource = .manual,
        label: String,
        amount: Decimal,
        matchingString: String? = nil,
        dueDay: Int? = nil,
        dueText: String? = nil,
        isPaid: Bool = false,
        copiesToNextMonthAutomatically: Bool = true,
        notes: String = ""
    ) {
        self.id = id
        self.budgetID = budgetID
        self.accountID = accountID
        self.monthKey = monthKey.rawValue
        self.type = type
        self.source = source
        self.label = label
        self.matchingString = matchingString
        self.amount = amount
        self.dueDay = dueDay
        self.dueText = dueText
        self.isPaid = isPaid
        self.copiesToNextMonthAutomatically = copiesToNextMonthAutomatically
        self.notes = notes
    }

    public convenience init(
        id: UUID = UUID(),
        budgetID: UUID = UUID(),
        accountID: UUID,
        monthKey: YearMonth,
        type: PlannedItemType,
        source: PlannedItemSource = .manual,
        label: String,
        amount: Decimal,
        matchingString: String? = nil,
        dueDay: Int? = nil,
        dueText: String? = nil,
        isPaid: Bool = false,
        notes: String = ""
    ) {
        self.init(
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
            copiesToNextMonthAutomatically: true,
            notes: notes
        )
    }

    public static func automaticallyCopiedItems(from items: [PlannedItem]) -> [PlannedItem] {
        items.filter(\.copiesToNextMonthAutomatically)
    }

    public static func copied(from item: PlannedItem, into monthKey: YearMonth) -> PlannedItem {
        PlannedItem(
            id: UUID(),
            budgetID: item.budgetID,
            accountID: item.accountID,
            monthKey: monthKey,
            type: item.type,
            source: .copiedFromPreviousMonth,
            label: item.label,
            amount: item.amount,
            matchingString: item.matchingString,
            dueDay: item.dueDay,
            dueText: item.dueText,
            isPaid: false,
            copiesToNextMonthAutomatically: item.copiesToNextMonthAutomatically,
            notes: item.notes
        )
    }
}

@Model
public final class Transaction {
    public var id: UUID = UUID()
    public var budgetID: UUID = UUID()
    public var accountID: UUID = UUID()
    public var monthKey: String = YearMonth(year: 2000, month: 1).rawValue
    public var amount: Decimal = 0
    public var note: String = ""
    public var sourceKind: String = ""
    public var sourceExternalTransactionID: String = ""
    public var sourcePostedAt: Date?

    public init(
        id: UUID = UUID(),
        budgetID: UUID = UUID(),
        accountID: UUID,
        monthKey: YearMonth,
        amount: Decimal,
        note: String = "",
        sourceKind: String = "",
        sourceExternalTransactionID: String = "",
        sourcePostedAt: Date? = nil
    ) {
        self.id = id
        self.budgetID = budgetID
        self.accountID = accountID
        self.monthKey = monthKey.rawValue
        self.amount = amount
        self.note = note
        self.sourceKind = sourceKind
        self.sourceExternalTransactionID = sourceExternalTransactionID
        self.sourcePostedAt = sourcePostedAt
    }
}

@Model
public final class ImportedTransactionRecord {
    public var id: UUID = UUID()
    public var budgetID: UUID = UUID()
    public var accountID: UUID = UUID()
    public var sourceKind: String = ""
    public var sourceAccountIdentifier: String = ""
    public var externalTransactionID: String = ""
    public var postedAt: Date = Date()
    public var amount: Decimal = 0
    public var payee: String = ""
    public var transactionType: String = ""
    public var rawSourcePayload: String = ""
    public var importedAt: Date = Date()
    public var appliedPlannedItemID: UUID?
    public var createdTransactionID: UUID?

    public init(
        id: UUID = UUID(),
        budgetID: UUID = UUID(),
        accountID: UUID,
        sourceKind: String,
        sourceAccountIdentifier: String,
        externalTransactionID: String,
        postedAt: Date,
        amount: Decimal,
        payee: String,
        transactionType: String,
        rawSourcePayload: String,
        importedAt: Date = Date(),
        appliedPlannedItemID: UUID? = nil,
        createdTransactionID: UUID? = nil
    ) {
        self.id = id
        self.budgetID = budgetID
        self.accountID = accountID
        self.sourceKind = sourceKind
        self.sourceAccountIdentifier = sourceAccountIdentifier
        self.externalTransactionID = externalTransactionID
        self.postedAt = postedAt
        self.amount = amount
        self.payee = payee
        self.transactionType = transactionType
        self.rawSourcePayload = rawSourcePayload
        self.importedAt = importedAt
        self.appliedPlannedItemID = appliedPlannedItemID
        self.createdTransactionID = createdTransactionID
    }
}

@Model
public final class WheelOfMoneyItem {
    public var id: UUID = UUID()
    public var budgetID: UUID = UUID()
    public var title: String = ""
    public var amount: Decimal = 0
    public var month: Int = WheelOfMoneyMonth.january.rawValue
    public var isPaid: Bool = false
    public var notes: String = ""
    public var isAutoGeneratedSavingsEntry: Bool = false

    public init(
        id: UUID = UUID(),
        budgetID: UUID,
        title: String,
        amount: Decimal,
        month: Int,
        isPaid: Bool = false,
        notes: String = "",
        isAutoGeneratedSavingsEntry: Bool = false
    ) {
        self.id = id
        self.budgetID = budgetID
        self.title = title
        self.amount = amount
        self.month = month
        self.isPaid = isPaid
        self.notes = notes
        self.isAutoGeneratedSavingsEntry = isAutoGeneratedSavingsEntry
    }
}
