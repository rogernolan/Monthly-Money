import CloudKit
import CoreData
import SwiftData
import XCTest
import SwiftUI
@testable import MonthlyMoney

@MainActor
final class MonthlyMoneyTests: XCTestCase {
    private static var retainedHostedTestObjects: [AnyObject] = []

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

    func testCurrentMonthBalancePersistsAcrossAppStateRecreation() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        state.primaryBankBalance = 1234

        let reloaded = AppState(repository: repository)
        try reloaded.refresh()

        XCTAssertEqual(reloaded.primaryBankBalance, 1234)
        XCTAssertFalse((try repository.activeBudget()?.monthBalancesPayload).map(\.isEmpty) ?? true)
    }

    func testDailySeparateAccountBalancePersistsAcrossAppStateRecreation() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        state.usesSeparateAccountForDailyBudget = true
        state.dailyBudgetSeparateAccountBalance = 888

        let reloaded = AppState(repository: repository)

        XCTAssertEqual(reloaded.dailyBudgetSeparateAccountBalance, 888)
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

    func testPendingMonthFilterIncludesUnpaidCreditsAndOutgoings() {
        let month = YearMonth(year: 2026, month: 3)
        let accountID = UUID()
        let items = [
            PlannedItem(accountID: accountID, monthKey: month, type: .credit, label: "Salary", amount: 1000, isPaid: false),
            PlannedItem(accountID: accountID, monthKey: month, type: .fixedDebit, label: "Rent", amount: 700, isPaid: false),
            PlannedItem(accountID: accountID, monthKey: month, type: .transfer, label: "Living", amount: 200, isPaid: false),
            PlannedItem(accountID: accountID, monthKey: month, type: .credit, label: "Paid bonus", amount: 50, isPaid: true),
            PlannedItem(accountID: accountID, monthKey: month, type: .fixedDebit, label: "Paid bill", amount: 20, isPaid: true)
        ]

        XCTAssertEqual(
            MonthItemFilterRules.filteredItems(items, for: .pending).map(\.label).sorted(),
            ["Living", "Rent", "Salary"]
        )
    }

    func testDefaultPersistencePlanUsesCloudBackedPrivateStoreAndSharedStore() {
        let plan = MonthlyMoneyPersistencePlan.defaultPlan()

        XCTAssertEqual(plan.privateStore.syncMode, .cloudPrivate)
        XCTAssertEqual(plan.sharedStore.syncMode, .cloudShared)
    }

    func testDefaultPersistencePlanUsesCoreDataPrivateAndSharedStores() {
        let plan = MonthlyMoneyPersistencePlan.defaultPlan()

        XCTAssertEqual(plan.privateStore.backend, .coreData)
        XCTAssertEqual(plan.sharedStore.backend, .coreData)
        XCTAssertEqual(plan.sharedStore.syncMode, .cloudShared)
    }

    func testCoreDataCloudKitProbeBuildsPrivateStoreDescription() {
        let description = CoreDataCloudKitProbe.makeStoreDescription(
            url: URL(fileURLWithPath: "/tmp/private.sqlite"),
            scope: .privateDatabase,
            containerIdentifier: "iCloud.com.hatbat.monthlymoney"
        )

        XCTAssertEqual(description.url?.path, "/tmp/private.sqlite")
        XCTAssertEqual(description.cloudKitContainerOptions?.containerIdentifier, "iCloud.com.hatbat.monthlymoney")
        XCTAssertEqual(description.cloudKitContainerOptions?.databaseScope, .private)
        let options = description.value(forKey: "options") as? [String: Any]
        XCTAssertEqual(options?[NSPersistentHistoryTrackingKey] as? Bool, true)
        XCTAssertEqual(options?[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? Bool, true)
    }

    func testCoreDataCloudKitProbeBuildsSharedStoreDescription() {
        let description = CoreDataCloudKitProbe.makeStoreDescription(
            url: URL(fileURLWithPath: "/tmp/shared.sqlite"),
            scope: .sharedDatabase,
            containerIdentifier: "iCloud.com.hatbat.monthlymoney"
        )

        XCTAssertEqual(description.url?.path, "/tmp/shared.sqlite")
        XCTAssertEqual(description.cloudKitContainerOptions?.containerIdentifier, "iCloud.com.hatbat.monthlymoney")
        XCTAssertEqual(description.cloudKitContainerOptions?.databaseScope, .shared)
        let options = description.value(forKey: "options") as? [String: Any]
        XCTAssertEqual(options?[NSPersistentHistoryTrackingKey] as? Bool, true)
        XCTAssertEqual(options?[NSPersistentStoreRemoteChangeNotificationPostOptionKey] as? Bool, true)
    }

    func testCoreDataAccountDataStoreRoundTripsBudgetAccountsItemsAndTransactions() throws {
        let store = try CoreDataAccountDataStore.makeInMemory()
        Self.retainHostedTestObject(store)

        let budget = Budget(
            id: UUID(),
            name: "Household",
            ownerParticipantID: "owner",
            sharingState: .local,
            usesSeparateAccountForDailyBudget: true,
            dailyBudgetAmount: 1500,
            dailyBudgetPaydayDay: 25
        )
        try store.upsertBudget(budget)

        let account = Account(
            id: UUID(),
            budgetID: budget.id,
            name: "Joint",
            role: .regular,
            type: .current,
            ownerParticipantID: "owner"
        )
        try store.upsertAccount(account)

        let item = PlannedItem(
            id: UUID(),
            budgetID: budget.id,
            accountID: account.id,
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Rent",
            amount: 1200,
            dueDay: 1,
            isPaid: false,
            copiesToNextMonthAutomatically: true,
            notes: "Landlord"
        )
        try store.upsertPlannedItems([item])

        let transaction = Transaction(
            id: UUID(),
            budgetID: budget.id,
            accountID: account.id,
            monthKey: YearMonth(year: 2026, month: 3),
            amount: 1200,
            note: "Rent payment"
        )
        try store.upsertTransactions([transaction])

        let budgets = try store.fetchBudgets()
        XCTAssertEqual(budgets.map(\.id), [budget.id])
        XCTAssertEqual(budgets.first?.usesSeparateAccountForDailyBudget, true)
        XCTAssertEqual(budgets.first?.dailyBudgetAmount, 1500)
        XCTAssertEqual(budgets.first?.dailyBudgetPaydayDay, 25)
        let accounts = try store.fetchAccounts()
        XCTAssertEqual(accounts.map(\.id), [account.id])
        let plannedItems = try store.fetchPlannedItems(accountIDs: [account.id], monthKey: YearMonth(year: 2026, month: 3))
        XCTAssertEqual(
            plannedItems.map(\.id),
            [item.id]
        )
        let transactions = try store.fetchTransactions(accountIDs: [account.id])
        XCTAssertEqual(
            transactions.map(\.id),
            [transaction.id]
        )
    }

    func testCoreDataAccountDataStoreMergesRemoteChangesIntoViewContext() throws {
        let store = try CoreDataAccountDataStore.makeInMemory()
        Self.retainHostedTestObject(store)

        XCTAssertTrue(store.mergesRemoteChangesAutomatically)
    }

    func testCoreDataAccountDataStoreResolvesManagedBudgetObjectID() throws {
        let store = try CoreDataAccountDataStore.makeInMemory()
        Self.retainHostedTestObject(store)

        let budget = Budget(
            id: UUID(),
            name: "Shared Household",
            ownerParticipantID: "owner",
            sharingState: .shared
        )
        try store.upsertBudget(budget)

        XCTAssertNotNil(try store.managedBudgetObjectID(for: budget.id))
    }

    func testBootstrapRulesWaitForCloudImportOnlyForEmptyCloudBackedPrivateStore() {
        XCTAssertTrue(
            AppBootstrapRules.shouldWaitForInitialCloudImport(
                privateStoreSyncMode: .cloudPrivate,
                accountCount: 0
            )
        )
        XCTAssertFalse(
            AppBootstrapRules.shouldWaitForInitialCloudImport(
                privateStoreSyncMode: .cloudPrivate,
                accountCount: 1
            )
        )
        XCTAssertFalse(
            AppBootstrapRules.shouldWaitForInitialCloudImport(
                privateStoreSyncMode: .localOnly,
                accountCount: 0
            )
        )
    }

    func testRepositoryDelegatesInitialPrivateCloudImportWaitToPrivateStore() async throws {
        let privateStore = AwaitingAccountDataStoreSpy()
        let repository = AccountRepository(
            privateStore: privateStore,
            sharedStore: InMemoryAccountDataStore(),
            privateStoreSyncMode: .cloudPrivate
        )

        try await repository.awaitInitialPrivateCloudImport(timeout: .seconds(3))

        XCTAssertTrue(privateStore.didAwaitInitialCloudImport)
    }

    func testPersistenceFactoryBuildsCoreDataPrivateAndSharedStores() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let repository = try MonthlyMoneyPersistenceFactory.makeRepository(
            plan: .defaultPlan(baseDirectory: directory),
            schema: Self.makeSchema()
        )
        Self.retainHostedTestObject(repository)

        XCTAssertEqual(repository.privateStoreImplementationKind, .coreData)
        XCTAssertEqual(repository.sharedStoreImplementationKind, .coreData)
        XCTAssertEqual(repository.sharedStoreSyncMode, .cloudShared)
    }

    func testSettingsSharingPresentationForLocalBudget() {
        let presentation = SettingsSharingPresentation(status: .localOnly)

        XCTAssertEqual(presentation.statusText, "Local only")
        XCTAssertTrue(presentation.isShareButtonEnabled)
        XCTAssertNil(presentation.note)
    }

    func testSettingsSharingPresentationForOwnerSharedBudget() {
        let presentation = SettingsSharingPresentation(status: .sharedByYou)

        XCTAssertEqual(presentation.statusText, "Shared by you")
        XCTAssertFalse(presentation.isShareButtonEnabled)
        XCTAssertEqual(presentation.note, "Unshare will come later.")
    }

    func testSettingsSharingPresentationForRecipientSharedBudget() {
        let presentation = SettingsSharingPresentation(status: .sharedWithYou)

        XCTAssertEqual(presentation.statusText, "Shared with you")
        XCTAssertFalse(presentation.isShareButtonEnabled)
        XCTAssertEqual(presentation.note, "Unshare will come later.")
    }

    func testAppStateSharingStatusReflectsActiveBudget() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        XCTAssertEqual(state.sharingStatus, .localOnly)

        let budget = try XCTUnwrap(try repository.activeBudget())
        budget.sharingState = .shared
        budget.ownerParticipantID = "owner"
        try repository.saveBudget(budget)
        XCTAssertEqual(state.sharingStatus, .sharedByYou)

        budget.ownerParticipantID = "jane"
        try repository.saveBudget(budget)
        XCTAssertEqual(state.sharingStatus, .sharedWithYou)
    }

    func testBudgetSettingsAreEditableForLocalAndOwnerSharedBudgets() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        XCTAssertTrue(state.canEditBudgetSettings)

        state.usesSeparateAccountForDailyBudget = true
        XCTAssertTrue(state.usesSeparateAccountForDailyBudget)

        let budget = try XCTUnwrap(try repository.activeBudget())
        budget.sharingState = .shared
        budget.ownerParticipantID = AppState.localOwnerParticipantID
        try repository.saveBudget(budget)

        XCTAssertTrue(state.canEditBudgetSettings)

        state.usesSeparateAccountForDailyBudget = false
        XCTAssertFalse(state.usesSeparateAccountForDailyBudget)
    }

    func testBudgetSettingsAreReadOnlyForParticipantSharedBudgets() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        let budget = try XCTUnwrap(try repository.activeBudget())
        budget.sharingState = .shared
        budget.ownerParticipantID = "jane"
        budget.usesSeparateAccountForDailyBudget = true
        try repository.saveBudget(budget)

        XCTAssertFalse(state.canEditBudgetSettings)
        XCTAssertTrue(state.usesSeparateAccountForDailyBudget)

        state.usesSeparateAccountForDailyBudget = false

        XCTAssertTrue(state.usesSeparateAccountForDailyBudget)
        XCTAssertEqual(try repository.activeBudget()?.usesSeparateAccountForDailyBudget, true)
    }

    func testShareBudgetMarksInProgressAndEndsSharedByOwner() async throws {
        let repository = try makeRepository()
        let expectation = expectation(description: "share handler called while progress flag is set")
        var observedState: AppState?
        let state = AppState(
            repository: repository,
            shareBudgetAction: { repository in
                let service = BudgetSharingService(repository: repository) { _ in
                    XCTAssertTrue(observedState?.isSharingBudget ?? false)
                    expectation.fulfill()
                }
                return try service.shareBudget(participantsSelection: [])
            }
        )
        observedState = state

        await state.bootstrapIfNeeded()
        XCTAssertFalse(state.isSharingBudget)

        await state.shareBudget()

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertFalse(state.isSharingBudget)
        XCTAssertEqual(state.sharingStatus, .sharedByYou)
        XCTAssertNotNil(try repository.sharedBudget())
        XCTAssertNil(try repository.localBudget())
    }

    func testShareBudgetStoresErrorWhenAlreadyShared() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let budget = try XCTUnwrap(try repository.activeBudget())
        budget.sharingState = .shared
        try repository.insertShared(
            budget: budget,
            accounts: try repository.accounts(),
            plannedItems: try repository.plannedItems(for: state.selectedMonth),
            transactions: []
        )
        try repository.deleteLocalBudget(id: budget.id)

        await state.shareBudget()

        XCTAssertFalse(state.isSharingBudget)
        XCTAssertNotNil(state.sharingErrorMessage)
    }

    func testRefreshShowsPendingSharedBudgetOverwriteForRecipient() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        try insertIncomingSharedBudget(into: repository, month: state.selectedMonth)

        try state.refresh()

        XCTAssertTrue(state.shouldShowSharedBudgetOverwriteAlert)
        XCTAssertEqual(state.pendingSharedBudgetAdoption?.budgetName, "Shared Household")
    }

    func testConfirmSharedBudgetOverwriteDeletesLocalBudgetAndAdoptsSharedBudget() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        try insertIncomingSharedBudget(into: repository, month: state.selectedMonth)
        try state.refresh()

        XCTAssertTrue(state.shouldShowSharedBudgetOverwriteAlert)

        try state.confirmSharedBudgetOverwrite()

        XCTAssertNil(try repository.localBudget())
        XCTAssertEqual(try repository.activeBudget()?.sharingState, .shared)
        XCTAssertEqual(state.primaryBankName, "Shared Monzo")
        XCTAssertFalse(state.shouldShowSharedBudgetOverwriteAlert)
        XCTAssertEqual(state.monthItems.map(\.label), ["Shared Rent"])
    }

    func testCancelSharedBudgetOverwriteKeepsLocalBudgetActive() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let localBudgetID = try XCTUnwrap(try repository.localBudget()?.id)
        try insertIncomingSharedBudget(into: repository, month: state.selectedMonth)
        try state.refresh()

        state.cancelSharedBudgetOverwrite()

        XCTAssertEqual(try repository.localBudget()?.id, localBudgetID)
        XCTAssertEqual(try repository.activeBudget()?.sharingState, .local)
        XCTAssertFalse(state.shouldShowSharedBudgetOverwriteAlert)

        try state.refresh()
        XCTAssertFalse(state.shouldShowSharedBudgetOverwriteAlert)
    }

    func testCloudRefreshPolicyOnlyPollsForActiveCloudBackedAppSessions() {
        XCTAssertTrue(
            CloudRefreshPolicy.shouldPoll(
                privateStoreSyncMode: .cloudPrivate,
                scenePhase: .active,
                isRunningTests: false
            )
        )
        XCTAssertFalse(
            CloudRefreshPolicy.shouldPoll(
                privateStoreSyncMode: .localOnly,
                scenePhase: .active,
                isRunningTests: false
            )
        )
        XCTAssertFalse(
            CloudRefreshPolicy.shouldPoll(
                privateStoreSyncMode: .cloudPrivate,
                scenePhase: .background,
                isRunningTests: false
            )
        )
        XCTAssertFalse(
            CloudRefreshPolicy.shouldPoll(
                privateStoreSyncMode: .cloudPrivate,
                scenePhase: .active,
                isRunningTests: true
            )
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

    private func insertIncomingSharedBudget(into repository: AccountRepository, month: YearMonth) throws {
        let budget = Budget(
            id: UUID(),
            name: "Shared Household",
            ownerParticipantID: "jane",
            sharingState: .shared
        )
        let account = Account(
            id: UUID(),
            budgetID: budget.id,
            name: "Shared Monzo",
            role: .regular,
            type: .current,
            ownerParticipantID: "jane"
        )
        let item = PlannedItem(
            id: UUID(),
            budgetID: budget.id,
            accountID: account.id,
            monthKey: month,
            type: .fixedDebit,
            label: "Shared Rent",
            amount: 1200,
            dueDay: 1,
            isPaid: false
        )

        try repository.insertShared(
            budget: budget,
            accounts: [account],
            plannedItems: [item],
            transactions: []
        )
    }

    private static let utcCalendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }()

    private static func retainHostedTestObject(_ object: AnyObject) {
        retainedHostedTestObjects.append(object)
    }

    private static func makeSchema() -> Schema {
        Schema([
            Budget.self,
            Account.self,
            PlannedItem.self,
            Transaction.self
        ])
    }

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

@MainActor
private final class AwaitingAccountDataStoreSpy: AccountDataStore {
    var implementationKind: DataStoreImplementationKind { .inMemory }
    private let backingStore = InMemoryAccountDataStore()
    private(set) var didAwaitInitialCloudImport = false

    func awaitInitialCloudImport(timeout: Duration) async throws {
        _ = timeout
        didAwaitInitialCloudImport = true
    }

    func fetchBudgets() throws -> [Budget] { try backingStore.fetchBudgets() }
    func fetchBudget(id: UUID) throws -> Budget? { try backingStore.fetchBudget(id: id) }
    func upsertBudget(_ budget: Budget) throws { try backingStore.upsertBudget(budget) }
    func deleteBudget(id: UUID) throws { try backingStore.deleteBudget(id: id) }
    func fetchAccounts() throws -> [Account] { try backingStore.fetchAccounts() }
    func fetchAccount(id: UUID) throws -> Account? { try backingStore.fetchAccount(id: id) }
    func upsertAccount(_ account: Account) throws { try backingStore.upsertAccount(account) }
    func deleteAccount(id: UUID) throws { try backingStore.deleteAccount(id: id) }
    func fetchPlannedItems() throws -> [PlannedItem] { try backingStore.fetchPlannedItems() }
    func fetchPlannedItem(id: UUID) throws -> PlannedItem? { try backingStore.fetchPlannedItem(id: id) }
    func fetchPlannedItems(accountIDs: Set<UUID>, monthKey: YearMonth?) throws -> [PlannedItem] {
        try backingStore.fetchPlannedItems(accountIDs: accountIDs, monthKey: monthKey)
    }
    func upsertPlannedItems(_ items: [PlannedItem]) throws { try backingStore.upsertPlannedItems(items) }
    func deletePlannedItem(id: UUID) throws { try backingStore.deletePlannedItem(id: id) }
    func deletePlannedItems(accountID: UUID) throws { try backingStore.deletePlannedItems(accountID: accountID) }
    func fetchTransactions() throws -> [MonthlyMoney.Transaction] { try backingStore.fetchTransactions() }
    func fetchTransactions(accountIDs: Set<UUID>) throws -> [MonthlyMoney.Transaction] {
        try backingStore.fetchTransactions(accountIDs: accountIDs)
    }
    func upsertTransactions(_ transactions: [MonthlyMoney.Transaction]) throws {
        try backingStore.upsertTransactions(transactions)
    }
    func deleteTransactions(accountID: UUID) throws { try backingStore.deleteTransactions(accountID: accountID) }
}
