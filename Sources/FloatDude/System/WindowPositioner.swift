import AppKit
import CoreGraphics

@MainActor
protocol WindowPositioning: Sendable {
    func origin(forPanelSize size: CGSize) -> CGPoint
    func origin(forPanelSize size: CGSize, avoiding rect: CGRect?) -> CGPoint
    func fittedPanelSize(for size: CGSize) -> CGSize
}

extension WindowPositioning {
    func origin(forPanelSize size: CGSize, avoiding _: CGRect?) -> CGPoint {
        origin(forPanelSize: size)
    }

    func fittedPanelSize(for size: CGSize) -> CGSize {
        size
    }
}

struct DisplayGeometry: Sendable, Equatable {
    let frame: CGRect
    let visibleFrame: CGRect

    init(frame: CGRect, visibleFrame: CGRect) {
        self.frame = frame
        self.visibleFrame = visibleFrame
    }
}

/// Pure geometry used by `WindowPositioner` and deterministic unit tests.
struct WindowPlacementCalculator: Sendable {
    static let defaultEdgeInset: CGFloat = 12
    static let defaultCursorGap: CGFloat = 14
    static let defaultCursorAvoidance: CGFloat = 24

    static func fittedPanelSize(
        _ panelSize: CGSize,
        in visibleFrame: CGRect,
        edgeInset: CGFloat = defaultEdgeInset
    ) -> CGSize {
        let safeFrame = visibleFrame.insetBy(dx: edgeInset, dy: edgeInset)
        return CGSize(
            width: max(1, min(panelSize.width, max(1, safeFrame.width))),
            height: max(1, min(panelSize.height, max(1, safeFrame.height)))
        )
    }

    static func origin(
        forPanelSize panelSize: CGSize,
        cursorLocation: CGPoint,
        displays: [DisplayGeometry],
        avoiding selectionRect: CGRect? = nil,
        edgeInset: CGFloat = defaultEdgeInset,
        cursorGap: CGFloat = defaultCursorGap,
        cursorAvoidance: CGFloat = defaultCursorAvoidance
    ) -> CGPoint {
        let display = activeDisplay(for: cursorLocation, in: displays)
        return origin(
            forPanelSize: panelSize,
            cursorLocation: cursorLocation,
            visibleFrame: display.visibleFrame,
            avoiding: selectionRect,
            edgeInset: edgeInset,
            cursorGap: cursorGap,
            cursorAvoidance: cursorAvoidance
        )
    }

    static func activeDisplay(
        for cursorLocation: CGPoint,
        in displays: [DisplayGeometry]
    ) -> DisplayGeometry {
        displays.first(where: { $0.frame.contains(cursorLocation) })
            ?? displays.first
            ?? DisplayGeometry(
                frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                visibleFrame: CGRect(x: 0, y: 0, width: 1440, height: 900)
            )
    }

    static func origin(
        forPanelSize panelSize: CGSize,
        cursorLocation: CGPoint,
        visibleFrame: CGRect,
        avoiding selectionRect: CGRect? = nil,
        edgeInset: CGFloat = defaultEdgeInset,
        cursorGap: CGFloat = defaultCursorGap,
        cursorAvoidance: CGFloat = defaultCursorAvoidance
    ) -> CGPoint {
        let safeFrame = visibleFrame.insetBy(dx: edgeInset, dy: edgeInset)
        let fittedSize = fittedPanelSize(panelSize, in: visibleFrame, edgeInset: edgeInset)
        let cursorRect = CGRect(
            x: cursorLocation.x - cursorAvoidance / 2,
            y: cursorLocation.y - cursorAvoidance / 2,
            width: cursorAvoidance,
            height: cursorAvoidance
        )
        let forbiddenRect = selectionRect.map { $0.union(cursorRect) } ?? cursorRect
        let desiredOrigin = CGPoint(
            x: cursorLocation.x + cursorGap,
            y: cursorLocation.y - fittedSize.height - cursorGap
        )

        let candidateOrigins = [
            desiredOrigin,
            CGPoint(
                x: cursorLocation.x - fittedSize.width - cursorGap,
                y: cursorLocation.y - fittedSize.height - cursorGap
            ),
            CGPoint(x: cursorLocation.x + cursorGap, y: cursorLocation.y + cursorGap),
            CGPoint(
                x: cursorLocation.x - fittedSize.width - cursorGap,
                y: cursorLocation.y + cursorGap
            ),
            CGPoint(
                x: forbiddenRect.maxX + cursorGap,
                y: forbiddenRect.midY - fittedSize.height / 2
            ),
            CGPoint(
                x: forbiddenRect.minX - fittedSize.width - cursorGap,
                y: forbiddenRect.midY - fittedSize.height / 2
            ),
            CGPoint(x: forbiddenRect.midX - fittedSize.width / 2, y: forbiddenRect.maxY + cursorGap),
            CGPoint(
                x: forbiddenRect.midX - fittedSize.width / 2,
                y: forbiddenRect.minY - fittedSize.height - cursorGap
            )
        ].map { clamp($0, panelSize: fittedSize, to: safeFrame) }

        return candidateOrigins.min { lhs, rhs in
            score(origin: lhs, panelSize: fittedSize, forbidden: forbiddenRect, desired: desiredOrigin)
                < score(origin: rhs, panelSize: fittedSize, forbidden: forbiddenRect, desired: desiredOrigin)
        } ?? clamp(desiredOrigin, panelSize: fittedSize, to: safeFrame)
    }

    private static func clamp(
        _ origin: CGPoint,
        panelSize: CGSize,
        to frame: CGRect
    ) -> CGPoint {
        CGPoint(
            x: min(max(origin.x, frame.minX), max(frame.minX, frame.maxX - panelSize.width)),
            y: min(max(origin.y, frame.minY), max(frame.minY, frame.maxY - panelSize.height))
        )
    }

    private static func score(
        origin: CGPoint,
        panelSize: CGSize,
        forbidden: CGRect,
        desired: CGPoint
    ) -> CGFloat {
        let panelRect = CGRect(origin: origin, size: panelSize)
        let overlap = panelRect.intersection(forbidden)
        let overlapArea = overlap.isNull ? 0 : overlap.width * overlap.height
        let distance = hypot(origin.x - desired.x, origin.y - desired.y)
        return overlapArea * 1_000_000 + distance
    }
}

/// Resolves the current mouse location against the active display and its
/// visible frame. All AppKit access stays on the main actor.
@MainActor
struct WindowPositioner: WindowPositioning {
    let edgeInset: CGFloat
    let cursorGap: CGFloat
    let cursorAvoidance: CGFloat

    nonisolated init(
        edgeInset: CGFloat = 12,
        cursorGap: CGFloat = 14,
        cursorAvoidance: CGFloat = 24
    ) {
        self.edgeInset = edgeInset
        self.cursorGap = cursorGap
        self.cursorAvoidance = cursorAvoidance
    }

    func origin(forPanelSize size: CGSize) -> CGPoint {
        origin(forPanelSize: size, avoiding: nil)
    }

    func origin(forPanelSize size: CGSize, avoiding rect: CGRect?) -> CGPoint {
        WindowPlacementCalculator.origin(
            forPanelSize: size,
            cursorLocation: NSEvent.mouseLocation,
            displays: displayGeometries,
            avoiding: rect,
            edgeInset: edgeInset,
            cursorGap: cursorGap,
            cursorAvoidance: cursorAvoidance
        )
    }

    func fittedPanelSize(for size: CGSize) -> CGSize {
        let display = WindowPlacementCalculator.activeDisplay(
            for: NSEvent.mouseLocation,
            in: displayGeometries
        )
        return WindowPlacementCalculator.fittedPanelSize(size, in: display.visibleFrame, edgeInset: edgeInset)
    }

    private var displayGeometries: [DisplayGeometry] {
        NSScreen.screens.map {
            DisplayGeometry(frame: $0.frame, visibleFrame: $0.visibleFrame)
        }
    }
}
