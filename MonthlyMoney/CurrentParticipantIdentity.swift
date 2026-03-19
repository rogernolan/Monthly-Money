import CloudKit
import Foundation

enum CurrentParticipantIdentity {
    private static let fallbackDefaultsKey = "MonthlyMoney.localParticipantID"

    static func resolve(
        containerIdentifier: String = MonthlyMoneyPersistenceFactory.cloudKitContainerIdentifier
    ) async -> String {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            return AppState.legacyOwnerParticipantID
        }

        let container = CKContainer(identifier: containerIdentifier)
        return await withCheckedContinuation { continuation in
            container.fetchUserRecordID { recordID, _ in
                if let recordName = recordID?.recordName, !recordName.isEmpty {
                    continuation.resume(returning: recordName)
                    return
                }
                continuation.resume(returning: fallbackParticipantID())
            }
        }
    }

    private static func fallbackParticipantID() -> String {
        let defaults = UserDefaults.standard
        if let existing = defaults.string(forKey: fallbackDefaultsKey), !existing.isEmpty {
            return existing
        }

        let generated = UUID().uuidString
        defaults.set(generated, forKey: fallbackDefaultsKey)
        return generated
    }
}
