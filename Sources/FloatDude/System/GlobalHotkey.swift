import Foundation

protocol GlobalHotkeyManaging: AnyObject {
    func register() throws
    func unregister()
}
