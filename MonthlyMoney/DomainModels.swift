import Foundation
import SwiftData

enum AccountRole: String, Codable, CaseIterable {
    case regular
    case variable
    case other
}

enum AccountType: String, Codable, CaseIterable {
    case current
    case credit
    case cash
    case other
}

enum BudgetSharingState: String, Codable, CaseIterable {
    case local
    case shared
}

enum PlannedItemType: String, Codable, CaseIterable {
    case fixedDebit
    case credit
    case transfer
}

enum PlannedItemSource: String, Codable, CaseIterable {
    case manual
    case copiedFromPreviousMonth
    case importedUnplanned
}

enum RepeatMode: String, Codable, CaseIterable {
    case oneOff = "oneOff"
    case calendar = "calendar"
    case periodic = "periodic"
}

struct CalendarRepeatTemplate: Codable {
    let type: PlannedItemType
    let label: String
    let matchingString: String?
    let amountRaw: String
    let dueDay: Int?
    let dueText: String?
    let importedPostedAt: Date?
    let notes: String

    init(item: PlannedItem) {
        type = item.type
        label = item.label
        matchingString = item.matchingString
        amountRaw = NSDecimalNumber(decimal: item.amount).stringValue
        dueDay = item.dueDay
        dueText = item.dueText
        importedPostedAt = item.importedPostedAt
        notes = item.notes
    }

    var amount: Decimal {
        Decimal(string: amountRaw, locale: Locale(identifier: "en_US_POSIX")) ?? 0
    }

    var payload: String? {
        (try? JSONEncoder().encode(self)).flatMap { String(data: $0, encoding: .utf8) }
    }

    init?(payload: String) {
        guard let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(Self.self, from: data) else { return nil }
        self = decoded
    }
}

@Model
final class PeriodicRepeatRevision {
    var id: UUID = UUID()
    var repeatID: UUID = UUID()
    var effectiveDateRaw: String = "2000-01-01"
    var anchorDateRaw: String = "2000-01-01"
    var repeatDays: Int = 1
    var type: PlannedItemType = PlannedItemType.fixedDebit
    var label: String = ""
    var matchingString: String?
    var amount: Decimal = 0
    var notes: String = ""

    var effectiveDate: CivilDate { CivilDate(rawValue: effectiveDateRaw)! }
    var anchorDate: CivilDate { CivilDate(rawValue: anchorDateRaw)! }

    init(
        id: UUID = UUID(),
        repeatID: UUID,
        effectiveDate: CivilDate,
        anchorDate: CivilDate,
        repeatDays: Int,
        type: PlannedItemType,
        label: String,
        matchingString: String?,
        amount: Decimal,
        notes: String
    ) {
        self.id = id
        self.repeatID = repeatID
        self.effectiveDateRaw = effectiveDate.rawValue
        self.anchorDateRaw = anchorDate.rawValue
        self.repeatDays = repeatDays
        self.type = type
        self.label = label
        self.matchingString = matchingString
        self.amount = amount
        self.notes = notes
    }
}

@Model
final class PeriodicRepeat {
    var id: UUID = UUID()
    var budgetID: UUID = UUID()
    var accountID: UUID = UUID()
    var endDateRaw: String?

    var endDate: CivilDate? {
        get { endDateRaw.flatMap(CivilDate.init(rawValue:)) }
        set { endDateRaw = newValue?.rawValue }
    }

    init(id: UUID = UUID(), budgetID: UUID, accountID: UUID, endDate: CivilDate? = nil) {
        self.id = id
        self.budgetID = budgetID
        self.accountID = accountID
        self.endDateRaw = endDate?.rawValue
    }
}

@Model
final class PeriodicRepeatSkip {
    var id: UUID = UUID()
    var repeatID: UUID = UUID()
    var scheduledDateRaw: String = "2000-01-01"

    var scheduledDate: CivilDate { CivilDate(rawValue: scheduledDateRaw)! }

    init(id: UUID = UUID(), repeatID: UUID, scheduledDate: CivilDate) {
        self.id = id
        self.repeatID = repeatID
        self.scheduledDateRaw = scheduledDate.rawValue
    }
}

@Model
final class PeriodicOccurrenceRecord {
    var plannedItemID: UUID = UUID()
    var budgetID: UUID = UUID()
    var repeatID: UUID?
    var scheduledDateRaw: String = "2000-01-01"
    var dueDateRaw: String = "2000-01-01"
    var isOverride: Bool = false

    var scheduledDate: CivilDate { CivilDate(rawValue: scheduledDateRaw)! }
    var dueDate: CivilDate { CivilDate(rawValue: dueDateRaw)! }

    init(
        plannedItemID: UUID,
        budgetID: UUID,
        repeatID: UUID?,
        scheduledDate: CivilDate,
        dueDate: CivilDate,
        isOverride: Bool = false
    ) {
        self.plannedItemID = plannedItemID
        self.budgetID = budgetID
        self.repeatID = repeatID
        self.scheduledDateRaw = scheduledDate.rawValue
        self.dueDateRaw = dueDate.rawValue
        self.isOverride = isOverride
    }
}

enum WheelOfMoneyMonth: Int, Codable, CaseIterable {
    case january = 1
    case february = 2
    case march = 3
    case april = 4
    case may = 5
    case june = 6
    case july = 7
    case august = 8
    case september = 9
    case october = 10
    case november = 11
    case december = 12
}

struct YearMonth: Codable, Hashable, Comparable, CustomStringConvertible {
    let year: Int
    let month: Int

    init(year: Int, month: Int) {
        precondition((1...12).contains(month), "Month must be 1...12")
        self.year = year
        self.month = month
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 2,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              (1...12).contains(month) else {
            return nil
        }
        self.year = year
        self.month = month
    }

    var rawValue: String {
        String(format: "%04d-%02d", year, month)
    }

    var description: String { rawValue }

    static func < (lhs: YearMonth, rhs: YearMonth) -> Bool {
        if lhs.year != rhs.year { return lhs.year < rhs.year }
        return lhs.month < rhs.month
    }
}

struct PopulatedMonth: Codable, Hashable {
    let id: UUID
    let budgetID: UUID
    let monthKey: YearMonth

    init(id: UUID = UUID(), budgetID: UUID, monthKey: YearMonth) {
        self.id = id
        self.budgetID = budgetID
        self.monthKey = monthKey
    }
}

@Model
final class PopulatedMonthRecord {
    var id: UUID = UUID()
    var budgetID: UUID = UUID()
    var monthKey: String = YearMonth(year: 2000, month: 1).rawValue

    init(id: UUID = UUID(), budgetID: UUID, monthKey: YearMonth) {
        self.id = id
        self.budgetID = budgetID
        self.monthKey = monthKey.rawValue
    }
}

@Model
final class Budget {
    var id: UUID = UUID()
    var name: String = ""
    var ownerParticipantID: String = ""
    var sharingState: BudgetSharingState = BudgetSharingState.local
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var monthlyBalanceLastUpdatedAt: Date?
    var dailyBalanceLastUpdatedAt: Date?
    var usesSeparateAccountForDailyBudget: Bool = false
    var dailyBudgetAmount: Decimal = 0
    var dailyBudgetPaydayDay: Int = 1
    var dailyBudgetSeparateAccountBalance: Decimal = 0
    var autoGenerateWoMSavingsEveryMonth: Bool = false
    var allowsPreviousMonthEditing: Bool = false
    var monthBalancesPayload: String = "{}"
    var hiddenDailyAccountID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        ownerParticipantID: String,
        sharingState: BudgetSharingState = .local,
        createdAt: Date = Date(),
        updatedAt: Date = Date(),
        monthlyBalanceLastUpdatedAt: Date? = nil,
        dailyBalanceLastUpdatedAt: Date? = nil,
        usesSeparateAccountForDailyBudget: Bool = false,
        dailyBudgetAmount: Decimal = 0,
        dailyBudgetPaydayDay: Int = 1,
        dailyBudgetSeparateAccountBalance: Decimal = 0,
        autoGenerateWoMSavingsEveryMonth: Bool = false,
        allowsPreviousMonthEditing: Bool = false,
        monthBalancesPayload: String = "{}",
        hiddenDailyAccountID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.ownerParticipantID = ownerParticipantID
        self.sharingState = sharingState
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.monthlyBalanceLastUpdatedAt = monthlyBalanceLastUpdatedAt
        self.dailyBalanceLastUpdatedAt = dailyBalanceLastUpdatedAt
        self.usesSeparateAccountForDailyBudget = usesSeparateAccountForDailyBudget
        self.dailyBudgetAmount = dailyBudgetAmount
        self.dailyBudgetPaydayDay = dailyBudgetPaydayDay
        self.dailyBudgetSeparateAccountBalance = dailyBudgetSeparateAccountBalance
        self.autoGenerateWoMSavingsEveryMonth = autoGenerateWoMSavingsEveryMonth
        self.allowsPreviousMonthEditing = allowsPreviousMonthEditing
        self.monthBalancesPayload = monthBalancesPayload
        self.hiddenDailyAccountID = hiddenDailyAccountID
    }
}

@Model
final class Account {
    var id: UUID = UUID()
    var budgetID: UUID = UUID()
    var name: String = ""
    var role: AccountRole = AccountRole.regular
    var type: AccountType = AccountType.current
    var ownerParticipantID: String = ""

    init(
        id: UUID = UUID(),
        budgetID: UUID = UUID(),
        name: String,
        role: AccountRole,
        type: AccountType,
        ownerParticipantID: String = ""
    ) {
        self.id = id
        self.budgetID = budgetID
        self.name = name
        self.role = role
        self.type = type
        self.ownerParticipantID = ownerParticipantID
    }
}

@Model
final class PlannedItem {
    var id: UUID = UUID()
    var budgetID: UUID = UUID()
    var accountID: UUID = UUID()
    var monthKey: String = YearMonth(year: 2000, month: 1).rawValue
    var type: PlannedItemType = PlannedItemType.fixedDebit
    var source: PlannedItemSource = PlannedItemSource.manual
    var label: String = ""
    var matchingString: String?
    var amount: Decimal = 0
    var dueDay: Int?
    var dueText: String?
    var calendarContinuationPayload: String?
    var repeatDays: Int?
    var recurrenceID: UUID?
    var repeatMode: RepeatMode = RepeatMode.oneOff
    var importedPostedAt: Date?
    var isPaid: Bool = false
    var copiesToNextMonthAutomatically: Bool = true
    var notes: String = ""

    init(
        id: UUID = UUID(),
        budgetID: UUID = UUID(),
        accountID: UUID,
        monthKey: YearMonth,
        type: PlannedItemType,
        source: PlannedItemSource = .manual,
        label: String,
        amount: Decimal,
        matchingString: String? = nil,
        dueDay: Int? = nil,
        dueText: String? = nil,
        calendarContinuationPayload: String? = nil,
        repeatDays: Int? = nil,
        recurrenceID: UUID? = nil,
        repeatMode: RepeatMode? = nil,
        importedPostedAt: Date? = nil,
        isPaid: Bool = false,
        copiesToNextMonthAutomatically: Bool = true,
        notes: String = ""
    ) {
        self.id = id
        self.budgetID = budgetID
        self.accountID = accountID
        self.monthKey = monthKey.rawValue
        self.type = type
        self.source = source
        self.label = label
        self.matchingString = matchingString
        self.amount = amount
        self.dueDay = dueDay
        self.dueText = dueText
        self.calendarContinuationPayload = calendarContinuationPayload
        self.repeatDays = repeatDays
        self.recurrenceID = recurrenceID
        self.repeatMode = repeatMode ?? Self.inferredRepeatMode(dueDay: dueDay, repeatDays: repeatDays, copiesAutomatically: copiesToNextMonthAutomatically)
        self.importedPostedAt = importedPostedAt
        self.isPaid = isPaid
        self.copiesToNextMonthAutomatically = copiesToNextMonthAutomatically
        self.notes = notes
    }

    convenience init(
        id: UUID = UUID(),
        budgetID: UUID = UUID(),
        accountID: UUID,
        monthKey: YearMonth,
        type: PlannedItemType,
        source: PlannedItemSource = .manual,
        label: String,
        amount: Decimal,
        matchingString: String? = nil,
        dueDay: Int? = nil,
        dueText: String? = nil,
        repeatDays: Int? = nil,
        recurrenceID: UUID? = nil,
        repeatMode: RepeatMode? = nil,
        isPaid: Bool = false,
        notes: String = ""
    ) {
        self.init(
            id: id,
            budgetID: budgetID,
            accountID: accountID,
            monthKey: monthKey,
            type: type,
            source: source,
            label: label,
            amount: amount,
            matchingString: matchingString,
            dueDay: dueDay,
            dueText: dueText,
            repeatDays: repeatDays,
            recurrenceID: recurrenceID,
            repeatMode: repeatMode,
            isPaid: isPaid,
            copiesToNextMonthAutomatically: true,
            notes: notes
        )
    }

    private static func inferredRepeatMode(dueDay: Int?, repeatDays: Int?, copiesAutomatically: Bool) -> RepeatMode {
        if repeatDays != nil { return .periodic }
        if dueDay != nil && copiesAutomatically { return .calendar }
        return .oneOff
    }

    var resolvedMonthKey: YearMonth? {
        YearMonth(rawValue: monthKey)
    }

    var calendarContinuationTemplate: CalendarRepeatTemplate? {
        calendarContinuationPayload.flatMap(CalendarRepeatTemplate.init(payload:))
    }

    // A one-off exception keeps the original calendar definition for the following month.
    var resumesCalendarRepeatNextMonth: Bool {
        repeatMode == .oneOff && calendarContinuationTemplate != nil
    }

    static func automaticallyCopiedItems(from items: [PlannedItem]) -> [PlannedItem] {
        items.filter { $0.repeatMode != .oneOff || $0.resumesCalendarRepeatNextMonth }
    }

    static func everyNDaysOccurrences(
        from anchor: PlannedItem,
        in month: YearMonth,
        paydayDay: Int = 1,
        calendar: Calendar = .current
    ) -> [PlannedItem] {
        guard let repeatDays = anchor.repeatDays,
              repeatDays > 0,
              let anchorDate = concreteDate(for: anchor, paydayDay: paydayDay, calendar: calendar),
              let budgetRange = budgetMonthRange(for: month, paydayDay: paydayDay, calendar: calendar) else {
            return []
        }

        var date = anchorDate
        var occurrences: [PlannedItem] = []
        while let nextDate = calendar.date(byAdding: .day, value: repeatDays, to: date),
              nextDate < budgetRange.end {
            date = nextDate
            guard date >= budgetRange.start else { continue }

            let occurrence = copied(from: anchor, into: month)
            occurrence.dueDay = calendar.component(.day, from: date)
            occurrence.repeatDays = repeatDays
            occurrence.recurrenceID = anchor.recurrenceID
            occurrences.append(occurrence)
        }
        return occurrences
    }

    static func periodicOccurrences(
        from history: [PlannedItem],
        into month: YearMonth,
        paydayDay: Int = 1,
        calendar: Calendar = .current
    ) -> [PlannedItem] {
        guard let budgetRange = budgetMonthRange(for: month, paydayDay: paydayDay, calendar: calendar) else { return [] }
        let periodic = history.filter { $0.repeatMode == .periodic && ($0.repeatDays ?? 0) > 0 && $0.recurrenceID != nil }
        var results: [PlannedItem] = []

        for group in Dictionary(grouping: periodic, by: { $0.recurrenceID! }).values {
            guard let latest = group.max(by: {
                (concreteDate(for: $0, paydayDay: paydayDay, calendar: calendar) ?? .distantPast) <
                    (concreteDate(for: $1, paydayDay: paydayDay, calendar: calendar) ?? .distantPast)
            }), let repeatDays = latest.repeatDays,
            var date = concreteDate(for: latest, paydayDay: paydayDay, calendar: calendar) else { continue }

            while let nextDate = calendar.date(byAdding: .day, value: repeatDays, to: date), nextDate < budgetRange.end {
                date = nextDate
                guard date >= budgetRange.start else { continue }
                let occurrence = copied(from: latest, into: month)
                occurrence.dueDay = calendar.component(.day, from: date)
                occurrence.repeatMode = .periodic
                results.append(occurrence)
            }
        }

        return results.sorted { ($0.dueDay ?? 0) < ($1.dueDay ?? 0) }
    }

    static func copiedItems(
        from sourceItems: [PlannedItem],
        into month: YearMonth,
        paydayDay: Int = 1,
        calendar: Calendar = .current
    ) -> [PlannedItem] {
        let eligibleItems = automaticallyCopiedItems(from: sourceItems)
        var copiedItems: [PlannedItem] = []
        var handledRecurrenceIDs = Set<UUID>()

        for item in eligibleItems {
            guard let recurrenceID = item.recurrenceID,
                  let repeatDays = item.repeatDays,
                  repeatDays > 0,
                  concreteDate(for: item, paydayDay: paydayDay, calendar: calendar) != nil else {
                copiedItems.append(copied(from: item, into: month))
                continue
            }
            guard handledRecurrenceIDs.insert(recurrenceID).inserted else { continue }

            let series = eligibleItems.filter {
                $0.recurrenceID == recurrenceID &&
                    $0.repeatDays == repeatDays &&
                    concreteDate(for: $0, paydayDay: paydayDay, calendar: calendar) != nil
            }
            guard let latest = series.max(by: {
                concreteDate(for: $0, paydayDay: paydayDay, calendar: calendar)! < concreteDate(for: $1, paydayDay: paydayDay, calendar: calendar)!
            }) else { continue }
            copiedItems.append(contentsOf: everyNDaysOccurrences(from: latest, in: month, paydayDay: paydayDay, calendar: calendar))
        }

        return copiedItems
    }

    static func copied(from item: PlannedItem, into monthKey: YearMonth) -> PlannedItem {
        let template = item.calendarContinuationTemplate
        return PlannedItem(
            id: UUID(),
            budgetID: item.budgetID,
            accountID: item.accountID,
            monthKey: monthKey,
            type: template?.type ?? item.type,
            source: .copiedFromPreviousMonth,
            label: template?.label ?? item.label,
            amount: template?.amount ?? item.amount,
            matchingString: template == nil ? item.matchingString : template?.matchingString,
            dueDay: template == nil ? item.dueDay : template?.dueDay,
            dueText: template == nil ? item.dueText : template?.dueText,
            repeatDays: template == nil ? item.repeatDays : nil,
            recurrenceID: template == nil ? item.recurrenceID : nil,
            repeatMode: item.resumesCalendarRepeatNextMonth ? .calendar : item.repeatMode,
            importedPostedAt: template == nil ? item.importedPostedAt : template?.importedPostedAt,
            isPaid: false,
            copiesToNextMonthAutomatically: template == nil ? item.copiesToNextMonthAutomatically : true,
            notes: template?.notes ?? item.notes
        )
    }

    private static func concreteDate(for item: PlannedItem, paydayDay: Int, calendar: Calendar) -> Date? {
        guard let month = YearMonth(rawValue: item.monthKey),
              let dueDay = item.dueDay else { return nil }
        let paydayDate = paydayDate(in: month, paydayDay: paydayDay, calendar: calendar)
        let dueMonth = paydayDay <= 1 ? month : (dueDay >= calendar.component(.day, from: paydayDate)
            ? previousMonth(of: month)
            : month)
        let monthStart = calendar.date(from: DateComponents(year: dueMonth.year, month: dueMonth.month, day: 1))
        let daysInMonth = monthStart.flatMap { calendar.range(of: .day, in: .month, for: $0)?.count } ?? 31
        return calendar.date(from: DateComponents(year: dueMonth.year, month: dueMonth.month, day: min(dueDay, daysInMonth)))
    }

    private static func budgetMonthRange(
        for month: YearMonth,
        paydayDay: Int,
        calendar: Calendar
    ) -> (start: Date, end: Date)? {
        if paydayDay <= 1 {
            let start = paydayDate(in: month, paydayDay: 1, calendar: calendar)
            let end = paydayDate(in: nextMonth(of: month), paydayDay: 1, calendar: calendar)
            return (start, end)
        }
        let start = paydayDate(in: previousMonth(of: month), paydayDay: paydayDay, calendar: calendar)
        let end = paydayDate(in: month, paydayDay: paydayDay, calendar: calendar)
        return start < end ? (start, end) : nil
    }

    private static func paydayDate(in month: YearMonth, paydayDay: Int, calendar: Calendar) -> Date {
        let monthStart = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1))!
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)!.count
        return calendar.date(
            from: DateComponents(year: month.year, month: month.month, day: min(max(paydayDay, 1), daysInMonth))
        )!
    }

    private static func previousMonth(of month: YearMonth) -> YearMonth {
        month.month == 1 ? YearMonth(year: month.year - 1, month: 12) : YearMonth(year: month.year, month: month.month - 1)
    }

    private static func nextMonth(of month: YearMonth) -> YearMonth {
        month.month == 12 ? YearMonth(year: month.year + 1, month: 1) : YearMonth(year: month.year, month: month.month + 1)
    }
}

@Model
final class Transaction {
    var id: UUID = UUID()
    var budgetID: UUID = UUID()
    var accountID: UUID = UUID()
    var monthKey: String = YearMonth(year: 2000, month: 1).rawValue
    var amount: Decimal = 0
    var note: String = ""
    var sourceKind: String = ""
    var sourceExternalTransactionID: String = ""
    var sourcePostedAt: Date?

    init(
        id: UUID = UUID(),
        budgetID: UUID = UUID(),
        accountID: UUID,
        monthKey: YearMonth,
        amount: Decimal,
        note: String = "",
        sourceKind: String = "",
        sourceExternalTransactionID: String = "",
        sourcePostedAt: Date? = nil
    ) {
        self.id = id
        self.budgetID = budgetID
        self.accountID = accountID
        self.monthKey = monthKey.rawValue
        self.amount = amount
        self.note = note
        self.sourceKind = sourceKind
        self.sourceExternalTransactionID = sourceExternalTransactionID
        self.sourcePostedAt = sourcePostedAt
    }
}

@Model
final class ImportedTransactionRecord {
    var id: UUID = UUID()
    var budgetID: UUID = UUID()
    var accountID: UUID = UUID()
    var sourceKind: String = ""
    var sourceAccountIdentifier: String = ""
    var externalTransactionID: String = ""
    var postedAt: Date = Date()
    var amount: Decimal = 0
    var payee: String = ""
    var transactionType: String = ""
    var rawSourcePayload: String = ""
    var importedAt: Date = Date()
    var appliedPlannedItemID: UUID?
    var createdTransactionID: UUID?

    init(
        id: UUID = UUID(),
        budgetID: UUID = UUID(),
        accountID: UUID,
        sourceKind: String,
        sourceAccountIdentifier: String,
        externalTransactionID: String,
        postedAt: Date,
        amount: Decimal,
        payee: String,
        transactionType: String,
        rawSourcePayload: String,
        importedAt: Date = Date(),
        appliedPlannedItemID: UUID? = nil,
        createdTransactionID: UUID? = nil
    ) {
        self.id = id
        self.budgetID = budgetID
        self.accountID = accountID
        self.sourceKind = sourceKind
        self.sourceAccountIdentifier = sourceAccountIdentifier
        self.externalTransactionID = externalTransactionID
        self.postedAt = postedAt
        self.amount = amount
        self.payee = payee
        self.transactionType = transactionType
        self.rawSourcePayload = rawSourcePayload
        self.importedAt = importedAt
        self.appliedPlannedItemID = appliedPlannedItemID
        self.createdTransactionID = createdTransactionID
    }
}

@Model
final class WheelOfMoneyItem {
    var id: UUID = UUID()
    var budgetID: UUID = UUID()
    var title: String = ""
    var amount: Decimal = 0
    var month: Int = WheelOfMoneyMonth.january.rawValue
    var isPaid: Bool = false
    var notes: String = ""
    var isAutoGeneratedSavingsEntry: Bool = false

    init(
        id: UUID = UUID(),
        budgetID: UUID,
        title: String,
        amount: Decimal,
        month: Int,
        isPaid: Bool = false,
        notes: String = "",
        isAutoGeneratedSavingsEntry: Bool = false
    ) {
        self.id = id
        self.budgetID = budgetID
        self.title = title
        self.amount = amount
        self.month = month
        self.isPaid = isPaid
        self.notes = notes
        self.isAutoGeneratedSavingsEntry = isAutoGeneratedSavingsEntry
    }
}
