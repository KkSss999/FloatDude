import Foundation

struct SSEEvent: Sendable, Equatable {
    let data: String
}

enum SSEParserError: Error, Sendable, Equatable {
    case invalidUTF8
}

/// Incremental SSE framer. It never decodes an incomplete UTF-8 sequence.
struct SSEParser: Sendable {
    private var lineBuffer = Data()
    private var dataLines: [String] = []

    mutating func append(_ chunk: Data) throws -> [SSEEvent] {
        lineBuffer.append(chunk)
        return try consumeCompleteLines()
    }

    mutating func finish() throws -> [SSEEvent] {
        var events = try consumeCompleteLines()
        if !lineBuffer.isEmpty {
            var finalLine = lineBuffer
            let isTrailingCarriageReturn = finalLine.last == 0x0D
            if isTrailingCarriageReturn {
                finalLine.removeLast()
            }
            if finalLine.isEmpty {
                if let event = finishEvent() {
                    events.append(event)
                }
            } else {
                try consumeLine(finalLine)
            }
            lineBuffer.removeAll(keepingCapacity: false)
        }
        if let event = finishEvent() {
            events.append(event)
        }
        return events
    }

    private mutating func consumeCompleteLines() throws -> [SSEEvent] {
        var events: [SSEEvent] = []

        while let delimiter = lineDelimiter(in: lineBuffer) {
            let line = lineBuffer.subdata(in: 0..<delimiter.lineEnd)
            lineBuffer.removeSubrange(0..<delimiter.nextIndex)
            try consumeLine(line)

            if delimiter.isBlankLine {
                if let event = finishEvent() {
                    events.append(event)
                }
            }
        }
        return events
    }

    private mutating func consumeLine(_ line: Data) throws {
        guard let string = String(data: line, encoding: .utf8) else {
            throw SSEParserError.invalidUTF8
        }

        guard !string.isEmpty else {
            return
        }
        guard !string.hasPrefix(":") else {
            return
        }

        let separator = string.firstIndex(of: ":")
        let field: String
        let value: String
        if let separator {
            field = String(string[..<separator])
            var start = string.index(after: separator)
            if start < string.endIndex && string[start] == " " {
                start = string.index(after: start)
            }
            value = String(string[start...])
        } else {
            field = string
            value = ""
        }

        if field == "data" {
            dataLines.append(value)
        }
    }

    private mutating func finishEvent() -> SSEEvent? {
        guard !dataLines.isEmpty else {
            return nil
        }
        defer { dataLines.removeAll(keepingCapacity: true) }
        return SSEEvent(data: dataLines.joined(separator: "\n"))
    }

    private func lineDelimiter(in data: Data) -> (lineEnd: Int, nextIndex: Int, isBlankLine: Bool)? {
        let bytes = [UInt8](data)
        for index in bytes.indices {
            switch bytes[index] {
            case 0x0A: // LF
                let lineEnd = index > 0 && bytes[index - 1] == 0x0D ? index - 1 : index
                return (lineEnd, index + 1, lineEnd == 0)
            case 0x0D: // CR, retaining a trailing CR until the next chunk
                guard index + 1 < bytes.count else {
                    return nil
                }
                let lineEnd = index
                let nextIndex = bytes[index + 1] == 0x0A ? index + 2 : index + 1
                return (lineEnd, nextIndex, lineEnd == 0)
            default:
                continue
            }
        }
        return nil
    }
}
