import Foundation
import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {
    @Published var selectedMonth: YearMonth
    @Published var viewScope: ViewScope = .myView

    @Published var openingBalances: [String: Decimal] = [:]
    @Published var primaryBankBalances: [String: Decimal] = [:]

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
            if try repository.accounts(for: .myView).isEmpty {
                let account = try repository.createAccount(
                    name: "Main Current",
                    role: .regular,
                    type: .current,
                    ownerParticipantID: "owner"
                )
                try repository.createPlannedItem(
                    PlannedItem(accountID: account.id, monthKey: selectedMonth, type: .fixedDebit, label: "Rent", amount: 1200, dueDay: 1),
                    in: .privateScope
                )
                try repository.createPlannedItem(
                    PlannedItem(accountID: account.id, monthKey: selectedMonth, type: .credit, label: "Salary", amount: 2600, dueDay: 25),
                    in: .privateScope
                )
                try repository.createPlannedItem(
                    PlannedItem(accountID: account.id, monthKey: selectedMonth, type: .transfer, label: "Living expenses", amount: 1500, dueText: "Daily"),
                    in: .privateScope
                )
            }
            try refresh()
        } catch {
            print("Bootstrap failed: \(error)")
        }
    }

    func refresh() throws {
        monthItems = try repository.plannedItems(for: selectedMonth, scope: viewScope)
    }

    var openingBalance: Decimal {
        get { openingBalances[selectedMonth.rawValue] ?? 0 }
        set { openingBalances[selectedMonth.rawValue] = newValue }
    }

    var primaryBankBalance: Decimal {
        get { primaryBankBalances[selectedMonth.rawValue] ?? 0 }
        set { primaryBankBalances[selectedMonth.rawValue] = newValue }
    }

    var monthTotals: MonthTotals {
        MonthCalculationEngine.calculate(
            items: monthItems,
            openingBalance: openingBalance,
            livingBuffer: livingBuffer,
            weeklyEstimate: weeklyEstimate,
            weekendEstimate: weekendEstimate,
            minSuggestedLiving: minSuggestedLiving,
            yearMonth: selectedMonth
        )
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
            let accounts = try repository.accounts(for: .myView)
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

    func update(item: PlannedItem, label: String, amount: Decimal, dueDay: Int?, dueText: String?, notes: String) {
        item.label = label
        item.amount = amount
        item.dueDay = dueDay
        item.dueText = dueText
        item.notes = notes
        do {
            try repository.savePlannedItem(item)
            try refresh()
        } catch {
            print("Edit failed: \(error)")
        }
    }

    func shiftMonth(by delta: Int) {
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

    static func currency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "GBP"
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }
}
