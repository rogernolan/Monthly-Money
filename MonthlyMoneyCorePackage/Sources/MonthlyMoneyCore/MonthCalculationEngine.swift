import Foundation

public struct MonthTotals: Equatable {
    public let fixedTotal: Decimal
    public let fixedDue: Decimal
    public let creditsTotal: Decimal
    public let creditsDue: Decimal
    public let transferDue: Decimal
    public let transferExLivingTotal: Decimal
    public let debitsDue: Decimal
    public let debitsTotalExLiving: Decimal
    public let projectedNetCredit: Decimal
    public let netOutgoingsDue: Decimal
    public let projectedBalance: Decimal
    public let suggestedLiving: Decimal
}

public enum MonthCalculationEngine {
    public static func fixedTotal(from items: [PlannedItem]) -> Decimal { sum(items, type: .fixedDebit) }
    public static func fixedDue(from items: [PlannedItem]) -> Decimal { dueSum(items, type: .fixedDebit) }
    public static func creditsTotal(from items: [PlannedItem]) -> Decimal { sum(items, type: .credit) }
    public static func creditsDue(from items: [PlannedItem]) -> Decimal { dueSum(items, type: .credit) }
    public static func transferDue(from items: [PlannedItem]) -> Decimal { dueSum(items, type: .transfer) }

    public static func transferExLivingTotal(from items: [PlannedItem]) -> Decimal {
        items.filter { $0.type == .transfer && !$0.label.lowercased().contains("living") }
            .reduce(0) { $0 + $1.amount }
    }

    public static func debitsDue(from items: [PlannedItem]) -> Decimal { fixedDue(from: items) + transferDue(from: items) }
    public static func debitsTotalExLiving(from items: [PlannedItem]) -> Decimal { fixedTotal(from: items) + transferExLivingTotal(from: items) }
    public static func projectedNetCredit(from items: [PlannedItem]) -> Decimal { creditsTotal(from: items) - debitsTotalExLiving(from: items) }
    public static func netOutgoingsDue(from items: [PlannedItem]) -> Decimal { debitsDue(from: items) - creditsDue(from: items) }
    public static func projectedBalance(openingBalance: Decimal, from items: [PlannedItem]) -> Decimal { openingBalance + projectedNetCredit(from: items) }

    public static func suggestedLiving(projectedNetCredit: Decimal, livingBuffer: Decimal, monthlyBudgetFromWeekModel: Decimal, minSuggestedLiving: Decimal) -> Decimal {
        max(minSuggestedLiving, min(projectedNetCredit - livingBuffer, monthlyBudgetFromWeekModel))
    }

    public static func monthlyBudgetFromWeekModel(year: Int, month: Int, weeklyEstimate: Decimal, weekendEstimate: Decimal) -> Decimal {
        let weekends = Decimal(weekendCount(year: year, month: month))
        return weeklyEstimate * 4 + weekends * weekendEstimate
    }

    public static func calculate(items: [PlannedItem], openingBalance: Decimal, livingBuffer: Decimal, weeklyEstimate: Decimal, weekendEstimate: Decimal, minSuggestedLiving: Decimal, yearMonth: YearMonth) -> MonthTotals {
        let projectedNet = projectedNetCredit(from: items)
        let budget = monthlyBudgetFromWeekModel(year: yearMonth.year, month: yearMonth.month, weeklyEstimate: weeklyEstimate, weekendEstimate: weekendEstimate)
        return MonthTotals(
            fixedTotal: fixedTotal(from: items),
            fixedDue: fixedDue(from: items),
            creditsTotal: creditsTotal(from: items),
            creditsDue: creditsDue(from: items),
            transferDue: transferDue(from: items),
            transferExLivingTotal: transferExLivingTotal(from: items),
            debitsDue: debitsDue(from: items),
            debitsTotalExLiving: debitsTotalExLiving(from: items),
            projectedNetCredit: projectedNet,
            netOutgoingsDue: netOutgoingsDue(from: items),
            projectedBalance: projectedBalance(openingBalance: openingBalance, from: items),
            suggestedLiving: suggestedLiving(projectedNetCredit: projectedNet, livingBuffer: livingBuffer, monthlyBudgetFromWeekModel: budget, minSuggestedLiving: minSuggestedLiving)
        )
    }

    private static func sum(_ items: [PlannedItem], type: PlannedItemType) -> Decimal {
        items.filter { $0.type == type }.reduce(0) { $0 + $1.amount }
    }

    private static func dueSum(_ items: [PlannedItem], type: PlannedItemType) -> Decimal {
        items.filter { $0.type == type && !$0.isPaid }.reduce(0) { $0 + $1.amount }
    }

    private static func weekendCount(year: Int, month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current
        var comps = DateComponents(year: year, month: month, day: 1)
        guard let start = calendar.date(from: comps), let days = calendar.range(of: .day, in: .month, for: start) else { return 0 }
        return days.reduce(0) { partial, day in
            comps.day = day
            guard let date = calendar.date(from: comps) else { return partial }
            let weekday = calendar.component(.weekday, from: date)
            return partial + ((weekday == 1 || weekday == 7) ? 1 : 0)
        }
    }
}
