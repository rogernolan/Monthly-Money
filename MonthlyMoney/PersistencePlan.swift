import Foundation
import SwiftData

enum StoreSyncMode: Equatable {
    case localOnly
    case cloudPrivate
    case cloudShared
}

enum StoreBackend: Equatable {
    case swiftData
    case coreData
}

struct MonthlyMoneyStorePlan: Equatable {
    let name: String
    let url: URL
    let syncMode: StoreSyncMode
    let backend: StoreBackend

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
        case .cloudShared:
            return ModelConfiguration(
                name,
                schema: schema,
                url: url,
                cloudKitDatabase: .none
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
                syncMode: .cloudPrivate,
                backend: .coreData
            ),
            sharedStore: MonthlyMoneyStorePlan(
                name: "SharedStore",
                url: baseDirectory.appendingPathComponent("SharedStore.store"),
                syncMode: .cloudShared,
                backend: .coreData
            )
        )
    }
}

enum AppBootstrapRules {
    static func shouldWaitForInitialCloudImport(privateStoreSyncMode: StoreSyncMode, accountCount: Int) -> Bool {
        privateStoreSyncMode == .cloudPrivate && accountCount == 0
    }
}
