# Periodic Repeats and WoM Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax for tracking.

**Goal:** Make versioned every-N-days repeat definitions the schedule source, show their next 24 budget months of occurrences in WoM, and calculate monthly savings from active repeat costs.

**Architecture:** Persist each repeat separately from its schedule revisions and dated occurrence rows. A civil-date projector combines active revisions, skips, and overrides without writing during WoM display. The repository owns atomic persistence and cross-store lifecycle; AppState applies permissions and payday-month assignment; the Month editor and WoM forward explicit action scopes.

**Tech Stack:** Swift 5, SwiftUI, SwiftData, Core Data, XCTest, xcodebuild, Swift Package Manager.

## Global Constraints

- Every periodic repeat with a positive interval is supported, including intervals of 28 days or fewer.
- Fixed-day calendar repeats retain their current month-copy behavior and do not appear in WoM.
- Persist civil dates as Gregorian year-month-day values and project by calendar days, not elapsed 24-hour periods.
- Assign occurrences to payday-based budget months; payday changes affect budget-month assignment but not occurrence identity.
- Use Decimal for all money.
- Add explicit SwiftData and Core Data migrations; preserve current records, paid states, import links, sharing scope, and IDs.
- WoM viewing does not write definitions, occurrences, or populated-month markers.
- Saving a repeat edit, skip, occurrence reconciliation, and population marker must be atomic within the owning store.
- Keep the user's existing repeat-copy changes in AppState.swift, MonthView.swift, and MonthlyMoneyTests.swift.

---

## File Structure

- MonthlyMoney/DomainModels.swift: persisted SwiftData definition, revision, skip, civil-date, and occurrence fields.
- MonthlyMoney/PeriodicRepeatSchedule.swift (new): civil-date conversion, revision projection, window grouping inputs, and Decimal savings calculation.
- MonthlyMoney/MonthlyMoneyPersistenceFactory.swift: versioned SwiftData schema and migration from V2.
- MonthlyMoney/CoreDataMapping.swift: Core Data V6 schema, relationships, mappings, and migration metadata.
- MonthlyMoney/CoreDataAccountDataStore.swift: Core Data migration, CRUD, and atomic save boundary.
- MonthlyMoney/Repository.swift: store protocol, in-memory/SwiftData/Core Data implementations, atomic changes, and share lifecycle.
- MonthlyMoney/AppState.swift: projection, population, edit scopes, stopping, deletion, conversion, savings target, and permissions.
- MonthlyMoney/MonthView.swift: occurrence edit scope and periodic actions from existing month rows.
- MonthlyMoney/WheelOfMoneyView.swift: read-only 24-budget-month projection and savings summary.
- MonthlyMoneyTests/MonthlyMoneyTests.swift: domain, repository, state, migration, and sharing regression tests.
- MonthlyMoneyUITests/MonthlyMoneyUITests.swift: WoM accessibility and edit-scope interaction coverage where test hosting permits.
- docs/superpowers/specs/2026-09-30-periodic-repeats-wom-design.md: approved behavior.
- docs/superpowers/plans/2026-09-30-periodic-repeats-wom.md: this execution checklist.

The project keeps its app-level SwiftData models and Core Data mapping in the app target; do not introduce a new dependency on the separate MonthlyMoneyCorePackage.

---

### Task 1: Civil dates, schedule revisions, and savings math

**Files:**
- Create: MonthlyMoney/PeriodicRepeatSchedule.swift
- Modify: MonthlyMoneyTests/MonthlyMoneyTests.swift

**Interfaces:**
- Produce CivilDate(year:month:day:), CivilDate.init?(rawValue:), rawValue, adding(days:calendar:), and chronological comparison.
- Produce PeriodicRepeatSchedule.project(repeatID:revisions:skips:from:through:) -> [PeriodicOccurrenceProjection].
- Produce PeriodicRepeatSchedule.monthlySavingsTarget(revisions:effectiveOn:) -> Decimal.
- PeriodicOccurrenceProjection contains repeat ID, immutable scheduled date, and the active revision's display fields.
- Projection uses the latest revision whose effectiveDate <= scheduledDate, and stops before the next revision boundary or exclusive repeat end date.
- A revision change with a new interval starts from its own anchor; descriptive-only revisions retain the preceding anchor phase.
- A skip suppresses only its (repeatID, scheduledDate).

- [ ] Step 1: Add failing civil-date and revision projection tests.

Add tests named testCivilDateUsesGregorianCalendarDaysAcrossDST, testPeriodicProjectionUsesLatestEligibleRevision, testRevisionBoundaryKeepsOldUnmaterializedDates, testIntervalRevisionStartsOnNewAnchor, testSkipSuppressesScheduledDateAfterRevisionChange, and testMonthlySavingsTargetAnnualizesIntervalsWithDecimalArithmetic.

Representative assertion:

    let dates = PeriodicRepeatSchedule.project(
        repeatID: repeat.id,
        revisions: [firstRevision, secondRevision],
        skips: [],
        from: CivilDate(year: 2026, month: 5, day: 1),
        through: CivilDate(year: 2026, month: 7, day: 31)
    ).map(\.scheduledDate)

    XCTAssertEqual(dates, expectedCivilDates)

Use intervals 1, 28, 29, 365, and 730, with DST, year, and revision boundaries. Include debit, credit, and transfer in savings tests; only debit revisions contribute.

- [ ] Step 2: Run focused tests and verify they fail because the projector interfaces do not exist.

Run: rtk proxy xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /private/tmp/MonthlyMoney-periodic-tests

Expected: focused tests fail for missing civil-date and revision-projector behavior. If simulator access is unavailable, record that app XCTest did not run.

- [ ] Step 3: Implement pure date and Decimal functions.

Store civil dates in canonical zero-padded yyyy-MM-dd form and validate Gregorian component round trips. Add calendar days with a Gregorian calendar. Projection must be deterministic and must not fetch or write from a repository.

- [ ] Step 4: Rerun focused tests.

Run the same xcodebuild test command.

Expected: all new date, revision, skip, and savings tests pass.

- [ ] Step 5: Commit the domain milestone.

---

### Task 2: Persisted models and SwiftData migration

**Files:**
- Modify: MonthlyMoney/DomainModels.swift
- Modify: MonthlyMoney/MonthlyMoneyPersistenceFactory.swift
- Modify: MonthlyMoney/MonthlyMoneyRepositoryBootstrap.swift
- Modify: MonthlyMoneyTests/MonthlyMoneyTests.swift

**Interfaces:**
- Add PeriodicRepeat with stable ID, budget ID, account ID, and optional exclusive end date.
- Add PeriodicRepeatRevision with stable ID, repeat ID, effective date, anchor date, positive interval, type, label, matching string, Decimal amount, and notes.
- Add PeriodicRepeatSkip identified by repeat ID and scheduled civil date.
- Add immutable PlannedItem scheduledDateRaw, editable dueDateRaw, optional repeat ID, and occurrence-override flag, with typed civil-date accessors.
- Add MonthlyMoneySchemaV3; keep V1 and V2 snapshots immutable and migrate V2 to V3 explicitly.
- Legacy grouping key is (budgetID, accountID, recurrenceID). Select the latest valid concrete occurrence as both initial anchor and effective date; break same-date ties by stable planned-item ID. Leave invalid or inactive rows unlinked.

- [ ] Step 1: Add failing SwiftData model and migration tests.

Test a V2 store containing two active recurrence IDs, two accounts, and one invalid row. Assert one definition per budget/account/recurrence group, latest anchor phase, deterministic tie breaking, all original planned-item IDs and stored month/due-day fields preserved, payday-resolved scheduled date versus editable due date, paid/import metadata preserved, and invalid rows remain readable and unlinked after closing and reopening the migrated store.

- [ ] Step 2: Run the migration tests and verify expected failure.

Run the focused xcodebuild test command from Task 1.

Expected: tests fail because V3 models and the V2 backfill do not exist.

- [ ] Step 3: Add V3 models and explicit migration.

Keep historical V1 and V2 schema declarations unchanged. Freeze the exact V2 `PlannedItem` shape in the V2 schema snapshot before changing the current model; migration must read through that snapshot, create definitions/revisions before linking existing occurrences, and use deterministic row ordering. Do not infer dates before the latest legacy occurrence.

- [ ] Step 4: Run all SwiftData migration and model tests.

Expected: migrated stores open with every original occurrence and payment/import field intact, and new models round-trip.

- [ ] Step 5: Commit the SwiftData milestone.

---

### Task 3: Core Data V6 schema and legacy backfill

**Files:**
- Modify: MonthlyMoney/CoreDataMapping.swift
- Modify: MonthlyMoney/CoreDataAccountDataStore.swift
- Modify: MonthlyMoneyTests/MonthlyMoneyTests.swift

**Interfaces:**
- Add Core Data entity names and attributes for repeat, revision, skip, scheduled date, due date, and override state.
- Add budget relationships so repeat data belongs to the shared budget graph; revisions and skips also link to their repeat.
- Add Core Data V6 after current V5 without changing V2, V3, V4, or V5 definitions.
- Migrate existing V5 planned items using the same grouping, latest-phase selection, tie break, and preservation rules as SwiftData.

- [ ] Step 1: Add failing V5-to-V6 migration tests.

Create a V5 store with same-date rows, different accounts, an import-linked occurrence, a paid row, and an invalid inactive periodic row. Assert migration creates separate groups, preserves payday-resolved scheduled dates, editable due dates, stored month/due-day fields, paid state and import links after reopening private and shared stores, detects no orphan imported references, and adds no guessed repeat to invalid rows.

- [ ] Step 2: Run the focused migration test and verify failure.

Run the focused xcodebuild test command from Task 1.

Expected: V5 store migration cannot find the new schema and migration policy.

- [ ] Step 3: Implement V6 entities, relationships, mappings, and migration.

Use the existing store-migration replacement pattern. Migrate into a temporary store and replace the old SQLite files only after migration succeeds. Preserve the source store on error.

- [ ] Step 4: Run Core Data model, migration, private/shared configuration, and mapping tests.

Expected: V2/V3/V4/V5 migration tests continue to pass and V5 data opens as V6.

- [ ] Step 5: Commit the Core Data milestone.

---

### Task 4: Repository CRUD, atomic changes, and sharing lifecycle

**Files:**
- Modify: MonthlyMoney/Repository.swift
- Modify: MonthlyMoney/CoreDataAccountDataStore.swift
- Modify: MonthlyMoney/MonthlyMoneyPersistenceFactory.swift
- Modify: MonthlyMoneyTests/MonthlyMoneyTests.swift

**Interfaces:**
- Extend AccountDataStore with fetch/upsert/delete operations for definitions, revisions, and skips, plus performAtomically<T>(_ body: () throws -> T) throws -> T.
- Implement the interface in memory, SwiftData, and Core Data stores.
- Extend localBudgetSnapshot and insertShared to carry definitions, revisions, and skips.
- Add repository queries scoped to owning budget/account and safe lookup by (repeatID, scheduledDate).
- Account/budget deletion removes repeat data without orphan revisions, skips, or linked occurrence references.

- [ ] Step 1: Add failing repository tests for CRUD, scoping, atomic rollback, sharing, and deletion.

Cover identical repeat labels on separate accounts, duplicate generation identity, deliberate injected write failures after each persisted revision/skip/occurrence/month-marker write and save boundary, reopened-store rollback state, local-to-shared snapshot round trip, unsharing, and account/budget deletion without orphan imported references.

- [ ] Step 2: Run focused repository tests and verify failure.

Run the focused xcodebuild test command from Task 1.

Expected: repository interfaces and repeat persistence operations are absent.

- [ ] Step 3: Implement store methods and transactional boundaries.

InMemoryAccountDataStore restores pre-transaction state when the closure throws. SwiftDataAccountDataStore rolls back its ModelContext on failure. CoreDataAccountDataStore rolls back its context before returning the error. Repository changes perform all repeat and occurrence writes in the store selected by the owning budget.

- [ ] Step 4: Rerun repository and prior sharing tests.

Expected: injected failures leave definitions, revisions, skips, planned items, and month markers unchanged; retries produce one consistent result.

- [ ] Step 5: Commit the repository milestone.

---

### Task 5: Projection, population, edits, deletion, and series lifecycle

**Files:**
- Modify: MonthlyMoney/AppState.swift
- Modify: MonthlyMoney/MonthView.swift
- Modify: MonthlyMoney/MonthItemEditorDraft.swift
- Modify: MonthlyMoneyTests/MonthlyMoneyTests.swift

**Interfaces:**
- Add AppState.womOccurrences projecting current budget month through the next 23 months without writes.
- Add month-group values containing YearMonth and date-sorted projections; group by displayed due date using the current payday.
- Add population that materializes only target-month dates, using the revision active on each scheduled date, by identity, respecting skips and overrides.
- Preserve the user's existing copyRepeatingEntriesToNextMonth and repopulation logic for calendar items. Periodic generation must not use the existing label/matching-string copy rule.
- Remove active `.periodic` generation from legacy `PlannedItem.periodicOccurrences`, `everyNDaysOccurrences`, and `Repository.periodicItems(before:)` paths so invalid or unlinked legacy rows cannot be silently reactivated. Keep `.calendar` month-copy behavior unchanged.
- Add occurrence-only, this-and-future, delete-this-occurrence, end-from-here, and explicit periodic-to-one-off/calendar conversion operations.
- Changes to an existing revision begin at the selected occurrence's immutable scheduled date. Descriptive changes keep phase; date/interval changes use the entered due date as anchor. Earlier revisions and earlier unmaterialized dates remain unchanged.
- Future reconciliation touches only affected already-populated months. A successful occurrence-only save does not mark a month populated.
- A month containing only edited periodic overrides can still be explicitly populated; ordinary months with other entries retain current guards.

- [ ] Step 1: Add failing AppState tests for projection and no writes on WoM viewing.

Cover window boundaries, sorting, payday grouping, due-date overrides entering/leaving the window, skipped dates, same-day tie order, and unchanged planned-item count/month markers on refresh.

- [ ] Step 2: Run projection tests and verify failure.

Run the focused xcodebuild test command from Task 1.

Expected: WoM occurrence projection is not implemented.

- [ ] Step 3: Add failing population and action-scope tests.

Cover every positive interval, multiple occurrences in one month, unmaterialized dates across revision boundaries, occurrence overrides, identity-based merge, population eligibility, skipped projection, end-date exclusivity, conversions, paid state, import-link preservation, and generated-row deletion policy.

Add a regression proving legacy periodic generation cannot reactivate invalid or unlinked rows, while fixed-day calendar copying still works.

- [ ] Step 4: Implement AppState/repository orchestration.

Use atomic repository operations for revision, skip, occurrence, and population-marker changes. Future schedule corrections preserve import-linked, paid, and overridden rows as detached one-off planned items when their scheduled identity becomes obsolete.

- [ ] Step 5: Run focused AppState and existing month-population tests.

Expected: lifecycle rules pass and the copied user changes still pass unchanged.

- [ ] Step 6: Commit the state and lifecycle milestone.

---

### Task 6: WoM and Month editor interactions

**Files:**
- Modify: MonthlyMoney/WheelOfMoneyView.swift
- Modify: MonthlyMoney/MonthView.swift
- Modify: MonthlyMoney/MonthItemEditorDraft.swift
- Modify: MonthlyMoneyUITests/MonthlyMoneyUITests.swift
- Modify: MonthlyMoneyTests/MonthlyMoneyTests.swift

**Interfaces:**
- WoM displays monthly target, annualized cost, and current-first 24-month occurrence groups from AppState.womOccurrences.
- WoM rows have stable accessibility identifiers based on repeat ID and scheduled civil date.
- Tapping a projected row opens its landing-month planned-item editor; saving this occurrence writes only that row and does not materialize other dates.
- The editor defaults to This occurrence; This and future is explicit. Interval changes are unavailable in occurrence-only scope.
- Delete, end repeat, and mode-conversion actions display their scope explicitly.
- WoM rendering and navigation remain read-only.

- [ ] Step 1: Add failing UI tests for month ordering, occurrence rows, scope labels, and no writes on navigation.

Use accessibility identifiers on test targets, not text-only selection. Verify current month is first and multiple same-series rows remain independently selectable.

- [ ] Step 2: Run focused UI tests and verify failure.

Run the focused xcodebuild test command from Task 1.

Expected: redesigned WoM accessibility elements and edit scopes are absent.

- [ ] Step 3: Replace WoM content and wire editor choices.

Remove annual Wheel item metrics, paid toggles, and month-of-year editor from this screen. Keep old persisted Wheel items readable and preserve Settings' automatic savings toggle.

- [ ] Step 4: Run focused UI, draft, and interaction tests.

Expected: WoM is read-only until an explicit action; occurrence-only and this-and-future route to distinct state operations.

- [ ] Step 5: Commit the UI milestone.

---

### Task 7: Savings target and automatic monthly row

**Files:**
- Modify: MonthlyMoney/AppState.swift
- Modify: MonthlyMoney/Repository.swift
- Modify MonthlyMoney/SettingsView.swift only if existing setting wording needs updating
- Modify: MonthlyMoneyTests/MonthlyMoneyTests.swift

**Interfaces:**
- Expose annualizedPeriodicRepeatCost(effectiveOn:) and monthlyPeriodicRepeatSavingsTarget(effectiveOn:) as Decimal values from revisions effective on the target budget month's start date.
- An ended repeat contributes zero on or after its exclusive end date; a future-effective revision does not affect earlier targets.
- autoGenerateWoMSavingsEveryMonth remains stored and editable in Settings.
- Month population creates WoM savings using the target at the target month start. The existing row-existence guard remains and never replaces an existing row.

- [ ] Step 1: Add failing AppState tests for current/future revisions, exclusive end date, debit-only aggregation, long intervals, and target-month-effective generation.
- [ ] Step 2: Run savings tests and verify failure.

Run the focused xcodebuild test command from Task 1.

Expected: savings still come from Wheel of Money items rather than active repeat revisions.

- [ ] Step 3: Replace WheelOfMoneyCalculator input in monthly population.

Sum fixed debit revisions with Decimal operations and add the resulting Decimal as the planned amount. Do not calculate annualized rates through Double.

- [ ] Step 4: Run savings, auto-generation, and populated-month tests.

Expected: the current setting creates one savings row at the target rate and preserves any existing row.

- [ ] Step 5: Commit the savings milestone.

---

### Task 8: Full migration, sharing, build, and test verification

**Files:**
- Modify: MonthlyMoneyTests/MonthlyMoneyTests.swift
- Modify: MonthlyMoneyUITests/MonthlyMoneyUITests.swift only for uncovered UI acceptance cases
- Review: every changed source and migration file

- [ ] Step 1: Run all focused SwiftData/Core Data migration tests.

Verify private/shared persistence, sharing/unsharing, restart round trip, stable IDs, revision history, skip retention, and no orphan repeats or imported item links.

- [ ] Step 2: Run full MonthlyMoney XCTest and UI suites.

Run: rtk proxy xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,name=iPhone 16 Pro' -derivedDataPath /private/tmp/MonthlyMoney-periodic-final

Expected: every app and UI test passes with zero failures.

- [ ] Step 3: Run the iOS app build.

Run: rtk proxy xcodebuild build -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'generic/platform=iOS' -derivedDataPath /private/tmp/MonthlyMoney-periodic-final

Expected: BUILD SUCCEEDED.

- [ ] Step 4: Run the standalone core package suite.

Run: rtk proxy swift test --package-path MonthlyMoneyCorePackage --scratch-path /private/tmp/MonthlyMoneyCorePackage-periodic-final

Expected: all 45 existing core tests and any new package tests pass.

- [ ] Step 5: Review final changes and evidence.

Run rtk git diff --check, inspect the branch diff, and verify the original workspace still contains its three pre-existing edits. Report app coverage separately from migration, sharing, and UI coverage; identify simulator or Xcode toolchain limitations precisely.

- [ ] Step 6: Commit the final implementation.
