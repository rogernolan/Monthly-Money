import SwiftUI
import SwiftData

@main
struct MonthlyMoneyApp: App {
    let repository: AccountRepository

    init() {
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            repository = AccountRepository(
                privateStore: InMemoryAccountDataStore(),
                sharedStore: InMemoryAccountDataStore()
            )
            return
        }

        let schema = Schema([
            Budget.self,
            Account.self,
            PlannedItem.self,
            Transaction.self
        ])

        do {
            // CloudKit can be wired here when container identifiers are in place.
            // v1 falls back to local persisted stores for both scopes.
            let privateContainer = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration("PrivateStore", schema: schema, isStoredInMemoryOnly: false)]
            )
            let sharedContainer = try ModelContainer(
                for: schema,
                configurations: [ModelConfiguration("SharedStore", schema: schema, isStoredInMemoryOnly: false)]
            )
            repository = AccountRepository(
                privateStore: SwiftDataAccountDataStore(modelContainer: privateContainer),
                sharedStore: SwiftDataAccountDataStore(modelContainer: sharedContainer)
            )
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(repository: repository)
        }
    }
}
