# Periodic Repeats and WoM Design

## Goal

Make a repeat definition the source of truth for every every-N-days planned-item series. Replace the WoM annual savings list with a date-based view of scheduled occurrences over the next 24 budget months. Materialized occurrences remain normal planned items so monthly budgets and paid state continue to work.

This design supersedes the decision in `2026-08-26-periodic-repeat-harvesting-design.md` to keep occurrence rows as the source of truth and not add a series entity. Fixed-day `.calendar` repeats retain their current month-copy behavior and do not appear in WoM.

## Repeat definition and schedule history

Add a persisted `PeriodicRepeat` with a stable ID, budget and account IDs, and an optional exclusive end date. Persist its schedule as `PeriodicRepeatRevision` records. Each revision contains a stable ID, repeat ID, inclusive effective date, concrete anchor date, positive interval in days, item type, label, matching string, Decimal amount, and notes. The repeat and revisions carry no budget month or paid state.

A revision applies from its effective date until the next revision's effective date or the repeat's end date, whichever comes first. Projection advances the anchor by calendar days and includes only dates in that range. A new repeat's first revision starts on its anchor date and includes the anchor occurrence. Every positive interval is supported, including intervals of 28 days or fewer.

**This and future** uses the selected occurrence's original scheduled date as the revision boundary. It replaces revisions at or after that boundary and leaves earlier revisions intact. Descriptive-only changes retain the previous schedule phase. A date or interval change uses the edited due date as the new anchor; that date must be on or after the boundary. A date before the boundary requires an occurrence-only edit. Previously unmaterialized dates before the boundary continue to use the earlier revision.

For example, changing a 28-day series to 30 days at its May 30 occurrence retains its earlier schedule, then starts the new schedule on May 30. Editing only the May 30 amount keeps the 28-day phase.

## Occurrence identity and overrides

Each generated `PlannedItem` references the repeat ID and persists an immutable `scheduledDate` plus an editable concrete `dueDate`. Its identity for generation is `(repeatID, scheduledDate)`. The repository uses this key for lookup and duplicate prevention, independently of matching strings, due days, labels, and amounts. It must not route periodic generation through the existing calendar-copy matching rule.

Persist civil dates as Gregorian year-month-day values. Projection adds calendar days rather than elapsed 24-hour periods. Payday changes can alter budget-month assignment but never occurrence identity. The app derives the planned item's budget month and due day from its editable due date using the budget's payday rules. It preserves existing stored month and due-day values during migration.

Persist an occurrence-override marker. An occurrence-only edit sets it and preserves all of that row's user-edited values during regeneration. Moving its due date leaves its scheduled date unchanged, so generation cannot recreate the original occurrence. WoM merges stored rows with projections by identity, displays overrides on their edited due dates, and includes moved overrides whose due dates enter the window even when their scheduled dates are outside it.

Add a persisted `PeriodicRepeatSkip` keyed by repeat ID and scheduled date. A skip suppresses that occurrence even when no planned row exists. Schedule revision changes retain skips; a skip applies whenever the same scheduled date is projected again.

## WoM projection and month population

WoM projects occurrences from the current budget month through the next 23 budget months. Opening, refreshing, or navigating WoM writes no definitions, planned rows, or populated-month markers. Group rows by the payday-based budget month of their displayed due date, current month first, with later months ascending. Sort each group by due date and use stable identity to break ties. Show every occurrence, including multiple occurrences from one repeat in a month.

WoM combines projected dates with stored occurrences and suppresses skips. Each row shows the repeat, due date, and amount. Retained standalone rows described below remain ordinary month entries and do not appear as active repeat projections.

Explicit month population materializes only occurrences landing in its target month, using the revision active on each scheduled date and respecting overrides and skips. It retains the existing month eligibility rules and writes the populated marker only after successful writes. Viewing the 24-month window does not change month totals or population eligibility.

Editing a projected WoM row uses the same permission rules as editing a planned item in its landing month. An occurrence-only save explicitly creates that one planned row and marks it as overridden; it does not mark the month populated or create other rows. Because that action can make a month nonempty before population, ordinary population remains available for an unmarked month containing only such periodic overrides. It merges generated occurrences by identity and preserves those overrides. Months containing other entries retain their existing population guards. A this-and-future save changes the definition and refreshes projection without materializing the display window.

Future regeneration updates existing affected rows and creates missing dates only in affected months already marked populated. It does not fill unpopulated months merely because they contain a manually edited occurrence. Existing explicit population and repopulation actions remain responsible for filling those months.

## Savings target

Show the annualized repeat cost and monthly savings target from the revision effective today for each active repeat. A repeat contributes zero before its first effective date or on and after its end date. Future revisions affect the target when they become effective. Skipped dates and occurrence overrides do not change this steady savings rate.

The monthly savings target is the annualized cost of active `.fixedDebit` repeats divided by 12. Annualize each as `amount * 365.2425 / repeatDays` using Decimal arithmetic, sum the results, then divide by 12. Credits and transfers remain visible in WoM but do not contribute. The rate does not depend on the number of occurrences in the display window.

The budget's `autoGenerateWoMSavingsEveryMonth` setting remains in Settings. Month population uses the target effective on the target budget month's start date. Definition edits do not rewrite existing “WoM savings” rows, and the existing guard prevents replacing an existing row. Existing `WheelOfMoneyItem` records remain stored and readable but are no longer shown.

## Editing, deletion, and stopping

Editing a planned-item row defaults to **This occurrence**. Descriptive and date edits affect that row only. Interval changes belong to **This and future**; the occurrence-only editor does not offer a series interval change.

For **This and future**, `AppState` reconciles materialized rows from the revision boundary onward. On dates still in the revised schedule it updates definition-owned fields only on non-overridden rows, preserving paid state and import metadata. It removes obsolete rows only when they are unpaid, unedited, and have no linked imported transaction. It retains paid, overridden, or import-linked obsolete rows as standalone planned items, clearing their repeat link and periodic mode while preserving their IDs, values, paid state, and import links. It then creates missing occurrences within affected populated months.

**Delete this occurrence** persists a skip and deletes the row, or persists only a skip for a projected row. Deletion follows existing planned-item permissions and import-link handling. **End this repeat from here** sets the exclusive end date to the selected scheduled date, removes later revisions, and reconciles rows at or after that date using the same removal and standalone-retention rules. Earlier rows and schedule history remain intact. Ended definitions remain persisted for history and sync.

Changing a periodic row to one-off or calendar requires an explicit scope choice. **This occurrence** persists a skip for its old identity and detaches that row into the chosen mode; the periodic series continues. **This and future** ends the periodic series at that boundary and retains the selected row in the chosen mode. Calendar conversion then uses the existing calendar-copy flow; protected obsolete rows become standalone one-off rows. Inactive periodic values retained by the editor do not reactivate an ended repeat. Switching back to periodic creates a new repeat anchored on the entered date.

The repository saves each edit's revision, skip, and occurrence changes atomically within the owning store. A failed operation leaves the prior state intact and reports an error. A successful retry produces the same result. All actions retain existing budget, account, and historical-edit permissions.

## Migration and persistence lifecycle

Add definitions, revisions, skips, scheduled and due dates, and the override marker through explicit SwiftData and Core Data schema migrations. Group valid active `.periodic` rows by budget ID, account ID, and non-nil recurrence ID. Never combine records across accounts, budgets, or owning stores. A valid row has a positive interval and a concrete date resolvable using the existing payday and date-clamping rules.

For each group, create one repeat and an initial revision using the latest valid concrete occurrence date as both anchor and effective date. Use that row's interval and descriptive fields. Break equal-date ties by stable planned-item ID. This preserves the current generator's phase, which advances from the latest occurrence, rather than realigning it to the earliest row. The migration does not infer missing historical schedules before that date.

Link all valid rows in the group to the repeat and persist their resolved scheduled and due dates. Earlier stored rows remain visible as historical materialized occurrences even though projection begins at the migration anchor. Preserve every row ID, stored month, due day, import metadata, and paid state. Mark rows whose definition-owned fields differ from the initial revision as overrides. Leave invalid rows and rows with inactive periodic settings unchanged and unlinked; do not assign a guessed series or silently resume them through the legacy generator. Existing invalid rows remain readable and can be repaired explicitly by creating a valid repeat.

Both private and shared stores migrate independently. The repository includes definitions, revisions, and skips in account/budget sharing, snapshot, copy, unsharing, and deletion operations alongside their occurrences. Moving an account preserves all identities and dates; deleting an account or budget removes its related repeat records without orphans. Core Data sharing includes these records in the owning budget's shared graph. Existing Wheel of Money records remain untouched.

## Code ownership

- `PeriodicRepeat` and its revisions own schedule configuration and pure civil-date projection.
- The repository owns persistence, atomic reconciliation, skips, identity lookup, and private/shared lifecycle operations.
- `AppState` coordinates permissions, edit scope, revision boundaries, month eligibility and assignment, regeneration, and refresh.
- WoM presents merged projection groups and forwards edits; it does not write rows during viewing or calculate recurrence dates.
- The month editor offers occurrence-only and this-and-future scopes and explicit deletion, stop, and mode-conversion actions.

## Verification

Add focused XCTest coverage for:

- short and long intervals across calendar, year, daylight-saving, and payday boundaries;
- all occurrences in a 24-budget-month window, including moved overrides, stable grouping and sorting, and no persistence writes during viewing;
- annualized cost and savings targets with Decimal arithmetic, current and future revisions, ended repeats, long intervals, and exclusion of credits and transfers;
- monthly “WoM savings” generation using the target month's start-date rate without replacing existing rows;
- intervals of 1, 28, 29, and more days, with multiple same-series occurrences per month;
- identity-based generation, including two different repeats with identical matching strings and due dates;
- occurrence-only edits preserving identity, overrides, and later schedules;
- this-and-future edits preserving earlier rows and unmaterialized dates, retaining schedule phase for descriptive edits, and replacing later revisions;
- reconciliation preserving paid state and import links, retaining obsolete protected rows as standalone, and filling only populated months;
- projected-row edits, subsequent population of months containing only overrides, unchanged permissions, and absence of incidental populated markers;
- skip persistence across retry and revision changes, stopping, deletion, and one-off/calendar conversion without resurrection;
- atomic failure injection and retry for revision, skip, occurrence, and populated-marker writes;
- migration preserving the latest legacy phase even when the earliest row is off that phase, deterministic equal-date ties, account/budget separation, invalid rows, and all existing IDs and paid states;
- SwiftData and Core Data migration in private and shared stores, sharing/unsharing round trips, and deletion without orphan repeat records;
- existing fixed-day behavior and readability of legacy Wheel of Money records.

After each implementation milestone, build and run the relevant tests. Before completion, run the full required test suite and app build; report migration and persistence coverage separately from view behavior.
