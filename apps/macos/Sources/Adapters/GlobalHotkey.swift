import AppKit
import ApplicationServices
@preconcurrency import CoreGraphics
import Foundation

@MainActor
final class GlobalHotkey {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var callbackGeneration = 0
    private var isPressed = false
    private var usedWithAnotherKey = false
    private var shortcut: HotkeyShortcut = .function
    private var functionPressedAt: TimeInterval?
    private var functionReleasedAt: TimeInterval?
    private var functionReleaseTask: Task<Void, Never>?
    private var ignoresFunctionRelease = false
    private var recordingActive = false
    private(set) var isHandsFree = false

    private static let functionDoubleTapInterval: TimeInterval = 0.35
    private static let maximumFunctionTapDuration: TimeInterval = 0.25
    static var functionDoubleTapDelay: Duration { .seconds(functionDoubleTapInterval) }

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?
    var onHandsFree: (() -> Void)?

    var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    func configure(_ newShortcut: HotkeyShortcut) {
        guard shortcut != newShortcut else { return }
        let wasActive = hasActiveGesture
        resetRecordingGesture()
        shortcut = newShortcut
        if wasActive { onCancel?() }
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }
        let mask = (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
        let pointer = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let owner = Unmanaged<GlobalHotkey>.fromOpaque(refcon).takeUnretainedValue()
                return MainActor.assumeIsolated {
                    owner.handleCGEvent(type: type, event: event)
                        ? nil
                        : Unmanaged.passUnretained(event)
                }
            },
            userInfo: pointer
        ) else {
            installFallbackMonitors()
            return isAccessibilityGranted && globalMonitor != nil
                && (shortcut == .function || shortcut == .rightOption)
        }

        removeFallbackMonitors()
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func handleCGEvent(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            reenableEventTap()
            return false
        }
        return handleEvent(
            type: type,
            keyCode: event.getIntegerValueField(.keyboardEventKeycode),
            flags: event.flags,
            timestamp: Double(event.timestamp) / 1_000_000_000,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) == 1,
            isSynthetic: event.getIntegerValueField(.eventSourceUserData) == TextSelectionReader.syntheticTextEventTag
        )
    }

    private func handleEvent(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags,
        timestamp: TimeInterval,
        isRepeat: Bool,
        isSynthetic: Bool
    ) -> Bool {
        guard !isSynthetic else { return false }
        if type == .keyDown, keyCode == 53, hasActiveGesture {
            resetRecordingGesture()
            enqueue(onCancel)
            return true
        }
        // Space-up may no longer contain the shortcut's modifier flags.
        if type == .keyUp, keyCode == 49, isPressed,
           shortcut == .optionSpace || shortcut == .commandShiftSpace {
            finishPress()
            return true
        }

        switch shortcut {
        case .function:
            if type == .flagsChanged, keyCode == 63 {
                handleFunction(isDown: flags.contains(.maskSecondaryFn), timestamp: timestamp)
                return true
            }
            if type == .keyDown, keyCode != 63, isPressed { usedWithAnotherKey = true }
        case .rightOption:
            if type == .flagsChanged, keyCode == 61 {
                handleModifier(isDown: flags.contains(.maskAlternate))
                return true
            }
            if type == .keyDown, keyCode != 61, isPressed { usedWithAnotherKey = true }
        case .optionSpace:
            if keyCode == 49, flags.contains(.maskAlternate) {
                handleKeyEvent(type: type, isRepeat: isRepeat)
                return true
            }
        case .commandShiftSpace:
            if keyCode == 49, flags.contains([.maskCommand, .maskShift]) {
                handleKeyEvent(type: type, isRepeat: isRepeat)
                return true
            }
        }
        return false
    }

    private func installFallbackMonitors() {
        let syntheticTag = TextSelectionReader.syntheticTextEventTag
        let forward: @Sendable (NSEvent) -> Void = { [weak self] event in
            guard let cgEvent = event.cgEvent else { return }
            let type = cgEvent.type
            let keyCode = cgEvent.getIntegerValueField(.keyboardEventKeycode)
            let flags = cgEvent.flags
            let timestamp = Double(cgEvent.timestamp) / 1_000_000_000
            let isRepeat = cgEvent.getIntegerValueField(.keyboardEventAutorepeat) == 1
            let isSynthetic = cgEvent.getIntegerValueField(.eventSourceUserData) == syntheticTag
            Task { @MainActor in
                guard let self, self.eventTap == nil else { return }
                _ = self.handleEvent(type: type, keyCode: keyCode, flags: flags, timestamp: timestamp, isRepeat: isRepeat, isSynthetic: isSynthetic)
            }
        }
        let events: NSEvent.EventTypeMask = [.flagsChanged, .keyDown, .keyUp]
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: events, handler: forward)
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: events) { event in
                forward(event)
                return event
            }
        }
    }

    private func handleFunction(isDown: Bool, timestamp: TimeInterval) {
        if isDown {
            guard !isPressed else { return }
            isPressed = true
            usedWithAnotherKey = false
            if isHandsFree {
                isHandsFree = false
                ignoresFunctionRelease = true
                enqueue(onRelease)
            } else if functionReleaseTask != nil {
                functionReleaseTask?.cancel()
                functionReleaseTask = nil
                let gap = functionReleasedAt.map { timestamp - $0 }
                functionReleasedAt = nil
                if let gap, gap >= 0, gap <= Self.functionDoubleTapInterval {
                    isHandsFree = true
                    enqueue(onHandsFree, requireCurrentGeneration: true)
                } else {
                    ignoresFunctionRelease = true
                    enqueue(onRelease)
                }
            } else {
                functionPressedAt = timestamp
                enqueue(onPress, requireCurrentGeneration: true)
            }
            return
        }
        guard isPressed else { return }
        isPressed = false
        // Measure physical key timing, not callback delivery time: audio startup
        // or a busy run loop can delay a quick Fn release.
        let wasTap = functionPressedAt.map {
            let duration = timestamp - $0
            return duration >= 0 && duration <= Self.maximumFunctionTapDuration
        } ?? false
        functionPressedAt = nil
        if ignoresFunctionRelease {
            ignoresFunctionRelease = false
            return
        }
        if isHandsFree { return }
        if usedWithAnotherKey {
            usedWithAnotherKey = false
            enqueue(onCancel)
        } else if wasTap {
            // A short first tap starts capture but must not submit a request
            // before the user has a chance to double-tap and lock recording.
            functionReleasedAt = timestamp
            functionReleaseTask = Task { [weak self] in
                do { try await Task.sleep(for: Self.functionDoubleTapDelay) } catch { return }
                guard let self else { return }
                self.functionReleaseTask = nil
                self.functionReleasedAt = nil
                self.enqueue(self.onRelease)
            }
        } else {
            enqueue(onRelease)
        }
    }

    func recordingStarted() {
        recordingActive = true
    }

    func resetRecordingGesture() {
        callbackGeneration &+= 1
        functionReleaseTask?.cancel()
        functionReleaseTask = nil
        functionPressedAt = nil
        functionReleasedAt = nil
        ignoresFunctionRelease = false
        isHandsFree = false
        isPressed = false
        usedWithAnotherKey = false
        recordingActive = false
    }

    private var hasActiveGesture: Bool {
        recordingActive || isPressed || isHandsFree || functionReleaseTask != nil
    }

    private func handleModifier(isDown: Bool) {
        if isDown, !isPressed {
            isPressed = true
            usedWithAnotherKey = false
            enqueue(onPress, requireCurrentGeneration: true)
        } else if !isDown, isPressed {
            finishPress()
        }
    }

    private func handleKeyEvent(type: CGEventType, isRepeat: Bool) {
        if type == .keyDown, !isRepeat, !isPressed {
            isPressed = true
            usedWithAnotherKey = false
            enqueue(onPress, requireCurrentGeneration: true)
        } else if type == .keyUp, isPressed {
            finishPress()
        }
    }

    private func finishPress() {
        isPressed = false
        let completion = usedWithAnotherKey ? onCancel : onRelease
        usedWithAnotherKey = false
        enqueue(completion)
    }

    func stop() {
        let wasActive = hasActiveGesture
        resetRecordingGesture()
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        if let eventTap { CFMachPortInvalidate(eventTap) }
        eventTap = nil
        runLoopSource = nil
        removeFallbackMonitors()
        if wasActive { onCancel?() }
    }

    private func removeFallbackMonitors() {
        if let globalMonitor { NSEvent.removeMonitor(globalMonitor) }
        if let localMonitor { NSEvent.removeMonitor(localMonitor) }
        globalMonitor = nil
        localMonitor = nil
    }

    private func enqueue(_ callback: (() -> Void)?, requireCurrentGeneration: Bool = false) {
        let generation = callbackGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self, !requireCurrentGeneration || self.callbackGeneration == generation else { return }
            callback?()
        }
    }

    private func reenableEventTap() {
        let wasActive = hasActiveGesture
        resetRecordingGesture()
        if wasActive { enqueue(onCancel) }
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
    }
}
