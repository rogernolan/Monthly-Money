# Daily Import And Chart Design

## Goal
Expand OFX import to support a hidden daily account, then use that data to power a future Daily view chart without changing the visible daily UI until milestone 3.

## Scope
- Milestone 1: add split import UI when separate daily account mode is enabled, with minimal daily import that only updates current balance
- Milestone 2: persist daily-account imported transactions idempotently for the current payday cycle only
- Milestone 3: tidy the Daily screen and add a balance-vs-day chart across the payday cycle

## Non-goals
- Showing imported daily transactions in the UI before milestone 3
- Replacing the current monthly import path
- Supporting multiple OFX providers beyond the existing Nationwide parser

## Current Context
- [SettingsView.swift](/Users/rog/Development/MonthlyMoney/MonthlyMoney/SettingsView.swift) currently exposes a single `Import OFX` action.
- [AppState.swift](/Users/rog/Development/MonthlyMoney/MonthlyMoney/AppState.swift) already persists `usesSeparateAccountForDailyBudget` and a separate daily balance value.
- [DailyView.swift](/Users/rog/Development/MonthlyMoney/MonthlyMoney/DailyView.swift) already uses a navbar title and a chip grid, but has no chart and no daily transaction model.
- The import pipeline already has a parser, idempotent imported-record storage, and monthly reconciliation path.

## Chosen Approach
Use a dedicated hidden daily account that is created and maintained internally when `Use separate account for daily budget` is enabled.

The monthly and daily imports will share the existing OFX parsing infrastructure, but they will diverge after parsing:
- monthly import keeps the current transaction import and reconciliation behavior
- daily import targets the hidden daily account and initially only applies statement balance

This keeps the existing monthly flow stable, gives the daily ledger a real account identity for idempotency, and prepares milestone 3’s chart without forcing daily data into month-planning models.

## Hidden Daily Account Model
- The app will create a hidden/internal account record when separate daily account mode is turned on or when an existing budget with that setting is opened.
- That hidden account is not shown in normal account selection UI.
- It is the sole target for `Import OFX to daily account`.
- Its imported transactions are stored silently for internal calculations and charting.

## Import UX
When `Use separate account for daily budget` is off:
- Keep the current UI unchanged with one section/action: `Import OFX`

When it is on:
- Rename the existing import action to `Import OFX to monthly account`
- Add a second action: `Import OFX to daily account`

The monthly import keeps the current account-picking behavior.
The daily import targets the hidden daily account directly and does not ask the user to choose from visible accounts.

## Milestone 1 Behavior
- Add the new import labels/branching in Settings.
- Parse the OFX file for daily import.
- Apply the OFX ledger balance to the hidden daily account’s current balance.
- Do not store daily transactions yet.
- Leave monthly import behavior unchanged.

## Milestone 2 Behavior
- Store OFX transactions imported to the hidden daily account using idempotent import semantics.
- Reuse the imported-record machinery pattern already used for monthly imports where practical.
- Do not reconcile daily imports into planned items or month transactions.
- Keep daily transactions only for the current payday cycle.
- Clear prior-cycle daily imported transactions when moving into a new cycle.

## Payday Cycle Semantics
The daily cycle is payday-to-payday using the configured `dailyBudgetPaydayDay`.

Retention rule:
- keep imported daily transactions whose posted date falls inside the current cycle
- remove older daily imported transactions once the app has advanced into a new cycle

This keeps milestone 2 intentionally narrow and avoids designing a long-term daily-history policy before the chart requirements are proven.

## Milestone 3 Daily View
- Tighten top spacing so chips sit closer to the top of the scroll view.
- Keep `Daily` as the navigation title rather than a content header.
- Add a chart beneath the chips.
- Chart plots balance against cycle day across the payday-to-payday window.

The chart data source will be:
- the hidden daily account’s imported transactions for the current cycle
- the daily balance/current balance state already stored on the budget

## Data Model And Migration
This feature introduces new persisted semantics around the hidden daily account, so it requires an explicit migration.

Migration responsibilities:
- persist enough information to identify the hidden daily account reliably
- on open/migration, create the hidden daily account if separate daily mode is enabled and the account does not yet exist
- preserve existing regular accounts and monthly imported records

If the chosen implementation needs new persisted fields on `Budget` or `Account`, those changes must be accompanied by a Core Data/SwiftData migration path rather than relying on store rebuilds.

## Risks
- Hidden-account creation must not duplicate accounts on repeated refresh/startup.
- Daily import must not accidentally flow into monthly reconciliation.
- Payday-cycle cleanup must be deterministic and based on the same month-boundary logic used elsewhere in the app.
- Milestone 3 charting needs the hidden daily ledger to be structurally sound before UI work begins.

## Testing Strategy
- Settings/UI tests for import section naming and visibility
- Unit tests for hidden daily account creation and lookup
- Unit tests for daily import balance-only behavior in milestone 1
- Unit tests for idempotent daily import storage in milestone 2
- Unit tests for payday-cycle cleanup of daily imported transactions
- Unit tests for chart-series generation in milestone 3

