import Foundation
import WatchConnectivity

final class DailyBudgetWatchSnapshotSyncer: NSObject, DailyBudgetWatchSnapshotSyncing {
    static let shared = DailyBudgetWatchSnapshotSyncer()

    private let encoder = JSONEncoder()
    private let defaults: UserDefaults
    private let session: WCSession?
    private let defaultsKey = DailyBudgetSharedStorage.watchSnapshotKey
    private var latestSnapshotData: Data?

    init(
        defaults: UserDefaults = DailyBudgetSharedStorage.sharedDefaults ?? .standard,
        session: WCSession? = WCSession.isSupported() ? .default : nil
    ) {
        self.defaults = defaults
        self.session = session
        super.init()

        session?.delegate = self
        session?.activate()
    }

    func sync(_ snapshot: DailyBudgetWatchSnapshot) {
        guard let data = try? encoder.encode(snapshot) else { return }
        latestSnapshotData = data
        defaults.set(data, forKey: defaultsKey)

        guard let session else { return }
        pushSnapshotData(data, to: session)
    }

    private func pushSnapshotData(_ data: Data, to session: WCSession) {
        do {
            try session.updateApplicationContext([defaultsKey: data])
        } catch {
            print("Watch snapshot sync failed: \(error)")
        }
    }
}

extension DailyBudgetWatchSnapshotSyncer: WCSessionDelegate {
    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        guard let latestSnapshotData else { return }
        pushSnapshotData(latestSnapshotData, to: session)
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
}
