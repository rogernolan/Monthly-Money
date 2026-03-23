import Foundation

enum NationwideOFXImporterError: Error, Equatable {
    case invalidXML
    case missingElement(String)
    case invalidAmount(String)
    case invalidDate(String)
    case invalidStatement(String)
}

final class NationwideOFXImporter {
    func parse(data: Data) throws -> NationwideOFXStatement {
        let treeBuilder = OFXTreeBuilder()
        let parser = XMLParser(data: data)
        parser.delegate = treeBuilder

        guard parser.parse(), let root = treeBuilder.root else {
            throw NationwideOFXImporterError.invalidXML
        }

        let ofx = root.name == "OFX" ? root : try root.child(named: "OFX")
        let bankMessages = try ofx.child(named: "BANKMSGSRSV1")
        let statementResponse = try bankMessages.child(named: "STMTTRNRS")
        let statement = try statementResponse.child(named: "STMTRS")
        let accountFrom = try statement.child(named: "BANKACCTFROM")
        let transactionList = try statement.child(named: "BANKTRANLIST")

        let currencyCode = try statement.text(named: "CURDEF")
        let accountIdentifier = try accountFrom.text(named: "ACCTID")
        let statementStartDate = try Self.parseOFXDate(transactionList.text(named: "DTSTART"))
        let statementEndDate = try Self.parseOFXDate(transactionList.text(named: "DTEND"))
        let ledgerBalance = try Self.parseLedgerBalance(from: statement)

        var transactions: [NationwideOFXTransaction] = []
        for transactionNode in transactionList.children(named: "STMTTRN") {
            let transactionType = try transactionNode.text(named: "TRNTYPE")
            let postedAt = try Self.parseOFXDate(transactionNode.text(named: "DTPOSTED"))
            let amountText = try transactionNode.text(named: "TRNAMT")
            let amount = try Self.parseAmount(amountText)
            let externalTransactionID = try transactionNode.text(named: "FITID")
            let payee = try transactionNode.text(named: "NAME")

            transactions.append(
                NationwideOFXTransaction(
                    externalTransactionID: externalTransactionID,
                    postedAt: postedAt,
                    amount: amount,
                    payee: payee,
                    transactionType: transactionType,
                    rawSourcePayload: Self.makeRawSourcePayload(
                        fitid: externalTransactionID,
                        trntype: transactionType,
                        dtposted: try transactionNode.text(named: "DTPOSTED"),
                        trnamt: amountText,
                        name: payee
                    )
                )
            )
        }

        guard !currencyCode.isEmpty, !accountIdentifier.isEmpty else {
            throw NationwideOFXImporterError.invalidStatement("Missing account metadata")
        }

        return NationwideOFXStatement(
            accountIdentifier: accountIdentifier,
            currencyCode: currencyCode,
            statementStartDate: statementStartDate,
            statementEndDate: statementEndDate,
            ledgerBalance: ledgerBalance,
            transactions: transactions
        )
    }

    private static func parseAmount(_ rawValue: String) throws -> Decimal {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Decimal(string: trimmed) else {
            throw NationwideOFXImporterError.invalidAmount(rawValue)
        }
        return amount
    }

    private static func parseOFXDate(_ rawValue: String) throws -> Date {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^(\d{4})(\d{2})(\d{2})(\d{2})(\d{2})(\d{2})(?:\.(\d+))?(?:\[(.+)\])?$"#
        let regex = try! NSRegularExpression(pattern: pattern, options: [])
        let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
        guard let match = regex.firstMatch(in: trimmed, options: [], range: range) else {
            throw NationwideOFXImporterError.invalidDate(rawValue)
        }

        func intValue(_ index: Int) throws -> Int {
            guard let range = Range(match.range(at: index), in: trimmed),
                  let value = Int(trimmed[range]) else {
                throw NationwideOFXImporterError.invalidDate(rawValue)
            }
            return value
        }

        let year = try intValue(1)
        let month = try intValue(2)
        let day = try intValue(3)
        let hour = try intValue(4)
        let minute = try intValue(5)
        let second = try intValue(6)
        let fractionalNanoseconds: Int
        if let range = Range(match.range(at: 7), in: trimmed) {
            let fractionText = String(trimmed[range])
            let padded = fractionText.padding(toLength: 9, withPad: "0", startingAt: 0)
            guard let nanoseconds = Int(padded.prefix(9)) else {
                throw NationwideOFXImporterError.invalidDate(rawValue)
            }
            fractionalNanoseconds = nanoseconds
        } else {
            fractionalNanoseconds = 0
        }

        let timezoneSeconds = try timezoneSeconds(from: match, in: trimmed, rawValue: rawValue)
        guard let timeZone = TimeZone(secondsFromGMT: timezoneSeconds) else {
            throw NationwideOFXImporterError.invalidDate(rawValue)
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = DateComponents(
            timeZone: timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute,
            second: second
        )
        guard let date = calendar.date(from: components) else {
            throw NationwideOFXImporterError.invalidDate(rawValue)
        }
        guard fractionalNanoseconds > 0 else {
            return date
        }
        return date.addingTimeInterval(TimeInterval(fractionalNanoseconds) / 1_000_000_000)
    }

    private static func timezoneSeconds(from match: NSTextCheckingResult, in string: String, rawValue: String) throws -> Int {
        guard let range = Range(match.range(at: 8), in: string) else {
            return 0
        }

        let token = String(string[range]).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return 0 }

        let sign = token.hasPrefix("-") ? -1 : 1
        let digits = token.trimmingCharacters(in: CharacterSet(charactersIn: "+-"))
        guard !digits.isEmpty else { return 0 }

        if digits.count <= 2, let hours = Int(digits) {
            return sign * hours * 3600
        }

        let padded = digits.padding(toLength: max(4, digits.count), withPad: "0", startingAt: 0)
        let hoursText = String(padded.prefix(max(0, padded.count - 2)))
        let minutesText = String(padded.suffix(2))
        guard let hours = Int(hoursText), let minutes = Int(minutesText) else {
            throw NationwideOFXImporterError.invalidDate(rawValue)
        }
        return sign * ((hours * 60 + minutes) * 60)
    }

    private static func makeRawSourcePayload(fitid: String, trntype: String, dtposted: String, trnamt: String, name: String) -> String {
        let payload = RawSourcePayload(fitid: fitid, trntype: trntype, dtposted: dtposted, trnamt: trnamt, name: name)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(payload), let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }

    private static func parseLedgerBalance(from statement: OFXTreeBuilder.Node) throws -> Decimal? {
        guard let ledgerBalanceNode = statement.children.first(where: { $0.name == "LEDGERBAL" }) else {
            return nil
        }
        let balanceText = try ledgerBalanceNode.text(named: "BALAMT")
        return try parseAmount(balanceText)
    }
}

private struct RawSourcePayload: Codable {
    let fitid: String
    let trntype: String
    let dtposted: String
    let trnamt: String
    let name: String
}

private final class OFXTreeBuilder: NSObject, XMLParserDelegate {
    fileprivate final class Node {
        let name: String
        var text: String = ""
        var children: [Node] = []

        init(name: String) {
            self.name = name
        }
    }

    fileprivate var root: Node?
    private var stack: [Node] = []

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String : String] = [:]) {
        let node = Node(name: elementName)
        if let parent = stack.last {
            parent.children.append(node)
        } else {
            root = node
        }
        stack.append(node)
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        stack.last?.text += string
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        _ = stack.popLast()
    }
}

private extension OFXTreeBuilder.Node {
    func child(named name: String) throws -> OFXTreeBuilder.Node {
        guard let child = children.first(where: { $0.name == name }) else {
            throw NationwideOFXImporterError.missingElement(name)
        }
        return child
    }

    func children(named name: String) -> [OFXTreeBuilder.Node] {
        children.filter { $0.name == name }
    }

    func text(named name: String) throws -> String {
        try child(named: name).trimmedText
    }

    var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
