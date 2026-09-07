import Carbon.HIToolbox
import Foundation

/// The keyboard descriptor used by the system hot-key registrar.
struct GlobalHotkeyDescriptor: Sendable, Equatable, Codable {
    let keyCode: UInt32
    let modifiers: UInt32
    let displayName: String

    init(keyCode: UInt32, modifiers: UInt32, displayName: String = "Option-Space") {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.displayName = displayName
    }

    /// Option-Space, the default shortcut for FloatDude.
    static let optionSpace = Self(
        keyCode: UInt32(kVK_Space),
        modifiers: UInt32(optionKey),
        displayName: "Option-Space"
    )

    init(parsing value: String) throws {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "_", with: "-")
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "⌥", with: "option-")

        let tokens = normalized.split(separator: "-").map(String.init)
        guard let key = tokens.last, !tokens.dropLast().isEmpty else {
            throw GlobalHotkeyDescriptorError.unsupported(value)
        }

        var modifiers: UInt32 = 0
        var modifierNames: [String] = []
        for token in tokens.dropLast() {
            switch token {
            case "option", "alt":
                modifiers |= UInt32(optionKey)
                modifierNames.append("Option")
            case "command", "cmd", "⌘":
                modifiers |= UInt32(cmdKey)
                modifierNames.append("Command")
            case "control", "ctrl", "⌃":
                modifiers |= UInt32(controlKey)
                modifierNames.append("Control")
            case "shift", "⇧":
                modifiers |= UInt32(shiftKey)
                modifierNames.append("Shift")
            default:
                throw GlobalHotkeyDescriptorError.unsupported(value)
            }
        }

        guard modifiers != 0, let keyCode = Self.keyCode(for: key) else {
            throw GlobalHotkeyDescriptorError.unsupported(value)
        }

        let displayKey = Self.displayKey(for: key)
        self.init(
            keyCode: keyCode,
            modifiers: modifiers,
            displayName: (modifierNames + [displayKey]).joined(separator: "-")
        )
    }

    private static func keyCode(for key: String) -> UInt32? {
        switch key {
        case "space": return UInt32(kVK_Space)
        case "return", "enter": return UInt32(kVK_Return)
        case "tab": return UInt32(kVK_Tab)
        case "escape", "esc": return UInt32(kVK_Escape)
        case "delete", "backspace": return UInt32(kVK_Delete)
        case "left": return UInt32(kVK_LeftArrow)
        case "right": return UInt32(kVK_RightArrow)
        case "up": return UInt32(kVK_UpArrow)
        case "down": return UInt32(kVK_DownArrow)
        default:
            guard key.count == 1, let scalar = key.unicodeScalars.first else { return nil }
            switch scalar {
            case "a": return UInt32(kVK_ANSI_A)
            case "b": return UInt32(kVK_ANSI_B)
            case "c": return UInt32(kVK_ANSI_C)
            case "d": return UInt32(kVK_ANSI_D)
            case "e": return UInt32(kVK_ANSI_E)
            case "f": return UInt32(kVK_ANSI_F)
            case "g": return UInt32(kVK_ANSI_G)
            case "h": return UInt32(kVK_ANSI_H)
            case "i": return UInt32(kVK_ANSI_I)
            case "j": return UInt32(kVK_ANSI_J)
            case "k": return UInt32(kVK_ANSI_K)
            case "l": return UInt32(kVK_ANSI_L)
            case "m": return UInt32(kVK_ANSI_M)
            case "n": return UInt32(kVK_ANSI_N)
            case "o": return UInt32(kVK_ANSI_O)
            case "p": return UInt32(kVK_ANSI_P)
            case "q": return UInt32(kVK_ANSI_Q)
            case "r": return UInt32(kVK_ANSI_R)
            case "s": return UInt32(kVK_ANSI_S)
            case "t": return UInt32(kVK_ANSI_T)
            case "u": return UInt32(kVK_ANSI_U)
            case "v": return UInt32(kVK_ANSI_V)
            case "w": return UInt32(kVK_ANSI_W)
            case "x": return UInt32(kVK_ANSI_X)
            case "y": return UInt32(kVK_ANSI_Y)
            case "z": return UInt32(kVK_ANSI_Z)
            case "0": return UInt32(kVK_ANSI_0)
            case "1": return UInt32(kVK_ANSI_1)
            case "2": return UInt32(kVK_ANSI_2)
            case "3": return UInt32(kVK_ANSI_3)
            case "4": return UInt32(kVK_ANSI_4)
            case "5": return UInt32(kVK_ANSI_5)
            case "6": return UInt32(kVK_ANSI_6)
            case "7": return UInt32(kVK_ANSI_7)
            case "8": return UInt32(kVK_ANSI_8)
            case "9": return UInt32(kVK_ANSI_9)
            default: return nil
            }
        }
    }

    private static func displayKey(for key: String) -> String {
        switch key {
        case "space": return "Space"
        case "return", "enter": return "Return"
        case "tab": return "Tab"
        case "escape", "esc": return "Escape"
        case "delete", "backspace": return "Delete"
        case "left": return "Left"
        case "right": return "Right"
        case "up": return "Up"
        case "down": return "Down"
        default: return key.uppercased()
        }
    }
}

enum GlobalHotkeyDescriptorError: LocalizedError, Sendable, Equatable {
    case unsupported(String)

    var errorDescription: String? {
        switch self {
        case let .unsupported(value):
            "Unsupported shortcut \(value). Use Option-Space in v0.1."
        }
    }
}

enum GlobalHotkeyError: Error, LocalizedError, Sendable, Equatable {
    case handlerInstallationFailed(OSStatus)
    case registrationFailed(OSStatus)
    case unregistrationFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .handlerInstallationFailed(status):
            "Could not install the global hot-key handler (OSStatus \(status))."
        case let .registrationFailed(status):
            "Could not register the global hot-key (OSStatus \(status))."
        case let .unregistrationFailed(status):
            "Could not unregister the global hot-key (OSStatus \(status))."
        }
    }
}

@MainActor
protocol GlobalHotkeyManaging: AnyObject {
    func register() throws
    /// Kept non-throwing for compatibility with the original protocol.
    func unregister()
}

@MainActor
protocol ConfigurableGlobalHotkeyManaging: GlobalHotkeyManaging {
    var descriptor: GlobalHotkeyDescriptor { get }
    func update(descriptor: GlobalHotkeyDescriptor) throws
}

/// An opt-in evolution of `GlobalHotkeyManaging` for callers that need to
/// surface a recoverable unregister failure.
@MainActor
protocol RecoverableGlobalHotkeyManaging: GlobalHotkeyManaging {
    func unregisterReportingError() throws
}

@MainActor
final class CarbonGlobalHotkey: RecoverableGlobalHotkeyManaging, ConfigurableGlobalHotkeyManaging {
    typealias Handler = @MainActor @Sendable () -> Void

    nonisolated static let eventSignature: OSType = 0x4644_484B // "FDHK"
    nonisolated static let defaultEventID: UInt32 = 1

    private(set) var descriptor: GlobalHotkeyDescriptor

    private let handler: Handler
    private let hotKeyID: EventHotKeyID
    private var hotKey: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var handlerBox: HandlerBox?

    init(
        descriptor: GlobalHotkeyDescriptor = .optionSpace,
        eventID: UInt32 = CarbonGlobalHotkey.defaultEventID,
        handler: @escaping Handler
    ) {
        self.descriptor = descriptor
        self.hotKeyID = EventHotKeyID(signature: Self.eventSignature, id: eventID)
        self.handler = handler
    }

    var isRegistered: Bool {
        hotKey != nil && eventHandler != nil
    }

    func register() throws {
        try register(descriptor: descriptor)
    }

    func update(descriptor: GlobalHotkeyDescriptor) throws {
        try register(descriptor: descriptor)
    }

    private func register(descriptor newDescriptor: GlobalHotkeyDescriptor) throws {
        if isRegistered {
            guard newDescriptor != descriptor else { return }
            let previousDescriptor = descriptor
            try unregisterReportingError()
            do {
                try register(descriptor: newDescriptor)
            } catch {
                try? register(descriptor: previousDescriptor)
                throw error
            }
            return
        }

        // A failed unregister can leave one native resource alive. Retry that
        // cleanup before installing anything new so registration never stacks
        // handlers or physical hot-key registrations.
        if hotKey != nil || eventHandler != nil {
            try unregisterReportingError()
        }

        let box = HandlerBox(handler: handler, hotKeyID: hotKeyID)
        var eventTypes = [EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )]
        var installedHandler: EventHandlerRef?
        let applicationTarget = GetApplicationEventTarget()
        let installStatus = InstallEventHandler(
            applicationTarget,
            carbonHotkeyEventHandler,
            eventTypes.count,
            &eventTypes,
            Unmanaged.passUnretained(box).toOpaque(),
            &installedHandler
        )
        guard installStatus == noErr else {
            throw GlobalHotkeyError.handlerInstallationFailed(installStatus)
        }

        var registeredHotKey: EventHotKeyRef?
        let registerStatus = RegisterEventHotKey(
            newDescriptor.keyCode,
            newDescriptor.modifiers,
            hotKeyID,
            applicationTarget,
            0,
            &registeredHotKey
        )
        guard registerStatus == noErr, let registeredHotKey else {
            RemoveEventHandler(installedHandler)
            throw GlobalHotkeyError.registrationFailed(registerStatus)
        }

        handlerBox = box
        eventHandler = installedHandler
        hotKey = registeredHotKey
        descriptor = newDescriptor
    }

    func unregister() {
        try? unregisterReportingError()
    }

    func unregisterReportingError() throws {
        var firstError: GlobalHotkeyError?

        if let hotKey {
            let status = UnregisterEventHotKey(hotKey)
            if status == noErr {
                self.hotKey = nil
            } else if firstError == nil {
                firstError = .unregistrationFailed(status)
            }
        }

        if let eventHandler {
            let status = RemoveEventHandler(eventHandler)
            if status == noErr {
                self.eventHandler = nil
                handlerBox = nil
            } else if firstError == nil {
                firstError = .unregistrationFailed(status)
            }
        }

        if let firstError {
            throw firstError
        }
    }

}

private final class HandlerBox: @unchecked Sendable {
    let handler: CarbonGlobalHotkey.Handler
    let hotKeyID: EventHotKeyID

    init(handler: @escaping CarbonGlobalHotkey.Handler, hotKeyID: EventHotKeyID) {
        self.handler = handler
        self.hotKeyID = hotKeyID
    }

    func invoke() {
        Task { @MainActor [handler] in
            handler()
        }
    }
}

private func carbonHotkeyEventHandler(
    _: EventHandlerCallRef?,
    event: EventRef?,
    userData: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hotKeyID
    )
    let box = Unmanaged<HandlerBox>.fromOpaque(userData).takeUnretainedValue()
    guard status == noErr,
          hotKeyID.signature == box.hotKeyID.signature,
          hotKeyID.id == box.hotKeyID.id
    else {
        return OSStatus(eventNotHandledErr)
    }
    box.invoke()
    return noErr
}
