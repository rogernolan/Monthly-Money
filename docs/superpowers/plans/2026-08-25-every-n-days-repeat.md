# Every n Days Repeat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a persisted `Every n days` repeat mode whose anchor and generated occurrences advance by calendar days, including multi-occurrence month copies and deterministic continuation from only the latest occurrence.

**Architecture:** Keep the existing `PlannedItem` month/day representation and add optional repeat metadata: `repeatDays` and a stable `recurrenceID`. Put pure calendar arithmetic and grouping in `PlannedItem` helpers, keep save/prompt coordination in `AppState`, and keep picker state/validation in `MonthItemEditorDraft`. Update both the SwiftData-facing app model and the Core Data-backed core model plus their mapping/model builders.

**Tech Stack:** Swift 6, SwiftUI, SwiftData, Core Data, CloudKit-compatible model attributes, XCTest, Swift Package Manager, `xcodebuild`.

## Global Constraints

- Use `Decimal` for all money. Never `Double`.
- Keep changes small and test-driven.
- Any data model change includes an explicit migration/defaulting test.
- After each milestone, build and run tests.
- Budget month boundaries remain payday-to-payday; recurrence arithmetic uses real calendar dates represented by `monthKey` and `dueDay`.
- New every-n-days items create only their entered anchor in the selected month.
- Converting an existing item makes that edited row the anchor and may offer all later occurrences in the selected month.
- Only the latest occurrence in a recurrence series continues into the next month.

---

### Task 1: Add pure recurrence metadata and calendar helpers

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/DomainModels.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/DomainModels.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/SharingAndMonthTests.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Interfaces:**
- `PlannedItem` gains `repeatDays: Int?` and `recurrenceID: UUID?` with nil defaults in all existing initializers.
- Add a pure helper equivalent to `static func everyNDaysOccurrences(from anchor: PlannedItem, in month: YearMonth, calendar: Calendar = .current) -> [PlannedItem]` that returns later occurrences only, never the anchor.
- Add a pure helper equivalent to `static func copiedItems(from sourceItems: [PlannedItem], into month: YearMonth, calendar: Calendar = .current) -> [PlannedItem]` that preserves ordinary items and advances every-n-days series from the latest source occurrence.

- [ ] **Step 1: Write failing tests for metadata and calendar arithmetic**

Add tests that construct a 28-day item anchored on 26 February 2026 and assert that the next occurrence is 26 March and the next is 23 April. Add a 10-day item anchored on 1 March 2026 and assert that later same-month occurrences are 11, 21, and 31 March. Add a target-month copy test where source occurrences are 1, 11, 21, and 31 March and target occurrences are 10, 20, and 30 April. Add a test with an unrelated item using a different `recurrenceID` and assert it is not grouped. Add a test that source rows containing several occurrences produce continuations only from the latest row.

Use assertions shaped like:

```swift
let dates = PlannedItem.everyNDaysOccurrences(from: anchor, in: march).compactMap { $0.dueDay }
XCTAssertEqual(dates, [11, 21, 31])
```

- [ ] **Step 2: Run the focused tests and verify the expected failure**

Run:

```bash
rtk swift test --package-path MonthlyMoneyCorePackage --filter SharingAndMonthTests
```

Expected: compilation/test failure because `repeatDays`, `recurrenceID`, and the new helpers do not exist yet.

- [ ] **Step 3: Implement the minimum model and helper behavior**

Add the two optional properties and pass them through the designated and convenience initializers. Build a concrete date from `YearMonth` plus `dueDay` using a Gregorian calendar. For same-month occurrences, repeatedly add `repeatDays` days, stop when the month changes, and make each result with `PlannedItem.copied(from:..., into:)` while replacing its `dueDay` with the generated calendar day and preserving the series metadata. For next-month copying, partition valid repeat rows by `recurrenceID`, choose the maximum concrete date in each group, and generate all dates after it whose month is the target. Treat malformed repeat rows (missing ID, missing due day, or non-positive interval) as ordinary items rather than crashing. Keep ordinary floating/fixed-day copying byte-for-byte equivalent to current behavior.

- [ ] **Step 4: Run the focused tests and the app model tests**

Run:

```bash
rtk swift test --package-path MonthlyMoneyCorePackage --filter SharingAndMonthTests
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests CODE_SIGNING_ALLOWED=NO
```

Expected: all recurrence and existing month-copy tests pass.

- [ ] **Step 5: Commit the pure model milestone**

```bash
rtk git add MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/DomainModels.swift MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/SharingAndMonthTests.swift MonthlyMoney/DomainModels.swift MonthlyMoneyTests/MonthlyMoneyTests.swift
rtk git commit -m "Add every-n-days recurrence helpers"
```

### Task 2: Persist repeat fields and cover migration/defaults

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/CoreDataMapping.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/DomainModels.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/DomainModels.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Interfaces:**
- Core Data `PlannedItem` entity contains optional `repeatDays` integer and optional `recurrenceID` UUID attributes.
- `CoreDataMapping.apply` writes both fields; `plannedItem(from:)` reads both with nil fallback for pre-migration rows.
- SwiftData model initializers expose the same optional fields, so both private and shared stores use identical schema properties.

- [ ] **Step 1: Write the failing persistence and model-schema tests**

Add a Core Data model test asserting `plannedItemEntity.attributesByName["repeatDays"]?.attributeType == .integer16AttributeType` and `recurrenceID` is UUID. Add a round-trip test that saves a `PlannedItem` with `repeatDays: 28` and a known `recurrenceID`, fetches it, and asserts both values survive. Add a legacy-row test that creates a managed object without the new fields and asserts the mapper returns nil values.

- [ ] **Step 2: Run the tests and verify they fail**

Run:

```bash
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testCoreDataModelBuilderDefinesPlannedItemRepeatAttributes CODE_SIGNING_ALLOWED=NO
```

Expected: failure because the attributes and mapper support are absent.

- [ ] **Step 3: Add the model attributes and mapping defaults**

Extend the programmatic `CoreDataModelBuilder` planned-item entity with optional repeat attributes, with no default needed because nil is the legacy value. Update both model initializers and every `PlannedItem` reconstruction/copy path to pass through the fields. In the mapper, use `as? NSNumber` and `as? UUID` so missing legacy values become nil; in `apply`, write `repeatDays.map(NSNumber.init(value:))` and `recurrenceID`.

- [ ] **Step 4: Run migration-focused and package tests**

Run:

```bash
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests CODE_SIGNING_ALLOWED=NO
rtk swift test --package-path MonthlyMoneyCorePackage
```

Expected: all tests pass, including existing Core Data and sharing tests, with legacy items still having nil repeat metadata.

- [ ] **Step 5: Commit the persistence milestone**

```bash
rtk git add MonthlyMoney/CoreDataMapping.swift MonthlyMoney/DomainModels.swift MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/DomainModels.swift MonthlyMoneyTests/MonthlyMoneyTests.swift
rtk git commit -m "Persist every-n-days repeat metadata"
```

### Task 3: Add draft state, validation, and editor controls

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/MonthItemEditorDraft.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/MonthView.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Interfaces:**
- `MonthDueSelection` gains `.everyNDays` and keeps fixed-day/floating value behavior.
- `MonthItemEditorDraft` gains `repeatDaysText: String`, initializes it from `item.repeatDays`, exposes `repeatDays: Int?`, and includes `repeatDaysAreValid` in `canSave` whenever `.everyNDays` is selected.
- Save calls carry `repeatDays` and `recurrenceID` decisions to `AppState`; new entries pass nil ID so `AppState` creates one.

- [ ] **Step 1: Write failing draft tests**

Add tests asserting that an item with `repeatDays: 28` initializes as `.everyNDays` with text `"28"`; a draft with `repeatDaysText = "28"` exposes 28; blank, `0`, `-1`, and `"28.5"` make `canSave` false; and a floating/day draft remains valid without repeat text.

- [ ] **Step 2: Run the draft tests and verify failure**

Run:

```bash
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testMonthItemEditorDraftInitialisesEveryNDays CODE_SIGNING_ALLOWED=NO
```

Expected: compilation failure or assertion failure because the new selection/state does not exist.

- [ ] **Step 3: Implement the minimum draft behavior and UI**

Derive `.everyNDays` when `item.repeatDays` is positive; otherwise derive the existing selection from `dueDay`. Add a numeric-pad `TextField("Repeat days", text: ...)` immediately below the picker only when `.everyNDays` is selected. Keep the existing day picker tags and make the new option’s label exactly `Every n days`. When changing away from every-n-days, make the save payload clear repeat metadata.

- [ ] **Step 4: Run draft and full app tests**

Run:

```bash
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests CODE_SIGNING_ALLOWED=NO
```

Expected: all tests pass and the app target compiles with the conditional field.

- [ ] **Step 5: Commit the editor milestone**

```bash
rtk git add MonthlyMoney/MonthItemEditorDraft.swift MonthlyMoney/MonthView.swift MonthlyMoneyTests/MonthlyMoneyTests.swift
rtk git commit -m "Add every-n-days editor controls"
```

### Task 4: Wire creation, editing, and same-month population

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/MonthView.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Interfaces:**
- Extend `AppState.update(..., repeatDays: Int?, recurrenceID: UUID?)` and `createEntry(..., repeatDays: Int?, recurrenceID: UUID? = nil)` while preserving defaults for existing callers.
- Add an AppState/testable helper equivalent to `sameMonthOccurrences(after item: PlannedItem) -> [PlannedItem]` that delegates to the pure model helper.
- The editor uses a save confirmation state for conversion of an existing item when that helper returns non-empty occurrences; confirming persists the anchor plus all generated rows, declining persists only the anchor.

- [ ] **Step 1: Write failing AppState tests**

Add a test that creates a new 10-day entry anchored on 1 March and asserts only one March row exists. Add a test that edits an existing March 1 item to 10-day repeat, confirms population, and asserts rows on 1, 11, 21, and 31 March sharing one recurrence ID. Add a test that declines and asserts only March 1 exists. Add a test that converting back to fixed day clears `repeatDays` and `recurrenceID`.

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testCreatingEveryNDaysEntryCreatesOnlyAnchor CODE_SIGNING_ALLOWED=NO
```

Expected: compilation failure or missing-row assertions because AppState does not accept repeat metadata or populate same-month occurrences.

- [ ] **Step 3: Implement save and prompt coordination**

When creating with positive repeat days, assign a fresh recurrence ID to the anchor and do not call same-month generation. When editing an existing item into every-n-days, assign a fresh recurrence ID, persist the edited item, compute later same-month rows, and expose a confirmation action from the editor. On confirmation, create the generated rows through the repository; on cancellation/decline, leave the persisted anchor. Restore the original in-memory fields if persistence fails. Do not prompt for a new item.

- [ ] **Step 4: Run the focused and full app tests**

Run:

```bash
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests CODE_SIGNING_ALLOWED=NO
```

Expected: all AppState, editor-draft, Core Data, and existing behavior tests pass.

- [ ] **Step 5: Commit the creation/editing milestone**

```bash
rtk git add MonthlyMoney/AppState.swift MonthlyMoney/MonthView.swift MonthlyMoneyTests/MonthlyMoneyTests.swift
rtk git commit -m "Create and populate every-n-days entries"
```

### Task 5: Integrate multi-occurrence next-month copying

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/SharingAndMonthTests.swift`

**Interfaces:**
- `AppState.copyItems(_:to:)` delegates the complete source list to `PlannedItem.copiedItems(from:into:)`, then persists each returned item.

- [ ] **Step 1: Write failing integration tests**

Add a repository/AppState population test for a 28-day pension anchored on 26 March that produces 23 April in the next month. Add a test where the source month has occurrences on 1, 11, 21, and 31 March and the target month receives 10, 20, and 30 April, not copies from every source row. Add a year-boundary test for December to January and a February/leap-year test. Keep the existing ordinary-item tests and assert their results are unchanged.

- [ ] **Step 2: Run tests and verify failure**

Run:

```bash
rtk swift test --package-path MonthlyMoneyCorePackage --filter SharingAndMonthTests
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests/MonthlyMoneyTests/testAutomaticMonthCopyCreatesEveryNDaysOccurrences CODE_SIGNING_ALLOWED=NO
```

Expected: the new integration assertions fail because `copyItems` still copies each source row as a single same-day item.

- [ ] **Step 3: Replace source filtering with recurrence-aware result generation**

Remove the old loop over `automaticallyCopiedItems` in `AppState.copyItems` and persist the array returned by `PlannedItem.copiedItems`. Ensure repeat rows with `copiesToNextMonthAutomatically == false` are excluded before grouping, and ordinary eligible rows continue to use the existing copy constructor. Keep generated rows unpaid and stamped `.copiedFromPreviousMonth`.

- [ ] **Step 4: Run integration and full tests**

Run:

```bash
rtk swift test --package-path MonthlyMoneyCorePackage
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests CODE_SIGNING_ALLOWED=NO
```

Expected: all package and app tests pass, including multi-occurrence, latest-only, and ordinary-copy regression coverage.

- [ ] **Step 5: Commit the copy-forward milestone**

```bash
rtk git add MonthlyMoney/AppState.swift MonthlyMoneyTests/MonthlyMoneyTests.swift MonthlyMoneyCorePackage/Tests/MonthlyMoneyCoreTests/SharingAndMonthTests.swift
rtk git commit -m "Advance every-n-days series across months"
```

### Task 6: Final verification and handoff

**Files:**
- Modify: none unless verification exposes a regression.
- Test: existing full targets.

- [ ] **Step 1: Run the complete core package suite**

```bash
rtk swift test --package-path MonthlyMoneyCorePackage
```

Expected: all tests pass.

- [ ] **Step 2: Run the complete iOS unit test target**

```bash
rtk xcodebuild test -project MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4' -only-testing:MonthlyMoneyTests CODE_SIGNING_ALLOWED=NO
```

Expected: all `MonthlyMoneyTests` pass and the app compiles.

- [ ] **Step 3: Inspect the final diff and status**

```bash
rtk git diff HEAD~5 --check
rtk git status --short
```

Expected: no whitespace errors, no accidental generated files, and only the approved implementation/spec changes are present.

- [ ] **Step 4: Commit any final test-only correction**

If verification requires a code correction, add a regression test first, run the failing test, make the minimal fix, rerun both full suites, then commit with a focused message. Do not weaken or delete a previously passing test.
