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
    @Attribute(.unique) var id: UUID
    var name: String
    var ownerParticipantID: String
    var sharingState: BudgetSharingState

    init(
        id: UUID = UUID(),
        name: String,
        ownerParticipantID: String,
        sharingState: BudgetSharingState = .local
    ) {
        self.id = id
        self.name = name
        self.ownerParticipantID = ownerParticipantID
        self.sharingState = sharingState
    }
}

@Model
final class Account {
    @Attribute(.unique) var id: UUID
    var budgetID: UUID
    var name: String
    var role: AccountRole
    var type: AccountType
    var ownerParticipantID: String

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
    @Attribute(.unique) var id: UUID
    var budgetID: UUID
    var accountID: UUID
    var monthKey: String
    var type: PlannedItemType
    var label: String
    var amount: Decimal
    var dueDay: Int?
    var dueText: String?
    var isPaid: Bool
    var copiesToNextMonthAutomatically: Bool
    var notes: String

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
    @Attribute(.unique) var id: UUID
    var budgetID: UUID
    var accountID: UUID
    var monthKey: String
    var amount: Decimal
    var note: String

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
