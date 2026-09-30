import CloudKit
import CoreData
import SwiftData
import XCTest
import SwiftUI
import UIKit
import UniformTypeIdentifiers
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

    func testWatchAppIconResourceIsBundledWithWatchTarget() throws {
        let projectFile = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("MonthlyMoney.xcodeproj/project.pbxproj")
        let project = try String(contentsOf: projectFile, encoding: .utf8)
        let watchResourcesStart = try XCTUnwrap(
            project.range(of: "\t\t9B1A017DC08A2E2FDF0AC398 /* Resources */ = {")?.lowerBound
        )
        let watchResourcesEnd = try XCTUnwrap(
            project[watchResourcesStart...].range(of: "\t\t};")?.lowerBound
        )
        let watchResourcesSection = String(project[watchResourcesStart..<watchResourcesEnd])

        XCTAssertTrue(
            watchResourcesSection.contains("AppIcon.icon in Resources"),
            "Expected the watch target resources build phase to include AppIcon.icon."
        )
    }

    func testCivilDateUsesGregorianCalendarDaysAcrossDST() throws {
        let calendar = Calendar(identifier: .gregorian)
        let start = try XCTUnwrap(CivilDate(year: 2026, month: 3, day: 28))

        XCTAssertEqual(
            start.adding(days: 1, calendar: calendar),
            CivilDate(year: 2026, month: 3, day: 29)
        )
        XCTAssertEqual(
            start.adding(days: 2, calendar: calendar),
            CivilDate(year: 2026, month: 3, day: 30)
        )
    }

    func testWheelOfMoneyRowsUseBritishLabelsOrdinalDaysAndDirectionSymbols() throws {
        XCTAssertEqual(WheelOfMoneyRowContent.annualisedCostTitle, "Annualised cost")
        XCTAssertEqual(
            WheelOfMoneyRowContent.singleOccurrenceRepeatPeriodHelp,
            "Cannot edit repeat period of a single entry. Select 'This and future' if you wish to change the repeat period."
        )
        XCTAssertEqual(WheelOfMoneyRowContent.dayText(for: try XCTUnwrap(CivilDate(year: 2026, month: 9, day: 1))), "1st")
        XCTAssertEqual(WheelOfMoneyRowContent.dayText(for: try XCTUnwrap(CivilDate(year: 2026, month: 9, day: 22))), "22nd")
        XCTAssertEqual(WheelOfMoneyRowContent.directionSymbol(for: .credit), "arrowtriangle.up.fill")
        XCTAssertEqual(WheelOfMoneyRowContent.directionSymbol(for: .fixedDebit), "arrowtriangle.down.fill")
        XCTAssertEqual(WheelOfMoneyRowContent.directionSymbol(for: .transfer), "arrowtriangle.down.fill")
    }

    func testPeriodicProjectionUsesLatestEligibleRevision() throws {
        let repeatID = UUID()
        let first = PeriodicRepeatRevision(
            id: UUID(), repeatID: repeatID,
            effectiveDate: CivilDate(year: 2026, month: 1, day: 1)!,
            anchorDate: CivilDate(year: 2026, month: 1, day: 1)!,
            repeatDays: 28, type: .fixedDebit, label: "Old", matchingString: "old",
            amount: 20, notes: ""
        )
        let second = PeriodicRepeatRevision(
            id: UUID(), repeatID: repeatID,
            effectiveDate: CivilDate(year: 2026, month: 2, day: 26)!,
            anchorDate: CivilDate(year: 2026, month: 2, day: 26)!,
            repeatDays: 30, type: .fixedDebit, label: "New", matchingString: "new",
            amount: 30, notes: ""
        )

        let projected = PeriodicRepeatSchedule.project(
            repeatID: repeatID,
            revisions: [first, second],
            skips: [],
            from: CivilDate(year: 2026, month: 1, day: 1)!,
            through: CivilDate(year: 2026, month: 4, day: 30)!
        )

        XCTAssertEqual(projected.first?.label, "Old")
        XCTAssertEqual(projected.first(where: { $0.scheduledDate == CivilDate(year: 2026, month: 2, day: 26)! })?.label, "New")
        XCTAssertFalse(projected.contains { $0.scheduledDate == CivilDate(year: 2026, month: 3, day: 1)! })
    }

    func testRevisionBoundaryKeepsOldUnmaterializedDates() throws {
        let repeatID = UUID()
        let old = PeriodicRepeatRevision(
            id: UUID(), repeatID: repeatID,
            effectiveDate: CivilDate(year: 2026, month: 1, day: 1)!,
            anchorDate: CivilDate(year: 2026, month: 1, day: 1)!,
            repeatDays: 28, type: .fixedDebit, label: "Old", matchingString: nil,
            amount: 10, notes: ""
        )
        let updated = PeriodicRepeatRevision(
            id: UUID(), repeatID: repeatID,
            effectiveDate: CivilDate(year: 2026, month: 3, day: 26)!,
            anchorDate: CivilDate(year: 2026, month: 3, day: 26)!,
            repeatDays: 30, type: .fixedDebit, label: "Updated", matchingString: nil,
            amount: 12, notes: ""
        )

        let dates = PeriodicRepeatSchedule.project(
            repeatID: repeatID, revisions: [old, updated], skips: [],
            from: CivilDate(year: 2026, month: 1, day: 1)!,
            through: CivilDate(year: 2026, month: 4, day: 30)!
        ).map(\.scheduledDate)

        XCTAssertTrue(dates.contains(CivilDate(year: 2026, month: 3, day: 26)!))
        XCTAssertFalse(dates.contains(CivilDate(year: 2026, month: 3, day: 25)!))
        XCTAssertFalse(dates.contains(CivilDate(year: 2026, month: 3, day: 29)!))
    }

    func testPeriodicProjectionSupportsShortAndLongIntervalsAcrossYearBoundary() throws {
        let intervals = [1, 28, 29, 365, 730]
        for interval in intervals {
            let repeatID = UUID()
            let anchor = CivilDate(year: 2025, month: 7, day: 1)!
            let revision = PeriodicRepeatRevision(
                id: UUID(), repeatID: repeatID,
                effectiveDate: anchor,
                anchorDate: anchor,
                repeatDays: interval, type: .fixedDebit, label: "Repeat", matchingString: nil,
                amount: 1, notes: ""
            )

            let dates = PeriodicRepeatSchedule.project(
                repeatID: repeatID, revisions: [revision], skips: [],
                from: anchor,
                through: CivilDate(year: 2027, month: 7, day: 1)!
            ).map(\.scheduledDate)

            XCTAssertEqual(dates.first, anchor)
            XCTAssertEqual(dates.dropFirst().first, anchor.adding(days: interval))
            XCTAssertTrue(zip(dates, dates.dropFirst()).allSatisfy { pair in
                pair.0.adding(days: interval) == pair.1
            })
        }
    }

    func testSkipSuppressesScheduledDateAfterRevisionChange() throws {
        let repeatID = UUID()
        let old = PeriodicRepeatRevision(
            id: UUID(), repeatID: repeatID,
            effectiveDate: CivilDate(year: 2026, month: 1, day: 1)!,
            anchorDate: CivilDate(year: 2026, month: 1, day: 1)!,
            repeatDays: 28, type: .fixedDebit, label: "Old", matchingString: nil,
            amount: 10, notes: ""
        )
        let revised = PeriodicRepeatRevision(
            id: UUID(), repeatID: repeatID,
            effectiveDate: CivilDate(year: 2026, month: 2, day: 26)!,
            anchorDate: CivilDate(year: 2026, month: 2, day: 26)!,
            repeatDays: 29, type: .fixedDebit, label: "New", matchingString: nil,
            amount: 11, notes: ""
        )
        let skippedDate = CivilDate(year: 2026, month: 3, day: 27)!

        let dates = PeriodicRepeatSchedule.project(
            repeatID: repeatID,
            revisions: [old, revised],
            skips: [PeriodicRepeatSkip(repeatID: repeatID, scheduledDate: skippedDate)],
            from: CivilDate(year: 2026, month: 1, day: 1)!,
            through: CivilDate(year: 2026, month: 5, day: 1)!
        ).map(\.scheduledDate)

        XCTAssertFalse(dates.contains(skippedDate))
    }

    func testMonthlySavingsTargetAnnualizesIntervalsWithDecimalArithmetic() throws {
        let repeatID = UUID()
        let debit = PeriodicRepeatRevision(
            id: UUID(), repeatID: repeatID,
            effectiveDate: CivilDate(year: 2026, month: 1, day: 1)!,
            anchorDate: CivilDate(year: 2026, month: 1, day: 1)!,
            repeatDays: 365, type: .fixedDebit, label: "Annual", matchingString: nil,
            amount: Decimal(string: "1200")!, notes: ""
        )
        let credit = PeriodicRepeatRevision(
            id: UUID(), repeatID: UUID(),
            effectiveDate: CivilDate(year: 2026, month: 1, day: 1)!,
            anchorDate: CivilDate(year: 2026, month: 1, day: 1)!,
            repeatDays: 1, type: .credit, label: "Credit", matchingString: nil,
            amount: Decimal(string: "100000")!, notes: ""
        )

        XCTAssertEqual(
            PeriodicRepeatSchedule.monthlySavingsTarget(
                revisions: [debit, credit],
                effectiveOn: CivilDate(year: 2026, month: 4, day: 1)!
            ),
            Decimal(string: "100.066438356164383561643835616438356164")!
        )
    }

    func testMonthlySavingsTargetExcludesRepeatsOfFourWeeksOrLess() throws {
        let effectiveOn = CivilDate(year: 2026, month: 4, day: 1)!
        let shortID = UUID()
        let longID = UUID()
        let revisedID = UUID()
        let shortRepeat = PeriodicRepeat(id: shortID, budgetID: UUID(), accountID: UUID())
        let longRepeat = PeriodicRepeat(id: longID, budgetID: UUID(), accountID: UUID())
        let revisedRepeat = PeriodicRepeat(id: revisedID, budgetID: UUID(), accountID: UUID())
        let shortRevision = PeriodicRepeatRevision(
            id: UUID(), repeatID: shortID,
            effectiveDate: CivilDate(year: 2026, month: 1, day: 1)!,
            anchorDate: CivilDate(year: 2026, month: 1, day: 1)!,
            repeatDays: 28, type: .fixedDebit, label: "Four-week repeat", matchingString: nil,
            amount: 28, notes: ""
        )
        let longRevision = PeriodicRepeatRevision(
            id: UUID(), repeatID: longID,
            effectiveDate: CivilDate(year: 2026, month: 1, day: 1)!,
            anchorDate: CivilDate(year: 2026, month: 1, day: 1)!,
            repeatDays: 29, type: .fixedDebit, label: "Long-term repeat", matchingString: nil,
            amount: 29, notes: ""
        )
        let priorLongRevision = PeriodicRepeatRevision(
            id: UUID(), repeatID: revisedID,
            effectiveDate: CivilDate(year: 2026, month: 1, day: 1)!,
            anchorDate: CivilDate(year: 2026, month: 1, day: 1)!,
            repeatDays: 365, type: .fixedDebit, label: "Prior annual repeat", matchingString: nil,
            amount: 365, notes: ""
        )
        let currentShortRevision = PeriodicRepeatRevision(
            id: UUID(), repeatID: revisedID,
            effectiveDate: CivilDate(year: 2026, month: 3, day: 1)!,
            anchorDate: CivilDate(year: 2026, month: 3, day: 1)!,
            repeatDays: 28, type: .fixedDebit, label: "Revised four-week repeat", matchingString: nil,
            amount: 28, notes: ""
        )
        let revisions = [shortRevision, longRevision, priorLongRevision, currentShortRevision]
        let repeats = [shortRepeat, longRepeat, revisedRepeat]

        XCTAssertEqual(
            PeriodicRepeatSchedule.monthlySavingsTarget(revisions: revisions, effectiveOn: effectiveOn),
            Decimal(string: "30.436875")!
        )
        XCTAssertEqual(
            PeriodicRepeatSchedule.annualizedCost(repeats: repeats, revisions: revisions, effectiveOn: effectiveOn),
            Decimal(string: "365.2425")!
        )
        XCTAssertEqual(
            PeriodicRepeatSchedule.monthlySavingsTarget(repeats: repeats, revisions: revisions, effectiveOn: effectiveOn),
            Decimal(string: "30.436875")!
        )
    }

    func testEndedRepeatStopsContributingOnItsExclusiveEndDate() throws {
        let repeatID = UUID()
        let date = CivilDate(year: 2026, month: 4, day: 1)!
        let repeatRecord = PeriodicRepeat(
            id: repeatID, budgetID: UUID(), accountID: UUID(),
            endDate: CivilDate(year: 2026, month: 4, day: 1)!
        )
        let revision = PeriodicRepeatRevision(
            id: UUID(), repeatID: repeatID,
            effectiveDate: CivilDate(year: 2026, month: 1, day: 1)!,
            anchorDate: CivilDate(year: 2026, month: 1, day: 1)!,
            repeatDays: 365, type: .fixedDebit, label: "Holiday", matchingString: nil,
            amount: 1200, notes: ""
        )

        XCTAssertEqual(
            PeriodicRepeatSchedule.monthlySavingsTarget(repeats: [repeatRecord], revisions: [revision], effectiveOn: date),
            Decimal.zero
        )
        XCTAssertGreaterThan(
            PeriodicRepeatSchedule.monthlySavingsTarget(
                repeats: [repeatRecord], revisions: [revision],
                effectiveOn: CivilDate(year: 2026, month: 3, day: 31)!
            ),
            Decimal.zero
        )
    }

    private func nextMonth(after month: YearMonth) -> YearMonth {
        var year = month.year
        var value = month.month + 1
        if value > 12 {
            value = 1
            year += 1
        }
        return YearMonth(year: year, month: value)
    }

    private func previousMonth(before month: YearMonth) -> YearMonth {
        let year = month.month == 1 ? month.year - 1 : month.year
        let value = month.month == 1 ? 12 : month.month - 1
        return YearMonth(year: year, month: value)
    }

    func testBootstrapCreatesLocalBudgetAndLoadsCurrentMonth() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        XCTAssertEqual(try repository.activeBudget()?.sharingState, .local)
        XCTAssertEqual(try repository.activeBudget()?.usesSeparateAccountForDailyBudget, false)
        XCTAssertTrue(state.monthItems.isEmpty)
        XCTAssertEqual(state.primaryBankBalance, 0)
        XCTAssertTrue(state.canNavigateToNextMonth)
        XCTAssertEqual(state.primaryBankName, "Nationwide")
    }

    func testCanNavigateToNextMonthWhenCurrentMonthIsEmpty() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        XCTAssertFalse(state.isSelectedMonthInFuture)
        XCTAssertTrue(state.monthItems.isEmpty)
        XCTAssertTrue(state.canNavigateToNextMonth)
    }

    func testCannotNavigateToNextMonthWhenFutureMonthIsEmpty() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        state.selectedMonth = nextMonth(after: state.selectedMonth)
        try state.refresh()

        XCTAssertTrue(state.isSelectedMonthInFuture)
        XCTAssertTrue(state.monthItems.isEmpty)
        XCTAssertFalse(state.canNavigateToNextMonth)
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

    func testPreviousMonthEditingSettingPersistsOnActiveBudget() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        XCTAssertFalse(state.allowsPreviousMonthEditing)
        XCTAssertFalse(try XCTUnwrap(try repository.activeBudget()).allowsPreviousMonthEditing)

        state.allowsPreviousMonthEditing = true

        XCTAssertTrue(state.allowsPreviousMonthEditing)
        XCTAssertTrue(try XCTUnwrap(try repository.activeBudget()).allowsPreviousMonthEditing)
    }

    func testCurrentBudgetMonthChangesOnPaydayBoundaryForBalanceEditing() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            nowProvider: { Self.date(year: 2026, month: 6, day: 27) }
        )

        await state.bootstrapIfNeeded()
        state.dailyBudgetPaydayDay = 26

        state.selectedMonth = YearMonth(year: 2026, month: 6)
        try state.refresh()
        state.primaryBankBalance = 100

        XCTAssertTrue(state.isSelectedMonthInPast)
        XCTAssertEqual(state.primaryBankBalance, 0)

        state.selectedMonth = YearMonth(year: 2026, month: 7)
        try state.refresh()
        state.primaryBankBalance = 200

        XCTAssertFalse(state.isSelectedMonthInPast)
        XCTAssertFalse(state.isSelectedMonthInFuture)
        XCTAssertEqual(state.primaryBankBalance, 200)
    }

    func testCurrentBudgetMonthStaysOnPreviousMonthBeforePayday() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            nowProvider: { Self.date(year: 2026, month: 6, day: 25) }
        )

        await state.bootstrapIfNeeded()
        state.dailyBudgetPaydayDay = 26

        state.selectedMonth = YearMonth(year: 2026, month: 6)
        try state.refresh()

        XCTAssertFalse(state.isSelectedMonthInPast)
        XCTAssertFalse(state.isSelectedMonthInFuture)

        state.selectedMonth = YearMonth(year: 2026, month: 7)
        try state.refresh()

        XCTAssertTrue(state.isSelectedMonthInFuture)
    }

    func testDaysRemainingInSelectedMonthUsesPaydayCycle() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            nowProvider: { Self.date(year: 2026, month: 6, day: 27) }
        )

        await state.bootstrapIfNeeded()
        state.dailyBudgetPaydayDay = 26
        state.selectedMonth = YearMonth(year: 2026, month: 7)
        try state.refresh()

        XCTAssertEqual(state.daysRemainingInMonth, 29)
    }

    func testHiddenDailyAccountCanBeCreatedAndExcludedFromVisibleAccounts() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        let budget = try XCTUnwrap(try repository.activeBudget())
        XCTAssertEqual(budget.name, "Budget")

        budget.usesSeparateAccountForDailyBudget = true
        try repository.saveBudget(budget)

        let hiddenAccount = try XCTUnwrap(repository.ensureHiddenDailyAccount(for: budget))
        let hiddenAccountAgain = try XCTUnwrap(repository.hiddenDailyAccount(for: budget))

        XCTAssertEqual(hiddenAccount.id, hiddenAccountAgain.id)
        XCTAssertEqual(hiddenAccount.name, "Daily budget")
        XCTAssertEqual(try repository.activeBudget()?.hiddenDailyAccountID, hiddenAccount.id)
        let visibleAccountIDs = Set(try repository.accounts().map(\.id))
        XCTAssertFalse(visibleAccountIDs.contains(hiddenAccount.id))
        XCTAssertEqual(visibleAccountIDs.count, 1)
    }

    func testHiddenDailyAccountPersistsAcrossSwiftDataRepositoryRecreation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let plan = MonthlyMoneyPersistencePlan(
            privateStore: MonthlyMoneyStorePlan(
                name: "PrivateStore",
                url: directory.appendingPathComponent("PrivateStore.store"),
                syncMode: .localOnly,
                backend: .swiftData
            ),
            sharedStore: MonthlyMoneyStorePlan(
                name: "SharedStore",
                url: directory.appendingPathComponent("SharedStore.store"),
                syncMode: .localOnly,
                backend: .swiftData
            )
        )
        let repository = try MonthlyMoneyPersistenceFactory.makeRepository(
            plan: plan,
            schema: Self.makeSchema()
        )
        Self.retainHostedTestObject(repository)
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        let budget = try XCTUnwrap(try repository.activeBudget())
        budget.usesSeparateAccountForDailyBudget = true
        try repository.saveBudget(budget)
        let hiddenAccount = try XCTUnwrap(repository.ensureHiddenDailyAccount(for: budget))

        let reloadedRepository = try MonthlyMoneyPersistenceFactory.makeRepository(
            plan: plan,
            schema: Self.makeSchema()
        )
        Self.retainHostedTestObject(reloadedRepository)

        let reloadedBudget = try XCTUnwrap(try reloadedRepository.activeBudget())
        XCTAssertEqual(reloadedBudget.hiddenDailyAccountID, hiddenAccount.id)
    }

    func testSwiftDataV1BudgetMigratesPreviousMonthEditingToOff() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("Budget.store")
        let budgetID = UUID()

        do {
            let legacySchema = Schema(
                MonthlyMoneySchemaV1.models,
                version: MonthlyMoneySchemaV1.versionIdentifier
            )
            let configuration = ModelConfiguration(
                "Legacy",
                schema: legacySchema,
                url: storeURL,
                cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: legacySchema, configurations: [configuration])
            container.mainContext.insert(
                MonthlyMoneySchemaV1.Budget(
                    id: budgetID,
                    name: "Legacy budget",
                    ownerParticipantID: "owner"
                )
            )
            try container.mainContext.save()
        }

        let currentSchema = Schema(versionedSchema: MonthlyMoneySchemaV3.self)
        let configuration = ModelConfiguration(
            "Current",
            schema: currentSchema,
            url: storeURL,
            cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: currentSchema,
            migrationPlan: MonthlyMoneySchemaMigrationPlan.self,
            configurations: [configuration]
        )
        let migratedBudget = try XCTUnwrap(
            container.mainContext.fetch(
                FetchDescriptor<Budget>(predicate: #Predicate { $0.id == budgetID })
            ).first
        )

        XCTAssertFalse(migratedBudget.allowsPreviousMonthEditing)
        XCTAssertEqual(migratedBudget.name, "Legacy budget")
    }

    func testSwiftDataV2BackfillsPeriodicDefinitionsAndPreservesOccurrenceDates() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("Budget.store")
        let budgetID = UUID()
        let firstAccountID = UUID()
        let secondAccountID = UUID()
        let recurrenceID = UUID()
        let latestID = UUID()
        let invalidID = UUID()

        do {
            let legacySchema = Schema(versionedSchema: MonthlyMoneySchemaV2.self)
            let configuration = ModelConfiguration(
                "LegacyV2", schema: legacySchema, url: storeURL, cloudKitDatabase: .none
            )
            let container = try ModelContainer(for: legacySchema, configurations: [configuration])
            container.mainContext.insert(Budget(
                id: budgetID, name: "Legacy budget", ownerParticipantID: "owner",
                dailyBudgetPaydayDay: 26
            ))
            container.mainContext.insert(Account(
                id: firstAccountID, budgetID: budgetID, name: "Current", role: .regular, type: .current
            ))
            container.mainContext.insert(Account(
                id: secondAccountID, budgetID: budgetID, name: "Savings", role: .regular, type: .cash
            ))
            container.mainContext.insert(PlannedItem(
                id: UUID(), budgetID: budgetID, accountID: firstAccountID,
                monthKey: YearMonth(year: 2026, month: 4), type: .fixedDebit,
                label: "Subscription", amount: 10, dueDay: 28, repeatDays: 28,
                recurrenceID: recurrenceID, repeatMode: .periodic
            ))
            container.mainContext.insert(PlannedItem(
                id: latestID, budgetID: budgetID, accountID: firstAccountID,
                monthKey: YearMonth(year: 2026, month: 6), type: .fixedDebit,
                label: "Subscription", amount: 10, dueDay: 30, repeatDays: 28,
                recurrenceID: recurrenceID, repeatMode: .periodic, isPaid: true
            ))
            container.mainContext.insert(PlannedItem(
                id: invalidID, budgetID: budgetID, accountID: secondAccountID,
                monthKey: YearMonth(year: 2026, month: 6), type: .fixedDebit,
                label: "Invalid", amount: 5, dueDay: nil, repeatDays: 0,
                recurrenceID: UUID(), repeatMode: .periodic
            ))
            try container.mainContext.save()
        }

        let currentSchema = Schema(versionedSchema: MonthlyMoneySchemaV3.self)
        let configuration = ModelConfiguration(
            "CurrentV3", schema: currentSchema, url: storeURL, cloudKitDatabase: .none
        )
        let container = try ModelContainer(
            for: currentSchema,
            migrationPlan: MonthlyMoneySchemaMigrationPlan.self,
            configurations: [configuration]
        )
        let repeats = try container.mainContext.fetch(FetchDescriptor<PeriodicRepeat>())
        let revisions = try container.mainContext.fetch(FetchDescriptor<PeriodicRepeatRevision>())
        let occurrences = try container.mainContext.fetch(FetchDescriptor<PeriodicOccurrenceRecord>())
        let plannedItems = try container.mainContext.fetch(FetchDescriptor<PlannedItem>())

        XCTAssertEqual(repeats.count, 1)
        XCTAssertEqual(revisions.count, 1)
        XCTAssertEqual(revisions.first?.anchorDate, CivilDate(year: 2026, month: 5, day: 30))
        XCTAssertEqual(occurrences.count, 2)
        XCTAssertEqual(occurrences.first(where: { $0.plannedItemID == latestID })?.scheduledDate, CivilDate(year: 2026, month: 5, day: 30))
        XCTAssertEqual(occurrences.first(where: { $0.plannedItemID == latestID })?.dueDate, CivilDate(year: 2026, month: 5, day: 30))
        XCTAssertEqual(plannedItems.first(where: { $0.id == latestID })?.monthKey, "2026-06")
        XCTAssertEqual(plannedItems.first(where: { $0.id == latestID })?.dueDay, 30)
        XCTAssertTrue(plannedItems.first(where: { $0.id == latestID })?.isPaid ?? false)
        XCTAssertFalse(occurrences.contains { $0.plannedItemID == invalidID })
    }

    func testFailedMigratedStoreReplacementPreservesOriginalStore() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let storeURL = directory.appendingPathComponent("Store.sqlite")
        let container = NSPersistentContainer(
            name: "MonthlyMoneyCoreData", managedObjectModel: CoreDataModelBuilder.v6Model
        )
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        if let store = container.persistentStoreCoordinator.persistentStores.first {
            try container.persistentStoreCoordinator.remove(store)
        }
        let originalMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: storeURL, options: nil
        )
        let originalStoreID = try XCTUnwrap(originalMetadata[NSStoreUUIDKey] as? String)
        let missingMigrationURL = directory.appendingPathComponent("MissingMigration.sqlite")

        XCTAssertThrowsError(
            try CoreDataAccountDataStore.replaceMigratedStore(from: missingMigrationURL, at: storeURL)
        )
        let restoredMetadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType, at: storeURL, options: nil
        )
        XCTAssertEqual(restoredMetadata[NSStoreUUIDKey] as? String, originalStoreID)
    }

    func testCoreDataV5MigrationBackfillsPeriodicDefinitionAndPreservesProtectedRow() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("CoreData.store")
        let budgetID = UUID()
        let accountID = UUID()
        let recurrenceID = UUID()
        let plannedItemID = UUID()
        let container = NSPersistentContainer(
            name: "MonthlyMoneyV5", managedObjectModel: CoreDataModelBuilder.sharedModel
        )
        let description = NSPersistentStoreDescription(url: storeURL)
        description.type = NSSQLiteStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }

        let context = container.viewContext
        let budget = NSEntityDescription.insertNewObject(
            forEntityName: CoreDataEntityName.budget, into: context
        )
        CoreDataMapping.apply(Budget(
            id: budgetID, name: "Legacy", ownerParticipantID: "owner", dailyBudgetPaydayDay: 26
        ), to: budget)
        let account = NSEntityDescription.insertNewObject(
            forEntityName: CoreDataEntityName.account, into: context
        )
        CoreDataMapping.apply(Account(
            id: accountID, budgetID: budgetID, name: "Current", role: .regular, type: .current
        ), to: account)
        account.setValue(budget, forKey: "budget")
        let item = NSEntityDescription.insertNewObject(
            forEntityName: CoreDataEntityName.plannedItem, into: context
        )
        CoreDataMapping.apply(PlannedItem(
            id: plannedItemID, budgetID: budgetID, accountID: accountID,
            monthKey: YearMonth(year: 2026, month: 6), type: .fixedDebit,
            label: "Insurance", amount: 300, dueDay: 30, repeatDays: 29,
            recurrenceID: recurrenceID, repeatMode: .periodic,
            importedPostedAt: Self.date(year: 2026, month: 5, day: 31), isPaid: true
        ), to: item)
        item.setValue(budget, forKey: "budget")
        budget.mutableSetValue(forKey: "accounts").add(account)
        budget.mutableSetValue(forKey: "plannedItems").add(item)
        try context.save()
        if let persistentStore = container.persistentStoreCoordinator.persistentStores.first {
            try container.persistentStoreCoordinator.remove(persistentStore)
        }

        let migrated = try CoreDataAccountDataStore.makePersistentLocal(url: storeURL)
        let repeats = try migrated.fetchPeriodicRepeats(budgetID: budgetID)
        let repeatIDs = Set(repeats.map(\.id))
        let revisions = try migrated.fetchPeriodicRepeatRevisions(repeatIDs: repeatIDs)
        let occurrences = try migrated.fetchPeriodicOccurrences(plannedItemIDs: [plannedItemID])
        let savedItem = try XCTUnwrap(migrated.fetchPlannedItem(id: plannedItemID))

        XCTAssertEqual(repeats.count, 1)
        XCTAssertEqual(revisions.first?.anchorDate, CivilDate(year: 2026, month: 5, day: 30))
        XCTAssertEqual(occurrences.first?.scheduledDate, CivilDate(year: 2026, month: 5, day: 30))
        XCTAssertEqual(savedItem.monthKey, "2026-06")
        XCTAssertEqual(savedItem.dueDay, 30)
        XCTAssertTrue(savedItem.isPaid)
        XCTAssertEqual(savedItem.importedPostedAt, Self.date(year: 2026, month: 5, day: 31))
    }

    func testRefreshCreatesHiddenDailyAccountForExistingSeparateDailyBudget() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        let budget = try XCTUnwrap(try repository.activeBudget())
        budget.usesSeparateAccountForDailyBudget = true
        try repository.saveBudget(budget)

        XCTAssertNil(try repository.hiddenDailyAccount(for: budget))

        try state.refresh()

        let refreshedBudget = try XCTUnwrap(try repository.activeBudget())
        let hiddenAccount = try XCTUnwrap(repository.hiddenDailyAccount(for: refreshedBudget))
        XCTAssertEqual(refreshedBudget.hiddenDailyAccountID, hiddenAccount.id)
        XCTAssertEqual(try repository.accounts().count, 1)
    }

    func testRefreshDoesNotDuplicateHiddenDailyAccountForExistingSeparateDailyBudget() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        let budget = try XCTUnwrap(try repository.activeBudget())
        budget.usesSeparateAccountForDailyBudget = true
        try repository.saveBudget(budget)

        try state.refresh()
        let firstBudget = try XCTUnwrap(try repository.activeBudget())
        let firstHiddenAccountID = try XCTUnwrap(repository.hiddenDailyAccount(for: firstBudget)?.id)

        try state.refresh()

        let refreshedBudget = try XCTUnwrap(try repository.activeBudget())
        XCTAssertEqual(try repository.hiddenDailyAccount(for: refreshedBudget)?.id, firstHiddenAccountID)
        XCTAssertEqual(try repository.accounts().count, 1)
    }

    func testBudgetDefaultsWheelOfMoneySavingsGenerationToOff() {
        let budget = Budget(name: "Household", ownerParticipantID: "rog")

        XCTAssertFalse(budget.autoGenerateWoMSavingsEveryMonth)
        XCTAssertFalse(budget.allowsPreviousMonthEditing)
    }

    func testWheelOfMoneyItemStoresCoreFields() {
        let budgetID = UUID()
        let item = WheelOfMoneyItem(
            budgetID: budgetID,
            title: "Christmas",
            amount: 1000,
            month: 12,
            isPaid: false,
            notes: "Presents",
            isAutoGeneratedSavingsEntry: true
        )

        XCTAssertEqual(item.budgetID, budgetID)
        XCTAssertEqual(item.title, "Christmas")
        XCTAssertEqual(item.amount, 1000)
        XCTAssertEqual(item.month, 12)
        XCTAssertFalse(item.isPaid)
        XCTAssertEqual(item.notes, "Presents")
        XCTAssertTrue(item.isAutoGeneratedSavingsEntry)
    }

    func testBootstrapLeavesWheelOfMoneyEmpty() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        XCTAssertTrue(state.wheelOfMoneyItems.isEmpty)
    }

    func testWheelOfMoneyMetricsAndPendingFilter() {
        let budgetID = UUID()
        let items = [
            WheelOfMoneyItem(budgetID: budgetID, title: "Car insurance", amount: 900, month: WheelOfMoneyMonth.march.rawValue, isPaid: false),
            WheelOfMoneyItem(budgetID: budgetID, title: "Christmas", amount: 1000, month: WheelOfMoneyMonth.december.rawValue, isPaid: false),
            WheelOfMoneyItem(budgetID: budgetID, title: "J Birthday", amount: 150, month: WheelOfMoneyMonth.may.rawValue, isPaid: true)
        ]

        let metrics = WheelOfMoneyCalculator.metrics(items: items, currentMonth: 3)

        XCTAssertEqual(metrics.annualTotal, 2050)
        XCTAssertEqual(metrics.monthlyAverage, Decimal(2050) / Decimal(12))
        XCTAssertEqual(metrics.pendingTotal, 1900)
        XCTAssertEqual(metrics.remainingAverage, Decimal(1900) / Decimal(10))
        XCTAssertTrue(metrics.remainingAverageExceedsMonthlyAverage)
        XCTAssertEqual(
            WheelOfMoneyFilterRules.filteredItems(items, for: .pending).map(\.title).sorted(),
            ["Car insurance", "Christmas"]
        )
    }

    func testEnablingWheelOfMoneySavingsGenerationDoesNotCreateEntriesImmediately() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        XCTAssertFalse(state.autoGenerateWoMSavingsEveryMonth)

        try repository.createWheelOfMoneyItem(
            WheelOfMoneyItem(
                budgetID: UUID(),
                title: "Car insurance",
                amount: 900,
                month: WheelOfMoneyMonth.march.rawValue,
                isPaid: false
            )
        )
        try state.refresh()

        state.autoGenerateWoMSavingsEveryMonth = true
        XCTAssertFalse(
            try repository.plannedItems(for: state.selectedMonth).contains(where: { $0.label == "WoM savings" })
        )
    }

    func testPopulatingMonthCreatesWheelOfMoneySavingsDebitWhenEnabled() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        state.autoGenerateWoMSavingsEveryMonth = true
        let targetMonth = state.selectedMonth
        let budget = try XCTUnwrap(try repository.activeBudget())
        let account = try XCTUnwrap(try repository.accounts().first)
        let repeatRecord = PeriodicRepeat(budgetID: budget.id, accountID: account.id)
        let anchor = CivilDate(year: 2026, month: 1, day: 1)!
        let revision = PeriodicRepeatRevision(
            repeatID: repeatRecord.id,
            effectiveDate: anchor,
            anchorDate: anchor,
            repeatDays: 365,
            type: .fixedDebit,
            label: "Car insurance",
            matchingString: nil,
            amount: 900,
            notes: ""
        )
        try repository.savePeriodicRepeat(repeatRecord)
        try repository.savePeriodicRepeatRevisions([revision], budgetID: budget.id)
        let sourceMonth = previousMonth(before: targetMonth)
        try repository.createPlannedItem(
            PlannedItem(
                accountID: account.id,
                monthKey: sourceMonth,
                type: .fixedDebit,
                label: "Rent",
                amount: 1200,
                dueDay: 1,
                isPaid: false
            )
        )
        state.selectedMonth = targetMonth
        try state.refresh()

        state.populateSelectedMonthFromPrevious()

        let savingsDebit = try XCTUnwrap(
            try repository.plannedItems(for: targetMonth).first(where: { $0.label == "WoM savings" })
        )
        let expectedAmount = state.monthlyPeriodicRepeatSavingsTarget

        XCTAssertEqual(savingsDebit.type, .fixedDebit)
        XCTAssertEqual(savingsDebit.amount, expectedAmount)
        XCTAssertNil(savingsDebit.dueDay)
        XCTAssertFalse(savingsDebit.isPaid)
        XCTAssertFalse(savingsDebit.copiesToNextMonthAutomatically)
    }

    func testPopulatingMonthCopiesAutoCopiedPreviousMonthItems() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let targetMonth = state.selectedMonth
        let sourceMonth = previousMonth(before: targetMonth)
        let accountID = try XCTUnwrap(try repository.accounts().first).id
        try repository.createPlannedItem(
            PlannedItem(
                accountID: accountID,
                monthKey: sourceMonth,
                type: .fixedDebit,
                label: "Rent",
                amount: 1200,
                dueDay: 1,
                isPaid: false,
                copiesToNextMonthAutomatically: true
            )
        )

        state.selectedMonth = targetMonth
        try state.refresh()
        state.populateSelectedMonthFromPrevious()

        let copiedItem = try XCTUnwrap(
            try repository.plannedItems(for: targetMonth).first(where: { $0.label == "Rent" })
        )

        XCTAssertEqual(copiedItem.source, .copiedFromPreviousMonth)
        XCTAssertEqual(copiedItem.amount, 1200)
        XCTAssertEqual(copiedItem.dueDay, 1)
        XCTAssertFalse(copiedItem.isPaid)
    }

    func testPeriodicPopulationUsesCanonicalRepeatScheduleAcrossMonths() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let targetMonth = state.selectedMonth
        let anchor = try XCTUnwrap(state.createEntry(
            type: .fixedDebit,
            label: "Pension",
            amount: 100,
            dueDay: 1,
            repeatDays: 10
        ))
        let recurrenceID = try XCTUnwrap(anchor.recurrenceID)
        let projected = state.womOccurrenceGroups
            .flatMap(\.occurrences)
            .filter { $0.repeatID == recurrenceID }
        XCTAssertGreaterThan(projected.count, 24)
        XCTAssertEqual(state.womOccurrenceGroups.first?.month, targetMonth)

        state.populateSameMonth(for: anchor)

        XCTAssertEqual(
            try repository.plannedItems(for: targetMonth)
                .filter { $0.recurrenceID == recurrenceID }
                .compactMap(\.dueDay)
                .sorted(),
            [1, 11, 21]
        )
    }

    func testPopulatingMonthDoesNotCreateWheelOfMoneySavingsDebitWhenDisabled() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let targetMonth = state.selectedMonth
        let sourceMonth = previousMonth(before: targetMonth)
        let accountID = try XCTUnwrap(try repository.accounts().first).id
        try repository.createPlannedItem(
            PlannedItem(
                accountID: accountID,
                monthKey: sourceMonth,
                type: .fixedDebit,
                label: "Rent",
                amount: 1200,
                dueDay: 1,
                isPaid: false
            )
        )
        state.selectedMonth = targetMonth
        try state.refresh()

        state.populateSelectedMonthFromPrevious()

        XCTAssertFalse(
            try repository.plannedItems(for: targetMonth).contains(where: { $0.label == "WoM savings" })
        )
    }

    func testPopulatingMonthCreatesWheelOfMoneySavingsDebitEvenWhenPreviousMonthIsEmpty() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        try repository.createWheelOfMoneyItem(
            WheelOfMoneyItem(
                budgetID: UUID(),
                title: "Car insurance",
                amount: 900,
                month: WheelOfMoneyMonth.march.rawValue,
                isPaid: false
            )
        )
        state.autoGenerateWoMSavingsEveryMonth = true
        let targetMonth = state.selectedMonth
        state.selectedMonth = targetMonth
        try state.refresh()

        state.populateSelectedMonthFromPrevious()

        XCTAssertTrue(
            try repository.plannedItems(for: targetMonth).contains(where: { $0.label == "WoM savings" })
        )
    }

    func testExistingWheelOfMoneySavingsDebitIsNotDuplicated() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        try repository.createWheelOfMoneyItem(
            WheelOfMoneyItem(
                budgetID: UUID(),
                title: "Car insurance",
                amount: 900,
                month: WheelOfMoneyMonth.march.rawValue,
                isPaid: false
            )
        )
        let targetMonth = state.selectedMonth
        let sourceMonth = previousMonth(before: targetMonth)
        let accountID = try XCTUnwrap(try repository.accounts().first).id
        try repository.createPlannedItem(
            PlannedItem(
                accountID: accountID,
                monthKey: sourceMonth,
                type: .fixedDebit,
                label: "Rent",
                amount: 1200,
                dueDay: 1,
                isPaid: false
            )
        )
        try repository.createPlannedItem(
            PlannedItem(
                accountID: accountID,
                monthKey: targetMonth,
                type: .fixedDebit,
                label: "WoM savings",
                amount: 123,
                dueDay: nil,
                isPaid: false,
                copiesToNextMonthAutomatically: false
            )
        )
        state.autoGenerateWoMSavingsEveryMonth = true
        state.selectedMonth = targetMonth
        try state.refresh()

        state.populateSelectedMonthFromPrevious()

        let matchingDebits = try repository.plannedItems(for: targetMonth)
            .filter { $0.label == "WoM savings" }

        XCTAssertEqual(matchingDebits.count, 1)
        XCTAssertEqual(matchingDebits.first?.amount, 123)
    }

    func testCreatingWheelOfMoneyEntryUpdatesAnnualTotal() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let originalTotal = state.wheelOfMoneyMetrics.annualTotal

        _ = state.createWheelOfMoneyEntry(
            title: "Boiler service",
            amount: 600,
            month: WheelOfMoneyMonth.october.rawValue
        )

        XCTAssertEqual(state.wheelOfMoneyMetrics.annualTotal, originalTotal + 600)
    }

    func testWheelOfMoneyRowContentShowsOnlyTrimmedNotes() {
        let item = WheelOfMoneyItem(
            budgetID: UUID(),
            title: "Christmas",
            amount: 1000,
            month: WheelOfMoneyMonth.december.rawValue,
            notes: "  Presents  "
        )
        let emptyNotes = WheelOfMoneyItem(
            budgetID: UUID(),
            title: "Car insurance",
            amount: 900,
            month: WheelOfMoneyMonth.march.rawValue,
            notes: "   "
        )

        XCTAssertEqual(WheelOfMoneyRowContent.notesLine(for: item), "Presents")
        XCTAssertNil(WheelOfMoneyRowContent.notesLine(for: emptyNotes))
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

    func testCurrentMonthBalanceEditUpdatesMonthlyAndDailyLastUpdatedWhenDailyUsesProjectedFunds() async throws {
        var repositoryNow = Self.date(year: 2026, month: 3, day: 12, hour: 8, minute: 0)
        let updatedAt = Self.date(year: 2026, month: 3, day: 12, hour: 9, minute: 30)
        let repository = try makeRepository(dateProvider: { repositoryNow })
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        repositoryNow = updatedAt
        state.primaryBankBalance = 1234

        let budget = try XCTUnwrap(try repository.activeBudget())
        XCTAssertEqual(budget.monthlyBalanceLastUpdatedAt, updatedAt)
        XCTAssertEqual(budget.dailyBalanceLastUpdatedAt, updatedAt)
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

    func testDailySeparateAccountBalanceEditUpdatesOnlyDailyLastUpdated() async throws {
        var repositoryNow = Self.date(year: 2026, month: 3, day: 12, hour: 8, minute: 0)
        let updatedAt = Self.date(year: 2026, month: 3, day: 12, hour: 10, minute: 45)
        let repository = try makeRepository(dateProvider: { repositoryNow })
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let originalMonthlyUpdatedAt = try XCTUnwrap((try repository.activeBudget())?.monthlyBalanceLastUpdatedAt)
        repositoryNow = updatedAt
        state.usesSeparateAccountForDailyBudget = true
        state.dailyBudgetSeparateAccountBalance = 888

        let budget = try XCTUnwrap(try repository.activeBudget())
        XCTAssertEqual(budget.monthlyBalanceLastUpdatedAt, originalMonthlyUpdatedAt)
        XCTAssertEqual(budget.dailyBalanceLastUpdatedAt, updatedAt)
    }

    func testSetPaidUpdatesMonthlyAndDailyLastUpdated() async throws {
        var repositoryNow = Self.date(year: 2026, month: 3, day: 12, hour: 8, minute: 0)
        let updatedAt = Self.date(year: 2026, month: 3, day: 12, hour: 11, minute: 15)
        let repository = try makeRepository(dateProvider: { repositoryNow })
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let account = try XCTUnwrap(try repository.accounts().first)
        let item = PlannedItem(
            accountID: account.id,
            monthKey: state.selectedMonth,
            type: .fixedDebit,
            label: "Rent",
            amount: 900,
            dueDay: 14,
            isPaid: false
        )
        try repository.createPlannedItem(item)
        try state.refresh()

        repositoryNow = updatedAt
        state.setPaid(item: item, paid: true)

        let budget = try XCTUnwrap(try repository.activeBudget())
        XCTAssertEqual(budget.monthlyBalanceLastUpdatedAt, updatedAt)
        XCTAssertEqual(budget.dailyBalanceLastUpdatedAt, updatedAt)
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

    func testDailyBalanceChartReconstructsEarlierBalancesAcrossCycle() {
        let calendar = Self.utcCalendar
        let accountID = UUID()
        let budgetID = UUID()
        let points = DailyBalanceChartCalculator.points(
            currentBalance: 200,
            today: Self.date(year: 2026, month: 3, day: 12),
            paydayDay: 10,
            transactions: [
                Transaction(
                    budgetID: budgetID,
                    accountID: accountID,
                    monthKey: YearMonth(year: 2026, month: 3),
                    amount: -15,
                    sourcePostedAt: Self.date(year: 2026, month: 3, day: 11)
                ),
                Transaction(
                    budgetID: budgetID,
                    accountID: accountID,
                    monthKey: YearMonth(year: 2026, month: 3),
                    amount: 20,
                    sourcePostedAt: Self.date(year: 2026, month: 3, day: 12)
                )
            ],
            calendar: calendar
        )

        XCTAssertEqual(points.map { calendar.component(.day, from: $0.date) }, [10, 11, 12])
        XCTAssertEqual(points.map(\.balance), [195, 180, 200])
    }

    func testDailyBalanceChartHandlesEmptyHiddenAccountTransactions() {
        let calendar = Self.utcCalendar
        let points = DailyBalanceChartCalculator.points(
            currentBalance: 123,
            today: Self.date(year: 2026, month: 3, day: 12),
            paydayDay: 10,
            transactions: [],
            calendar: calendar
        )

        XCTAssertEqual(points.map { calendar.component(.day, from: $0.date) }, [10, 11, 12])
        XCTAssertEqual(points.map(\.balance), [123, 123, 123])
    }

    func testDailyBalanceChartPointsUseCurrentBalanceWhenSeparateDailyAccountIsDisabled() async throws {
        let repository = try makeRepository()
        let fixedNow = Self.date(year: 2026, month: 3, day: 12)
        let state = AppState(repository: repository, nowProvider: { fixedNow })

        await state.bootstrapIfNeeded()
        state.primaryBankBalance = 150

        XCTAssertFalse(state.usesSeparateAccountForDailyBudget)
        XCTAssertEqual(state.dailyBalanceChartPoints.first?.balance, 150)
        XCTAssertEqual(state.dailyBalanceChartPoints.last?.balance, 150)
    }

    func testDailyBalanceChartPointsUseVisibleAccountTransactionsWhenSeparateDailyAccountIsDisabled() async throws {
        let repository = try makeRepository()
        let fixedNow = Self.date(year: 2026, month: 3, day: 12)
        let state = AppState(repository: repository, nowProvider: { fixedNow })

        await state.bootstrapIfNeeded()
        state.dailyBudgetPaydayDay = 10
        state.selectedMonth = YearMonth(year: 2026, month: 4)
        try state.refresh()
        state.primaryBankBalance = 200

        let account = try XCTUnwrap(try repository.accounts().first)
        try repository.createPlannedItem(
            PlannedItem(
                accountID: account.id,
                monthKey: YearMonth(year: 2026, month: 4),
                type: .fixedDebit,
                label: "Coffee",
                amount: 15,
                dueDay: 11,
                isPaid: true
            )
        )

        try state.refresh()

        XCTAssertEqual(state.dailyBalanceChartPoints.map(\.balance), [215, 200, 200])
    }

    func testDailyBudgetWatchSnapshotContainsSixReadOnlyChips() async throws {
        let repository = try makeRepository()
        let fixedNow = Self.date(year: 2026, month: 3, day: 12)
        let state = AppState(repository: repository, nowProvider: { fixedNow })

        await state.bootstrapIfNeeded()
        state.dailyBudgetAmount = 310
        state.dailyBudgetPaydayDay = 10
        state.selectedMonth = YearMonth(year: 2026, month: 4)
        try state.refresh()
        state.primaryBankBalance = 200

        let snapshot = state.dailyBudgetWatchSnapshot

        XCTAssertEqual(snapshot.chips.count, 6)
        XCTAssertEqual(snapshot.chips.map(\.title), [
            "Budget",
            "Avg. Day",
            "Balance",
            "Behind",
            "Current Day",
            "Days left"
        ])
        XCTAssertEqual(snapshot.chips[0].value, AppState.currency(310))
        XCTAssertEqual(snapshot.chips[2].value, AppState.currency(200))
        XCTAssertEqual(snapshot.chips[3].value, AppState.currency(90))
        XCTAssertEqual(snapshot.chips[5].value, "29")
    }

    func testDailyBudgetWidgetSnapshotContainsAheadBehindAndCurrentDay() async throws {
        let repository = try makeRepository()
        let fixedNow = Self.date(year: 2026, month: 3, day: 12)
        let state = AppState(repository: repository, nowProvider: { fixedNow })

        await state.bootstrapIfNeeded()
        state.dailyBudgetAmount = 310
        state.dailyBudgetPaydayDay = 10
        state.selectedMonth = YearMonth(year: 2026, month: 4)
        try state.refresh()
        state.primaryBankBalance = 200

        let snapshot = state.dailyBudgetWidgetSnapshot

        XCTAssertEqual(snapshot.chips.count, 2)
        XCTAssertEqual(snapshot.chips.map(\.title), [
            "Behind",
            "Current Day"
        ])
        XCTAssertEqual(snapshot.chips[0].value, AppState.currency(90))
        XCTAssertEqual(snapshot.chips[1].value, AppState.currency(6.90))
    }

    func testDailyPresentationContentUsesAheadBehindLabelAndAbsoluteValue() {
        XCTAssertEqual(DailyPresentationContent.aheadBehindTitle(for: 20), "Ahead")
        XCTAssertEqual(DailyPresentationContent.aheadBehindTitle(for: 0), "Ahead")
        XCTAssertEqual(DailyPresentationContent.aheadBehindTitle(for: -20), "Behind")
        XCTAssertEqual(DailyPresentationContent.aheadBehindValue(for: 20), AppState.currency(20))
        XCTAssertEqual(DailyPresentationContent.aheadBehindValue(for: -20), AppState.currency(20))
    }

    func testRefreshPublishesDailyBudgetWatchSnapshot() async throws {
        let repository = try makeRepository()
        let syncSpy = DailyBudgetWatchSnapshotSyncSpy()
        let state = AppState(
            repository: repository,
            dailyBudgetWatchSnapshotSyncer: syncSpy
        )

        await state.bootstrapIfNeeded()

        XCTAssertEqual(syncSpy.snapshots.count, 1)
        XCTAssertEqual(syncSpy.snapshots.last?.chips.count, 6)

        try state.refresh()

        XCTAssertEqual(syncSpy.snapshots.count, 2)
        XCTAssertEqual(syncSpy.snapshots.last?.chips.count, 6)
    }

    func testRefreshPublishesDailyBudgetWidgetSnapshot() async throws {
        let repository = try makeRepository()
        let syncSpy = DailyBudgetWidgetSnapshotSyncSpy()
        let state = AppState(
            repository: repository,
            dailyBudgetWidgetSnapshotSyncer: syncSpy
        )

        await state.bootstrapIfNeeded()

        XCTAssertEqual(syncSpy.snapshots.count, 1)
        XCTAssertEqual(syncSpy.snapshots.last?.chips.count, 2)

        try state.refresh()

        XCTAssertEqual(syncSpy.snapshots.count, 2)
        XCTAssertEqual(syncSpy.snapshots.last?.chips.count, 2)
    }

    func testDailyBalanceChartUsesFixedGregorianGMTCalendarForBucketing() async throws {
        let repository = try makeRepository()
        let now = Self.date(year: 2026, month: 4, day: 1)
        let state = AppState(repository: repository, nowProvider: { now })

        await state.bootstrapIfNeeded()
        state.usesSeparateAccountForDailyBudget = true
        state.dailyBudgetSeparateAccountBalance = 100
        state.dailyBudgetPaydayDay = 28

        let budget = try XCTUnwrap(try repository.activeBudget())
        let hiddenAccount = try XCTUnwrap(repository.hiddenDailyAccount(for: budget))
        try repository.createTransaction(
            Transaction(
                budgetID: budget.id,
                accountID: hiddenAccount.id,
                monthKey: YearMonth(year: 2026, month: 4),
                amount: -20,
                note: "Late-night coffee",
                sourcePostedAt: Self.date(year: 2026, month: 3, day: 31, hour: 23, minute: 30)
            )
        )

        try state.refresh()

        let londonCalendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "Europe/London") ?? .current
            return calendar
        }()

        XCTAssertEqual(state.dailyBalanceChartPoints.map { londonCalendar.component(.day, from: $0.date) }, [28, 29, 30, 31, 1])
        XCTAssertEqual(Self.utcCalendar.component(.hour, from: try XCTUnwrap(state.dailyBalanceChartPoints.last?.date)), 0)
        XCTAssertEqual(state.dailyBalanceChartPoints.map(\.balance), [120, 120, 120, 100, 100])
    }

    func testDailyBalanceChartUsesLinearInterpolation() {
        XCTAssertTrue(String(describing: DailyBalanceChartStyle.interpolationMethod).lowercased().contains("linear"))
    }

    func testDailyBalanceChartUsesBalanceTitle() {
        XCTAssertEqual(DailyBalanceChartStyle.title, "Balance")
    }

    func testDailyBalanceChartDomainSpansEntirePaydayCycle() {
        let cycleMetrics = DailyBudgetCycleMetrics(
            previousPayday: Self.date(year: 2026, month: 3, day: 28),
            nextPayday: Self.date(year: 2026, month: 4, day: 28),
            cycleDays: 31,
            elapsedDaysInCycle: 4,
            remainingDaysToPayday: 27,
            dailyBudget: 10,
            expectedBalanceToday: 270,
            aheadBehind: 0,
            currentDailyBudget: 10
        )

        let domain = DailyBalanceChartStyle.domain(for: cycleMetrics)

        XCTAssertEqual(domain.lowerBound, cycleMetrics.previousPayday)
        XCTAssertEqual(domain.upperBound, cycleMetrics.nextPayday)
    }

    func testDailyBalanceChartDayLabelUsesFixedGregorianGMTCalendar() {
        XCTAssertEqual(
            DailyBalanceChartStyle.dayLabel(for: Self.date(year: 2026, month: 3, day: 31, hour: 23, minute: 30)),
            "31"
        )
    }

    func testDailyBalanceChartWeekendGuideDatesMarkFridaysAcrossCycle() {
        let guideDates = DailyBalanceChartStyle.weekendGuideDates(
            from: Self.date(year: 2026, month: 3, day: 28),
            to: Self.date(year: 2026, month: 4, day: 28)
        )

        XCTAssertEqual(
            guideDates,
            [
                Self.date(year: 2026, month: 4, day: 3, hour: 0, minute: 0),
                Self.date(year: 2026, month: 4, day: 10, hour: 0, minute: 0),
                Self.date(year: 2026, month: 4, day: 17, hour: 0, minute: 0),
                Self.date(year: 2026, month: 4, day: 24, hour: 0, minute: 0)
            ]
        )
    }

    func testDailyBalanceChartPresentationKeepsAreaFillAndHidesPoints() {
        XCTAssertTrue(DailyBalanceChartStyle.showsAreaFill)
        XCTAssertFalse(DailyBalanceChartStyle.showsPointMarkers)
    }

    func testDailyBalanceChartYDomainUsesZeroAsLowerBound() {
        let domain = DailyBalanceChartStyle.yDomain(
            points: [
                DailyBalanceChartPoint(date: Self.date(year: 2026, month: 3, day: 28), balance: 120),
                DailyBalanceChartPoint(date: Self.date(year: 2026, month: 3, day: 29), balance: 180)
            ],
            fallbackBalance: 100
        )

        XCTAssertEqual(domain.lowerBound, 0)
        XCTAssertGreaterThan(domain.upperBound, 180)
    }

    func testEditableMoneyChipValueKeepsEmptyDraftWhileFocused() {
        XCTAssertEqual(
            EditableMoneyChipValue.displayText(
                isFocused: true,
                draft: "",
                committedText: "123.45",
                formattedValue: "GBP123.45"
            ),
            ""
        )
    }

    func testEditableMoneyChipValueShowsCommittedTextWhenFocusedWithoutDraft() {
        XCTAssertEqual(
            EditableMoneyChipValue.displayText(
                isFocused: true,
                draft: nil,
                committedText: "123.45",
                formattedValue: "GBP123.45"
            ),
            "123.45"
        )
    }

    func testDailyLayoutUsesReducedChipHeightAndTighterChartSpacing() {
        XCTAssertEqual(DailyLayoutMetrics.chipMinHeight, 82)
        XCTAssertEqual(DailyLayoutMetrics.contentSpacing, 8)
    }

    func testDailyNavigationUsesInlineTitleDisplay() {
        XCTAssertEqual(DailyNavigationStyle.title, "Daily")
        XCTAssertTrue(DailyNavigationStyle.usesInlineTitleDisplay)
    }

    func testImportFormatDetectsOfxAndQifExtensions() {
        XCTAssertEqual(ImportFormat.from(fileName: "statement.ofx"), .ofx)
        XCTAssertEqual(ImportFormat.from(fileName: "statement.QIF"), .qif)
        XCTAssertNil(ImportFormat.from(fileName: "statement.txt"))
    }

    func testSupportedImportTypesIncludeOnlyOfxAndQif() {
        let identifiers = Set<String>(SupportedImportTypes.all.map(\.identifier))
        XCTAssertEqual(identifiers, Set<String>([SupportedImportTypes.ofx.identifier, SupportedImportTypes.qif.identifier]))
    }

    func testDailyBalanceChartRespectsPaydayCycleBoundaries() {
        let calendar = Self.utcCalendar
        let accountID = UUID()
        let budgetID = UUID()
        let points = DailyBalanceChartCalculator.points(
            currentBalance: 100,
            today: Self.date(year: 2026, month: 3, day: 2),
            paydayDay: 28,
            transactions: [
                Transaction(
                    budgetID: budgetID,
                    accountID: accountID,
                    monthKey: YearMonth(year: 2026, month: 2),
                    amount: -50,
                    sourcePostedAt: Self.date(year: 2026, month: 2, day: 27)
                ),
                Transaction(
                    budgetID: budgetID,
                    accountID: accountID,
                    monthKey: YearMonth(year: 2026, month: 2),
                    amount: -10,
                    sourcePostedAt: Self.date(year: 2026, month: 2, day: 28)
                ),
                Transaction(
                    budgetID: budgetID,
                    accountID: accountID,
                    monthKey: YearMonth(year: 2026, month: 3),
                    amount: -5,
                    sourcePostedAt: Self.date(year: 2026, month: 3, day: 1)
                ),
                Transaction(
                    budgetID: budgetID,
                    accountID: accountID,
                    monthKey: YearMonth(year: 2026, month: 3),
                    amount: 20,
                    sourcePostedAt: Self.date(year: 2026, month: 3, day: 2)
                )
            ],
            calendar: calendar
        )

        XCTAssertEqual(points.map { calendar.component(.day, from: $0.date) }, [28, 1, 2])
        XCTAssertEqual(points.map { calendar.component(.month, from: $0.date) }, [2, 3, 3])
        XCTAssertEqual(points.map(\.balance), [85, 80, 100])
    }

    func testDailyBalanceChartPointsUseHiddenDailyAccountTransactions() async throws {
        let repository = try makeRepository()
        let fixedNow = Self.date(year: 2026, month: 3, day: 12)
        let state = AppState(repository: repository, nowProvider: { fixedNow })

        await state.bootstrapIfNeeded()
        state.usesSeparateAccountForDailyBudget = true
        state.dailyBudgetSeparateAccountBalance = 200
        state.dailyBudgetPaydayDay = 10

        let budget = try XCTUnwrap(try repository.activeBudget())
        let hiddenAccount = try XCTUnwrap(repository.hiddenDailyAccount(for: budget))
        try repository.createTransaction(
            Transaction(
                budgetID: budget.id,
                accountID: hiddenAccount.id,
                monthKey: YearMonth(year: 2026, month: 4),
                amount: -15,
                note: "Coffee",
                sourcePostedAt: Self.date(year: 2026, month: 3, day: 11)
            )
        )

        try state.refresh()

        XCTAssertEqual(state.dailyBalanceChartPoints.map(\.balance), [215, 200, 200])
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
            DailyPresentationContent.budgetTitle,
            "Starting budget"
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

    func testChipPaletteUsesBlackTextAndGreyPlainChipsInDarkMode() {
        let palette = ChipPalette.forColorScheme(.dark)

        XCTAssertEqual(palette.titleColor, Color.black.opacity(0.65))
        XCTAssertEqual(palette.valueColor, .black)
        XCTAssertEqual(palette.plainTop, Color(red: 0.86, green: 0.86, blue: 0.86))
        XCTAssertEqual(palette.plainBottom, Color(red: 0.80, green: 0.80, blue: 0.80))
        XCTAssertEqual(palette.negativeTop, Color(red: 0.98, green: 0.90, blue: 0.90))
        XCTAssertEqual(palette.negativeBottom, Color(red: 0.94, green: 0.78, blue: 0.78))
    }

    func testChipPaletteKeepsWhitePlainChipsInLightMode() {
        let palette = ChipPalette.forColorScheme(.light)

        XCTAssertEqual(palette.titleColor, .secondary)
        XCTAssertEqual(palette.valueColor, .primary)
        XCTAssertEqual(palette.plainTop, .white)
        XCTAssertEqual(palette.plainBottom, Color(red: 0.96, green: 0.96, blue: 0.96))
        XCTAssertEqual(palette.negativeTop, Color(red: 0.98, green: 0.86, blue: 0.86))
        XCTAssertEqual(palette.negativeBottom, Color(red: 0.93, green: 0.70, blue: 0.70))
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
            PlannedItem(accountID: accountID, monthKey: month, type: .fixedDebit, label: "Placeholder", amount: 0, isPaid: false),
            PlannedItem(accountID: accountID, monthKey: month, type: .credit, label: "Paid bonus", amount: 50, isPaid: true),
            PlannedItem(accountID: accountID, monthKey: month, type: .fixedDebit, label: "Paid bill", amount: 20, isPaid: true)
        ]

        XCTAssertEqual(
            MonthItemFilterRules.filteredItems(items, for: .pending).map(\.label).sorted(),
            ["Living", "Rent", "Salary"]
        )
    }

    func testPendingMonthFilterExcludesZeroValueItems() {
        let month = YearMonth(year: 2026, month: 3)
        let accountID = UUID()
        let items = [
            PlannedItem(accountID: accountID, monthKey: month, type: .fixedDebit, label: "Zero debit", amount: 0, isPaid: false),
            PlannedItem(accountID: accountID, monthKey: month, type: .credit, label: "Zero credit", amount: 0, isPaid: false),
            PlannedItem(accountID: accountID, monthKey: month, type: .transfer, label: "Living", amount: 200, isPaid: false)
        ]

        XCTAssertEqual(
            MonthItemFilterRules.filteredItems(items, for: .pending).map(\.label),
            ["Living"]
        )
    }

    func testMonthItemSortOrdersDueDaysFromPayday() {
        let month = YearMonth(year: 2026, month: 3)
        let accountID = UUID()
        let items = [
            PlannedItem(accountID: accountID, monthKey: month, type: .fixedDebit, label: "Before payday", amount: 10, dueDay: 24),
            PlannedItem(accountID: accountID, monthKey: month, type: .fixedDebit, label: "Payday", amount: 10, dueDay: 25),
            PlannedItem(accountID: accountID, monthKey: month, type: .fixedDebit, label: "Month end", amount: 10, dueDay: 31),
            PlannedItem(accountID: accountID, monthKey: month, type: .fixedDebit, label: "After wrap", amount: 10, dueDay: 1)
        ]

        XCTAssertEqual(
            MonthItemSortRules.sortedItems(items, paydayDay: 25, month: month).map(\.label),
            ["Payday", "Month end", "After wrap", "Before payday"]
        )
    }

    func testMonthItemSortClampsPaydayToMonthLength() {
        let month = YearMonth(year: 2026, month: 2)
        let accountID = UUID()
        let items = [
            PlannedItem(accountID: accountID, monthKey: month, type: .fixedDebit, label: "Before payday", amount: 10, dueDay: 27),
            PlannedItem(accountID: accountID, monthKey: month, type: .fixedDebit, label: "Payday", amount: 10, dueDay: 28),
            PlannedItem(accountID: accountID, monthKey: month, type: .fixedDebit, label: "After wrap", amount: 10, dueDay: 1)
        ]

        XCTAssertEqual(
            MonthItemSortRules.sortedItems(items, paydayDay: 31, month: month).map(\.label),
            ["Payday", "After wrap", "Before payday"]
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
        XCTAssertTrue(description.shouldMigrateStoreAutomatically)
        XCTAssertTrue(description.shouldInferMappingModelAutomatically)
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
        XCTAssertTrue(description.shouldMigrateStoreAutomatically)
        XCTAssertTrue(description.shouldInferMappingModelAutomatically)
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
            matchingString: "Council tax",
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
            note: "Rent payment",
            sourceKind: "nationwide_ofx",
            sourceExternalTransactionID: "FITID-TRANSACTION-1",
            sourcePostedAt: Date(timeIntervalSince1970: 1_234.5)
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
        XCTAssertEqual(plannedItems.first?.matchingString, "Council tax")
        let transactions = try store.fetchTransactions(accountIDs: [account.id])
        XCTAssertEqual(
            transactions.map(\.id),
            [transaction.id]
        )
        XCTAssertEqual(transactions.first?.sourceKind, "nationwide_ofx")
        XCTAssertEqual(transactions.first?.sourceExternalTransactionID, "FITID-TRANSACTION-1")
        XCTAssertEqual(transactions.first?.sourcePostedAt, Date(timeIntervalSince1970: 1_234.5))
        XCTAssertEqual(plannedItems.first?.source, .manual)

        let container = NSPersistentContainer(
            name: "MonthlyMoneyCoreData",
            managedObjectModel: CoreDataModelBuilder.sharedModel
        )
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        let context = container.viewContext
        let copiedItem = PlannedItem(
            id: UUID(),
            budgetID: budget.id,
            accountID: account.id,
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            source: .copiedFromPreviousMonth,
            label: "Utilities",
            amount: 75,
            dueDay: 2,
            isPaid: false,
            copiesToNextMonthAutomatically: true,
            notes: "Copied source check"
        )
        let copiedItemObject = NSEntityDescription.insertNewObject(
            forEntityName: CoreDataEntityName.plannedItem,
            into: context
        )
        CoreDataMapping.apply(copiedItem, to: copiedItemObject)
        try context.save()

        let roundTripStore = CoreDataAccountDataStore(persistentContainer: container)
        let copiedPlannedItems = try roundTripStore.fetchPlannedItems(
            accountIDs: [account.id],
            monthKey: YearMonth(year: 2026, month: 3)
        )
        let persistedCopiedItem = try XCTUnwrap(copiedPlannedItems.first { $0.id == copiedItem.id })
        XCTAssertEqual(persistedCopiedItem.source, .copiedFromPreviousMonth)
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

    func testCoreDataModelBuilderDefinesBudgetDependentRelationships() {
        let model = CoreDataModelBuilder.sharedModel
        let budgetEntity = try? XCTUnwrap(model.entitiesByName[CoreDataEntityName.budget])
        let accountEntity = try? XCTUnwrap(model.entitiesByName[CoreDataEntityName.account])
        let plannedItemEntity = try? XCTUnwrap(model.entitiesByName[CoreDataEntityName.plannedItem])
        let transactionEntity = try? XCTUnwrap(model.entitiesByName[CoreDataEntityName.transaction])
        let importedTransactionRecordEntity = try? XCTUnwrap(model.entitiesByName[CoreDataEntityName.importedTransactionRecord])
        let wheelOfMoneyItemEntity = try? XCTUnwrap(model.entitiesByName[CoreDataEntityName.wheelOfMoneyItem])

        let budgetRelationshipNames = Set(budgetEntity?.relationshipsByName.keys ?? Dictionary<String, NSRelationshipDescription>().keys)
        XCTAssertEqual(
            budgetRelationshipNames,
            ["accounts", "plannedItems", "transactions", "importedTransactionRecords", "wheelOfMoneyItems", "populatedMonths"]
        )

        XCTAssertEqual(accountEntity?.relationshipsByName["budget"]?.destinationEntity?.name, CoreDataEntityName.budget)
        XCTAssertEqual(plannedItemEntity?.relationshipsByName["budget"]?.destinationEntity?.name, CoreDataEntityName.budget)
        XCTAssertEqual(transactionEntity?.relationshipsByName["budget"]?.destinationEntity?.name, CoreDataEntityName.budget)
        XCTAssertEqual(importedTransactionRecordEntity?.relationshipsByName["budget"]?.destinationEntity?.name, CoreDataEntityName.budget)
        XCTAssertEqual(wheelOfMoneyItemEntity?.relationshipsByName["budget"]?.destinationEntity?.name, CoreDataEntityName.budget)
    }

    func testCoreDataAccountDataStoreAttachesDependentsToBudgetRelationships() throws {
        let store = try CoreDataAccountDataStore.makeInMemory()
        Self.retainHostedTestObject(store)

        let budget = Budget(
            id: UUID(),
            name: "Household",
            ownerParticipantID: "owner",
            sharingState: .local
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
            dueDay: 1
        )
        try store.upsertPlannedItems([item])

        let transaction = Transaction(
            id: UUID(),
            budgetID: budget.id,
            accountID: account.id,
            monthKey: YearMonth(year: 2026, month: 3),
            amount: 1200,
            note: "Rent"
        )
        try store.upsertTransactions([transaction])

        let importedRecord = ImportedTransactionRecord(
            id: UUID(),
            budgetID: budget.id,
            accountID: account.id,
            sourceKind: "nationwide_ofx",
            sourceAccountIdentifier: "****81197",
            externalTransactionID: "FITID-1",
            postedAt: Date(timeIntervalSince1970: 1_000),
            amount: -12.34,
            payee: "Test Payee",
            transactionType: "POS",
            rawSourcePayload: "{\"fitid\":\"FITID-1\"}",
            importedAt: Date(timeIntervalSince1970: 1_100),
            appliedPlannedItemID: UUID(),
            createdTransactionID: UUID()
        )
        try store.upsertImportedTransactionRecords([importedRecord])

        let counts = try store.budgetRelationshipCounts(for: budget.id)
        XCTAssertEqual(counts.accounts, 1)
        XCTAssertEqual(counts.plannedItems, 1)
        XCTAssertEqual(counts.transactions, 1)
        XCTAssertEqual(counts.importedTransactionRecords, 1)
    }

    func testCoreDataAccountDataStoreRoundTripsImportedTransactionRecords() throws {
        let store = try CoreDataAccountDataStore.makeInMemory()
        Self.retainHostedTestObject(store)

        let budget = Budget(
            id: UUID(),
            name: "Household",
            ownerParticipantID: "owner",
            sharingState: .local
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

        let record = ImportedTransactionRecord(
            id: UUID(),
            budgetID: budget.id,
            accountID: account.id,
            sourceKind: "nationwide_ofx",
            sourceAccountIdentifier: "****81197",
            externalTransactionID: "FITID-ROUNDTRIP",
            postedAt: Date(timeIntervalSince1970: 1_000),
            amount: -42.50,
            payee: "Roundtrip Payee",
            transactionType: "DIRECTDEBIT",
            rawSourcePayload: "{\"fitid\":\"FITID-ROUNDTRIP\"}",
            importedAt: Date(timeIntervalSince1970: 1_100),
            appliedPlannedItemID: UUID(),
            createdTransactionID: UUID()
        )

        try store.upsertImportedTransactionRecords([record])

        let fetched = try store.fetchImportedTransactionRecords(accountIDs: [account.id])
        XCTAssertEqual(fetched.map(\.externalTransactionID), ["FITID-ROUNDTRIP"])
        XCTAssertEqual(fetched.first?.rawSourcePayload, "{\"fitid\":\"FITID-ROUNDTRIP\"}")
        XCTAssertNotNil(fetched.first?.appliedPlannedItemID)
        XCTAssertNotNil(fetched.first?.createdTransactionID)
    }

    func testProductionRepositoryPersistsImportedTransactionLinkUpdates() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let repository = try MonthlyMoneyPersistenceFactory.makeRepository(
            plan: Self.localCoreDataPlan(baseDirectory: directory),
            schema: Self.makeSchema()
        )
        Self.retainHostedTestObject(repository)

        let account = try repository.createAccount(name: "Current", role: .regular, type: .current, ownerParticipantID: "owner")
        let targetItem = PlannedItem(
            accountID: account.id,
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Rent",
            amount: 1200,
            dueDay: 1,
            isPaid: false
        )
        try repository.createPlannedItem(targetItem)

        let record = ImportedTransactionRecord(
            accountID: account.id,
            sourceKind: ImportedTransactionService.nationwideOFXSourceKind,
            sourceAccountIdentifier: "****81197",
            externalTransactionID: "FITID-LINK",
            postedAt: Self.date(year: 2026, month: 3, day: 2),
            amount: -1200,
            payee: "Rent",
            transactionType: "DIRECTDEBIT",
            rawSourcePayload: "{}"
        )
        try repository.createImportedTransactionRecord(record)

        record.appliedPlannedItemID = targetItem.id
        try repository.saveImportedTransactionRecord(record)

        let savedRecord = try repository.importedTransactionRecords(accountIDs: [account.id]).first(where: { $0.id == record.id })
        XCTAssertEqual(savedRecord?.appliedPlannedItemID, targetItem.id)
    }

    func testImportedTransactionBudgetMonthMovesToNextMonthOnOrAfterPayday() {
        XCTAssertEqual(
            ImportedTransactionReconciliationService.budgetMonthKey(
                year: 2026,
                month: 1,
                day: 29,
                paydayDay: 28,
                calendar: Self.utcCalendar,
                referenceDate: Self.date(year: 2026, month: 1, day: 29)
            ),
            YearMonth(year: 2026, month: 2)
        )
    }

    func testImportedTransactionBudgetMonthMovesToNextMonthOnPayday() {
        XCTAssertEqual(
            ImportedTransactionReconciliationService.budgetMonthKey(
                year: 2026,
                month: 1,
                day: 28,
                paydayDay: 28,
                calendar: Self.utcCalendar,
                referenceDate: Self.date(year: 2026, month: 1, day: 28)
            ),
            YearMonth(year: 2026, month: 2)
        )
    }

    func testImportedTransactionBudgetMonthStaysInCurrentMonthBeforePayday() {
        XCTAssertEqual(
            ImportedTransactionReconciliationService.budgetMonthKey(
                year: 2026,
                month: 1,
                day: 27,
                paydayDay: 28,
                calendar: Self.utcCalendar,
                referenceDate: Self.date(year: 2026, month: 1, day: 27)
            ),
            YearMonth(year: 2026, month: 1)
        )
    }

    func testImportedTransactionBudgetMonthStaysInCalendarMonthWhenPaydayIsFirst() {
        XCTAssertEqual(
            ImportedTransactionReconciliationService.budgetMonthKey(
                year: 2026,
                month: 3,
                day: 21,
                paydayDay: 1,
                calendar: Self.utcCalendar,
                referenceDate: Self.date(year: 2026, month: 3, day: 21)
            ),
            YearMonth(year: 2026, month: 3)
        )
    }

    func testMonzoQIFImporterParsesTransactions() throws {
        let statement = try MonzoQIFImporter().parse(data: Self.makeQIFData())

        XCTAssertEqual(statement.accountIdentifier, "monzo_qif")
        XCTAssertEqual(statement.currencyCode, "GBP")
        XCTAssertNil(statement.ledgerBalance)
        XCTAssertEqual(statement.transactions.count, 2)
        XCTAssertEqual(statement.statementStartDate, Self.date(year: 2026, month: 3, day: 2))
        XCTAssertEqual(statement.statementEndDate, Self.date(year: 2026, month: 3, day: 29))
        XCTAssertEqual(statement.transactions[0].postedAt, Self.date(year: 2026, month: 3, day: 2))
        XCTAssertEqual(statement.transactions[0].amount, Decimal(string: "-12.34"))
        XCTAssertEqual(statement.transactions[0].payee, "Monzo Card")
        XCTAssertEqual(statement.transactions[0].transactionType, "DEBIT")
        XCTAssertEqual(statement.transactions[1].postedAt, Self.date(year: 2026, month: 3, day: 29))
        XCTAssertEqual(statement.transactions[1].amount, Decimal(string: "200.00"))
        XCTAssertEqual(statement.transactions[1].payee, "Roger Nolan")
        XCTAssertEqual(statement.transactions[1].transactionType, "CREDIT")
    }

    func testImportQIFDataIsIdempotentUsingDateAmountAndPayee() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            nowProvider: { Self.date(year: 2026, month: 3, day: 30) }
        )

        await state.bootstrapIfNeeded()
        let account = try XCTUnwrap(try repository.accounts().first)

        let firstResult = try state.importQIFData(
            Self.makeQIFData(),
            fileName: "monzo.qif",
            into: account.id
        )
        let secondResult = try state.importQIFData(
            Self.makeQIFData(),
            fileName: "monzo.qif",
            into: account.id
        )

        XCTAssertEqual(firstResult.importResult.insertedCount, 2)
        XCTAssertEqual(firstResult.importResult.skippedCount, 0)
        XCTAssertEqual(secondResult.importResult.insertedCount, 0)
        XCTAssertEqual(secondResult.importResult.skippedCount, 2)
        XCTAssertEqual(try repository.importedTransactionRecords(accountIDs: [account.id]).count, 2)
    }

    func testImportQIFDataUpdatesMonthlyAndDailyLastUpdatedWhenDailyUsesProjectedFunds() async throws {
        var repositoryNow = Self.date(year: 2026, month: 3, day: 12, hour: 8, minute: 0)
        let updatedAt = Self.date(year: 2026, month: 3, day: 12, hour: 14, minute: 20)
        let repository = try makeRepository(dateProvider: { repositoryNow })
        let state = AppState(
            repository: repository,
            nowProvider: { Self.date(year: 2026, month: 3, day: 12) }
        )

        await state.bootstrapIfNeeded()
        let account = try XCTUnwrap(try repository.accounts().first)
        repositoryNow = updatedAt

        _ = try state.importQIFData(
            Self.makeQIFData(),
            fileName: "monzo.qif",
            into: account.id
        )

        let budget = try XCTUnwrap(try repository.activeBudget())
        XCTAssertEqual(budget.monthlyBalanceLastUpdatedAt, updatedAt)
        XCTAssertEqual(budget.dailyBalanceLastUpdatedAt, updatedAt)
    }

    func testImportDailyQIFDataDerivesCurrentBalanceFromStartingBudgetAndTransactions() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            nowProvider: { Self.date(year: 2026, month: 3, day: 30) }
        )

        await state.bootstrapIfNeeded()
        state.usesSeparateAccountForDailyBudget = true
        state.dailyBudgetAmount = Decimal(string: "1000")!

        let result = try state.importDailyQIFData(
            Self.makeQIFData(),
            fileName: "monzo.qif"
        )

        let budget = try XCTUnwrap(try repository.activeBudget())
        let hiddenAccount = try XCTUnwrap(repository.hiddenDailyAccount(for: budget))
        let transactions = try repository.transactions(accountIDs: [hiddenAccount.id])

        XCTAssertEqual(result.importResult.insertedCount, 2)
        XCTAssertEqual(result.importResult.skippedCount, 0)
        XCTAssertEqual(result.ignoredOutsideCurrentCycleCount, 0)
        XCTAssertEqual(state.dailyBudgetSeparateAccountBalance, Decimal(string: "1187.66"))
        XCTAssertEqual(state.dailyBudgetCurrentBalance, Decimal(string: "1187.66"))
        XCTAssertEqual(transactions.count, 2)
        XCTAssertEqual(Set(transactions.map(\.monthKey)), [YearMonth(year: 2026, month: 3).rawValue])
        XCTAssertEqual(state.dailyBalanceChartPoints.last?.balance, Decimal(string: "1187.66"))
    }

    func testImportDailyQIFDataUpdatesOnlyDailyLastUpdated() async throws {
        var repositoryNow = Self.date(year: 2026, month: 3, day: 12, hour: 8, minute: 0)
        let updatedAt = Self.date(year: 2026, month: 3, day: 12, hour: 15, minute: 5)
        let repository = try makeRepository(dateProvider: { repositoryNow })
        let state = AppState(
            repository: repository,
            nowProvider: { Self.date(year: 2026, month: 3, day: 12) }
        )

        await state.bootstrapIfNeeded()
        let originalMonthlyUpdatedAt = try XCTUnwrap((try repository.activeBudget())?.monthlyBalanceLastUpdatedAt)
        repositoryNow = updatedAt
        state.usesSeparateAccountForDailyBudget = true

        _ = try state.importDailyQIFData(
            Self.makeQIFData(),
            fileName: "monzo.qif"
        )

        let budget = try XCTUnwrap(try repository.activeBudget())
        XCTAssertEqual(budget.monthlyBalanceLastUpdatedAt, originalMonthlyUpdatedAt)
        XCTAssertEqual(budget.dailyBalanceLastUpdatedAt, updatedAt)
    }

    func testImportDailyQIFDataReportsSkippedDuplicates() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            nowProvider: { Self.date(year: 2026, month: 3, day: 30) }
        )

        await state.bootstrapIfNeeded()
        state.usesSeparateAccountForDailyBudget = true

        let first = try state.importDailyQIFData(Self.makeQIFData(), fileName: "monzo.qif")
        let second = try state.importDailyQIFData(Self.makeQIFData(), fileName: "monzo.qif")

        XCTAssertEqual(first.importResult.insertedCount, 2)
        XCTAssertEqual(first.importResult.skippedCount, 0)
        XCTAssertEqual(second.importResult.insertedCount, 0)
        XCTAssertEqual(second.importResult.skippedCount, 2)
    }

    func testDerivedDailyBalanceRecalculatesWhenStartingBudgetChanges() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            nowProvider: { Self.date(year: 2026, month: 3, day: 30) }
        )

        await state.bootstrapIfNeeded()
        state.usesSeparateAccountForDailyBudget = true
        state.dailyBudgetAmount = Decimal(string: "1000")!

        _ = try state.importDailyQIFData(Self.makeQIFData(), fileName: "monzo.qif")
        XCTAssertEqual(state.dailyBudgetCurrentBalance, Decimal(string: "1187.66"))

        state.dailyBudgetAmount = Decimal(string: "900")!

        XCTAssertEqual(state.dailyBudgetCurrentBalance, Decimal(string: "1087.66"))
        XCTAssertEqual(state.dailyBalanceChartPoints.last?.balance, Decimal(string: "1087.66"))
    }

    func testImportDailyQIFDataPreservesExplicitBalanceOverride() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            nowProvider: { Self.date(year: 2026, month: 3, day: 12) }
        )

        await state.bootstrapIfNeeded()
        state.usesSeparateAccountForDailyBudget = true
        state.dailyBudgetSeparateAccountBalance = Decimal(string: "4321.09")!

        _ = try state.importDailyQIFData(Self.makeQIFData(), fileName: "monzo.qif")

        XCTAssertEqual(state.dailyBudgetCurrentBalance, Decimal(string: "4321.09"))
    }

    func testImportDailyQIFDataIgnoresTransactionsOutsideCurrentCycle() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            nowProvider: { Self.date(year: 2026, month: 3, day: 24) }
        )

        await state.bootstrapIfNeeded()
        state.usesSeparateAccountForDailyBudget = true
        state.dailyBudgetPaydayDay = 28
        state.dailyBudgetAmount = 1000

        let result = try state.importDailyQIFData(Self.makeOutOfCycleQIFData(), fileName: "monzo.qif")

        let budget = try XCTUnwrap(try repository.activeBudget())
        let hiddenAccount = try XCTUnwrap(repository.hiddenDailyAccount(for: budget))
        let transactions = try repository.transactions(accountIDs: [hiddenAccount.id])
        let importedRecords = try repository.importedTransactionRecords(accountIDs: [hiddenAccount.id])

        XCTAssertEqual(result.importResult.insertedCount, 0)
        XCTAssertEqual(result.importResult.skippedCount, 0)
        XCTAssertEqual(result.ignoredOutsideCurrentCycleCount, 2)
        XCTAssertTrue(transactions.isEmpty)
        XCTAssertTrue(importedRecords.isEmpty)
        XCTAssertEqual(state.dailyBudgetCurrentBalance, 1000)
    }

    func testImportOFXDataUpdatesPrimaryBankBalanceFromStatementLedgerBalance() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)
        let balanceMonth = YearMonth(year: 2026, month: 4)

        await state.bootstrapIfNeeded()
        state.selectedMonth = balanceMonth
        let account = try XCTUnwrap(try repository.accounts().first)

        _ = try state.importOFXData(
            Self.makeOFXData(
                postedDate: "20260302000000",
                transactionAmount: "-12.34",
                ledgerBalance: "1234.56"
            ),
            fileName: "statement.ofx",
            into: account.id
        )

        XCTAssertEqual(state.primaryBankBalances[balanceMonth.rawValue], Decimal(string: "1234.56"))
        XCTAssertEqual(state.primaryBankBalance, Decimal(string: "1234.56"))
    }

    func testImportOFXDataOnPaydayCreatesMonthItemInNextBudgetMonth() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        state.dailyBudgetPaydayDay = 28

        let account = try XCTUnwrap(try repository.accounts().first)

        _ = try state.importOFXData(
            Self.makeOFXData(
                postedDate: "20260328000000",
                transactionAmount: "-12.34"
            ),
            fileName: "statement.ofx",
            into: account.id
        )

        let marchItems = try repository.plannedItems(for: YearMonth(year: 2026, month: 3))
        let aprilItems = try repository.plannedItems(for: YearMonth(year: 2026, month: 4))

        XCTAssertEqual(marchItems.filter { $0.label == "Card Payment" }.count, 0)
        XCTAssertEqual(aprilItems.filter { $0.label == "Card Payment" }.count, 1)
    }

    func testImportDailyOFXDataUpdatesDailySeparateAccountBalanceFromStatementLedgerBalance() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            nowProvider: { Self.date(year: 2026, month: 3, day: 12) }
        )

        await state.bootstrapIfNeeded()
        state.usesSeparateAccountForDailyBudget = true

        XCTAssertEqual(state.dailyBudgetSeparateAccountBalance, 0)

        _ = try state.importDailyOFXData(
            Self.makeOFXData(
                postedDate: "20260302000000",
                transactionAmount: "-12.34",
                ledgerBalance: "4321.09"
            ),
            fileName: "daily-statement.ofx"
        )

        XCTAssertEqual(state.dailyBudgetSeparateAccountBalance, Decimal(string: "4321.09"))
        XCTAssertEqual(try repository.activeBudget()?.dailyBudgetSeparateAccountBalance, Decimal(string: "4321.09"))
    }

    func testImportDailyOFXDataStoresCurrentCycleTransactionsAndImportedRecords() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            nowProvider: { Self.date(year: 2026, month: 3, day: 12) }
        )

        await state.bootstrapIfNeeded()
        state.usesSeparateAccountForDailyBudget = true

        let budget = try XCTUnwrap(try repository.activeBudget())
        let hiddenAccount = try XCTUnwrap(repository.hiddenDailyAccount(for: budget))

        _ = try state.importDailyOFXData(
            Self.makeOFXData(
                postedDate: "20260302000000",
                transactionAmount: "-12.34",
                ledgerBalance: "4321.09"
            ),
            fileName: "daily-statement.ofx"
        )

        XCTAssertEqual(try repository.transactions(accountIDs: [hiddenAccount.id]).count, 1)
        XCTAssertEqual(try repository.importedTransactionRecords(accountIDs: [hiddenAccount.id]).count, 1)
    }

    func testImportDailyOFXDataIsIdempotentForHiddenDailyAccount() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            nowProvider: { Self.date(year: 2026, month: 3, day: 12) }
        )

        await state.bootstrapIfNeeded()
        state.usesSeparateAccountForDailyBudget = true

        let budget = try XCTUnwrap(try repository.activeBudget())
        let hiddenAccount = try XCTUnwrap(repository.hiddenDailyAccount(for: budget))
        let data = Self.makeOFXData(
            postedDate: "20260302000000",
            transactionAmount: "-12.34",
            ledgerBalance: "4321.09"
        )

        _ = try state.importDailyOFXData(data, fileName: "daily-statement.ofx")
        _ = try state.importDailyOFXData(data, fileName: "daily-statement.ofx")

        XCTAssertEqual(try repository.transactions(accountIDs: [hiddenAccount.id]).count, 1)
        XCTAssertEqual(try repository.importedTransactionRecords(accountIDs: [hiddenAccount.id]).count, 1)
    }

    func testRefreshClearsStaleHiddenDailyImportedDataWhenCycleMovesForward() async throws {
        var now = Self.date(year: 2026, month: 1, day: 20)
        let repository = try makeRepository()
        let state = AppState(repository: repository, nowProvider: { now })

        await state.bootstrapIfNeeded()
        state.usesSeparateAccountForDailyBudget = true
        state.dailyBudgetPaydayDay = 28

        let budget = try XCTUnwrap(try repository.activeBudget())
        let hiddenAccount = try XCTUnwrap(repository.hiddenDailyAccount(for: budget))
        let data = Self.makeOFXData(
            postedDate: "20260121000000",
            transactionAmount: "-12.34",
            ledgerBalance: "4321.09"
        )

        _ = try state.importDailyOFXData(data, fileName: "daily-statement.ofx")
        XCTAssertEqual(try repository.transactions(accountIDs: [hiddenAccount.id]).count, 1)
        XCTAssertEqual(try repository.importedTransactionRecords(accountIDs: [hiddenAccount.id]).count, 1)

        now = Self.date(year: 2026, month: 2, day: 1)
        try state.refresh()

        XCTAssertTrue(try repository.transactions(accountIDs: [hiddenAccount.id]).isEmpty)
        XCTAssertTrue(try repository.importedTransactionRecords(accountIDs: [hiddenAccount.id]).isEmpty)
    }

    func testImportDailyOFXDataDoesNotCreatePlannedItems() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            nowProvider: { Self.date(year: 2026, month: 3, day: 12) }
        )

        await state.bootstrapIfNeeded()
        state.usesSeparateAccountForDailyBudget = true

        let budget = try XCTUnwrap(try repository.activeBudget())
        let hiddenAccount = try XCTUnwrap(repository.hiddenDailyAccount(for: budget))
        let plannedItemsBefore = try repository.plannedItems(for: state.selectedMonth)

        _ = try state.importDailyOFXData(
            Self.makeOFXData(
                postedDate: "20260302000000",
                transactionAmount: "-12.34",
                ledgerBalance: "4321.09"
            ),
            fileName: "daily-statement.ofx"
        )

        XCTAssertEqual(try repository.transactions(accountIDs: [hiddenAccount.id]).count, 1)
        XCTAssertEqual(try repository.importedTransactionRecords(accountIDs: [hiddenAccount.id]).count, 1)
        XCTAssertEqual(try repository.plannedItems(for: state.selectedMonth), plannedItemsBefore)
    }

    func testImportDailyOFXDataWithoutLedgerBalanceThrowsReadableError() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        state.usesSeparateAccountForDailyBudget = true

        do {
            _ = try state.importDailyOFXData(
                Self.makeOFXData(
                    postedDate: "20260302000000",
                    transactionAmount: "-12.34"
                ),
                fileName: "daily-statement.ofx"
            )
            XCTFail("Expected daily OFX import to throw when ledger balance is missing")
        } catch let error as DailyOFXImportError {
            XCTAssertEqual(error, .missingLedgerBalance)
            XCTAssertEqual(
                error.localizedDescription,
                "The OFX file does not include a ledger balance, so the daily balance could not be updated."
            )
        }
    }

    func testCoreDataAccountDataStoreBackfillsBudgetRelationshipsForExistingDependents() throws {
        let container = NSPersistentContainer(
            name: "MonthlyMoneyCoreData",
            managedObjectModel: CoreDataModelBuilder.sharedModel
        )
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError {
            throw loadError
        }

        let context = container.viewContext
        let budget = Budget(
            id: UUID(),
            name: "Household",
            ownerParticipantID: "owner",
            sharingState: .local
        )

        let budgetObject = NSEntityDescription.insertNewObject(
            forEntityName: CoreDataEntityName.budget,
            into: context
        )
        CoreDataMapping.apply(budget, to: budgetObject)

        let account = Account(
            id: UUID(),
            budgetID: budget.id,
            name: "Joint",
            role: .regular,
            type: .current,
            ownerParticipantID: "owner"
        )
        let accountObject = NSEntityDescription.insertNewObject(
            forEntityName: CoreDataEntityName.account,
            into: context
        )
        CoreDataMapping.apply(account, to: accountObject)

        let item = PlannedItem(
            id: UUID(),
            budgetID: budget.id,
            accountID: account.id,
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Rent",
            amount: 1200,
            dueDay: 1
        )
        item.source = .copiedFromPreviousMonth
        let itemObject = NSEntityDescription.insertNewObject(
            forEntityName: CoreDataEntityName.plannedItem,
            into: context
        )
        CoreDataMapping.apply(item, to: itemObject)

        let transaction = Transaction(
            id: UUID(),
            budgetID: budget.id,
            accountID: account.id,
            monthKey: YearMonth(year: 2026, month: 3),
            amount: 1200,
            note: "Rent"
        )
        let transactionObject = NSEntityDescription.insertNewObject(
            forEntityName: CoreDataEntityName.transaction,
            into: context
        )
        CoreDataMapping.apply(transaction, to: transactionObject)

        try context.save()

        let store = CoreDataAccountDataStore(persistentContainer: container)
        Self.retainHostedTestObject(store)
        let beforeCounts = try store.budgetRelationshipCounts(for: budget.id)
        XCTAssertEqual(beforeCounts.accounts, 0)
        XCTAssertEqual(beforeCounts.plannedItems, 0)
        XCTAssertEqual(beforeCounts.transactions, 0)
        XCTAssertEqual(beforeCounts.importedTransactionRecords, 0)

        try store.repairBudgetRelationships(for: budget.id)

        let afterCounts = try store.budgetRelationshipCounts(for: budget.id)
        XCTAssertEqual(afterCounts.accounts, 1)
        XCTAssertEqual(afterCounts.plannedItems, 1)
        XCTAssertEqual(afterCounts.transactions, 1)
        XCTAssertEqual(afterCounts.importedTransactionRecords, 0)
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

    func testPersistenceFactoryBuildsLocalCoreDataPrivateAndSharedStores() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let repository = try MonthlyMoneyPersistenceFactory.makeRepository(
            plan: Self.localCoreDataPlan(baseDirectory: directory),
            schema: Self.makeSchema()
        )
        Self.retainHostedTestObject(repository)

        XCTAssertEqual(repository.privateStoreImplementationKind, .coreData)
        XCTAssertEqual(repository.sharedStoreImplementationKind, .coreData)
        XCTAssertEqual(repository.sharedStoreSyncMode, .localOnly)
    }

    func testCloudKitShareSceneConfigurationUsesShareSceneDelegate() {
        let configuration = CloudKitShareSceneConfiguration.make(for: .windowApplication)

        XCTAssertTrue(configuration.delegateClass == MonthlyMoneyCloudKitShareSceneDelegate.self)
    }

    func testWheelOfMoneySavingsSettingPersistsInProductionRepository() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let repository = try MonthlyMoneyPersistenceFactory.makeRepository(
            plan: Self.localCoreDataPlan(baseDirectory: directory),
            schema: Self.makeSchema()
        )
        Self.retainHostedTestObject(repository)

        let state = AppState(repository: repository)
        await state.bootstrapIfNeeded()
        XCTAssertFalse(state.autoGenerateWoMSavingsEveryMonth)

        state.autoGenerateWoMSavingsEveryMonth = true

        let reloaded = AppState(repository: repository)
        try reloaded.refresh()

        XCTAssertTrue(reloaded.autoGenerateWoMSavingsEveryMonth)
        XCTAssertEqual(try repository.activeBudget()?.autoGenerateWoMSavingsEveryMonth, true)
    }

    func testCloudKitShareAcceptancePolicyOnlyProcessesWhenMetadataExists() {
        XCTAssertFalse(CloudKitShareAcceptancePolicy.shouldProcess(pendingMetadataCount: 0))
        XCTAssertTrue(CloudKitShareAcceptancePolicy.shouldProcess(pendingMetadataCount: 1))
    }

    func testCloudKitShareAcceptanceDispatcherStartsAcceptanceForPendingMetadata() {
        var drained = false
        var accepted: [Int] = []

        CloudKitShareAcceptanceDispatcher.dispatchIfNeeded(
            pendingMetadataCount: 1,
            drain: {
                drained = true
                return [1, 2]
            },
            start: { accepted = $0 }
        )

        XCTAssertTrue(drained)
        XCTAssertEqual(accepted, [1, 2])
    }

    func testCloudKitShareAcceptanceDispatcherDoesNothingWhenNoMetadataIsPending() {
        var drained = false
        var didStart = false

        CloudKitShareAcceptanceDispatcher.dispatchIfNeeded(
            pendingMetadataCount: 0,
            drain: {
                drained = true
                return [1]
            },
            start: { _ in didStart = true }
        )

        XCTAssertFalse(drained)
        XCTAssertFalse(didStart)
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
        XCTAssertTrue(presentation.isShareButtonEnabled)
        XCTAssertTrue(presentation.showsUnshareButton)
        XCTAssertNil(presentation.note)
    }

    func testSettingsSharingPresentationForRecipientSharedBudget() {
        let presentation = SettingsSharingPresentation(status: .sharedWithYou)

        XCTAssertEqual(presentation.statusText, "Shared with you")
        XCTAssertFalse(presentation.isShareButtonEnabled)
        XCTAssertFalse(presentation.showsUnshareButton)
        XCTAssertNil(presentation.note)
    }

    func testSettingsSharingPresentationForSharedBudgetAvailable() {
        let presentation = SettingsSharingPresentation(status: .sharedAvailable)

        XCTAssertEqual(presentation.statusText, "Shared budget available")
        XCTAssertFalse(presentation.isShareButtonEnabled)
        XCTAssertFalse(presentation.showsUnshareButton)
        XCTAssertEqual(presentation.note, "Open the shared budget from the overwrite prompt when you're ready.")
    }

    func testShareMetadataConfiguratorSetsTitleAndType() {
        let rootRecord = CKRecord(recordType: "Budget")
        let share = CKShare(rootRecord: rootRecord)

        ShareMetadataConfigurator.apply(to: share, budgetName: "Joint Budget")

        XCTAssertEqual(share[CKShare.SystemFieldKey.title] as? String, ShareMetadataConfigurator.appDisplayName)
        XCTAssertEqual(share[CKShare.SystemFieldKey.shareType] as? String, ShareMetadataConfigurator.itemType)
    }

    func testSettingsSharingPresentationForLocalBudgetDoesNotShowUnshare() {
        let presentation = SettingsSharingPresentation(status: .localOnly)

        XCTAssertFalse(presentation.showsUnshareButton)
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

    func testAppStateSharingStatusReflectsSharedBudgetAvailableBeforeAdoption() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            currentParticipantIDProvider: { "rog" }
        )

        await state.bootstrapIfNeeded()
        try insertIncomingSharedBudget(into: repository, month: state.selectedMonth)

        try state.refresh()

        XCTAssertEqual(state.sharingStatus, .sharedAvailable)
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
        budget.ownerParticipantID = "owner"
        try repository.saveBudget(budget)

        XCTAssertTrue(state.canEditBudgetSettings)

        state.usesSeparateAccountForDailyBudget = false
        XCTAssertFalse(state.usesSeparateAccountForDailyBudget)
    }

    func testWheelOfMoneySavingsSettingPersistsOnActiveBudget() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        XCTAssertFalse(state.autoGenerateWoMSavingsEveryMonth)

        state.autoGenerateWoMSavingsEveryMonth = true

        XCTAssertTrue(state.autoGenerateWoMSavingsEveryMonth)
        XCTAssertEqual(try repository.activeBudget()?.autoGenerateWoMSavingsEveryMonth, true)

        state.autoGenerateWoMSavingsEveryMonth = false

        XCTAssertFalse(state.autoGenerateWoMSavingsEveryMonth)
        XCTAssertEqual(try repository.activeBudget()?.autoGenerateWoMSavingsEveryMonth, false)
    }

    func testWheelOfMoneySavingsSettingPersistsAcrossAppStateRecreation() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        state.autoGenerateWoMSavingsEveryMonth = true

        let reloaded = AppState(repository: repository)
        try reloaded.refresh()

        XCTAssertTrue(reloaded.autoGenerateWoMSavingsEveryMonth)
        XCTAssertEqual(try repository.activeBudget()?.autoGenerateWoMSavingsEveryMonth, true)
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

    func testBudgetSettingsRemainEditableWhileSharedBudgetIsOnlyAvailable() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            currentParticipantIDProvider: { "rog" }
        )

        await state.bootstrapIfNeeded()
        try insertIncomingSharedBudget(into: repository, month: state.selectedMonth)
        try state.refresh()

        XCTAssertEqual(state.sharingStatus, .sharedAvailable)
        XCTAssertTrue(state.canEditBudgetSettings)
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
                let sharedBudget = try service.shareBudget(participantsSelection: [])
                return BudgetShareResult(
                    sharedBudget: sharedBudget,
                    shareSession: self.makeTestBudgetShareSession(budgetID: sharedBudget.id)
                )
            }
        )
        observedState = state

        await state.bootstrapIfNeeded()
        XCTAssertFalse(state.isSharingBudget)

        await state.shareBudget()

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertFalse(state.isSharingBudget)
        XCTAssertEqual(state.sharingStatus, .sharedByYou)
        XCTAssertNotNil(try repository.localBudget())
        XCTAssertNil(try repository.sharedBudget())
        XCTAssertEqual(try repository.localBudget()?.sharingState, .shared)
        XCTAssertEqual(state.pendingBudgetShareResult?.sharedBudget.id, try repository.activeBudget()?.id)
        XCTAssertEqual(state.pendingBudgetShareResult?.shareSession.budgetID, try repository.activeBudget()?.id)
    }

    func testShareBudgetReopensForOwnerSharedBudget() async throws {
        let repository = try makeRepository()
        let expectation = expectation(description: "share handler called for already shared owner budget")
        let state = AppState(
            repository: repository,
            shareBudgetAction: { repository in
                let sharedBudget = try BudgetSharingService(repository: repository) { _ in
                    expectation.fulfill()
                }.shareBudget(participantsSelection: [])
                return BudgetShareResult(
                    sharedBudget: sharedBudget,
                    shareSession: self.makeTestBudgetShareSession(budgetID: sharedBudget.id)
                )
            }
        )

        await state.bootstrapIfNeeded()
        let budget = try XCTUnwrap(try repository.activeBudget())
        budget.sharingState = .shared
        try repository.saveBudget(budget)

        await state.shareBudget()

        await fulfillment(of: [expectation], timeout: 1)
        XCTAssertFalse(state.isSharingBudget)
        XCTAssertNil(state.sharingErrorMessage)
        XCTAssertNotNil(state.pendingBudgetShareResult)
    }

    func testHandleStopSharingReturnsOwnerBudgetToLocalState() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let budget = try XCTUnwrap(try repository.activeBudget())
        budget.sharingState = .shared
        budget.ownerParticipantID = "owner"
        try repository.saveBudget(budget)
        try state.refresh()

        XCTAssertEqual(state.sharingStatus, .sharedByYou)

        try await state.handleBudgetShareStopped()

        XCTAssertEqual(try repository.activeBudget()?.sharingState, .local)
        XCTAssertEqual(state.sharingStatus, .localOnly)
    }

    func testHandleStopSharingKeepsBudgetSharedWhenVerificationFails() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            verifyBudgetUnsharedAction: { _, _ in false }
        )

        await state.bootstrapIfNeeded()
        let budget = try XCTUnwrap(try repository.activeBudget())
        budget.sharingState = .shared
        budget.ownerParticipantID = "owner"
        try repository.saveBudget(budget)
        try state.refresh()

        await state.handleBudgetShareStoppedFromUI()

        XCTAssertEqual(try repository.activeBudget()?.sharingState, .shared)
        XCTAssertEqual(state.sharingStatus, .sharedByYou)
        XCTAssertEqual(state.sharingErrorMessage, "Could not confirm that sharing was removed.")
    }

    func testClearingBudgetSharePresentationRemovesPendingShareResult() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            shareBudgetAction: { repository in
                let sharedBudget = try BudgetSharingService(repository: repository).shareBudget(participantsSelection: [])
                return BudgetShareResult(
                    sharedBudget: sharedBudget,
                    shareSession: self.makeTestBudgetShareSession(budgetID: sharedBudget.id)
                )
            }
        )

        await state.bootstrapIfNeeded()
        await state.shareBudget()
        XCTAssertNotNil(state.pendingBudgetShareResult)

        state.clearPendingBudgetSharePresentation()

        XCTAssertNil(state.pendingBudgetShareResult)
    }

    func testRefreshShowsPendingSharedBudgetOverwriteForRecipient() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            currentParticipantIDProvider: { "rog" }
        )

        await state.bootstrapIfNeeded()
        try insertIncomingSharedBudget(into: repository, month: state.selectedMonth)

        try state.refresh()

        XCTAssertTrue(state.shouldShowSharedBudgetOverwriteAlert)
        XCTAssertEqual(state.pendingSharedBudgetAdoption?.budgetName, "Shared Household")
    }

    func testConfirmSharedBudgetOverwriteDeletesLocalBudgetAndAdoptsSharedBudget() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            currentParticipantIDProvider: { "rog" }
        )

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
        XCTAssertEqual(state.wheelOfMoneyItems.map(\.title), ["Shared Christmas"])
    }

    func testCancelSharedBudgetOverwriteKeepsLocalBudgetActive() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            currentParticipantIDProvider: { "rog" }
        )

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

    func testRefreshRecreatesLocalBudgetWhenSharedBudgetDisappearsAfterAdoption() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            currentParticipantIDProvider: { "rog" }
        )

        await state.bootstrapIfNeeded()
        try insertIncomingSharedBudget(into: repository, month: state.selectedMonth)
        try state.refresh()
        try state.confirmSharedBudgetOverwrite()

        let sharedBudgetID = try XCTUnwrap(try repository.sharedBudget()?.id)
        try repository.deleteBudget(id: sharedBudgetID)

        try state.refresh()

        XCTAssertEqual(try repository.activeBudget()?.sharingState, .local)
        XCTAssertNotNil(try repository.localBudget())
        XCTAssertTrue(state.monthItems.isEmpty)
        XCTAssertEqual(state.primaryBankBalance, 0)
        XCTAssertEqual(state.primaryBankName, "Nationwide")
    }

    func testSharedBudgetOwnedByResolvedParticipantIsSharedByYou() async throws {
        let repository = try makeRepository()
        let state = AppState(
            repository: repository,
            currentParticipantIDProvider: { "rog" }
        )

        await state.bootstrapIfNeeded()

        let budget = try XCTUnwrap(try repository.activeBudget())
        budget.sharingState = .shared
        budget.ownerParticipantID = "rog"
        try repository.saveBudget(budget)

        try state.refresh()

        XCTAssertEqual(state.sharingStatus, .sharedByYou)
        XCTAssertFalse(state.shouldShowSharedBudgetOverwriteAlert)
    }

    func testBootstrapMigratesLegacyLocalOwnerIdentifier() async throws {
        let repository = try makeRepository()
        let legacyBudget = Budget(
            id: UUID(),
            name: "Budget",
            ownerParticipantID: "owner",
            sharingState: .local
        )
        try repository.saveBudget(legacyBudget)

        let state = AppState(
            repository: repository,
            currentParticipantIDProvider: { "rog" }
        )

        await state.bootstrapIfNeeded()

        XCTAssertEqual(try repository.localBudget()?.ownerParticipantID, "rog")
        XCTAssertEqual(state.sharingStatus, .localOnly)
    }

    func testCloudRefreshPolicyOnlyPollsForActiveCloudBackedAppSessions() {
        XCTAssertTrue(
            CloudRefreshPolicy.shouldPoll(
                privateStoreSyncMode: .cloudPrivate,
                sharedStoreSyncMode: .localOnly,
                scenePhase: .active,
                isRunningTests: false
            )
        )
        XCTAssertTrue(
            CloudRefreshPolicy.shouldPoll(
                privateStoreSyncMode: .localOnly,
                sharedStoreSyncMode: .cloudShared,
                scenePhase: .active,
                isRunningTests: false
            )
        )
        XCTAssertFalse(
            CloudRefreshPolicy.shouldPoll(
                privateStoreSyncMode: .localOnly,
                sharedStoreSyncMode: .localOnly,
                scenePhase: .active,
                isRunningTests: false
            )
        )
        XCTAssertFalse(
            CloudRefreshPolicy.shouldPoll(
                privateStoreSyncMode: .cloudPrivate,
                sharedStoreSyncMode: .cloudShared,
                scenePhase: .background,
                isRunningTests: false
            )
        )
        XCTAssertFalse(
            CloudRefreshPolicy.shouldPoll(
                privateStoreSyncMode: .cloudPrivate,
                sharedStoreSyncMode: .cloudShared,
                scenePhase: .active,
                isRunningTests: true
            )
        )
    }

    func testAcceptSharedBudgetErrorMessageIncludesUnderlyingErrorContext() throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)
        let underlying = NSError(
            domain: "CKErrorDomain",
            code: 42,
            userInfo: [NSLocalizedDescriptionKey: "Invitation is not valid."]
        )

        XCTAssertEqual(
            state.debugAcceptSharedBudgetErrorMessage(for: underlying),
            "Failed to accept shared budget: Invitation is not valid. (CKErrorDomain 42)"
        )
    }

    func testAcceptSharedBudgetErrorMessageIncludesPartialFailureDetails() throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)
        let itemError = NSError(
            domain: CKError.errorDomain,
            code: CKError.zoneNotFound.rawValue,
            userInfo: [NSLocalizedDescriptionKey: "Zone not found."]
        )
        let partialFailure = NSError(
            domain: CKError.errorDomain,
            code: CKError.partialFailure.rawValue,
            userInfo: [CKPartialErrorsByItemIDKey: ["share-1": itemError]]
        )

        XCTAssertEqual(
            state.debugAcceptSharedBudgetErrorMessage(for: partialFailure),
            "Failed to accept shared budget: Zone not found. (CKErrorDomain 26)"
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
        state.openingBalance = 777
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

    func testPastMonthMutationsAreEnabledWhenSettingIsOn() async throws {
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
            label: "Historical bill",
            amount: 42,
            dueDay: 4,
            isPaid: false
        )
        try repository.createPlannedItem(item)

        state.allowsPreviousMonthEditing = true
        state.selectedMonth = pastMonth
        try state.refresh()
        state.primaryBankBalance = 999
        state.setPaid(item: item, paid: true)
        state.update(
            item: item,
            label: "Updated historical bill",
            amount: 88,
            dueDay: 5,
            dueText: nil,
            type: .credit,
            copiesToNextMonthAutomatically: false,
            notes: "Updated note"
        )
        let created = state.createEntry(type: .fixedDebit, label: "Past add", amount: 11, dueDay: 7)

        XCTAssertEqual(state.primaryBankBalance, 0)
        XCTAssertEqual(state.openingBalance, 0)
        let reloaded = try XCTUnwrap(try repository.plannedItems(for: pastMonth).first(where: { $0.id == item.id }))
        XCTAssertTrue(reloaded.isPaid)
        XCTAssertEqual(reloaded.label, "Updated historical bill")
        XCTAssertEqual(reloaded.amount, 88)
        XCTAssertEqual(reloaded.type, .credit)
        XCTAssertEqual(reloaded.notes, "Updated note")
        XCTAssertNotNil(created)

        state.delete(item: reloaded)
        XCTAssertNil(try repository.plannedItems(for: pastMonth).first(where: { $0.id == item.id }))
    }

    func testPreviousMonthEditingDoesNotEnableBulkPopulation() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        let currentMonth = state.selectedMonth
        let pastMonth = YearMonth(
            year: currentMonth.month == 1 ? currentMonth.year - 1 : currentMonth.year,
            month: currentMonth.month == 1 ? 12 : currentMonth.month - 1
        )
        state.allowsPreviousMonthEditing = true
        state.selectedMonth = pastMonth
        try state.refresh()

        XCTAssertTrue(state.canEditSelectedMonth)
        XCTAssertFalse(state.canPopulateSelectedMonthFromPrevious)
    }

    func testPopulationActionsStayScopedToCurrentMonthAndMoveToPreviousAfterUse() async throws {
        let repository = try makeRepository()
        let now = Self.date(year: 2026, month: 6, day: 27)
        let state = AppState(repository: repository, nowProvider: { now })

        await state.bootstrapIfNeeded()

        let currentMonth = state.selectedMonth
        let previousMonth = YearMonth(
            year: currentMonth.month == 1 ? currentMonth.year - 1 : currentMonth.year,
            month: currentMonth.month == 1 ? 12 : currentMonth.month - 1
        )
        let nextMonth = nextMonth(after: currentMonth)
        let account = try XCTUnwrap(try repository.accounts().first)

        XCTAssertTrue(state.canPopulateSelectedMonthFromPrevious)
        XCTAssertFalse(state.canCopyRepeatingEntriesToNextMonth)
        XCTAssertFalse(state.currentMonthHasEntries)

        state.selectedMonth = nextMonth
        try state.refresh()
        XCTAssertFalse(state.canPopulateSelectedMonthFromPrevious)

        state.selectedMonth = previousMonth
        try state.refresh()
        XCTAssertFalse(state.canCopyRepeatingEntriesToNextMonth)

        try repository.createPlannedItem(
            PlannedItem(
                accountID: account.id,
                monthKey: currentMonth,
                type: .fixedDebit,
                label: "Rent",
                amount: 1200,
                dueDay: 1,
                repeatMode: .calendar
            )
        )
        state.selectedMonth = currentMonth
        try state.refresh()
        XCTAssertFalse(state.canPopulateSelectedMonthFromPrevious)
        XCTAssertTrue(state.currentMonthHasEntries)

        state.selectedMonth = previousMonth
        try state.refresh()
        XCTAssertTrue(state.canCopyRepeatingEntriesToNextMonth)
    }

    func testPreviousMonthCopyActionAppearsWhenCurrentMonthWasPopulatedButIsEmpty() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        let currentMonth = state.selectedMonth
        let previousMonth = YearMonth(
            year: currentMonth.month == 1 ? currentMonth.year - 1 : currentMonth.year,
            month: currentMonth.month == 1 ? 12 : currentMonth.month - 1
        )
        try repository.markMonthPopulated(currentMonth)

        state.selectedMonth = previousMonth
        try state.refresh()

        XCTAssertTrue(state.canCopyRepeatingEntriesToNextMonth)
    }

    func testRepopulatingUpdatesOnlyEntriesWithMatchingSearchTextAndDate() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        let currentMonth = state.selectedMonth
        let sourceMonth = previousMonth(before: currentMonth)
        let account = try XCTUnwrap(try repository.accounts().first)
        let source = PlannedItem(
            accountID: account.id,
            monthKey: sourceMonth,
            type: .fixedDebit,
            label: "Updated streaming subscription",
            amount: 18,
            matchingString: "STREAMING SERVICE",
            dueDay: 8,
            repeatMode: .calendar
        )
        try repository.createPlannedItem(source)

        let matching = PlannedItem(
            accountID: account.id,
            monthKey: currentMonth,
            type: .fixedDebit,
            label: "Old streaming subscription",
            amount: 12,
            matchingString: "STREAMING SERVICE",
            dueDay: 8,
            repeatMode: .calendar,
            isPaid: true
        )
        let unrelated = PlannedItem(
            accountID: account.id,
            monthKey: currentMonth,
            type: .fixedDebit,
            label: "Unrelated subscription",
            amount: 5,
            matchingString: "OTHER SERVICE",
            dueDay: 8,
            repeatMode: .calendar
        )
        let differentDate = PlannedItem(
            accountID: account.id,
            monthKey: currentMonth,
            type: .fixedDebit,
            label: "Later streaming subscription",
            amount: 14,
            matchingString: "STREAMING SERVICE",
            dueDay: 9,
            repeatMode: .calendar
        )
        try repository.createPlannedItem(matching)
        try repository.createPlannedItem(unrelated)
        try repository.createPlannedItem(differentDate)

        state.selectedMonth = sourceMonth
        try state.refresh()
        XCTAssertTrue(state.canCopyRepeatingEntriesToNextMonth)

        state.copyRepeatingEntriesToNextMonth()

        let currentEntries = try repository.plannedItems(for: currentMonth)
        let updated = try XCTUnwrap(currentEntries.first(where: { $0.id == matching.id }))
        let untouched = try XCTUnwrap(currentEntries.first(where: { $0.id == unrelated.id }))
        let later = try XCTUnwrap(currentEntries.first(where: { $0.id == differentDate.id }))
        XCTAssertEqual(updated.label, "Updated streaming subscription")
        XCTAssertEqual(updated.amount, 18)
        XCTAssertTrue(updated.isPaid)
        XCTAssertEqual(untouched.label, "Unrelated subscription")
        XCTAssertEqual(untouched.amount, 5)
        XCTAssertEqual(later.label, "Later streaming subscription")
        XCTAssertEqual(later.amount, 14)
        XCTAssertEqual(currentEntries.count, 3)
    }

    func testThisAndFutureEditProjectsFromTheSelectedOccurrence() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let anchor = try XCTUnwrap(state.createEntry(
            type: .fixedDebit,
            label: "Gym membership",
            amount: 30,
            dueDay: 1,
            repeatDays: 10
        ))
        let occurrence = try XCTUnwrap(
            state.womOccurrenceGroups
                .flatMap(\.occurrences)
                .first(where: { $0.repeatID == anchor.recurrenceID && $0.scheduledDate != CivilDate(year: state.selectedMonth.year, month: state.selectedMonth.month, day: 1)! })
        )

        XCTAssertTrue(state.savePeriodicOccurrence(
            occurrence,
            label: "Updated gym membership",
            matchingString: "GYM MEMBERSHIP",
            amount: 40,
            dueDate: occurrence.dueDate,
            type: .fixedDebit,
            notes: "",
            repeatDays: 15,
            scope: .thisAndFuture
        ))

        let updated = try XCTUnwrap(state.womOccurrenceGroups.flatMap(\.occurrences).first(where: {
            $0.repeatID == anchor.recurrenceID && $0.scheduledDate == occurrence.scheduledDate
        }))
        XCTAssertEqual(updated.label, "Updated gym membership")
        XCTAssertEqual(updated.amount, 40)
        XCTAssertEqual(updated.repeatDays, 15)
    }

    func testUpdatingMonthItemPersistsMatchingStringAndAllowsClearing() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let account = try XCTUnwrap(try repository.accounts().first)
        let item = PlannedItem(
            accountID: account.id,
            monthKey: state.selectedMonth,
            type: .fixedDebit,
            label: "Council tax",
            amount: 1200,
            dueDay: 10,
            isPaid: false
        )
        try repository.createPlannedItem(item)

        state.update(
            item: item,
            label: "Council tax",
            matchingString: "Statement keywords",
            amount: 1200,
            dueDay: 10,
            dueText: nil,
            type: .fixedDebit,
            copiesToNextMonthAutomatically: true,
            notes: ""
        )

        let savedWithMatchingString = try XCTUnwrap(
            try repository.plannedItems(for: state.selectedMonth).first(where: { $0.id == item.id })
        )
        XCTAssertEqual(savedWithMatchingString.matchingString, "Statement keywords")

        state.update(
            item: item,
            label: "Council tax",
            matchingString: nil,
            amount: 1200,
            dueDay: 10,
            dueText: nil,
            type: .fixedDebit,
            copiesToNextMonthAutomatically: true,
            notes: ""
        )

        let clearedMatchingString = try XCTUnwrap(
            try repository.plannedItems(for: state.selectedMonth).first(where: { $0.id == item.id })
        )
        XCTAssertNil(clearedMatchingString.matchingString)
    }

    func testCreatingMonthItemPersistsMatchingString() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        let created = state.createEntry(
            type: .fixedDebit,
            label: "Parking",
            matchingString: "Statement keywords",
            amount: 12,
            dueDay: 4
        )

        let saved = try XCTUnwrap(created)
        XCTAssertEqual(saved.matchingString, "Statement keywords")
        XCTAssertEqual(
            try repository.plannedItems(for: state.selectedMonth).first(where: { $0.id == saved.id })?.matchingString,
            "Statement keywords"
        )
    }

    func testCreatingEveryNDaysEntryCreatesOnlyItsAnchor() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()

        let created = try XCTUnwrap(state.createEntry(
            type: .fixedDebit,
            label: "Pension",
            amount: 100,
            dueDay: 1,
            repeatDays: 10
        ))

        let monthItems = try repository.plannedItems(for: state.selectedMonth)
        XCTAssertEqual(monthItems.filter { $0.recurrenceID == created.recurrenceID }.count, 1)
        XCTAssertEqual(created.repeatDays, 10)
        XCTAssertEqual(created.dueDay, 1)
    }

    func testChangingEveryNDaysEntryBackToFixedDayClearsRecurrenceMetadata() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let account = try XCTUnwrap(try repository.accounts().first)
        let item = PlannedItem(
            accountID: account.id,
            monthKey: state.selectedMonth,
            type: .fixedDebit,
            label: "Pension",
            amount: 100,
            dueDay: 1,
            repeatDays: 10,
            recurrenceID: UUID()
        )
        try repository.createPlannedItem(item)

        state.update(
            item: item,
            label: "Pension",
            amount: 100,
            dueDay: 2,
            dueText: nil,
            type: .fixedDebit,
            repeatDays: nil,
            recurrenceID: nil,
            repeatMode: .calendar,
            copiesToNextMonthAutomatically: true,
            notes: ""
        )

        let saved = try XCTUnwrap(try repository.plannedItems(for: state.selectedMonth).first)
        XCTAssertEqual(saved.repeatDays, 10)
        XCTAssertEqual(saved.recurrenceID, item.recurrenceID)
        XCTAssertEqual(saved.repeatMode, .calendar)
    }

    func testPopulatingEveryNDaysEntryCreatesAllLaterOccurrencesInSelectedMonth() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let item = try XCTUnwrap(state.createEntry(
            type: .fixedDebit,
            label: "Pension",
            amount: 100,
            dueDay: 1,
            repeatDays: 10
        ))

        XCTAssertEqual(state.sameMonthOccurrences(for: item).compactMap(\.dueDay), [11, 21])
        state.populateSameMonth(for: item)

        XCTAssertEqual(
            try repository.plannedItems(for: state.selectedMonth)
                .filter { $0.recurrenceID == item.recurrenceID }
                .compactMap(\.dueDay)
                .sorted(),
            [1, 11, 21]
        )
    }

    func testEditingImportedUnplannedItemPromotesSourceToManual() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let account = try XCTUnwrap(try repository.accounts().first)
        let item = PlannedItem(
            accountID: account.id,
            monthKey: state.selectedMonth,
            type: .fixedDebit,
            source: .importedUnplanned,
            label: "Shop Purchase",
            amount: 42,
            matchingString: "shop",
            dueDay: 14,
            isPaid: true,
            copiesToNextMonthAutomatically: false,
            notes: "Imported"
        )
        try repository.createPlannedItem(item)

        state.update(
            item: item,
            label: "Shop Purchase",
            matchingString: "shop",
            amount: 42,
            dueDay: 14,
            dueText: nil,
            type: .fixedDebit,
            copiesToNextMonthAutomatically: false,
            notes: "Edited by user"
        )

        let saved = try XCTUnwrap(
            try repository.plannedItems(for: state.selectedMonth).first(where: { $0.id == item.id })
        )
        XCTAssertEqual(saved.source, .manual)
        XCTAssertEqual(saved.matchingString, "shop")
        XCTAssertEqual(saved.notes, "Edited by user")
    }

    func testEditingCopiedItemPreservesCopiedSource() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let account = try XCTUnwrap(try repository.accounts().first)
        let item = PlannedItem(
            accountID: account.id,
            monthKey: state.selectedMonth,
            type: .fixedDebit,
            source: .copiedFromPreviousMonth,
            label: "Rent",
            amount: 1200,
            dueDay: 1,
            isPaid: false
        )
        try repository.createPlannedItem(item)

        state.update(
            item: item,
            label: "Rent",
            matchingString: nil,
            amount: 1200,
            dueDay: 1,
            dueText: nil,
            type: .fixedDebit,
            sourceOverride: .copiedFromPreviousMonth,
            copiesToNextMonthAutomatically: true,
            notes: ""
        )

        let saved = try XCTUnwrap(
            try repository.plannedItems(for: state.selectedMonth).first(where: { $0.id == item.id })
        )
        XCTAssertEqual(saved.source, .copiedFromPreviousMonth)
    }

    func testManualMatchCandidatesExcludePaidAndImportedUnplannedItems() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let account = try XCTUnwrap(try repository.accounts().first)
        let source = PlannedItem(
            accountID: account.id,
            monthKey: state.selectedMonth,
            type: .fixedDebit,
            source: .importedUnplanned,
            label: "Source",
            amount: 20,
            dueDay: 4,
            isPaid: true,
            copiesToNextMonthAutomatically: false
        )
        let eligible = PlannedItem(
            accountID: account.id,
            monthKey: state.selectedMonth,
            type: .fixedDebit,
            label: "Eligible",
            amount: 20,
            dueDay: 5,
            isPaid: false
        )
        let paid = PlannedItem(
            accountID: account.id,
            monthKey: state.selectedMonth,
            type: .fixedDebit,
            label: "Paid",
            amount: 30,
            dueDay: 6,
            isPaid: true
        )
        let importedUnplanned = PlannedItem(
            accountID: account.id,
            monthKey: state.selectedMonth,
            type: .fixedDebit,
            source: .importedUnplanned,
            label: "Imported unplanned",
            amount: 40,
            dueDay: 7,
            isPaid: false,
            copiesToNextMonthAutomatically: false
        )
        try repository.createPlannedItem(source)
        try repository.createPlannedItem(eligible)
        try repository.createPlannedItem(paid)
        try repository.createPlannedItem(importedUnplanned)
        try state.refresh()

        XCTAssertEqual(
            state.manualMatchCandidates(for: source).map(\.label),
            ["Eligible"]
        )
    }

    func testManualMatchMovesImportToTargetAndDeletesSourceItem() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let account = try XCTUnwrap(try repository.accounts().first)
        let source = PlannedItem(
            accountID: account.id,
            monthKey: state.selectedMonth,
            type: .fixedDebit,
            source: .importedUnplanned,
            label: "Coffee shop",
            amount: 14.50,
            dueDay: 17,
            importedPostedAt: Self.date(year: state.selectedMonth.year, month: state.selectedMonth.month, day: 17),
            isPaid: true,
            copiesToNextMonthAutomatically: false
        )
        let target = PlannedItem(
            accountID: account.id,
            monthKey: state.selectedMonth,
            type: .fixedDebit,
            label: "Eating out",
            amount: 12,
            matchingString: nil,
            dueDay: 5,
            isPaid: false
        )
        try repository.createPlannedItem(source)
        try repository.createPlannedItem(target)
        let importRecord = ImportedTransactionRecord(
            accountID: account.id,
            sourceKind: ImportedTransactionService.nationwideOFXSourceKind,
            sourceAccountIdentifier: "****81197",
            externalTransactionID: "FITID-MANUAL-MATCH",
            postedAt: Self.date(year: state.selectedMonth.year, month: state.selectedMonth.month, day: 17),
            amount: -14.50,
            payee: "Coffee shop",
            transactionType: "POS",
            rawSourcePayload: "{}",
            appliedPlannedItemID: source.id
        )
        try repository.createImportedTransactionRecord(importRecord)
        try state.refresh()

        let matchedItem = try XCTUnwrap(state.matchImportedUnplannedItem(source, to: target))

        let savedTarget = try XCTUnwrap(try repository.plannedItem(id: matchedItem.id))
        let records = try repository.importedTransactionRecords(accountIDs: [account.id])

        XCTAssertEqual(savedTarget.id, target.id)
        XCTAssertEqual(savedTarget.amount, 14.50)
        XCTAssertEqual(savedTarget.dueDay, 17)
        XCTAssertEqual(savedTarget.importedPostedAt, importRecord.postedAt)
        XCTAssertEqual(savedTarget.matchingString, "Coffee shop")
        XCTAssertTrue(savedTarget.isPaid)
        XCTAssertEqual(records.first?.appliedPlannedItemID, target.id)
        XCTAssertFalse(try repository.hasPlannedItem(id: source.id))
    }

    func testSwiftDataUpsertPreservesImportedPostedAt() throws {
        let schema = Schema(versionedSchema: MonthlyMoneySchemaV3.self)
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let container = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(
                "SwiftDataUpsertTest",
                schema: schema,
                url: directory.appendingPathComponent("Budget.store"),
                cloudKitDatabase: .none
            )]
        )
        let store = SwiftDataAccountDataStore(modelContainer: container)
        let date = Self.date(year: 2026, month: 3, day: 17)
        let itemID = UUID()
        let original = PlannedItem(
            id: itemID,
            accountID: UUID(),
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Imported",
            amount: 10
        )
        try store.upsertPlannedItems([original])

        let updated = PlannedItem(
            id: itemID,
            accountID: original.accountID,
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Imported",
            amount: 10,
            importedPostedAt: date
        )
        try store.upsertPlannedItems([updated])

        XCTAssertEqual(try store.fetchPlannedItem(id: itemID)?.importedPostedAt, date)
    }

    func testManualMatchPreservesExistingMatchingString() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let account = try XCTUnwrap(try repository.accounts().first)
        let source = PlannedItem(
            accountID: account.id,
            monthKey: state.selectedMonth,
            type: .fixedDebit,
            source: .importedUnplanned,
            label: "Tesco",
            amount: 54,
            dueDay: 9,
            isPaid: true,
            copiesToNextMonthAutomatically: false
        )
        let target = PlannedItem(
            accountID: account.id,
            monthKey: state.selectedMonth,
            type: .fixedDebit,
            label: "Groceries",
            amount: 50,
            matchingString: "supermarket",
            dueDay: 2,
            isPaid: false
        )
        try repository.createPlannedItem(source)
        try repository.createPlannedItem(target)
        try repository.createImportedTransactionRecord(
            ImportedTransactionRecord(
                accountID: account.id,
                sourceKind: ImportedTransactionService.nationwideOFXSourceKind,
                sourceAccountIdentifier: "****81197",
                externalTransactionID: "FITID-MANUAL-MATCH-KEEP",
                postedAt: Self.date(year: state.selectedMonth.year, month: state.selectedMonth.month, day: 9),
                amount: -54,
                payee: "Tesco",
                transactionType: "POS",
                rawSourcePayload: "{}",
                appliedPlannedItemID: source.id
            )
        )

        _ = try state.matchImportedUnplannedItem(source, to: target)

        let savedTarget = try XCTUnwrap(try repository.plannedItem(id: target.id))
        XCTAssertEqual(savedTarget.matchingString, "supermarket")
    }

    func testLinkedImportedPayeeReturnsStatementTextForMatchedItem() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository)

        await state.bootstrapIfNeeded()
        let account = try XCTUnwrap(try repository.accounts().first)
        let item = PlannedItem(
            accountID: account.id,
            monthKey: state.selectedMonth,
            type: .fixedDebit,
            label: "Groceries",
            amount: 54,
            dueDay: 9,
            isPaid: true
        )
        try repository.createPlannedItem(item)
        try repository.createImportedTransactionRecord(
            ImportedTransactionRecord(
                accountID: account.id,
                sourceKind: ImportedTransactionService.nationwideOFXSourceKind,
                sourceAccountIdentifier: "****81197",
                externalTransactionID: "FITID-STATEMENT-TEXT",
                postedAt: Self.date(year: state.selectedMonth.year, month: state.selectedMonth.month, day: 9),
                amount: -54,
                payee: "TESCO STORES 1234",
                transactionType: "POS",
                rawSourcePayload: "{}",
                appliedPlannedItemID: item.id
            )
        )

        XCTAssertEqual(state.linkedImportedPayee(for: item), "TESCO STORES 1234")
        XCTAssertEqual(
            state.linkedImportedPostedAt(for: item),
            Self.date(year: state.selectedMonth.year, month: state.selectedMonth.month, day: 9)
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

    func testDailyBudgetStatusFormatterBuildsAheadSummary() {
        let summary = DailyBudgetStatusFormatter.summary(
            from: DailyBudgetStatusSnapshot(
                aheadBehind: 125.50,
                currentDailyBudget: 18.25,
                daysUntilPayday: 6,
                projectedBalance: 240
            )
        )

        XCTAssertEqual(
            summary.spokenPhrase,
            "You're £125.50 ahead. Daily budget: £18.25. Payday is in 6 days."
        )
    }

    func testDailyBudgetStatusFormatterBuildsBehindSummary() {
        let summary = DailyBudgetStatusFormatter.summary(
            from: DailyBudgetStatusSnapshot(
                aheadBehind: -42.10,
                currentDailyBudget: 9.75,
                daysUntilPayday: 1,
                projectedBalance: 80
            )
        )

        XCTAssertEqual(
            summary.spokenPhrase,
            "You're £42.10 behind. Daily budget: £9.75. Payday is in 1 day."
        )
    }

    func testDailyBudgetStatusServiceReturnsCurrentBudgetStatusSnapshot() async throws {
        let repository = try makeRepository()
        let state = AppState(repository: repository, nowProvider: {
            Self.date(year: 2026, month: 4, day: 13)
        })

        await state.bootstrapIfNeeded()
        state.dailyBudgetAmount = 300
        state.dailyBudgetPaydayDay = 20
        state.primaryBankBalance = 240

        let account = try XCTUnwrap(try repository.accounts().first)
        try repository.createPlannedItem(
            PlannedItem(
                accountID: account.id,
                monthKey: state.selectedMonth,
                type: .fixedDebit,
                label: "Rent",
                amount: 90,
                dueDay: 18,
                isPaid: false
            )
        )
        try state.refresh()

        let service = DailyBudgetStatusService(
            repository: repository,
            nowProvider: { Self.date(year: 2026, month: 4, day: 13) }
        )

        let expectedMetrics = state.dailyCycleMetrics
        let snapshot = try service.currentStatus()

        XCTAssertEqual(snapshot.aheadBehind, expectedMetrics.aheadBehind)
        XCTAssertEqual(snapshot.currentDailyBudget, expectedMetrics.currentDailyBudget)
        XCTAssertEqual(snapshot.daysUntilPayday, expectedMetrics.remainingDaysToPayday)
        XCTAssertEqual(snapshot.projectedBalance, state.projectedBalanceFromCurrentBalance)
    }

    func testRefreshMigratesMissingBalanceLastUpdatedTimestampsFromBudgetUpdatedAt() async throws {
        let repository = try makeRepository()
        let legacyUpdatedAt = Self.date(year: 2026, month: 2, day: 27, hour: 8, minute: 0)
        let budget = try XCTUnwrap(try repository.activeBudget() ?? repository.createBudget(name: "Budget", ownerParticipantID: "owner"))
        budget.updatedAt = legacyUpdatedAt
        budget.monthlyBalanceLastUpdatedAt = nil
        budget.dailyBalanceLastUpdatedAt = nil
        try repository.saveBudget(budget, updateModifiedAt: false)

        let state = AppState(repository: repository)
        try state.refresh()

        let migratedBudget = try XCTUnwrap(try repository.activeBudget())
        XCTAssertEqual(migratedBudget.monthlyBalanceLastUpdatedAt, legacyUpdatedAt)
        XCTAssertEqual(migratedBudget.dailyBalanceLastUpdatedAt, legacyUpdatedAt)
    }

    func testBalanceLastUpdatedPresentationBecomesStaleAfterSevenDays() {
        let updatedAt = Self.date(year: 2026, month: 3, day: 1)
        let freshReference = Self.date(year: 2026, month: 3, day: 8)
        let staleReference = Self.date(year: 2026, month: 3, day: 9)

        XCTAssertFalse(BalanceLastUpdatedPresentation.isStale(updatedAt, relativeTo: freshReference, calendar: Self.utcCalendar))
        XCTAssertTrue(BalanceLastUpdatedPresentation.isStale(updatedAt, relativeTo: staleReference, calendar: Self.utcCalendar))
    }

    func testDailyBudgetStatusFormatterBuildsProjectedOverdraftSummary() {
        let summary = DailyBudgetStatusFormatter.summary(
            from: DailyBudgetStatusSnapshot(
                aheadBehind: -42.10,
                currentDailyBudget: 9.75,
                daysUntilPayday: 3,
                projectedBalance: -58.40
            )
        )

        XCTAssertEqual(
            summary.spokenPhrase,
            "3 days to payday, you need to pay at least £58.40 in to avoid going overdrawn."
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

    func testMonthlyBudgetFromWeekModelUsesPaydayCycleWeekends() {
        let budget = MonthCalculationEngine.monthlyBudgetFromWeekModel(
            year: 2026,
            month: 7,
            paydayDay: 26,
            weeklyEstimate: 0,
            weekendEstimate: 10
        )

        XCTAssertEqual(budget, 90)
    }

    func testMonthItemEditorDraftRequiresNameButAllowsZeroAmountToSave() {
        var draft = MonthItemEditorDraft(newType: .fixedDebit, dueDay: 11)

        XCTAssertFalse(draft.canSave)

        draft.label = "Gas bill"
        XCTAssertTrue(draft.canSave)

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

    func testMonthItemEditorDraftInitialisesStatementKeywordsFromItem() {
        let draft = MonthItemEditorDraft(
            item: PlannedItem(
                accountID: UUID(),
                monthKey: YearMonth(year: 2026, month: 3),
                type: .fixedDebit,
                source: .importedUnplanned,
                label: "Rent",
                amount: 1200,
                matchingString: "monthly rent"
            )
        )

        XCTAssertEqual(draft.matchingString, "monthly rent")
        XCTAssertFalse(draft.isPlanned)
    }

    func testMonthItemEditorDraftValidatesEveryNDaysRepeatInput() {
        let item = PlannedItem(
            accountID: UUID(),
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Pension",
            amount: 100,
            dueDay: 1,
            repeatDays: 28,
            recurrenceID: UUID()
        )
        var draft = MonthItemEditorDraft(item: item)

        XCTAssertEqual(draft.dueSelection, .everyNDays)
        XCTAssertEqual(draft.repeatDaysText, "28")
        XCTAssertEqual(draft.repeatDays, 28)

        for invalidValue in ["", "0", "-1", "28.5"] {
            draft.repeatDaysText = invalidValue
            XCTAssertFalse(draft.canSave)
        }

        draft.repeatDaysText = "14"
        XCTAssertTrue(draft.canSave)
    }

    func testMonthItemEditorDraftRequiresEveryNDaysAnchor() {
        let item = PlannedItem(
            accountID: UUID(),
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Pension",
            amount: 100
        )
        var draft = MonthItemEditorDraft(item: item)
        draft.dueSelection = .everyNDays
        draft.repeatDaysText = "28"

        XCTAssertNil(draft.dueDay)
        XCTAssertFalse(draft.canSave)

        draft.repeatAnchorDay = 1
        XCTAssertTrue(draft.canSave)
    }

    func testMonthItemEditorDraftPreservesConcreteDayWhenRepeatIsTurnedOff() {
        let item = PlannedItem(
            accountID: UUID(),
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Imported bill",
            amount: 42,
            dueDay: 17,
            repeatMode: .calendar
        )
        var draft = MonthItemEditorDraft(item: item)

        draft.repeatMode = .oneOff

        XCTAssertEqual(draft.dueDay, 17)
    }

    func testMonthItemEditorDraftRecoversMissingDayFromImportedDate() {
        let importedDate = Self.date(year: 2026, month: 3, day: 17)
        let item = PlannedItem(
            accountID: UUID(),
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Imported bill",
            amount: 42,
            repeatMode: .oneOff
        )

        let draft = MonthItemEditorDraft(item: item, importedPostedAt: importedDate)

        XCTAssertEqual(draft.dueDay, 17)
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
        XCTAssertEqual(item.source, .manual)
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
            copiesToNextMonthAutomatically: false,
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

    func testMonthItemRowMetadataLinesShowCopyIndicatorForRecurringItems() {
        let item = PlannedItem(
            accountID: UUID(),
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Rent",
            amount: 1200,
            dueDay: 28,
            dueText: nil,
            isPaid: false,
            copiesToNextMonthAutomatically: true
        )

        XCTAssertEqual(MonthItemRowContent.metadataLines(for: item), ["28th"])
    }

    func testMonthItemRowShowsUnplannedIndicatorForImportedUnplannedItems() {
        let outgoingUnplannedItem = PlannedItem(
            accountID: UUID(),
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            source: .importedUnplanned,
            label: "Coffee",
            amount: 4.50
        )
        let creditUnplannedItem = PlannedItem(
            accountID: UUID(),
            monthKey: YearMonth(year: 2026, month: 3),
            type: .credit,
            source: .importedUnplanned,
            label: "Refund",
            amount: 12
        )
        let manualItem = PlannedItem(
            accountID: UUID(),
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            source: .manual,
            label: "Rent",
            amount: 1200
        )

        XCTAssertEqual(MonthItemRowContent.amountFootnote(for: outgoingUnplannedItem), "unplanned")
        XCTAssertNil(MonthItemRowContent.amountFootnote(for: creditUnplannedItem))
        XCTAssertNil(MonthItemRowContent.amountFootnote(for: manualItem))
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
                selectedMonth: YearMonth(year: 2026, month: 3),
                paydayDay: 1,
                today: Self.date(year: 2026, month: 3, day: 12)
            )
        )
    }

    func testMonthItemRowDoesNotHighlightNextCalendarMonthItemsAfterPayday() {
        let item = PlannedItem(
            accountID: UUID(),
            monthKey: YearMonth(year: 2026, month: 7),
            type: .fixedDebit,
            label: "Mortgage",
            amount: 1_200,
            dueDay: 1,
            dueText: nil,
            isPaid: false
        )

        XCTAssertFalse(
            MonthItemRowContent.showsOverdueHighlight(
                for: item,
                isSelectedMonthInPast: false,
                isSelectedMonthInFuture: false,
                selectedMonth: YearMonth(year: 2026, month: 7),
                paydayDay: 28,
                today: Self.date(year: 2026, month: 6, day: 29)
            )
        )
    }

    func testAutomaticMonthCopyIncludesRepeatingItemsOnly() {
        let items = [
            PlannedItem(
                accountID: UUID(),
                monthKey: YearMonth(year: 2026, month: 3),
                type: .fixedDebit,
                label: "Rent",
                amount: 1200,
                dueDay: 1,
                repeatMode: .calendar
            ),
            PlannedItem(
                accountID: UUID(),
                monthKey: YearMonth(year: 2026, month: 3),
                type: .fixedDebit,
                label: "One-off",
                amount: 75,
                repeatMode: .oneOff,
                copiesToNextMonthAutomatically: true
            )
        ]

        XCTAssertEqual(
            PlannedItem.automaticallyCopiedItems(from: items).map(\.label),
            ["Rent"]
        )
    }

    private func makeRepository(dateProvider: @escaping () -> Date = Date.init) throws -> AccountRepository {
        return AccountRepository(
            privateStore: InMemoryAccountDataStore(),
            sharedStore: InMemoryAccountDataStore(),
            dateProvider: dateProvider
        )
    }

    private static func localCoreDataPlan(baseDirectory: URL) -> MonthlyMoneyPersistencePlan {
        MonthlyMoneyPersistencePlan(
            privateStore: MonthlyMoneyStorePlan(
                name: "PrivateStore",
                url: baseDirectory.appendingPathComponent("PrivateStore.store"),
                syncMode: .localOnly,
                backend: .coreData
            ),
            sharedStore: MonthlyMoneyStorePlan(
                name: "SharedStore",
                url: baseDirectory.appendingPathComponent("SharedStore.store"),
                syncMode: .localOnly,
                backend: .coreData
            )
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
        let wheelOfMoneyItem = WheelOfMoneyItem(
            budgetID: budget.id,
            title: "Shared Christmas",
            amount: 1000,
            month: WheelOfMoneyMonth.december.rawValue,
            isPaid: false,
            notes: "Shared presents"
        )

        try repository.insertShared(
            budget: budget,
            accounts: [account],
            plannedItems: [item],
            transactions: [],
            wheelOfMoneyItems: [wheelOfMoneyItem]
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

    private final class DailyBudgetWatchSnapshotSyncSpy: DailyBudgetWatchSnapshotSyncing {
        private(set) var snapshots: [DailyBudgetWatchSnapshot] = []

        func sync(_ snapshot: DailyBudgetWatchSnapshot) {
            snapshots.append(snapshot)
        }
    }

    private final class DailyBudgetWidgetSnapshotSyncSpy: DailyBudgetWidgetSnapshotSyncing {
        private(set) var snapshots: [DailyBudgetWidgetSnapshot] = []

        func sync(_ snapshot: DailyBudgetWidgetSnapshot) {
            snapshots.append(snapshot)
        }
    }

    private static func makeSchema() -> Schema {
        Schema(versionedSchema: MonthlyMoneySchemaV3.self)
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

    private static func date(year: Int, month: Int, day: Int, hour: Int, minute: Int) -> Date {
        utcCalendar.date(from: DateComponents(
            calendar: utcCalendar,
            timeZone: utcCalendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        ))!
    }

    private static func makeOFXData(
        postedDate: String,
        transactionAmount: String,
        ledgerBalance: String? = nil
    ) -> Data {
        let ledgerBalanceBlock = ledgerBalance.map {
            """
            <LEDGERBAL>
              <BALAMT>\($0)</BALAMT>
              <DTASOF>\(postedDate)</DTASOF>
            </LEDGERBAL>
            """
        } ?? ""

        let ofx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <OFX>
          <BANKMSGSRSV1>
            <STMTTRNRS>
              <STMTRS>
                <CURDEF>GBP</CURDEF>
                <BANKACCTFROM>
                  <ACCTID>****81197</ACCTID>
                </BANKACCTFROM>
                <BANKTRANLIST>
                  <DTSTART>20260301000000</DTSTART>
                  <DTEND>20260331235959</DTEND>
                  <STMTTRN>
                    <TRNTYPE>DEBIT</TRNTYPE>
                    <DTPOSTED>\(postedDate)</DTPOSTED>
                    <TRNAMT>\(transactionAmount)</TRNAMT>
                    <FITID>FITID-1</FITID>
                    <NAME>Card Payment</NAME>
                  </STMTTRN>
                </BANKTRANLIST>
                \(ledgerBalanceBlock)
              </STMTRS>
            </STMTTRNRS>
          </BANKMSGSRSV1>
        </OFX>
        """

        return Data(ofx.utf8)
    }

    private static func makeQIFData() -> Data {
        let qif = """
        !Type:Bank
        D02/03/2026
        T-12.34
        PMonzo Card
        LEating out
        MCoffee
        ^
        D29/03/2026
        T200.00
        PRoger Nolan
        LTransfers
        MPOCKET MONEY
        ^
        """

        return Data(qif.utf8)
    }

    private static func makeOutOfCycleQIFData() -> Data {
        let qif = """
        !Type:Bank
        D02/12/2025
        T-12.34
        PMonzo Card
        ^
        D27/02/2026
        T200.00
        PRoger Nolan
        ^
        """

        return Data(qif.utf8)
    }

    private func makeTestBudgetShareSession(budgetID: UUID) -> BudgetShareSession {
        let rootRecord = CKRecord(recordType: "Budget")
        let share = CKShare(rootRecord: rootRecord)
        share[CKShare.SystemFieldKey.title] = "MonthlyMoney" as CKRecordValue
        return BudgetShareSession(
            budgetID: budgetID,
            share: share,
            containerIdentifier: MonthlyMoneyPersistenceFactory.cloudKitContainerIdentifier
        )
    }

    func testCoreDataModelBuilderDefinesAndPersistsEveryNDaysAttributes() throws {
        let plannedItemEntity = try XCTUnwrap(
            CoreDataModelBuilder.sharedModel.entitiesByName[CoreDataEntityName.plannedItem]
        )
        XCTAssertEqual(
            plannedItemEntity.attributesByName["repeatDays"]?.attributeType,
            .integer16AttributeType
        )
        XCTAssertEqual(
            plannedItemEntity.attributesByName["recurrenceID"]?.attributeType,
            .UUIDAttributeType
        )
        XCTAssertTrue(plannedItemEntity.attributesByName["repeatDays"]?.isOptional == true)
        XCTAssertTrue(plannedItemEntity.attributesByName["recurrenceID"]?.isOptional == true)

        let managedObjectContext = try makeInMemoryManagedObjectContext()
        let item = PlannedItem(
            accountID: UUID(),
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Pension",
            amount: 100,
            dueDay: 26,
            repeatDays: 28,
            recurrenceID: UUID()
        )
        let managedObject = NSEntityDescription.insertNewObject(
            forEntityName: CoreDataEntityName.plannedItem,
            into: managedObjectContext
        )
        CoreDataMapping.apply(item, to: managedObject)
        try managedObjectContext.save()

        let roundTrip = CoreDataMapping.plannedItem(from: managedObject)
        XCTAssertEqual(roundTrip.repeatDays, 28)
        XCTAssertEqual(roundTrip.recurrenceID, item.recurrenceID)

        let legacyObject = NSEntityDescription.insertNewObject(
            forEntityName: CoreDataEntityName.plannedItem,
            into: managedObjectContext
        )
        let migratedFloating = CoreDataMapping.plannedItem(from: legacyObject)
        XCTAssertEqual(migratedFloating.repeatMode, .oneOff)
        XCTAssertNil(migratedFloating.repeatDays)
        XCTAssertNil(migratedFloating.dueDay)
        XCTAssertNil(migratedFloating.recurrenceID)
    }

    func testCoreDataEveryNDaysMigrationIsVersionedAndInferable() throws {
        XCTAssertEqual(CoreDataModelBuilder.legacyModel.versionIdentifiers, ["MonthlyMoney.v2"])
        XCTAssertEqual(CoreDataModelBuilder.v3Model.versionIdentifiers, ["MonthlyMoney.v3"])
        XCTAssertEqual(CoreDataModelBuilder.v4Model.versionIdentifiers, ["MonthlyMoney.v4"])
        XCTAssertEqual(CoreDataModelBuilder.sharedModel.versionIdentifiers, ["MonthlyMoney.v5"])
        XCTAssertEqual(
            CoreDataModelBuilder.sharedModel.entitiesByName[CoreDataEntityName.plannedItem]?.attributesByName["importedPostedAt"]?.attributeType,
            .dateAttributeType
        )
        XCTAssertEqual(
            CoreDataModelBuilder.sharedModel.entitiesByName[CoreDataEntityName.budget]?.attributesByName["allowsPreviousMonthEditing"]?.defaultValue as? Bool,
            false
        )

        let mapping = try CoreDataModelBuilder.inferredEveryNDaysMigrationModel()
        XCTAssertTrue(mapping.entityMappings.contains { $0.sourceEntityName == CoreDataEntityName.plannedItem })
    }

    func testCoreDataEveryNDaysMigrationUsesExplicitPolicy() throws {
        let mapping = try CoreDataModelBuilder.explicitEveryNDaysMigrationModel()
        let plannedItemMapping = try XCTUnwrap(
            mapping.entityMappings.first { $0.sourceEntityName == CoreDataEntityName.plannedItem }
        )

        XCTAssertEqual(plannedItemMapping.mappingType.rawValue, 1)
        XCTAssertEqual(
            plannedItemMapping.entityMigrationPolicyClassName,
            NSStringFromClass(CoreDataV2ToV3MigrationPolicy.self)
        )
    }

    func testCoreDataV2StoreMigratesBeforeLoadingV3Store() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("PrivateStore.sqlite")
        let budgetID = UUID()
        let accountID = UUID()
        let itemID = UUID()
        let copiedItemID = UUID()

        do {
            let container = NSPersistentContainer(
                name: "MonthlyMoneyCoreData",
                managedObjectModel: CoreDataModelBuilder.legacyModel
            )
            let description = NSPersistentStoreDescription(url: storeURL)
            description.type = NSSQLiteStoreType
            description.shouldAddStoreAsynchronously = false
            container.persistentStoreDescriptions = [description]
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError { throw loadError }

            let context = container.viewContext
            let budget = NSEntityDescription.insertNewObject(
                forEntityName: CoreDataEntityName.budget,
                into: context
            )
            budget.setValue(budgetID, forKey: "id")
            budget.setValue("Home", forKey: "name")
            budget.setValue("owner", forKey: "ownerParticipantID")
            let account = NSEntityDescription.insertNewObject(
                forEntityName: CoreDataEntityName.account,
                into: context
            )
            account.setValue(accountID, forKey: "id")
            account.setValue(budgetID, forKey: "budgetID")
            account.setValue("Current", forKey: "name")
            let item = NSEntityDescription.insertNewObject(
                forEntityName: CoreDataEntityName.plannedItem,
                into: context
            )
            item.setValue(itemID, forKey: "id")
            item.setValue(budgetID, forKey: "budgetID")
            item.setValue(accountID, forKey: "accountID")
            item.setValue("2026-04", forKey: "monthKey")
            item.setValue(PlannedItemType.fixedDebit.rawValue, forKey: "typeRaw")
            item.setValue("Pension", forKey: "label")
            item.setValue(NSDecimalNumber(string: "100"), forKey: "amount")
            item.setValue(true, forKey: "copiesToNextMonthAutomatically")
            let copiedItem = NSEntityDescription.insertNewObject(
                forEntityName: CoreDataEntityName.plannedItem,
                into: context
            )
            copiedItem.setValue(copiedItemID, forKey: "id")
            copiedItem.setValue(budgetID, forKey: "budgetID")
            copiedItem.setValue(accountID, forKey: "accountID")
            copiedItem.setValue("2026-05", forKey: "monthKey")
            copiedItem.setValue(PlannedItemType.fixedDebit.rawValue, forKey: "typeRaw")
            copiedItem.setValue("Pension", forKey: "label")
            copiedItem.setValue(NSDecimalNumber(string: "100"), forKey: "amount")
            copiedItem.setValue(true, forKey: "copiesToNextMonthAutomatically")
            try context.save()
        }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: nil
        )
        XCTAssertTrue(
            CoreDataModelBuilder.legacyModel.isConfiguration(
                withName: nil,
                compatibleWithStoreMetadata: metadata
            )
        )
        let store = try CoreDataAccountDataStore.makePersistentLocal(url: storeURL)
        let migratedItems = try store.fetchPlannedItems()
        let migratedItem = try XCTUnwrap(migratedItems.first { $0.id == itemID })
        XCTAssertEqual(migratedItem.repeatMode, .oneOff)
        XCTAssertNil(migratedItem.repeatDays)
        XCTAssertNil(migratedItem.dueDay)
        XCTAssertNil(migratedItem.recurrenceID)
        let migratedCopy = try XCTUnwrap(migratedItems.first { $0.id == copiedItemID })
        XCTAssertEqual(migratedCopy.repeatMode, .oneOff)
        XCTAssertNil(migratedCopy.recurrenceID)
    }

    func testCoreDataV4StoreMigratesPreviousMonthEditingAsOff() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appendingPathComponent("PrivateStore.sqlite")
        let budgetID = UUID()

        try autoreleasepool {
            let container = NSPersistentContainer(
                name: "MonthlyMoneyCoreData",
                managedObjectModel: CoreDataModelBuilder.v4Model
            )
            let description = NSPersistentStoreDescription(url: storeURL)
            description.type = NSSQLiteStoreType
            description.shouldAddStoreAsynchronously = false
            container.persistentStoreDescriptions = [description]
            var loadError: Error?
            container.loadPersistentStores { _, error in loadError = error }
            if let loadError { throw loadError }

            let budget = NSEntityDescription.insertNewObject(
                forEntityName: CoreDataEntityName.budget,
                into: container.viewContext
            )
            budget.setValue(budgetID, forKey: "id")
            budget.setValue("Home", forKey: "name")
            budget.setValue("owner", forKey: "ownerParticipantID")
            try container.viewContext.save()
            if let persistentStore = container.persistentStoreCoordinator.persistentStores.first {
                try container.persistentStoreCoordinator.remove(persistentStore)
            }
        }

        let metadata = try NSPersistentStoreCoordinator.metadataForPersistentStore(
            ofType: NSSQLiteStoreType,
            at: storeURL,
            options: nil
        )
        XCTAssertTrue(
            CoreDataModelBuilder.v4Model.isConfiguration(withName: nil, compatibleWithStoreMetadata: metadata)
        )

        let store = try CoreDataAccountDataStore.makePersistentLocal(url: storeURL)
        XCTAssertFalse(try XCTUnwrap(store.fetchBudgets().first).allowsPreviousMonthEditing)
    }

    func testRepeatModeAndPopulatedMonthArePersistedInTheCurrentModel() throws {
        XCTAssertEqual(RepeatMode.periodic.rawValue, "periodic")
        let budgetID = UUID()
        let month = YearMonth(year: 2026, month: 4)
        let marker = PopulatedMonth(budgetID: budgetID, monthKey: month)
        XCTAssertEqual(marker.monthKey, month)

        let plannedItemEntity = try XCTUnwrap(
            CoreDataModelBuilder.sharedModel.entitiesByName[CoreDataEntityName.plannedItem]
        )
        XCTAssertEqual(
            plannedItemEntity.attributesByName["repeatModeRaw"]?.attributeType,
            .stringAttributeType
        )
        XCTAssertTrue(plannedItemEntity.attributesByName["repeatModeRaw"]?.isOptional == true)
        XCTAssertNotNil(CoreDataModelBuilder.sharedModel.entitiesByName[CoreDataEntityName.populatedMonth])
    }

    func testPopulatedMonthRepositoryRoundTripAndDeduplication() throws {
        let repository = try makeRepository()
        let budget = try repository.createBudget(name: "Home", ownerParticipantID: "owner")
        _ = try repository.createAccount(name: "Current", role: .regular, type: .current, ownerParticipantID: "owner")
        let month = YearMonth(year: 2026, month: 4)

        try repository.markMonthPopulated(month)
        try repository.markMonthPopulated(month)

        XCTAssertTrue(try repository.isMonthPopulated(month))
        XCTAssertEqual(try repository.populatedMonths().filter { $0.budgetID == budget.id && $0.monthKey == month }.count, 1)
    }

    func testPeriodicHistoryIsScopedAndBeforeTarget() throws {
        let repository = try makeRepository()
        let budget = try repository.createBudget(name: "Home", ownerParticipantID: "owner")
        let account = try repository.createAccount(name: "Current", role: .regular, type: .current, ownerParticipantID: "owner")
        let target = YearMonth(year: 2026, month: 6)
        let periodic = PlannedItem(
            budgetID: budget.id, accountID: account.id, monthKey: YearMonth(year: 2026, month: 4),
            type: .fixedDebit, label: "Pension", amount: 100, dueDay: 4, repeatDays: 28,
            recurrenceID: UUID(), repeatMode: .periodic
        )
        let calendar = PlannedItem(
            budgetID: budget.id, accountID: account.id, monthKey: YearMonth(year: 2026, month: 5),
            type: .fixedDebit, label: "Rent", amount: 100, dueDay: 1, repeatMode: .calendar
        )
        try repository.createPlannedItem(periodic)
        try repository.createPlannedItem(calendar)

        let history = try repository.periodicItems(before: target)
        XCTAssertEqual(history.map(\.id), [periodic.id])
    }

    private func makeInMemoryManagedObjectContext() throws -> NSManagedObjectContext {
        let container = NSPersistentContainer(
            name: "MonthlyMoneyCoreData",
            managedObjectModel: CoreDataModelBuilder.sharedModel
        )
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]

        var loadError: Error?
        container.loadPersistentStores { _, error in
            loadError = error
        }
        if let loadError { throw loadError }
        return container.viewContext
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
    func deleteTransaction(id: UUID) throws { try backingStore.deleteTransaction(id: id) }
    func fetchImportedTransactionRecords(accountIDs: Set<UUID>) throws -> [ImportedTransactionRecord] {
        try backingStore.fetchImportedTransactionRecords(accountIDs: accountIDs)
    }
    func upsertImportedTransactionRecords(_ records: [ImportedTransactionRecord]) throws {
        try backingStore.upsertImportedTransactionRecords(records)
    }
    func deleteImportedTransactionRecords(accountID: UUID) throws {
        try backingStore.deleteImportedTransactionRecords(accountID: accountID)
    }
    func deleteImportedTransactionRecord(id: UUID) throws { try backingStore.deleteImportedTransactionRecord(id: id) }
    func fetchWheelOfMoneyItems() throws -> [WheelOfMoneyItem] { try backingStore.fetchWheelOfMoneyItems() }
    func fetchWheelOfMoneyItem(id: UUID) throws -> WheelOfMoneyItem? { try backingStore.fetchWheelOfMoneyItem(id: id) }
    func fetchWheelOfMoneyItems(budgetID: UUID) throws -> [WheelOfMoneyItem] {
        try backingStore.fetchWheelOfMoneyItems(budgetID: budgetID)
    }
    func upsertWheelOfMoneyItems(_ items: [WheelOfMoneyItem]) throws {
        try backingStore.upsertWheelOfMoneyItems(items)
    }
    func deleteWheelOfMoneyItem(id: UUID) throws { try backingStore.deleteWheelOfMoneyItem(id: id) }
    func deleteWheelOfMoneyItems(budgetID: UUID) throws { try backingStore.deleteWheelOfMoneyItems(budgetID: budgetID) }
}
