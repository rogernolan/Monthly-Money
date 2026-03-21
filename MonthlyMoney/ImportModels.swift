import Foundation

struct NationwideOFXStatement: Equatable {
    let accountIdentifier: String
    let currencyCode: String
    let statementStartDate: Date
    let statementEndDate: Date
    let transactions: [NationwideOFXTransaction]
}

struct NationwideOFXTransaction: Equatable {
    let externalTransactionID: String
    let postedAt: Date
    let amount: Decimal
    let payee: String
    let transactionType: String
    let rawSourcePayload: String
}

struct ImportedTransactionImportResult: Equatable {
    let parsedCount: Int
    let insertedCount: Int
    let skippedCount: Int
    let statementAccountIdentifier: String
    let statementStartDate: Date
    let statementEndDate: Date
    let insertedRecordIDs: [UUID]
}
