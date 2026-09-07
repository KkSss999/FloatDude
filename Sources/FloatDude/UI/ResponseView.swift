import SwiftUI

/// Response states are rendered independently so a coordinator can replace
/// the stream implementation without changing this presentation surface.
struct ResponseView: View {
    let response: String
    let state: FloatingPanelState
    let onCopy: ((String) -> Void)?
    let onCancel: (() -> Void)?
    let onRetry: (() -> Void)?
    let onOpenSettings: (() -> Void)?

    init(
        response: String,
        state: FloatingPanelState = .completed(text: ""),
        onCopy: ((String) -> Void)? = nil,
        onCancel: (() -> Void)? = nil,
        onRetry: (() -> Void)? = nil,
        onOpenSettings: (() -> Void)? = nil
    ) {
        self.response = response
        self.state = state
        self.onCopy = onCopy
        self.onCancel = onCancel
        self.onRetry = onRetry
        self.onOpenSettings = onOpenSettings
    }

    private var visibleResponse: String {
        guard let stateResponse = state.responseText else { return response }
        return stateResponse.isEmpty ? response : stateResponse
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            content
            footer
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var header: some View {
        Rectangle()
            .fill(Color.primary.opacity(0.10))
            .frame(height: 0.5)
            .padding(.vertical, 3)
            .accessibilityHidden(true)
    }

    @ViewBuilder
    private var content: some View {
        switch state {
        case .loading(let action):
            statusCard {
                ProgressView()
                    .controlSize(.small)
                Text("Preparing \(action.title)…")
            }
        case .streaming:
            responseText(visibleResponse)
                .overlay(alignment: .topTrailing) {
                    ProgressView()
                        .controlSize(.small)
                        .padding(.vertical, 4)
                        .padding(.horizontal, 1)
                        .accessibilityLabel("Generating")
                }
        case .completed:
            responseText(visibleResponse)
        case .cancelled:
            statusCard {
                Image(systemName: "pause.circle")
                Text("Request cancelled")
            }
        case .error(let message):
            statusCard {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Text(message)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case .idle, .prompting:
            EmptyView()
        }
    }

    private func responseText(_ text: String) -> some View {
        ScrollView(.vertical) {
            MarkdownResponse(text: text.isEmpty ? " " : text)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .padding(.horizontal, 1)
        }
        .frame(maxHeight: 140)
        .accessibilityLabel("Response text")
    }

    private func statusCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 10, content: content)
            .font(.body)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 10)
    }

    @ViewBuilder
    private var footer: some View {
        switch state {
        case .loading, .streaming:
            HStack {
                Text("You can cancel at any time")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("Cancel", role: .cancel) { onCancel?() }
                    .buttonStyle(GlassActionStyle())
            }
        case .completed:
            HStack {
                Button {
                    onCopy?(visibleResponse)
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .buttonStyle(GlassActionStyle())
                .disabled(visibleResponse.isEmpty)
                .accessibilityHint("Copy the response to the clipboard")
                Spacer(minLength: 8)
                escButton
            }
        case .cancelled, .error:
            HStack {
                Button("Try Again", action: { onRetry?() })
                    .buttonStyle(.borderedProminent)
                    .disabled(onRetry == nil)
                if case .error = state {
                    Button("Settings…", action: { onOpenSettings?() })
                        .buttonStyle(GlassActionStyle())
                        .disabled(onOpenSettings == nil)
                }
                Spacer(minLength: 8)
                escButton
            }
        case .idle, .prompting:
            EmptyView()
        }
    }

    private var escButton: some View {
        Button {
            onCancel?()
        } label: {
            Text("Esc to close")
                .font(.caption)
        }
        .buttonStyle(.borderless)
        .keyboardShortcut(.escape)
        .foregroundStyle(.secondary)
    }
}

// MARK: - Markdown

enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case unorderedList([String])
    case orderedList([String])
    case quote(String)
    case code(language: String?, text: String)
    case table(headers: [String], rows: [[String]])
    case divider
}

enum MarkdownDocument {
    static func parse(_ source: String) -> [MarkdownBlock] {
        let lines = source.components(separatedBy: .newlines)
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var index = 0

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: "\n")))
            paragraph.removeAll(keepingCapacity: true)
        }

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                flushParagraph()
                let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                index += 1
                var code: [String] = []
                while index < lines.count,
                      !lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("```") {
                    code.append(lines[index])
                    index += 1
                }
                if index < lines.count { index += 1 }
                blocks.append(.code(language: language.isEmpty ? nil : language,
                                    text: code.joined(separator: "\n")))
                continue
            }

            if index + 1 < lines.count,
               trimmed.contains("|"),
               isTableSeparator(lines[index + 1]) {
                flushParagraph()
                let headers = tableCells(line)
                index += 2
                var rows: [[String]] = []
                while index < lines.count {
                    let row = lines[index].trimmingCharacters(in: .whitespaces)
                    guard !row.isEmpty, row.contains("|") else { break }
                    rows.append(tableCells(lines[index]))
                    index += 1
                }
                blocks.append(.table(headers: headers, rows: rows))
                continue
            }

            if let heading = heading(line) {
                flushParagraph()
                blocks.append(heading)
                index += 1
                continue
            }

            if trimmed == "---" || trimmed == "***" || trimmed == "___" {
                flushParagraph()
                blocks.append(.divider)
                index += 1
                continue
            }

            if unorderedItem(line) != nil {
                flushParagraph()
                var items: [String] = []
                while index < lines.count, let item = unorderedItem(lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.unorderedList(items))
                continue
            }

            if orderedItem(line) != nil {
                flushParagraph()
                var items: [String] = []
                while index < lines.count, let item = orderedItem(lines[index]) {
                    items.append(item)
                    index += 1
                }
                blocks.append(.orderedList(items))
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                var quote: [String] = []
                while index < lines.count {
                    let candidate = lines[index].trimmingCharacters(in: .whitespaces)
                    guard candidate.hasPrefix(">") else { break }
                    quote.append(String(candidate.dropFirst()).trimmingCharacters(in: .whitespaces))
                    index += 1
                }
                blocks.append(.quote(quote.joined(separator: "\n")))
                continue
            }

            if trimmed.isEmpty {
                flushParagraph()
            } else {
                paragraph.append(line)
            }
            index += 1
        }

        flushParagraph()
        return blocks
    }

    private static func heading(_ line: String) -> MarkdownBlock? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let level = trimmed.prefix(while: { $0 == "#" }).count
        guard (1...6).contains(level),
              trimmed.dropFirst(level).first == " "
        else { return nil }
        return .heading(
            level: level,
            text: String(trimmed.dropFirst(level + 1))
        )
    }

    private static func unorderedItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        for prefix in ["- ", "* ", "+ "] where trimmed.hasPrefix(prefix) {
            return String(trimmed.dropFirst(2))
        }
        return nil
    }

    private static func orderedItem(_ line: String) -> String? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard let dot = trimmed.firstIndex(of: "."),
              dot != trimmed.startIndex,
              trimmed[..<dot].allSatisfy(\.isNumber)
        else { return nil }
        let remainder = trimmed[trimmed.index(after: dot)...]
        guard remainder.first == " " else { return nil }
        return String(remainder.dropFirst())
    }

    private static func tableCells(_ line: String) -> [String] {
        line.trimmingCharacters(in: CharacterSet(charactersIn: " |"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private static func isTableSeparator(_ line: String) -> Bool {
        let cells = tableCells(line)
        return !cells.isEmpty && cells.allSatisfy { cell in
            let normalized = cell.trimmingCharacters(in: CharacterSet(charactersIn: ":"))
            return normalized.count >= 3 && normalized.allSatisfy { $0 == "-" }
        }
    }
}

private struct MarkdownResponse: View {
    let blocks: [MarkdownBlock]

    init(text: String) {
        blocks = MarkdownDocument.parse(text)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case let .heading(level, text):
            Text(inline(text))
                .font(headingFont(level))
                .padding(.top, level == 1 ? 2 : 0)
        case let .paragraph(text):
            Text(inline(text))
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        case let .unorderedList(items):
            list(items, ordered: false)
        case let .orderedList(items):
            list(items, ordered: true)
        case let .quote(text):
            HStack(alignment: .top, spacing: 9) {
                Capsule().fill(Color.accentColor.opacity(0.55)).frame(width: 2)
                Text(inline(text))
                    .font(.body.italic())
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        case let .code(language, text):
            VStack(alignment: .leading, spacing: 5) {
                if let language {
                    Text(language.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(.secondary)
                }
                ScrollView(.horizontal) {
                    Text(text)
                        .font(.system(size: 12, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(10)
            .glassInset(cornerRadius: 10)
        case let .table(headers, rows):
            markdownTable(headers: headers, rows: rows)
        case .divider:
            Divider().opacity(0.6)
        }
    }

    private func list(_ items: [String], ordered: Bool) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(ordered ? "\(index + 1)." : "•")
                        .foregroundStyle(.secondary)
                        .frame(width: 18, alignment: .trailing)
                    Text(inline(item))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .font(.body)
    }

    private func markdownTable(headers: [String], rows: [[String]]) -> some View {
        let columnCount = max(headers.count, rows.map(\.count).max() ?? 0)
        return ScrollView(.horizontal) {
            VStack(alignment: .leading, spacing: 0) {
                tableRow(headers, count: columnCount, isHeader: true)
                Divider()
                ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                    tableRow(row, count: columnCount, isHeader: false)
                    Divider().opacity(0.35)
                }
            }
        }
        .glassInset(cornerRadius: 10)
    }

    private func tableRow(_ cells: [String], count: Int, isHeader: Bool) -> some View {
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<count, id: \.self) { index in
                Text(inline(index < cells.count ? cells[index] : ""))
                    .font(.system(size: 12, weight: isHeader ? .semibold : .regular))
                    .frame(width: 140, alignment: .leading)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 7)
            }
        }
    }

    private func inline(_ source: String) -> AttributedString {
        (try? AttributedString(
            markdown: source,
            options: .init(
                interpretedSyntax: .inlineOnlyPreservingWhitespace,
                failurePolicy: .returnPartiallyParsedIfPossible
            )
        )) ?? AttributedString(source)
    }

    private func headingFont(_ level: Int) -> Font {
        switch level {
        case 1: .title3.weight(.semibold)
        case 2: .headline
        default: .subheadline.weight(.semibold)
        }
    }
}
