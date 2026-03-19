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
            matchingString: "council"
        )
        try repository.createPlannedItem(plannedItem)
        let importedRecord = makeImportedRecord(
            budgetID: account.budgetID,
            accountID: account.id,
            externalTransactionID: "FITID-1",
            postedAt: Self.date("2026-03-10T12:00:00.123Z"),
            amount: -1200,
            payee: "COUNCIL TAX DIRECT DEBIT",
            transactionType: "DIRECTDEBIT"
        )
        try repository.createImportedTransactionRecord(importedRecord)

        let service = ImportedTransactionReconciliationService(repository: repository)
        let result = try service.reconcile(account: account)

        let reconciledItem = try XCTUnwrap(try repository.plannedItems(for: YearMonth(year: 2026, month: 3)).first)
        let reconciledRecord = try XCTUnwrap(try repository.importedTransactionRecords(accountIDs: [account.id]).first)

        XCTAssertEqual(result.matchedCount, 1)
        XCTAssertTrue(reconciledItem.isPaid)
        XCTAssertEqual(reconciledItem.amount, 1200)
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
            amount: 1200
        )
        try repository.createPlannedItem(plannedItem)
        let importedRecord = makeImportedRecord(
            budgetID: account.budgetID,
            accountID: account.id,
            externalTransactionID: "FITID-2",
            postedAt: Self.date("2026-03-11T08:00:00.000Z"),
            amount: -1200,
            payee: "Council tax payment",
            transactionType: "DIRECTDEBIT"
        )
        try repository.createImportedTransactionRecord(importedRecord)

        let service = ImportedTransactionReconciliationService(repository: repository)
        let result = try service.reconcile(account: account)

        let reconciledItem = try XCTUnwrap(try repository.plannedItems(for: YearMonth(year: 2026, month: 3)).first)
        let reconciledRecord = try XCTUnwrap(try repository.importedTransactionRecords(accountIDs: [account.id]).first)

        XCTAssertEqual(result.matchedCount, 1)
        XCTAssertTrue(reconciledItem.isPaid)
        XCTAssertEqual(reconciledItem.amount, 1200)
        XCTAssertEqual(reconciledRecord.appliedPlannedItemID, reconciledItem.id)
    }

    func testReconciliationCreatesTransactionForUnmatchedImportedRowWithSourceIdentity() throws {
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

        let reconciledRecord = try XCTUnwrap(try repository.importedTransactionRecords(accountIDs: [account.id]).first)
        let createdTransactions = try repository.localBudgetSnapshot()?.transactions ?? []
        let createdTransaction = try XCTUnwrap(createdTransactions.first)

        XCTAssertEqual(result.createdCount, 1)
        XCTAssertEqual(createdTransactions.count, 1)
        XCTAssertEqual(reconciledRecord.createdTransactionID, createdTransaction.id)
        XCTAssertEqual(createdTransaction.note, "Shop Purchase")
        XCTAssertEqual(createdTransaction.sourceKind, "nationwide_ofx")
        XCTAssertEqual(createdTransaction.sourceExternalTransactionID, "FITID-3")
        XCTAssertEqual(createdTransaction.sourcePostedAt, Self.date("2026-03-12T14:15:16.789Z"))
    }

    func testReconciliationIsIdempotentAcrossRepeatedRuns() throws {
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
        let firstResult = try service.reconcile(account: account)
        let firstCreatedTransactionID = try XCTUnwrap(
            repository.importedTransactionRecords(accountIDs: [account.id]).first?.createdTransactionID
        )
        let secondResult = try service.reconcile(account: account)

        let records = try repository.importedTransactionRecords(accountIDs: [account.id])
        let createdTransactions = try repository.localBudgetSnapshot()?.transactions ?? []

        XCTAssertEqual(firstResult.createdCount, 1)
        XCTAssertEqual(secondResult.createdCount, 0)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(createdTransactions.count, 1)
        XCTAssertEqual(records.first?.createdTransactionID, firstCreatedTransactionID)
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
