import Foundation
import SwiftData

enum StoreSyncMode: Equatable {
    case localOnly
    case cloudPrivate
}

struct MonthlyMoneyStorePlan: Equatable {
    let name: String
    let url: URL
    let syncMode: StoreSyncMode

    func modelConfiguration(schema: Schema) -> ModelConfiguration {
        switch syncMode {
        case .localOnly:
            return ModelConfiguration(
                name,
                schema: schema,
                url: url,
                cloudKitDatabase: .none
            )
        case .cloudPrivate:
            return ModelConfiguration(
                name,
                schema: schema,
                url: url,
                cloudKitDatabase: .automatic
            )
        }
    }
}

struct MonthlyMoneyPersistencePlan: Equatable {
    let privateStore: MonthlyMoneyStorePlan
    let sharedStore: MonthlyMoneyStorePlan

    static func defaultPlan(baseDirectory: URL = MonthlyMoneyApp.persistentStoreDirectory()) -> MonthlyMoneyPersistencePlan {
        MonthlyMoneyPersistencePlan(
            privateStore: MonthlyMoneyStorePlan(
                name: "PrivateStore",
                url: baseDirectory.appendingPathComponent("PrivateStore.store"),
                syncMode: .cloudPrivate
            ),
            sharedStore: MonthlyMoneyStorePlan(
                name: "SharedStore",
                url: baseDirectory.appendingPathComponent("SharedStore.store"),
                syncMode: .localOnly
            )
        )
    }
}

enum AppBootstrapRules {
    static func shouldWaitForInitialCloudImport(privateStoreSyncMode: StoreSyncMode, accountCount: Int) -> Bool {
        privateStoreSyncMode == .cloudPrivate && accountCount == 0
    }
}
