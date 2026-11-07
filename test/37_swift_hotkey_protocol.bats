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
import Darwin

let identity = HotkeyProcessIdentity(pid: 23, startTime: 123.5, executable: "/tmp/hub_bar")
let original = HotkeyMessage(kind: .heartbeatReply, messageID: "request-1",
                             timestamp: 456.0, senderPID: 23,
                             processIdentity: identity, sessionID: "session-1")
precondition(original.isFresh(at: 456.0, maximumAge: 1))
precondition(!original.isFresh(at: 455.0, maximumAge: 1))
precondition(!original.isFresh(at: 458.0, maximumAge: 1))
guard let encoded = HotkeyDatagram.encode(original),
      let decoded = HotkeyDatagram.decode(encoded),
      decoded.kind == .heartbeatReply,
      decoded.messageID == "request-1",
      decoded.processIdentity == identity,
      decoded.sessionID == "session-1" else {
    fatalError("protocol round trip failed")
}

let heartbeatLatency = HotkeyHeartbeatPolicy.responseLatency(
    sentAt: 10, responseTimestamp: 11.1, receivedAt: 11.1
)
precondition(heartbeatLatency.map { abs($0 - 1.1) < 0.001 } == true)
precondition(HotkeyHeartbeatPolicy.responseLatency(
    sentAt: 10, responseTimestamp: 11, receivedAt: 10.9
) == nil)
precondition(HotkeyHeartbeatPolicy.responseLatency(
    sentAt: 10, responseTimestamp: 16, receivedAt: 16
) == nil)

let socketPath = CommandLine.arguments[1]
precondition(HotkeyPaths.configDirectory == ProcessInfo.processInfo.environment["HUB_CONFIG_DIR"])
precondition(HotkeyPaths.runtimeDirectory == ProcessInfo.processInfo.environment["HUB_RUNTIME_DIR"])
precondition(HotkeyPaths.sessionFile == ProcessInfo.processInfo.environment["HUB_SESSION_FILE"])
precondition(HotkeyPaths.lifecycleLockDirectory == ProcessInfo.processInfo.environment["HUB_LIFECYCLE_LOCK_DIR"])
let received = DispatchSemaphore(value: 0)
let listener = try HotkeyDatagram.listen(at: socketPath, queue: DispatchQueue(label: "test.socket")) {
    message in
    if message.kind == .overlay && message.overlayVisible == true {
        received.signal()
    }
}
listener.start()
do {
    let competingListener = try HotkeyDatagram.listen(
        at: socketPath, queue: DispatchQueue(label: "test.second.socket")
    ) { _ in }
    _ = competingListener
    fatalError("a second listener replaced the active endpoint")
} catch {}
let sent = HotkeyDatagram.send(
    HotkeyMessage(kind: .overlay, overlayVisible: true, sessionID: "session-1"),
    to: socketPath
)
precondition(sent)
precondition(received.wait(timeout: .now() + 2) == .success)
listener.stop()

let blockedQueue = DispatchQueue(label: "test.socket.cancel")
let queueBlocked = DispatchSemaphore(value: 0)
let unblockQueue = DispatchSemaphore(value: 0)
blockedQueue.async {
    queueBlocked.signal()
    _ = unblockQueue.wait(timeout: .now() + 5)
}
precondition(queueBlocked.wait(timeout: .now() + 2) == .success)
var stoppedListener: HotkeyDatagramListener? = try HotkeyDatagram.listen(
    at: socketPath + ".stopped", queue: blockedQueue
) { _ in }
stoppedListener?.start()
stoppedListener?.stop()
stoppedListener = nil
let probeDescriptor = open("/dev/null", O_RDONLY)
precondition(probeDescriptor >= 0)
unblockQueue.signal()
usleep(200_000)
precondition(fcntl(probeDescriptor, F_GETFD) >= 0,
             "socket cancellation closed a descriptor reused after listener deinit")
close(probeDescriptor)
SWIFT
    swiftc -O -o "$COMPILE_OUT/hotkey_protocol" \
        "$REPO_DIR/lib/hotkey_protocol.swift" \
        "$REPO_DIR/lib/hotkey_recovery_policy.swift" \
        "$COMPILE_OUT/main.swift"
}

teardown() {
    if [[ -n "${COMPILE_OUT:-}" ]]; then rm -rf "$COMPILE_OUT"; fi
}

@test "hotkey IPC encodes versioned messages and receives Unix datagrams" {
    run env \
        HUB_CONFIG_DIR="$COMPILE_OUT/config" \
        HUB_RUNTIME_DIR="$COMPILE_OUT/runtime" \
        HUB_SESSION_FILE="$COMPILE_OUT/custom/session" \
        HUB_LIFECYCLE_LOCK_DIR="$COMPILE_OUT/custom/lifecycle.lock" \
        "$COMPILE_OUT/hotkey_protocol" "$COMPILE_OUT/hotkey.sock"
    [[ "$status" -eq 0 ]] || { printf '%s\n' "$output"; return 1; }
}
