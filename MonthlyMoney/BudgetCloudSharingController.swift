import CloudKit
import SwiftUI
import UIKit

struct BudgetCloudSharingController: UIViewControllerRepresentable {
    let shareResult: BudgetShareResult
    let onDismiss: () -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UICloudSharingController {
        let controller = UICloudSharingController(
            share: shareResult.shareSession.share,
            container: CKContainer(identifier: shareResult.shareSession.containerIdentifier)
        )
        controller.delegate = context.coordinator
        controller.availablePermissions = [.allowReadWrite]
        return controller
    }

    func updateUIViewController(_ uiViewController: UICloudSharingController, context: Context) {}

    final class Coordinator: NSObject, UICloudSharingControllerDelegate {
        private let parent: BudgetCloudSharingController

        init(_ parent: BudgetCloudSharingController) {
            self.parent = parent
        }

        func itemTitle(for csc: UICloudSharingController) -> String? {
            parent.shareResult.sharedBudget.name
        }

        func cloudSharingControllerDidSaveShare(_ csc: UICloudSharingController) {
            parent.onDismiss()
        }

        func cloudSharingControllerDidStopSharing(_ csc: UICloudSharingController) {
            parent.onDismiss()
        }

        func cloudSharingController(_ csc: UICloudSharingController, failedToSaveShareWithError error: any Error) {
            parent.onError(error.localizedDescription)
        }
    }
}
