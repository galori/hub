import Foundation

enum HotkeyGestureAction: Equatable {
    case showClusterOverlay(Bool)
    case toggleFullscreen
}

enum HotkeyGestureEventType {
    case flagsChanged
    case keyDown
}

struct HotkeyGestureEvent {
    let type: HotkeyGestureEventType
    let keyCode: UInt16
    let leftShiftDown: Bool
    let rightShiftDown: Bool
    let otherModifierDown: Bool
    let timestamp: UInt64
}

struct HotkeyGestureRecognizer {
    private let rightShiftKeyCode: UInt16 = 60
    private let doubleTapInterval: UInt64 = 400_000_000
    private var firstRightShiftTap: UInt64?
    private var clusterOverlayVisible = false

    mutating func process(_ event: HotkeyGestureEvent) -> [HotkeyGestureAction] {
        if event.type == .keyDown {
            firstRightShiftTap = nil
            return []
        }

        var actions: [HotkeyGestureAction] = []
        let bothShiftsDown = event.leftShiftDown && event.rightShiftDown
        if bothShiftsDown != clusterOverlayVisible {
            clusterOverlayVisible = bothShiftsDown
            actions.append(.showClusterOverlay(bothShiftsDown))
        }

        if event.otherModifierDown || event.leftShiftDown {
            firstRightShiftTap = nil
            return actions
        }

        guard event.keyCode == rightShiftKeyCode else {
            firstRightShiftTap = nil
            return actions
        }

        guard event.rightShiftDown else {
            return actions
        }

        if let firstTap = firstRightShiftTap,
           event.timestamp >= firstTap,
           event.timestamp - firstTap < doubleTapInterval {
            firstRightShiftTap = nil
            actions.append(.toggleFullscreen)
        } else {
            firstRightShiftTap = event.timestamp
        }
        return actions
    }

    mutating func reset() -> [HotkeyGestureAction] {
        firstRightShiftTap = nil
        guard clusterOverlayVisible else { return [] }
        clusterOverlayVisible = false
        return [.showClusterOverlay(false)]
    }

    mutating func synchronize(leftShiftDown: Bool, rightShiftDown: Bool) -> [HotkeyGestureAction] {
        firstRightShiftTap = nil
        clusterOverlayVisible = leftShiftDown && rightShiftDown
        return [.showClusterOverlay(clusterOverlayVisible)]
    }
}
