import Foundation

enum MonzoQIFImporterError: Error, Equatable {
    case invalidEncoding
    case invalidHeader(String)
    case invalidDate(String)
    case invalidAmount(String)
    case invalidStatement(String)
}

final class MonzoQIFImporter {
    func parse(data: Data) throws -> MonzoQIFStatement {
        let contents = try decode(data: data)
        let lines = contents
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
            .components(separatedBy: "\n")

        guard let firstNonEmptyLine = lines.first(where: { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
            throw MonzoQIFImporterError.invalidStatement("The QIF file is empty.")
        }
        guard firstNonEmptyLine == "!Type:Bank" else {
            throw MonzoQIFImporterError.invalidHeader(firstNonEmptyLine)
        }

        var transactions: [MonzoQIFTransaction] = []
        var fields: [Character: String] = [:]

        for rawLine in lines.drop(while: { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }).dropFirst() {
            let line = rawLine.trimmingCharacters(in: .newlines)
            guard !line.isEmpty else { continue }

            if line == "^" {
                if !fields.isEmpty {
                    transactions.append(try transaction(from: fields))
                    fields.removeAll(keepingCapacity: true)
                }
                continue
            }

            guard let key = line.first else { continue }
            fields[key] = String(line.dropFirst())
        }

        if !fields.isEmpty {
            transactions.append(try transaction(from: fields))
        }

        guard let startDate = transactions.map(\.postedAt).min(),
              let endDate = transactions.map(\.postedAt).max() else {
            throw MonzoQIFImporterError.invalidStatement("The QIF file does not contain any transactions.")
        }

        return MonzoQIFStatement(
            accountIdentifier: "monzo_qif",
            currencyCode: "GBP",
            statementStartDate: startDate,
            statementEndDate: endDate,
            ledgerBalance: nil,
            transactions: transactions
        )
    }

    private func decode(data: Data) throws -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        throw MonzoQIFImporterError.invalidEncoding
    }

    private func transaction(from fields: [Character: String]) throws -> MonzoQIFTransaction {
        let rawDate = fields["D"] ?? ""
        let rawAmount = fields["T"] ?? ""
        let payee = fields["P"]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let postedAt = try Self.parseDate(rawDate)
        let amount = try Self.parseAmount(rawAmount)
        let transactionType = amount < 0 ? "DEBIT" : "CREDIT"

        return MonzoQIFTransaction(
            externalTransactionID: Self.syntheticExternalTransactionID(
                postedAt: postedAt,
                amount: amount,
                payee: payee
            ),
            postedAt: postedAt,
            amount: amount,
            payee: payee,
            transactionType: transactionType,
            rawSourcePayload: Self.makeRawSourcePayload(
                date: rawDate,
                amount: rawAmount,
                payee: payee,
                category: fields["L"] ?? "",
                memo: fields["M"] ?? "",
                address: fields["A"] ?? ""
            )
        )
    }

    private static func parseDate(_ rawValue: String) throws -> Date {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let formats = ["dd/MM/yyyy", "d/MM/yyyy", "dd/MM/yy", "d/MM/yy"]

        for format in formats {
            let formatter = DateFormatter()
            formatter.calendar = fixedCalendar
            formatter.timeZone = fixedCalendar.timeZone
            formatter.locale = Locale(identifier: "en_GB")
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return fixedCalendar.date(
                    bySettingHour: 12,
                    minute: 0,
                    second: 0,
                    of: date
                ) ?? date
            }
        }

        throw MonzoQIFImporterError.invalidDate(rawValue)
    }

    private static func parseAmount(_ rawValue: String) throws -> Decimal {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Decimal(string: trimmed) else {
            throw MonzoQIFImporterError.invalidAmount(rawValue)
        }
        return amount
    }

    private static func syntheticExternalTransactionID(postedAt: Date, amount: Decimal, payee: String) -> String {
        let day = qifIdentityDateFormatter.string(from: postedAt)
        let normalizedPayee = payee
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .split(whereSeparator: \.isWhitespace)
            .joined(separator: " ")
        return "\(day)|\(amount)|\(normalizedPayee)"
    }

    private static func makeRawSourcePayload(
        date: String,
        amount: String,
        payee: String,
        category: String,
        memo: String,
        address: String
    ) -> String {
        let payload = RawQIFSourcePayload(
            date: date,
            amount: amount,
            payee: payee,
            category: category,
            memo: memo,
            address: address
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload), let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static var fixedCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }

    private static let qifIdentityDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = fixedCalendar
        formatter.timeZone = fixedCalendar.timeZone
        formatter.locale = Locale(identifier: "en_GB")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

private struct RawQIFSourcePayload: Codable {
    let date: String
    let amount: String
    let payee: String
    let category: String
    let memo: String
    let address: String
}
