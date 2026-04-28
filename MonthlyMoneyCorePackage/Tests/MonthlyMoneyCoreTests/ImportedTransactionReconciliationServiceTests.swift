import Foundation
import XCTest
@testable import MonthlyMoneyCore

final class ImportedTransactionReconciliationServiceTests: XCTestCase {
    func testReconciliationMatchesPlannedItemUsingMatchingString() throws {
        let repository = makeRepository()
        let account = try makeAccount(in: repository, name: "Nationwide")
        let plannedItem = PlannedItem(
            budgetID: account.budgetID,
            accountID: account.id,
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Council tax",
            amount: 1200,
            matchingString: "council",
            dueDay: 12
        )
        try repository.createPlannedItem(plannedItem)
        let importedRecord = makeImportedRecord(
            budgetID: account.budgetID,
            accountID: account.id,
            externalTransactionID: "FITID-1",
            postedAt: Self.date("2026-03-11T12:00:00.123Z"),
            amount: -1200,
            payee: "COUNCIL TAX DIRECT DEBIT",
            transactionType: "DIRECTDEBIT"
        )
        try repository.createImportedTransactionRecord(importedRecord)

        let service = ImportedTransactionReconciliationService(repository: repository)
        let result = try service.reconcile(account: account)

        let reconciledItem = try XCTUnwrap(
            repository.plannedItems(for: YearMonth(year: 2026, month: 3)).first(where: { $0.id == plannedItem.id })
        )
        let reconciledRecord = try XCTUnwrap(
            repository.importedTransactionRecords(accountIDs: [account.id]).first(where: { $0.id == importedRecord.id })
        )

        XCTAssertEqual(result.matchedCount, 1)
        XCTAssertTrue(reconciledItem.isPaid)
        XCTAssertEqual(reconciledItem.source, plannedItem.source)
        XCTAssertEqual(reconciledItem.amount, 1200)
        XCTAssertEqual(reconciledItem.dueDay, 11)
        XCTAssertEqual(reconciledRecord.appliedPlannedItemID, reconciledItem.id)
    }

    func testReconciliationFallsBackToPlannedItemLabelWhenMatchingStringMissing() throws {
        let repository = makeRepository()
        let account = try makeAccount(in: repository, name: "Nationwide")
        let plannedItem = PlannedItem(
            budgetID: account.budgetID,
            accountID: account.id,
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Council tax",
            amount: 1200,
            dueDay: 10
        )
        try repository.createPlannedItem(plannedItem)
        let importedRecord = makeImportedRecord(
            budgetID: account.budgetID,
            accountID: account.id,
            externalTransactionID: "FITID-2",
            postedAt: Self.date("2026-03-12T08:00:00.000Z"),
            amount: -1200,
            payee: "Council tax payment",
            transactionType: "DIRECTDEBIT"
        )
        try repository.createImportedTransactionRecord(importedRecord)

        let service = ImportedTransactionReconciliationService(repository: repository)
        let result = try service.reconcile(account: account)

        let reconciledItem = try XCTUnwrap(
            repository.plannedItems(for: YearMonth(year: 2026, month: 3)).first(where: { $0.id == plannedItem.id })
        )
        let reconciledRecord = try XCTUnwrap(
            repository.importedTransactionRecords(accountIDs: [account.id]).first(where: { $0.id == importedRecord.id })
        )

        XCTAssertEqual(result.matchedCount, 1)
        XCTAssertTrue(reconciledItem.isPaid)
        XCTAssertEqual(reconciledItem.amount, 1200)
        XCTAssertEqual(reconciledRecord.appliedPlannedItemID, reconciledItem.id)
    }

    func testReconciliationCreatesImportedUnplannedPlannedItemForUnmatchedImportedRow() throws {
        let repository = makeRepository()
        let account = try makeAccount(in: repository, name: "Nationwide")
        let importedRecord = makeImportedRecord(
            budgetID: account.budgetID,
            accountID: account.id,
            externalTransactionID: "FITID-3",
            postedAt: Self.date("2026-03-12T14:15:16.789Z"),
            amount: -42.50,
            payee: "Shop Purchase",
            transactionType: "POS"
        )
        try repository.createImportedTransactionRecord(importedRecord)

        let service = ImportedTransactionReconciliationService(repository: repository)
        let result = try service.reconcile(account: account)

        let reconciledRecord = try XCTUnwrap(
            repository.importedTransactionRecords(accountIDs: [account.id]).first(where: { $0.id == importedRecord.id })
        )
        let createdTransactions = try repository.localBudgetSnapshot()?.transactions ?? []
        let plannedItems = try repository.plannedItems(for: YearMonth(year: 2026, month: 3))
        let createdPlannedItem = try XCTUnwrap(plannedItems.first(where: { $0.source == .importedUnplanned }))

        XCTAssertEqual(result.createdCount, 1)
        XCTAssertEqual(createdTransactions.count, 0)
        XCTAssertEqual(plannedItems.count, 1)
        XCTAssertEqual(createdPlannedItem.monthKey, YearMonth(year: 2026, month: 3).rawValue)
        XCTAssertEqual(createdPlannedItem.label, importedRecord.payee)
        XCTAssertEqual(createdPlannedItem.matchingString, importedRecord.payee)
        XCTAssertEqual(createdPlannedItem.amount, Decimal(string: "42.50"))
        XCTAssertEqual(createdPlannedItem.type, .fixedDebit)
        XCTAssertTrue(createdPlannedItem.isPaid)
        XCTAssertEqual(createdPlannedItem.source, .importedUnplanned)
        XCTAssertEqual(createdPlannedItem.dueDay, 12)
        XCTAssertFalse(createdPlannedItem.copiesToNextMonthAutomatically)
        XCTAssertEqual(reconciledRecord.appliedPlannedItemID, createdPlannedItem.id)
        XCTAssertNil(reconciledRecord.createdTransactionID)
    }

    func testReconciliationCreatesImportedUnplannedItemInNextBudgetMonthOnPayday() throws {
        let repository = makeRepository()
        let account = try makeAccount(in: repository, name: "Nationwide")
        let budget = try XCTUnwrap(try repository.activeBudget())
        budget.dailyBudgetPaydayDay = 28
        try repository.saveBudget(budget)
        let importedRecord = makeImportedRecord(
            budgetID: account.budgetID,
            accountID: account.id,
            externalTransactionID: "FITID-PAYDAY",
            postedAt: Self.date("2026-04-28T12:00:00.000Z"),
            amount: -12.34,
            payee: "Card Payment",
            transactionType: "POS"
        )
        try repository.createImportedTransactionRecord(importedRecord)

        _ = try ImportedTransactionReconciliationService(repository: repository).reconcile(account: account)

        XCTAssertTrue(try repository.plannedItems(for: YearMonth(year: 2026, month: 4)).isEmpty)
        XCTAssertEqual(
            try repository.plannedItems(for: YearMonth(year: 2026, month: 5)).map(\.label),
            ["Card Payment"]
        )
    }

    func testReconciliationDoesNotDuplicateImportedUnplannedItemsAcrossRepeatedRuns() throws {
        let repository = makeRepository()
        let account = try makeAccount(in: repository, name: "Nationwide")
        let importedRecord = makeImportedRecord(
            budgetID: account.budgetID,
            accountID: account.id,
            externalTransactionID: "FITID-4",
            postedAt: Self.date("2026-03-13T09:00:00.500Z"),
            amount: -18.75,
            payee: "Corner Shop",
            transactionType: "POS"
        )
        try repository.createImportedTransactionRecord(importedRecord)

        let service = ImportedTransactionReconciliationService(repository: repository)
        _ = try service.reconcile(account: account)
        _ = try service.reconcile(account: account)

        let records = try repository.importedTransactionRecords(accountIDs: [account.id])
        let plannedItems = try repository.plannedItems(for: YearMonth(year: 2026, month: 3))
        let importedUnplannedItems = plannedItems.filter { $0.source == .importedUnplanned }

        XCTAssertEqual(importedUnplannedItems.count, 1)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.appliedPlannedItemID, importedUnplannedItems.first?.id)
    }

    func testReconciliationReappliesLinkedImportedUnplannedItemWhenUntickedAndReimported() throws {
        let repository = makeRepository()
        let account = try makeAccount(in: repository, name: "Nationwide")
        let importedRecord = makeImportedRecord(
            budgetID: account.budgetID,
            accountID: account.id,
            externalTransactionID: "FITID-5",
            postedAt: Self.date("2026-03-16T09:30:00.000Z"),
            amount: -31.25,
            payee: "Coffee Shop",
            transactionType: "POS"
        )
        try repository.createImportedTransactionRecord(importedRecord)

        let service = ImportedTransactionReconciliationService(repository: repository)
        _ = try service.reconcile(account: account)

        let createdPlannedItem = try XCTUnwrap(
            repository.plannedItems(for: YearMonth(year: 2026, month: 3)).first(where: { $0.source == .importedUnplanned })
        )
        createdPlannedItem.isPaid = false
        try repository.savePlannedItem(createdPlannedItem)

        let result = try service.reconcile(account: account)

        let refreshedItem = try XCTUnwrap(
            repository.plannedItems(for: YearMonth(year: 2026, month: 3)).first(where: { $0.id == createdPlannedItem.id })
        )
        let refreshedRecord = try XCTUnwrap(
            repository.importedTransactionRecords(accountIDs: [account.id]).first(where: { $0.id == importedRecord.id })
        )

        XCTAssertEqual(result.matchedCount, 1)
        XCTAssertEqual(result.createdCount, 0)
        XCTAssertTrue(refreshedItem.isPaid)
        XCTAssertEqual(refreshedItem.dueDay, 16)
        XCTAssertEqual(refreshedRecord.appliedPlannedItemID, refreshedItem.id)
        XCTAssertEqual(
            try repository.plannedItems(for: YearMonth(year: 2026, month: 3)).filter { $0.source == .importedUnplanned }.count,
            1
        )
    }

    func testReconciliationDoesNotMatchPlannedItemWhenAmountIsOutsideTolerance() throws {
        let repository = makeRepository()
        let account = try makeAccount(in: repository, name: "Nationwide")
        let plannedItem = PlannedItem(
            budgetID: account.budgetID,
            accountID: account.id,
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Mall",
            amount: 100,
            matchingString: "mall",
            dueDay: 12
        )
        try repository.createPlannedItem(plannedItem)
        let importedRecord = makeImportedRecord(
            budgetID: account.budgetID,
            accountID: account.id,
            externalTransactionID: "FITID-6",
            postedAt: Self.date("2026-03-12T10:00:00.000Z"),
            amount: -130,
            payee: "MALL purchase",
            transactionType: "POS"
        )
        try repository.createImportedTransactionRecord(importedRecord)

        let result = try ImportedTransactionReconciliationService(repository: repository).reconcile(account: account)

        let refreshedPlannedItem = try XCTUnwrap(
            repository.plannedItems(for: YearMonth(year: 2026, month: 3)).first(where: { $0.id == plannedItem.id })
        )
        let importedUnplannedItems = try repository.plannedItems(for: YearMonth(year: 2026, month: 3))
            .filter { $0.source == .importedUnplanned }

        XCTAssertEqual(result.matchedCount, 0)
        XCTAssertEqual(result.createdCount, 1)
        XCTAssertFalse(refreshedPlannedItem.isPaid)
        XCTAssertEqual(importedUnplannedItems.count, 1)
    }

    func testReconciliationDoesNotMatchPlannedItemWhenDateIsOutsideTolerance() throws {
        let repository = makeRepository()
        let account = try makeAccount(in: repository, name: "Nationwide")
        let plannedItem = PlannedItem(
            budgetID: account.budgetID,
            accountID: account.id,
            monthKey: YearMonth(year: 2026, month: 3),
            type: .fixedDebit,
            label: "Train ticket",
            amount: 25,
            matchingString: "train",
            dueDay: 10
        )
        try repository.createPlannedItem(plannedItem)
        let importedRecord = makeImportedRecord(
            budgetID: account.budgetID,
            accountID: account.id,
            externalTransactionID: "FITID-7",
            postedAt: Self.date("2026-03-16T10:00:00.000Z"),
            amount: -25,
            payee: "TRAIN fare",
            transactionType: "POS"
        )
        try repository.createImportedTransactionRecord(importedRecord)

        let result = try ImportedTransactionReconciliationService(repository: repository).reconcile(account: account)

        let refreshedPlannedItem = try XCTUnwrap(
            repository.plannedItems(for: YearMonth(year: 2026, month: 3)).first(where: { $0.id == plannedItem.id })
        )
        let importedUnplannedItems = try repository.plannedItems(for: YearMonth(year: 2026, month: 3))
            .filter { $0.source == .importedUnplanned }

        XCTAssertEqual(result.matchedCount, 0)
        XCTAssertEqual(result.createdCount, 1)
        XCTAssertFalse(refreshedPlannedItem.isPaid)
        XCTAssertEqual(importedUnplannedItems.count, 1)
    }

    func testReconciliationCanBeLimitedToSpecificImportedRecords() throws {
        let repository = makeRepository()
        let account = try makeAccount(in: repository, name: "Nationwide")
        let olderImportedRecord = makeImportedRecord(
            budgetID: account.budgetID,
            accountID: account.id,
            externalTransactionID: "FITID-older",
            postedAt: Self.date("2026-03-14T08:00:00.000Z"),
            amount: -42,
            payee: "Older Unapplied Import",
            transactionType: "DIRECTDEBIT"
        )
        let newlyImportedRecord = makeImportedRecord(
            budgetID: account.budgetID,
            accountID: account.id,
            externalTransactionID: "FITID-new",
            postedAt: Self.date("2026-03-15T08:00:00.000Z"),
            amount: -84,
            payee: "Newly Imported Record",
            transactionType: "DIRECTDEBIT"
        )
        try repository.createImportedTransactionRecord(olderImportedRecord)
        try repository.createImportedTransactionRecord(newlyImportedRecord)

        let result = try ImportedTransactionReconciliationService(repository: repository).reconcile(
            account: account,
            importedRecordIDs: [newlyImportedRecord.id]
        )

        let records = try repository.importedTransactionRecords(accountIDs: [account.id])
        let refreshedOlderRecord = try XCTUnwrap(records.first(where: { $0.id == olderImportedRecord.id }))
        let refreshedNewRecord = try XCTUnwrap(records.first(where: { $0.id == newlyImportedRecord.id }))
        let plannedItems = try repository.plannedItems(for: YearMonth(year: 2026, month: 3))
        let importedUnplannedItem = try XCTUnwrap(plannedItems.first(where: { $0.source == .importedUnplanned }))

        XCTAssertEqual(result.createdCount, 1)
        XCTAssertEqual(result.matchedCount, 0)
        XCTAssertNil(refreshedOlderRecord.appliedPlannedItemID)
        XCTAssertNil(refreshedOlderRecord.createdTransactionID)
        XCTAssertNotNil(refreshedNewRecord.appliedPlannedItemID)
        XCTAssertNil(refreshedNewRecord.createdTransactionID)
        XCTAssertEqual(plannedItems.count, 1)
        XCTAssertEqual(importedUnplannedItem.label, newlyImportedRecord.payee)
        XCTAssertEqual(importedUnplannedItem.amount, Decimal(string: "84"))
        XCTAssertEqual(importedUnplannedItem.type, .fixedDebit)
        XCTAssertTrue(importedUnplannedItem.isPaid)
        XCTAssertEqual(importedUnplannedItem.monthKey, YearMonth(year: 2026, month: 3).rawValue)
        XCTAssertEqual(importedUnplannedItem.source, .importedUnplanned)
        XCTAssertFalse(importedUnplannedItem.copiesToNextMonthAutomatically)
        XCTAssertEqual(refreshedNewRecord.appliedPlannedItemID, importedUnplannedItem.id)
        XCTAssertEqual(try repository.localBudgetSnapshot()?.transactions.count ?? 0, 0)
    }

    private func makeRepository() -> AccountRepository {
        AccountRepository(
            privateStore: InMemoryAccountDataStore(),
            sharedStore: InMemoryAccountDataStore()
        )
    }

    private func makeAccount(in repository: AccountRepository, name: String) throws -> Account {
        try repository.createAccount(
            name: name,
            role: .regular,
            type: .current,
            ownerParticipantID: "owner"
        )
    }

    private func makeImportedRecord(
        budgetID: UUID,
        accountID: UUID,
        externalTransactionID: String,
        postedAt: Date,
        amount: Decimal,
        payee: String,
        transactionType: String
    ) -> ImportedTransactionRecord {
        ImportedTransactionRecord(
            budgetID: budgetID,
            accountID: accountID,
            sourceKind: "nationwide_ofx",
            sourceAccountIdentifier: "****81197",
            externalTransactionID: externalTransactionID,
            postedAt: postedAt,
            amount: amount,
            payee: payee,
            transactionType: transactionType,
            rawSourcePayload: "{\"fitid\":\"\(externalTransactionID)\"}"
        )
    }

    private static func date(_ iso8601: String) -> Date {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: iso8601) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        guard let date = formatter.date(from: iso8601) else {
            preconditionFailure("Invalid ISO-8601 literal in test: \(iso8601)")
        }
        return date
    }
}
