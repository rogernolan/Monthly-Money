# Month Item Source Design

**Goal**

Show the source/state of every month-view entry and surface unmatched imported entries as clearly marked unplanned rows in the month list.

**Scope**

- Add a source/state to `PlannedItem`.
- Show that source/state in the month row UI for every entry.
- Mark import-created unplanned entries with a red exclamation icon to the left of the paid checkmark.
- Change unmatched import reconciliation so it creates a new monthly item with `copiesToNextMonthAutomatically = false`.
- Keep matched imports updating existing planned items.

**Approaches**

1. Recommended: make unmatched imports create `PlannedItem` rows tagged with an origin state.
   - This fits the current month view and month totals, both of which are already driven by `PlannedItem`.
   - It gives the user a visible row to review and mark paid.
   - It avoids inventing a second month-list rendering path for transactions.

2. Create both a `PlannedItem` and a `Transaction` for unmatched imports.
   - This preserves a ledger-style record, but it introduces two first-class records for one real-world event.
   - It increases idempotency and future-sync complexity.
   - It risks confusion over which object is authoritative.

3. Keep unmatched imports as transactions and teach Month View to also render transactions.
   - This would preserve the current reconciliation behavior.
   - It is the most invasive UI/data-flow change because the month screen, totals, and editing flow are all currently planned-item based.

Recommendation: option 1.

**Architecture**

Add a small `PlannedItem` source/state enum, likely:

- `manual`
- `copiedFromPreviousMonth`
- `importedUnplanned`

Creation rules:

- User-created entries default to `manual`.
- Auto-populated next-month copies are tagged `copiedFromPreviousMonth`.
- Unmatched imports create a new `PlannedItem` tagged `importedUnplanned` and set `copiesToNextMonthAutomatically = false`.

Matched imports do not change the source/state of an existing item. Completing an existing month item from an import must not change whether that item is planned or unplanned.

Planning rules:

- `manual` and `copiedFromPreviousMonth` are planned entries.
- `importedUnplanned` is explicitly unplanned.
- Only unmatched imports create `importedUnplanned` items.
- If the user edits an `importedUnplanned` item in any way, it is promoted to `manual`.

This means the warning state is temporary. The item starts as unplanned because it came from import automation, but once the user confirms or adjusts it, it becomes a normal planned item.

**UI**

Month rows should show source/state for every entry.

Recommended presentation:

- keep the existing due text line
- add a source caption line:
  - `Added this month`
  - `Copied from previous month`
  - `Imported (unplanned)`
- keep notes as the last metadata line when present

For `importedUnplanned` rows, add a red `exclamationmark.circle.fill` immediately to the left of the paid checkbox. This gives a strong warning without changing the row layout too much.

Once an imported-unplanned row is edited and promoted to `manual`, the warning icon should disappear and the row should present like a normal planned item.

**Import Reconciliation Change**

Update only the unmatched-import branch so it creates a new `PlannedItem` instead of a transaction.

Suggested field mapping:

- `type`: infer from sign, with negative amounts becoming `.fixedDebit` and positive amounts becoming `.credit`
- `label`: imported payee
- `matchingString`: imported payee
- `amount`: absolute value for debits, positive amount for credits, following current planned-item conventions
- `dueDay`: posted date day
- `dueText`: `Imported`
- `isPaid`: true, because the import represents an already-observed bank movement
- `copiesToNextMonthAutomatically`: false
- `notes`: optional import debugging note later if needed
- `source`: `importedUnplanned`

Keep `ImportedTransactionRecord` linked to the created planned item instead of a created transaction.

For matched imports:

- mark the existing planned item complete
- update the amount as before
- do not change its `source`

**Idempotency**

Unmatched imports must still be idempotent.

- If an imported record already has `appliedPlannedItemID` or an equivalent created-item link, skip it.
- Re-importing the same OFX file must not create duplicate unplanned rows.
- Re-running reconciliation over the same imported record must not create another month item.

The existing imported-record identity based on OFX `FITID` remains the main protection against duplicate imports.

**Platform Assumptions**

Verified:

- `MonthView` renders `state.monthItems`, which are loaded from `repository.plannedItems(for: selectedMonth)`.
- Month totals and projected balance calculations are also based on `PlannedItem`, not `Transaction`.
- The current next-month population path already funnels through `copyItems`, giving us a single place to tag copied items.

Unverified:

- Whether existing persisted records should receive a migration default of `manual` in both SwiftData and Core Data without any custom migration step. This should be validated with the existing persistence round-trip tests.

**Testing**

Add coverage for:

- `PlannedItem` default source is `manual`
- copied items receive `copiedFromPreviousMonth`
- unmatched imported rows create exactly one planned item with `source = importedUnplanned`
- unmatched imported rows set `copiesToNextMonthAutomatically = false`
- editing an imported-unplanned item promotes it to `manual`
- matched imported rows keep the existing planned item source unchanged
- repeated reconciliation stays idempotent and does not create duplicate unplanned items
- month row metadata includes the source label
- unplanned rows show the red warning icon

**Why This Design**

The month screen already treats planned items as the canonical monthly planning surface. Making unmatched imports create planned items aligns with that model, keeps the UI understandable, and directly supports the milestone requirement to create a new monthly item with copy-forward disabled.
