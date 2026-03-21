import Foundation

public struct ImportedTransactionImportResult: Equatable {
    public let parsedCount: Int
    public let insertedCount: Int
    public let skippedCount: Int
    public let statementAccountIdentifier: String
    public let statementStartDate: Date
    public let statementEndDate: Date
    public let insertedRecordIDs: [UUID]

    public init(
        parsedCount: Int,
        insertedCount: Int,
        skippedCount: Int,
        statementAccountIdentifier: String,
        statementStartDate: Date,
        statementEndDate: Date,
        insertedRecordIDs: [UUID] = []
    ) {
        self.parsedCount = parsedCount
        self.insertedCount = insertedCount
        self.skippedCount = skippedCount
        self.statementAccountIdentifier = statementAccountIdentifier
        self.statementStartDate = statementStartDate
        self.statementEndDate = statementEndDate
        self.insertedRecordIDs = insertedRecordIDs
    }
}

public final class ImportedTransactionService {
    public static let nationwideOFXSourceKind = "nationwide_ofx"

    private let repository: AccountRepository
    private let dateProvider: () -> Date

    public init(
        repository: AccountRepository,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.dateProvider = dateProvider
    }

    @discardableResult
    public func `import`(
        statement: NationwideOFXStatement,
        into account: Account
    ) throws -> ImportedTransactionImportResult {
        let existingRecords = try repository.importedTransactionRecords(accountIDs: [account.id])
        let existingIdentityKeys = Set(
            existingRecords.map { Self.identityKey(sourceKind: $0.sourceKind, externalTransactionID: $0.externalTransactionID) }
        )

        var unseenRecords: [ImportedTransactionRecord] = []
        var seenIdentityKeys = existingIdentityKeys
        var skippedCount = 0

        for transaction in statement.transactions {
            let identityKey = Self.identityKey(
                sourceKind: Self.nationwideOFXSourceKind,
                externalTransactionID: transaction.externalTransactionID
            )
            if seenIdentityKeys.contains(identityKey) {
                skippedCount += 1
                continue
            }

            seenIdentityKeys.insert(identityKey)
            unseenRecords.append(
                ImportedTransactionRecord(
                    budgetID: account.budgetID,
                    accountID: account.id,
                    sourceKind: Self.nationwideOFXSourceKind,
                    sourceAccountIdentifier: statement.accountIdentifier,
                    externalTransactionID: transaction.externalTransactionID,
                    postedAt: transaction.postedAt,
                    amount: transaction.amount,
                    payee: transaction.payee,
                    transactionType: transaction.transactionType,
                    rawSourcePayload: transaction.rawSourcePayload,
                    importedAt: dateProvider()
                )
            )
        }

        for record in unseenRecords {
            try repository.createImportedTransactionRecord(record)
        }

        return ImportedTransactionImportResult(
            parsedCount: statement.transactions.count,
            insertedCount: unseenRecords.count,
            skippedCount: skippedCount,
            statementAccountIdentifier: statement.accountIdentifier,
            statementStartDate: statement.statementStartDate,
            statementEndDate: statement.statementEndDate,
            insertedRecordIDs: unseenRecords.map(\.id)
        )
    }

    private static func identityKey(sourceKind: String, externalTransactionID: String) -> String {
        "\(sourceKind)::\(externalTransactionID)"
    }
}
