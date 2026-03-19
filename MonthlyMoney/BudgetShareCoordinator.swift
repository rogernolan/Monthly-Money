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
    case stopShareVerificationFailed

    var errorDescription: String? {
        switch self {
        case .missingSharedBudgetRoot:
            return "Could not locate the shared budget for sharing."
        case .sharingUnavailable:
            return "Sharing is not available on this device."
        case .sharePreparationFailed:
            return "Could not prepare the CloudKit share."
        case .stopShareVerificationFailed:
            return "Could not confirm that sharing was removed."
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
        ShareMetadataConfigurator.apply(to: shareSession.share, budgetName: sharedBudget.name)
        return BudgetShareResult(sharedBudget: sharedBudget, shareSession: shareSession)
    }
}

enum ShareMetadataConfigurator {
    static let appDisplayName = "Monthly Money"
    static let itemType = "Monthly Money budget"

    static func apply(to share: CKShare, budgetName _: String) {
        share[CKShare.SystemFieldKey.title] = appDisplayName as CKRecordValue
        share[CKShare.SystemFieldKey.shareType] = itemType as CKRecordValue
        if let imageData = ShareThumbnailProvider.pngData() {
            share[CKShare.SystemFieldKey.thumbnailImageData] = imageData as CKRecordValue
        }
    }
}
