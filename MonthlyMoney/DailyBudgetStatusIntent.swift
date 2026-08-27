import AppIntents
import Foundation

struct DailyBudgetStatusSnapshot: Equatable {
    let aheadBehind: Decimal
    let currentDailyBudget: Decimal
    let daysUntilPayday: Int
    let projectedBalance: Decimal
}

@MainActor
struct DailyBudgetStatusSummary: Equatable {
    let spokenPhrase: String
}

@MainActor
enum DailyBudgetStatusFormatter {
    static func summary(from snapshot: DailyBudgetStatusSnapshot) -> DailyBudgetStatusSummary {
        if snapshot.projectedBalance < 0 {
            let dayWord = snapshot.daysUntilPayday == 1 ? "day" : "days"
            let spokenPhrase = "\(snapshot.daysUntilPayday) \(dayWord) to payday, you need to pay at least \(currency(abs(snapshot.projectedBalance))) in to avoid going overdrawn."
            return DailyBudgetStatusSummary(spokenPhrase: spokenPhrase)
        }

        let statusAmount = currency(abs(snapshot.aheadBehind))
        let statusWord = snapshot.aheadBehind < 0 ? "behind" : "ahead"
        let dayWord = snapshot.daysUntilPayday == 1 ? "day" : "days"
        let spokenPhrase = "You're \(statusAmount) \(statusWord). Daily budget: \(currency(snapshot.currentDailyBudget)). Payday is in \(snapshot.daysUntilPayday) \(dayWord)."
        return DailyBudgetStatusSummary(spokenPhrase: spokenPhrase)
    }

    private static func currency(_ value: Decimal) -> String {
        AppState.currency(value)
    }
}

@MainActor
struct DailyBudgetStatusService {
    let repository: AccountRepository
    var nowProvider: () -> Date = Date.init

    func currentStatus() throws -> DailyBudgetStatusSnapshot {
        let state = AppState(
            repository: repository,
            dailyBudgetWatchSnapshotSyncer: NoOpDailyBudgetWatchSnapshotSyncer(),
            dailyBudgetWidgetSnapshotSyncer: NoOpDailyBudgetWidgetSnapshotSyncer(),
            nowProvider: nowProvider
        )
        try state.refresh()
        let metrics = state.dailyCycleMetrics
        return DailyBudgetStatusSnapshot(
            aheadBehind: metrics.aheadBehind,
            currentDailyBudget: metrics.currentDailyBudget,
            daysUntilPayday: metrics.remainingDaysToPayday,
            projectedBalance: state.projectedBalanceFromCurrentBalance
        )
    }
}

final class NoOpDailyBudgetWatchSnapshotSyncer: DailyBudgetWatchSnapshotSyncing {
    func sync(_ snapshot: DailyBudgetWatchSnapshot) {
        _ = snapshot
    }
}

final class NoOpDailyBudgetWidgetSnapshotSyncer: DailyBudgetWidgetSnapshotSyncing {
    func sync(_ snapshot: DailyBudgetWidgetSnapshot) {
        _ = snapshot
    }
}

struct DailyBudgetStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "Get Budget Status"
    static let description = IntentDescription("Get the current daily budget status, including whether you are ahead or behind, your current daily budget, and how many days remain until payday.")

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let snapshot: DailyBudgetStatusSnapshot = try await MainActor.run {
            let repository = try MonthlyMoneyRepositoryBootstrap.makeRepository()
            return try DailyBudgetStatusService(repository: repository).currentStatus()
        }
        let summary = await MainActor.run {
            DailyBudgetStatusFormatter.summary(from: snapshot)
        }
        return .result(dialog: IntentDialog(stringLiteral: summary.spokenPhrase))
    }
}

struct MonthlyMoneyAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DailyBudgetStatusIntent(),
            phrases: [
                "What's my budget status in \(.applicationName)",
                "How far ahead am I in \(.applicationName)",
                "What's my current daily budget in \(.applicationName)"
            ],
            shortTitle: "Budget Status",
            systemImageName: "sterlingsign.circle"
        )
    }
}
