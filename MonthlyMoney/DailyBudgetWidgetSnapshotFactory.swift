import Foundation

enum DailyBudgetWidgetSnapshotFactory {
    static func make(
        currentBalance: Decimal,
        metrics: DailyBudgetCycleMetrics
    ) -> DailyBudgetWidgetSnapshot {
        DailyBudgetWidgetSnapshot(
            updatedAt: Date(),
            chips: [
                DailyBudgetWidgetChipSnapshot(
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
                DailyBudgetWidgetChipSnapshot(
                    title: "Current Day",
                    value: AppState.currency(metrics.currentDailyBudget),
                    tone: tone(
                        for: DailyChipToneResolver.tone(
                            for: .currentDailyBudget,
                            metrics: metrics,
                            currentBalance: currentBalance
                        )
                    )
                )
            ]
        )
    }

    private static func tone(for tone: DailyChipTone) -> DailyBudgetWidgetChipTone {
        switch tone {
        case .negative:
            return .negative
        case .neutral, .plain:
            return .neutral
        case .positive:
            return .positive
        }
    }
}
