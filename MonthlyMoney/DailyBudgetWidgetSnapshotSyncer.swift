import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

final class DailyBudgetWidgetSnapshotSyncer: DailyBudgetWidgetSnapshotSyncing {
    static let shared = DailyBudgetWidgetSnapshotSyncer()

    private let store: DailyBudgetWidgetSnapshotStore

    init(store: DailyBudgetWidgetSnapshotStore = DailyBudgetWidgetSnapshotStore()) {
        self.store = store
    }

    func sync(_ snapshot: DailyBudgetWidgetSnapshot) {
        store.save(snapshot)
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }
}
