# Import Reconciliation Design

**Goal**

Add an apply step for imported OFX rows that matches rows to monthly planned items using a simple substring matcher, creates first-class transactions for unmatched rows, stays idempotent, and removes the sample bootstrap data currently seeded into a new store.

**Scope**

- Add `matchingString` to planned items.
- Match imported rows against planned items using case-insensitive substring matching.
- Fall back to planned item `label` when `matchingString` is empty.
- Mark matched planned items paid and update their amount.
- Create first-class transactions for unmatched imported rows.
- Make reconciliation idempotent using OFX `FITID` where available.
- Remove bootstrap sample/seed data so a fresh store starts empty rather than pre-filled.

**Architecture**

Keep parsing, import persistence, and reconciliation separate.

1. `NationwideOFXImporter` parses OFX into normalized imported rows.
2. `ImportedTransactionService` stores normalized rows without duplicates.
3. A new reconciliation service scans stored imported rows, matches them to planned items, and either updates the matching planned item or creates a first-class transaction.

This preserves the intermediate audit trail and makes retries safe.

**Model Changes**

Add `matchingString: String` to `PlannedItem`.

- Use this field for import matching.
- If it is empty or whitespace-only, fall back to `label`.

Extend `ImportedTransactionRecord` with reconciliation trace fields:

- `appliedPlannedItemID: UUID?`
- `createdTransactionID: UUID?`

Extend `Transaction` with source-trace fields for idempotency:

- `sourceKind: String`
- `sourceExternalTransactionID: String`
- `sourcePostedAt: Date?`

For unmatched imports, set the visible transaction name/text fields to the imported payee so the created transaction reads naturally in the app.

**Matching Rules**

For each imported row:

1. Normalize the imported payee and candidate planned-item matcher by trimming whitespace and lowercasing.
2. Use `matchingString` if present; otherwise use planned item `label`.
3. A planned item matches when either string contains the other as a case-insensitive substring.
4. Restrict matching to planned items in the imported row’s `YearMonth`.
5. Ignore already-paid planned items for matching to avoid accidentally double-completing items.

If multiple planned items match, prefer:

1. exact normalized equality
2. earliest due day
3. stable tie-break by UUID

This keeps the initial behavior simple but deterministic.

**Idempotency**

Reconciliation must be safe to run repeatedly.

For matched planned items:

- If the imported row already has `appliedPlannedItemID`, skip it.
- If the planned item is already paid from this imported row, do not re-apply it.

For unmatched imports:

- Prefer OFX identity: `accountID + sourceKind + sourceExternalTransactionID`
- If a future importer lacks a source transaction id, fall back to `accountID + sourcePostedAt + amount`

Because Nationwide OFX includes `FITID`, that primary key is sufficient for v1.

Created transactions should store the source identity so repeated reconciliation does not create duplicates even if the imported row linkage is missing or incomplete.

**Data Flow**

1. User imports an OFX file manually.
2. Imported rows are stored as `ImportedTransactionRecord`.
3. User triggers reconciliation, or the app runs it immediately after import.
4. Reconciliation loads unapplied imported rows for the relevant account(s).
5. Each row is either:
   - matched to a planned item, marked paid, amount updated, and linked back on the imported row
   - or converted into a first-class transaction, with source identity recorded and linked back on the imported row
6. Re-running reconciliation is safe and produces no duplicate effects.

**Bootstrap Cleanup**

Remove the sample bootstrap behavior in `AppState` that currently seeds:

- example balances
- planned items from the starter sheet
- wheel-of-money seed data
- auto-copied future-month sample data

Recommendation:

- Keep the minimal empty local budget/account shell creation so the app still has an active budget.
- Remove all sample transactional/planned-item content and sample balance values.

This keeps first launch usable without silently pre-populating financial data.

**Platform Assumptions**

Verified:

- Nationwide OFX includes `FITID`, so unmatched created transactions can be keyed idempotently from source identity.
- Imported rows already persist per account and survive re-import safely.
- Repository/store layers already support local/shared scoping for imported rows.

Unverified:

- Whether reconciliation should run automatically after import or remain a separate explicit step. Implementation can start with automatic reconcile after successful import if that reduces UI surface.
- Whether current transaction UI needs an additional visible name field beyond existing `note`. If not, `note` can hold the payee for now.

**Testing**

Add tests for:

- matching uses `matchingString` when present
- matching falls back to `label` when `matchingString` is empty
- matched imports mark planned items paid and update amount
- unmatched imports create exactly one transaction
- reconciliation is idempotent for repeated runs
- created transactions store source identity fields
- bootstrap no longer seeds example records or balances

**Why This Design**

This keeps Milestone 3 incremental and auditable. Matching stays simple, deterministic, and user-editable. Unmatched rows become real transactions without losing the source link, and OFX `FITID` gives us a strong idempotency anchor for safe retries.
