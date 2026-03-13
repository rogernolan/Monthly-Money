# Editable Money Chip Affordance Design

## Goal
Make editable money chips look obviously editable and easier to interact with, without introducing separate Month and Daily implementations.

## Design
The shared `EditableMoneyChipValue` component will gain a permanent edit affordance: a small grey rounded square with a pencil icon anchored at the top-left of the chip. That badge remains visible both at rest and while editing so the chip continues to read as editable.

The full chip surface becomes a tap target that starts editing the numeric value. Tapping anywhere on the chip focuses the text field, switches from formatted currency text to raw numeric editing text, and preserves the existing green tick dismiss affordance on the right. The current dismiss animation and value formatting rules stay unchanged.

Because Month and Daily already route editable chip values through the shared component, the change applies consistently to all current editable chips without additional screen-specific logic.
