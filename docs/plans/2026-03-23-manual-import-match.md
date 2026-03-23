# Manual Import Match Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a manual match flow for imported-unplanned month items so the user can merge one into an existing unpaid planned item from the details screen.

**Architecture:** Extend the month item details editor with a conditional match action and an `Unplanned` toggle backed by `PlannedItemSource`. Implement the merge in `AppState` so the UI stays thin: move the import link onto the selected target item, update the target fields, delete the source imported-unplanned item, and keep the editor open on the matched target.

**Critical Assumptions:**
- The current details editor navigation can swap from one edited `PlannedItem` to another by driving `navigationDestination(item:)` state in `MonthView.swift`.
- `PlannedItem.source == .importedUnplanned` is the correct backing for the new `Unplanned` switch and existing row indicator behavior.
- We need targeted delete support for one imported transaction record rather than account-wide deletion; this will be implemented in the repository/store layer first.

**Tech Stack:** SwiftUI, SwiftData/CoreData repository abstraction, XCTest

---

### Task 1: Add repository support for deleting one imported transaction record

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/Repository.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/CoreDataAccountDataStore.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/CoreDataMapping.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Steps:**
1. Write a failing test that saves one imported transaction record and deletes it by id without affecting other records.
2. Run the focused test and confirm it fails for the missing API.
3. Add `deleteImportedTransactionRecord(id:)` through the repository and both backing stores.
4. Re-run the focused test and confirm it passes.

### Task 2: Implement manual import-match merge behavior in app state

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Steps:**
1. Write failing tests for:
   - candidate filtering excludes imported-unplanned items and paid items
   - matching moves import linkage to the target item
   - target amount and due day are updated from the source
   - blank `matchingString` is filled, existing non-blank value is preserved
   - source imported-unplanned item is deleted
2. Run those focused tests and confirm they fail.
3. Add `AppState` helpers for eligible match candidates and the merge operation.
4. Re-run the focused tests and confirm they pass.

### Task 3: Add the editor UI flow

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/MonthView.swift`
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoney/MonthItemEditorDraft.swift`
- Test: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Steps:**
1. Add a failing view-model/content test for the `Unplanned` toggle behavior if needed.
2. Add the `Unplanned` switch to the details editor, bound to `source`.
3. Add the `Match to planned item` action for imported-unplanned items only.
4. Push a picker of current-month unpaid non-imported-unplanned items.
5. After a selection, run the merge and swap the editor to the matched target item instead of dismissing to the list.
6. Re-run focused tests for the editor-related behavior.

### Task 4: Verify end to end

**Files:**
- Modify: `/Users/rog/Development/MonthlyMoney/MonthlyMoneyTests/MonthlyMoneyTests.swift`

**Steps:**
1. Run the focused manual-match and repository tests together.
2. Run `xcodebuild build -project /Users/rog/Development/MonthlyMoney/MonthlyMoney.xcodeproj -scheme MonthlyMoney -destination 'platform=iOS Simulator,id=73D6AA6F-3E4C-431B-A24B-05113EC8CED4'`.
3. Commit with a message describing the manual import match feature.
