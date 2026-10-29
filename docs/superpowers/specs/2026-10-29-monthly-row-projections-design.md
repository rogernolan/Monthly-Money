# Monthly row projected balances

Each monthly transaction row will show a projected balance in smaller text directly below, and right aligned with, its transaction amount. A red rounded rectangle will sit behind balances of zero or less. VoiceOver will identify the value as a projected balance. Existing unplanned markers will remain visible.

The calculation starts with the same balance as the monthly projected-balance card: the current bank balance for the current and past months, and the computed opening balance for future months. It walks all monthly items in the existing payday-based display order, adding unpaid credits and subtracting unpaid debits and transfers. Paid items leave the balance unchanged because the bank balance already includes them. Each row shows the balance after that row. Floating items retain their existing position after dated items.

The projection always includes all monthly items. Selecting Debits, Credits, or Pending only filters which rows appear; it does not change their projected balances. The final projection agrees with the monthly projected-balance card.

AppState will derive these values from its published monthly items and balance state, using Decimal throughout. Entry creation, editing, deletion, paid-status changes, balance edits, imports, month changes, and refreshes therefore update projections through the existing state paths. No stored fields or migration are needed.

A computed projection is the smallest approach because the existing state already publishes every input. Storing projections would add invalidation and migration work. Calculating from only the filtered list would hide transactions from the financial calculation.

Focused tests will cover payday ordering, credits/debits/transfers, paid and zero-value entries, exact decimal arithmetic, zero and negative warnings, filter independence, and recalculation after balance and entry changes and OFX import. Verification will include the application unit suite and an iOS simulator build, followed by a visual check where available.

Rog approved this behavior on 29 October 2026, including highlighting both zero and negative balances.
