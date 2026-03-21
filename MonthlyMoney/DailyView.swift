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
}

struct DailyView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var colorScheme
    @FocusState private var focusedEditableChipID: String?

    var body: some View {
        ScrollView {
            GeometryReader { proxy in
                let cardWidth = max((proxy.size.width - 10) / 2, 0)
                let metrics = state.dailyCycleMetrics
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        budgetChip
                            .frame(width: cardWidth)
                        dailyBudgetChip(metrics: metrics)
                            .frame(width: cardWidth)
                    }

                    HStack(spacing: 10) {
                        currentBalanceChip(metrics: metrics)
                            .frame(width: cardWidth)
                        aheadBehindChip(metrics: metrics)
                            .frame(width: cardWidth)
                    }

                    HStack(spacing: 10) {
                        currentDailyBudgetChip(metrics: metrics)
                            .frame(width: cardWidth)
                        daysUntilPaydayChip(metrics: metrics)
                            .frame(width: cardWidth)
                    }
                }
            }
            .frame(height: 326)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Daily")
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
                    value: $state.dailyBudgetSeparateAccountBalance,
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
            title: "Ahead / behind",
            tone: DailyChipToneResolver.tone(for: .aheadBehind, metrics: metrics, currentBalance: state.dailyBudgetCurrentBalance)
        ) {
            Text(AppState.currency(metrics.aheadBehind))
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
        .frame(minHeight: 92, alignment: .topTrailing)
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
                Color(red: 0.98, green: 0.86, blue: 0.86),
                Color(red: 0.93, green: 0.70, blue: 0.70),
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
