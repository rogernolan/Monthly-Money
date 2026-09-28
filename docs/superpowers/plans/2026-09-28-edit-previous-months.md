# Edit previous months Implementation Plan

> **For agentic workers:** Use inline execution of these tasks in order. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an owner-controlled budget setting that, when enabled, allows all existing editing actions on previous budget months.

**Architecture:** Store the option as a Boolean on `Budget`, defaulting to `false` in SwiftData and the Core Data mapping. `AppState` will provide one effective month-edit permission, and `SettingsView` and `MonthView` will use that permission consistently while retaining payday-based month classification.

**Tech Stack:** Swift, SwiftUI, SwiftData, Core Data, XCTest, Swift Package tests.

## Global Constraints

- Accounts are private by default; shared accounts and dependent records follow existing store behavior.
- Use Decimal for all money. Never Double.
- Keep changes small and test-driven.
- Any data model change must include an explicit migration.
- After each milestone: build + run tests.
- Budget month boundaries are payday-to-payday.

---

## Files and responsibilities

- `MonthlyMoneyCorePackage/Sources/MonthlyMoneyCore/DomainModels.swift`: persisted SwiftData `Budget` property and initializer default.
- `MonthlyMoney/DomainModels.swift`: app-side `Budget` property and initializer default.
- `MonthlyMoney/CoreDataMapping.swift`: Core Data attribute default and read/write mapping for old and new budgets.
- `MonthlyMoney/Repository.swift`: copy budget setting through existing budget update/copy paths where applicable.
- `MonthlyMoney/AppState.swift`: setting getter/setter and effective selected-month edit permission.
- `MonthlyMoney/SettingsView.swift`: owner-controlled switch.
- `MonthlyMoney/MonthView.swift`: all past-month action gates.
- `MonthlyMoneyTests/MonthlyMoneyTests.swift`: setting persistence and month permission tests.

### Task 1: Persist the setting with a default-off migration

**Interfaces:** `Budget.allowsPreviousMonthEditing: Bool`, default `false`.

- [ ] Add a test to `MonthlyMoneyTests.swift` proving a new budget starts with the setting off and that saving/reloading preserves `true`.
- [ ] Run the focused MonthlyMoney test and confirm the test fails because the property is absent.
- [ ] Add `allowsPreviousMonthEditing` with default `false` to both Budget representations and their initializers.
- [ ] Add a nonoptional Core Data Boolean attribute with default `false`; map the field both directions, using `false` when an older stored object has no value.
- [ ] Inspect repository budget copying and add the field wherever budget settings are copied between representations.
- [ ] Run the focused test and confirm it passes; build and run the core and app tests for this milestone.

### Task 2: Expose setting and one selected-month edit rule

**Interfaces:** `AppState.allowsPreviousMonthEditing: Bool`; `AppState.canEditSelectedMonth: Bool`.

- [ ] Add tests showing the selected current month is editable, a past month is locked by default, and a past month becomes editable when the setting is enabled.
- [ ] Run the focused test and confirm it fails because the setting and permission are absent.
- [ ] Add a setter that follows `canEditBudgetSettings`, persists the value, and notifies SwiftUI after saving.
- [ ] Define `canEditSelectedMonth` as `!isSelectedMonthInPast || allowsPreviousMonthEditing`; leave future-month behavior to each existing control.
- [ ] Run the focused tests and confirm they pass; build and run the core and app tests for this milestone.

### Task 3: Apply the permission to every past-month control

**Interfaces:** Settings binds to `AppState.allowsPreviousMonthEditing`; month controls read `AppState.canEditSelectedMonth`.

- [ ] Add “Allow editing previous months” to an appropriate section in `SettingsView`, disabled when `!state.canEditBudgetSettings`.
- [ ] Replace past-month-only guards in `MonthView` for balance editing, add entry, item paid state, item editing, editor save fields, and delete swipe with the shared selected-month permission.
- [ ] Preserve current/future constraints explicitly. In particular, keep existing rules that prevent editing future month balances and do not enable past-month automatic operations unrelated to direct editing.
- [ ] Build and run app and core tests; inspect all `isSelectedMonthInPast` edit gates to confirm none remain unintentionally locked.

### Task 4: Verify persistence compatibility and finish

- [ ] Run the complete `MonthlyMoneyCorePackage` test suite and all `MonthlyMoneyTests`.
- [ ] Build the iOS app target and inspect compiler diagnostics.
- [ ] Review the diff for accidental schema changes, check `git diff --check`, and report any unverified platform-specific migration behavior.
