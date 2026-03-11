import XCTest
@testable import MonthlyMoney

@MainActor
final class MonthlyMoneyTests: XCTestCase {
    override func setUpWithError() throws {
        print("TEST START: \(name) @ \(Date())")
    }

    override func tearDownWithError() throws {
        print("TEST END: \(name) @ \(Date())")
    }

    func testBootstrapCreatesLocalBudgetAndLoadsCurrentMonth() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        XCTAssertEqual(try repository.activeBudget()?.sharingState, .local)
        XCTAssertFalse(state.monthItems.isEmpty)
        XCTAssertEqual(state.primaryBankName, "Nationwide")
    }

    func testMonthCalculationEngineDeterministicBudgetAndSuggestedLiving() {
        let budget = MonthCalculationEngine.monthlyBudgetFromWeekModel(
            year: 2026,
            month: 2,
            weeklyEstimate: 100,
            weekendEstimate: 10
        )
        XCTAssertEqual(budget, 480)

        let suggested = MonthCalculationEngine.suggestedLiving(
            projectedNetCredit: 900,
            livingBuffer: 200,
            monthlyBudgetFromWeekModel: 650,
            minSuggestedLiving: 250
        )
        XCTAssertEqual(suggested, 650)

        let minimumSuggested = MonthCalculationEngine.suggestedLiving(
            projectedNetCredit: 300,
            livingBuffer: 200,
            monthlyBudgetFromWeekModel: 120,
            minSuggestedLiving: 250
        )
        XCTAssertEqual(minimumSuggested, 250)
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

    func testMonthItemEditorDraftRequiresNameAndPositiveAmountToSave() {
        var draft = MonthItemEditorDraft(newType: .fixedDebit, dueDay: 11)

        XCTAssertFalse(draft.canSave)

        draft.label = "Gas bill"
        XCTAssertFalse(draft.canSave)

        draft.amountText = "0"
        XCTAssertFalse(draft.canSave)

        draft.amountText = "42.50"
        XCTAssertTrue(draft.canSave)
    }

    func testMonthItemEditorDraftNormalisesNegativeAmountToDebit() {
        var draft = MonthItemEditorDraft(newType: .credit, dueDay: 25)

        draft.amountText = "-1200"
        draft.normalizeAmountInput(locale: Locale(identifier: "en_GB"))

        XCTAssertEqual(draft.entryKind, .debit)
        XCTAssertEqual(draft.amountText, "1200")
    }

    private func makeRepository() throws -> AccountRepository {
        return AccountRepository(
            privateStore: InMemoryAccountDataStore(),
            sharedStore: InMemoryAccountDataStore()
        )
    }
}
