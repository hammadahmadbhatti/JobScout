import Foundation
import Compression

/// A small, dependency-free .xlsx writer — just what the applications sheet
/// needs: several sheets, text/number/date/link cells, a handful of styles,
/// column widths, frozen header row and autofilter.
public enum XLSX {
    /// Cell styles defined in styles.xml (the raw value is the cellXfs index).
    public enum Style: Int, Sendable {
        case text = 0, header, wrap, date, dateTime, link
        case green, red, yellow, gray
        case title, bold, number
    }

    public enum Cell: Sendable {
        case text(String, Style = .text)
        case number(Double, Style = .number)
        case date(Date, Style = .date)
        case link(String)
        case empty
    }

    public struct Sheet: Sendable {
        public var name: String
        public var columnWidths: [Double]
        public var rows: [[Cell]]
        public var freezeHeader: Bool
        public var autoFilter: Bool
        /// Height (points) for every row after the header; nil = Excel default.
        public var bodyRowHeight: Double?

        public init(
            name: String, columnWidths: [Double] = [], rows: [[Cell]],
            freezeHeader: Bool = false, autoFilter: Bool = false, bodyRowHeight: Double? = nil
        ) {
            self.name = name
            self.columnWidths = columnWidths
            self.rows = rows
            self.freezeHeader = freezeHeader
            self.autoFilter = autoFilter
            self.bodyRowHeight = bodyRowHeight
        }
    }

    /// Excel refuses text longer than this in one cell.
    public static let maxCellLength = 32_767

    public static func workbook(_ sheets: [Sheet]) -> Data {
        var zip = ZipWriter()
        zip.add("[Content_Types].xml", contentTypes(sheetCount: sheets.count))
        zip.add("_rels/.rels", rootRels)
        zip.add("xl/workbook.xml", workbookXML(sheets))
        zip.add("xl/_rels/workbook.xml.rels", workbookRels(sheetCount: sheets.count))
        zip.add("xl/styles.xml", stylesXML)
        for (i, sheet) in sheets.enumerated() {
            let (xml, links) = sheetXML(sheet)
            zip.add("xl/worksheets/sheet\(i + 1).xml", xml)
            if !links.isEmpty {
                zip.add("xl/worksheets/_rels/sheet\(i + 1).xml.rels", sheetRels(links))
            }
        }
        return zip.finish()
    }

    // MARK: Parts

    static func contentTypes(sheetCount: Int) -> String {
        let sheets = (1...max(sheetCount, 1)).map {
            #"<Override PartName="/xl/worksheets/sheet\#($0).xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>"#
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">\
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>\
        <Default Extension="xml" ContentType="application/xml"/>\
        <Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>\
        <Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>\
        \(sheets)</Types>
        """
    }

    static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>\
    </Relationships>
    """

    static func workbookXML(_ sheets: [Sheet]) -> String {
        var names = Set<String>()
        var sheetTags = ""
        var defined = ""
        for (i, sheet) in sheets.enumerated() {
            var name = safeSheetName(sheet.name)
            while names.contains(name) { name = String(name.prefix(28)) + "\(i + 1)" }
            names.insert(name)
            sheetTags += #"<sheet name="\#(escape(name))" sheetId="\#(i + 1)" r:id="rId\#(i + 1)"/>"#
            if sheet.autoFilter {
                let ref = "'\(name.replacingOccurrences(of: "'", with: "''"))'!" + filterRange(sheet, absolute: true)
                defined += #"<definedName name="_xlnm._FilterDatabase" localSheetId="\#(i)" hidden="1">\#(escape(ref))</definedName>"#
            }
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">\
        <bookViews><workbookView xWindow="0" yWindow="0" windowWidth="28800" windowHeight="17000"/></bookViews>\
        <sheets>\(sheetTags)</sheets>\
        \(defined.isEmpty ? "" : "<definedNames>\(defined)</definedNames>")\
        </workbook>
        """
    }

    static func workbookRels(sheetCount: Int) -> String {
        var rels = (1...max(sheetCount, 1)).map {
            #"<Relationship Id="rId\#($0)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet\#($0).xml"/>"#
        }.joined()
        rels += #"<Relationship Id="rId\#(sheetCount + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>"#
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(rels)</Relationships>
        """
    }

    /// Fonts: 0 normal · 1 bold · 2 link · 3 title. Fills: 0/1 required ·
    /// 2 header · 3 green · 4 red · 5 yellow · 6 gray. Order of cellXfs
    /// matches `Style`.
    static let stylesXML = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">\
    <numFmts count="2"><numFmt numFmtId="164" formatCode="yyyy-mm-dd"/><numFmt numFmtId="165" formatCode="yyyy-mm-dd hh:mm"/></numFmts>\
    <fonts count="4">\
    <font><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/></font>\
    <font><b/><sz val="11"/><color theme="1"/><name val="Calibri"/><family val="2"/></font>\
    <font><u/><sz val="11"/><color rgb="FF0563C1"/><name val="Calibri"/><family val="2"/></font>\
    <font><b/><sz val="14"/><color theme="1"/><name val="Calibri"/><family val="2"/></font>\
    </fonts>\
    <fills count="7">\
    <fill><patternFill patternType="none"/></fill>\
    <fill><patternFill patternType="gray125"/></fill>\
    <fill><patternFill patternType="solid"><fgColor rgb="FFDDEBF7"/><bgColor indexed="64"/></patternFill></fill>\
    <fill><patternFill patternType="solid"><fgColor rgb="FFC6EFCE"/><bgColor indexed="64"/></patternFill></fill>\
    <fill><patternFill patternType="solid"><fgColor rgb="FFFFC7CE"/><bgColor indexed="64"/></patternFill></fill>\
    <fill><patternFill patternType="solid"><fgColor rgb="FFFFEB9C"/><bgColor indexed="64"/></patternFill></fill>\
    <fill><patternFill patternType="solid"><fgColor rgb="FFEDEDED"/><bgColor indexed="64"/></patternFill></fill>\
    </fills>\
    <borders count="2"><border><left/><right/><top/><bottom/><diagonal/></border>\
    <border><left/><right/><top/><bottom style="thin"><color rgb="FF9BC2E6"/></bottom><diagonal/></border></borders>\
    <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>\
    <cellXfs count="13">\
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top"/></xf>\
    <xf numFmtId="0" fontId="1" fillId="2" borderId="1" xfId="0" applyFont="1" applyFill="1" applyBorder="1" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf>\
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>\
    <xf numFmtId="164" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="left" vertical="top"/></xf>\
    <xf numFmtId="165" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="left" vertical="top"/></xf>\
    <xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="top"/></xf>\
    <xf numFmtId="0" fontId="0" fillId="3" borderId="0" xfId="0" applyFill="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>\
    <xf numFmtId="0" fontId="0" fillId="4" borderId="0" xfId="0" applyFill="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>\
    <xf numFmtId="0" fontId="0" fillId="5" borderId="0" xfId="0" applyFill="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>\
    <xf numFmtId="0" fontId="0" fillId="6" borderId="0" xfId="0" applyFill="1" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>\
    <xf numFmtId="0" fontId="3" fillId="0" borderId="0" xfId="0" applyFont="1"/>\
    <xf numFmtId="0" fontId="1" fillId="0" borderId="0" xfId="0" applyFont="1" applyAlignment="1"><alignment vertical="top"/></xf>\
    <xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="right" vertical="top"/></xf>\
    </cellXfs>\
    <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>\
    </styleSheet>
    """

    static func sheetXML(_ sheet: Sheet) -> (String, [(ref: String, url: String)]) {
        var links: [(ref: String, url: String)] = []
        var rowsXML = ""
        for (r, row) in sheet.rows.enumerated() {
            let rowNum = r + 1
            var attrs = #"r="\#(rowNum)""#
            if r == 0, sheet.freezeHeader {
                attrs += #" ht="22" customHeight="1""#
            } else if r > 0, let h = sheet.bodyRowHeight {
                attrs += #" ht="\#(h)" customHeight="1""#
            }
            var cells = ""
            for (c, cell) in row.enumerated() {
                let ref = columnName(c) + String(rowNum)
                switch cell {
                case .empty:
                    continue
                case let .text(value, style):
                    cells += inlineString(ref, value, style)
                case let .number(value, style):
                    cells += #"<c r="\#(ref)" s="\#(style.rawValue)"><v>\#(value)</v></c>"#
                case let .date(value, style):
                    cells += #"<c r="\#(ref)" s="\#(style.rawValue)"><v>\#(serial(value))</v></c>"#
                case let .link(url):
                    cells += inlineString(ref, url, .link)
                    if url.hasPrefix("http"), url.count < 2000 { links.append((ref, url)) }
                }
            }
            rowsXML += "<row \(attrs)>\(cells)</row>"
        }

        var xml = """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">
        """
        if sheet.freezeHeader {
            xml += #"<sheetViews><sheetView workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/><selection pane="bottomLeft" activeCell="A2" sqref="A2"/></sheetView></sheetViews>"#
        } else {
            xml += #"<sheetViews><sheetView workbookViewId="0"/></sheetViews>"#
        }
        xml += #"<sheetFormatPr defaultRowHeight="15"/>"#
        if !sheet.columnWidths.isEmpty {
            xml += "<cols>"
            for (i, w) in sheet.columnWidths.enumerated() {
                xml += #"<col min="\#(i + 1)" max="\#(i + 1)" width="\#(w)" customWidth="1"/>"#
            }
            xml += "</cols>"
        }
        xml += "<sheetData>\(rowsXML)</sheetData>"
        if sheet.autoFilter {
            xml += #"<autoFilter ref="\#(filterRange(sheet, absolute: false))"/>"#
        }
        if !links.isEmpty {
            xml += "<hyperlinks>"
            for (i, link) in links.enumerated() {
                xml += #"<hyperlink ref="\#(link.ref)" r:id="rId\#(i + 1)"/>"#
            }
            xml += "</hyperlinks>"
        }
        xml += #"<pageMargins left="0.7" right="0.7" top="0.75" bottom="0.75" header="0.3" footer="0.3"/>"#
        xml += "</worksheet>"
        return (xml, links)
    }

    static func sheetRels(_ links: [(ref: String, url: String)]) -> String {
        let rels = links.enumerated().map { i, link in
            #"<Relationship Id="rId\#(i + 1)" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink" Target="\#(escape(link.url))" TargetMode="External"/>"#
        }.joined()
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">\(rels)</Relationships>
        """
    }

    // MARK: Helpers

    static func inlineString(_ ref: String, _ value: String, _ style: Style) -> String {
        var text = cleanXMLText(value)
        if text.utf16.count > maxCellLength {
            text = String(text.prefix(maxCellLength - 100)) + "\n… (truncated, open the job link)"
            while text.utf16.count > maxCellLength { text.removeLast(200) }
        }
        return #"<c r="\#(ref)" s="\#(style.rawValue)" t="inlineStr"><is><t xml:space="preserve">\#(escape(text))</t></is></c>"#
    }

    static func filterRange(_ sheet: Sheet, absolute: Bool) -> String {
        let cols = max(sheet.rows.first?.count ?? 1, 1)
        let rows = max(sheet.rows.count, 1)
        let last = columnName(cols - 1)
        return absolute ? "$A$1:$\(last)$\(rows)" : "A1:\(last)\(rows)"
    }

    /// Excel serial date in local time (days since 1899-12-30).
    static func serial(_ date: Date) -> Double {
        let local = date.timeIntervalSince1970 + Double(TimeZone.current.secondsFromGMT(for: date))
        // Whole seconds, so Excel shows 11:00 rather than 10:59:59.97.
        return (local.rounded() / 86_400 + 25_569)
    }

    public static func columnName(_ index: Int) -> String {
        var n = index + 1
        var name = ""
        while n > 0 {
            let r = (n - 1) % 26
            name = String(UnicodeScalar(65 + r)!) + name
            n = (n - 1) / 26
        }
        return name
    }

    static func safeSheetName(_ name: String) -> String {
        let cleaned = name.filter { !"[]:*?/\\".contains($0) }
        let trimmed = String(cleaned.prefix(31))
        return trimmed.isEmpty ? "Sheet" : trimmed
    }

    /// Removes characters XML 1.0 forbids (scraped text sometimes has them).
    static func cleanXMLText(_ s: String) -> String {
        String(String.UnicodeScalarView(s.unicodeScalars.filter { u in
            switch u.value {
            case 0x9, 0xA, 0xD: return true
            case 0x20...0xD7FF, 0xE000...0xFFFD, 0x10000...0x10FFFF: return true
            default: return false
            }
        }))
    }

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"": out += "&quot;"
            default: out.append(ch)
            }
        }
        return out
    }
}

/// Minimal ZIP archive writer (deflate via Apple's Compression framework,
/// falling back to stored entries) — enough for an .xlsx package.
struct ZipWriter {
    private var data = Data()
    private var central = Data()
    private var count: UInt16 = 0
    private let dosTime: UInt16
    private let dosDate: UInt16

    init(date: Date = Date()) {
        let c = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let hour: Int = c.hour ?? 0, minute: Int = c.minute ?? 0, second: Int = c.second ?? 0
        let year: Int = max((c.year ?? 1980) - 1980, 0), month: Int = c.month ?? 1, day: Int = c.day ?? 1
        dosTime = UInt16((hour << 11) | (minute << 5) | (second / 2))
        dosDate = UInt16((year << 9) | (month << 5) | day)
    }

    mutating func add(_ path: String, _ text: String) {
        add(path, Data(text.utf8))
    }

    mutating func add(_ path: String, _ content: Data) {
        let name = Data(path.utf8)
        let crc = CRC32.checksum(content)
        let deflated = Self.deflate(content)
        let method: UInt16 = deflated == nil ? 0 : 8
        let payload = deflated ?? content
        let offset = UInt32(data.count)

        var local = Data()
        local.append(le32: 0x0403_4B50)
        local.append(le16: 20)          // version needed
        local.append(le16: 0x0800)      // UTF-8 names
        local.append(le16: method)
        local.append(le16: dosTime)
        local.append(le16: dosDate)
        local.append(le32: crc)
        local.append(le32: UInt32(payload.count))
        local.append(le32: UInt32(content.count))
        local.append(le16: UInt16(name.count))
        local.append(le16: 0)
        local.append(name)
        data.append(local)
        data.append(payload)

        central.append(le32: 0x0201_4B50)
        central.append(le16: 20)        // version made by
        central.append(le16: 20)
        central.append(le16: 0x0800)
        central.append(le16: method)
        central.append(le16: dosTime)
        central.append(le16: dosDate)
        central.append(le32: crc)
        central.append(le32: UInt32(payload.count))
        central.append(le32: UInt32(content.count))
        central.append(le16: UInt16(name.count))
        central.append(le16: 0)         // extra
        central.append(le16: 0)         // comment
        central.append(le16: 0)         // disk
        central.append(le16: 0)         // internal attrs
        central.append(le32: 0)         // external attrs
        central.append(le32: offset)
        central.append(name)
        count += 1
    }

    mutating func finish() -> Data {
        let centralOffset = UInt32(data.count)
        var out = data
        out.append(central)
        out.append(le32: 0x0605_4B50)
        out.append(le16: 0)
        out.append(le16: 0)
        out.append(le16: count)
        out.append(le16: count)
        out.append(le32: UInt32(central.count))
        out.append(le32: centralOffset)
        out.append(le16: 0)
        return out
    }

    /// Raw DEFLATE (COMPRESSION_ZLIB emits no zlib header — exactly ZIP's method 8).
    static func deflate(_ input: Data) -> Data? {
        guard !input.isEmpty else { return nil }
        let capacity = input.count + input.count / 8 + 1024
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) -> Int in
            input.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                compression_encode_buffer(
                    dst.bindMemory(to: UInt8.self).baseAddress!, capacity,
                    src.bindMemory(to: UInt8.self).baseAddress!, input.count,
                    nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written < input.count else { return nil }
        output.count = written
        return output
    }
}

enum CRC32 {
    static let table: [UInt32] = (0..<256).map { i in
        var c = UInt32(i)
        for _ in 0..<8 { c = (c & 1) != 0 ? 0xEDB8_8320 ^ (c >> 1) : c >> 1 }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xFF)] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

private extension Data {
    mutating func append(le16 v: UInt16) {
        append(UInt8(v & 0xFF))
        append(UInt8(v >> 8))
    }

    mutating func append(le32 v: UInt32) {
        for shift in stride(from: 0, to: 32, by: 8) { append(UInt8((v >> UInt32(shift)) & 0xFF)) }
    }
}
