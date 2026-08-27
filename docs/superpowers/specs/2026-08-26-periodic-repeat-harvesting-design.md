# Periodic Repeat Harvesting Design

## Goal

Replace the current date-picker repeat choices with explicit one-off, calendar, and periodic modes, and allow periodic occurrences to be harvested into a target budget month even when intervening months contain no rows.

## Approved decisions

- Keep planned-item occurrence rows as the persisted source of truth; do not add a separate periodic-series entity.
- Use the existing item date as the periodic anchor. The periodic editor contains only the positive repeat-day interval.
- Preserve stored calendar-day and periodic-interval data when changing modes. The active mode determines which data is used.
- Convert legacy Floating items to periodic items with a 28-day interval and day 1 as the deterministic anchor.
- Persist an explicit populated-month marker so an empty month can still be traversed after the user populates it.

## UI and mode model

Persist a `RepeatMode` enum with these cases:

- `oneOff`: no repeat-specific editor; recurrence is inactive and the item is not copied.
- `calendar`: show the existing day-of-month picker and copy from the immediately previous month.
- `periodic`: show only the positive `Repeat days` editor; the item's existing date is the anchor.

Changing modes must not clear inactive settings. For example, switching a periodic item to one-off preserves its interval and anchor, and switching it back to periodic restores them. The active mode controls recurrence behavior and prevents stale inactive fields from affecting copying.

New periodic items use their entered date as the anchor and create only that anchor row. Editing an item to periodic uses the edited item date as the anchor.

## Month population model

Add a lightweight `PopulatedMonth` record containing:

- `id: UUID`
- `budgetID: UUID`
- `monthKey: YearMonth`

The existence of this record means the user explicitly populated that month. It is valid for a populated month to contain zero planned items.

The repository exposes:

```swift
func isMonthPopulated(_ month: YearMonth) throws -> Bool
func markMonthPopulated(_ month: YearMonth) throws
func periodicItems(before month: YearMonth) throws -> [PlannedItem]
```

The new entity is included in SwiftData and Core Data schemas with an explicit migration. Existing stores have no markers until the user populates a month.

## Population and harvesting

Population remains an explicit action for the next unpopulated month. It performs two independent operations:

1. Fetch the immediately previous month and copy only non-periodic items. Calendar-repeat items retain their existing behavior; periodic items are excluded from this path.
2. Fetch all periodic occurrences before the target month, group them by `recurrenceID`, choose the latest concrete occurrence in each group, and advance it by `repeatDays` until the target payday-to-payday month is reached. Create every occurrence that falls inside the target month and no rows in intervening months.

After both operations succeed, write the `PopulatedMonth` marker even if the target received no entries. If any operation fails, do not write the marker so the user can retry.

The periodic calculation uses concrete dates resolved against payday budget-month boundaries. A target can receive multiple occurrences. A later population uses the latest occurrence already present in the previous populated month when that is the latest available source, while the backward search handles empty intervening months.

Example chain: a 28-day series anchored on April 4 produces May 2 and May 30 when May is populated, then produces June 27 when June is populated. This is a 1:2:1 sequence across April, May, and June.

Navigation uses the marker rather than item count:

- the next unpopulated month is the only month offering Populate;
- a populated-but-empty month still permits navigation to the following month;
- opening a month does not populate it automatically;
- periodic rows never appear in skipped months merely because another repeat type was copied.

## Persistence and migration

Add `repeatMode` to the planned-item models and add `PopulatedMonth` to both persistence implementations. The explicit migration must preserve all existing planned-item values and derive the initial mode as follows:

- legacy Floating (`dueDay == nil`, automatic copying enabled) becomes Periodic with `repeatDays == 28`, `dueDay == 1`, and a new recurrence ID;
- existing fixed-day automatically copied items become Calendar;
- non-copying items become Does not repeat.

The migration must be versioned for both SwiftData and Core Data, and existing rows must remain visible in their original budget months.

## Testing

Add focused tests for:

- mode persistence and switching without losing inactive calendar/periodic settings;
- legacy Floating migration to Periodic/28 days/day 1;
- positive periodic interval validation, including values above 31;
- calendar copying limited to the immediately previous month;
- periodic harvesting from an earlier month across empty intervening months;
- 32-day and 100-day intervals;
- no periodic rows created in skipped months;
- multiple target-month occurrences and the following-month continuation;
- the explicit April 4 / 28-day chain: April 1 occurrence, May 2 occurrences, June 1 occurrence;
- payday and year boundaries;
- populated markers for empty months and navigation through them;
- repeated population not duplicating rows or markers;
- one-off mode ignoring preserved recurrence settings.

## Error handling

Invalid periodic intervals prevent saving. Harvesting and marker creation use the existing repository error path. Marker creation occurs only after all target-month writes succeed; a failed operation leaves the month unmarked and retryable.
