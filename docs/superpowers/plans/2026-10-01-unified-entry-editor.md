# Unified Entry Editor Implementation Plan

> **For agentic workers:** Execute these tasks inline in the existing periodic-repeats WoM PR worktree; no subagent delegation is requested.

**Goal:** Give Month and WoM entries the approved common form layout and complete short-periodic editing and deletion from the Month editor.

**Architecture:** Keep Month and WoM save paths, since Month edits stored planned rows and WoM can edit projected occurrences. Share small SwiftUI controls for Type and Repeat, and centralise repeat-mode availability. Add one repository operation to detach an individual periodic occurrence to a one-off planned row while preserving identity and metadata.

**Tech Stack:** SwiftUI, SwiftData/Core Data-backed repository, XCTest.

## Global Constraints

- Use Decimal for money.
- Honour payday-based budget months and historical edit permissions.
- Preserve imported links, paid state, and planned-item identity when detaching a periodic occurrence.
- Keep repeat-period help in the same cell as its control.
- Build and test after each behaviour milestone.

---

### Task 1: Periodic occurrence to None

**Files:** `MonthlyMoney/AppState.swift`, `MonthlyMoney/Repository.swift`, both concrete store implementations, `MonthlyMoneyTests/MonthlyMoneyTests.swift`.

1. Add a failing test: detaching the second occurrence leaves a one-off row with the same ID and values, suppresses its scheduled periodic date, and leaves the third occurrence projected.
2. Run the focused test and confirm the expected failure.
3. Add a repository transaction that saves the skip, removes the occurrence record, and upserts the row as one-off. Expose it through `AppState.detachPeriodicOccurrence` with existing month permissions.
4. Run the focused test, then the relevant MonthlyMoneyTests suite and app build.

### Task 2: Common editor presentation

**Files:** `MonthlyMoney/MonthView.swift`, `MonthlyMoney/WheelOfMoneyView.swift`, a small shared SwiftUI control file if needed, and relevant tests.

1. Add a failing test for allowed repeat-mode transitions: a new entry can choose all modes, an existing Calendar or Periodic entry can choose its current mode or None, and direct Calendar/Periodic conversions are rejected.
2. Run it to confirm the expected failure, then implement the mode rule.
3. Arrange both editors into Details, Repeat details, and Notes/Delete. Put Title, Match string, Amount, coloured Type, and multipart Repeat in Details. Show Calendar day or Periodic start date and repeat period conditionally. Retain imported-item context and help text.
4. Make the Month editor's periodic Delete button call the scope-aware periodic operation. Keep calendar and one-off deletion on the current stored-row path. Route periodic-to-None saves through Task 1.
5. Keep Calendar copying after a Calendar-to-None occurrence edit by storing the original calendar details on the one-off row, then resuming Calendar mode from that snapshot in the next month. Add a failing month-rollover test before changing the copy path and migrate both stores explicitly.
6. Run the focused tests and build.

### Task 3: Final verification and PR update

**Files:** all changed files.

1. Review the diff against every line of the approved design; check wording, layout, mode transitions, edit scope, and deletion.
2. Run the full MonthlyMoneyTests suite and app build, plus `git diff --check`.
3. Commit and push the verified changes to the existing PR branch.
