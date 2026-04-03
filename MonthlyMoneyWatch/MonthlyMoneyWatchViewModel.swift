import Foundation
import WatchConnectivity
#if canImport(WidgetKit)
import WidgetKit
#endif

@MainActor
final class MonthlyMoneyWatchViewModel: NSObject, ObservableObject {
    @Published private(set) var snapshot: WatchDailyBudgetSnapshot?

    private let store: WatchDailyBudgetSnapshotStore
    private let widgetStore: DailyBudgetWidgetSnapshotStore
    private let session: WCSession?
    private let decoder = JSONDecoder()

    init(
        store: WatchDailyBudgetSnapshotStore = WatchDailyBudgetSnapshotStore(),
        widgetStore: DailyBudgetWidgetSnapshotStore = DailyBudgetWidgetSnapshotStore(),
        session: WCSession? = WCSession.isSupported() ? .default : nil
    ) {
        self.store = store
        self.widgetStore = widgetStore
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
        guard let decodedSnapshot = try? decoder.decode(WatchDailyBudgetSnapshot.self, from: data) else {
            snapshot = nil
            return
        }
        snapshot = decodedSnapshot
        if let widgetSnapshot = DailyBudgetWidgetSnapshot(watchSnapshot: decodedSnapshot) {
            widgetStore.save(widgetSnapshot)
            #if canImport(WidgetKit)
            WidgetCenter.shared.reloadAllTimelines()
            #endif
        }
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
