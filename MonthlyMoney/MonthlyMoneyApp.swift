import SwiftUI
import SwiftData

@main
struct MonthlyMoneyApp: App {
    @UIApplicationDelegateAdaptor(MonthlyMoneyAppDelegate.self) private var appDelegate
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
            Transaction.self,
            WheelOfMoneyItem.self
        ])

        do {
            repository = try Self.makePersistentRepository(schema: schema)
        } catch {
            Self.logPersistenceError("Could not create persistent stores", error: error)
            print("Warning: Deleting local stores and retrying.")
            Self.deletePersistentStores()

            do {
                repository = try Self.makePersistentRepository(schema: schema)
            } catch {
                Self.logPersistenceError("Rebuilding persistent stores failed", error: error)
                print("Warning: Falling back to in-memory storage for this launch.")
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
        let plan = MonthlyMoneyPersistencePlan.defaultPlan()
        return try MonthlyMoneyPersistenceFactory.makeRepository(plan: plan, schema: schema)
    }

    static func persistentStoreDirectory() -> URL {
        let fileManager = FileManager.default
        let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = appSupport.appendingPathComponent("MonthlyMoney", isDirectory: true)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private static func persistentStoreURL(named name: String) -> URL {
        persistentStoreDirectory().appendingPathComponent("\(name).store")
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

    private static func logPersistenceError(_ message: String, error: Error) {
        let nsError = error as NSError
        print("Warning: \(message): \(error)")
        if !nsError.userInfo.isEmpty {
            print("Warning: Persistence NSError domain=\(nsError.domain) code=\(nsError.code) userInfo=\(nsError.userInfo)")
        }
        if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
            print("Warning: Underlying error domain=\(underlying.domain) code=\(underlying.code) userInfo=\(underlying.userInfo)")
        }
    }
}
