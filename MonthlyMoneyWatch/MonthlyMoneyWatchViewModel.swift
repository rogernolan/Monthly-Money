import Foundation
import WatchConnectivity

@MainActor
final class MonthlyMoneyWatchViewModel: NSObject, ObservableObject {
    @Published private(set) var snapshot: WatchDailyBudgetSnapshot?

    private let store: WatchDailyBudgetSnapshotStore
    private let session: WCSession?
    private let decoder = JSONDecoder()

    init(
        store: WatchDailyBudgetSnapshotStore = WatchDailyBudgetSnapshotStore(),
        session: WCSession? = WCSession.isSupported() ? .default : nil
    ) {
        self.store = store
        self.session = session
        self.snapshot = store.load()
        super.init()

        session?.delegate = self
        session?.activate()
        applyExistingApplicationContextIfAvailable()
    }

    func refreshFromCache() {
        snapshot = store.load()
    }

    private func applySnapshotData(_ data: Data) {
        store.save(data)
        snapshot = try? decoder.decode(WatchDailyBudgetSnapshot.self, from: data)
    }

    private func applyExistingApplicationContextIfAvailable() {
        guard let session else { return }

        if let data = session.receivedApplicationContext[WatchDailyBudgetSnapshotKey.applicationContextKey] as? Data {
            applySnapshotData(data)
            return
        }

        if let data = session.applicationContext[WatchDailyBudgetSnapshotKey.applicationContextKey] as? Data {
            applySnapshotData(data)
        }
    }
}

extension MonthlyMoneyWatchViewModel: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor in
            applyExistingApplicationContextIfAvailable()
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String : Any]) {
        guard let data = applicationContext[WatchDailyBudgetSnapshotKey.applicationContextKey] as? Data else {
            return
        }

        Task { @MainActor in
            applySnapshotData(data)
        }
    }
}
