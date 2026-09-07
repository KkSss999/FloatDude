import Carbon.HIToolbox
import XCTest
@testable import FloatDude

final class GlobalHotkeyTests: XCTestCase {
    func testOptionSpaceDescriptorAcceptsCanonicalAndSymbolForms() throws {
        XCTAssertEqual(try GlobalHotkeyDescriptor(parsing: "Option-Space"), .optionSpace)
        XCTAssertEqual(try GlobalHotkeyDescriptor(parsing: "⌥ Space"), .optionSpace)
        XCTAssertEqual(try GlobalHotkeyDescriptor(parsing: "alt+space"), .optionSpace)
        let commandK = try GlobalHotkeyDescriptor(parsing: "Command-K")
        XCTAssertEqual(commandK.displayName, "Command-K")
    }

    func testUnsupportedDescriptorIsActionable() {
        XCTAssertThrowsError(try GlobalHotkeyDescriptor(parsing: "Function-K")) { error in
            XCTAssertEqual(
                error as? GlobalHotkeyDescriptorError,
                .unsupported("Function-K")
            )
        }
    }

    @MainActor
    func testRegisteredApplicationTargetReceivesMatchingHotKeyEvent() async throws {
        var invocationCount = 0
        let testEventID: UInt32 = 999
        let hotkey = CarbonGlobalHotkey(
            descriptor: try GlobalHotkeyDescriptor(parsing: "Command-K"),
            eventID: testEventID
        ) {
            invocationCount += 1
        }
        try hotkey.register()
        defer { hotkey.unregister() }

        var event: EventRef?
        XCTAssertEqual(
            CreateEvent(
                nil,
                OSType(kEventClassKeyboard),
                UInt32(kEventHotKeyPressed),
                GetCurrentEventTime(),
                EventAttributes(kEventAttributeUserEvent),
                &event
            ),
            noErr
        )
        let createdEvent = try XCTUnwrap(event)
        defer { ReleaseEvent(createdEvent) }

        var hotKeyID = EventHotKeyID(
            signature: CarbonGlobalHotkey.eventSignature,
            id: testEventID
        )
        XCTAssertEqual(
            SetEventParameter(
                createdEvent,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                MemoryLayout<EventHotKeyID>.size,
                &hotKeyID
            ),
            noErr
        )
        XCTAssertEqual(SendEventToEventTarget(createdEvent, GetApplicationEventTarget()), noErr)

        for _ in 0..<100 where invocationCount == 0 {
            await Task.yield()
        }
        XCTAssertEqual(invocationCount, 1)
    }
}
