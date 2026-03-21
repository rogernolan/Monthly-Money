import Foundation

public struct ImportedTransactionReconciliationResult: Equatable {
    public let matchedCount: Int
    public let createdCount: Int
    public let skippedCount: Int

    public init(matchedCount: Int, createdCount: Int, skippedCount: Int = 0) {
        self.matchedCount = matchedCount
        self.createdCount = createdCount
        self.skippedCount = skippedCount
    }
}

public final class ImportedTransactionReconciliationService {
    private let repository: AccountRepository
    private let calendar: Calendar
    private static let amountTolerance = Decimal(string: "0.05")!
    private static let dayTolerance = 3

    public init(
        repository: AccountRepository,
        calendar: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(secondsFromGMT: 0)!
            return calendar
        }()
    ) {
        self.repository = repository
        self.calendar = calendar
    }

    @discardableResult
    public func reconcile(account: Account) throws -> ImportedTransactionReconciliationResult {
        let importedRecords = try repository.importedTransactionRecords(accountIDs: [account.id])
        return try reconcile(account: account, importedRecords: importedRecords)
    }

    @discardableResult
    public func reconcile(
        account: Account,
        importedRecordIDs: [UUID]
    ) throws -> ImportedTransactionReconciliationResult {
        let importedRecordIDSet = Set(importedRecordIDs)
        let importedRecords = try repository.importedTransactionRecords(accountIDs: [account.id])
            .filter { importedRecordIDSet.contains($0.id) }
        return try reconcile(account: account, importedRecords: importedRecords)
    }

    private func reconcile(
        account: Account,
        importedRecords: [ImportedTransactionRecord]
    ) throws -> ImportedTransactionReconciliationResult {
        let monthKeys = Set(importedRecords.map { monthKey(for: $0.postedAt).rawValue })
        let monthItems = try repository.plannedItems(for: nil)
            .filter { $0.accountID == account.id }
            .filter { monthKeys.contains($0.monthKey) }

        var matchedCount = 0
        var createdCount = 0

        for record in importedRecords {
            if try reconcileExistingTransactionLink(for: record) {
                continue
            }

            if try reconcileLinkedPlannedItem(for: record) {
                matchedCount += 1
                continue
            }

            if try reconcilePlannedItem(for: record, using: monthItems) {
                matchedCount += 1
                continue
            }

            if try reconcileImportedUnplannedItem(for: record, account: account) {
                createdCount += 1
            }
        }

        return ImportedTransactionReconciliationResult(
            matchedCount: matchedCount,
            createdCount: createdCount
        )
    }

    private func reconcileExistingTransactionLink(for record: ImportedTransactionRecord) throws -> Bool {
        if let createdTransactionID = record.createdTransactionID,
           try transactionExists(id: createdTransactionID, accountID: record.accountID) {
            return true
        }

        if let existing = try findExistingTransaction(for: record) {
            record.createdTransactionID = existing.id
            try repository.saveImportedTransactionRecord(record)
            return true
        }

        return false
    }

    private func reconcileLinkedPlannedItem(for record: ImportedTransactionRecord) throws -> Bool {
        guard let appliedPlannedItemID = record.appliedPlannedItemID,
              let linkedItem = try repository.plannedItem(id: appliedPlannedItemID) else {
            return false
        }

        linkedItem.isPaid = true
        linkedItem.amount = abs(record.amount)
        try repository.savePlannedItem(linkedItem)

        record.appliedPlannedItemID = linkedItem.id
        try repository.saveImportedTransactionRecord(record)
        return true
    }

    private func reconcilePlannedItem(for record: ImportedTransactionRecord, using plannedItems: [PlannedItem]) throws -> Bool {
        let monthKey = monthKey(for: record.postedAt)
        let candidates = plannedItems
            .filter { $0.accountID == record.accountID }
            .filter { $0.monthKey == monthKey.rawValue }
            .filter { !$0.isPaid }
            .filter { Self.matches(importedRecord: record, plannedItem: $0, calendar: calendar) }

        guard let match = Self.bestMatch(from: candidates, importedRecord: record, calendar: calendar) else {
            return false
        }

        match.isPaid = true
        match.amount = abs(record.amount)
        try repository.savePlannedItem(match)

        record.appliedPlannedItemID = match.id
        try repository.saveImportedTransactionRecord(record)
        return true
    }

    private func reconcileImportedUnplannedItem(for record: ImportedTransactionRecord, account: Account) throws -> Bool {
        let plannedItem = PlannedItem(
            budgetID: account.budgetID,
            accountID: account.id,
            monthKey: monthKey(for: record.postedAt),
            type: Self.plannedItemType(for: record.amount),
            source: .importedUnplanned,
            label: record.payee,
            amount: abs(record.amount),
            matchingString: record.payee,
            isPaid: true,
            copiesToNextMonthAutomatically: false
        )
        try repository.createPlannedItem(plannedItem)

        record.appliedPlannedItemID = plannedItem.id
        try repository.saveImportedTransactionRecord(record)
        return true
    }

    private func transactionExists(id: UUID, accountID: UUID) throws -> Bool {
        try repository.transactions(accountIDs: [accountID]).contains { $0.id == id }
    }

    private func findExistingTransaction(for record: ImportedTransactionRecord) throws -> Transaction? {
        try repository.transactions(accountIDs: [record.accountID]).first { transaction in
            guard transaction.sourceKind == record.sourceKind else { return false }
            if !record.externalTransactionID.isEmpty {
                return transaction.sourceExternalTransactionID == record.externalTransactionID
            }
            return transaction.sourcePostedAt == record.postedAt && transaction.amount == record.amount
        }
    }

    private func monthKey(for date: Date) -> YearMonth {
        let components = calendar.dateComponents([.year, .month], from: date)
        return YearMonth(year: components.year ?? 2000, month: components.month ?? 1)
    }

    private static func matches(importedRecord: ImportedTransactionRecord, plannedItem: PlannedItem, calendar: Calendar) -> Bool {
        guard textMatches(importedPayee: importedRecord.payee, plannedItem: plannedItem) else { return false }
        guard amountMatches(importedAmount: abs(importedRecord.amount), plannedItem: plannedItem) else { return false }
        guard dueDayMatches(importedDate: importedRecord.postedAt, plannedItem: plannedItem, calendar: calendar) else { return false }
        return true
    }

    private static func bestMatch(
        from plannedItems: [PlannedItem],
        importedRecord: ImportedTransactionRecord,
        calendar: Calendar
    ) -> PlannedItem? {
        let sorted = plannedItems.sorted { lhs, rhs in
            let lhsScore = matchScore(importedRecord: importedRecord, plannedItem: lhs, calendar: calendar)
            let rhsScore = matchScore(importedRecord: importedRecord, plannedItem: rhs, calendar: calendar)
            if lhsScore.amountDelta != rhsScore.amountDelta {
                return lhsScore.amountDelta < rhsScore.amountDelta
            }
            if lhsScore.dayDelta != rhsScore.dayDelta {
                return lhsScore.dayDelta < rhsScore.dayDelta
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        return sorted.first
    }

    private static func matchScore(
        importedRecord: ImportedTransactionRecord,
        plannedItem: PlannedItem,
        calendar: Calendar
    ) -> (amountDelta: Decimal, dayDelta: Int) {
        (
            amountDelta: abs(abs(importedRecord.amount) - plannedItem.amount),
            dayDelta: abs(dayComponent(for: importedRecord.postedAt, calendar: calendar) - (plannedItem.dueDay ?? Int.max))
        )
    }

    private static func plannedMatcher(for plannedItem: PlannedItem) -> String {
        let trimmed = plannedItem.matchingString?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? plannedItem.label : trimmed
    }

    private static func textMatches(importedPayee: String, plannedItem: PlannedItem) -> Bool {
        let imported = normalize(importedPayee)
        let matcher = normalize(plannedMatcher(for: plannedItem))
        guard !imported.isEmpty, !matcher.isEmpty else { return false }
        return imported.contains(matcher)
    }

    private static func amountMatches(importedAmount: Decimal, plannedItem: PlannedItem) -> Bool {
        let delta = abs(importedAmount - plannedItem.amount)
        let allowedDelta = plannedItem.amount * amountTolerance
        return delta <= allowedDelta
    }

    private static func dueDayMatches(importedDate: Date, plannedItem: PlannedItem, calendar: Calendar) -> Bool {
        guard let plannedDueDay = plannedItem.dueDay else { return false }
        let importedDay = dayComponent(for: importedDate, calendar: calendar)
        return abs(importedDay - plannedDueDay) <= dayTolerance
    }

    private static func dayComponent(for date: Date, calendar: Calendar) -> Int {
        calendar.component(.day, from: date)
    }

    private static func plannedItemType(for amount: Decimal) -> PlannedItemType {
        amount < 0 ? .fixedDebit : .credit
    }

    private static func normalize(_ string: String) -> String {
        string
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }
}
