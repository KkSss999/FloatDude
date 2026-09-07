import Foundation
import XCTest
@testable import FloatDude

final class SSEParserTests: XCTestCase {
    func testHandlesFragmentedUTF8AndMultipleDataLines() throws {
        let payload = "data: 你\ndata: 好\r\n\r\n"
        let bytes = Array(payload.utf8)
        let splitInsideCharacter = bytes.firstIndex(of: 0xE4)! + 1
        var parser = SSEParser()

        var events = try parser.append(Data(bytes[..<splitInsideCharacter]))
        XCTAssertTrue(events.isEmpty)
        events += try parser.append(Data(bytes[splitInsideCharacter..<bytes.count]))

        XCTAssertEqual(events, [SSEEvent(data: "你\n好")])
    }

    func testEmitsEventsAcrossChunksAndFlushesDoneAtEnd() throws {
        var parser = SSEParser()
        XCTAssertEqual(try parser.append(Data("data: first\n\n".utf8)), [SSEEvent(data: "first")])
        XCTAssertEqual(try parser.append(Data("data: [DO".utf8)), [])
        XCTAssertEqual(try parser.append(Data("NE]\n\n".utf8)), [SSEEvent(data: "[DONE]")])
    }

    func testRejectsInvalidUTF8OnlyAfterACompleteLineOrFinish() {
        var parser = SSEParser()
        XCTAssertThrowsError(try parser.append(Data([0xFF, 0x0A]))) { error in
            XCTAssertEqual(error as? SSEParserError, .invalidUTF8)
        }
    }

    func testPreservesEventFieldForAnthropicMessagesStreams() throws {
        var parser = SSEParser()

        let events = try parser.append(Data(
            "event: content_block_delta\ndata: {\"type\":\"content_block_delta\"}\n\n".utf8
        ))

        XCTAssertEqual(events, [
            SSEEvent(data: "{\"type\":\"content_block_delta\"}", event: "content_block_delta")
        ])
    }
}
