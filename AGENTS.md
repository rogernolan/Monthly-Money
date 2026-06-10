# AGENTS.md — Monthly Money iOS App

## Goal
Implement the data layer + sharing/migration architecture:
- Accounts are private by default.
- Accounts can be shared; sharing migrates the account and all dependent records from private store to shared store.
- Months are computed views over records visible via accounts.

## Non-goals (v1)
- Open Banking sync
- Complex per-record ACLs
- Reverse migration (shared -> private)

## Constraints
- Use Decimal for all money. Never Double.
- Keep the changes small and test-driven.
- Any data model change must include an explicit migration.
- After each milestone: build + run tests.
- Budget month boundaries are payday-to-payday, not calendar months. For example, with payday on the 26th, June 27 belongs to the July budget month; June's balance is no longer editable and July's is.

## Deliverables
- SwiftData models (or Core Data if chosen), including dual CloudKit stores.
- Migration service: Private -> Shared for an account.
- Calculation engine for month totals + view scope.
- XCTest coverage for totals + migration invariants.

## Definition of done
- Unit tests pass.
- App compiles.
- Migration leaves no orphan records and totals are preserved.

## testing
- if a test that once passed fails, your first assumption should be that there is a bug, not that the test itself needs fixing up.
