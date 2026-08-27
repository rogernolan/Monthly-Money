import Foundation
import SwiftData

@MainActor
enum MonthlyMoneyPersistenceFactory {
    nonisolated static let cloudKitContainerIdentifier = "iCloud.com.hatbat.monthlymoney"

    static func makeRepository(
        plan: MonthlyMoneyPersistencePlan,
        schema: Schema
    ) throws -> AccountRepository {
        let privateStore: AccountDataStore
        switch plan.privateStore.backend {
        case .coreData:
            privateStore = try makeCoreDataStore(for: plan.privateStore)
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
            sharedStore = try makeCoreDataStore(for: plan.sharedStore)
        }

        return AccountRepository(
            privateStore: privateStore,
            sharedStore: sharedStore,
            privateStoreSyncMode: plan.privateStore.syncMode,
            sharedStoreSyncMode: plan.sharedStore.syncMode
        )
    }

    private static func makeCoreDataStore(for plan: MonthlyMoneyStorePlan) throws -> CoreDataAccountDataStore {
        switch plan.syncMode {
        case .localOnly:
            return try CoreDataAccountDataStore.makePersistentLocal(url: plan.url)
        case .cloudPrivate:
            return try CoreDataAccountDataStore.makePersistentCloudKitPrivate(
                url: plan.url,
                containerIdentifier: cloudKitContainerIdentifier
            )
        case .cloudShared:
            return try CoreDataAccountDataStore.makePersistentCloudKitShared(
                url: plan.url,
                containerIdentifier: cloudKitContainerIdentifier
            )
        }
    }
}
