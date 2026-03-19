import Foundation
import XCTest
@testable import MonthlyMoneyCore

final class NationwideOFXImporterTests: XCTestCase {
    func testParsesStatementMetadata() throws {
        let importer = NationwideOFXImporter()
        let fixture = try loadFixture("nationwide-sample")

        let statement = try importer.parse(data: fixture)

        XCTAssertEqual(statement.currencyCode, "GBP")
        XCTAssertEqual(statement.accountIdentifier, "****81197")
        XCTAssertEqual(statement.statementStartDate, Self.date("2025-12-01T12:00:00Z"))
        XCTAssertEqual(
            statement.statementEndDate.timeIntervalSince1970,
            Self.date("2026-02-28T11:59:59.999Z").timeIntervalSince1970,
            accuracy: 0.001
        )
    }

    func testParsesTransactionFields() throws {
        let importer = NationwideOFXImporter()
        let fixture = try loadFixture("nationwide-sample")

        let statement = try importer.parse(data: fixture)
        let transaction = try XCTUnwrap(statement.transactions.first)

        XCTAssertEqual(transaction.externalTransactionID, "00DIRECTDEBIT202512011200000000-38300ASHFORDBC")
        XCTAssertEqual(transaction.postedAt, Self.date("2025-12-01T12:00:00Z"))
        XCTAssertEqual(transaction.amount, Decimal(string: "-383.00"))
        XCTAssertEqual(transaction.payee, "ASHFORD B C")
        XCTAssertEqual(transaction.transactionType, "DIRECTDEBIT")
    }

    func testDecodesXMLEntitiesInPayees() throws {
        let importer = NationwideOFXImporter()
        let fixture = try loadFixture("nationwide-sample")

        let statement = try importer.parse(data: fixture)
        let transaction = try XCTUnwrap(statement.transactions.first { $0.externalTransactionID == "00POS202512011200000000-1171BQ1192ASHFORDGBAPPLEPAY3569" })

        XCTAssertEqual(transaction.payee, "B & Q 1192 ASHFORD GB APPLEPAY 3569")
    }

    private func loadFixture(_ name: String) throws -> Data {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let fixtureURL = testFileURL
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures")
            .appendingPathComponent("\(name).ofx")
        return try Data(contentsOf: fixtureURL)
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
