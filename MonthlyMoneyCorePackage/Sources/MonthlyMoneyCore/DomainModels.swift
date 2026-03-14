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
    public var usesSeparateAccountForDailyBudget: Bool = false
    public var dailyBudgetAmount: Decimal = 0
    public var dailyBudgetPaydayDay: Int = 1
    public var dailyBudgetSeparateAccountBalance: Decimal = 0
    public var monthBalancesPayload: String = "{}"

    public init(
        id: UUID = UUID(),
        name: String,
        ownerParticipantID: String,
        sharingState: BudgetSharingState = .local,
        usesSeparateAccountForDailyBudget: Bool = false,
        dailyBudgetAmount: Decimal = 0,
        dailyBudgetPaydayDay: Int = 1,
        dailyBudgetSeparateAccountBalance: Decimal = 0,
        monthBalancesPayload: String = "{}"
    ) {
        self.id = id
        self.name = name
        self.ownerParticipantID = ownerParticipantID
        self.sharingState = sharingState
        self.usesSeparateAccountForDailyBudget = usesSeparateAccountForDailyBudget
        self.dailyBudgetAmount = dailyBudgetAmount
        self.dailyBudgetPaydayDay = dailyBudgetPaydayDay
        self.dailyBudgetSeparateAccountBalance = dailyBudgetSeparateAccountBalance
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
    public var label: String = ""
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
        label: String,
        amount: Decimal,
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
        self.label = label
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
        label: String,
        amount: Decimal,
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
            label: label,
            amount: amount,
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
}

@Model
public final class Transaction {
    public var id: UUID = UUID()
    public var budgetID: UUID = UUID()
    public var accountID: UUID = UUID()
    public var monthKey: String = YearMonth(year: 2000, month: 1).rawValue
    public var amount: Decimal = 0
    public var note: String = ""

    public init(
        id: UUID = UUID(),
        budgetID: UUID = UUID(),
        accountID: UUID,
        monthKey: YearMonth,
        amount: Decimal,
        note: String = ""
    ) {
        self.id = id
        self.budgetID = budgetID
        self.accountID = accountID
        self.monthKey = monthKey.rawValue
        self.amount = amount
        self.note = note
    }
}
