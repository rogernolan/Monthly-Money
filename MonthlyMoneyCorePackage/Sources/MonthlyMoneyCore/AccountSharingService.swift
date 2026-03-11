import Foundation

public enum BudgetSharingError: Error, Equatable {
    case budgetNotFound
    case budgetAlreadyShared
    case reverseMigrationNotSupported
    case invalidMonthKey
}

public protocol BudgetShareProvider: AnyObject {
    func createShare(for budget: Budget) throws
}

public final class NoOpBudgetShareProvider: BudgetShareProvider {
    public static let shared = NoOpBudgetShareProvider()

    private init() {}

    public func createShare(for budget: Budget) throws {}
}

public final class BudgetSharingService {
    private let repository: AccountRepository
    private let shareProvider: BudgetShareProvider

    public init(repository: AccountRepository, shareProvider: BudgetShareProvider = NoOpBudgetShareProvider.shared) {
        self.repository = repository
        self.shareProvider = shareProvider
    }

    @discardableResult
    public func shareBudget(participantsSelection: [String]) throws -> Budget {
        _ = participantsSelection

        if try repository.sharedBudget() != nil {
            throw BudgetSharingError.reverseMigrationNotSupported
        }

        guard let snapshot = try repository.localBudgetSnapshot() else {
            throw BudgetSharingError.budgetNotFound
        }

        guard snapshot.budget.sharingState == .local else {
            throw BudgetSharingError.budgetAlreadyShared
        }

        let sharedBudget = Budget(
            id: snapshot.budget.id,
            name: snapshot.budget.name,
            ownerParticipantID: snapshot.budget.ownerParticipantID,
            sharingState: .shared
        )

        let sharedAccounts = snapshot.accounts.map { account in
            Account(
                id: account.id,
                budgetID: sharedBudget.id,
                name: account.name,
                role: account.role,
                type: account.type,
                ownerParticipantID: account.ownerParticipantID,
                accessMode: account.accessMode,
                sharedWithParticipantIDs: account.sharedWithParticipantIDs,
                storageScope: .sharedScope
            )
        }

        let sharedPlannedItems = try snapshot.plannedItems.map { item -> PlannedItem in
            guard let monthKey = YearMonth(rawValue: item.monthKey) else {
                throw BudgetSharingError.invalidMonthKey
            }
            return PlannedItem(
                id: item.id,
                budgetID: sharedBudget.id,
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

        let sharedTransactions = try snapshot.transactions.map { transaction -> Transaction in
            guard let monthKey = YearMonth(rawValue: transaction.monthKey) else {
                throw BudgetSharingError.invalidMonthKey
            }
            return Transaction(
                id: transaction.id,
                budgetID: sharedBudget.id,
                accountID: transaction.accountID,
                monthKey: monthKey,
                amount: transaction.amount,
                note: transaction.note
            )
        }

        try repository.insertShared(
            budget: sharedBudget,
            accounts: sharedAccounts,
            plannedItems: sharedPlannedItems,
            transactions: sharedTransactions
        )
        try repository.deleteLocalBudget(id: snapshot.budget.id)
        try shareProvider.createShare(for: sharedBudget)
        return sharedBudget
    }
}
