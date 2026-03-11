# Remove Compatibility Layer Design

Goal: delete the remaining account-sharing compatibility layer and make the app/core data model budget-scoped only.

Decisions:
- Remove `StorageScope` and `ViewScope`.
- Remove `AccountAccessMode`, `Account.accessMode`, `Account.sharedWithParticipantIDs`, and `Account.storageScope`.
- Route writes using the active budget/account's budget membership and budget `sharingState`.
- Keep repository/share invariants in the core package.
- Keep app-hosted tests focused on app behaviour only.

Implementation outline:
1. Remove obsolete model fields/types from app and core models.
2. Simplify repository APIs to budget-derived reads/writes only.
3. Update budget sharing service to stop copying removed fields.
4. Update app state and tests to the simplified API.
5. Run package tests and hosted app tests.
