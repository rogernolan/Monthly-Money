import Foundation

struct WheelOfMoneyItemEditorDraft {
    var title: String
    var amountText: String
    var month: Int
    var notes: String

    init(item: WheelOfMoneyItem) {
        title = item.title
        amountText = NSDecimalNumber(decimal: item.amount).stringValue
        month = item.month
        notes = item.notes
    }

    init() {
        title = ""
        amountText = "0"
        month = WheelOfMoneyMonth.january.rawValue
        notes = ""
    }

    var amount: Decimal {
        Decimal(string: amountText, locale: Locale.current) ?? 0
    }

    var canSave: Bool {
        !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && amount > 0
    }
}
