import CloudKit
import Foundation

struct BudgetShareSession {
    let budgetID: UUID
    let share: CKShare
    let containerIdentifier: String
}

struct BudgetShareResult {
    let sharedBudget: Budget
    let shareSession: BudgetShareSession
}

extension BudgetShareResult: Identifiable {
    var id: UUID { sharedBudget.id }
}

enum BudgetShareCoordinatorError: LocalizedError, Equatable {
    case missingSharedBudgetRoot
    case sharingUnavailable
    case sharePreparationFailed

    var errorDescription: String? {
        switch self {
        case .missingSharedBudgetRoot:
            return "Could not locate the shared budget for sharing."
        case .sharingUnavailable:
            return "Sharing is not available on this device."
        case .sharePreparationFailed:
            return "Could not prepare the CloudKit share."
        }
    }
}

struct BudgetShareCoordinator {
    private let repository: AccountRepository

    init(repository: AccountRepository) {
        self.repository = repository
    }

    func prepareShareResult(for sharedBudget: Budget) async throws -> BudgetShareResult {
        let shareSession = try await repository.prepareShareSession(forSharedBudgetID: sharedBudget.id)
        return BudgetShareResult(sharedBudget: sharedBudget, shareSession: shareSession)
    }
}
