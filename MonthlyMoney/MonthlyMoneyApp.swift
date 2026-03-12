import SwiftUI
import SwiftData

@main
struct MonthlyMoneyApp: App {
    let repository: AccountRepository
    private static let persistentStoreNames = ["PrivateStore", "SharedStore"]

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
            repository = try Self.makePersistentRepository(schema: schema)
        } catch {
            print("Warning: Could not create ModelContainer: \(error). Deleting local stores and retrying.")
            Self.deletePersistentStores()

            do {
                repository = try Self.makePersistentRepository(schema: schema)
            } catch {
                print("Warning: Rebuilding SwiftData stores failed: \(error). Falling back to in-memory storage for this launch.")
                repository = AccountRepository(
                    privateStore: InMemoryAccountDataStore(),
                    sharedStore: InMemoryAccountDataStore()
                )
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(repository: repository)
        }
    }

    private static func makePersistentRepository(schema: Schema) throws -> AccountRepository {
        // CloudKit can be wired here when container identifiers are in place.
        // v1 falls back to local persisted stores for both scopes.
        let privateContainer = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration("PrivateStore", schema: schema, url: persistentStoreURL(named: "PrivateStore"))]
        )
        let sharedContainer = try ModelContainer(
            for: schema,
            configurations: [ModelConfiguration("SharedStore", schema: schema, url: persistentStoreURL(named: "SharedStore"))]
        )
        return AccountRepository(
            privateStore: SwiftDataAccountDataStore(modelContainer: privateContainer),
            sharedStore: SwiftDataAccountDataStore(modelContainer: sharedContainer)
        )
    }

    private static func persistentStoreURL(named name: String) -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = appSupport.appendingPathComponent("MonthlyMoney", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent("\(name).store")
    }

    private static func deletePersistentStores() {
        let fileManager = FileManager.default
        for name in persistentStoreNames {
            let url = persistentStoreURL(named: name)
            let sidecars = [url, url.appendingPathExtension("shm"), url.appendingPathExtension("wal")]
            for fileURL in sidecars where fileManager.fileExists(atPath: fileURL.path) {
                do {
                    try fileManager.removeItem(at: fileURL)
                } catch {
                    print("Warning: Failed removing store file \(fileURL.lastPathComponent): \(error)")
                }
            }
        }
    }
}
