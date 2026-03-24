import Foundation

struct ImportedAccountStatement: Equatable {
    let accountIdentifier: String
    let currencyCode: String
    let statementStartDate: Date
    let statementEndDate: Date
    let ledgerBalance: Decimal?
    let transactions: [ImportedAccountTransaction]
}

struct ImportedAccountTransaction: Equatable {
    let externalTransactionID: String
    let postedAt: Date
    let amount: Decimal
    let payee: String
    let transactionType: String
    let rawSourcePayload: String
}

typealias NationwideOFXStatement = ImportedAccountStatement
typealias NationwideOFXTransaction = ImportedAccountTransaction
typealias MonzoQIFStatement = ImportedAccountStatement
typealias MonzoQIFTransaction = ImportedAccountTransaction

struct ImportedTransactionImportResult: Equatable {
    let parsedCount: Int
    let insertedCount: Int
    let skippedCount: Int
    let statementAccountIdentifier: String
    let statementStartDate: Date
    let statementEndDate: Date
    let insertedRecordIDs: [UUID]
}

struct DailyImportedStatementResult: Equatable {
    let importResult: ImportedTransactionImportResult
    let ignoredOutsideCurrentCycleCount: Int
}
