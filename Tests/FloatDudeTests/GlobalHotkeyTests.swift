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
}
