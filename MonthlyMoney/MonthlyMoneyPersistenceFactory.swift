import Foundation
import SwiftData

enum MonthlyMoneyPersistenceFactory {
    nonisolated static let cloudKitContainerIdentifier = "iCloud.com.hatbat.monthlymoney"

    static func makeRepository(
        plan: MonthlyMoneyPersistencePlan,
        schema: Schema
    ) throws -> AccountRepository {
        let privateStore: AccountDataStore
        switch plan.privateStore.backend {
        case .coreData:
            privateStore = try CoreDataAccountDataStore.makePersistentCloudKitPrivate(
                url: plan.privateStore.url,
                containerIdentifier: cloudKitContainerIdentifier
            )
        case .swiftData:
            let container = try ModelContainer(
                for: schema,
                configurations: [plan.privateStore.modelConfiguration(schema: schema)]
            )
            privateStore = SwiftDataAccountDataStore(modelContainer: container)
        }

        let sharedStore: AccountDataStore
        switch plan.sharedStore.backend {
        case .swiftData:
            let container = try ModelContainer(
                for: schema,
                configurations: [plan.sharedStore.modelConfiguration(schema: schema)]
            )
            sharedStore = SwiftDataAccountDataStore(modelContainer: container)
        case .coreData:
            sharedStore = try CoreDataAccountDataStore.makePersistentCloudKitShared(
                url: plan.sharedStore.url,
                containerIdentifier: cloudKitContainerIdentifier
            )
        }

        return AccountRepository(
            privateStore: privateStore,
            sharedStore: sharedStore,
            privateStoreSyncMode: plan.privateStore.syncMode,
            sharedStoreSyncMode: plan.sharedStore.syncMode
        )
    }
}
