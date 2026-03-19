import Foundation
import XCTest
@testable import MonthlyMoneyCore

final class ImportedTransactionServiceTests: XCTestCase {
    func testReimportingSameStatementIntoSameAccountSkipsDuplicateFITIDs() throws {
        let repository = makeRepository()
        let account = try makeAccount(in: repository, name: "Nationwide")
        let service = ImportedTransactionService(repository: repository)
        let statement = makeStatement(
            accountIdentifier: "****81197",
            transactions: [
                makeTransaction(fitid: "FITID-1", amount: -12.34, payee: "Coffee Shop"),
                makeTransaction(fitid: "FITID-2", amount: -45.67, payee: "Groceries")
            ]
        )

        let firstImport = try service.import(statement: statement, into: account)
        let secondImport = try service.import(statement: statement, into: account)

        XCTAssertEqual(firstImport.insertedCount, 2)
        XCTAssertEqual(firstImport.skippedCount, 0)
        XCTAssertEqual(secondImport.insertedCount, 0)
        XCTAssertEqual(secondImport.skippedCount, 2)
        XCTAssertEqual(
            try repository.importedTransactionRecords(accountIDs: [account.id]).map(\.externalTransactionID),
            ["FITID-1", "FITID-2"]
        )
    }

    func testOverlappingStatementsOnlyInsertNewFITIDs() throws {
        let repository = makeRepository()
        let account = try makeAccount(in: repository, name: "Nationwide")
        let service = ImportedTransactionService(repository: repository)
        let firstStatement = makeStatement(
            accountIdentifier: "****81197",
            transactions: [
                makeTransaction(fitid: "FITID-1", amount: -12.34, payee: "Coffee Shop"),
                makeTransaction(fitid: "FITID-2", amount: -45.67, payee: "Groceries")
            ]
        )
        let overlappingStatement = makeStatement(
            accountIdentifier: "****81197",
            transactions: [
                makeTransaction(fitid: "FITID-2", amount: -45.67, payee: "Groceries"),
                makeTransaction(fitid: "FITID-3", amount: -18.00, payee: "Pharmacy")
            ]
        )

        let firstImport = try service.import(statement: firstStatement, into: account)
        let secondImport = try service.import(statement: overlappingStatement, into: account)

        XCTAssertEqual(firstImport.insertedCount, 2)
        XCTAssertEqual(secondImport.insertedCount, 1)
        XCTAssertEqual(secondImport.skippedCount, 1)
        XCTAssertEqual(
            try repository.importedTransactionRecords(accountIDs: [account.id]).map(\.externalTransactionID),
            ["FITID-1", "FITID-2", "FITID-3"]
        )
    }

    func testSameFITIDCanExistInDifferentAccounts() throws {
        let repository = makeRepository()
        let firstAccount = try makeAccount(in: repository, name: "Nationwide 1")
        let secondAccount = try makeAccount(in: repository, name: "Nationwide 2")
        let service = ImportedTransactionService(repository: repository)
        let statement = makeStatement(
            accountIdentifier: "****81197",
            transactions: [
                makeTransaction(fitid: "FITID-SHARED", amount: -12.34, payee: "Shared Merchant")
            ]
        )

        let firstImport = try service.import(statement: statement, into: firstAccount)
        let secondImport = try service.import(statement: statement, into: secondAccount)

        XCTAssertEqual(firstImport.insertedCount, 1)
        XCTAssertEqual(secondImport.insertedCount, 1)
        XCTAssertEqual(
            try repository.importedTransactionRecords(accountIDs: [firstAccount.id]).map(\.externalTransactionID),
            ["FITID-SHARED"]
        )
        XCTAssertEqual(
            try repository.importedTransactionRecords(accountIDs: [secondAccount.id]).map(\.externalTransactionID),
            ["FITID-SHARED"]
        )
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

    private func makeStatement(accountIdentifier: String, transactions: [NationwideOFXTransaction]) -> NationwideOFXStatement {
        NationwideOFXStatement(
            accountIdentifier: accountIdentifier,
            currencyCode: "GBP",
            statementStartDate: Self.date("2026-03-01T00:00:00Z"),
            statementEndDate: Self.date("2026-03-31T23:59:59Z"),
            transactions: transactions
        )
    }

    private func makeTransaction(fitid: String, amount: Decimal, payee: String) -> NationwideOFXTransaction {
        NationwideOFXTransaction(
            externalTransactionID: fitid,
            postedAt: Self.date("2026-03-10T12:00:00Z"),
            amount: amount,
            payee: payee,
            transactionType: "POS",
            rawSourcePayload: "{\"fitid\":\"\(fitid)\"}"
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
