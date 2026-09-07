import Foundation
import XCTest
@testable import FloatDude

final class AgentEngineTests: XCTestCase {
    func testConversationArchiveRoundTripsMessagesAndAttachments() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatDude-AgentEngineTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let persistence = FileConversationPersistence(fileURL: directory.appendingPathComponent("archive.json"))
        let attachment = AgentAttachment(
            displayName: "notes.md",
            kind: .markdown,
            storedPath: directory.appendingPathComponent("notes.md").path,
            byteCount: 12
        )
        let conversation = AgentConversation(
            title: "Research",
            messages: [
                AgentMessage(role: .user, content: "Question"),
                AgentMessage(role: .assistant, content: "Answer"),
            ],
            attachments: [attachment]
        )
        let archive = ConversationArchive(
            activeConversationID: conversation.id,
            conversations: [conversation]
        )

        try persistence.save(archive)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: persistence.fileURL.path)

        XCTAssertEqual(try persistence.load(), archive)
        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: persistence.fileURL.path)[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(permissions.intValue, 0o600)
    }

    func testAttachmentImportAndReadToolStayInsideConversationFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatDude-AttachmentTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("source.md")
        try Data("# Notes\n\nA durable fact.".utf8).write(to: source)
        let importer = AttachmentImporter(rootDirectory: directory.appendingPathComponent("managed"))
        let attachment = try importer.importFile(at: source, conversationID: UUID())
        let executor = NativeToolExecutor(
            exportDirectory: directory.appendingPathComponent("exports"),
            attachmentRoot: directory.appendingPathComponent("managed")
        )
        let arguments = "{\"attachment_id\":\"\(attachment.id.uuidString)\",\"offset\":0,\"limit\":200}"

        let result = try executor.execute(
            AgentToolCall(id: "read-1", name: "read", argumentsJSON: arguments),
            attachments: [attachment]
        )

        XCTAssertFalse(result.isError)
        XCTAssertTrue(result.content.contains("A durable fact."))
        XCTAssertNotEqual(attachment.storedPath, source.path)
        XCTAssertTrue(attachment.storedPath.contains("managed"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try XCTUnwrap(attachment.extractedTextPath)))
        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: attachment.storedPath)[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(permissions.intValue, 0o600)

        let forged = AgentAttachment(
            displayName: "source.md",
            kind: .markdown,
            storedPath: source.path,
            byteCount: 24
        )
        let forgedArguments = "{\"attachment_id\":\"\(forged.id.uuidString)\"}"
        let rejected = try executor.execute(
            AgentToolCall(id: "read-forged", name: "read", argumentsJSON: forgedArguments),
            attachments: [forged]
        )
        XCTAssertTrue(rejected.isError)
    }

    func testWriteToolRejectsPathsAndWritesOnlyManagedExport() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatDude-WriteTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let executor = NativeToolExecutor(exportDirectory: directory)

        let unsafe = try executor.execute(
            AgentToolCall(id: "write-1", name: "write",
                          argumentsJSON: #"{"name":"../escape.md","content":"bad"}"#),
            attachments: []
        )
        XCTAssertTrue(unsafe.isError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.deletingLastPathComponent().appendingPathComponent("escape.md").path))

        let executable = try executor.execute(
            AgentToolCall(id: "write-script", name: "write",
                          argumentsJSON: #"{"name":"run.sh","content":"echo unsafe"}"#),
            attachments: []
        )
        XCTAssertTrue(executable.isError)

        let safe = try executor.execute(
            AgentToolCall(id: "write-2", name: "write",
                          argumentsJSON: ##"{"name":"answer","content":"# Saved"}"##),
            attachments: []
        )
        XCTAssertFalse(safe.isError)
        XCTAssertEqual(try String(contentsOf: directory.appendingPathComponent("answer.md"), encoding: .utf8), "# Saved")
    }

    func testXLSXExtractorReadsSharedStringsAndNumbers() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatDude-XLSXTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("sample.xlsx")
        let shared = #"<?xml version="1.0"?><sst><si><t>Name</t></si><si><t>FloatDude</t></si></sst>"#
        let sheet = #"<?xml version="1.0"?><worksheet><sheetData><row><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row><row><c r="A2"><v>42</v></c></row></sheetData></worksheet>"#
        try makeStoredZIP([
            "xl/sharedStrings.xml": Data(shared.utf8),
            "xl/worksheets/sheet1.xml": Data(sheet.utf8),
        ]).write(to: url)

        let text = try AttachmentTextExtractor.extract(from: url)

        XCTAssertTrue(text.contains("Name\tFloatDude"))
        XCTAssertTrue(text.contains("42"))
    }

    func testAttachmentWithCredentialIsRejectedAndManagedCopyIsRemoved() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FloatDude-SensitiveAttachment-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let source = directory.appendingPathComponent("secret.md")
        try Data(("token: sk-" + String(repeating: "a", count: 24)).utf8).write(to: source)
        let managed = directory.appendingPathComponent("managed")
        let importer = AttachmentImporter(rootDirectory: managed)

        XCTAssertThrowsError(try importer.importFile(at: source, conversationID: UUID())) { error in
            XCTAssertEqual(error as? AgentEngineError, .sensitiveAttachment)
        }
        let managedFiles = (try? FileManager.default.subpathsOfDirectory(atPath: managed.path)) ?? []
        XCTAssertTrue(managedFiles.allSatisfy { relativePath in
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(
                atPath: managed.appendingPathComponent(relativePath).path,
                isDirectory: &isDirectory
            )
            return isDirectory.boolValue
        })
    }

    func testModelCatalogParserAcceptsOpenAIAndAlternateShapes() throws {
        XCTAssertEqual(
            ModelCatalogClient.modelIDs(from: Data(#"{"data":[{"id":"gpt-a"},{"id":"gpt-b"}]}"#.utf8)),
            ["gpt-a", "gpt-b"]
        )
        XCTAssertEqual(
            ModelCatalogClient.modelIDs(from: Data(#"{"models":[{"name":"model-a"}]}"#.utf8)),
            ["model-a"]
        )
    }

    func testSoftwareRootExposesExactlyReadAndWrite() {
        XCTAssertEqual(NativeAgentTool.allCases, [.read, .write])
        XCTAssertTrue(SoftwareRootPrompt.text.contains("exactly two native tools: read and write"))
        XCTAssertFalse(SoftwareRootPrompt.text.contains("api-key"))
    }

    func testContextPolicyKeepsNewestCompleteTurnsWithinBudget() {
        let messages = [
            AgentMessage(role: .user, content: "old-user"),
            AgentMessage(role: .assistant, content: "old-assistant"),
            AgentMessage(role: .user, content: "new-user"),
            AgentMessage(role: .assistant, content: "new-assistant"),
        ]

        let history = AgentContextPolicy.historyForRequest(messages, maximumCharacters: 24)

        XCTAssertEqual(history.map(\.content), ["new-user", "new-assistant"])
    }

    private func makeStoredZIP(_ entries: [String: Data]) -> Data {
        var result = Data()
        var central = Data()
        for name in entries.keys.sorted() {
            let payload = entries[name]!
            let nameData = Data(name.utf8)
            let offset = UInt32(result.count)
            result.appendLE(UInt32(0x0403_4B50))
            result.appendLE(UInt16(20)); result.appendLE(UInt16(0)); result.appendLE(UInt16(0))
            result.appendLE(UInt16(0)); result.appendLE(UInt16(0)); result.appendLE(UInt32(0))
            result.appendLE(UInt32(payload.count)); result.appendLE(UInt32(payload.count))
            result.appendLE(UInt16(nameData.count)); result.appendLE(UInt16(0))
            result.append(nameData); result.append(payload)

            central.appendLE(UInt32(0x0201_4B50))
            central.appendLE(UInt16(20)); central.appendLE(UInt16(20)); central.appendLE(UInt16(0))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(UInt32(0)); central.appendLE(UInt32(payload.count)); central.appendLE(UInt32(payload.count))
            central.appendLE(UInt16(nameData.count)); central.appendLE(UInt16(0)); central.appendLE(UInt16(0))
            central.appendLE(UInt16(0)); central.appendLE(UInt16(0)); central.appendLE(UInt32(0)); central.appendLE(offset)
            central.append(nameData)
        }
        let centralOffset = UInt32(result.count)
        result.append(central)
        result.appendLE(UInt32(0x0605_4B50))
        result.appendLE(UInt16(0)); result.appendLE(UInt16(0))
        result.appendLE(UInt16(entries.count)); result.appendLE(UInt16(entries.count))
        result.appendLE(UInt32(central.count)); result.appendLE(centralOffset); result.appendLE(UInt16(0))
        return result
    }
}

private extension Data {
    mutating func appendLE<T: FixedWidthInteger>(_ value: T) {
        var littleEndian = value.littleEndian
        Swift.withUnsafeBytes(of: &littleEndian) { append(contentsOf: $0) }
    }
}
