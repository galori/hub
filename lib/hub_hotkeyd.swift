import AppKit
import CoreGraphics
import Darwin
import Foundation

private struct HotkeyRecoveryEvent: Codable {
    let timestamp: TimeInterval
    let pid: Int32?
    let result: String
    let reason: String
}

private enum HotkeyBarTerminationResult {
    case terminated
    case targetChanged
    case stillRunning
}

private struct HotkeyRestartBudgetRecord: Codable {
    let sessionID: String
    var budget: HotkeyRestartBudget
    var recoveryHistory: [HotkeyRecoveryEvent] = []
}

private struct HotkeyDaemonStatus: Codable {
    var updatedAt = Date().timeIntervalSince1970
    var helperPID = ProcessInfo.processInfo.processIdentifier
    var helperStartTime: TimeInterval?
    var sessionID: String?
    var inputMonitoringPermission = "unknown"
    var tapHealth = "starting"
    var tapLastError: String?
    var listenerHeartbeatAt = Date().timeIntervalSince1970
    var listenerHeartbeatAge: TimeInterval = 0
    var barHeartbeatAt: TimeInterval?
    var barHeartbeatAge: TimeInterval?
    var barHeartbeatResponseLatency: TimeInterval?
    var slowBarHeartbeatCount = 0
    var lastSlowBarHeartbeatAt: TimeInterval?
    var barPID: Int32?
    var barStartTime: TimeInterval?
    var clusterOverlayVisible = false
    var fullscreenActionFailureCount = 0
    var droppedFullscreenActionCount = 0
    var lastFullscreenActionError: String?
    var overlaySendFailureCount = 0
    var recoveryState = "idle"
    var recoveryHistory: [HotkeyRecoveryEvent] = []
    var lastRecoverySample: String?
    var lastRecoveryError: String?
}

private final class HubHotkeyDaemon {
    private let controlQueue = DispatchQueue(label: "sh.hub.hotkeyd.control")
    private let recoveryQueue = DispatchQueue(label: "sh.hub.hotkeyd.recovery", qos: .utility)
    private let fullscreenQueue = DispatchQueue(label: "sh.hub.hotkeyd.fullscreen", qos: .userInitiated)
    private let overlayQueue = DispatchQueue(label: "sh.hub.hotkeyd.overlay")
    private let fullscreenGate = DispatchSemaphore(value: 1)
    private let statusLock = NSLock()
    private let eventLoopLock = NSLock()
    private let stoppingLock = NSLock()

    private var status = HotkeyDaemonStatus()
    private var listener: HotkeyDatagramListener?
    private var healthTimer: DispatchSourceTimer?
    private var terminationSignal: DispatchSourceSignal?
    private var listenerThread: Thread?
    private var listenerRunLoop: CFRunLoop?
    private var eventTap: CFMachPort?
    private var eventTapSource: CFRunLoopSource?
    private var gestureRecognizer = HotkeyGestureRecognizer()
    private var tapRetryDelay: TimeInterval = 1
    private var nextTapRetryAt = Date.distantPast
    private var listenerGraceUntil = Date().addingTimeInterval(15)
    private var barGraceUntil = Date().addingTimeInterval(15)
    private var barExpectedSince = Date()
    private var lastBarHeartbeatAt: Date?
    private var lastBarIdentity: HotkeyProcessIdentity?
    private var pendingHeartbeatRequests: [String: Date] = [:]
    private var recoveryInProgress = false
    private var pendingOverlayState: (visible: Bool, immediate: Bool, recognizedAt: Date)?
    private var overlayFlush: DispatchWorkItem?
    private var stopping = false

    func start() {
        prepareRuntimeDirectory()
        let sessionID = activeSessionID()
        let helperIdentity = HotkeyProcessIdentity.current()
        let recoveryHistory = sessionID.flatMap {
            readRestartBudgetRecord(for: $0)?.recoveryHistory
        } ?? []
        mutateStatus {
            $0.helperPID = ProcessInfo.processInfo.processIdentifier
            $0.helperStartTime = helperIdentity?.startTime
            $0.sessionID = sessionID
            $0.recoveryHistory = recoveryHistory
        }
        installControlSocket()
        installWorkspaceNotifications()
        installTerminationSignal()
        startListenerThread()
        startHealthTimer()
        publishStatus()
        log("listener started")
    }

    private func prepareRuntimeDirectory() {
        try? FileManager.default.createDirectory(
            atPath: HotkeyPaths.runtimeDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        _ = chmod(HotkeyPaths.runtimeDirectory, mode_t(S_IRWXU))
    }

    private func installControlSocket() {
        do {
            listener = try HotkeyDatagram.listen(
                at: HotkeyPaths.hotkeysSocket,
                queue: controlQueue
            ) { [weak self] message in
                self?.handleControlMessage(message)
            }
            listener?.start()
        } catch {
            log("control socket unavailable: \(error.localizedDescription)")
            exit(70)
        }
    }

    private func installWorkspaceNotifications() {
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) {
            [weak self] _ in
            self?.controlQueue.async { self?.beginGracePeriod(reason: "sleep") }
        }
        center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) {
            [weak self] _ in
            self?.controlQueue.async { self?.beginGracePeriod(reason: "wake") }
        }
        center.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.controlQueue.async { self?.beginGracePeriod(reason: "session active") }
        }
        center.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                           object: nil, queue: .main) { [weak self] _ in
            self?.controlQueue.async { self?.resetGestureState() }
        }
    }

    private func installTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: controlQueue)
        source.setEventHandler { [weak self] in
            self?.shutdown()
        }
        source.resume()
        terminationSignal = source
    }

    private func startListenerThread() {
        let thread = Thread { [weak self] in
            self?.runEventLoop()
        }
        thread.name = "sh.hub.hotkeyd.event-tap"
        listenerThread = thread
        thread.start()
    }

    private func startHealthTimer() {
        let timer = DispatchSource.makeTimerSource(queue: controlQueue)
        timer.schedule(deadline: .now(), repeating: 1, leeway: .milliseconds(100))
        timer.setEventHandler { [weak self] in
            self?.heartbeatBar()
            self?.checkBarHealth()
            self?.checkListenerHealth()
            self?.publishStatus()
        }
        timer.resume()
        healthTimer = timer
    }

    private func handleControlMessage(_ message: HotkeyMessage) {
        guard message.isFresh(maximumAge: 5) else { return }
        switch message.kind {
        case .heartbeatReply:
            receiveBarHeartbeat(message)
        case .barRestarting:
            beginGracePeriod(reason: "manual bar restart")
        case .requestAccess:
            requestInputMonitoringAccess()
        case .overlay:
            guard message.isFresh(maximumAge: 1),
                  let sessionID = activeSessionID(),
                  message.sessionID == sessionID,
                  let visible = message.overlayVisible else {
                return
            }
            enqueueOverlayState(visible,
                               immediate: message.overlayImmediate ?? false,
                               recognizedAt: Date(timeIntervalSince1970: message.timestamp))
        case .heartbeatRequest:
            break
        }
    }

    private func requestInputMonitoringAccess() {
        DispatchQueue.main.async { [weak self] in
            _ = CGRequestListenEventAccess()
            let granted = CGPreflightListenEventAccess()
            self?.controlQueue.async {
                self?.mutateStatus {
                    $0.inputMonitoringPermission = granted ? "granted" : "notGranted"
                }
                self?.requestTapRecreation()
            }
        }
    }

    private func runEventLoop() {
        autoreleasepool {
            let runLoop = CFRunLoopGetCurrent()
            eventLoopLock.lock()
            listenerRunLoop = runLoop
            eventLoopLock.unlock()

            while !isStopping() {
                _ = CFRunLoopRunInMode(CFRunLoopMode.defaultMode, 0.5, false)
                let now = Date()
                mutateStatus { $0.listenerHeartbeatAt = now.timeIntervalSince1970 }
                checkTapHealth(at: now)
            }

            destroyEventTap()
        }
    }

    private func checkTapHealth(at now: Date) {
        if let tap = eventTap {
            if !CFMachPortIsValid(tap) {
                destroyEventTap()
                mutateStatus {
                    $0.tapHealth = "recreating"
                    $0.tapLastError = "event tap became invalid"
                }
                scheduleTapRetry(at: now)
            } else if !CGEvent.tapIsEnabled(tap: tap) {
                CGEvent.tapEnable(tap: tap, enable: true)
                resetGestureAndSynchronize()
                mutateStatus { $0.tapHealth = "reenabling" }
            } else if statusSnapshot().tapHealth != "healthy" {
                mutateStatus {
                    $0.tapHealth = "healthy"
                    $0.tapLastError = nil
                }
            }
        } else if now >= nextTapRetryAt {
            createEventTap()
        }
    }

    private func createEventTap() {
        let accessGranted = CGPreflightListenEventAccess()
        mutateStatus {
            $0.inputMonitoringPermission = accessGranted ? "granted" : "notGranted"
        }
        guard accessGranted else {
            mutateStatus {
                $0.tapHealth = "permissionRequired"
                $0.tapLastError = "Enable Hub Hotkeys.app in System Settings > "
                    + "Privacy & Security > Input Monitoring"
            }
            scheduleTapRetry(at: Date())
            return
        }

        let flagsChangedMask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let keyDownMask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: flagsChangedMask | keyDownMask,
            callback: { _, type, event, userInfo in
                guard let userInfo else { return Unmanaged.passUnretained(event) }
                let daemon = Unmanaged<HubHotkeyDaemon>.fromOpaque(userInfo).takeUnretainedValue()
                return daemon.receiveTapEvent(type: type, event: event)
            },
            userInfo: userInfo
        ) else {
            mutateStatus {
                $0.tapHealth = "unavailable"
                $0.tapLastError = "CGEvent.tapCreate returned no event tap"
            }
            scheduleTapRetry(at: Date())
            return
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        eventTap = tap
        eventTapSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        tapRetryDelay = 1
        nextTapRetryAt = .distantFuture
        mutateStatus {
            $0.tapHealth = "healthy"
            $0.tapLastError = nil
        }
        resetGestureAndSynchronize()
    }

    private func scheduleTapRetry(at now: Date) {
        nextTapRetryAt = now.addingTimeInterval(tapRetryDelay)
        tapRetryDelay = min(tapRetryDelay * 2, 30)
    }

    private func destroyEventTap() {
        if let source = eventTapSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            eventTapSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
            eventTap = nil
        }
        resetGestureAndSynchronize()
    }

    private func receiveTapEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            resetGestureAndSynchronize()
            mutateStatus { $0.tapHealth = "reenabling" }
            return Unmanaged.passUnretained(event)
        }

        guard type == .flagsChanged || type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let rawFlags = UInt64(event.flags.rawValue)
        let keyCode = UInt16(truncatingIfNeeded: event.getIntegerValueField(.keyboardEventKeycode))
        let otherModifierDown = !event.flags.intersection([
            .maskControl, .maskAlternate, .maskCommand, .maskAlphaShift, .maskSecondaryFn
        ]).isEmpty
        let gestureEvent = HotkeyGestureEvent(
            type: type == .keyDown ? .keyDown : .flagsChanged,
            keyCode: keyCode,
            leftShiftDown: rawFlags & 0x0002 != 0,
            rightShiftDown: rawFlags & 0x0004 != 0,
            otherModifierDown: otherModifierDown,
            timestamp: event.timestamp
        )
        enqueueGestureActions(gestureRecognizer.process(gestureEvent))
        return Unmanaged.passUnretained(event)
    }

    private func resetGestureState() {
        performOnEventLoop { [weak self] in
            guard let self else { return }
            self.enqueueGestureActions(self.gestureRecognizer.reset())
        }
    }

    private func resetGestureAndSynchronize() {
        enqueueGestureActions(gestureRecognizer.reset())
        let leftShiftDown = CGEventSource.keyState(.combinedSessionState, key: 56)
        let rightShiftDown = CGEventSource.keyState(.combinedSessionState, key: 60)
        enqueueGestureActions(
            gestureRecognizer.synchronize(leftShiftDown: leftShiftDown,
                                          rightShiftDown: rightShiftDown)
        )
    }

    private func performOnEventLoop(_ work: @escaping () -> Void) {
        eventLoopLock.lock()
        let runLoop = listenerRunLoop
        eventLoopLock.unlock()
        guard let runLoop else { return }
        CFRunLoopPerformBlock(runLoop, CFRunLoopMode.defaultMode.rawValue, work)
        CFRunLoopWakeUp(runLoop)
    }

    private func enqueueGestureActions(_ actions: [HotkeyGestureAction]) {
        for action in actions {
            switch action {
            case .showClusterOverlay(let visible):
                enqueueOverlayState(visible)
            case .toggleFullscreen:
                enqueueFullscreenAction(recognizedAt: Date())
            }
        }
    }

    private func enqueueOverlayState(_ visible: Bool,
                                     immediate: Bool = false,
                                     recognizedAt: Date = Date()) {
        mutateStatus { $0.clusterOverlayVisible = visible }
        overlayQueue.async { [weak self] in
            guard let self else { return }
            self.pendingOverlayState = (visible, immediate, recognizedAt)
            guard self.overlayFlush == nil else { return }
            let flush = DispatchWorkItem { [weak self] in
                guard let self else { return }
                let pending = self.pendingOverlayState
                self.pendingOverlayState = nil
                self.overlayFlush = nil
                if let pending {
                    let age = Date().timeIntervalSince(pending.recognizedAt)
                    if age >= 0 && age <= 1 {
                        self.sendOverlayState(pending.visible, immediate: pending.immediate)
                    }
                }
            }
            self.overlayFlush = flush
            self.overlayQueue.asyncAfter(deadline: .now() + .milliseconds(20), execute: flush)
        }
    }

    private func enqueueFullscreenAction(recognizedAt: Date) {
        guard fullscreenGate.wait(timeout: .now()) == .success else {
            mutateStatus { $0.droppedFullscreenActionCount += 1 }
            return
        }
        fullscreenQueue.async { [weak self] in
            defer { self?.fullscreenGate.signal() }
            let age = Date().timeIntervalSince(recognizedAt)
            guard age >= 0 && age <= 1 else {
                self?.mutateStatus { $0.droppedFullscreenActionCount += 1 }
                return
            }
            self?.runFullscreenAction()
        }
    }

    private func runFullscreenAction() {
        guard let aerospace = [
            "/opt/homebrew/bin/aerospace",
            "/usr/local/bin/aerospace"
        ].first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            recordFullscreenActionFailure("aerospace executable not found")
            return
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: aerospace)
        process.arguments = ["fullscreen"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            recordFullscreenActionFailure("could not launch aerospace fullscreen: \(error.localizedDescription)")
            return
        }

        guard exited.wait(timeout: .now() + 2) == .success else {
            process.terminate()
            if exited.wait(timeout: .now() + .milliseconds(200)) != .success,
               process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
                exited.wait()
            }
            recordFullscreenActionFailure("aerospace fullscreen timed out")
            return
        }
        if process.terminationStatus != 0 {
            recordFullscreenActionFailure("aerospace fullscreen exited \(process.terminationStatus)")
        }
    }

    private func recordFullscreenActionFailure(_ message: String) {
        mutateStatus {
            $0.fullscreenActionFailureCount += 1
            $0.lastFullscreenActionError = message
        }
        log(message)
    }

    private func sendOverlayState(_ visible: Bool, immediate: Bool = false) {
        let message = HotkeyMessage(
            kind: .overlay,
            overlayVisible: visible,
            overlayImmediate: immediate,
            sessionID: activeSessionID()
        )
        if !HotkeyDatagram.send(message, to: HotkeyPaths.barSocket) {
            mutateStatus { $0.overlaySendFailureCount += 1 }
        }
    }

    private func heartbeatBar() {
        guard let sessionID = activeSessionID() else { return }
        let message = HotkeyMessage(kind: .heartbeatRequest, sessionID: sessionID)
        pendingHeartbeatRequests[message.messageID] = Date()
        pendingHeartbeatRequests = pendingHeartbeatRequests.filter {
            Date().timeIntervalSince($0.value) <= 5
        }
        _ = HotkeyDatagram.send(message, to: HotkeyPaths.barSocket)
    }

    private func receiveBarHeartbeat(_ message: HotkeyMessage) {
        guard let sentAt = pendingHeartbeatRequests.removeValue(forKey: message.messageID) else {
            return
        }
        let receivedAt = Date().timeIntervalSince1970
        guard let responseLatency = HotkeyHeartbeatPolicy.responseLatency(
                sentAt: sentAt.timeIntervalSince1970,
                responseTimestamp: message.timestamp,
                receivedAt: receivedAt
              ),
              let sessionID = activeSessionID(),
              message.sessionID == sessionID,
              let identity = message.processIdentity,
              let expectedIdentity = readBarIdentity(),
              identity == expectedIdentity,
              message.senderPID == identity.pid,
              identity.executable == barExecutablePath(),
              HotkeyProcessIdentity.identity(for: identity.pid) == identity else {
            return
        }

        let previousHeartbeatAt = lastBarHeartbeatAt
        let identityChanged = lastBarIdentity != identity
        let shouldResynchronize = identityChanged
            || previousHeartbeatAt.map { Date().timeIntervalSince($0) > 3 } != false
        lastBarIdentity = identity
        lastBarHeartbeatAt = Date(timeIntervalSince1970: message.timestamp)
        mutateStatus {
            $0.sessionID = sessionID
            $0.barHeartbeatAt = message.timestamp
            $0.barHeartbeatAge = 0
            $0.barHeartbeatResponseLatency = responseLatency
            if responseLatency > HotkeyHeartbeatPolicy.slowResponseThreshold {
                $0.slowBarHeartbeatCount += 1
                $0.lastSlowBarHeartbeatAt = receivedAt
            }
            $0.barPID = identity.pid
            $0.barStartTime = identity.startTime
            $0.recoveryState = "idle"
        }
        if responseLatency > HotkeyHeartbeatPolicy.slowResponseThreshold {
            log("slow Hub Bar UI heartbeat response: \(Int(responseLatency * 1000))ms")
        }
        if shouldResynchronize {
            let snapshot = statusSnapshot()
            sendOverlayState(snapshot.clusterOverlayVisible, immediate: snapshot.clusterOverlayVisible)
        }
    }

    private func checkBarHealth() {
        let now = Date()
        let sessionID = activeSessionID()
        mutateStatus { $0.sessionID = sessionID }
        guard let sessionID else {
            lastBarHeartbeatAt = nil
            lastBarIdentity = nil
            mutateStatus { $0.recoveryState = "disabled" }
            return
        }

        let identityOnDisk = readBarIdentity()
        if identityOnDisk != lastBarIdentity, identityOnDisk != nil {
            lastBarIdentity = identityOnDisk
            lastBarHeartbeatAt = nil
            barExpectedSince = now
            barGraceUntil = now.addingTimeInterval(15)
        }

        let heartbeatAge = now.timeIntervalSince(lastBarHeartbeatAt ?? barExpectedSince)
        if heartbeatAge < 10 || now < barGraceUntil {
            if !recoveryInProgress {
                mutateStatus { $0.recoveryState = "idle" }
            }
            return
        }
        guard !recoveryInProgress else { return }
        beginAutomaticRecovery(sessionID: sessionID, now: now)
    }

    private func beginAutomaticRecovery(sessionID: String, now: Date) {
        let budget = loadRestartBudget(for: sessionID)
        if let allowedAt = budget.nextAllowedTime(at: now.timeIntervalSince1970) {
            mutateStatus { $0.recoveryState = "deferred until \(Int(allowedAt))" }
            return
        }

        recoveryInProgress = true
        mutateStatus { $0.recoveryState = "sampling" }
        recoveryQueue.async { [weak self] in
            self?.performAutomaticRecovery(sessionID: sessionID)
        }
    }

    private func performAutomaticRecovery(sessionID: String) {
        guard let lock = HotkeyLifecycleLock.acquire(timeout: 20) else {
            finishRecovery(result: "deferred", error: "bar lifecycle lock is busy")
            return
        }
        defer { lock.release() }

        guard activeSessionID() == sessionID else {
            finishRecovery(result: "cancelled", error: nil)
            return
        }
        let stillStalled = controlQueue.sync {
            activeSessionID() == sessionID
                && Date() >= barGraceUntil
                && Date().timeIntervalSince(lastBarHeartbeatAt ?? barExpectedSince) >= 10
        }
        guard stillStalled else {
            finishRecovery(result: "cancelled", error: nil)
            return
        }

        let recordedIdentity = readBarIdentity()
        let oldIdentity = recordedIdentity.flatMap {
            processIsUnchanged($0) ? $0 : nil
        }
        let samplePath = oldIdentity.flatMap { sampleBarStack($0) }
        let reason = "bar heartbeat missing for at least 10 seconds"
        log("bar heartbeat failure; sample=\(samplePath ?? "unavailable")")
        mutateStatus { $0.lastRecoverySample = samplePath }

        let stillStalledAfterSample = controlQueue.sync {
            activeSessionID() == sessionID
                && Date() >= barGraceUntil
                && Date().timeIntervalSince(lastBarHeartbeatAt ?? barExpectedSince) >= 10
                && readBarIdentity() == recordedIdentity
        }
        guard stillStalledAfterSample else {
            finishRecovery(result: "cancelled", error: nil)
            return
        }

        var budget = loadRestartBudget(for: sessionID)
        if let allowedAt = budget.nextAllowedTime(at: Date().timeIntervalSince1970) {
            controlQueue.async {
                self.recoveryInProgress = false
                self.mutateStatus { $0.recoveryState = "deferred until \(Int(allowedAt))" }
            }
            return
        }
        budget.record(at: Date().timeIntervalSince1970)
        saveRestartBudget(budget, sessionID: sessionID)

        guard activeSessionID() == sessionID else {
            finishRecovery(result: "cancelled", error: nil)
            return
        }
        if let oldIdentity {
            switch terminateBarIfUnchanged(oldIdentity) {
            case .terminated:
                break
            case .targetChanged:
                guard readBarIdentity() == recordedIdentity else {
                    finishRecovery(result: "cancelled", error: nil)
                    return
                }
            case .stillRunning:
                appendRecoveryEvent(HotkeyRecoveryEvent(
                    timestamp: Date().timeIntervalSince1970,
                    pid: oldIdentity.pid,
                    result: "terminationFailed",
                    reason: reason
                ))
                finishRecovery(result: "failed", error: "stalled bar remained after SIGKILL")
                return
            }
        }
        guard activeSessionID() == sessionID else {
            finishRecovery(result: "cancelled", error: nil)
            return
        }
        guard startBarThroughLifecycle(sessionID: sessionID) else {
            appendRecoveryEvent(HotkeyRecoveryEvent(
                timestamp: Date().timeIntervalSince1970,
                pid: oldIdentity?.pid,
                result: "barStartFailed",
                reason: reason
            ))
            finishRecovery(result: "failed", error: "bar lifecycle command failed")
            return
        }

        let recovered = waitForBarHeartbeat(after: oldIdentity, sessionID: sessionID, timeout: 15)
        if recovered {
            appendRecoveryEvent(HotkeyRecoveryEvent(
                timestamp: Date().timeIntervalSince1970,
                pid: oldIdentity?.pid,
                result: "restarted",
                reason: reason
            ))
            finishRecovery(result: "restarted", error: nil)
        } else {
            appendRecoveryEvent(HotkeyRecoveryEvent(
                timestamp: Date().timeIntervalSince1970,
                pid: oldIdentity?.pid,
                result: "heartbeatNotRestored",
                reason: reason
            ))
            finishRecovery(result: "failed", error: "replacement bar did not answer heartbeat")
        }
    }

    private func sampleBarStack(_ identity: HotkeyProcessIdentity) -> String? {
        guard processIsUnchanged(identity),
              FileManager.default.isExecutableFile(atPath: "/usr/bin/sample") else {
            return nil
        }
        let directory = HotkeyPaths.runtimeDirectory + "/hub-hotkeyd-samples"
        try? FileManager.default.createDirectory(
            atPath: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        let fileName = "hub_bar-\(Int(Date().timeIntervalSince1970))-\(identity.pid).sample"
        let outputPath = directory + "/" + fileName
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sample")
        process.arguments = ["\(identity.pid)", "1", "-file", outputPath]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return nil
        }
        let overallDeadline = DispatchTime.now() + .seconds(2)
        if exited.wait(timeout: .now() + .seconds(1)) != .success {
            process.terminate()
            if exited.wait(timeout: overallDeadline) != .success, process.isRunning {
                _ = kill(process.processIdentifier, SIGKILL)
            }
        }
        trimStackSamples(in: directory)
        return FileManager.default.fileExists(atPath: outputPath) ? outputPath : nil
    }

    private func trimStackSamples(in directory: String) {
        guard let paths = try? FileManager.default.contentsOfDirectory(atPath: directory) else { return }
        let samples = paths.filter { $0.hasSuffix(".sample") }.sorted()
        for stale in samples.dropLast(5) {
            try? FileManager.default.removeItem(atPath: directory + "/" + stale)
        }
    }

    private func processIsUnchanged(_ identity: HotkeyProcessIdentity) -> Bool {
        HotkeyProcessIdentity.identity(for: identity.pid) == identity
            && identity.executable == barExecutablePath()
    }

    private func terminateBarIfUnchanged(
        _ identity: HotkeyProcessIdentity
    ) -> HotkeyBarTerminationResult {
        guard processIsUnchanged(identity) else { return .targetChanged }
        _ = kill(identity.pid, SIGTERM)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline && processIsUnchanged(identity) {
            usleep(100_000)
        }
        if processIsUnchanged(identity) {
            _ = kill(identity.pid, SIGKILL)
            let killDeadline = Date().addingTimeInterval(2)
            while Date() < killDeadline && processIsUnchanged(identity) {
                usleep(100_000)
            }
        }
        return processIsUnchanged(identity) ? .stillRunning : .terminated
    }

    private func startBarThroughLifecycle(sessionID: String) -> Bool {
        guard let script = hubScriptPath(),
              FileManager.default.isExecutableFile(atPath: script) else {
            return false
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: script)
        process.arguments = ["bar-recovery-start", sessionID,
                            "\(ProcessInfo.processInfo.processIdentifier)"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        do {
            try process.run()
        } catch {
            return false
        }
        guard exited.wait(timeout: .now() + 5) == .success else {
            process.terminate()
            return false
        }
        return process.terminationStatus == 0
    }

    private func waitForBarHeartbeat(after oldIdentity: HotkeyProcessIdentity?,
                                    sessionID: String,
                                    timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let recovered = controlQueue.sync {
                guard activeSessionID() == sessionID,
                      let heartbeat = lastBarHeartbeatAt,
                      Date().timeIntervalSince(heartbeat) <= 3,
                      let identity = lastBarIdentity else {
                    return false
                }
                return oldIdentity != identity
            }
            if recovered { return true }
            if activeSessionID() != sessionID { return false }
            Thread.sleep(forTimeInterval: 0.2)
        }
        return false
    }

    private func finishRecovery(result: String, error: String?) {
        controlQueue.async {
            self.recoveryInProgress = false
            self.mutateStatus {
                $0.recoveryState = result
                $0.lastRecoveryError = error
            }
            if let error {
                self.log("automatic bar recovery \(result): \(error)")
            } else {
                self.log("automatic bar recovery \(result)")
            }
        }
    }

    private func appendRecoveryEvent(_ event: HotkeyRecoveryEvent) {
        controlQueue.sync {
            self.mutateStatus {
                $0.recoveryHistory.append(event)
                $0.recoveryHistory = Array($0.recoveryHistory.suffix(20))
            }
            let snapshot = self.statusSnapshot()
            guard let sessionID = snapshot.sessionID else { return }
            self.saveRestartBudget(
                self.loadRestartBudget(for: sessionID),
                sessionID: sessionID,
                recoveryHistory: snapshot.recoveryHistory
            )
        }
    }

    private func loadRestartBudget(for sessionID: String) -> HotkeyRestartBudget {
        readRestartBudgetRecord(for: sessionID)?.budget ?? HotkeyRestartBudget()
    }

    private func readRestartBudgetRecord(for sessionID: String) -> HotkeyRestartBudgetRecord? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: HotkeyPaths.restartBudgetFile)),
              let record = try? JSONDecoder().decode(HotkeyRestartBudgetRecord.self, from: data),
              record.sessionID == sessionID else {
            return nil
        }
        return record
    }

    private func saveRestartBudget(_ budget: HotkeyRestartBudget,
                                   sessionID: String,
                                   recoveryHistory: [HotkeyRecoveryEvent]? = nil) {
        let events = recoveryHistory
            ?? readRestartBudgetRecord(for: sessionID)?.recoveryHistory
            ?? []
        let record = HotkeyRestartBudgetRecord(sessionID: sessionID,
                                               budget: budget,
                                               recoveryHistory: events)
        guard let data = try? JSONEncoder().encode(record) else { return }
        try? FileManager.default.createDirectory(
            atPath: HotkeyPaths.runtimeDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? data.write(to: URL(fileURLWithPath: HotkeyPaths.restartBudgetFile), options: .atomic)
    }

    private func checkListenerHealth() {
        let snapshot = statusSnapshot()
        let age = Date().timeIntervalSince1970 - snapshot.listenerHeartbeatAt
        guard age >= 10, Date() >= listenerGraceUntil else { return }
        log("event listener stalled for \(Int(age)) seconds; exiting for launchd recovery")
        exit(70)
    }

    private func beginGracePeriod(reason: String) {
        let now = Date()
        listenerGraceUntil = now.addingTimeInterval(15)
        barGraceUntil = now.addingTimeInterval(15)
        barExpectedSince = now
        lastBarHeartbeatAt = nil
        pendingHeartbeatRequests.removeAll()
        lastBarIdentity = readBarIdentity()
        mutateStatus { $0.recoveryState = "grace" }
        resetGestureState()
        controlQueue.asyncAfter(deadline: .now() + 1) { [weak self] in
            self?.performOnEventLoop { [weak self] in
                self?.resetGestureAndSynchronize()
            }
        }
        log("watchdogs reset: \(reason)")
    }

    private func requestTapRecreation() {
        performOnEventLoop { [weak self] in
            guard let self else { return }
            self.destroyEventTap()
            self.mutateStatus { $0.tapHealth = "recreating" }
            self.tapRetryDelay = 1
            self.nextTapRetryAt = Date()
        }
    }

    private func activeSessionID() -> String? {
        guard let value = try? String(contentsOfFile: HotkeyPaths.sessionFile, encoding: .utf8) else {
            return nil
        }
        let sessionID = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return sessionID.isEmpty ? nil : sessionID
    }

    private func readBarIdentity() -> HotkeyProcessIdentity? {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: HotkeyPaths.barIdentityFile)) else {
            return nil
        }
        return try? JSONDecoder().decode(HotkeyProcessIdentity.self, from: data)
    }

    private func barExecutablePath() -> String {
        ProcessInfo.processInfo.environment["HUB_BAR_BIN"]
            ?? HotkeyPaths.configDirectory + "/hub_bar"
    }

    private func hubScriptPath() -> String? {
        if let path = ProcessInfo.processInfo.environment["HUB_SCRIPT"], !path.isEmpty {
            return path
        }
        return try? String(contentsOfFile: HotkeyPaths.configDirectory + "/hub_path",
                           encoding: .utf8)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func statusSnapshot() -> HotkeyDaemonStatus {
        statusLock.lock()
        defer { statusLock.unlock() }
        return status
    }

    private func isStopping() -> Bool {
        stoppingLock.lock()
        defer { stoppingLock.unlock() }
        return stopping
    }

    private func markStopping() -> Bool {
        stoppingLock.lock()
        defer { stoppingLock.unlock() }
        guard !stopping else { return false }
        stopping = true
        return true
    }

    private func mutateStatus(_ update: (inout HotkeyDaemonStatus) -> Void) {
        statusLock.lock()
        update(&status)
        statusLock.unlock()
    }

    private func publishStatus() {
        let now = Date().timeIntervalSince1970
        let heartbeatAge = lastBarHeartbeatAt.map { max(0, Date().timeIntervalSince($0)) }
            ?? max(0, Date().timeIntervalSince(barExpectedSince))
        statusLock.lock()
        status.updatedAt = now
        status.sessionID = activeSessionID()
        status.listenerHeartbeatAge = max(0, now - status.listenerHeartbeatAt)
        status.barHeartbeatAge = heartbeatAge
        let data = try? JSONEncoder().encode(status)
        statusLock.unlock()
        guard let data else { return }
        try? FileManager.default.createDirectory(
            atPath: HotkeyPaths.runtimeDirectory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )
        try? data.write(to: URL(fileURLWithPath: HotkeyPaths.statusFile), options: .atomic)
    }

    private func log(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let line = "[\(timestamp)] HOTKEY \(message)\n"
        let descriptor = open(HotkeyPaths.logFile, O_WRONLY | O_APPEND | O_CREAT, mode_t(S_IRUSR | S_IWUSR))
        guard descriptor >= 0 else { return }
        _ = flock(descriptor, LOCK_EX)
        line.withCString { pointer in _ = write(descriptor, pointer, strlen(pointer)) }
        _ = flock(descriptor, LOCK_UN)
        close(descriptor)
    }

    private func shutdown() {
        guard markStopping() else { return }
        listener?.stop()
        healthTimer?.cancel()
        terminationSignal?.cancel()
        performOnEventLoop {
            CFRunLoopStop(CFRunLoopGetCurrent())
        }
        mutateStatus { $0.recoveryState = "stopped" }
        publishStatus()
        log("listener stopped")
        exit(0)
    }
}

private struct HotkeyLifecycleLock {
    private let ownerPID: Int32

    static func acquire(timeout: TimeInterval) -> HotkeyLifecycleLock? {
        let directory = HotkeyPaths.lifecycleLockDirectory
        let ownerPath = directory + "/owner"
        let deadline = Date().addingTimeInterval(timeout)
        let pid = ProcessInfo.processInfo.processIdentifier
        try? FileManager.default.createDirectory(
            atPath: (directory as NSString).deletingLastPathComponent,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        while Date() < deadline {
            if mkdir(directory, mode_t(S_IRWXU)) == 0 {
                try? "\(pid)\n".write(toFile: ownerPath, atomically: true, encoding: .utf8)
                return HotkeyLifecycleLock(ownerPID: pid)
            }
            if errno != EEXIST { return nil }

            if let ownerText = try? String(contentsOfFile: ownerPath, encoding: .utf8),
               let owner = Int32(ownerText.trimmingCharacters(in: .whitespacesAndNewlines)),
               kill(owner, 0) != 0 && errno == ESRCH {
                _ = unlink(ownerPath)
                _ = rmdir(directory)
            } else if !FileManager.default.fileExists(atPath: ownerPath),
                      let attributes = try? FileManager.default.attributesOfItem(atPath: directory),
                      let modified = attributes[.modificationDate] as? Date,
                      Date().timeIntervalSince(modified) > 2 {
                _ = rmdir(directory)
            }
            usleep(50_000)
        }
        return nil
    }

    private init(ownerPID: Int32) {
        self.ownerPID = ownerPID
    }

    func release() {
        let directory = HotkeyPaths.lifecycleLockDirectory
        let ownerPath = directory + "/owner"
        guard let ownerText = try? String(contentsOfFile: ownerPath, encoding: .utf8),
              Int32(ownerText.trimmingCharacters(in: .whitespacesAndNewlines)) == ownerPID else {
            return
        }
        _ = unlink(ownerPath)
        _ = rmdir(directory)
    }
}

private func runHotkeyClient(_ arguments: [String]) -> Never {
    guard arguments.count >= 2 else {
        fputs("Usage: hub_hotkeyd --overlay <show|hide> | --bar-restarting | --request-access\n", stderr)
        exit(2)
    }

    let command = arguments[1]
    let message: HotkeyMessage
    let destination: String
    switch command {
    case "--overlay":
        guard arguments.count == 3, arguments[2] == "show" || arguments[2] == "hide" else {
            fputs("Usage: hub_hotkeyd --overlay <show|hide>\n", stderr)
            exit(2)
        }
        message = HotkeyMessage(
            kind: .overlay,
            overlayVisible: arguments[2] == "show",
            overlayImmediate: arguments[2] == "hide",
            sessionID: try? String(contentsOfFile: HotkeyPaths.sessionFile, encoding: .utf8)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
        destination = HotkeyPaths.hotkeysSocket
    case "--bar-restarting":
        message = HotkeyMessage(kind: .barRestarting)
        destination = HotkeyPaths.hotkeysSocket
    case "--request-access":
        message = HotkeyMessage(kind: .requestAccess)
        destination = HotkeyPaths.hotkeysSocket
    default:
        fputs("Unknown hub_hotkeyd command: \(command)\n", stderr)
        exit(2)
    }

    let sendAttempts = command == "--request-access" ? 21 : 1
    for attempt in 0..<sendAttempts {
        if HotkeyDatagram.send(message, to: destination) {
            exit(0)
        }
        if attempt + 1 < sendAttempts {
            usleep(100_000)
        }
    }
    fputs("Could not send hotkey IPC message to \(destination)\n", stderr)
    exit(1)
}

let hotkeyArguments = CommandLine.arguments
if hotkeyArguments.count > 1 && hotkeyArguments[1] != "--daemon" {
    runHotkeyClient(hotkeyArguments)
} else {
    let daemon = HubHotkeyDaemon()
    daemon.start()
    RunLoop.main.run()
}
