import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var selectedMonth: YearMonth

    @Published var openingBalances: [String: Decimal] = [:]
    @Published var primaryBankBalances: [String: Decimal] = [:]
    @Published var primaryBankName: String = "Primary bank"

    @Published var weeklyEstimate: Decimal = 350
    @Published var weekendEstimate: Decimal = 20
    @Published var minSuggestedLiving: Decimal = 1500
    @Published var livingBuffer: Decimal = 100

    @Published var includeCash = true
    @Published var includeFX = true
    @Published var cashBalance: Decimal = 0
    @Published var fxBalance: Decimal = 0
    @Published var paydayDay: Int = 1

    @Published var monthItems: [PlannedItem] = []

    private let repository: AccountRepository

    init(repository: AccountRepository) {
        self.repository = repository
        let now = Date()
        let calendar = Calendar.current
        self.selectedMonth = YearMonth(
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now)
        )
    }

    func bootstrapIfNeeded() async {
        do {
            if try repository.accounts().isEmpty {
                let account = try repository.createAccount(
                    name: "Nationwide",
                    role: .regular,
                    type: .current,
                    ownerParticipantID: "owner"
                )
                primaryBankBalances[selectedMonth.rawValue] = 397
                try seedDefaultsFromSheet(accountID: account.id, month: selectedMonth)
                try ensureNextMonthCopiedFromCurrent(accountID: account.id)
            } else if let account = try repository.accounts().first {
                try ensureCurrentMonthHasSeedData(accountID: account.id)
                try ensureNextMonthCopiedFromCurrent(accountID: account.id)
            }
            try refresh()
        } catch {
            print("Bootstrap failed: \(error)")
        }
    }

    func refresh() throws {
        monthItems = try repository.plannedItems(for: selectedMonth)
        if let firstAccount = try repository.accounts().first {
            primaryBankName = firstAccount.name
        } else {
            primaryBankName = "Primary bank"
        }
    }

    var openingBalance: Decimal {
        get { effectiveOpeningBalance(for: selectedMonth) }
        set { openingBalances[selectedMonth.rawValue] = newValue }
    }

    var primaryBankBalance: Decimal {
        get { primaryBankBalances[selectedMonth.rawValue] ?? 0 }
        set { primaryBankBalances[selectedMonth.rawValue] = newValue }
    }

    var monthTotals: MonthTotals {
        MonthCalculationEngine.calculate(
            items: monthItems,
            openingBalance: effectiveOpeningBalance(for: selectedMonth),
            livingBuffer: livingBuffer,
            weeklyEstimate: weeklyEstimate,
            weekendEstimate: weekendEstimate,
            minSuggestedLiving: minSuggestedLiving,
            yearMonth: selectedMonth
        )
    }

    var projectedBalanceFromCurrentBalance: Decimal {
        let base = isSelectedMonthInFuture ? openingBalance : primaryBankBalance
        return base - monthTotals.netOutgoingsDue
    }

    var isSelectedMonthInFuture: Bool {
        selectedMonth > currentYearMonth
    }

    var isSelectedMonthInPast: Bool {
        selectedMonth < currentYearMonth
    }

    var canNavigateToNextMonth: Bool {
        !monthItems.isEmpty
    }

    var canPopulateSelectedMonthFromPrevious: Bool {
        !isSelectedMonthInPast && monthItems.isEmpty
    }

    var fundsTotal: Decimal {
        var result = primaryBankBalance
        if includeCash { result += cashBalance }
        if includeFX { result += fxBalance }
        return result
    }

    var daysRemainingInMonth: Int {
        var comps = DateComponents()
        comps.year = selectedMonth.year
        comps.month = selectedMonth.month
        comps.day = 1
        let calendar = Calendar.current
        guard let start = calendar.date(from: comps),
              let range = calendar.range(of: .day, in: .month, for: start) else {
            return 1
        }

        let today = Date()
        let currentDay = calendar.component(.day, from: today)
        let total = range.count
        if calendar.component(.year, from: today) == selectedMonth.year,
           calendar.component(.month, from: today) == selectedMonth.month {
            return max(1, total - currentDay + 1)
        }
        return total
    }

    var currentDailyAverage: Decimal {
        fundsTotal / Decimal(daysRemainingInMonth)
    }

    var aheadBehind: Decimal {
        fundsTotal - monthTotals.suggestedLiving
    }

    var weeksReckoner: Decimal {
        MonthCalculationEngine.monthlyBudgetFromWeekModel(
            year: selectedMonth.year,
            month: selectedMonth.month,
            weeklyEstimate: weeklyEstimate,
            weekendEstimate: weekendEstimate
        )
    }

    func setPaid(item: PlannedItem, paid: Bool) {
        item.isPaid = paid
        do {
            try repository.savePlannedItem(item)
            try refresh()
        } catch {
            print("Failed setPaid: \(error)")
        }
    }

    func delete(item: PlannedItem) {
        do {
            try repository.deletePlannedItem(id: item.id)
            try refresh()
        } catch {
            print("Delete failed: \(error)")
        }
    }

    func duplicate(item: PlannedItem) {
        let copy = PlannedItem(
            accountID: item.accountID,
            monthKey: selectedMonth,
            type: item.type,
            label: item.label,
            amount: item.amount,
            dueDay: item.dueDay,
            dueText: item.dueText,
            isPaid: false,
            notes: item.notes
        )
        do {
            try repository.savePlannedItem(copy)
            try refresh()
        } catch {
            print("Duplicate failed: \(error)")
        }
    }

    func copy(item: PlannedItem, to month: YearMonth) {
        let copy = PlannedItem(
            accountID: item.accountID,
            monthKey: month,
            type: item.type,
            label: item.label,
            amount: item.amount,
            dueDay: item.dueDay,
            dueText: item.dueText,
            isPaid: false,
            notes: item.notes
        )
        do {
            try repository.savePlannedItem(copy)
            try refresh()
        } catch {
            print("Copy failed: \(error)")
        }
    }

    func setLivingExpensesToSuggested() {
        let suggested = monthTotals.suggestedLiving
        if let living = monthItems.first(where: { $0.type == .transfer && $0.label.lowercased().contains("living") }) {
            living.amount = suggested
            do {
                try repository.savePlannedItem(living)
                try refresh()
                return
            } catch {
                print("Update living failed: \(error)")
            }
        }

        do {
            let accounts = try repository.accounts()
            guard let account = accounts.first else { return }
            let item = PlannedItem(
                accountID: account.id,
                monthKey: selectedMonth,
                type: .transfer,
                label: "Living expenses",
                amount: suggested,
                dueText: "Daily"
            )
            try repository.savePlannedItem(item)
            try refresh()
        } catch {
            print("Create living failed: \(error)")
        }
    }

    func update(item: PlannedItem, label: String, amount: Decimal, dueDay: Int?, dueText: String?, type: PlannedItemType, notes: String) {
        item.label = label
        item.amount = amount
        item.dueDay = dueDay
        item.dueText = dueText
        item.type = type
        item.notes = notes
        do {
            try repository.savePlannedItem(item)
            try refresh()
        } catch {
            print("Edit failed: \(error)")
        }
    }

    @discardableResult
    func createEntry(type: PlannedItemType, label: String = "", amount: Decimal = 0, dueDay: Int?, notes: String = "") -> PlannedItem? {
        do {
            let accounts = try repository.accounts()
            guard let account = accounts.first else { return nil }

            let item = PlannedItem(
                accountID: account.id,
                monthKey: selectedMonth,
                type: type,
                label: label,
                amount: amount,
                dueDay: dueDay,
                dueText: nil,
                isPaid: false,
                notes: notes
            )
            try repository.createPlannedItem(item)
            try refresh()
            return item
        } catch {
            print("Create entry failed: \(error)")
            return nil
        }
    }

    func shiftMonth(by delta: Int) {
        guard delta <= 0 || canNavigateToNextMonth else { return }
        var year = selectedMonth.year
        var month = selectedMonth.month + delta
        while month < 1 { month += 12; year -= 1 }
        while month > 12 { month -= 12; year += 1 }
        selectedMonth = YearMonth(year: year, month: month)
        do {
            try refresh()
        } catch {
            print("Refresh failed: \(error)")
        }
    }

    func populateSelectedMonthFromPrevious() {
        guard canPopulateSelectedMonthFromPrevious else { return }

        do {
            let sourceItems = try repository.plannedItems(for: previousMonth(of: selectedMonth))
            guard !sourceItems.isEmpty else { return }
            try copyItems(sourceItems, to: selectedMonth)
            try refresh()
        } catch {
            print("Populate month failed: \(error)")
        }
    }

    static func currency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "GBP"
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private var currentYearMonth: YearMonth {
        let now = Date()
        let calendar = Calendar.current
        return YearMonth(
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now)
        )
    }

    private func effectiveOpeningBalance(for month: YearMonth) -> Decimal {
        if month <= currentYearMonth {
            return openingBalances[month.rawValue] ?? 0
        }
        return closingBalance(for: previousMonth(of: month))
    }

    private func closingBalance(for month: YearMonth) -> Decimal {
        let balanceBasis: Decimal
        if month <= currentYearMonth {
            balanceBasis = primaryBankBalances[month.rawValue] ?? openingBalances[month.rawValue] ?? 0
        } else {
            balanceBasis = effectiveOpeningBalance(for: month)
        }

        let items: [PlannedItem]
        if month == selectedMonth {
            items = monthItems
        } else {
            items = (try? repository.plannedItems(for: month)) ?? []
        }
        return balanceBasis - MonthCalculationEngine.netOutgoingsDue(from: items)
    }

    private func previousMonth(of month: YearMonth) -> YearMonth {
        var year = month.year
        var value = month.month - 1
        if value < 1 {
            value = 12
            year -= 1
        }
        return YearMonth(year: year, month: value)
    }

    private func nextMonth(of month: YearMonth) -> YearMonth {
        var year = month.year
        var value = month.month + 1
        if value > 12 {
            value = 1
            year += 1
        }
        return YearMonth(year: year, month: value)
    }

    private func ensureCurrentMonthHasSeedData(accountID: UUID) throws {
        let current = currentYearMonth
        let currentItems = try repository.plannedItems(for: current)
            .filter { $0.accountID == accountID }
        guard currentItems.isEmpty else { return }

        let previous = previousMonth(of: current)
        let previousItems = try repository.plannedItems(for: previous)
            .filter { $0.accountID == accountID }

        if previousItems.isEmpty {
            selectedMonth = current
            try seedDefaultsFromSheet(accountID: accountID, month: current)
            return
        }

        try copyItems(previousItems, to: current)
    }

    private func ensureNextMonthCopiedFromCurrent(accountID: UUID) throws {
        let current = currentYearMonth
        let next = nextMonth(of: current)

        let nextItems = try repository.plannedItems(for: next)
            .filter { $0.accountID == accountID }
        guard nextItems.isEmpty else { return }

        let currentItems = try repository.plannedItems(for: current)
            .filter { $0.accountID == accountID }
        guard !currentItems.isEmpty else { return }

        try copyItems(currentItems, to: next)
    }

    private func copyItems(_ sourceItems: [PlannedItem], to month: YearMonth) throws {
        for source in sourceItems {
            let copy = PlannedItem(
                accountID: source.accountID,
                monthKey: month,
                type: source.type,
                label: source.label,
                amount: source.amount,
                dueDay: source.dueDay,
                dueText: source.dueText,
                isPaid: false,
                notes: source.notes
            )
            try repository.createPlannedItem(copy)
        }
    }

    private func seedDefaultsFromSheet(accountID: UUID, month: YearMonth) throws {
        func money(_ value: String) -> Decimal {
            Decimal(string: value) ?? 0
        }

        let febDebitDefaults: [(label: String, dueDay: Int?, amount: Decimal, isPaid: Bool, notes: String)] = [
            ("Sky", nil, money("29"), true, ""),
            ("Savings standing order", nil, money("200"), true, ""),
            ("Bank fees", 1, money("13"), true, ""),
            ("Council tax", 1, money("347"), true, "Not Feb and march"),
            ("Novagas", 3, money("200"), true, ""),
            ("EE mobile", 3, money("39"), true, ""),
            ("Apple media etc", 4, money("32.95"), true, ""),
            ("PDSA", 4, money("10"), true, ""),
            ("Octopus Electricity", 6, money("90"), true, ""),
            ("Gardener 1", 7, money("40"), true, ""),
            ("Water", 7, money("26"), true, ""),
            ("Guide Dogs", 8, money("17"), true, ""),
            ("Petrol", 11, money("120"), true, "Diesel"),
            ("BT Broadband", 13, money("32.99"), true, ""),
            ("ManyPets Flynnsurance", 13, money("68"), true, ""),
            ("Peloton membership", 18, money("40"), false, ""),
            ("Dogfood", 8, money("110"), false, ""),
            ("Gardener 2", 21, money("40"), false, "")
        ]

        let febCreditDefaults: [(label: String, amount: Decimal, isPaid: Bool)] = [
            ("Salary J", money("1047.59"), true),
            ("Salary R", money("1047.588"), true),
            ("From savings", money("2500"), true),
            ("Pension", money("0"), false)
        ]

        let febTransferDefaults: [(label: String, dueDay: Int?, amount: Decimal, isPaid: Bool, notes: String)] = [
            ("Living expenses", nil, money("2500"), true, "Transfer to joint Monzo"),
            ("Jane pocket money", 1, money("200"), true, ""),
            ("Rog pocket money", 1, money("200"), true, ""),
            ("To savings", nil, money("0"), false, ""),
            ("Credit card", 1, money("0"), false, "Paid from savings")
        ]

        let january = previousMonth(of: month)
        primaryBankBalances[january.rawValue] = 575

        let janDebitDefaults: [(label: String, dueDay: Int?, amount: Decimal, isPaid: Bool, notes: String)] = [
            ("Sky", nil, money("29"), true, ""),
            ("Dogfood", 8, money("110"), true, ""),
            ("Bank fees", 1, money("13"), true, ""),
            ("Council tax", 1, money("347"), true, "Not Feb and march"),
            ("Savings standing order", nil, money("200"), true, ""),
            ("Novagas", 3, money("200"), true, ""),
            ("EE mobile", 3, money("39"), true, ""),
            ("Apple media etc", 4, money("32.95"), true, ""),
            ("PDSA", 4, money("10"), true, ""),
            ("Peloton membership", 5, money("40"), true, ""),
            ("Octopus Electricity", 6, money("90"), true, ""),
            ("Gardener 1", 7, money("40"), true, ""),
            ("Water", 7, money("26"), true, ""),
            ("Guide Dogs", 8, money("17"), true, ""),
            ("Petrol", 11, money("120"), true, "Diesel"),
            ("Gardener 2", 21, money("40"), false, ""),
            ("BT Broadband", 13, money("32.99"), false, ""),
            ("ManyPets Flynnsurance", 13, money("70"), false, "")
        ]

        let janCreditDefaults: [(label: String, amount: Decimal, isPaid: Bool)] = [
            ("Salary J", money("1047.59"), true),
            ("Salary R", money("1047.588"), true),
            ("From savings", money("2500"), true),
            ("Pension", money("0"), false)
        ]

        let janTransferDefaults: [(label: String, dueDay: Int?, amount: Decimal, isPaid: Bool, notes: String)] = [
            ("Living expenses", nil, money("2000"), true, "Transfer to joint Monzo"),
            ("Jane pocket money", 1, money("200"), true, ""),
            ("Rog pocket money", 1, money("200"), true, ""),
            ("To savings", nil, money("0"), false, ""),
            ("Credit card", 1, money("0"), false, "Paid from savings")
        ]

        try seedPlannedItems(accountID: accountID, month: month, debits: febDebitDefaults, credits: febCreditDefaults, transfers: febTransferDefaults)
        try seedPlannedItems(accountID: accountID, month: january, debits: janDebitDefaults, credits: janCreditDefaults, transfers: janTransferDefaults)
    }

    private func seedPlannedItems(
        accountID: UUID,
        month: YearMonth,
        debits: [(label: String, dueDay: Int?, amount: Decimal, isPaid: Bool, notes: String)],
        credits: [(label: String, amount: Decimal, isPaid: Bool)],
        transfers: [(label: String, dueDay: Int?, amount: Decimal, isPaid: Bool, notes: String)]
    ) throws {
        for item in debits {
            try repository.createPlannedItem(
                PlannedItem(
                    accountID: accountID,
                    monthKey: month,
                    type: .fixedDebit,
                    label: item.label,
                    amount: item.amount,
                    dueDay: item.dueDay,
                    isPaid: item.isPaid,
                    notes: item.notes
                )
            )
        }

        for item in credits {
            try repository.createPlannedItem(
                PlannedItem(
                    accountID: accountID,
                    monthKey: month,
                    type: .credit,
                    label: item.label,
                    amount: item.amount,
                    isPaid: item.isPaid
                )
            )
        }

        for item in transfers {
            try repository.createPlannedItem(
                PlannedItem(
                    accountID: accountID,
                    monthKey: month,
                    type: .transfer,
                    label: item.label,
                    amount: item.amount,
                    dueDay: item.dueDay,
                    isPaid: item.isPaid,
                    notes: item.notes
                )
            )
        }
    }
}
