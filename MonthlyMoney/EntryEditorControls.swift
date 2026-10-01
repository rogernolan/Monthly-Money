import SwiftUI

struct EntryEditorField<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            content
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct EntryEditorTypePicker: View {
    @Binding var selection: MonthEntryKind

    var body: some View {
        EntryEditorField(title: "Type") {
            HStack(spacing: 2) {
                ForEach(MonthEntryKind.allCases) { kind in
                    Button {
                        selection = kind
                    } label: {
                        Text(kind.title)
                            .font(.subheadline.weight(.medium))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                            .foregroundStyle(selection == kind ? Color.white : Color.primary)
                            .background {
                                if selection == kind {
                                    RoundedRectangle(cornerRadius: 7)
                                        .fill(kind == .credit ? Color.green : Color.red)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(selection == kind ? "Selected" : "")
                }
            }
            .padding(2)
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
            .accessibilityIdentifier("entry-editor-type")
        }
    }
}

struct EntryEditorRepeatPicker: View {
    @Binding var selection: MonthRepeatMode
    let existingMode: RepeatMode?
    var calendarContinuation = false

    var body: some View {
        EntryEditorField(title: "Repeat") {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 2) {
                    ForEach(MonthRepeatMode.allCases, id: \.self) { mode in
                        let available = MonthRepeatMode.availableModes(
                            existing: existingMode, calendarContinuation: calendarContinuation
                        ).contains(mode)
                        Button {
                            selection = mode
                        } label: {
                            Text(mode.title)
                                .font(.subheadline.weight(.medium))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 8)
                                .foregroundStyle(selection == mode ? Color.white : (available ? Color.primary : Color.secondary))
                                .background {
                                    if selection == mode {
                                        RoundedRectangle(cornerRadius: 7).fill(Color.accentColor)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .disabled(!available)
                        .accessibilityValue(selection == mode ? "Selected" : (available ? "" : "Unavailable for this entry"))
                    }
                }
                .padding(2)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 9))
                .accessibilityIdentifier("entry-editor-repeat")
                if existingMode == .periodic && selection == .oneOff {
                    Text("Only this occurrence becomes a one-off entry. Later repeats continue.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if existingMode == .calendar && selection == .oneOff {
                    Text("This entry becomes a one-off entry.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if calendarContinuation && selection == .oneOff {
                    Text("This entry is one-off; the calendar repeat resumes next month.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}
