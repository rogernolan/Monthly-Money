import Foundation

enum DailyBudgetWatchChipTone: String, Codable, Equatable {
    case plain
    case negative
    case neutral
    case positive
}

struct DailyBudgetWatchChipSnapshot: Codable, Equatable {
    let title: String
    let value: String
    let tone: DailyBudgetWatchChipTone
}

struct DailyBudgetWatchSnapshot: Codable, Equatable {
    let updatedAt: Date
    let chips: [DailyBudgetWatchChipSnapshot]
}

protocol DailyBudgetWatchSnapshotSyncing: AnyObject {
    func sync(_ snapshot: DailyBudgetWatchSnapshot)
}

enum DailyBudgetWatchSnapshotFactory {
    static func make(
        dailyBudgetAmount: Decimal,
        paydayDay: Int,
        usesSeparateAccount: Bool,
        currentBalance: Decimal,
        metrics: DailyBudgetCycleMetrics
    ) -> DailyBudgetWatchSnapshot {
        DailyBudgetWatchSnapshot(
            updatedAt: Date(),
            chips: [
                DailyBudgetWatchChipSnapshot(
                    title: "Budget",
                    value: AppState.currency(dailyBudgetAmount),
                    tone: .plain
                ),
                DailyBudgetWatchChipSnapshot(
                    title: "Avg. Day",
                    value: AppState.currency(metrics.dailyBudget),
                    tone: .plain
                ),
                DailyBudgetWatchChipSnapshot(
                    title: "Balance",
                    value: AppState.currency(currentBalance),
                    tone: tone(
                        for: DailyChipToneResolver.tone(
                            for: .currentBalance,
                            metrics: metrics,
                            currentBalance: currentBalance
                        )
                    )
                ),
                DailyBudgetWatchChipSnapshot(
                    title: DailyPresentationContent.aheadBehindTitle(for: metrics.aheadBehind),
                    value: DailyPresentationContent.aheadBehindValue(for: metrics.aheadBehind),
                    tone: tone(
                        for: DailyChipToneResolver.tone(
                            for: .aheadBehind,
                            metrics: metrics,
                            currentBalance: currentBalance
                        )
                    )
                ),
                DailyBudgetWatchChipSnapshot(
                    title: "Current Day",
                    value: AppState.currency(metrics.currentDailyBudget),
                    tone: tone(
                        for: DailyChipToneResolver.tone(
                            for: .currentDailyBudget,
                            metrics: metrics,
                            currentBalance: currentBalance
                        )
                    )
                ),
                DailyBudgetWatchChipSnapshot(
                    title: "Days left",
                    value: "\(metrics.remainingDaysToPayday)",
                    tone: .plain
                )
            ]
        )
    }

    private static func tone(for tone: DailyChipTone) -> DailyBudgetWatchChipTone {
        switch tone {
        case .plain:
            return .plain
        case .negative:
            return .negative
        case .neutral:
            return .neutral
        case .positive:
            return .positive
        }
    }
}
