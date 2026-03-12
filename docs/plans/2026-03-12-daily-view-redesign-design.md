# Daily View Redesign Design

Goal: replace the current Daily screen with a focused payday-cycle dashboard built around a small set of editable inputs and three calculated chips.

Decisions:
- Daily is a single current-cycle screen, not a month history view.
- The screen is anchored to the current payday cycle, so date math uses payday-to-payday modular arithmetic across month boundaries.
- The editable inputs are `Budget`, `Current Balance`, and `Payday`.
- `Current Balance` is editable only when `Budget.usesSeparateAccountForDailyBudget` is `true`.
- When `usesSeparateAccountForDailyBudget` is `false`, `Current Balance` shows the Month view's projected closing balance and is read-only.
- The calculated chips are `Daily budget`, `Ahead / behind`, and `Current daily budget`.
- Chip colors match Month view semantics:
  - `Ahead / behind`: red when below zero, yellow when zero, green when above zero.
  - `Current daily budget`: red when below `Daily budget`, yellow when equal, green when above.
- The old Daily sections are removed entirely: Cash + FX, weekly reckoner, and the living-expenses action.

State/model shape:
- Keep the existing budget-level switch `usesSeparateAccountForDailyBudget`.
- Add Daily-specific persisted inputs to the active budget model:
  - `dailyBudgetAmount: Decimal`
  - `dailyBudgetPaydayDay: Int`
- Keep `dailyBudgetCurrentBalanceByMonthKey` in `AppState` for now only if the separate-account path is enabled; otherwise derive balance from Month view projected closing balance.
- No separate account wiring yet. The switch only affects whether the Current Balance chip is editable and which source value is used.

Calculation rules:
- `daysInCycle` = number of days between the previous payday and the next payday.
- `remainingDaysToPayday` = number of days from today to the next payday.
- `elapsedDaysInCycle` = `daysInCycle - remainingDaysToPayday`.
- `dailyBudget` = `budget / daysInCycle`.
- `expectedBalanceToday` = `budget - (dailyBudget * elapsedDaysInCycle)`.
- `aheadBehind` = `currentBalance - expectedBalanceToday`.
- `currentDailyBudget` = `currentBalance / max(remainingDaysToPayday, 1)`.
- Payday arithmetic must wrap across month ends using real calendar dates rather than assuming today is before payday in the current month.

UI shape:
- Top row: three editable chips for `Budget`, `Current Balance`, `Payday`.
- Second row: three computed chips for `Daily budget`, `Ahead / behind`, `Current daily budget`.
- Reuse the Month chip styling so the Daily page looks visually consistent.
- Currency values use the system currency symbol.

Testing:
- Add pure date/cycle math tests covering payday wrap across month boundaries.
- Add tests for chip calculations using both separate-account modes.
- Add app-level tests for the active budget defaults and for read-only/editable balance behavior as far as the current test surface allows.
