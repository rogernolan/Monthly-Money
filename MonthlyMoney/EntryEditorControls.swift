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
            Picker("Type", selection: $selection) {
                ForEach(MonthEntryKind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
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
                Picker("Repeat", selection: Binding(
                    get: { selection },
                    set: { mode in
                        if MonthRepeatMode.availableModes(
                            existing: existingMode, calendarContinuation: calendarContinuation
                        ).contains(mode) {
                            selection = mode
                        }
                    }
                )) {
                    ForEach(MonthRepeatMode.allCases, id: \.self) { mode in
                        let available = MonthRepeatMode.availableModes(
                            existing: existingMode, calendarContinuation: calendarContinuation
                        ).contains(mode)
                        Text(mode.title).tag(mode)
                        .disabled(!available)
                    }
                }
                .labelsHidden()
                .pickerStyle(.segmented)
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
