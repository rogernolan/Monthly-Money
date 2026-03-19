import SwiftUI

enum CloudRefreshPolicy {
    static let pollInterval: Duration = .seconds(5)

    static func shouldPoll(
        privateStoreSyncMode: StoreSyncMode,
        sharedStoreSyncMode: StoreSyncMode,
        scenePhase: ScenePhase,
        isRunningTests: Bool
    ) -> Bool {
        let hasCloudBackedStore = privateStoreSyncMode == .cloudPrivate || sharedStoreSyncMode == .cloudShared
        return hasCloudBackedStore && scenePhase == .active && !isRunningTests
    }
}

enum CloudKitShareAcceptancePolicy {
    static func shouldProcess(pendingMetadataCount: Int) -> Bool {
        pendingMetadataCount > 0
    }
}

enum CloudKitShareAcceptanceDispatcher {
    static func dispatchIfNeeded<Metadata>(
        pendingMetadataCount: Int,
        drain: () -> [Metadata],
        start: ([Metadata]) -> Void
    ) {
        guard CloudKitShareAcceptancePolicy.shouldProcess(pendingMetadataCount: pendingMetadataCount) else {
            return
        }

        let metadata = drain()
        guard !metadata.isEmpty else { return }
        start(metadata)
    }
}

struct ContentView: View {
    @StateObject private var state: AppState
    @StateObject private var acceptedCloudKitShareInbox = AcceptedCloudKitShareInbox.shared
    @Environment(\.scenePhase) private var scenePhase
    private let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

    init(repository: AccountRepository) {
        _state = StateObject(wrappedValue: AppState(repository: repository))
    }

    private func dispatchPendingAcceptedSharesIfNeeded() {
        CloudKitShareAcceptanceDispatcher.dispatchIfNeeded(
            pendingMetadataCount: acceptedCloudKitShareInbox.pendingMetadata.count,
            drain: { acceptedCloudKitShareInbox.drainPendingMetadata() },
            start: { metadata in
                Task {
                    await state.acceptIncomingCloudKitShares(metadata)
                }
            }
        )
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
        .task {
            dispatchPendingAcceptedSharesIfNeeded()
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
                sharedStoreSyncMode: state.sharedStoreSyncMode,
                scenePhase: scenePhase,
                isRunningTests: isRunningTests
            ) else {
                return
            }

            try? state.refresh()

            while CloudRefreshPolicy.shouldPoll(
                privateStoreSyncMode: state.privateStoreSyncMode,
                sharedStoreSyncMode: state.sharedStoreSyncMode,
                scenePhase: scenePhase,
                isRunningTests: isRunningTests
            ) {
                try? await Task.sleep(for: CloudRefreshPolicy.pollInterval)
                guard !Task.isCancelled else { return }
                try? state.refresh()
            }
        }
        .onChange(of: acceptedCloudKitShareInbox.pendingMetadata.count) { _, count in
            guard count > 0 else { return }
            dispatchPendingAcceptedSharesIfNeeded()
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
