import SwiftUI

struct ContentView: View {
    @StateObject private var state: AppState
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
