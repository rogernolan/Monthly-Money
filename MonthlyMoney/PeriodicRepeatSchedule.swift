import Foundation

struct CivilDate: Hashable, Codable, Comparable, CustomStringConvertible {
    let year: Int
    let month: Int
    let day: Int

    init?(year: Int, month: Int, day: Int) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.calendar = calendar
        components.timeZone = calendar.timeZone
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let date = calendar.date(from: components) else { return nil }
        let resolved = calendar.dateComponents([.year, .month, .day], from: date)
        guard resolved.year == year, resolved.month == month, resolved.day == day else { return nil }
        self.year = year
        self.month = month
        self.day = day
    }

    init?(rawValue: String) {
        let parts = rawValue.split(separator: "-")
        guard parts.count == 3,
              let year = Int(parts[0]),
              let month = Int(parts[1]),
              let day = Int(parts[2]),
              String(format: "%04d-%02d-%02d", year, month, day) == rawValue,
              let value = CivilDate(year: year, month: month, day: day) else {
            return nil
        }
        self = value
    }

    var rawValue: String { String(format: "%04d-%02d-%02d", year, month, day) }
    var description: String { rawValue }

    func adding(days: Int, calendar: Calendar = Calendar(identifier: .gregorian)) -> CivilDate? {
        var calendar = calendar
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        guard let date = calendar.date(from: components),
              let result = calendar.date(byAdding: .day, value: days, to: date) else {
            return nil
        }
        let resolved = calendar.dateComponents([.year, .month, .day], from: result)
        guard let year = resolved.year, let month = resolved.month, let day = resolved.day else { return nil }
        return CivilDate(year: year, month: month, day: day)
    }

    static func < (lhs: CivilDate, rhs: CivilDate) -> Bool { lhs.rawValue < rhs.rawValue }
}

struct PeriodicOccurrenceProjection: Equatable {
    let repeatID: UUID
    let scheduledDate: CivilDate
    let type: PlannedItemType
    let label: String
    let matchingString: String?
    let amount: Decimal
    let notes: String
}

enum PeriodicRepeatSchedule {
    static func project(
        repeatID: UUID,
        revisions: [PeriodicRepeatRevision],
        skips: [PeriodicRepeatSkip],
        from: CivilDate,
        through: CivilDate
    ) -> [PeriodicOccurrenceProjection] {
        guard from <= through else { return [] }
        let ordered = revisions
            .filter { $0.repeatID == repeatID && $0.repeatDays > 0 }
            .sorted {
                if $0.effectiveDate != $1.effectiveDate { return $0.effectiveDate < $1.effectiveDate }
                return $0.id.uuidString < $1.id.uuidString
            }
        let skippedDates = Set(skips.filter { $0.repeatID == repeatID }.map(\.scheduledDate))
        var result: [PeriodicOccurrenceProjection] = []

        for (index, revision) in ordered.enumerated() {
            let lowerBound = max(from, revision.effectiveDate)
            let upperBound = index + 1 < ordered.count
                ? min(through, ordered[index + 1].effectiveDate.adding(days: -1) ?? through)
                : through
            guard lowerBound <= upperBound else { continue }

            var candidate = revision.anchorDate
            if candidate < lowerBound {
                let calendar = Calendar(identifier: .gregorian)
                let anchor = calendar.date(from: DateComponents(year: candidate.year, month: candidate.month, day: candidate.day))!
                let lower = calendar.date(from: DateComponents(year: lowerBound.year, month: lowerBound.month, day: lowerBound.day))!
                let elapsed = calendar.dateComponents([.day], from: anchor, to: lower).day ?? 0
                let steps = (elapsed + revision.repeatDays - 1) / revision.repeatDays
                guard let first = candidate.adding(days: steps * revision.repeatDays) else { continue }
                candidate = first
            }

            while candidate <= upperBound {
                if candidate >= from && !skippedDates.contains(candidate) {
                    result.append(PeriodicOccurrenceProjection(
                        repeatID: repeatID,
                        scheduledDate: candidate,
                        type: revision.type,
                        label: revision.label,
                        matchingString: revision.matchingString,
                        amount: revision.amount,
                        notes: revision.notes
                    ))
                }
                guard let next = candidate.adding(days: revision.repeatDays) else { break }
                candidate = next
            }
        }

        return result.sorted { $0.scheduledDate < $1.scheduledDate }
    }

    static func monthlySavingsTarget(revisions: [PeriodicRepeatRevision], effectiveOn date: CivilDate) -> Decimal {
        let activeByRepeat = Dictionary(grouping: revisions.filter { $0.effectiveDate <= date }, by: \.repeatID)
        let annualized = activeByRepeat.values.compactMap { revisions -> Decimal? in
            guard let revision = revisions.max(by: {
                if $0.effectiveDate != $1.effectiveDate { return $0.effectiveDate < $1.effectiveDate }
                return $0.id.uuidString < $1.id.uuidString
            }), revision.repeatDays > 28, revision.type == .fixedDebit else {
                return nil
            }
            return revision.amount * Decimal(string: "365.2425")! / Decimal(revision.repeatDays)
        }.reduce(Decimal.zero, +)
        return annualized / Decimal(12)
    }

    static func annualizedCost(
        repeats: [PeriodicRepeat],
        revisions: [PeriodicRepeatRevision],
        effectiveOn date: CivilDate
    ) -> Decimal {
        let activeRepeatIDs = Set(repeats.filter { $0.endDate.map { date < $0 } ?? true }.map(\.id))
        let activeByRepeat = Dictionary(grouping: revisions.filter {
            activeRepeatIDs.contains($0.repeatID) && $0.effectiveDate <= date
        }, by: \.repeatID)
        return activeByRepeat.values.compactMap { values -> Decimal? in
            guard let revision = values.max(by: {
                if $0.effectiveDate != $1.effectiveDate { return $0.effectiveDate < $1.effectiveDate }
                return $0.id.uuidString < $1.id.uuidString
            }), revision.repeatDays > 28, revision.type == .fixedDebit else { return nil }
            return revision.amount * Decimal(string: "365.2425")! / Decimal(revision.repeatDays)
        }.reduce(Decimal.zero, +)
    }

    static func monthlySavingsTarget(
        repeats: [PeriodicRepeat],
        revisions: [PeriodicRepeatRevision],
        effectiveOn date: CivilDate
    ) -> Decimal {
        annualizedCost(repeats: repeats, revisions: revisions, effectiveOn: date) / Decimal(12)
    }
}
