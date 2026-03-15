import CloudKit
import Combine
import Foundation

@MainActor
final class AcceptedCloudKitShareInbox: ObservableObject {
    static let shared = AcceptedCloudKitShareInbox()

    @Published private(set) var pendingMetadata: [CKShare.Metadata] = []

    private init() {}

    func enqueue(_ metadata: CKShare.Metadata) {
        pendingMetadata.append(metadata)
    }

    func drainPendingMetadata() -> [CKShare.Metadata] {
        let metadata = pendingMetadata
        pendingMetadata.removeAll()
        return metadata
    }
}
