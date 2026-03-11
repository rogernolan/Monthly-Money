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

    func testNewAccountsDefaultToOwnerOnlyAndPrivate() throws {
        let repository = makeRepository()
        let account = try repository.createAccount(name: "Current", role: .regular, type: .current, ownerParticipantID: "owner")
        XCTAssertEqual(account.accessMode, .ownerOnly)
        XCTAssertEqual(account.storageScope, .privateScope)
    }

    func testShareAccountMovesRecordsToSharedAndPreservesTotals() throws {
        let repository = makeRepository()
        let account = try repository.createAccount(name: "Bills", role: .regular, type: .current, ownerParticipantID: "owner")
        let month = YearMonth(year: 2026, month: 2)
        try repository.createPlannedItem(PlannedItem(accountID: account.id, monthKey: month, type: .fixedDebit, label: "Rent", amount: 1200), in: .privateScope)
        try repository.createPlannedItem(PlannedItem(accountID: account.id, monthKey: month, type: .credit, label: "Salary", amount: 2500), in: .privateScope)

        let before = try repository.plannedItems(for: month, scope: .myView)
        let beforeTotals = MonthCalculationEngine.calculate(items: before, openingBalance: 1000, livingBuffer: 100, weeklyEstimate: 100, weekendEstimate: 10, minSuggestedLiving: 1500, yearMonth: month)

        let service = AccountSharingService(repository: repository)
        _ = try service.shareAccount(accountID: account.id, participantsSelection: ["p2"])

        XCTAssertNil(try repository.privateAccount(id: account.id))
        XCTAssertNotNil(try repository.sharedAccount(id: account.id))
        XCTAssertTrue(try repository.privateDependents(accountID: account.id).plannedItems.isEmpty)

        let after = try repository.plannedItems(for: month, scope: .myView)
        let afterTotals = MonthCalculationEngine.calculate(items: after, openingBalance: 1000, livingBuffer: 100, weeklyEstimate: 100, weekendEstimate: 10, minSuggestedLiving: 1500, yearMonth: month)
        XCTAssertEqual(beforeTotals, afterTotals)
    }

    func testViewScopes() throws {
        let repository = makeRepository()
        let privateOnly = try repository.createAccount(name: "Private", role: .regular, type: .current, ownerParticipantID: "owner")
        let toShare = try repository.createAccount(name: "Share", role: .regular, type: .current, ownerParticipantID: "owner")
        try AccountSharingService(repository: repository).shareAccount(accountID: toShare.id, participantsSelection: [])

        let sharedIDs = try repository.accountIDs(for: .sharedView)
        XCTAssertTrue(sharedIDs.contains(toShare.id))
        XCTAssertFalse(sharedIDs.contains(privateOnly.id))

        let myIDs = try repository.accountIDs(for: .myView)
        XCTAssertTrue(myIDs.contains(privateOnly.id))
        XCTAssertTrue(myIDs.contains(toShare.id))
    }

    func testSharedScopeCannotReferencePrivateAccount() throws {
        let repository = makeRepository()
        let privateAccount = try repository.createAccount(name: "Private", role: .regular, type: .current, ownerParticipantID: "owner")
        let month = YearMonth(year: 2026, month: 3)
        XCTAssertThrowsError(
            try repository.createPlannedItem(PlannedItem(accountID: privateAccount.id, monthKey: month, type: .fixedDebit, label: "Bad", amount: 10), in: .sharedScope)
        )
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

        try repository.createPlannedItem(currentItem, in: .privateScope)
        try repository.createPlannedItem(nextItem, in: .privateScope)
        try repository.deletePlannedItem(id: currentItem.id)

        let currentItems = try repository.plannedItems(for: current, scope: .myView)
        let nextItems = try repository.plannedItems(for: next, scope: .myView)

        XCTAssertFalse(currentItems.contains(where: { $0.id == currentItem.id }))
        XCTAssertTrue(nextItems.contains(where: { $0.id == nextItem.id }))
    }

    private func makeRepository() -> AccountRepository {
        AccountRepository(
            privateStore: InMemoryAccountDataStore(scope: .privateScope),
            sharedStore: InMemoryAccountDataStore(scope: .sharedScope)
        )
    }
}
