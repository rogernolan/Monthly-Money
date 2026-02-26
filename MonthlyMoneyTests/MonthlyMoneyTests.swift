import XCTest
import SwiftData
@testable import MonthlyMoney

@MainActor
final class MonthlyMoneyTests: XCTestCase {
    override func setUpWithError() throws {
        print("TEST START: \(name) @ \(Date())")
    }

    override func tearDownWithError() throws {
        print("TEST END: \(name) @ \(Date())")
    }

    func testNewAccountsDefaultToOwnerOnlyAndPrivate() throws {
        let repository = try makeRepository()

        let accountID = try repository.createAccount(
            name: "Checking",
            role: .regular,
            type: .current,
            ownerParticipantID: "owner"
        ).id
        let account = try XCTUnwrap(repository.privateAccount(id: accountID))
        XCTAssertEqual(account.accessMode, .ownerOnly)
        XCTAssertEqual(account.storageScope, .privateScope)

        let myViewIDs = try repository.accountIDs(for: .myView)
        XCTAssertEqual(myViewIDs, [accountID])
    }

    func testShareAccountMovesAccountAndDependentsToSharedStoreAndPreservesTotals() throws {
        let repository = try makeRepository()
        let accountID = try repository.createAccount(
            name: "Bills",
            role: .regular,
            type: .current,
            ownerParticipantID: "owner"
        ).id

        let month = YearMonth(year: 2026, month: 2)
        try repository.createPlannedItem(
            PlannedItem(accountID: accountID, monthKey: month, type: .fixedDebit, label: "Rent", amount: 1200, isPaid: false),
            in: .privateScope
        )
        try repository.createPlannedItem(
            PlannedItem(accountID: accountID, monthKey: month, type: .credit, label: "Salary", amount: 2200, isPaid: false),
            in: .privateScope
        )
        try repository.createPlannedItem(
            PlannedItem(accountID: accountID, monthKey: month, type: .transfer, label: "Living transfer", amount: 300, isPaid: false),
            in: .privateScope
        )

        let beforeItems = try repository.plannedItems(for: month, scope: .myView)
        let beforeTotals = MonthCalculationEngine.calculate(
            items: beforeItems,
            openingBalance: 1000,
            livingBuffer: 200,
            weeklyEstimate: 150,
            weekendEstimate: 25,
            minSuggestedLiving: 100,
            yearMonth: month
        )

        let service = AccountSharingService(repository: repository)
        let sharedAccount = try service.shareAccount(accountID: accountID, participantsSelection: ["p2"])

        XCTAssertEqual(sharedAccount.storageScope, .sharedScope)
        XCTAssertEqual(sharedAccount.accessMode, .sharedWithSome)
        XCTAssertEqual(sharedAccount.sharedWithParticipantIDs, ["p2"])

        XCTAssertNil(try repository.privateAccount(id: accountID))
        XCTAssertNil(try repository.sharedAccount(id: accountID))
        XCTAssertNotNil(try repository.sharedAccount(id: sharedAccount.id))

        let privateDependents = try repository.privateDependents(accountID: accountID)
        XCTAssertTrue(privateDependents.plannedItems.isEmpty)
        XCTAssertTrue(privateDependents.transactions.isEmpty)

        let afterItems = try repository.plannedItems(for: month, scope: .myView)
        let afterTotals = MonthCalculationEngine.calculate(
            items: afterItems,
            openingBalance: 1000,
            livingBuffer: 200,
            weeklyEstimate: 150,
            weekendEstimate: 25,
            minSuggestedLiving: 100,
            yearMonth: month
        )

        XCTAssertEqual(beforeTotals, afterTotals)
    }

    func testSharedViewExcludesPrivateAccounts() throws {
        let repository = try makeRepository()

        let privateOnlyID = try repository.createAccount(
            name: "Private",
            role: .regular,
            type: .current,
            ownerParticipantID: "owner"
        ).id
        let toShareID = try repository.createAccount(
            name: "Shared",
            role: .regular,
            type: .current,
            ownerParticipantID: "owner"
        ).id

        let service = AccountSharingService(repository: repository)
        let sharedAccount = try service.shareAccount(accountID: toShareID, participantsSelection: [])

        let sharedIDs = try repository.accountIDs(for: .sharedView)

        XCTAssertEqual(sharedIDs, [sharedAccount.id])
        XCTAssertFalse(sharedIDs.contains(privateOnlyID))
    }

    func testMyViewIncludesPrivateAndSharedAccounts() throws {
        print("STEP 1: makeRepository")
        let repository = try makeRepository()

        print("STEP 2: create private account")
        let privateOnlyID = try repository.createAccount(
            name: "Private",
            role: .regular,
            type: .current,
            ownerParticipantID: "owner"
        ).id
        print("STEP 2 done: \(privateOnlyID)")
        print("STEP 3: create account to share")
        let toShareID = try repository.createAccount(
            name: "Shared",
            role: .regular,
            type: .current,
            ownerParticipantID: "owner"
        ).id
        print("STEP 3 done: \(toShareID)")

        print("STEP 4: share account")
        let service = AccountSharingService(repository: repository)
        let sharedAccount = try service.shareAccount(accountID: toShareID, participantsSelection: ["p2"])
        print("STEP 4 done")

        print("STEP 5: fetch my view accounts")
        let myViewIDs = try repository.accountIDs(for: .myView)
        print("STEP 5 done: count=\(myViewIDs.count)")

        XCTAssertEqual(myViewIDs, [privateOnlyID, sharedAccount.id])
    }

    func testSharedScopeCannotReferencePrivateAccount() throws {
        let repository = try makeRepository()
        let privateAccountID = try repository.createAccount(
            name: "Private",
            role: .regular,
            type: .current,
            ownerParticipantID: "owner"
        ).id

        let month = YearMonth(year: 2026, month: 3)
        XCTAssertThrowsError(
            try repository.createPlannedItem(
                PlannedItem(accountID: privateAccountID, monthKey: month, type: .fixedDebit, label: "Bad", amount: 10),
                in: .sharedScope
            )
        ) { error in
            XCTAssertEqual(error as? RepositoryError, .invalidCrossScopeReference)
        }
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

    private func makeRepository() throws -> AccountRepository {
        let schema = Schema([Account.self, PlannedItem.self, Transaction.self])
        let privateContainer = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration("TestPrivateStore", schema: schema, isStoredInMemoryOnly: true)]
        )
        let sharedContainer = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration("TestSharedStore", schema: schema, isStoredInMemoryOnly: true)]
        )

        return AccountRepository(
            privateStore: SwiftDataAccountDataStore(scope: .privateScope, modelContainer: privateContainer),
            sharedStore: SwiftDataAccountDataStore(scope: .sharedScope, modelContainer: sharedContainer)
        )
    }
}
