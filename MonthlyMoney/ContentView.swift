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
