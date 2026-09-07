import AppKit
import Foundation
import PDFKit
import zlib

struct AttachmentImporter: Sendable {
    static let maximumBytes: Int64 = 25 * 1024 * 1024
    let rootDirectory: URL

    init(rootDirectory: URL? = nil) {
        self.rootDirectory = rootDirectory
            ?? FileConversationPersistence.defaultRootURL().appendingPathComponent("Attachments", isDirectory: true)
    }

    func importFile(at sourceURL: URL, conversationID: UUID) throws -> AgentAttachment {
        let accessed = sourceURL.startAccessingSecurityScopedResource()
        defer { if accessed { sourceURL.stopAccessingSecurityScopedResource() } }

        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
        guard values.isRegularFile == true else { throw AgentEngineError.unsupportedAttachment }
        let byteCount = Int64(values.fileSize ?? 0)
        guard byteCount <= Self.maximumBytes else { throw AgentEngineError.attachmentTooLarge }
        let kind = try Self.kind(forExtension: sourceURL.pathExtension)

        let conversationDirectory = rootDirectory
            .appendingPathComponent(conversationID.uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: conversationDirectory, withIntermediateDirectories: true)
        let id = UUID()
        let safeName = Self.safeDisplayName(sourceURL.lastPathComponent)
        let destination = conversationDirectory.appendingPathComponent("\(id.uuidString)-\(safeName)")
        try FileManager.default.copyItem(at: sourceURL, to: destination)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
        )

        // Validate extraction during import so a broken document does not
        // become a tool-visible attachment later.
        let extractedURL = conversationDirectory.appendingPathComponent("\(id.uuidString)-extracted.txt")
        do {
            let extracted = try AttachmentTextExtractor.extract(from: destination)
            guard !SensitiveTextDetector.containsCredential(in: extracted) else {
                throw AgentEngineError.sensitiveAttachment
            }
            try Data(extracted.utf8).write(to: extractedURL, options: .atomic)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: extractedURL.path
            )
        } catch {
            try? FileManager.default.removeItem(at: destination)
            try? FileManager.default.removeItem(at: extractedURL)
            throw error
        }
        return AgentAttachment(
            id: id,
            displayName: safeName,
            kind: kind,
            storedPath: destination.path,
            extractedTextPath: extractedURL.path,
            byteCount: byteCount
        )
    }

    func remove(_ attachment: AgentAttachment) throws {
        let url = URL(fileURLWithPath: attachment.storedPath)
        let standardizedRoot = rootDirectory.standardizedFileURL.path + "/"
        guard url.standardizedFileURL.path.hasPrefix(standardizedRoot) else {
            throw AgentEngineError.attachmentNotFound
        }
        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }
        if let extractedTextPath = attachment.extractedTextPath {
            let extractedURL = URL(fileURLWithPath: extractedTextPath)
            guard extractedURL.standardizedFileURL.path.hasPrefix(standardizedRoot) else {
                throw AgentEngineError.attachmentNotFound
            }
            if FileManager.default.fileExists(atPath: extractedURL.path) {
                try FileManager.default.removeItem(at: extractedURL)
            }
        }
    }

    private static func kind(forExtension pathExtension: String) throws -> AgentAttachmentKind {
        switch pathExtension.lowercased() {
        case "pdf": .pdf
        case "md", "markdown": .markdown
        case "doc", "docx", "rtf", "rtfd", "odt": .word
        case "xlsx", "csv", "tsv": .spreadsheet
        case "txt", "text": .text
        default: throw AgentEngineError.unsupportedAttachment
        }
    }

    private static func safeDisplayName(_ value: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:").union(.controlCharacters)
        let parts = value.components(separatedBy: forbidden).filter { !$0.isEmpty }
        return String((parts.joined(separator: "-").isEmpty ? "attachment" : parts.joined(separator: "-")).prefix(160))
    }
}

enum AttachmentTextExtractor {
    static let maximumCharacters = 400_000

    static func extract(from url: URL) throws -> String {
        let result: String
        switch url.pathExtension.lowercased() {
        case "pdf":
            guard let document = PDFDocument(url: url) else { throw AgentEngineError.unsupportedAttachment }
            result = (0..<document.pageCount).compactMap { document.page(at: $0)?.string }
                .joined(separator: "\n\n")
        case "md", "markdown", "txt", "text":
            result = try String(contentsOf: url, encoding: .utf8)
        case "csv", "tsv":
            result = try String(contentsOf: url, encoding: .utf8)
        case "docx":
            let attributed = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.officeOpenXML],
                documentAttributes: nil
            )
            result = attributed.string
        case "doc":
            let attributed = try NSAttributedString(
                url: url,
                options: [.documentType: NSAttributedString.DocumentType.docFormat],
                documentAttributes: nil
            )
            result = attributed.string
        case "rtf", "rtfd", "odt":
            let attributed = try NSAttributedString(url: url, options: [:], documentAttributes: nil)
            result = attributed.string
        case "xlsx":
            result = try XLSXTextExtractor.extract(from: url)
        default:
            throw AgentEngineError.unsupportedAttachment
        }
        let normalized = result.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw AgentEngineError.unsupportedAttachment }
        return String(normalized.prefix(maximumCharacters))
    }
}

private enum XLSXTextExtractor {
    static func extract(from url: URL) throws -> String {
        let archive = try MinimalZIPArchive(data: Data(contentsOf: url))
        let sharedStrings = try archive.entry(named: "xl/sharedStrings.xml")
            .map { SharedStringsParser.parse($0) } ?? []
        let sheetNames = archive.entryNames
            .filter { $0.hasPrefix("xl/worksheets/sheet") && $0.hasSuffix(".xml") }
            .sorted(by: naturalSheetOrder)
        guard !sheetNames.isEmpty, sheetNames.count <= 256 else {
            throw AgentEngineError.unsupportedAttachment
        }

        var sections: [String] = []
        var characterCount = 0
        for (index, name) in sheetNames.enumerated() {
            guard let data = try archive.entry(named: name) else { return "" }
            let rows = WorksheetParser.parse(data, sharedStrings: sharedStrings)
            let section = (["## Sheet \(index + 1)"] + rows.map { $0.joined(separator: "\t") })
                .joined(separator: "\n")
            sections.append(section)
            characterCount += section.count
            if characterCount >= AttachmentTextExtractor.maximumCharacters { break }
        }
        return String(sections.joined(separator: "\n\n").prefix(AttachmentTextExtractor.maximumCharacters))
    }

    private static func naturalSheetOrder(_ lhs: String, _ rhs: String) -> Bool {
        let left = Int(lhs.filter(\.isNumber)) ?? 0
        let right = Int(rhs.filter(\.isNumber)) ?? 0
        return left < right
    }
}

private struct MinimalZIPArchive {
    private struct Entry {
        let method: UInt16
        let compressedSize: Int
        let uncompressedSize: Int
        let localOffset: Int
    }

    let data: Data
    private let entries: [String: Entry]
    var entryNames: [String] { Array(entries.keys) }

    init(data: Data) throws {
        self.data = data
        guard let endOffset = Self.findSignature(0x0605_4B50, in: data),
              let count = data.uint16(at: endOffset + 10),
              let centralOffset = data.uint32(at: endOffset + 16),
              count <= 5_000
        else { throw AgentEngineError.unsupportedAttachment }

        var cursor = Int(centralOffset)
        var parsed: [String: Entry] = [:]
        for _ in 0..<Int(count) {
            guard data.uint32(at: cursor) == 0x0201_4B50,
                  let method = data.uint16(at: cursor + 10),
                  let compressed = data.uint32(at: cursor + 20),
                  let uncompressed = data.uint32(at: cursor + 24),
                  let nameLength = data.uint16(at: cursor + 28),
                  let extraLength = data.uint16(at: cursor + 30),
                  let commentLength = data.uint16(at: cursor + 32),
                  let localOffset = data.uint32(at: cursor + 42)
            else { throw AgentEngineError.unsupportedAttachment }
            let nameStart = cursor + 46
            let nameEnd = nameStart + Int(nameLength)
            guard nameEnd <= data.count,
                  let name = String(data: data[nameStart..<nameEnd], encoding: .utf8)
            else { throw AgentEngineError.unsupportedAttachment }
            parsed[name] = Entry(
                method: method,
                compressedSize: Int(compressed),
                uncompressedSize: Int(uncompressed),
                localOffset: Int(localOffset)
            )
            cursor = nameEnd + Int(extraLength) + Int(commentLength)
        }
        entries = parsed
    }

    func entry(named name: String) throws -> Data? {
        guard let entry = entries[name] else { return nil }
        guard entry.uncompressedSize <= 64 * 1024 * 1024 else {
            throw AgentEngineError.attachmentTooLarge
        }
        let offset = entry.localOffset
        guard data.uint32(at: offset) == 0x0403_4B50,
              let nameLength = data.uint16(at: offset + 26),
              let extraLength = data.uint16(at: offset + 28)
        else { throw AgentEngineError.unsupportedAttachment }
        let start = offset + 30 + Int(nameLength) + Int(extraLength)
        let end = start + entry.compressedSize
        guard end <= data.count else { throw AgentEngineError.unsupportedAttachment }
        let compressed = Data(data[start..<end])
        switch entry.method {
        case 0: return compressed
        case 8: return try Self.inflateRaw(compressed, expectedSize: entry.uncompressedSize)
        default: throw AgentEngineError.unsupportedAttachment
        }
    }

    private static func findSignature(_ signature: UInt32, in data: Data) -> Int? {
        guard data.count >= 4 else { return nil }
        let lowerBound = max(0, data.count - 65_557)
        for index in stride(from: data.count - 4, through: lowerBound, by: -1) {
            if data.uint32(at: index) == signature { return index }
        }
        return nil
    }

    private static func inflateRaw(_ input: Data, expectedSize: Int) throws -> Data {
        var stream = z_stream()
        let status = inflateInit2_(&stream, -MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard status == Z_OK else { throw AgentEngineError.unsupportedAttachment }
        defer { inflateEnd(&stream) }
        var output = Data(count: max(1, expectedSize))
        let outputCapacity = output.count
        let result: Int32 = input.withUnsafeBytes { inputBytes in
            output.withUnsafeMutableBytes { outputBytes in
                stream.next_in = UnsafeMutablePointer<Bytef>(mutating: inputBytes.bindMemory(to: Bytef.self).baseAddress)
                stream.avail_in = uInt(input.count)
                stream.next_out = outputBytes.bindMemory(to: Bytef.self).baseAddress
                stream.avail_out = uInt(outputCapacity)
                return inflate(&stream, Z_FINISH)
            }
        }
        guard result == Z_STREAM_END else { throw AgentEngineError.unsupportedAttachment }
        output.count = Int(stream.total_out)
        return output
    }
}

private final class SharedStringsParser: NSObject, XMLParserDelegate {
    private var strings: [String] = []
    private var current = ""
    private var insideText = false

    static func parse(_ data: Data) -> [String] {
        let delegate = SharedStringsParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.strings
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        if elementName == "si" { current = "" }
        if elementName == "t" { insideText = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideText { current += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "t" { insideText = false }
        if elementName == "si" { strings.append(current) }
    }
}

private final class WorksheetParser: NSObject, XMLParserDelegate {
    private let sharedStrings: [String]
    private var rows: [[String]] = []
    private var row: [String] = []
    private var cellType: String?
    private var cellReference = ""
    private var value = ""
    private var insideValue = false

    init(sharedStrings: [String]) { self.sharedStrings = sharedStrings }

    static func parse(_ data: Data, sharedStrings: [String]) -> [[String]] {
        let delegate = WorksheetParser(sharedStrings: sharedStrings)
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        parser.parse()
        return delegate.rows
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String] = [:]) {
        if elementName == "row" { row = [] }
        if elementName == "c" {
            cellType = attributes["t"]
            cellReference = attributes["r"] ?? ""
            value = ""
        }
        if elementName == "v" || elementName == "t" { insideValue = true }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if insideValue { value += string }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName qName: String?) {
        if elementName == "v" || elementName == "t" { insideValue = false }
        if elementName == "c" {
            let column = Self.columnIndex(cellReference)
            while row.count <= column { row.append("") }
            if cellType == "s", let index = Int(value), index < sharedStrings.count {
                row[column] = sharedStrings[index]
            } else {
                row[column] = value
            }
        }
        if elementName == "row" { rows.append(row) }
    }

    private static func columnIndex(_ reference: String) -> Int {
        var result = 0
        for scalar in reference.uppercased().unicodeScalars where scalar.value >= 65 && scalar.value <= 90 {
            result = result * 26 + Int(scalar.value - 64)
        }
        return max(0, result - 1)
    }
}

private extension Data {
    func uint16(at offset: Int) -> UInt16? {
        guard offset >= 0, offset + 2 <= count else { return nil }
        return UInt16(self[offset]) | UInt16(self[offset + 1]) << 8
    }

    func uint32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= count else { return nil }
        return UInt32(self[offset])
            | UInt32(self[offset + 1]) << 8
            | UInt32(self[offset + 2]) << 16
            | UInt32(self[offset + 3]) << 24
    }
}
