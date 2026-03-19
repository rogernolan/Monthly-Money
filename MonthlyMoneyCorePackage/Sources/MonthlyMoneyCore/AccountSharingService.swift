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

        if let privateBudget = try repository.localBudget() {
            if privateBudget.sharingState == .local {
                privateBudget.sharingState = .shared
                try repository.saveBudget(privateBudget)
            }
            try shareHandler(privateBudget)
            return privateBudget
        }

        if try repository.sharedBudget() != nil {
            throw BudgetSharingError.reverseMigrationNotSupported
        }

        throw BudgetSharingError.budgetNotFound
    }
}
