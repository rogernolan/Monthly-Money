# Daily Chip Copy And Layout Design

## Goal
Adjust the Daily screen card copy and layout so the budget fields read more clearly, editable money fields show the system currency symbol when resting, and payday context is visible as a dedicated informational chip.

## Design
The Daily screen keeps the existing payday-cycle calculations and only changes presentation. The top row remains the two white budget cards. The second row shows the conditional current-balance card and ahead/behind. The third row becomes two half-width cards: current daily budget on the left and a white informational card on the right showing days until payday with the payday date rendered as an ordinal.

Editable currency fields will render as plain numeric input while focused, but show the current locale currency symbol when resting. Card titles are updated to: `Starting budget at beginning of month`, `Average daily budget`, and conditional `Current balance` / `Predicted remaining funds`.
