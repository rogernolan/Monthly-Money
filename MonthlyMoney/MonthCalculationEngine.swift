import Foundation

struct MonthTotals: Equatable {
    let fixedTotal: Decimal
    let fixedDue: Decimal
    let creditsTotal: Decimal
    let creditsDue: Decimal
    let transferDue: Decimal
    let transferExLivingTotal: Decimal
    let debitsDue: Decimal
    let debitsTotalExLiving: Decimal
    let projectedNetCredit: Decimal
    let netOutgoingsDue: Decimal
    let projectedBalance: Decimal
    let suggestedLiving: Decimal
}

enum MonthCalculationEngine {
    static func fixedTotal(from items: [PlannedItem]) -> Decimal {
        sum(items, type: .fixedDebit)
    }

    static func fixedDue(from items: [PlannedItem]) -> Decimal {
        dueSum(items, type: .fixedDebit)
    }

    static func creditsTotal(from items: [PlannedItem]) -> Decimal {
        sum(items, type: .credit)
    }

    static func creditsDue(from items: [PlannedItem]) -> Decimal {
        dueSum(items, type: .credit)
    }

    static func transferDue(from items: [PlannedItem]) -> Decimal {
        dueSum(items, type: .transfer)
    }

    static func transferExLivingTotal(from items: [PlannedItem]) -> Decimal {
        items
            .filter { $0.type == .transfer && !isLiving($0) }
            .reduce(0) { $0 + $1.amount }
    }

    static func debitsDue(from items: [PlannedItem]) -> Decimal {
        fixedDue(from: items) + transferDue(from: items)
    }

    static func debitsTotalExLiving(from items: [PlannedItem]) -> Decimal {
        fixedTotal(from: items) + transferExLivingTotal(from: items)
    }

    static func projectedNetCredit(from items: [PlannedItem]) -> Decimal {
        creditsTotal(from: items) - debitsTotalExLiving(from: items)
    }

    static func netOutgoingsDue(from items: [PlannedItem]) -> Decimal {
        debitsDue(from: items) - creditsDue(from: items)
    }

    static func projectedBalance(openingBalance: Decimal, from items: [PlannedItem]) -> Decimal {
        openingBalance - netOutgoingsDue(from: items)
    }

    static func suggestedLiving(
        projectedNetCredit: Decimal,
        livingBuffer: Decimal,
        monthlyBudgetFromWeekModel: Decimal,
        minSuggestedLiving: Decimal
    ) -> Decimal {
        let capped = min(projectedNetCredit - livingBuffer, monthlyBudgetFromWeekModel)
        return max(minSuggestedLiving, capped)
    }

    static func monthlyBudgetFromWeekModel(
        year: Int,
        month: Int,
        weeklyEstimate: Decimal,
        weekendEstimate: Decimal
    ) -> Decimal {
        let weekends = Decimal(weekendCount(year: year, month: month))
        let weeklyBase = weeklyEstimate * Decimal(4)
        return weeklyBase + (weekends * weekendEstimate)
    }

    static func calculate(
        items: [PlannedItem],
        openingBalance: Decimal,
        livingBuffer: Decimal,
        weeklyEstimate: Decimal,
        weekendEstimate: Decimal,
        minSuggestedLiving: Decimal,
        yearMonth: YearMonth
    ) -> MonthTotals {
        let projectedNet = projectedNetCredit(from: items)
        let budget = monthlyBudgetFromWeekModel(
            year: yearMonth.year,
            month: yearMonth.month,
            weeklyEstimate: weeklyEstimate,
            weekendEstimate: weekendEstimate
        )

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
            suggestedLiving: suggestedLiving(
                projectedNetCredit: projectedNet,
                livingBuffer: livingBuffer,
                monthlyBudgetFromWeekModel: budget,
                minSuggestedLiving: minSuggestedLiving
            )
        )
    }

    private static func sum(_ items: [PlannedItem], type: PlannedItemType) -> Decimal {
        items.filter { $0.type == type }.reduce(0) { $0 + $1.amount }
    }

    private static func dueSum(_ items: [PlannedItem], type: PlannedItemType) -> Decimal {
        items.filter { $0.type == type && !$0.isPaid }.reduce(0) { $0 + $1.amount }
    }

    private static func isLiving(_ item: PlannedItem) -> Bool {
        item.label.lowercased().contains("living")
    }

    private static func weekendCount(year: Int, month: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = 1

        guard let startDate = calendar.date(from: components),
              let daysRange = calendar.range(of: .day, in: .month, for: startDate) else {
            return 0
        }

        return daysRange.reduce(0) { partial, day in
            var dayComponents = DateComponents()
            dayComponents.year = year
            dayComponents.month = month
            dayComponents.day = day
            guard let date = calendar.date(from: dayComponents) else {
                return partial
            }
            let weekday = calendar.component(.weekday, from: date)
            let isWeekendDay = weekday == 1 || weekday == 7
            return partial + (isWeekendDay ? 1 : 0)
        }
    }
}
