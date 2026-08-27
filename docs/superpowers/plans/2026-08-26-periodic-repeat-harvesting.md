# Periodic Repeat Harvesting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add explicit one-off, calendar, and periodic repeat modes, and let periodic occurrences be harvested into a target payday-to-payday month across empty intervening months.

**Architecture:** Planned-item occurrences remain the source of truth. A lightweight `PopulatedMonth` marker records that the user explicitly processed a month, while the repository exposes all earlier periodic occurrences so the target month can be generated without creating rows in skipped months. The app keeps ordinary calendar copying and periodic harvesting as separate paths.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Core Data/CloudKit, XCTest, the `MonthlyMoneyCorePackage` Swift package.

## Global Constraints

- Use Decimal for all money. Never Double.
- Keep the changes small and test-driven.
- Any data model change must include an explicit migration.
- After each milestone: build + run tests.
- Budget month boundaries are payday-to-payday, not calendar months.
- New periodic items create only their anchor row.
- Periodic rows are created only in the month explicitly being populated.
- Preserve stored calendar-day and periodic-interval data when changing repeat modes.
- Legacy Floating items migrate to Periodic with 28 days and day 1 as the anchor.

---

### Task 1: Add repeat modes and the populated-month model

**Files:**
- Modify: `MonthlyMoney/DomainModels.swift`
- Modify: `MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/DomainModels.swift`
- Modify: `MonthlyMoney/MonthlyMoneyRepositoryBootstrap.swift`
- Modify: `MonthlyMoney/CoreDataMapping.swift`
- Modify: `MonthlyMoney/Repository.swift`
- Modify: `MonthlyMoney/CoreDataAccountDataStore.swift`
- Test: `MonthlyMoneyTests/MonthlyMoneyTests.swift`
- Test: `MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/SharingAndMonthTests.swift`

**Interfaces:**
- Produce `RepeatMode: String, Codable` with `.oneOff`, `.calendar`, and `.periodic`.
- Produce `PopulatedMonth` with `id`, `budgetID`, and `monthKey`.
- Add `repeatMode` to `PlannedItem` without removing `dueDay`, `repeatDays`, or `recurrenceID`.
- Add store/repository operations for fetching, upserting, and deleting populated-month markers.

- [ ] **Step 1: Write failing model and migration tests.**

Add tests that assert:

```swift
XCTAssertEqual(RepeatMode.periodic.rawValue, "periodic")
let marker = PopulatedMonth(budgetID: budget.id, monthKey: month)
XCTAssertEqual(marker.monthKey, month)
XCTAssertEqual(CoreDataModelBuilder.legacyModel.versionIdentifiers, ["MonthlyMoney.v2"])
XCTAssertEqual(CoreDataModelBuilder.sharedModel.versionIdentifiers, ["MonthlyMoney.v3"])
```

Also verify the new Core Data entity and `repeatMode` attribute are optional/defaulted for old rows, and that a legacy Floating row maps to periodic/28/day-1 migration values.

- [ ] **Step 2: Run the focused tests and confirm they fail.**

Run:

```bash
rtk swift test --package-path MonthlyMoneyCorePackage
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testRepeatModePersistence -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testLegacyFloatingMigration CODE_SIGNING_ALLOWED=NO
```

Expected: compilation/test failures because the mode, marker, and migration interfaces do not yet exist.

- [ ] **Step 3: Implement the model and explicit schema migration.**

Add the enum and marker to both domain model copies. Add `repeatMode` to `PlannedItem`, defaulting new items to `.oneOff` unless the initializer receives an explicit mode. Add the marker to the SwiftData schema.

Extend the existing Core Data versioned-model builder with a v2 source model and v3 destination model. Add the `CDPopulatedMonth` entity, its budget relationship, and the `repeatMode` attribute. The migration must preserve all existing attributes and map old rows as follows:

```swift
if oldRepeatDays != nil {
    repeatMode = .periodic
} else if oldDueDay != nil && oldCopiesAutomatically {
    repeatMode = .calendar
} else {
    repeatMode = .oneOff
}
```

For old Floating rows (`dueDay == nil && copiesToNextMonthAutomatically == true`), set `repeatMode = .periodic`, `repeatDays = 28`, `dueDay = 1`, and generate a recurrence ID. Keep non-copying rows one-off. Use the project’s explicit version/mapping migration mechanism rather than relying only on inferred hashes.

- [ ] **Step 4: Implement marker storage in all data stores.**

Extend `AccountDataStore` with:

```swift
func fetchPopulatedMonths(budgetID: UUID) throws -> [PopulatedMonth]
func upsertPopulatedMonths(_ months: [PopulatedMonth]) throws
func deletePopulatedMonths(budgetID: UUID) throws
```

Implement these methods in `InMemoryAccountDataStore`, `SwiftDataAccountDataStore`, and `CoreDataAccountDataStore`. Add Core Data mapping and the `CDPopulatedMonth` entity relationship. Include markers in budget deletion and private-to-shared budget snapshot/insert paths so sharing cannot leave orphaned markers.

- [ ] **Step 5: Run the model/store tests and commit.**

Run:

```bash
rtk swift test --package-path MonthlyMoneyCorePackage
rtk xcodebuild build -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' CODE_SIGNING_ALLOWED=NO
```

Expected: all package tests pass and the app build succeeds. Commit:

```bash
rtk git add MonthlyMoney MonthlyMoneyCorePackage MonthlyMoneyTests
rtk git commit -m "Add repeat modes and populated month model"
```

### Task 2: Add repository queries and repeat-mode persistence behavior

**Files:**
- Modify: `MonthlyMoney/Repository.swift`
- Modify: `MonthlyMoney/DomainModels.swift`
- Modify: `MonthlyMoney/CoreDataMapping.swift`
- Modify: `MonthlyMoneyTests/MonthlyMoneyTests.swift`
- Test: `MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Interfaces:**
- Produce `AccountRepository.isMonthPopulated(_:) throws -> Bool`.
- Produce `AccountRepository.populatedMonths() throws -> [PopulatedMonth]`.
- Produce `AccountRepository.markMonthPopulated(_:) throws`.
- Produce `AccountRepository.periodicItems(before:) throws -> [PlannedItem]`.
- Ensure all three methods resolve the active budget, visible account scope, and correct private/shared store.

- [ ] **Step 1: Write failing repository tests.**

Cover marker round trips, marker deduplication, deletion with a budget, and periodic history filtering:

```swift
try repository.markMonthPopulated(month)
XCTAssertTrue(try repository.isMonthPopulated(month))
try repository.markMonthPopulated(month)
XCTAssertEqual(try repository.populatedMonths().filter { $0.monthKey == month }.count, 1)

let history = try repository.periodicItems(before: targetMonth)
XCTAssertTrue(history.allSatisfy { $0.repeatMode == .periodic && $0.resolvedMonthKey! < targetMonth })
```

Include private/shared visibility tests so a participant sees markers and periodic rows only from the active budget.

- [ ] **Step 2: Run the tests and verify the new APIs fail.**

Run:

```bash
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testPopulatedMonthRepositoryRoundTrip -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testPeriodicHistoryIsScopedAndBeforeTarget CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 3: Implement the repository methods.**

Fetch markers through the active budget’s store, upsert one marker by `(budgetID, monthKey)`, and touch the owning budget’s `updatedAt` after a successful write. Fetch periodic history with `repeatMode == .periodic`, `repeatDays > 0`, a non-nil recurrence ID, and an earlier `monthKey`; return all visible accounts from the active budget without including shared/private duplicates.

Update budget snapshot and deletion code to include populated-month records. Preserve inactive `dueDay`, `repeatDays`, and `recurrenceID` values when saving a planned item; only `repeatMode` changes which values are active.

- [ ] **Step 4: Run the repository tests and commit.**

Run:

```bash
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testPopulatedMonthRepositoryRoundTrip -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testPeriodicHistoryIsScopedAndBeforeTarget CODE_SIGNING_ALLOWED=NO
```

Expected: focused tests pass. Commit:

```bash
rtk git add MonthlyMoney MonthlyMoneyTests
rtk git commit -m "Add periodic history and populated month repository APIs"
```

### Task 3: Implement target-only periodic harvesting

**Files:**
- Modify: `MonthlyMoney/DomainModels.swift`
- Modify: `MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/DomainModels.swift`
- Modify: `MonthlyMoney/AppState.swift`
- Modify: `MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/SharingAndMonthTests.swift`
- Test: `MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Interfaces:**
- Produce a pure planner such as `PlannedItem.periodicOccurrences(from:into:paydayDay:calendar:) -> [PlannedItem]`.
- The planner consumes historical periodic occurrences and returns rows only in the target month.
- `AppState.populateSelectedMonthFromPrevious()` must call ordinary copying and periodic harvesting separately, then mark the target populated only after both succeed.

- [ ] **Step 1: Write failing recurrence tests.**

Add deterministic Gregorian tests for:

```swift
// April 4 + 28 days => May 2, then May 30, then June 27.
XCTAssertEqual(harvest(history, into: may).map(\.dueDay), [2, 30])
XCTAssertEqual(harvest(history + mayRows, into: june).map(\.dueDay), [27])
```

Also cover 32-day and 100-day intervals, payday boundaries, year/leap-year boundaries, separate recurrence IDs, and no output for skipped months. Assert that ordinary calendar items passed to the ordinary-copy path never enter periodic harvesting.

- [ ] **Step 2: Run package tests and confirm the new scenarios fail.**

Run:

```bash
rtk swift test --package-path MonthlyMoneyCorePackage
```

- [ ] **Step 3: Implement the pure planner.**

For each recurrence ID, select the latest concrete date from the historical rows. Advance by the positive interval until the generated date reaches the target budget-month range. Add all generated dates in `[previous payday, current payday)`, assigning the target `monthKey`, preserving item fields/mode/interval/recurrence ID, and resetting paid state. Do not emit rows for earlier months or ordinary repeat modes.

- [ ] **Step 4: Integrate the planner into AppState.**

In `populateSelectedMonthFromPrevious()`:

```swift
let previous = try repository.plannedItems(for: previousMonth(of: selectedMonth))
copyCalendarItems(previous.filter { $0.repeatMode == .calendar }, into: selectedMonth)
let history = try repository.periodicItems(before: selectedMonth)
for item in PlannedItem.periodicOccurrences(from: history, into: selectedMonth, paydayDay: dailyBudgetPaydayDay) {
    try repository.createPlannedItem(item)
}
try repository.markMonthPopulated(selectedMonth)
try refresh()
```

Make repeated population idempotent by checking existing target IDs/dates/recurrence IDs before inserting. Keep the marker write after all item writes; on error leave the target unmarked.

- [ ] **Step 5: Run recurrence and AppState tests and commit.**

Run:

```bash
rtk swift test --package-path MonthlyMoneyCorePackage
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testPopulatingDistantPeriodicMonth -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testPeriodicChainOneTwoOne CODE_SIGNING_ALLOWED=NO
```

Expected: all recurrence tests pass. Commit:

```bash
rtk git add MonthlyMoney MonthlyMoneyCorePackage MonthlyMoneyTests
rtk git commit -m "Harvest periodic repeats across empty months"
```

### Task 4: Update month navigation and the three-mode editor

**Files:**
- Modify: `MonthlyMoney/AppState.swift`
- Modify: `MonthlyMoney/MonthItemEditorDraft.swift`
- Modify: `MonthlyMoney/MonthView.swift`
- Modify: `MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Interfaces:**
- `AppState.canPopulateSelectedMonthFromPrevious` must require the target to be unpopulated and empty.
- `AppState.canNavigateToNextMonth` must use populated markers/entries rather than `monthItems.isEmpty` alone.
- `MonthItemEditorDraft` must expose `repeatMode`, preserve inactive settings, and validate positive periodic intervals.

- [ ] **Step 1: Write failing UI/state tests.**

Test that:

```swift
XCTAssertTrue(state.canPopulateSelectedMonthFromPrevious)
state.populateSelectedMonthFromPrevious()
XCTAssertTrue(try repository.isMonthPopulated(state.selectedMonth))
XCTAssertTrue(state.canNavigateToNextMonth)
```

Test mode switching preserves day and interval data, one-off ignores preserved recurrence data, calendar mode shows/uses the day picker, periodic mode shows/uses only the repeat-day field, and invalid/zero/negative/non-integer intervals cannot save.

- [ ] **Step 2: Run focused tests and confirm the current UI/state behavior fails.**

Run:

```bash
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testEmptyPopulatedMonthAllowsNavigation -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testRepeatModePreservesInactiveSettings CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 3: Implement marker-aware navigation.**

Load the selected month’s marker state during `refresh()`. Offer Populate only when the selected month is the next unpopulated, editable, empty month. Permit moving onward when the current month has entries or a marker, including a marker-only month. Keep opening a month read-only with respect to population.

- [ ] **Step 4: Implement the three-mode editor.**

Replace `MonthDueSelection` with mode-aware state:

```swift
enum MonthRepeatMode: Hashable {
    case oneOff
    case calendar
    case periodic
}
```

Show no repeat editor for one-off, the current day picker for calendar, and only `Repeat days` for periodic. Preserve `dueDay`, `repeatDays`, and `recurrenceID` when changing modes. Use the item’s existing `dueDay` as the periodic anchor; new periodic items use their entered date. Ensure one-off mode does not copy while leaving inactive settings intact.

- [ ] **Step 5: Run focused UI/state tests, build, and commit.**

Run:

```bash
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testEmptyPopulatedMonthAllowsNavigation -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testRepeatModePreservesInactiveSettings CODE_SIGNING_ALLOWED=NO
rtk xcodebuild build -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' CODE_SIGNING_ALLOWED=NO
```

Expected: focused tests pass and the app build succeeds. Commit:

```bash
rtk git add MonthlyMoney MonthlyMoneyTests
rtk git commit -m "Add three repeat modes and marker-aware navigation"
```

### Task 5: Full verification and follow-up PR handoff

**Files:**
- Modify: `docs/superpowers/specs/2026-08-26-periodic-repeat-harvesting-design.md` only if implementation decisions require a documented correction.
- Test: `MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/SharingAndMonthTests.swift`
- Test: `MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Interfaces:**
- Verify the complete implementation against the approved design and keep the follow-up branch based on `origin/main`.

- [ ] **Step 1: Run the complete package suite.**

```bash
rtk swift test --package-path MonthlyMoneyCorePackage
```

Expected: all package tests pass, including the periodic 1:2:1 chain and distant-month tests.

- [ ] **Step 2: Run the complete app test target and record any environment-only failure.**

```bash
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests CODE_SIGNING_ALLOWED=NO
```

Expected: no feature failures. If the known simulator malloc crash recurs, reproduce it against `origin/main`, record the exact failure in the PR, and do not call the full app suite passing.

- [ ] **Step 3: Run the device build and diff checks.**

```bash
rtk xcodebuild -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'id=6F0B04B2-F4E6-5843-BE61-6DDA11465F0D' -derivedDataPath /tmp/MonthlyMoney-periodic-device build
rtk git diff --check
rtk git status -sb
```

Expected: signed device build succeeds, diff check is clean, and the worktree contains only intentional committed changes.

- [ ] **Step 4: Request review, push, and update the follow-up PR.**

Use the branch `codex/periodic-repeat-harvesting`, push it to `origin`, create a PR against `main`, and include the package/app/device verification results. Preserve the worktree for review feedback.
