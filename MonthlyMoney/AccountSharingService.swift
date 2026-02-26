import Foundation

enum AccountSharingError: Error, Equatable {
    case accountNotFound
    case accountAlreadyShared
    case reverseMigrationNotSupported
    case invalidMonthKey
}

protocol AccountShareProvider {
    func createShare(for account: Account) throws
}

struct NoOpAccountShareProvider: AccountShareProvider {
    func createShare(for account: Account) throws {
        // CKShare wiring hook. Intentionally left as no-op for v1 scaffolding.
    }
}

final class AccountSharingService {
    private let repository: AccountRepository
    private let shareProvider: AccountShareProvider

    init(repository: AccountRepository, shareProvider: AccountShareProvider = NoOpAccountShareProvider()) {
        self.repository = repository
        self.shareProvider = shareProvider
    }

    @discardableResult
    func shareAccount(accountID: UUID, participantsSelection: [String]) throws -> Account {
        if try repository.sharedAccount(id: accountID) != nil {
            throw AccountSharingError.reverseMigrationNotSupported
        }

        let accountSnapshot: (id: UUID, name: String, role: AccountRole, type: AccountType, ownerParticipantID: String)
        let plannedSnapshots: [(id: UUID, accountID: UUID, monthKey: YearMonth, type: PlannedItemType, label: String, amount: Decimal, dueDay: Int?, dueText: String?, isPaid: Bool, notes: String)]
        let transactionSnapshots: [(id: UUID, accountID: UUID, monthKey: YearMonth, amount: Decimal, note: String)]

        do {
            guard let privateAccount = try repository.privateAccount(id: accountID) else {
                throw AccountSharingError.accountNotFound
            }

            guard privateAccount.storageScope == .privateScope else {
                throw AccountSharingError.accountAlreadyShared
            }

            accountSnapshot = (
                id: privateAccount.id,
                name: privateAccount.name,
                role: privateAccount.role,
                type: privateAccount.type,
                ownerParticipantID: privateAccount.ownerParticipantID
            )

            let dependents = try repository.privateDependents(accountID: accountID)
            plannedSnapshots = try dependents.plannedItems.map { item in
                guard let monthKey = YearMonth(rawValue: item.monthKey) else {
                    throw AccountSharingError.invalidMonthKey
                }
                return (
                    id: item.id,
                    accountID: item.accountID,
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
            transactionSnapshots = try dependents.transactions.map { transaction in
                guard let monthKey = YearMonth(rawValue: transaction.monthKey) else {
                    throw AccountSharingError.invalidMonthKey
                }
                return (
                    id: transaction.id,
                    accountID: transaction.accountID,
                    monthKey: monthKey,
                    amount: transaction.amount,
                    note: transaction.note
                )
            }
        }

        let accessMode: AccountAccessMode = participantsSelection.isEmpty ? .sharedWithAll : .sharedWithSome
        let migratedAccountID = UUID()
        let sharedAccount = Account(
            id: migratedAccountID,
            name: accountSnapshot.name,
            role: accountSnapshot.role,
            type: accountSnapshot.type,
            ownerParticipantID: accountSnapshot.ownerParticipantID,
            accessMode: accessMode,
            sharedWithParticipantIDs: participantsSelection,
            storageScope: .sharedScope
        )

        try repository.deletePrivate(accountID: accountID)

        let sharedPlannedItems = plannedSnapshots.map { snapshot in
            PlannedItem(
                id: snapshot.id,
                accountID: migratedAccountID,
                monthKey: snapshot.monthKey,
                type: snapshot.type,
                label: snapshot.label,
                amount: snapshot.amount,
                dueDay: snapshot.dueDay,
                dueText: snapshot.dueText,
                isPaid: snapshot.isPaid,
                notes: snapshot.notes
            )
        }

        let sharedTransactions = transactionSnapshots.map { snapshot in
            Transaction(
                id: snapshot.id,
                accountID: migratedAccountID,
                monthKey: snapshot.monthKey,
                amount: snapshot.amount,
                note: snapshot.note
            )
        }

        try repository.insertShared(account: sharedAccount, plannedItems: sharedPlannedItems, transactions: sharedTransactions)
        try shareProvider.createShare(for: sharedAccount)

        return sharedAccount
    }
}
