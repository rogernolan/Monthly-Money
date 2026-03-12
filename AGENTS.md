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
- After each milestone: build + run tests.

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
