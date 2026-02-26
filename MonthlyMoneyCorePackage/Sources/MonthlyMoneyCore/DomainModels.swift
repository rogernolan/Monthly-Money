import Foundation
import SwiftData

public enum AccountRole: String, Codable, CaseIterable {
    case regular
    case variable
    case savings
    case other
}

public enum AccountType: String, Codable, CaseIterable {
    case current
    case credit
    case savings
    case cash
    case other
}

public enum AccountAccessMode: String, Codable, CaseIterable {
    case ownerOnly
    case sharedWithAll
    case sharedWithSome
}

public enum StorageScope: String, Codable, CaseIterable {
    case privateScope
    case sharedScope
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
public final class Account {
    @Attribute(.unique) public var id: UUID
    public var name: String
    public var role: AccountRole
    public var type: AccountType
    public var ownerParticipantID: String
    public var accessMode: AccountAccessMode
    public var sharedWithParticipantIDs: [String]
    public var storageScope: StorageScope

    public init(
        id: UUID = UUID(),
        name: String,
        role: AccountRole,
        type: AccountType,
        ownerParticipantID: String,
        accessMode: AccountAccessMode = .ownerOnly,
        sharedWithParticipantIDs: [String] = [],
        storageScope: StorageScope = .privateScope
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.type = type
        self.ownerParticipantID = ownerParticipantID
        self.accessMode = accessMode
        self.sharedWithParticipantIDs = sharedWithParticipantIDs
        self.storageScope = storageScope
    }
}

@Model
public final class PlannedItem {
    @Attribute(.unique) public var id: UUID
    public var accountID: UUID
    public var monthKey: String
    public var type: PlannedItemType
    public var label: String
    public var amount: Decimal
    public var dueDay: Int?
    public var dueText: String?
    public var isPaid: Bool
    public var notes: String

    public init(
        id: UUID = UUID(),
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
        self.id = id
        self.accountID = accountID
        self.monthKey = monthKey.rawValue
        self.type = type
        self.label = label
        self.amount = amount
        self.dueDay = dueDay
        self.dueText = dueText
        self.isPaid = isPaid
        self.notes = notes
    }
}

@Model
public final class Transaction {
    @Attribute(.unique) public var id: UUID
    public var accountID: UUID
    public var monthKey: String
    public var amount: Decimal
    public var note: String

    public init(
        id: UUID = UUID(),
        accountID: UUID,
        monthKey: YearMonth,
        amount: Decimal,
        note: String = ""
    ) {
        self.id = id
        self.accountID = accountID
        self.monthKey = monthKey.rawValue
        self.amount = amount
        self.note = note
    }
}
