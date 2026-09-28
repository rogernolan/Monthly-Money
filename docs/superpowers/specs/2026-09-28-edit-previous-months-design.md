# Edit previous months

## Decision

Settings will include an “Allow editing previous months” switch. It defaults to off. The setting belongs to the budget, follows it across devices, and can be changed by the budget owner under the existing budget settings permission rule.

The existing payday-based `currentYearMonth` calculation continues to define whether a selected month is current, previous, or future. When the switch is on, the Month screen enables all existing editing actions for a previous month: changing its balance, adding entries, editing entries, changing paid state, and deleting entries. When it is off, previous months remain read-only. Future-month behavior does not change.

## Data and migration

The Budget model will store the Boolean setting with a default of `false`. The SwiftData and Core Data representations will use the same default. Existing persisted budgets must migrate with the switch off so an app update does not silently unlock historical editing. The Core Data model mapping and the SwiftData model schema must both preserve this default when reading existing budgets.

## Implementation boundary

`AppState` will expose the persisted value and the effective permission for the selected month. `SettingsView` will bind the switch to the budget setting and disable it when the current user cannot edit budget settings. `MonthView` will use the effective permission consistently for balance editing, entry creation, entry editing, paid-state changes, and deletion. Current- and future-month rules remain as they are.

## Verification

Tests will cover the default-off behavior, persistence of the setting, and enabled access to past-month actions while preserving the payday boundary and future-month behavior. The app build and test suites will run after implementation, in line with the project instructions.
