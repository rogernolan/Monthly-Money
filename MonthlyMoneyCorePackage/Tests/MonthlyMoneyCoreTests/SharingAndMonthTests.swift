import XCTest
@testable import MonthlyMoneyCore

final class SharingAndMonthTests: XCTestCase {
    func testLocalBudgetDefaults() {
        let budget = Budget(name: "Home", ownerParticipantID: "owner")
        let account = Account(budgetID: budget.id, name: "Current", role: .regular, type: .current)
        let month = YearMonth(year: 2026, month: 2)
        let item = PlannedItem(budgetID: budget.id, accountID: account.id, monthKey: month, type: .fixedDebit, label: "Rent", amount: 1200)
        let transaction = Transaction(budgetID: budget.id, accountID: account.id, monthKey: month, amount: 10)

        XCTAssertEqual(budget.sharingState, .local)
        XCTAssertEqual(account.budgetID, budget.id)
        XCTAssertEqual(item.budgetID, budget.id)
        XCTAssertEqual(transaction.budgetID, budget.id)
    }

    func testNewAccountsAttachToActiveLocalBudget() throws {
        let repository = makeRepository()
        let account = try repository.createAccount(name: "Current", role: .regular, type: .current, ownerParticipantID: "owner")
        XCTAssertEqual(account.budgetID, try repository.activeBudget()?.id)
        XCTAssertEqual(try repository.activeBudget()?.sharingState, .local)
    }

    func testShareBudgetMigratesWholeBudgetAndPreservesTotals() throws {
        let privateStore = InMemoryAccountDataStore()
        let sharedStore = InMemoryAccountDataStore()
        let repository = AccountRepository(privateStore: privateStore, sharedStore: sharedStore)
        let account = try repository.createAccount(name: "Bills", role: .regular, type: .current, ownerParticipantID: "owner")
        let month = YearMonth(year: 2026, month: 2)
        try repository.createPlannedItem(PlannedItem(accountID: account.id, monthKey: month, type: .fixedDebit, label: "Rent", amount: 1200))
        try repository.createPlannedItem(PlannedItem(accountID: account.id, monthKey: month, type: .credit, label: "Salary", amount: 2500))
        try repository.createTransaction(Transaction(accountID: account.id, monthKey: month, amount: 100, note: "Stub"))

        let before = try repository.plannedItems(for: month)
        let beforeTotals = MonthCalculationEngine.calculate(items: before, openingBalance: 1000, livingBuffer: 100, weeklyEstimate: 100, weekendEstimate: 10, minSuggestedLiving: 1500, yearMonth: month)

        let service = BudgetSharingService(repository: repository)
        let sharedBudget = try service.shareBudget(participantsSelection: ["p2"])

        XCTAssertEqual(sharedBudget.sharingState, .shared)
        XCTAssertEqual(try repository.activeBudget()?.id, sharedBudget.id)
        XCTAssertTrue(try privateStore.fetchBudgets().isEmpty)
        XCTAssertTrue(try privateStore.fetchAccounts().isEmpty)
        XCTAssertTrue(try privateStore.fetchPlannedItems(accountIDs: [account.id], monthKey: nil).isEmpty)
        XCTAssertTrue(try privateStore.fetchTransactions(accountIDs: [account.id]).isEmpty)
        XCTAssertEqual(try sharedStore.fetchBudgets().map(\.id), [sharedBudget.id])
        XCTAssertEqual(try sharedStore.fetchAccounts().map(\.id), [account.id])
        XCTAssertEqual(try sharedStore.fetchPlannedItems(accountIDs: [account.id], monthKey: month).count, 2)
        XCTAssertEqual(try sharedStore.fetchTransactions(accountIDs: [account.id]).count, 1)

        let after = try repository.plannedItems(for: month)
        let afterTotals = MonthCalculationEngine.calculate(items: after, openingBalance: 1000, livingBuffer: 100, weeklyEstimate: 100, weekendEstimate: 10, minSuggestedLiving: 1500, yearMonth: month)
        XCTAssertEqual(beforeTotals, afterTotals)
    }

    func testActiveBudgetScope() throws {
        let privateStore = InMemoryAccountDataStore()
        let sharedStore = InMemoryAccountDataStore()

        let localBudget = Budget(name: "Local", ownerParticipantID: "owner", sharingState: .local)
        let sharedBudget = Budget(name: "Shared", ownerParticipantID: "owner", sharingState: .shared)
        try privateStore.upsertBudget(localBudget)
        try sharedStore.upsertBudget(sharedBudget)

        let localAccount = Account(budgetID: localBudget.id, name: "Current", role: .regular, type: .current)
        let sharedAccount = Account(budgetID: sharedBudget.id, name: "Joint", role: .regular, type: .current)
        try privateStore.upsertAccount(localAccount)
        try sharedStore.upsertAccount(sharedAccount)

        let month = YearMonth(year: 2026, month: 2)
        try privateStore.upsertPlannedItems([
            PlannedItem(budgetID: localBudget.id, accountID: localAccount.id, monthKey: month, type: .fixedDebit, label: "Rent", amount: 1200)
        ])
        try sharedStore.upsertPlannedItems([
            PlannedItem(budgetID: sharedBudget.id, accountID: sharedAccount.id, monthKey: month, type: .fixedDebit, label: "Shared Rent", amount: 800)
        ])

        let repository = AccountRepository(privateStore: privateStore, sharedStore: sharedStore)

        XCTAssertEqual(try repository.activeBudget()?.id, localBudget.id)
        XCTAssertEqual(try repository.accounts().map(\.id), [localAccount.id])
        XCTAssertEqual(try repository.plannedItems(for: month).map(\.accountID), [localAccount.id])
    }

    func testShareBudgetRejectsAlreadySharedBudget() throws {
        let repository = makeRepository()
        _ = try repository.createAccount(name: "Current", role: .regular, type: .current, ownerParticipantID: "owner")

        let service = BudgetSharingService(repository: repository)
        _ = try service.shareBudget(participantsSelection: [])

        XCTAssertThrowsError(try service.shareBudget(participantsSelection: [])) { error in
            XCTAssertEqual(error as? BudgetSharingError, .reverseMigrationNotSupported)
        }
    }

    func testMonthCalculationDeterministicBudgetAndSuggestedLiving() {
        XCTAssertEqual(
            MonthCalculationEngine.monthlyBudgetFromWeekModel(year: 2026, month: 2, weeklyEstimate: 100, weekendEstimate: 10),
            480
        )
        XCTAssertEqual(
            MonthCalculationEngine.suggestedLiving(projectedNetCredit: 900, livingBuffer: 200, monthlyBudgetFromWeekModel: 650, minSuggestedLiving: 250),
            650
        )
    }

    func testProjectedBalanceMatchesDueTotalsArithmetic() {
        let month = YearMonth(year: 2026, month: 2)
        let accountID = UUID()
        let items = [
            PlannedItem(accountID: accountID, monthKey: month, type: .fixedDebit, label: "Rent", amount: 1200, isPaid: false),
            PlannedItem(accountID: accountID, monthKey: month, type: .transfer, label: "Living expenses", amount: 500, isPaid: false),
            PlannedItem(accountID: accountID, monthKey: month, type: .credit, label: "Salary", amount: 2000, isPaid: false)
        ]

        let openingBalance: Decimal = 1000
        let totals = MonthCalculationEngine.calculate(
            items: items,
            openingBalance: openingBalance,
            livingBuffer: 100,
            weeklyEstimate: 100,
            weekendEstimate: 10,
            minSuggestedLiving: 250,
            yearMonth: month
        )

        XCTAssertEqual(totals.netOutgoingsDue, -300)
        XCTAssertEqual(totals.projectedBalance, openingBalance - totals.netOutgoingsDue)
        XCTAssertEqual(totals.projectedBalance, 1300)
    }

    func testDeletingCurrentMonthItemDoesNotDeleteMatchingItemInNextMonth() throws {
        let repository = makeRepository()
        let account = try repository.createAccount(name: "Bills", role: .regular, type: .current, ownerParticipantID: "owner")
        let current = YearMonth(year: 2026, month: 3)
        let next = YearMonth(year: 2026, month: 4)

        let currentItem = PlannedItem(
            accountID: account.id,
            monthKey: current,
            type: .fixedDebit,
            label: "Rent",
            amount: 1200,
            dueDay: 1,
            isPaid: false
        )
        let nextItem = PlannedItem(
            accountID: account.id,
            monthKey: next,
            type: .fixedDebit,
            label: "Rent",
            amount: 1200,
            dueDay: 1,
            isPaid: false
        )

        try repository.createPlannedItem(currentItem)
        try repository.createPlannedItem(nextItem)
        try repository.deletePlannedItem(id: currentItem.id)

        let currentItems = try repository.plannedItems(for: current)
        let nextItems = try repository.plannedItems(for: next)

        XCTAssertFalse(currentItems.contains(where: { $0.id == currentItem.id }))
        XCTAssertTrue(nextItems.contains(where: { $0.id == nextItem.id }))
    }

    func testAutomaticMonthCopySkipsItemsMarkedNotToAutoCopy() {
        let items = [
            PlannedItem(
                accountID: UUID(),
                monthKey: YearMonth(year: 2026, month: 3),
                type: .fixedDebit,
                label: "Rent",
                amount: 1200
            ),
            PlannedItem(
                accountID: UUID(),
                monthKey: YearMonth(year: 2026, month: 3),
                type: .fixedDebit,
                label: "One-off",
                amount: 75,
                copiesToNextMonthAutomatically: false
            )
        ]

        XCTAssertEqual(
            PlannedItem.automaticallyCopiedItems(from: items).map(\.label),
            ["Rent"]
        )
    }

    private func makeRepository() -> AccountRepository {
        AccountRepository(
            privateStore: InMemoryAccountDataStore(),
            sharedStore: InMemoryAccountDataStore()
        )
    }
}
