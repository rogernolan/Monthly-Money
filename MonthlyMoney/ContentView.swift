import SwiftUI

enum CloudRefreshPolicy {
    static let pollInterval: Duration = .seconds(5)

    static func shouldPoll(privateStoreSyncMode: StoreSyncMode, scenePhase: ScenePhase, isRunningTests: Bool) -> Bool {
        privateStoreSyncMode == .cloudPrivate && scenePhase == .active && !isRunningTests
    }
}

struct ContentView: View {
    @StateObject private var state: AppState
    @Environment(\.scenePhase) private var scenePhase
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init(repository: AccountRepository) {
        _state = StateObject(wrappedValue: AppState(repository: repository))
    }

    var body: some View {
        TabView {
            NavigationStack {
                MonthView()
            }
            .tabItem {
                Label("Month", systemImage: "calendar")
            }

            NavigationStack {
                DailyView()
            }
            .tabItem {
                Label("Daily", systemImage: "sun.max")
            }

            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
        .environmentObject(state)
        .task {
            if !isRunningTests {
                await state.bootstrapIfNeeded()
            }
        }
        .alert(
            "Open shared budget?",
            isPresented: Binding(
                get: { state.shouldShowSharedBudgetOverwriteAlert },
                set: { isPresented in
                    if !isPresented {
                        state.cancelSharedBudgetOverwrite()
                    }
                }
            ),
            presenting: state.pendingSharedBudgetAdoption
        ) { _ in
            Button("Cancel", role: .cancel) {
                state.cancelSharedBudgetOverwrite()
            }
            Button("Overwrite and Open Shared Budget", role: .destructive) {
                state.confirmSharedBudgetOverwriteFromUI()
            }
        } message: { adoption in
            Text("Opening \"\(adoption.budgetName)\" will overwrite your existing MonthlyMoney budget on this device. This cannot be undone.")
        }
        .task(id: scenePhase) {
            guard CloudRefreshPolicy.shouldPoll(
                privateStoreSyncMode: state.privateStoreSyncMode,
                scenePhase: scenePhase,
                isRunningTests: isRunningTests
            ) else {
                return
            }

            try? state.refresh()

            while CloudRefreshPolicy.shouldPoll(
                privateStoreSyncMode: state.privateStoreSyncMode,
                scenePhase: scenePhase,
                isRunningTests: isRunningTests
            ) {
                try? await Task.sleep(for: CloudRefreshPolicy.pollInterval)
                guard !Task.isCancelled else { return }
                try? state.refresh()
            }
        }
    }
}

#Preview {
    ContentView(
        repository: AccountRepository(
            privateStore: InMemoryAccountDataStore(),
            sharedStore: InMemoryAccountDataStore()
        )
    )
}
