import CoreGraphics

protocol WindowPositioning: Sendable {
    func origin(forPanelSize size: CGSize) -> CGPoint
}
