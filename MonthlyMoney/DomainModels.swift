import Foundation
import SwiftData

enum AccountRole: String, Codable, CaseIterable {
    case regular
    case variable
    case other
}

enum AccountType: String, Codable, CaseIterable {
    case current
    case credit
    case cash
    case other
}

enum BudgetSharingState: String, Codable, CaseIterable {
    case local
    case shared
}

enum PlannedItemType: String, Codable, CaseIterable {
    case fixedDebit
    case credit
    case transfer
}

enum WheelOfMoneyMonth: Int, Codable, CaseIterable {
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

struct YearMonth: Codable, Hashable, Comparable, CustomStringConvertible {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        precondition((1...12).contains(month), "Month must be 1...12")
        self.year = year
        self.month = month
    }

    init?(rawValue: String) {
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

    var rawValue: String {
        String(format: "%04d-%02d", year, month)
    }

    var description: String { rawValue }

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        return lhs.month < rhs.month
    }
}

@Model
final class Budget {
    var id: UUID = UUID()
    var name: String = ""
    var ownerParticipantID: String = ""
    var sharingState: BudgetSharingState = BudgetSharingState.local
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var usesSeparateAccountForDailyBudget: Bool = false
    var dailyBudgetAmount: Decimal = 0
    var dailyBudgetPaydayDay: Int = 1
    var dailyBudgetSeparateAccountBalance: Decimal = 0
    var autoGenerateWoMSavingsEveryMonth: Bool = false
    var monthBalancesPayload: String = "{}"

    init(
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
final class Account {
    var id: UUID = UUID()
    var budgetID: UUID = UUID()
    var name: String = ""
    var role: AccountRole = AccountRole.regular
    var type: AccountType = AccountType.current
    var ownerParticipantID: String = ""

    init(
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
final class PlannedItem {
    var id: UUID = UUID()
    var budgetID: UUID = UUID()
    var accountID: UUID = UUID()
    var monthKey: String = YearMonth(year: 2000, month: 1).rawValue
    var type: PlannedItemType = PlannedItemType.fixedDebit
    var label: String = ""
    var amount: Decimal = 0
    var dueDay: Int?
    var dueText: String?
    var isPaid: Bool = false
    var copiesToNextMonthAutomatically: Bool = true
    var notes: String = ""

    init(
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

    convenience init(
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

    var resolvedMonthKey: YearMonth? {
        YearMonth(rawValue: monthKey)
    }

    static func automaticallyCopiedItems(from items: [PlannedItem]) -> [PlannedItem] {
        items.filter(\.copiesToNextMonthAutomatically)
    }
}

@Model
final class Transaction {
    var id: UUID = UUID()
    var budgetID: UUID = UUID()
    var accountID: UUID = UUID()
    var monthKey: String = YearMonth(year: 2000, month: 1).rawValue
    var amount: Decimal = 0
    var note: String = ""

    init(
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

@Model
final class WheelOfMoneyItem {
    var id: UUID = UUID()
    var budgetID: UUID = UUID()
    var title: String = ""
    var amount: Decimal = 0
    var month: Int = WheelOfMoneyMonth.january.rawValue
    var isPaid: Bool = false
    var notes: String = ""
    var isAutoGeneratedSavingsEntry: Bool = false

    init(
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
