import Foundation

public enum BudgetSharingError: Error, Equatable {
    case budgetNotFound
    case budgetAlreadyShared
    case reverseMigrationNotSupported
    case invalidMonthKey
}

public typealias BudgetShareHandler = (Budget) throws -> Void

public struct BudgetSharingService {
    private let repository: AccountRepository
    private let shareHandler: BudgetShareHandler

    public init(repository: AccountRepository, shareHandler: @escaping BudgetShareHandler = { _ in }) {
        self.repository = repository
        self.shareHandler = shareHandler
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
            sharingState: .shared,
            usesSeparateAccountForDailyBudget: snapshot.budget.usesSeparateAccountForDailyBudget,
            dailyBudgetAmount: snapshot.budget.dailyBudgetAmount,
            dailyBudgetPaydayDay: snapshot.budget.dailyBudgetPaydayDay,
            dailyBudgetSeparateAccountBalance: snapshot.budget.dailyBudgetSeparateAccountBalance,
            monthBalancesPayload: snapshot.budget.monthBalancesPayload
        )

        let sharedAccounts = snapshot.accounts.map { account in
            Account(
                id: account.id,
                budgetID: sharedBudget.id,
                name: account.name,
                role: account.role,
                type: account.type,
                ownerParticipantID: account.ownerParticipantID
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
                copiesToNextMonthAutomatically: item.copiesToNextMonthAutomatically,
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
        try shareHandler(sharedBudget)
        return sharedBudget
    }
}
