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
        XCTAssertEqual(try repository.activeBudget()?.usesSeparateAccountForDailyBudget, false)
        XCTAssertFalse(state.monthItems.isEmpty)
        XCTAssertTrue(state.canNavigateToNextMonth)
        XCTAssertEqual(state.primaryBankName, "Nationwide")
    }

    func testDailyBudgetAccountSettingPersistsOnActiveBudget() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        XCTAssertFalse(state.usesSeparateAccountForDailyBudget)

        state.usesSeparateAccountForDailyBudget = true

        XCTAssertTrue(state.usesSeparateAccountForDailyBudget)
        XCTAssertEqual(try repository.activeBudget()?.usesSeparateAccountForDailyBudget, true)
    }

    func testDailyBudgetInputsPersistOnActiveBudget() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        XCTAssertEqual(state.dailyBudgetAmount, 0)
        XCTAssertEqual(state.dailyBudgetPaydayDay, 1)

        state.dailyBudgetAmount = 1550
        state.dailyBudgetPaydayDay = 28

        XCTAssertEqual(state.dailyBudgetAmount, 1550)
        XCTAssertEqual(state.dailyBudgetPaydayDay, 28)
        XCTAssertEqual(try repository.activeBudget()?.dailyBudgetAmount, 1550)
        XCTAssertEqual(try repository.activeBudget()?.dailyBudgetPaydayDay, 28)
    }

    func testDailyCurrentBalanceUsesMonthProjectionWhenSeparateAccountDisabled() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        XCTAssertFalse(state.usesSeparateAccountForDailyBudget)
        XCTAssertEqual(state.dailyBudgetCurrentBalance, state.projectedBalanceFromCurrentBalance)
    }

    func testDailyCurrentBalanceUsesSeparateAccountBalanceWhenEnabled() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        state.usesSeparateAccountForDailyBudget = true
        state.dailyBudgetSeparateAccountBalance = 777

        XCTAssertEqual(state.dailyBudgetCurrentBalance, 777)
    }

    func testDailyBudgetCycleWrapsAcrossMonthBoundary() {
        let calendar = Self.utcCalendar
        let metrics = DailyBudgetCycleCalculator.metrics(
            today: Self.date(year: 2026, month: 4, day: 2),
            paydayDay: 1,
            budget: 3000,
            currentBalance: 2900,
            calendar: calendar
        )

        XCTAssertEqual(
            calendar.startOfDay(for: metrics.previousPayday),
            calendar.startOfDay(for: Self.date(year: 2026, month: 4, day: 1))
        )
        XCTAssertEqual(
            calendar.startOfDay(for: metrics.nextPayday),
            calendar.startOfDay(for: Self.date(year: 2026, month: 5, day: 1))
        )
        XCTAssertEqual(metrics.cycleDays, 30)
        XCTAssertEqual(metrics.elapsedDaysInCycle, 1)
        XCTAssertEqual(metrics.remainingDaysToPayday, 29)
    }

    func testDailyBudgetCycleCalculatesChipValues() {
        let metrics = DailyBudgetCycleCalculator.metrics(
            today: Self.date(year: 2026, month: 3, day: 12),
            paydayDay: 1,
            budget: 3100,
            currentBalance: 2500,
            calendar: Self.utcCalendar
        )

        XCTAssertEqual(metrics.dailyBudget, 100)
        XCTAssertEqual(metrics.expectedBalanceToday, 2000)
        XCTAssertEqual(metrics.aheadBehind, 500)
        XCTAssertEqual(metrics.currentDailyBudget, 125)
    }

    func testDailyChipToneResolverUsesWhiteBudgetCardsAndComparisonColours() {
        let metrics = DailyBudgetCycleMetrics(
            previousPayday: Self.date(year: 2026, month: 3, day: 1),
            nextPayday: Self.date(year: 2026, month: 4, day: 1),
            cycleDays: 31,
            elapsedDaysInCycle: 11,
            remainingDaysToPayday: 20,
            dailyBudget: 100,
            expectedBalanceToday: 2000,
            aheadBehind: -50,
            currentDailyBudget: 120
        )

        XCTAssertEqual(DailyChipToneResolver.tone(for: .budget, metrics: metrics, currentBalance: 500), .plain)
        XCTAssertEqual(DailyChipToneResolver.tone(for: .dailyBudget, metrics: metrics, currentBalance: 500), .plain)
        XCTAssertEqual(DailyChipToneResolver.tone(for: .aheadBehind, metrics: metrics, currentBalance: 500), .negative)
        XCTAssertEqual(DailyChipToneResolver.tone(for: .currentDailyBudget, metrics: metrics, currentBalance: 500), .positive)
    }

    func testDailyPresentationHelpersExposeUpdatedTitlesAndPaydayLabel() {
        XCTAssertEqual(
            DailyPresentationContent.balanceTitle(usesSeparateAccount: true),
            "Current balance"
        )
        XCTAssertEqual(
            DailyPresentationContent.balanceTitle(usesSeparateAccount: false),
            "Predicted remaining funds"
        )
        XCTAssertEqual(
            DailyPresentationContent.daysUntilPaydayTitle(paydayDay: 17),
            "Days until payday (17th)"
        )
    }

    func testEditableMoneyChipLayoutShowsDismissButtonOnlyWhileFocused() {
        XCTAssertEqual(
            EditableMoneyChipLayout.editing,
            EditableMoneyChipLayout(isEditing: true)
        )
        XCTAssertEqual(
            EditableMoneyChipLayout.resting,
            EditableMoneyChipLayout(isEditing: false)
        )
        XCTAssertTrue(EditableMoneyChipLayout.editing.showsDismissButton)
        XCTAssertFalse(EditableMoneyChipLayout.resting.showsDismissButton)
        XCTAssertEqual(EditableMoneyChipLayout.editing.trailingAccessoryWidth, 34)
        XCTAssertEqual(EditableMoneyChipLayout.resting.trailingAccessoryWidth, 0)
    }

    func testEditableMoneyChipLayoutShowsPersistentEditBadge() {
        XCTAssertTrue(EditableMoneyChipLayout.editing.showsEditBadge)
        XCTAssertTrue(EditableMoneyChipLayout.resting.showsEditBadge)
    }

    func testMonthEditableCardRulesOnlyAllowCurrentMonthBalanceEditing() {
        XCTAssertTrue(
            MonthEditableCardRules.allowsCurrentBalanceEditing(
                isSelectedMonthInPast: false,
                isSelectedMonthInFuture: false
            )
        )
        XCTAssertFalse(
            MonthEditableCardRules.allowsCurrentBalanceEditing(
                isSelectedMonthInPast: true,
                isSelectedMonthInFuture: false
            )
        )
        XCTAssertFalse(
            MonthEditableCardRules.allowsCurrentBalanceEditing(
                isSelectedMonthInPast: false,
                isSelectedMonthInFuture: true
            )
        )
    }

    func testMonthChipFocusIDChangesPerMonth() {
        let january = YearMonth(year: 2026, month: 1)
        let february = YearMonth(year: 2026, month: 2)

        XCTAssertEqual(
            MonthChipFocusID.currentBalance(for: january),
            "month-current-balance-2026-01"
        )
        XCTAssertNotEqual(
            MonthChipFocusID.currentBalance(for: january),
            MonthChipFocusID.currentBalance(for: february)
        )
    }

    func testPastMonthMutationsAreIgnored() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        let currentMonth = state.selectedMonth
        let pastMonth = YearMonth(year: currentMonth.month == 1 ? currentMonth.year - 1 : currentMonth.year,
                                  month: currentMonth.month == 1 ? 12 : currentMonth.month - 1)
        let account = try XCTUnwrap(try repository.accounts().first)
        let item = PlannedItem(
            accountID: account.id,
            monthKey: pastMonth,
            type: .fixedDebit,
            label: "Frozen bill",
            amount: 42,
            dueDay: 4,
            isPaid: false
        )
        try repository.createPlannedItem(item)

        state.selectedMonth = pastMonth
        try state.refresh()
        let originalPastMonthBalance = state.primaryBankBalance

        state.primaryBankBalance = 999
        state.setPaid(item: item, paid: true)
        state.update(
            item: item,
            label: "Changed",
            amount: 88,
            dueDay: 5,
            dueText: nil,
            type: .credit,
            copiesToNextMonthAutomatically: false,
            notes: "Should not persist"
        )
        state.delete(item: item)
        let created = state.createEntry(type: .fixedDebit, label: "Past add", amount: 11, dueDay: 7)

        let reloaded = try XCTUnwrap(try repository.plannedItems(for: pastMonth).first(where: { $0.id == item.id }))
        XCTAssertEqual(state.primaryBankBalance, originalPastMonthBalance)
        XCTAssertFalse(reloaded.isPaid)
        XCTAssertEqual(reloaded.label, "Frozen bill")
        XCTAssertEqual(reloaded.amount, 42)
        XCTAssertEqual(reloaded.type, .fixedDebit)
        XCTAssertEqual(reloaded.notes, "")
        XCTAssertNil(created)
        XCTAssertEqual(
            try repository.plannedItems(for: pastMonth).filter { $0.label == "Past add" }.count,
            0
        )
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

    func testNewPlannedItemsCopyToNextMonthAutomaticallyByDefault() {
        let item = PlannedItem(
            accountID: UUID(),
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Rent",
            amount: 1200
        )

        XCTAssertTrue(item.copiesToNextMonthAutomatically)
    }

    func testMonthItemRowMetadataLinesShowDayThenNotes() {
        let item = PlannedItem(
            accountID: UUID(),
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Gas bill",
            amount: 42,
            dueDay: 7,
            dueText: nil,
            isPaid: false,
            notes: "Call to confirm meter reading"
        )

        XCTAssertEqual(
            MonthItemRowContent.metadataLines(for: item),
            ["7th", "Call to confirm meter reading"]
        )
    }

    func testMonthItemRowMetadataLinesHideEmptyNotes() {
        let item = PlannedItem(
            accountID: UUID(),
            monthKey: YearMonth(year: 2026, month: 3),
            type: .credit,
            label: "Salary",
            amount: 1000,
            dueDay: nil,
            dueText: "Floating",
            isPaid: false,
            notes: "   "
        )

        XCTAssertEqual(MonthItemRowContent.metadataLines(for: item), ["Floating"])
    }

    func testMonthItemRowDoesNotHighlightOverdueForZeroAmount() {
        let item = PlannedItem(
            accountID: UUID(),
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Placeholder",
            amount: 0,
            dueDay: 1,
            dueText: nil,
            isPaid: false
        )

        XCTAssertFalse(
            MonthItemRowContent.showsOverdueHighlight(
                for: item,
                isSelectedMonthInPast: false,
                isSelectedMonthInFuture: false,
                todayDay: 12
            )
        )
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

    private func makeRepository() throws -> AccountRepository {
        return AccountRepository(
            privateStore: InMemoryAccountDataStore(),
            sharedStore: InMemoryAccountDataStore()
        )
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private static func date(year: Int, month: Int, day: Int) -> Date {
        utcCalendar.date(from: DateComponents(
            calendar: utcCalendar,
            timeZone: utcCalendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: 12
        ))!
    }
}
