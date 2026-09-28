import Foundation
import SwiftUI
import Combine
import CloudKit

enum SettingsSharingStatus: Equatable {
    case localOnly
    case sharedAvailable
    case sharedByYou
    case sharedWithYou
}

enum WheelOfMoneyFilter: String, CaseIterable, Equatable {
    case all
    case pending
}

struct WheelOfMoneyMetrics: Equatable {
    let annualTotal: Decimal
    let monthlyAverage: Decimal
    let pendingTotal: Decimal
    let remainingAverage: Decimal

    var remainingAverageExceedsMonthlyAverage: Bool {
        remainingAverage > monthlyAverage
    }
}

enum WheelOfMoneyFilterRules {
    static func filteredItems(_ items: [WheelOfMoneyItem], for filter: WheelOfMoneyFilter) -> [WheelOfMoneyItem] {
        switch filter {
        case .all:
            return items
        case .pending:
            return items.filter { !$0.isPaid }
        }
    }
}

enum WheelOfMoneyCalculator {
    static func metrics(items: [WheelOfMoneyItem], currentMonth: Int) -> WheelOfMoneyMetrics {
        let annualTotal = items.reduce(Decimal.zero) { $0 + $1.amount }
        let monthlyAverage = annualTotal / Decimal(12)
        let pendingTotal = items.filter { !$0.isPaid }.reduce(Decimal.zero) { $0 + $1.amount }
        let remainingMonths = max(1, 12 - min(max(currentMonth, 1), 12) + 1)
        let remainingAverage = pendingTotal / Decimal(remainingMonths)
        return WheelOfMoneyMetrics(
            annualTotal: annualTotal,
            monthlyAverage: monthlyAverage,
            pendingTotal: pendingTotal,
            remainingAverage: remainingAverage
        )
    }
}

struct SettingsSharingPresentation: Equatable {
    let status: SettingsSharingStatus

    var statusText: String {
        switch status {
        case .localOnly:
            return "Local only"
        case .sharedAvailable:
            return "Shared budget available"
        case .sharedByYou:
            return "Shared by you"
        case .sharedWithYou:
            return "Shared with you"
        }
    }

    var isShareButtonEnabled: Bool {
        status == .localOnly || status == .sharedByYou
    }

    var showsUnshareButton: Bool {
        status == .sharedByYou
    }

    var note: String? {
        switch status {
        case .localOnly:
            return nil
        case .sharedAvailable:
            return "Open the shared budget from the overwrite prompt when you're ready."
        case .sharedByYou, .sharedWithYou:
            return nil
        }
    }
}

typealias ShareBudgetAction = (AccountRepository) async throws -> BudgetShareResult
typealias CurrentParticipantIDProvider = () async -> String
typealias VerifyBudgetUnsharedAction = (AccountRepository, UUID) async throws -> Bool

struct PendingSharedBudgetAdoption: Equatable {
    let budgetID: UUID
    let budgetName: String
}

enum DailyOFXImportError: LocalizedError, Equatable {
    case missingLedgerBalance
    case dailyBudgetAccountUnavailable

    var errorDescription: String? {
        switch self {
        case .missingLedgerBalance:
            return "The OFX file does not include a ledger balance, so the daily balance could not be updated."
        case .dailyBudgetAccountUnavailable:
            return "Enable \"Use separate account for daily budget\" before importing to the daily account."
        }
    }
}

private struct PersistedMonthBalances: Codable, Equatable {
    var openingBalances: [String: String]
    var primaryBankBalances: [String: String]
    var dailyBudgetSeparateAccountBalanceOverride: String?

    static let empty = PersistedMonthBalances(
        openingBalances: [:],
        primaryBankBalances: [:],
        dailyBudgetSeparateAccountBalanceOverride: nil
    )
}

private enum PersistedMonthBalancesCodec {
    static func decode(_ payload: String) -> PersistedMonthBalances {
        guard let data = payload.data(using: .utf8),
              let decoded = try? JSONDecoder().decode(PersistedMonthBalances.self, from: data) else {
            return .empty
        }
        return decoded
    }

    static func encode(
        openingBalances: [String: Decimal],
        primaryBankBalances: [String: Decimal],
        dailyBudgetSeparateAccountBalanceOverride: Decimal?
    ) -> String {
        let payload = PersistedMonthBalances(
            openingBalances: openingBalances.mapValues { NSDecimalNumber(decimal: $0).stringValue },
            primaryBankBalances: primaryBankBalances.mapValues { NSDecimalNumber(decimal: $0).stringValue },
            dailyBudgetSeparateAccountBalanceOverride: dailyBudgetSeparateAccountBalanceOverride.map {
                NSDecimalNumber(decimal: $0).stringValue
            }
        )
        guard let data = try? JSONEncoder().encode(payload),
              let json = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return json
    }

    static func decimalMap(from values: [String: String]) -> [String: Decimal] {
        values.reduce(into: [:]) { result, entry in
            result[entry.key] = Decimal(string: entry.value) ?? 0
        }
    }
}

struct DailyBudgetCycleMetrics: Equatable {
    let previousPayday: Date
    let nextPayday: Date
    let cycleDays: Int
    let elapsedDaysInCycle: Int
    let remainingDaysToPayday: Int
    let dailyBudget: Decimal
    let expectedBalanceToday: Decimal
    let aheadBehind: Decimal
    let currentDailyBudget: Decimal
}

struct DailyBalanceChartPoint: Identifiable, Equatable {
    let date: Date
    let balance: Decimal

    var id: Date { date }

    var balanceValue: Double {
        NSDecimalNumber(decimal: balance).doubleValue
    }
}

private enum DailyBudgetCalendarProvider {
    static var fixedGregorianGMT: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}

enum DailyBudgetCycleCalculator {
    static func cycleBoundaries(
        today: Date,
        paydayDay: Int,
        calendar: Calendar
    ) -> (previousPayday: Date, nextPayday: Date) {
        let normalizedToday = calendar.startOfDay(for: today)
        let currentMonthPayday = paydayDate(
            relativeTo: normalizedToday,
            monthOffset: 0,
            paydayDay: paydayDay,
            calendar: calendar
        )

        if normalizedToday >= currentMonthPayday {
            return (
                previousPayday: currentMonthPayday,
                nextPayday: paydayDate(
                    relativeTo: normalizedToday,
                    monthOffset: 1,
                    paydayDay: paydayDay,
                    calendar: calendar
                )
            )
        }

        return (
            previousPayday: paydayDate(
                relativeTo: normalizedToday,
                monthOffset: -1,
                paydayDay: paydayDay,
                calendar: calendar
            ),
            nextPayday: currentMonthPayday
        )
    }

    static func metrics(
        today: Date,
        paydayDay: Int,
        budget: Decimal,
        currentBalance: Decimal,
        calendar: Calendar
    ) -> DailyBudgetCycleMetrics {
        let boundaries = cycleBoundaries(
            today: today,
            paydayDay: paydayDay,
            calendar: calendar
        )
        let previousPayday = boundaries.previousPayday
        let nextPayday = boundaries.nextPayday
        let normalizedToday = calendar.startOfDay(for: today)

        let cycleDays = calendar.dateComponents([.day], from: previousPayday, to: nextPayday).day ?? 1
        let elapsedDays = calendar.dateComponents([.day], from: previousPayday, to: normalizedToday).day ?? 0
        let remainingDays = max(calendar.dateComponents([.day], from: normalizedToday, to: nextPayday).day ?? 1, 1)
        let dailyBudget = budget / Decimal(max(cycleDays, 1))
        let expectedBalanceToday = budget - (dailyBudget * Decimal(elapsedDays))
        let aheadBehind = currentBalance - expectedBalanceToday
        let currentDailyBudget = currentBalance / Decimal(remainingDays)

        return DailyBudgetCycleMetrics(
            previousPayday: previousPayday,
            nextPayday: nextPayday,
            cycleDays: cycleDays,
            elapsedDaysInCycle: elapsedDays,
            remainingDaysToPayday: remainingDays,
            dailyBudget: dailyBudget,
            expectedBalanceToday: expectedBalanceToday,
            aheadBehind: aheadBehind,
            currentDailyBudget: currentDailyBudget
        )
    }

    private static func paydayDate(
        relativeTo date: Date,
        monthOffset: Int,
        paydayDay: Int,
        calendar: Calendar
    ) -> Date {
        let shiftedMonth = calendar.date(byAdding: .month, value: monthOffset, to: date) ?? date
        let monthStart = calendar.date(from: calendar.dateComponents([.year, .month], from: shiftedMonth)) ?? shiftedMonth
        let daysInMonth = calendar.range(of: .day, in: .month, for: monthStart)?.count ?? 31
        let clampedDay = min(max(paydayDay, 1), daysInMonth)
        return calendar.date(
            byAdding: .day,
            value: clampedDay - 1,
            to: monthStart
        ) ?? monthStart
    }
}

enum DailyBalanceChartCalculator {
    static func points(
        currentBalance: Decimal,
        today: Date,
        paydayDay: Int,
        transactions: [Transaction],
        calendar: Calendar
    ) -> [DailyBalanceChartPoint] {
        let boundaries = DailyBudgetCycleCalculator.cycleBoundaries(
            today: today,
            paydayDay: paydayDay,
            calendar: calendar
        )
        let cycleStart = calendar.startOfDay(for: boundaries.previousPayday)
        let cycleEnd = calendar.startOfDay(for: today)
        let netTransactionsByDay = transactions.reduce(into: [Date: Decimal]()) { result, transaction in
            guard let postedAt = transaction.sourcePostedAt else { return }
            let day = calendar.startOfDay(for: postedAt)
            guard day >= cycleStart, day <= cycleEnd else { return }
            result[day, default: .zero] += transaction.amount
        }

        var runningBalance = currentBalance
        var day = cycleEnd
        var points: [DailyBalanceChartPoint] = []

        while day >= cycleStart {
            points.append(DailyBalanceChartPoint(date: day, balance: runningBalance))
            runningBalance -= netTransactionsByDay[day] ?? .zero
            guard let previousDay = calendar.date(byAdding: .day, value: -1, to: day) else {
                break
            }
            day = calendar.startOfDay(for: previousDay)
        }

        return points.reversed()
    }
}

@MainActor
final class AppState: ObservableObject {
    static let legacyOwnerParticipantID = "owner"

    @Published var selectedMonth: YearMonth
    @Published private(set) var isSharingBudget = false
    @Published private(set) var sharingErrorMessage: String?
    @Published private(set) var pendingSharedBudgetAdoption: PendingSharedBudgetAdoption?
    @Published private(set) var pendingBudgetShareResult: BudgetShareResult?

    @Published var openingBalances: [String: Decimal] = [:] {
        didSet { persistBudgetStateIfNeeded() }
    }
    @Published var primaryBankBalances: [String: Decimal] = [:] {
        didSet { persistBudgetStateIfNeeded() }
    }
    @Published var primaryBankName: String = "Primary bank"

    @Published var weeklyEstimate: Decimal = 350
    @Published var weekendEstimate: Decimal = 20
    @Published var minSuggestedLiving: Decimal = 1500
    @Published var livingBuffer: Decimal = 100

    @Published var includeCash = true
    @Published var includeFX = true
    @Published var cashBalance: Decimal = 0
    @Published var fxBalance: Decimal = 0
    @Published var paydayDay: Int = 1
    @Published private var explicitDailyBudgetSeparateAccountBalanceOverride: Decimal? {
        didSet { persistBudgetStateIfNeeded() }
    }

    @Published private(set) var accounts: [Account] = []
    @Published var monthItems: [PlannedItem] = []
    @Published var wheelOfMoneyItems: [WheelOfMoneyItem] = []
    @Published var wheelOfMoneyFilter: WheelOfMoneyFilter = .all

    private let repository: AccountRepository
    private let shareBudgetAction: ShareBudgetAction
    private let currentParticipantIDProvider: CurrentParticipantIDProvider
    private let verifyBudgetUnsharedAction: VerifyBudgetUnsharedAction
    private let dailyBudgetWatchSnapshotSyncer: DailyBudgetWatchSnapshotSyncing
    private let dailyBudgetWidgetSnapshotSyncer: DailyBudgetWidgetSnapshotSyncing
    private let nowProvider: () -> Date
    private var currentParticipantID: String
    private var isHydratingPersistedBudgetState = false
    private var dismissedSharedBudgetAdoptionIDs: Set<UUID> = []
    init(
        repository: AccountRepository,
        currentParticipantIDProvider: @escaping CurrentParticipantIDProvider = {
            await CurrentParticipantIdentity.resolve()
        },
        verifyBudgetUnsharedAction: @escaping VerifyBudgetUnsharedAction = { repository, budgetID in
            try !repository.hasActiveShare(for: budgetID)
        },
        shareBudgetAction: @escaping ShareBudgetAction = { repository in
            let sharedBudget = try BudgetSharingService(repository: repository).shareBudget(participantsSelection: [])
            return try await BudgetShareCoordinator(repository: repository).prepareShareResult(for: sharedBudget)
        },
        dailyBudgetWatchSnapshotSyncer: DailyBudgetWatchSnapshotSyncing? = nil,
        dailyBudgetWidgetSnapshotSyncer: DailyBudgetWidgetSnapshotSyncing? = nil,
        nowProvider: @escaping () -> Date = Date.init
    ) {
        self.repository = repository
        self.currentParticipantIDProvider = currentParticipantIDProvider
        self.verifyBudgetUnsharedAction = verifyBudgetUnsharedAction
        self.currentParticipantID = Self.legacyOwnerParticipantID
        self.shareBudgetAction = shareBudgetAction
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        self.dailyBudgetWatchSnapshotSyncer = dailyBudgetWatchSnapshotSyncer
            ?? (isRunningTests ? NoOpDailyBudgetWatchSnapshotSyncer() : DailyBudgetWatchSnapshotSyncer.shared)
        self.dailyBudgetWidgetSnapshotSyncer = dailyBudgetWidgetSnapshotSyncer
            ?? (isRunningTests ? NoOpDailyBudgetWidgetSnapshotSyncer() : DailyBudgetWidgetSnapshotSyncer.shared)
        self.nowProvider = nowProvider
        let now = nowProvider()
        let calendar = Calendar.current
        self.selectedMonth = YearMonth(
            year: calendar.component(.year, from: now),
            month: calendar.component(.month, from: now)
        )
        do {
            try loadPersistedBudgetState()
        } catch {
            print("Initial budget state load failed: \(error)")
        }
    }

    func bootstrapIfNeeded() async {
        do {
            currentParticipantID = await currentParticipantIDProvider()
            try await waitForInitialCloudImportIfNeeded()
            _ = try repository.reconcileDuplicateLocalBudgets()
            try migrateLegacyOwnerIdentifiersIfNeeded()

            if try repository.accounts().isEmpty {
                _ = try repository.createAccount(
                    name: "Nationwide",
                    role: .regular,
                    type: .current,
                    ownerParticipantID: currentParticipantID
                )
            }
            selectedMonth = currentYearMonth
            try refresh()
        } catch {
            print("Bootstrap failed: \(error)")
        }
    }

    private func waitForInitialCloudImportIfNeeded() async throws {
        let initialAccountCount = try repository.accounts().count
        guard AppBootstrapRules.shouldWaitForInitialCloudImport(
            privateStoreSyncMode: repository.privateStoreSyncMode,
            accountCount: initialAccountCount
        ) else {
            return
        }

        try await repository.awaitInitialPrivateCloudImport(timeout: .seconds(10))
    }

    func refresh() throws {
        try restoreLocalBudgetIfNeeded()
        try migrateBalanceLastUpdatedTimestampsIfNeeded()
        try ensureHiddenDailyAccountIfNeeded()
        try cleanupHiddenDailyImportedDataIfNeeded()
        try loadPersistedBudgetState()
        accounts = try repository.accounts()
        monthItems = try repository.plannedItems(for: selectedMonth)
        wheelOfMoneyItems = try repository.wheelOfMoneyItems()
        if let firstAccount = accounts.first {
            primaryBankName = firstAccount.name
        } else {
            primaryBankName = "Primary bank"
        }
        try updatePendingSharedBudgetAdoption()
        publishDailyBudgetWatchSnapshot()
        objectWillChange.send()
    }

    private func restoreLocalBudgetIfNeeded() throws {
        guard try repository.activeBudget() == nil else { return }

        _ = try repository.createAccount(
            name: "Nationwide",
            role: .regular,
            type: .current,
            ownerParticipantID: currentParticipantID
        )
    }

    private func ensureHiddenDailyAccountIfNeeded() throws {
        guard let budget = try repository.activeBudget(),
              budget.usesSeparateAccountForDailyBudget else {
            return
        }

        _ = try repository.ensureHiddenDailyAccount(for: budget)
    }

    private func cleanupHiddenDailyImportedDataIfNeeded() throws {
        guard let budget = try repository.activeBudget(),
              budget.usesSeparateAccountForDailyBudget,
              let hiddenAccount = try repository.hiddenDailyAccount(for: budget) else {
            return
        }

        let cycleBounds = currentDailyCycleDateRange()
        let transactions = try repository.transactions(accountIDs: [hiddenAccount.id])
        for transaction in transactions {
            guard let postedAt = transaction.sourcePostedAt else {
                try repository.deleteTransaction(id: transaction.id)
                continue
            }
            let day = Self.fixedDailyCycleCalendar.startOfDay(for: postedAt)
            guard day >= cycleBounds.startInclusive, day < cycleBounds.endExclusive else {
                try repository.deleteTransaction(id: transaction.id)
                continue
            }
        }

        let importedRecords = try repository.importedTransactionRecords(accountIDs: [hiddenAccount.id])
        for record in importedRecords {
            let day = Self.fixedDailyCycleCalendar.startOfDay(for: record.postedAt)
            guard day >= cycleBounds.startInclusive, day < cycleBounds.endExclusive else {
                try repository.deleteImportedTransactionRecord(id: record.id)
                continue
            }
        }
    }

    private func currentDailyCycleDateRange() -> (startInclusive: Date, endExclusive: Date) {
        let calendar = Self.fixedDailyCycleCalendar
        let boundaries = DailyBudgetCycleCalculator.cycleBoundaries(
            today: nowProvider(),
            paydayDay: dailyBudgetPaydayDay,
            calendar: calendar
        )
        return (
            startInclusive: calendar.startOfDay(for: boundaries.previousPayday),
            endExclusive: calendar.startOfDay(for: boundaries.nextPayday)
        )
    }

    var usesSeparateAccountForDailyBudget: Bool {
        get { (try? repository.activeBudget()?.usesSeparateAccountForDailyBudget) ?? false }
        set {
            do {
                guard canEditBudgetSettings else { return }
                guard let budget = try repository.activeBudget() else { return }
                budget.usesSeparateAccountForDailyBudget = newValue
                try repository.saveBudget(budget)
                try refresh()
            } catch {
                print("Update daily budget account setting failed: \(error)")
            }
        }
    }

    var autoGenerateWoMSavingsEveryMonth: Bool {
        get { (try? repository.activeBudget()?.autoGenerateWoMSavingsEveryMonth) ?? false }
        set {
            do {
                guard canEditBudgetSettings else { return }
                guard let budget = try repository.activeBudget() else { return }
                budget.autoGenerateWoMSavingsEveryMonth = newValue
                try repository.saveBudget(budget)
                try refresh()
            } catch {
                print("Update WoM savings generation setting failed: \(error)")
            }
        }
    }

    var allowsPreviousMonthEditing: Bool {
        get { (try? repository.activeBudget()?.allowsPreviousMonthEditing) ?? false }
        set {
            do {
                guard canEditBudgetSettings else { return }
                guard let budget = try repository.activeBudget() else { return }
                budget.allowsPreviousMonthEditing = newValue
                try repository.saveBudget(budget)
                try refresh()
            } catch {
                print("Update previous month editing setting failed: \(error)")
            }
        }
    }

    var persistedMonthBalancePayload: String {
        PersistedMonthBalancesCodec.encode(
            openingBalances: openingBalances,
            primaryBankBalances: primaryBankBalances,
            dailyBudgetSeparateAccountBalanceOverride: explicitDailyBudgetSeparateAccountBalanceOverride
        )
    }

    var dailyBudgetSeparateAccountBalance: Decimal {
        get { explicitDailyBudgetSeparateAccountBalanceOverride ?? derivedDailyBudgetSeparateAccountBalance }
        set {
            explicitDailyBudgetSeparateAccountBalanceOverride = newValue
            markDailyBalanceUpdatedIfNeeded()
            objectWillChange.send()
        }
    }

    var privateStoreSyncMode: StoreSyncMode {
        repository.privateStoreSyncMode
    }

    var sharedStoreSyncMode: StoreSyncMode {
        repository.sharedStoreSyncMode
    }

    var sharingStatus: SettingsSharingStatus {
        if let localBudget = try? repository.localBudget(),
           let sharedBudget = try? repository.sharedBudget(),
           sharedBudget.ownerParticipantID != currentParticipantID,
           sharedBudget.id != localBudget.id {
            return .sharedAvailable
        }

        guard let budget = try? repository.activeBudget() else { return .localOnly }
        guard budget.sharingState == .shared else { return .localOnly }
        return budget.ownerParticipantID == currentParticipantID ? .sharedByYou : .sharedWithYou
    }

    var sharingPresentation: SettingsSharingPresentation {
        SettingsSharingPresentation(status: sharingStatus)
    }

    var shouldShowSharedBudgetOverwriteAlert: Bool {
        pendingSharedBudgetAdoption != nil
    }

    var canEditBudgetSettings: Bool {
        switch sharingStatus {
        case .localOnly, .sharedAvailable, .sharedByYou:
            return true
        case .sharedWithYou:
            return false
        }
    }

    func shareBudget() async {
        guard !isSharingBudget else { return }
        isSharingBudget = true
        sharingErrorMessage = nil
        pendingBudgetShareResult = nil
        defer { isSharingBudget = false }

        do {
            pendingBudgetShareResult = try await shareBudgetAction(repository)
            try refresh()
        } catch {
            sharingErrorMessage = shareErrorMessage(for: error)
        }
    }

    func clearPendingBudgetSharePresentation() {
        pendingBudgetShareResult = nil
    }

    nonisolated static func loadImportedOFXFile(from url: URL) async throws -> Data {
        let data = try await Task.detached(priority: .userInitiated) {
            let didStartAccessing = url.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            return try Data(contentsOf: url)
        }.value
        print("[Import] loaded file '\(url.lastPathComponent)' (\(data.count) bytes)")
        return data
    }

    func importOFXData(
        _ data: Data,
        fileName: String,
        into accountID: UUID
    ) throws -> (importResult: ImportedTransactionImportResult, reconciliationResult: ImportedTransactionReconciliationResult) {
        let availableAccounts = try repository.accounts()
        guard let account = availableAccounts.first(where: { $0.id == accountID }) else {
            throw RepositoryError.accountNotFound
        }

        let statement = try NationwideOFXImporter().parse(data: data)
        let importResult = try ImportedTransactionService(repository: repository).import(
            statement: statement,
            sourceKind: ImportedTransactionService.nationwideOFXSourceKind,
            into: account
        )
        let reconciliationResult = try ImportedTransactionReconciliationService(repository: repository).reconcile(
            account: account,
            importedRecordIDs: importResult.insertedRecordIDs
        )
        applyImportedStatementBalanceIfPresent(statement)
        try markBalanceViewsUpdated(monthly: true, daily: !usesSeparateAccountForDailyBudget)
        try refresh()
        print(
            "[OFXImport] imported file '\(fileName)' into account '\(account.name)': parsed \(importResult.parsedCount), inserted \(importResult.insertedCount), skipped \(importResult.skippedCount), matched \(reconciliationResult.matchedCount), created planned items \(reconciliationResult.createdCount)"
        )
        return (importResult: importResult, reconciliationResult: reconciliationResult)
    }

    func importQIFData(
        _ data: Data,
        fileName: String,
        into accountID: UUID
    ) throws -> (importResult: ImportedTransactionImportResult, reconciliationResult: ImportedTransactionReconciliationResult) {
        let availableAccounts = try repository.accounts()
        guard let account = availableAccounts.first(where: { $0.id == accountID }) else {
            throw RepositoryError.accountNotFound
        }

        let statement = try MonzoQIFImporter().parse(data: data)
        let importResult = try ImportedTransactionService(repository: repository).import(
            statement: statement,
            sourceKind: ImportedTransactionService.monzoQIFSourceKind,
            into: account
        )
        let reconciliationResult = try ImportedTransactionReconciliationService(repository: repository).reconcile(
            account: account,
            importedRecordIDs: importResult.insertedRecordIDs
        )
        try markBalanceViewsUpdated(monthly: true, daily: !usesSeparateAccountForDailyBudget)
        try refresh()
        print(
            "[QIFImport] imported file '\(fileName)' into account '\(account.name)': parsed \(importResult.parsedCount), inserted \(importResult.insertedCount), skipped \(importResult.skippedCount), matched \(reconciliationResult.matchedCount), created planned items \(reconciliationResult.createdCount)"
        )
        return (importResult: importResult, reconciliationResult: reconciliationResult)
    }

    func importDailyOFXData(
        _ data: Data,
        fileName: String
    ) throws -> Decimal {
        guard let budget = try repository.activeBudget(),
              budget.usesSeparateAccountForDailyBudget else {
            throw DailyOFXImportError.dailyBudgetAccountUnavailable
        }

        try ensureHiddenDailyAccountIfNeeded()
        guard let hiddenAccount = try repository.hiddenDailyAccount(for: budget) else {
            throw DailyOFXImportError.dailyBudgetAccountUnavailable
        }

        let statement = try NationwideOFXImporter().parse(data: data)
        guard let ledgerBalance = statement.ledgerBalance else {
            throw DailyOFXImportError.missingLedgerBalance
        }

        let importResult = try ImportedTransactionService(repository: repository).import(
            statement: statement,
            sourceKind: ImportedTransactionService.nationwideOFXSourceKind,
            into: hiddenAccount
        )
        try createDailyImportedTransactions(
            for: hiddenAccount,
            importedRecordIDs: importResult.insertedRecordIDs
        )
        dailyBudgetSeparateAccountBalance = ledgerBalance
        try markDailyBalanceUpdated()
        try refresh()
        print(
            "[OFXImport] imported file '\(fileName)' into daily balance: ledger balance \(ledgerBalance)"
        )
        return ledgerBalance
    }

    func importDailyQIFData(
        _ data: Data,
        fileName: String
    ) throws -> DailyImportedStatementResult {
        guard let budget = try repository.activeBudget(),
              budget.usesSeparateAccountForDailyBudget else {
            throw DailyOFXImportError.dailyBudgetAccountUnavailable
        }

        try ensureHiddenDailyAccountIfNeeded()
        guard let hiddenAccount = try repository.hiddenDailyAccount(for: budget) else {
            throw DailyOFXImportError.dailyBudgetAccountUnavailable
        }

        let statement = try MonzoQIFImporter().parse(data: data)
        let filtered = filterStatementToCurrentDailyCycle(statement)
        let importResult = try ImportedTransactionService(repository: repository).import(
            statement: filtered.statement,
            sourceKind: ImportedTransactionService.monzoQIFSourceKind,
            into: hiddenAccount
        )
        try createDailyImportedTransactions(
            for: hiddenAccount,
            importedRecordIDs: importResult.insertedRecordIDs
        )
        try markDailyBalanceUpdated()
        try refresh()
        print(
            "[QIFImport] imported file '\(fileName)' into daily account: parsed \(importResult.parsedCount), inserted \(importResult.insertedCount), skipped \(importResult.skippedCount), ignored outside cycle \(filtered.ignoredOutsideCurrentCycleCount)"
        )
        return DailyImportedStatementResult(
            importResult: importResult,
            ignoredOutsideCurrentCycleCount: filtered.ignoredOutsideCurrentCycleCount
        )
    }

    private func applyImportedStatementBalanceIfPresent(_ statement: NationwideOFXStatement) {
        guard let ledgerBalance = statement.ledgerBalance else { return }
        primaryBankBalances[selectedMonth.rawValue] = ledgerBalance
    }

    private func filterStatementToCurrentDailyCycle(
        _ statement: ImportedAccountStatement
    ) -> (statement: ImportedAccountStatement, ignoredOutsideCurrentCycleCount: Int) {
        let calendar = Self.fixedDailyCycleCalendar
        let cycleBounds = currentDailyCycleDateRange()
        let filteredTransactions = statement.transactions.filter { transaction in
            let day = calendar.startOfDay(for: transaction.postedAt)
            return day >= cycleBounds.startInclusive && day < cycleBounds.endExclusive
        }

        return (
            statement: ImportedAccountStatement(
                accountIdentifier: statement.accountIdentifier,
                currencyCode: statement.currencyCode,
                statementStartDate: statement.statementStartDate,
                statementEndDate: statement.statementEndDate,
                ledgerBalance: statement.ledgerBalance,
                transactions: filteredTransactions
            ),
            ignoredOutsideCurrentCycleCount: max(0, statement.transactions.count - filteredTransactions.count)
        )
    }

    func sharingPresentationDidFail(message: String) {
        pendingBudgetShareResult = nil
        sharingErrorMessage = message
    }

    func handleBudgetShareStopped() async throws {
        guard let budget = try repository.localBudget() ?? repository.activeBudget() else {
            clearPendingBudgetSharePresentation()
            throw BudgetSharingError.budgetNotFound
        }
        let isUnshared = try await verifyBudgetUnsharedAction(repository, budget.id)
        guard isUnshared else {
            throw BudgetShareCoordinatorError.stopShareVerificationFailed
        }
        budget.sharingState = .local
        try repository.saveBudget(budget)
        clearPendingBudgetSharePresentation()
        try refresh()
    }

    func handleBudgetShareStoppedFromUI() async {
        do {
            try await handleBudgetShareStopped()
        } catch {
            sharingErrorMessage = shareErrorMessage(for: error)
        }
    }

    func acceptIncomingCloudKitShares(_ metadata: [CKShare.Metadata]) async {
        guard !metadata.isEmpty else { return }
        print("[ShareAccept] received \(metadata.count) share metadata item(s)")
        do {
            try await repository.acceptIncomingSharedBudgetInvitations(metadata)
            print("[ShareAccept] accepted invitations, refreshing app state")
            try refresh()
            print("[ShareAccept] accept flow completed")
        } catch {
            print("[ShareAccept] accept failed: \(error)")
            sharingErrorMessage = acceptSharedBudgetErrorMessage(for: error)
        }
    }

    func confirmSharedBudgetOverwrite() throws {
        guard pendingSharedBudgetAdoption != nil else { return }
        guard let localBudget = try repository.localBudget() else {
            pendingSharedBudgetAdoption = nil
            return
        }

        try repository.deleteLocalBudget(id: localBudget.id)
        pendingSharedBudgetAdoption = nil
        try refresh()
    }

    func confirmSharedBudgetOverwriteFromUI() {
        do {
            try confirmSharedBudgetOverwrite()
        } catch {
            sharingErrorMessage = "Failed to open shared budget."
        }
    }

    func cancelSharedBudgetOverwrite() {
        guard let pending = pendingSharedBudgetAdoption else { return }
        dismissedSharedBudgetAdoptionIDs.insert(pending.budgetID)
        pendingSharedBudgetAdoption = nil
    }

    var dailyBudgetAmount: Decimal {
        get { (try? repository.activeBudget()?.dailyBudgetAmount) ?? 0 }
        set {
            do {
                guard let budget = try repository.activeBudget() else { return }
                budget.dailyBudgetAmount = newValue
                try repository.saveBudget(budget)
                publishDailyBudgetWatchSnapshot()
                objectWillChange.send()
            } catch {
                print("Update daily budget amount failed: \(error)")
            }
        }
    }

    var dailyBudgetPaydayDay: Int {
        get { (try? repository.activeBudget()?.dailyBudgetPaydayDay) ?? 1 }
        set {
            do {
                guard canEditBudgetSettings else { return }
                guard let budget = try repository.activeBudget() else { return }
                budget.dailyBudgetPaydayDay = min(max(newValue, 1), 31)
                try repository.saveBudget(budget)
                publishDailyBudgetWatchSnapshot()
                objectWillChange.send()
            } catch {
                print("Update daily budget payday failed: \(error)")
            }
        }
    }

    var dailyBudgetCurrentBalance: Decimal {
        usesSeparateAccountForDailyBudget ? dailyBudgetSeparateAccountBalance : projectedBalanceFromCurrentBalance
    }

    var dailyBalanceChartCurrentBalance: Decimal {
        usesSeparateAccountForDailyBudget ? dailyBudgetSeparateAccountBalance : primaryBankBalance
    }

    var dailyCycleMetrics: DailyBudgetCycleMetrics {
        DailyBudgetCycleCalculator.metrics(
            today: nowProvider(),
            paydayDay: dailyBudgetPaydayDay,
            budget: dailyBudgetAmount,
            currentBalance: dailyBudgetCurrentBalance,
            calendar: Calendar.current
        )
    }

    var dailyBalanceChartPoints: [DailyBalanceChartPoint] {
        return DailyBalanceChartCalculator.points(
            currentBalance: dailyBalanceChartCurrentBalance,
            today: nowProvider(),
            paydayDay: dailyBudgetPaydayDay,
            transactions: dailyBalanceChartTransactions(),
            calendar: Self.fixedDailyCycleCalendar
        )
    }

    var dailyBudgetWatchSnapshot: DailyBudgetWatchSnapshot {
        DailyBudgetWatchSnapshotFactory.make(
            dailyBudgetAmount: dailyBudgetAmount,
            paydayDay: dailyBudgetPaydayDay,
            usesSeparateAccount: usesSeparateAccountForDailyBudget,
            currentBalance: dailyBudgetCurrentBalance,
            metrics: dailyCycleMetrics
        )
    }

    var dailyBudgetWidgetSnapshot: DailyBudgetWidgetSnapshot {
        DailyBudgetWidgetSnapshotFactory.make(
            currentBalance: dailyBudgetCurrentBalance,
            metrics: dailyCycleMetrics
        )
    }

    var monthlyBalanceLastUpdatedAt: Date? {
        (try? repository.activeBudget())?.monthlyBalanceLastUpdatedAt
    }

    var dailyBalanceLastUpdatedAt: Date? {
        (try? repository.activeBudget())?.dailyBalanceLastUpdatedAt
    }

    var currentDate: Date {
        nowProvider()
    }

    var openingBalance: Decimal {
        get { effectiveOpeningBalance(for: selectedMonth) }
        set {
            guard canEdit(month: selectedMonth) else { return }
            openingBalances[selectedMonth.rawValue] = newValue
            markMonthlyBalanceUpdatedIfNeeded()
        }
    }

    var primaryBankBalance: Decimal {
        get { primaryBankBalances[selectedMonth.rawValue] ?? 0 }
        set {
            guard canEdit(month: selectedMonth) else { return }
            primaryBankBalances[selectedMonth.rawValue] = newValue
            markMonthlyBalanceUpdatedIfNeeded()
            if !usesSeparateAccountForDailyBudget && selectedMonth == currentYearMonth {
                markDailyBalanceUpdatedIfNeeded()
            }
        }
    }

    var monthTotals: MonthTotals {
        MonthCalculationEngine.calculate(
            items: monthItems,
            openingBalance: effectiveOpeningBalance(for: selectedMonth),
            livingBuffer: livingBuffer,
            weeklyEstimate: weeklyEstimate,
            weekendEstimate: weekendEstimate,
            minSuggestedLiving: minSuggestedLiving,
            yearMonth: selectedMonth,
            paydayDay: dailyBudgetPaydayDay
        )
    }

    var filteredWheelOfMoneyItems: [WheelOfMoneyItem] {
        WheelOfMoneyFilterRules.filteredItems(wheelOfMoneyItems, for: wheelOfMoneyFilter)
            .sorted {
                if $0.month != $1.month {
                    return $0.month < $1.month
                }
                return $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    var wheelOfMoneyMetrics: WheelOfMoneyMetrics {
        WheelOfMoneyCalculator.metrics(
            items: wheelOfMoneyItems,
            currentMonth: currentYearMonth.month
        )
    }

    var projectedBalanceFromCurrentBalance: Decimal {
        let base = isSelectedMonthInFuture ? openingBalance : primaryBankBalance
        return base - monthTotals.netOutgoingsDue
    }

    var isSelectedMonthInFuture: Bool {
        selectedMonth > currentYearMonth
    }

    var isSelectedMonthInPast: Bool {
        selectedMonth < currentYearMonth
    }

    var canNavigateToNextMonth: Bool {
        !isSelectedMonthInFuture || !monthItems.isEmpty || ((try? repository.isMonthPopulated(selectedMonth)) ?? false)
    }

    var canPopulateSelectedMonthFromPrevious: Bool {
        canEditSelectedMonth && monthItems.isEmpty && !((try? repository.isMonthPopulated(selectedMonth)) ?? false)
    }

    var fundsTotal: Decimal {
        var result = primaryBankBalance
        if includeCash { result += cashBalance }
        if includeFX { result += fxBalance }
        return result
    }

    var daysRemainingInMonth: Int {
        let calendar = Self.fixedDailyCycleCalendar
        let cycle = budgetCycleDateRange(for: selectedMonth, calendar: calendar)
        guard selectedMonth == currentYearMonth else {
            return max(calendar.dateComponents([.day], from: cycle.startInclusive, to: cycle.endExclusive).day ?? 1, 1)
        }

        let today = calendar.startOfDay(for: nowProvider())
        return max(calendar.dateComponents([.day], from: today, to: cycle.endExclusive).day ?? 1, 1)
    }

    var currentDailyAverage: Decimal {
        fundsTotal / Decimal(daysRemainingInMonth)
    }

    var aheadBehind: Decimal {
        fundsTotal - monthTotals.suggestedLiving
    }

    var weeksReckoner: Decimal {
        MonthCalculationEngine.monthlyBudgetFromWeekModel(
            year: selectedMonth.year,
            month: selectedMonth.month,
            paydayDay: dailyBudgetPaydayDay,
            weeklyEstimate: weeklyEstimate,
            weekendEstimate: weekendEstimate
        )
    }

    func setPaid(item: PlannedItem, paid: Bool) {
        guard canEdit(item: item) else { return }
        item.isPaid = paid
        do {
            try repository.savePlannedItem(item)
            try markBalanceViewsUpdated(monthly: true, daily: true)
            try refresh()
        } catch {
            print("Failed setPaid: \(error)")
        }
    }

    func delete(item: PlannedItem) {
        guard canEdit(item: item) else { return }
        do {
            try repository.deletePlannedItem(id: item.id)
            try refresh()
        } catch {
            print("Delete failed: \(error)")
        }
    }

    func setWheelOfMoneyPaid(item: WheelOfMoneyItem, paid: Bool) {
        item.isPaid = paid
        do {
            try repository.saveWheelOfMoneyItem(item)
            try refresh()
        } catch {
            print("Failed setWheelOfMoneyPaid: \(error)")
        }
    }

    func delete(wheelOfMoneyItem item: WheelOfMoneyItem) {
        do {
            try repository.deleteWheelOfMoneyItem(id: item.id)
            try refresh()
        } catch {
            print("Delete WoM item failed: \(error)")
        }
    }

    func update(
        wheelOfMoneyItem item: WheelOfMoneyItem,
        title: String,
        amount: Decimal,
        month: Int,
        notes: String
    ) {
        item.title = title
        item.amount = amount
        item.month = month
        item.notes = notes
        do {
            try repository.saveWheelOfMoneyItem(item)
            try refresh()
        } catch {
            print("Edit WoM item failed: \(error)")
        }
    }

    @discardableResult
    func createWheelOfMoneyEntry(
        title: String,
        amount: Decimal,
        month: Int,
        notes: String = "",
        isAutoGeneratedSavingsEntry: Bool = false
    ) -> WheelOfMoneyItem? {
        do {
            let item = WheelOfMoneyItem(
                budgetID: UUID(),
                title: title,
                amount: amount,
                month: month,
                isPaid: false,
                notes: notes,
                isAutoGeneratedSavingsEntry: isAutoGeneratedSavingsEntry
            )
            try repository.createWheelOfMoneyItem(item)
            try refresh()
            return item
        } catch {
            print("Create WoM entry failed: \(error)")
            return nil
        }
    }

    func duplicate(item: PlannedItem) {
        guard canEditSelectedMonth else { return }
        let copy = PlannedItem(
            accountID: item.accountID,
            monthKey: selectedMonth,
            type: item.type,
            label: item.label,
            amount: item.amount,
            dueDay: item.dueDay,
            dueText: item.dueText,
            isPaid: false,
            copiesToNextMonthAutomatically: item.copiesToNextMonthAutomatically,
            notes: item.notes
        )
        do {
            try repository.savePlannedItem(copy)
            try refresh()
        } catch {
            print("Duplicate failed: \(error)")
        }
    }

    func copy(item: PlannedItem, to month: YearMonth) {
        guard canEdit(month: month) else { return }
        let copy = PlannedItem(
            accountID: item.accountID,
            monthKey: month,
            type: item.type,
            label: item.label,
            amount: item.amount,
            dueDay: item.dueDay,
            dueText: item.dueText,
            isPaid: false,
            copiesToNextMonthAutomatically: item.copiesToNextMonthAutomatically,
            notes: item.notes
        )
        do {
            try repository.savePlannedItem(copy)
            try refresh()
        } catch {
            print("Copy failed: \(error)")
        }
    }

    func setLivingExpensesToSuggested() {
        guard canEditSelectedMonth else { return }
        let suggested = monthTotals.suggestedLiving
        if let living = monthItems.first(where: { $0.type == .transfer && $0.label.lowercased().contains("living") }) {
            living.amount = suggested
            do {
                try repository.savePlannedItem(living)
                try refresh()
                return
            } catch {
                print("Update living failed: \(error)")
            }
        }

        do {
            let accounts = try repository.accounts()
            guard let account = accounts.first else { return }
            let item = PlannedItem(
                accountID: account.id,
                monthKey: selectedMonth,
                type: .transfer,
                label: "Living expenses",
                amount: suggested,
                dueText: "Daily"
            )
            try repository.savePlannedItem(item)
            try refresh()
        } catch {
            print("Create living failed: \(error)")
        }
    }

    func update(
        item: PlannedItem,
        label: String,
        amount: Decimal,
        dueDay: Int?,
        dueText: String?,
        type: PlannedItemType,
        repeatDays: Int? = nil,
        recurrenceID: UUID? = nil,
        repeatMode: RepeatMode? = nil,
        copiesToNextMonthAutomatically: Bool,
        notes: String
    ) {
        update(
            item: item,
            label: label,
            matchingString: item.matchingString,
            amount: amount,
            dueDay: dueDay,
            dueText: dueText,
            type: type,
            repeatDays: repeatDays,
            recurrenceID: recurrenceID,
            repeatMode: repeatMode,
            copiesToNextMonthAutomatically: copiesToNextMonthAutomatically,
            notes: notes
        )
    }

    func update(
        item: PlannedItem,
        label: String,
        matchingString: String? = nil,
        amount: Decimal,
        dueDay: Int?,
        dueText: String?,
        type: PlannedItemType,
        sourceOverride: PlannedItemSource? = nil,
        repeatDays: Int? = nil,
        recurrenceID: UUID? = nil,
        repeatMode: RepeatMode? = nil,
        copiesToNextMonthAutomatically: Bool,
        notes: String
    ) {
        guard canEdit(item: item) else { return }
        item.label = label
        item.matchingString = normalizeMatchingString(matchingString)
        item.amount = amount
        item.dueDay = dueDay
        item.dueText = dueText
        let originalRepeatDays = item.repeatDays
        let originalRecurrenceID = item.recurrenceID
        let originalRepeatMode = item.repeatMode
        let originalCopiesAutomatically = item.copiesToNextMonthAutomatically
        let resolvedRepeatMode = repeatMode ?? item.repeatMode
        let normalizedRepeatDays = resolvedRepeatMode == .periodic
            ? repeatDays.flatMap { $0 > 0 ? $0 : nil }
            : originalRepeatDays
        item.repeatMode = resolvedRepeatMode
        item.repeatDays = normalizedRepeatDays
        item.recurrenceID = normalizedRepeatDays == nil
            ? item.recurrenceID
            : (normalizedRepeatDays != originalRepeatDays ? UUID() : (recurrenceID ?? item.recurrenceID ?? UUID()))
        item.type = type
        item.copiesToNextMonthAutomatically = resolvedRepeatMode == .calendar && copiesToNextMonthAutomatically
        item.notes = notes
        let originalSource = item.source
        item.source = resolvedUpdatedSource(
            originalSource: originalSource,
            sourceOverride: sourceOverride
        )
        do {
            try repository.savePlannedItem(item)
            try refresh()
        } catch {
            item.source = originalSource
            item.repeatDays = originalRepeatDays
            item.recurrenceID = originalRecurrenceID
            item.repeatMode = originalRepeatMode
            item.copiesToNextMonthAutomatically = originalCopiesAutomatically
            print("Edit failed: \(error)")
        }
    }

    @discardableResult
    func createEntry(
        type: PlannedItemType,
        label: String = "",
        matchingString: String? = nil,
        amount: Decimal = 0,
        dueDay: Int?,
        source: PlannedItemSource = .manual,
        repeatDays: Int? = nil,
        recurrenceID: UUID? = nil,
        repeatMode: RepeatMode? = nil,
        copiesToNextMonthAutomatically: Bool = true,
        notes: String = ""
    ) -> PlannedItem? {
        guard canEditSelectedMonth else { return nil }
        do {
            let accounts = try repository.accounts()
            guard let account = accounts.first else { return nil }
            let resolvedRepeatMode = repeatMode ?? (repeatDays != nil ? .periodic : (dueDay != nil && copiesToNextMonthAutomatically ? .calendar : .oneOff))

            let item = PlannedItem(
                accountID: account.id,
                monthKey: selectedMonth,
                type: type,
                source: source,
                label: label,
                amount: amount,
                matchingString: normalizeMatchingString(matchingString),
                dueDay: dueDay,
                dueText: nil,
                repeatDays: resolvedRepeatMode == .periodic ? repeatDays.flatMap { $0 > 0 ? $0 : nil } : nil,
                recurrenceID: resolvedRepeatMode == .periodic ? (recurrenceID ?? UUID()) : nil,
                repeatMode: resolvedRepeatMode,
                isPaid: false,
                copiesToNextMonthAutomatically: resolvedRepeatMode == .calendar && copiesToNextMonthAutomatically,
                notes: notes
            )
            try repository.createPlannedItem(item)
            try refresh()
            return item
        } catch {
            print("Create entry failed: \(error)")
            return nil
        }
    }

    func manualMatchCandidates(for sourceItem: PlannedItem) -> [PlannedItem] {
        guard sourceItem.source == .importedUnplanned,
              sourceItem.resolvedMonthKey == selectedMonth else {
            return []
        }

        return MonthItemSortRules.sortedItems(
            monthItems.filter { item in
                item.id != sourceItem.id &&
                !item.isPaid &&
                item.source != .importedUnplanned
            },
            paydayDay: dailyBudgetPaydayDay,
            month: selectedMonth
        )
    }

    func sameMonthOccurrences(for item: PlannedItem) -> [PlannedItem] {
        guard item.resolvedMonthKey == selectedMonth, item.repeatMode == .periodic else { return [] }
        return PlannedItem.everyNDaysOccurrences(from: item, in: selectedMonth, paydayDay: dailyBudgetPaydayDay)
    }

    func populateSameMonth(for item: PlannedItem) {
        guard canEditSelectedMonth else { return }
        do {
            let existingItems = try repository.plannedItems(for: selectedMonth)
            let existingDays = Set<Int>(existingItems.compactMap { existing in
                guard existing.recurrenceID == item.recurrenceID else { return nil }
                return existing.dueDay
            })
            for occurrence in sameMonthOccurrences(for: item) {
                guard let dueDay = occurrence.dueDay, !existingDays.contains(dueDay) else { continue }
                try repository.createPlannedItem(occurrence)
            }
            try refresh()
        } catch {
            print("Populate every-n-days occurrences failed: \(error)")
        }
    }

    @discardableResult
    func matchImportedUnplannedItem(_ sourceItem: PlannedItem, to targetItem: PlannedItem) throws -> PlannedItem? {
        guard canEdit(item: sourceItem),
              sourceItem.source == .importedUnplanned,
              sourceItem.id != targetItem.id,
              sourceItem.accountID == targetItem.accountID,
              sourceItem.resolvedMonthKey == targetItem.resolvedMonthKey,
              targetItem.source != .importedUnplanned else {
            return nil
        }

        let originalTargetAmount = targetItem.amount
        let originalTargetDueDay = targetItem.dueDay
        let originalTargetDueText = targetItem.dueText
        let originalTargetIsPaid = targetItem.isPaid
        let originalTargetMatchingString = targetItem.matchingString
        let originalTargetImportedPostedAt = targetItem.importedPostedAt
        let originalTargetSource = targetItem.source

        let accountIDs = Set([sourceItem.accountID])
        let importedRecords = try repository.importedTransactionRecords(accountIDs: accountIDs)
        let linkedRecords = importedRecords.filter { $0.appliedPlannedItemID == sourceItem.id }
        let fallbackMatchingString = normalizeMatchingString(sourceItem.matchingString) ?? sourceItem.label
        let importedPostedAt = sourceItem.importedPostedAt ?? linkedRecords.first?.postedAt

        targetItem.amount = sourceItem.amount
        targetItem.dueDay = sourceItem.dueDay
        targetItem.dueText = sourceItem.dueText
        if targetItem.importedPostedAt == nil {
            targetItem.importedPostedAt = importedPostedAt
        }
        targetItem.isPaid = true
        targetItem.source = originalTargetSource == .importedUnplanned ? .manual : originalTargetSource
        if normalizeMatchingString(targetItem.matchingString) == nil {
            targetItem.matchingString = fallbackMatchingString
        }

        do {
            try repository.savePlannedItem(targetItem)
            for record in linkedRecords {
                record.appliedPlannedItemID = targetItem.id
                try repository.saveImportedTransactionRecord(record)
            }
            try repository.deletePlannedItem(id: sourceItem.id)
            try refresh()
            return try repository.plannedItem(id: targetItem.id)
        } catch {
            targetItem.amount = originalTargetAmount
            targetItem.dueDay = originalTargetDueDay
            targetItem.dueText = originalTargetDueText
            targetItem.isPaid = originalTargetIsPaid
            targetItem.matchingString = originalTargetMatchingString
            targetItem.importedPostedAt = originalTargetImportedPostedAt
            targetItem.source = originalTargetSource
            throw error
        }
    }

    func linkedImportedPayee(for item: PlannedItem) -> String? {
        guard let linkedRecord = try? repository.importedTransactionRecords(accountIDs: [item.accountID])
            .first(where: { $0.appliedPlannedItemID == item.id }) else {
            return nil
        }

        let trimmed = linkedRecord.payee.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    func linkedImportedPostedAt(for item: PlannedItem) -> Date? {
        try? repository.importedTransactionRecords(accountIDs: [item.accountID])
            .first(where: { $0.appliedPlannedItemID == item.id })?.postedAt
    }

    func shiftMonth(by delta: Int) {
        guard delta <= 0 || canNavigateToNextMonth else { return }
        var year = selectedMonth.year
        var month = selectedMonth.month + delta
        while month < 1 { month += 12; year -= 1 }
        while month > 12 { month -= 12; year += 1 }
        selectedMonth = YearMonth(year: year, month: month)
        do {
            try refresh()
        } catch {
            print("Refresh failed: \(error)")
        }
    }

    func populateSelectedMonthFromPrevious() {
        guard canPopulateSelectedMonthFromPrevious else { return }

        do {
            let sourceItems = try repository.plannedItems(for: previousMonth(of: selectedMonth))
            try copyItems(sourceItems.filter { $0.repeatMode == .calendar }, to: selectedMonth)

            let existing = try repository.plannedItems(for: selectedMonth)
            let existingKeys = Set(existing.map { "\($0.recurrenceID?.uuidString ?? $0.id.uuidString):\($0.dueDay ?? 0)" })
            let periodicCopies = PlannedItem.periodicOccurrences(
                from: try repository.periodicItems(before: selectedMonth),
                into: selectedMonth,
                paydayDay: dailyBudgetPaydayDay
            )
            for copy in periodicCopies {
                let key = "\(copy.recurrenceID?.uuidString ?? copy.id.uuidString):\(copy.dueDay ?? 0)"
                if !existingKeys.contains(key) {
                    try repository.createPlannedItem(copy)
                }
            }
            if autoGenerateWoMSavingsEveryMonth {
                try ensureGeneratedWheelOfMoneySavingsItem(for: selectedMonth)
            }
            try repository.markMonthPopulated(selectedMonth)
            try refresh()
        } catch {
            print("Populate month failed: \(error)")
        }
    }

    nonisolated static func currency(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = Locale.current.currency?.identifier ?? "GBP"
        return formatter.string(from: value as NSDecimalNumber) ?? "\(value)"
    }

    private var currentYearMonth: YearMonth {
        dailyBudgetMonthKey(for: nowProvider())
    }

    var canEditSelectedMonth: Bool {
        !isSelectedMonthInPast || allowsPreviousMonthEditing
    }

    private func canEdit(item: PlannedItem) -> Bool {
        guard let month = item.resolvedMonthKey else { return false }
        return canEdit(month: month)
    }

    private func canEdit(month: YearMonth) -> Bool {
        month >= currentYearMonth || allowsPreviousMonthEditing
    }

    private func normalizeMatchingString(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private func resolvedUpdatedSource(
        originalSource: PlannedItemSource,
        sourceOverride: PlannedItemSource?
    ) -> PlannedItemSource {
        if let sourceOverride {
            return sourceOverride
        }
        if originalSource == .importedUnplanned {
            return .manual
        }
        return originalSource
    }

    private func effectiveOpeningBalance(for month: YearMonth) -> Decimal {
        if month <= currentYearMonth {
            return openingBalances[month.rawValue] ?? 0
        }
        return closingBalance(for: previousMonth(of: month))
    }

    private func closingBalance(for month: YearMonth) -> Decimal {
        let balanceBasis: Decimal
        if month <= currentYearMonth {
            balanceBasis = primaryBankBalances[month.rawValue] ?? openingBalances[month.rawValue] ?? 0
        } else {
            balanceBasis = effectiveOpeningBalance(for: month)
        }

        let items: [PlannedItem]
        if month == selectedMonth {
            items = monthItems
        } else {
            items = (try? repository.plannedItems(for: month)) ?? []
        }
        return balanceBasis - MonthCalculationEngine.netOutgoingsDue(from: items)
    }

    private func previousMonth(of month: YearMonth) -> YearMonth {
        var year = month.year
        var value = month.month - 1
        if value < 1 {
            value = 12
            year -= 1
        }
        return YearMonth(year: year, month: value)
    }

    private func createDailyImportedTransactions(
        for account: Account,
        importedRecordIDs: [UUID]
    ) throws {
        guard !importedRecordIDs.isEmpty else { return }
        let importedRecordIDSet = Set(importedRecordIDs)
        let importedRecords = try repository.importedTransactionRecords(accountIDs: [account.id])
            .filter { importedRecordIDSet.contains($0.id) }

        for record in importedRecords {
            let transaction = Transaction(
                id: record.id,
                budgetID: account.budgetID,
                accountID: account.id,
                monthKey: dailyBudgetMonthKey(for: record.postedAt),
                amount: record.amount,
                note: record.payee,
                sourceKind: record.sourceKind,
                sourceExternalTransactionID: record.externalTransactionID,
                sourcePostedAt: record.postedAt
            )
            try repository.createTransaction(transaction)
        }
    }

    private func dailyBalanceChartTransactions() -> [Transaction] {
        if let budget = try? repository.activeBudget(),
           budget.usesSeparateAccountForDailyBudget,
           let hiddenAccount = try? repository.hiddenDailyAccount(for: budget) {
            return (try? repository.transactions(accountIDs: [hiddenAccount.id])) ?? []
        }

        return visibleAccountDailyBalanceChartTransactions()
    }

    private func visibleAccountDailyBalanceChartTransactions() -> [Transaction] {
        guard let account = try? repository.accounts().first else { return [] }
        let cycleMonthKey = currentDailyCycleMonthKey()
        let items = (try? repository.plannedItems(for: cycleMonthKey)) ?? []

        return items.compactMap { item in
            guard item.accountID == account.id,
                  item.isPaid,
                  let postedAt = dailyChartPostedAt(for: item, in: cycleMonthKey) else {
                return nil
            }

            return Transaction(
                id: item.id,
                budgetID: item.budgetID,
                accountID: item.accountID,
                monthKey: cycleMonthKey,
                amount: dailyChartAmount(for: item),
                note: item.label,
                sourcePostedAt: postedAt
            )
        }
    }

    private func dailyChartAmount(for item: PlannedItem) -> Decimal {
        switch item.type {
        case .credit:
            return item.amount
        case .fixedDebit, .transfer:
            return -item.amount
        }
    }

    private func dailyChartPostedAt(for item: PlannedItem, in cycleMonth: YearMonth) -> Date? {
        guard let dueDay = item.dueDay else { return nil }

        let actualMonth: YearMonth
        if dailyBudgetPaydayDay == 1 || dueDay <= dailyBudgetPaydayDay {
            actualMonth = cycleMonth
        } else {
            actualMonth = previousMonth(of: cycleMonth)
        }

        var components = DateComponents()
        components.year = actualMonth.year
        components.month = actualMonth.month
        components.day = dueDay
        return Self.fixedDailyCycleCalendar.date(from: components)
    }

    private var derivedDailyBudgetSeparateAccountBalance: Decimal {
        dailyBudgetAmount + netDailyImportedTransactionsInCurrentCycle()
    }

    private func netDailyImportedTransactionsInCurrentCycle() -> Decimal {
        let calendar = Self.fixedDailyCycleCalendar
        let boundaries = DailyBudgetCycleCalculator.cycleBoundaries(
            today: nowProvider(),
            paydayDay: dailyBudgetPaydayDay,
            calendar: calendar
        )
        let cycleStart = calendar.startOfDay(for: boundaries.previousPayday)
        let cycleEnd = calendar.startOfDay(for: nowProvider())

        return dailyBalanceChartTransactions().reduce(into: Decimal.zero) { total, transaction in
            guard let postedAt = transaction.sourcePostedAt else { return }
            let day = calendar.startOfDay(for: postedAt)
            guard day >= cycleStart, day <= cycleEnd else { return }
            total += transaction.amount
        }
    }

    private func dailyBudgetMonthKey(for date: Date) -> YearMonth {
        let calendar = Self.fixedDailyCycleCalendar
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return ImportedTransactionReconciliationService.budgetMonthKey(
            year: components.year ?? 2000,
            month: components.month ?? 1,
            day: components.day ?? 1,
            paydayDay: dailyBudgetPaydayDay,
            calendar: calendar,
            referenceDate: date
        )
    }

    private func currentDailyCycleMonthKey() -> YearMonth {
        dailyBudgetMonthKey(for: nowProvider())
    }

    private func budgetCycleDateRange(
        for month: YearMonth,
        calendar: Calendar
    ) -> (startInclusive: Date, endExclusive: Date) {
        let startMonth = previousMonth(of: month)
        return (
            startInclusive: paydayDate(in: startMonth, calendar: calendar),
            endExclusive: paydayDate(in: month, calendar: calendar)
        )
    }

    private func paydayDate(in month: YearMonth, calendar: Calendar) -> Date {
        let monthStart = calendar.date(from: DateComponents(year: month.year, month: month.month, day: 1))
        let daysInMonth = monthStart.flatMap { calendar.range(of: .day, in: .month, for: $0)?.count } ?? 31
        let clampedDay = min(max(dailyBudgetPaydayDay, 1), daysInMonth)
        return calendar.date(from: DateComponents(year: month.year, month: month.month, day: clampedDay))
            ?? monthStart
            ?? nowProvider()
    }

    private static var fixedDailyCycleCalendar: Calendar {
        DailyBudgetCalendarProvider.fixedGregorianGMT
    }

    private func nextMonth(of month: YearMonth) -> YearMonth {
        var year = month.year
        var value = month.month + 1
        if value > 12 {
            value = 1
            year += 1
        }
        return YearMonth(year: year, month: value)
    }

    private func ensureGeneratedWheelOfMoneySavingsItem(for month: YearMonth) throws {
        let existingMonthItems = try repository.plannedItems(for: month)
        guard !existingMonthItems.contains(where: { $0.label == "WoM savings" }) else { return }

        let generatedAmount = WheelOfMoneyCalculator.metrics(
            items: try repository.wheelOfMoneyItems(),
            currentMonth: month.month
        ).remainingAverage

        guard let account = try repository.accounts().first else { return }

        try repository.createPlannedItem(
            PlannedItem(
                accountID: account.id,
                monthKey: month,
                type: .fixedDebit,
                label: "WoM savings",
                amount: generatedAmount,
                dueDay: nil,
                isPaid: false,
                copiesToNextMonthAutomatically: false
            )
        )
    }

    private func copyItems(_ sourceItems: [PlannedItem], to month: YearMonth) throws {
        for copy in PlannedItem.copiedItems(from: sourceItems, into: month, paydayDay: dailyBudgetPaydayDay) {
            try repository.createPlannedItem(copy)
        }
    }

    private func loadPersistedBudgetState() throws {
        guard let budget = try repository.activeBudget() else {
            isHydratingPersistedBudgetState = true
            openingBalances = [:]
            primaryBankBalances = [:]
            explicitDailyBudgetSeparateAccountBalanceOverride = nil
            isHydratingPersistedBudgetState = false
            return
        }

        let persisted = PersistedMonthBalancesCodec.decode(budget.monthBalancesPayload)
        isHydratingPersistedBudgetState = true
        openingBalances = PersistedMonthBalancesCodec.decimalMap(from: persisted.openingBalances)
        primaryBankBalances = PersistedMonthBalancesCodec.decimalMap(from: persisted.primaryBankBalances)
        explicitDailyBudgetSeparateAccountBalanceOverride = persisted.dailyBudgetSeparateAccountBalanceOverride.flatMap { Decimal(string: $0) }
        if explicitDailyBudgetSeparateAccountBalanceOverride == nil,
           budget.dailyBudgetSeparateAccountBalance != 0 {
            explicitDailyBudgetSeparateAccountBalanceOverride = budget.dailyBudgetSeparateAccountBalance
        }
        isHydratingPersistedBudgetState = false
    }

    private func migrateBalanceLastUpdatedTimestampsIfNeeded() throws {
        try BudgetBalanceLastUpdatedMigration.migrateIfNeeded(repository: repository)
    }

    private func persistBudgetStateIfNeeded() {
        guard !isHydratingPersistedBudgetState else { return }
        do {
            guard let budget = try repository.activeBudget() else { return }
            budget.monthBalancesPayload = persistedMonthBalancePayload
            budget.dailyBudgetSeparateAccountBalance = explicitDailyBudgetSeparateAccountBalanceOverride ?? 0
            try repository.saveBudget(budget)
            publishDailyBudgetWatchSnapshot()
        } catch {
            print("Persist budget state failed: \(error)")
        }
    }

    private func markMonthlyBalanceUpdatedIfNeeded() {
        do {
            try markMonthlyBalanceUpdated()
        } catch {
            print("Update monthly last updated failed: \(error)")
        }
    }

    private func markDailyBalanceUpdatedIfNeeded() {
        do {
            try markDailyBalanceUpdated()
        } catch {
            print("Update daily last updated failed: \(error)")
        }
    }

    private func markMonthlyBalanceUpdated() throws {
        guard let budget = try repository.activeBudget() else { return }
        try repository.markMonthlyBalanceUpdated(id: budget.id)
    }

    private func markDailyBalanceUpdated() throws {
        guard let budget = try repository.activeBudget() else { return }
        try repository.markDailyBalanceUpdated(id: budget.id)
    }

    private func markBalanceViewsUpdated(monthly: Bool, daily: Bool) throws {
        guard let budget = try repository.activeBudget() else { return }
        try repository.markBalanceViewsUpdated(id: budget.id, monthly: monthly, daily: daily)
    }

    private func publishDailyBudgetWatchSnapshot() {
        dailyBudgetWatchSnapshotSyncer.sync(dailyBudgetWatchSnapshot)
        dailyBudgetWidgetSnapshotSyncer.sync(dailyBudgetWidgetSnapshot)
    }

    private func updatePendingSharedBudgetAdoption() throws {
        guard let localBudget = try repository.localBudget(),
              let sharedBudget = try repository.sharedBudget(),
              sharedBudget.ownerParticipantID != currentParticipantID,
              localBudget.id != sharedBudget.id,
              !dismissedSharedBudgetAdoptionIDs.contains(sharedBudget.id) else {
            pendingSharedBudgetAdoption = nil
            return
        }

        pendingSharedBudgetAdoption = PendingSharedBudgetAdoption(
            budgetID: sharedBudget.id,
            budgetName: sharedBudget.name
        )
    }

    private func migrateLegacyOwnerIdentifiersIfNeeded() throws {
        guard currentParticipantID != Self.legacyOwnerParticipantID else { return }
        guard let localBudget = try repository.localBudget(),
              localBudget.ownerParticipantID == Self.legacyOwnerParticipantID else {
            return
        }

        localBudget.ownerParticipantID = currentParticipantID
        try repository.saveBudget(localBudget)
    }

    private func shareErrorMessage(for error: Error) -> String {
        if let sharingError = error as? BudgetSharingError {
            switch sharingError {
            case .budgetNotFound:
                return "Could not find a budget to share."
            case .budgetAlreadyShared, .reverseMigrationNotSupported:
                return "This budget is already shared."
            case .invalidMonthKey:
                return "This budget could not be shared."
            }
        }
        if let coordinatorError = error as? BudgetShareCoordinatorError {
            switch coordinatorError {
            case .stopShareVerificationFailed:
                return "Could not confirm that sharing was removed."
            default:
                break
            }
        }
        return "Budget sharing failed."
    }

    private func acceptSharedBudgetErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        if nsError.domain == CKError.errorDomain,
           nsError.code == CKError.partialFailure.rawValue,
           let partialErrors = nsError.userInfo[CKPartialErrorsByItemIDKey] as? [AnyHashable: NSError],
           let nestedError = partialErrors.values.first {
            return acceptSharedBudgetErrorMessage(for: nestedError)
        }

        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return "Failed to accept shared budget: \(description) (\(nsError.domain) \(nsError.code))"
        }

        if let description = nsError.userInfo[NSLocalizedDescriptionKey] as? String,
           !description.isEmpty {
            return "Failed to accept shared budget: \(description) (\(nsError.domain) \(nsError.code))"
        }

        return "Failed to accept shared budget: \(nsError.domain) \(nsError.code)"
    }

    func debugAcceptSharedBudgetErrorMessage(for error: Error) -> String {
        acceptSharedBudgetErrorMessage(for: error)
    }
}
