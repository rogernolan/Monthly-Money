# Editable Money Chip Dismiss Interaction Design

## Goal
Add a shared inline keyboard-dismiss affordance for every editable money chip in the app, covering both Daily and Month without duplicating interaction code.

## Design
Editable money values will use one shared SwiftUI component that wraps a numeric text field, focus state, and an inline dismiss affordance. While a field has focus, the value text animates left to reserve trailing space and a green tick-in-circle button appears on the right. The button animates with a spring transition using opacity from 25% to 100% and scale from 25% through a brief overshoot to 110%, then settles at 100%. Tapping the button clears focus, dismisses the keyboard, and returns the field to its resting currency-formatted display.

This interaction applies to:
- Daily starting budget
- Daily current balance when separate-account mode is enabled
- Month current balance when that card is editable
- Any other editable Month money chip already backed by a `Binding<Decimal>`

A small pure layout helper will keep the visibility and reserved trailing width testable without UI inspection. The Month and Daily screens will both render the same component so behavior and animation stay consistent.
