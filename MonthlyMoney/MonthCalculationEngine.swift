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
        paydayDay: Int = 1,
        weeklyEstimate: Decimal,
        weekendEstimate: Decimal
    ) -> Decimal {
        let weekends = Decimal(weekendCount(year: year, month: month, paydayDay: paydayDay))
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
        yearMonth: YearMonth,
        paydayDay: Int = 1
    ) -> MonthTotals {
        let projectedNet = projectedNetCredit(from: items)
        let budget = monthlyBudgetFromWeekModel(
            year: yearMonth.year,
            month: yearMonth.month,
            paydayDay: paydayDay,
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

    private static func weekendCount(year: Int, month: Int, paydayDay: Int) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .current

        guard let startDate = paydayDay <= 1
                ? calendar.date(from: DateComponents(year: year, month: month, day: 1))
                : paydayDate(year: previousMonthYear(forYear: year, month: month), month: previousMonthValue(for: month), paydayDay: paydayDay, calendar: calendar),
              let endDate = paydayDay <= 1
                ? calendar.date(byAdding: .month, value: 1, to: startDate)
                : paydayDate(year: year, month: month, paydayDay: paydayDay, calendar: calendar) else {
            return 0
        }

        var count = 0
        var date = startDate
        while date < endDate {
            let weekday = calendar.component(.weekday, from: date)
            if weekday == 1 || weekday == 7 {
                count += 1
            }
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: date) else {
                break
            }
            date = nextDate
        }
        return count
    }

    private static func paydayDate(year: Int, month: Int, paydayDay: Int, calendar: Calendar) -> Date? {
        let monthStart = calendar.date(from: DateComponents(year: year, month: month, day: 1))
        let daysInMonth = monthStart.flatMap { calendar.range(of: .day, in: .month, for: $0)?.count } ?? 31
        return calendar.date(from: DateComponents(year: year, month: month, day: min(max(paydayDay, 1), daysInMonth)))
    }

    private static func previousMonthYear(forYear year: Int, month: Int) -> Int {
        month == 1 ? year - 1 : year
    }

    private static func previousMonthValue(for month: Int) -> Int {
        month == 1 ? 12 : month - 1
    }
}
