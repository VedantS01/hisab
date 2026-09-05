import Foundation

/// Minimal spreadsheet reader for exporter-generated .xlsx files: shared strings
/// plus per-sheet rows as [columnLetter: cellText].
enum XLSXReader {
    struct Workbook {
        let sharedStrings: [String]
        let sheets: [String: [[String: String]]]  // entry name -> rows
    }

    static func read(data: Data) throws -> Workbook {
        let entries = try MinimalZip.entries(in: data)
        let shared: [String]
        if let ssData = entries["xl/sharedStrings.xml"] {
            shared = try SharedStringsReader.parse(ssData)
        } else {
            shared = []
        }
        var sheets: [String: [[String: String]]] = [:]
        for (name, entryData) in entries where name.hasPrefix("xl/worksheets/") && name.hasSuffix(".xml") {
            sheets[name] = try SheetReader.parse(entryData, sharedStrings: shared)
        }
        return Workbook(sharedStrings: shared, sheets: sheets)
    }
}

private final class SharedStringsReader: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var inT = false
    private var inSI = false

    static func parse(_ data: Data) throws -> [String] {
        let reader = SharedStringsReader()
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else { throw ParseError.unrecognizedFormat }
        return reader.strings
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        if name == "si" { inSI = true; current = "" }
        if name == "t" { inT = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inT { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        if name == "t" { inT = false }
        if name == "si" { inSI = false; strings.append(current) }
    }
}

private final class SheetReader: NSObject, XMLParserDelegate {
    private var sharedStrings: [String] = []
    private var rows: [[String: String]] = []
    private var currentRow: [String: String] = [:]
    private var currentColumn = ""
    private var currentType = ""
    private var currentValue = ""
    private var capturing = false

    static func parse(_ data: Data, sharedStrings: [String]) throws -> [[String: String]] {
        let reader = SheetReader()
        reader.sharedStrings = sharedStrings
        let parser = XMLParser(data: data)
        parser.delegate = reader
        guard parser.parse() else { throw ParseError.unrecognizedFormat }
        return reader.rows
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?,
                qualifiedName: String?, attributes: [String: String] = [:]) {
        switch name {
        case "row":
            currentRow = [:]
        case "c":
            let ref = attributes["r"] ?? ""
            currentColumn = String(ref.prefix { $0.isLetter })
            currentType = attributes["t"] ?? ""
            currentValue = ""
        case "v", "t":
            capturing = true
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if capturing { currentValue += string }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?,
                qualifiedName: String?) {
        switch name {
        case "v", "t":
            capturing = false
        case "c":
            guard !currentColumn.isEmpty, !currentValue.isEmpty else { break }
            if currentType == "s", let index = Int(currentValue),
               sharedStrings.indices.contains(index) {
                currentRow[currentColumn] = sharedStrings[index]
            } else {
                currentRow[currentColumn] = currentValue
            }
        case "row":
            rows.append(currentRow)
        default:
            break
        }
    }
}
