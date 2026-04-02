import Charts
import SwiftUI

enum DailyChipKind {
    case budget
    case dailyBudget
    case currentBalance
    case aheadBehind
    case currentDailyBudget
    case daysUntilPayday
}

enum DailyChipTone: Equatable {
    case plain
    case negative
    case neutral
    case positive
}

enum DailyChipToneResolver {
    static func tone(
        for kind: DailyChipKind,
        metrics: DailyBudgetCycleMetrics,
        currentBalance: Decimal
    ) -> DailyChipTone {
        switch kind {
        case .budget, .dailyBudget, .daysUntilPayday:
            return .plain
        case .currentBalance:
            return tone(for: currentBalance)
        case .aheadBehind:
            return tone(for: metrics.aheadBehind)
        case .currentDailyBudget:
            return comparisonTone(lhs: metrics.currentDailyBudget, rhs: metrics.dailyBudget)
        }
    }

    static func tone(for value: Decimal) -> DailyChipTone {
        if value < 0 { return .negative }
        if value == 0 { return .neutral }
        return .positive
    }

    static func comparisonTone(lhs: Decimal, rhs: Decimal) -> DailyChipTone {
        if lhs < rhs { return .negative }
        if lhs == rhs { return .neutral }
        return .positive
    }
}

enum DailyPresentationContent {
    static let budgetTitle = "Starting budget"
    static let dailyBudgetTitle = "Average daily budget"
    static let currentBalanceTitle = "Current balance"
    static let projectedFundsTitle = "Predicted remaining funds"

    static func balanceTitle(usesSeparateAccount: Bool) -> String {
        usesSeparateAccount ? currentBalanceTitle : projectedFundsTitle
    }

    static func daysUntilPaydayTitle(paydayDay: Int) -> String {
        "Days until payday (\(MonthItemRowContent.ordinal(paydayDay)))"
    }

    static func aheadBehindTitle(for value: Decimal) -> String {
        value < 0 ? "Behind" : "Ahead"
    }

    static func aheadBehindValue(for value: Decimal) -> String {
        AppState.currency(abs(value))
    }
}

struct DailyView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedEditableChipID: String?

    var body: some View {
        ScrollView {
            let metrics = state.dailyCycleMetrics
            let chartPoints = state.dailyBalanceChartPoints
            VStack(spacing: DailyLayoutMetrics.contentSpacing) {
                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 10),
                        GridItem(.flexible(), spacing: 10)
                    ],
                    spacing: 10
                ) {
                    budgetChip
                    dailyBudgetChip(metrics: metrics)
                    currentBalanceChip(metrics: metrics)
                    aheadBehindChip(metrics: metrics)
                    currentDailyBudgetChip(metrics: metrics)
                    daysUntilPaydayChip(metrics: metrics)
                }

                if !state.dailyBalanceChartPoints.isEmpty {
                    dailyBalanceChartCard(points: chartPoints, metrics: metrics)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(DailyNavigationStyle.title)
        .navigationBarTitleDisplayMode(.inline)
    }

    private func dailyBalanceChartCard(points: [DailyBalanceChartPoint], metrics: DailyBudgetCycleMetrics) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(DailyBalanceChartStyle.title)
                .font(.headline)

            DailyBalanceChartView(
                points: points,
                cycleMetrics: metrics
            )
            .frame(height: 190)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemGroupedBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(uiColor: .separator).opacity(0.18), lineWidth: 1)
        )
    }

    private var budgetChip: some View {
        dailyChip(
            title: DailyPresentationContent.budgetTitle,
            tone: .plain,
            editableFocusID: "daily-budget"
        ) {
            EditableMoneyChipValue(
                value: $state.dailyBudgetAmount,
                fontSize: ChipTypography.dailyValueFontSize(for: horizontalSizeClass),
                focus: $focusedEditableChipID,
                focusID: "daily-budget",
                accessibilityIdentifier: "daily-chip-budget-value"
            )
        }
    }

    private func dailyBudgetChip(metrics: DailyBudgetCycleMetrics) -> some View {
        dailyChip(
            title: DailyPresentationContent.dailyBudgetTitle,
            tone: .plain
        ) {
            Text(AppState.currency(metrics.dailyBudget))
                .font(.system(size: ChipTypography.dailyValueFontSize(for: horizontalSizeClass), weight: .semibold))
                .accessibilityIdentifier("daily-chip-average-budget-value")
        }
    }

    private func currentBalanceChip(metrics: DailyBudgetCycleMetrics) -> some View {
        dailyChip(
            title: DailyPresentationContent.balanceTitle(usesSeparateAccount: state.usesSeparateAccountForDailyBudget),
            tone: DailyChipToneResolver.tone(for: .currentBalance, metrics: metrics, currentBalance: state.dailyBudgetCurrentBalance),
            editableFocusID: state.usesSeparateAccountForDailyBudget ? "daily-current-balance" : nil
        ) {
            if state.usesSeparateAccountForDailyBudget {
                EditableMoneyChipValue(
                    value: Binding(
                        get: { state.dailyBudgetSeparateAccountBalance },
                        set: { state.dailyBudgetSeparateAccountBalance = $0 }
                    ),
                    fontSize: ChipTypography.dailyValueFontSize(for: horizontalSizeClass),
                    focus: $focusedEditableChipID,
                    focusID: "daily-current-balance",
                    accessibilityIdentifier: "daily-chip-current-balance-value"
                )
            } else {
                Text(AppState.currency(state.dailyBudgetCurrentBalance))
                    .font(.system(size: ChipTypography.dailyValueFontSize(for: horizontalSizeClass), weight: .semibold))
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .accessibilityIdentifier("daily-chip-current-balance-value")
            }
        }
    }

    private func aheadBehindChip(metrics: DailyBudgetCycleMetrics) -> some View {
        dailyChip(
            title: DailyPresentationContent.aheadBehindTitle(for: metrics.aheadBehind),
            tone: DailyChipToneResolver.tone(for: .aheadBehind, metrics: metrics, currentBalance: state.dailyBudgetCurrentBalance)
        ) {
            Text(DailyPresentationContent.aheadBehindValue(for: metrics.aheadBehind))
                .font(.system(size: ChipTypography.dailyValueFontSize(for: horizontalSizeClass), weight: .semibold))
                .accessibilityIdentifier("daily-chip-ahead-behind-value")
        }
    }

    private func currentDailyBudgetChip(metrics: DailyBudgetCycleMetrics) -> some View {
        dailyChip(
            title: "Current daily budget",
            tone: DailyChipToneResolver.tone(for: .currentDailyBudget, metrics: metrics, currentBalance: state.dailyBudgetCurrentBalance)
        ) {
            Text(AppState.currency(metrics.currentDailyBudget))
                .font(.system(size: ChipTypography.dailyValueFontSize(for: horizontalSizeClass), weight: .semibold))
                .accessibilityIdentifier("daily-chip-current-daily-budget-value")
        }
    }

    private func daysUntilPaydayChip(metrics: DailyBudgetCycleMetrics) -> some View {
        dailyChip(
            title: DailyPresentationContent.daysUntilPaydayTitle(paydayDay: state.dailyBudgetPaydayDay),
            tone: .plain
        ) {
            Text("\(metrics.remainingDaysToPayday)")
                .font(.system(size: ChipTypography.dailyValueFontSize(for: horizontalSizeClass), weight: .semibold))
                .accessibilityIdentifier("daily-chip-days-until-payday-value")
        }
    }

    @ViewBuilder
    private func dailyChip<Content: View>(
        title: String,
        tone: DailyChipTone,
        editableFocusID: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let style = style(for: tone)
        let palette = ChipPalette.forColorScheme(colorScheme)
        let titleLeadingInset: CGFloat = editableFocusID == nil ? 0 : 28
        let chip = VStack(alignment: .trailing, spacing: 6) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(palette.titleColor)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, titleLeadingInset)

            content()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .foregroundStyle(palette.valueColor)
        .multilineTextAlignment(.trailing)
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .frame(minHeight: DailyLayoutMetrics.chipMinHeight, alignment: .topTrailing)
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [style.top, style.bottom],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(style.border.opacity(0.35), lineWidth: 1)
        )

        if let editableFocusID {
            chip
                .overlay(alignment: .topLeading) {
                    EditableMoneyChipBadge()
                        .padding(.top, 6)
                        .padding(.leading, 6)
                }
                .contentShape(Rectangle())
                .onTapGesture {
                    focusedEditableChipID = editableFocusID
                }
        } else {
            chip
        }
    }

    private func style(for tone: DailyChipTone) -> (top: Color, bottom: Color, border: Color) {
        let palette = ChipPalette.forColorScheme(colorScheme)
        switch tone {
        case .plain:
            return (
                palette.plainTop,
                palette.plainBottom,
                palette.plainBorder
            )
        case .negative:
            return (
                palette.negativeTop,
                palette.negativeBottom,
                .red
            )
        case .neutral:
            return (
                Color(red: 0.99, green: 0.95, blue: 0.82),
                Color(red: 0.96, green: 0.88, blue: 0.63),
                .orange
            )
        case .positive:
            return (
                Color(red: 0.87, green: 0.95, blue: 0.89),
                Color(red: 0.72, green: 0.88, blue: 0.76),
                .green
            )
        }
    }
}

enum DailyLayoutMetrics {
    static let chipMinHeight: CGFloat = 82
    static let contentSpacing: CGFloat = 8
}

enum DailyNavigationStyle {
    static let title = "Daily"
    static let usesInlineTitleDisplay = true
}

private struct DailyBalanceChartView: View {
    let points: [DailyBalanceChartPoint]
    let cycleMetrics: DailyBudgetCycleMetrics

    var body: some View {
        Chart(points) { point in
            ForEach(DailyBalanceChartStyle.weekendGuideDates(from: cycleMetrics.previousPayday, to: cycleMetrics.nextPayday), id: \.self) { date in
                RuleMark(x: .value("Weekend", date))
                    .foregroundStyle(Color.secondary.opacity(0.24))
                    .lineStyle(StrokeStyle(lineWidth: 1))
            }

            AreaMark(
                x: .value("Day", point.date),
                y: .value("Balance", point.balanceValue)
            )
            .interpolationMethod(DailyBalanceChartStyle.interpolationMethod)
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color.accentColor.opacity(0.25),
                        Color.accentColor.opacity(0.05)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            LineMark(
                x: .value("Day", point.date),
                y: .value("Balance", point.balanceValue)
            )
            .interpolationMethod(DailyBalanceChartStyle.interpolationMethod)
            .foregroundStyle(Color.accentColor)
            .lineStyle(StrokeStyle(lineWidth: 2))
        }
        .chartXScale(domain: DailyBalanceChartStyle.domain(for: cycleMetrics))
        .chartYScale(domain: DailyBalanceChartStyle.yDomain(points: points, fallbackBalance: cycleMetrics.currentDailyBudget))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.12))
                AxisTick()
                AxisValueLabel {
                    if let date = value.as(Date.self) {
                        Text(DailyBalanceChartStyle.dayLabel(for: date))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading) { value in
                AxisGridLine()
                    .foregroundStyle(Color.secondary.opacity(0.10))
                AxisTick()
                AxisValueLabel {
                    if let y = value.as(Double.self) {
                        Text(AppState.currency(NSDecimalNumber(value: y).decimalValue))
                    }
                }
            }
        }
        .chartOverlay { _ in
            Rectangle().fill(.clear)
        }
        .accessibilityElement()
        .accessibilityLabel("Payday cycle balance chart")
        .accessibilityValue(chartAccessibilityValue)
    }

    private var chartAccessibilityValue: String {
        guard let first = points.first, let last = points.last else {
            return "No data"
        }
        return "\(AppState.currency(first.balance)) to \(AppState.currency(last.balance))"
    }
}

enum DailyBalanceChartStyle {
    static let title = "Balance"
    static let interpolationMethod: InterpolationMethod = .linear
    static let showsAreaFill = true
    static let showsPointMarkers = false

    static func domain(for metrics: DailyBudgetCycleMetrics) -> ClosedRange<Date> {
        metrics.previousPayday...metrics.nextPayday
    }

    static func yDomain(points: [DailyBalanceChartPoint], fallbackBalance: Decimal) -> ClosedRange<Double> {
        let yValues = points.map(\.balanceValue)
        guard let maxY = yValues.max() else {
            let baseline = max(0, NSDecimalNumber(decimal: fallbackBalance).doubleValue)
            return 0...max(baseline + 1, 1)
        }

        if yValues.count == 1 || yValues.min() == maxY {
            let padding = max(abs(maxY) * 0.05, 25)
            return 0...max(maxY + padding, 1)
        }

        let padding = max(maxY * 0.12, 25)
        return 0...max(maxY + padding, 1)
    }

    static func dayLabel(for date: Date) -> String {
        let day = fixedCalendar.component(.day, from: date)
        return "\(day)"
    }

    static func weekendGuideDates(from start: Date, to end: Date) -> [Date] {
        let normalizedStart = fixedCalendar.startOfDay(for: start)
        let normalizedEnd = fixedCalendar.startOfDay(for: end)
        var dates: [Date] = []
        var day = normalizedStart

        while day <= normalizedEnd {
            if fixedCalendar.component(.weekday, from: day) == 6 {
                dates.append(day)
            }
            guard let nextDay = fixedCalendar.date(byAdding: .day, value: 1, to: day) else {
                break
            }
            day = fixedCalendar.startOfDay(for: nextDay)
        }

        return dates
    }

    private static var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
