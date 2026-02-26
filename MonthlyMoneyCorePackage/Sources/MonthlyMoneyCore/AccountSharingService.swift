import Foundation

public enum AccountSharingError: Error, Equatable {
    case accountNotFound
    case accountAlreadyShared
    case reverseMigrationNotSupported
    case invalidMonthKey
}

public protocol AccountShareProvider {
    func createShare(for account: Account) throws
}

public struct NoOpAccountShareProvider: AccountShareProvider {
    public init() {}
    public func createShare(for account: Account) throws {}
}

public final class AccountSharingService {
    private let repository: AccountRepository
    private let shareProvider: AccountShareProvider

    public init(repository: AccountRepository, shareProvider: AccountShareProvider = NoOpAccountShareProvider()) {
        self.repository = repository
        self.shareProvider = shareProvider
    }

    @discardableResult
    public func shareAccount(accountID: UUID, participantsSelection: [String]) throws -> Account {
        if try repository.sharedAccount(id: accountID) != nil {
            throw AccountSharingError.reverseMigrationNotSupported
        }
        guard let privateAccount = try repository.privateAccount(id: accountID) else {
            throw AccountSharingError.accountNotFound
        }
        guard privateAccount.storageScope == .privateScope else {
            throw AccountSharingError.accountAlreadyShared
        }

        let dependents = try repository.privateDependents(accountID: accountID)
        let sharedAccount = Account(
            id: privateAccount.id,
            name: privateAccount.name,
            role: privateAccount.role,
            type: privateAccount.type,
            ownerParticipantID: privateAccount.ownerParticipantID,
            accessMode: participantsSelection.isEmpty ? .sharedWithAll : .sharedWithSome,
            sharedWithParticipantIDs: participantsSelection,
            storageScope: .sharedScope
        )

        let sharedPlannedItems = try dependents.plannedItems.map { item -> PlannedItem in
            guard let monthKey = YearMonth(rawValue: item.monthKey) else { throw AccountSharingError.invalidMonthKey }
            return PlannedItem(
                id: item.id,
                accountID: sharedAccount.id,
                monthKey: monthKey,
                type: item.type,
                label: item.label,
                amount: item.amount,
                dueDay: item.dueDay,
                dueText: item.dueText,
                isPaid: item.isPaid,
                notes: item.notes
            )
        }

        let sharedTransactions = try dependents.transactions.map { transaction -> Transaction in
            guard let monthKey = YearMonth(rawValue: transaction.monthKey) else { throw AccountSharingError.invalidMonthKey }
            return Transaction(
                id: transaction.id,
                accountID: sharedAccount.id,
                monthKey: monthKey,
                amount: transaction.amount,
                note: transaction.note
            )
        }

        try repository.deletePrivate(accountID: accountID)
        try repository.insertShared(account: sharedAccount, plannedItems: sharedPlannedItems, transactions: sharedTransactions)
        try shareProvider.createShare(for: sharedAccount)
        return sharedAccount
    }
}
