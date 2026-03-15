import CloudKit
import UIKit

enum CloudKitShareSceneConfiguration {
    static func make(for role: UISceneSession.Role) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: "MonthlyMoney", sessionRole: role)
        configuration.delegateClass = MonthlyMoneyCloudKitShareSceneDelegate.self
        return configuration
    }
}

final class MonthlyMoneyAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        CloudKitShareSceneConfiguration.make(for: connectingSceneSession.role)
    }
}

final class MonthlyMoneyCloudKitShareSceneDelegate: NSObject, UIWindowSceneDelegate {
    func windowScene(
        _ windowScene: UIWindowScene,
        userDidAcceptCloudKitShareWith cloudKitShareMetadata: CKShare.Metadata
    ) {
        Task { @MainActor in
            AcceptedCloudKitShareInbox.shared.enqueue(cloudKitShareMetadata)
        }
    }
}
