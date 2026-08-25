import Foundation

enum MonthEntryKind: String, CaseIterable, Identifiable, Equatable {
    case debit
    case credit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .debit:
            return "Debit"
        case .credit:
            return "Credit"
        }
    }
}

enum MonthDueSelection: Hashable {
    case floating
    case everyNDays
    case day(Int)

    init(_ day: Int?) {
        if let day {
            self = .day(day)
        } else {
            self = .floating
        }
    }

    var value: Int? {
        switch self {
        case .floating:
            return nil
        case .everyNDays:
            return nil
        case .day(let day):
            return day
        }
    }
}

struct MonthItemEditorDraft {
    var label: String
    var matchingString: String
    var entryKind: MonthEntryKind
    var amountText: String
    var dueSelection: MonthDueSelection
    var repeatDaysText: String
    var isPlanned: Bool
    var copiesToNextMonthAutomatically: Bool
    var notes: String

    init(item: PlannedItem) {
        label = item.label
        matchingString = item.matchingString ?? ""
        entryKind = item.type == .credit ? .credit : .debit
        amountText = NSDecimalNumber(decimal: item.amount).stringValue
        dueSelection = item.repeatDays.map { _ in .everyNDays } ?? MonthDueSelection(item.dueDay)
        repeatDaysText = item.repeatDays.map(String.init) ?? ""
        isPlanned = item.source != .importedUnplanned
        copiesToNextMonthAutomatically = item.copiesToNextMonthAutomatically
        notes = item.notes
    }

    init(newType: PlannedItemType, dueDay: Int?) {
        label = ""
        matchingString = ""
        entryKind = newType == .credit ? .credit : .debit
        amountText = "0"
        dueSelection = MonthDueSelection(dueDay)
        repeatDaysText = ""
        isPlanned = true
        copiesToNextMonthAutomatically = true
        notes = ""
    }

    var canSave: Bool {
        !label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
            (dueSelection != .everyNDays || repeatDaysAreValid)
    }

    var amount: Decimal {
        Decimal(string: amountText, locale: Locale.current) ?? 0
    }

    var repeatDays: Int? {
        guard dueSelection == .everyNDays,
              repeatDaysText.allSatisfy(\.isNumber),
              let value = Int(repeatDaysText),
              value > 0 else {
            return nil
        }
        return value
    }

    var repeatDaysAreValid: Bool {
        repeatDays != nil
    }

    mutating func normalizeAmountInput(locale: Locale = .current) {
        guard let parsed = Decimal(string: amountText, locale: locale), parsed < 0 else { return }
        entryKind = .debit
        amountText = NSDecimalNumber(decimal: absDecimal(parsed)).stringValue
    }

    func resolvedType(existingItemType: PlannedItemType? = nil) -> PlannedItemType {
        switch entryKind {
        case .credit:
            return .credit
        case .debit:
            return existingItemType == .transfer ? .transfer : .fixedDebit
        }
    }

    private func absDecimal(_ value: Decimal) -> Decimal {
        value < 0 ? -value : value
    }
}
