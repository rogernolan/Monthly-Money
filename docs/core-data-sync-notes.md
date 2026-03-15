# Core Data Sync Notes

## Duplicate Local Budgets

MonthlyMoney keeps a single active local budget in the user's private CloudKit database.

During early CloudKit sync work, some installs created duplicate local budgets in the private database. Deleting the app did not remove those records, because private CloudKit data survives app reinstall.

The app now reconciles duplicate local budgets during startup:

- wait for the initial private CloudKit import
- choose the canonical local budget using the newest `updatedAt` timestamp, then `createdAt`, then `id`
- delete older duplicate local budgets and all dependent accounts, planned items, and transactions

This safeguard is intentional and should remain in place. It protects users from stale private-cloud data and from any future bootstrap bug that accidentally creates more than one local budget.
