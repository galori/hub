#!/usr/bin/env bats

REPO_DIR="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"

setup() {
    if [[ -n "${SKIP_SWIFT_COMPILE:-}" ]]; then
        skip "SKIP_SWIFT_COMPILE set"
    fi
    if ! command -v swiftc >/dev/null 2>&1; then
        skip "swiftc not available"
    fi
    COMPILE_OUT="$(mktemp -d)"
    export CLANG_MODULE_CACHE_PATH="$COMPILE_OUT/module-cache"
    mkdir -p "$CLANG_MODULE_CACHE_PATH"
    cat > "$COMPILE_OUT/main.swift" <<'SWIFT'
import Foundation

func flags(_ keyCode: UInt16, _ time: UInt64,
           left: Bool = false, right: Bool = false, other: Bool = false) -> HotkeyGestureEvent {
    HotkeyGestureEvent(type: .flagsChanged, keyCode: keyCode,
                       leftShiftDown: left, rightShiftDown: right,
                       otherModifierDown: other, timestamp: time)
}

func key(_ time: UInt64, right: Bool = false) -> HotkeyGestureEvent {
    HotkeyGestureEvent(type: .keyDown, keyCode: 0,
                       leftShiftDown: false, rightShiftDown: right,
                       otherModifierDown: false, timestamp: time)
}

func expect(_ expected: [HotkeyGestureAction], _ actual: [HotkeyGestureAction],
            _ message: String) {
    precondition(expected == actual, "\(message): expected \(expected), got \(actual)")
}

var gestures = HotkeyGestureRecognizer()
expect([], gestures.process(flags(60, 1_000_000_000, right: true)), "first right shift")
expect([], gestures.process(flags(60, 1_100_000_000, right: false)), "right shift release")
expect([.toggleFullscreen], gestures.process(flags(60, 1_399_000_000, right: true)),
       "double tap inside threshold")

gestures.reset()
_ = gestures.process(flags(60, 2_000_000_000, right: true))
_ = gestures.process(flags(60, 2_050_000_000, right: false))
expect([], gestures.process(flags(60, 2_400_000_000, right: true)),
       "double tap at exact threshold")

gestures.reset()
_ = gestures.process(flags(60, 3_000_000_000, right: true))
expect([.toggleFullscreen], gestures.process(flags(60, 3_200_000_000, right: true)),
       "second press after a missed release")

gestures.reset()
expect([], gestures.process(flags(56, 4_000_000_000, left: true)), "left shift alone")
expect([.showClusterOverlay(true)],
       gestures.process(flags(60, 4_100_000_000, left: true, right: true)), "both shifts")
expect([.showClusterOverlay(false)],
       gestures.process(flags(60, 4_200_000_000, left: true, right: false)), "release both shifts")

gestures.reset()
_ = gestures.process(flags(60, 5_000_000_000, right: true))
_ = gestures.process(flags(60, 5_050_000_000, right: false))
expect([], gestures.process(key(5_100_000_000)), "typing cancels a pending tap")
_ = gestures.process(flags(60, 5_200_000_000, right: true))
expect([], gestures.process(flags(60, 5_250_000_000, right: false)), "typing does not toggle")

gestures.reset()
_ = gestures.process(flags(60, 6_000_000_000, right: true))
_ = gestures.process(flags(60, 6_050_000_000, right: false))
expect([], gestures.process(flags(59, 6_100_000_000, other: true)),
       "another modifier cancels a pending tap")

gestures.reset()
_ = gestures.process(flags(60, 6_500_000_000, right: true))
_ = gestures.process(flags(60, 6_550_000_000, right: false))
_ = gestures.process(flags(57, 6_600_000_000))
expect([], gestures.process(flags(60, 6_700_000_000, right: true)),
       "a modifier release cancels a pending tap")

gestures.reset()
_ = gestures.process(flags(60, 7_000_000_000, right: true))
_ = gestures.process(flags(60, 7_050_000_000, right: false))
_ = gestures.reset()
_ = gestures.synchronize(leftShiftDown: false, rightShiftDown: false)
expect([], gestures.process(flags(60, 7_100_000_000, right: true)),
       "tap interruption clears pending history")
SWIFT
    swiftc -O -o "$COMPILE_OUT/hotkey_gestures" \
        "$REPO_DIR/lib/hotkey_gesture.swift" "$COMPILE_OUT/main.swift"
}

teardown() {
    if [[ -n "${COMPILE_OUT:-}" ]]; then rm -rf "$COMPILE_OUT"; fi
}

@test "hotkey gesture recognition handles timing, typing, modifiers, and recovery" {
    run "$COMPILE_OUT/hotkey_gestures"
    [[ "$status" -eq 0 ]]
}
