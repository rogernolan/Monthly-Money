# Core Data Migration Design

## Goal
Replace the app’s SwiftData-backed persistence with Core Data-backed persistence so MonthlyMoney can support both:
- CloudKit private-database sync
- CloudKit shared-database budget sharing between users

## Why This Migration Is Needed
The current app architecture assumes two persistence stores:
- private/local store
- shared store

That architecture is still valid.

The blocker is the persistence framework, not the product model:
- SwiftData in the installed SDK supports local storage and CloudKit private-db use
- SwiftData does not expose a CloudKit shared-database configuration path
- v2 recipient sharing therefore cannot be completed on SwiftData alone

Core Data with `NSPersistentCloudKitContainer` is the practical path because it supports both private and shared CloudKit stores.

## Product Constraints
- There is only one active budget.
- Budget sharing remains one-way in v1/v2: local/private -> shared.
- No local/shared merge.
- No unshare in this phase.
- No one-time migration from old SwiftData installs is required because there are no users yet.
- `Use separate account for daily budget` must:
  - be persisted in Core Data
  - only be editable by the owner of the active budget

## Recommended Approach
Move the app’s real persistence implementation to Core Data while keeping the repository and app-facing model shape as stable as possible.

This means:
- keep `AccountRepository` as the main app boundary
- keep in-memory stores for tests
- replace `SwiftDataAccountDataStore` with `CoreDataAccountDataStore`
- keep app/UI code using the existing repository/domain layer as much as possible

This avoids rewriting the UI just to change persistence.

## Architecture
### Repository boundary stays stable
The existing [Repository.swift](/Users/rog/Development/MonthlyMoney/MonthlyMoney/Repository.swift) protocol boundary is the right seam:
- `AccountDataStore`
- `AccountRepository`
- budget snapshot / share migration helpers

Those should remain the contract for the app.

### Persistence implementation changes
Replace:
- `SwiftDataAccountDataStore`

With:
- `CoreDataAccountDataStore`

Backed by:
- one Core Data stack for the private store
- one Core Data stack for the shared store

Each stack should be created from an `NSPersistentCloudKitContainer` configured for the appropriate database scope.

### App-facing models
Keep the existing app-domain types in [DomainModels.swift](/Users/rog/Development/MonthlyMoney/MonthlyMoney/DomainModels.swift) as the types the repository returns.

The Core Data layer should map between:
- managed objects/entities
- app-domain models

This keeps most of `AppState`, `MonthView`, `DailyView`, and `SettingsView` unchanged.

## Core Data Model
The Core Data schema needs entities equivalent to the current domain model:
- `Budget`
- `Account`
- `PlannedItem`
- `Transaction`

Each entity should store the same fields already used by the app.

Important fields on `Budget` include:
- `id`
- `name`
- `ownerParticipantID`
- `sharingState`
- `usesSeparateAccountForDailyBudget`
- `dailyBudgetAmount`
- `dailyBudgetPaydayDay`
- `dailyBudgetSeparateAccountBalance`
- `monthBalancesPayload`

This preserves the current app behaviour while moving persistence underneath it.

## Owner-Only Daily Setting Rule
`Use separate account for daily budget` should remain a budget-level property, but editing it must be restricted.

Rule:
- owner can edit it when the active budget is local or `sharedByYou`
- participant cannot edit it when the active budget is `sharedWithYou`

Implementation shape:
- the value is still stored on `Budget`
- `AppState` should expose a capability such as `canEditBudgetSettings`
- `SettingsView` disables the toggle when the active budget is shared with the current user as participant
- repository still persists the field regardless of store type

This same owner-only rule likely applies later to other budget-wide settings, so it should be represented explicitly rather than embedded ad hoc in the view.

## CloudKit Store Layout
### Private store
- Core Data persistent store
- CloudKit private database
- canonical store for local owner budget before sharing

### Shared store
- Core Data persistent store
- CloudKit shared database
- canonical store after share creation or share acceptance

### Active budget selection
The existing budget selection rule can remain:
- prefer local budget when active budget is local
- use shared budget when active budget has been migrated/shared

The repository should continue to decide this, not the UI.

## Share Flow After Migration
### Owner
1. Tap `Share Budget`
2. Repository/service snapshots local budget
3. Insert snapshot into Core Data shared store
4. Delete local/private copy
5. Create `CKShare` for the shared budget root
6. Present system share UI
7. Owner continues on the shared budget

### Recipient
1. Accept share invitation
2. App detects shared budget in the Core Data shared store
3. If local data exists, show destructive overwrite warning
4. On confirm:
   - delete local/private budget data
   - adopt shared budget
5. Participant sees shared budget, but owner-only settings remain disabled

## Migration Scope
Included:
- Core Data private store
- Core Data shared store
- replacement of app runtime persistence wiring
- owner-only budget settings guard for `Use separate account for daily budget`

Explicitly excluded:
- SwiftData -> Core Data migration for existing installs
- unshare
- merge of local and shared budgets
- multi-budget switching

## Risk Management
### First proof task
Before building the full Core Data layer, prove the hardest platform requirement:
- configure and open both a private-db and shared-db `NSPersistentCloudKitContainer` in this app target

This must happen before entity/repository conversion work.

### Keep blast radius small
- preserve repository API
- preserve app-domain models
- preserve in-memory test store
- migrate one persistence implementation layer at a time

## Testing Strategy
### Store-level
- CRUD for each entity via `CoreDataAccountDataStore`
- budget sharing snapshot round-trips through Core Data store mapping

### App-level
- current bootstrap and budgeting behaviour still works
- private sync still works
- owner share flow still works
- `Use separate account for daily budget` is disabled for non-owner shared budgets
- recipient adoption flow can be added on top once shared store is live

## Rollout Plan
1. Prove Core Data private/shared CloudKit store configuration
2. Build Core Data entity model and store mapping
3. Swap app runtime to Core Data private store
4. Swap shared store to Core Data shared store
5. Reconnect share/adoption flows on real shared persistence
6. Finish recipient overwrite dialog and owner-only settings enforcement in UI
