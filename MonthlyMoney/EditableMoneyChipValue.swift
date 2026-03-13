import SwiftUI

struct EditableMoneyChipLayout: Equatable {
    let showsDismissButton: Bool
    let trailingAccessoryWidth: CGFloat
    let showsEditBadge: Bool

    init(isEditing: Bool) {
        showsDismissButton = isEditing
        trailingAccessoryWidth = isEditing ? 34 : 0
        showsEditBadge = true
    }

    static let editing = EditableMoneyChipLayout(isEditing: true)
    static let resting = EditableMoneyChipLayout(isEditing: false)
}

struct EditableMoneyChipValue: View {
    @Binding var value: Decimal

    let fontSize: CGFloat
    let focus: FocusState<String?>.Binding
    let focusID: String

    @State private var draft = ""

    private var layout: EditableMoneyChipLayout {
        EditableMoneyChipLayout(isEditing: isFocused)
    }

    private var isFocused: Bool {
        focus.wrappedValue == focusID
    }

    private var buttonAnimation: Animation {
        .spring(response: 0.34, dampingFraction: 0.52)
    }

    var body: some View {
        ZStack(alignment: .trailing) {
            TextField("0", text: Binding(
                get: {
                    if isFocused {
                        return draft.isEmpty ? plainString(from: value) : draft
                    }
                    return AppState.currency(value)
                },
                set: { newValue in
                    draft = newValue
                    value = Decimal(
                        string: sanitizedNumericString(from: newValue),
                        locale: Locale.current
                    ) ?? 0
                }
            ))
            .focused(focus, equals: focusID)
            .keyboardType(.decimalPad)
            .multilineTextAlignment(.trailing)
            .font(.system(size: fontSize, weight: .semibold))
            .frame(maxWidth: .infinity, alignment: .trailing)
            .padding(.trailing, layout.trailingAccessoryWidth)

            Button {
                focus.wrappedValue = nil
            } label: {
                Image(systemName: "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [
                                        Color(red: 0.20, green: 0.71, blue: 0.40),
                                        Color(red: 0.10, green: 0.48, blue: 0.24)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                    )
                    .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
            }
            .buttonStyle(.plain)
            .frame(width: 30, height: 30)
            .opacity(layout.showsDismissButton ? 1 : 0.25)
            .scaleEffect(layout.showsDismissButton ? 1 : 0.25, anchor: .center)
            .allowsHitTesting(layout.showsDismissButton)
            .accessibilityHidden(!layout.showsDismissButton)
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
        .animation(buttonAnimation, value: layout)
        .onChange(of: focus.wrappedValue) { _, newValue in
            if newValue == focusID {
                draft = plainString(from: value)
            } else {
                draft = ""
            }
        }
    }

    private func plainString(from decimal: Decimal) -> String {
        NSDecimalNumber(decimal: decimal).stringValue
    }

    private func sanitizedNumericString(from input: String) -> String {
        let decimalSeparator = Locale.current.decimalSeparator ?? "."
        let groupingSeparator = Locale.current.groupingSeparator ?? ","
        let currencySymbol = Locale.current.currencySymbol ?? ""
        let filtered = input
            .replacingOccurrences(of: currencySymbol, with: "")
            .replacingOccurrences(of: groupingSeparator, with: "")
            .filter { $0.isNumber || String($0) == decimalSeparator || $0 == "-" }
        return filtered.isEmpty ? "0" : filtered
    }
}

struct EditableMoneyChipBadge: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
            .fill(Color(uiColor: .systemGray5))
            .frame(width: 20, height: 20)
            .overlay {
                Image(systemName: "pencil")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Color.secondary)
            }
            .allowsHitTesting(false)
    }
}
