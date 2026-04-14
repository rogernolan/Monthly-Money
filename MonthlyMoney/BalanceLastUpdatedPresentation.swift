import Foundation

enum BalanceLastUpdatedPresentation {
    static func text(for updatedAt: Date?, relativeTo referenceDate: Date) -> String? {
        guard let updatedAt else { return nil }
        return "Last updated \(dateString(for: updatedAt, relativeTo: referenceDate))"
    }

    static func isStale(_ updatedAt: Date, relativeTo referenceDate: Date, calendar: Calendar = .current) -> Bool {
        let updatedDay = calendar.startOfDay(for: updatedAt)
        let referenceDay = calendar.startOfDay(for: referenceDate)
        let elapsedDays = calendar.dateComponents([.day], from: updatedDay, to: referenceDay).day ?? 0
        return elapsedDays > 7
    }

    private static func dateString(for updatedAt: Date, relativeTo referenceDate: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent

        let calendar = Calendar.current
        if calendar.isDate(updatedAt, inSameDayAs: referenceDate) {
            formatter.setLocalizedDateFormatFromTemplate("HH:mm")
        } else {
            formatter.setLocalizedDateFormatFromTemplate("d MMM")
        }

        return formatter.string(from: updatedAt)
    }
}
