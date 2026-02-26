import Foundation
import SwiftData

enum AccountRole: String, Codable, CaseIterable {
    case regular
    case variable
    case savings
    case other
}

enum AccountType: String, Codable, CaseIterable {
    case current
    case credit
    case savings
    case cash
    case other
}

enum AccountAccessMode: String, Codable, CaseIterable {
    case ownerOnly
    case sharedWithAll
    case sharedWithSome
}

enum StorageScope: String, Codable, CaseIterable {
    case privateScope
    case sharedScope
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
final class Account {
    @Attribute(.unique) var id: UUID
    var name: String
    var role: AccountRole
    var type: AccountType
    var ownerParticipantID: String
    var accessMode: AccountAccessMode
    private var sharedWithParticipantIDsStorage: String
    var storageScope: StorageScope

    init(
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
        self.sharedWithParticipantIDsStorage = Self.encodeParticipantIDs(sharedWithParticipantIDs)
        self.storageScope = storageScope
    }

    var sharedWithParticipantIDs: [String] {
        get { Self.decodeParticipantIDs(sharedWithParticipantIDsStorage) }
        set { sharedWithParticipantIDsStorage = Self.encodeParticipantIDs(newValue) }
    }

    private static func encodeParticipantIDs(_ values: [String]) -> String {
        values.joined(separator: "|")
    }

    private static func decodeParticipantIDs(_ storage: String) -> [String] {
        guard !storage.isEmpty else { return [] }
        return storage.split(separator: "|").map(String.init)
    }
}

@Model
final class PlannedItem {
    @Attribute(.unique) var id: UUID
    var accountID: UUID
    var monthKey: String
    var type: PlannedItemType
    var label: String
    var amount: Decimal
    var dueDay: Int?
    var dueText: String?
    var isPaid: Bool
    var notes: String

    init(
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

    var resolvedMonthKey: YearMonth? {
        YearMonth(rawValue: monthKey)
    }
}

@Model
final class Transaction {
    @Attribute(.unique) var id: UUID
    var accountID: UUID
    var monthKey: String
    var amount: Decimal
    var note: String

    init(
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
