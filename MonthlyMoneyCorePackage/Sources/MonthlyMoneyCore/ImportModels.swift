import Foundation

public struct NationwideOFXStatement: Equatable {
    public let accountIdentifier: String
    public let currencyCode: String
    public let statementStartDate: Date
    public let statementEndDate: Date
    public let transactions: [NationwideOFXTransaction]

    public init(
        accountIdentifier: String,
        currencyCode: String,
        statementStartDate: Date,
        statementEndDate: Date,
        transactions: [NationwideOFXTransaction]
    ) {
        self.accountIdentifier = accountIdentifier
        self.currencyCode = currencyCode
        self.statementStartDate = statementStartDate
        self.statementEndDate = statementEndDate
        self.transactions = transactions
    }
}

public struct NationwideOFXTransaction: Equatable {
    public let externalTransactionID: String
    public let postedAt: Date
    public let amount: Decimal
    public let payee: String
    public let transactionType: String
    public let rawSourcePayload: String

    public init(
        externalTransactionID: String,
        postedAt: Date,
        amount: Decimal,
        payee: String,
        transactionType: String,
        rawSourcePayload: String
    ) {
        self.externalTransactionID = externalTransactionID
        self.postedAt = postedAt
        self.amount = amount
        self.payee = payee
        self.transactionType = transactionType
        self.rawSourcePayload = rawSourcePayload
    }
}
