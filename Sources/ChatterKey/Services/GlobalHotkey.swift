import AppKit
import ApplicationServices
import CoreGraphics
import Foundation

@MainActor
final class GlobalHotkey {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalFlagsMonitor: Any?
    private var localFlagsMonitor: Any?
    private var isPressed = false
    private var usedWithAnotherKey = false
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    var isAccessibilityGranted: Bool {
        AXIsProcessTrusted()
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func start() -> Bool {
        installNSEventFallbacks()
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

                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    Task { @MainActor in owner.reenableEventTap() }
                    return Unmanaged.passUnretained(event)
                }

                let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
                if type == .flagsChanged {
                    // Some keyboards report Fn with key code 63; others only expose
                    // the secondaryFn flag. Observe the flag transition in both cases.
                    let isDown = event.flags.contains(.maskSecondaryFn)
                    Task { @MainActor in owner.handleFn(isDown: isDown) }
                    if keyCode == 63 { return nil }
                } else if type == .keyDown, keyCode != 63 {
                    Task { @MainActor in owner.handleOtherKey() }
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: pointer
        ) else {
            return globalFlagsMonitor != nil || localFlagsMonitor != nil
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func installNSEventFallbacks() {
        if globalFlagsMonitor == nil {
            globalFlagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                let isDown = event.modifierFlags.contains(.function)
                Task { @MainActor in self?.handleFn(isDown: isDown) }
            }
        }
        if localFlagsMonitor == nil {
            localFlagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                let isDown = event.modifierFlags.contains(.function)
                Task { @MainActor in self?.handleFn(isDown: isDown) }
                return event
            }
        }
    }

    private func reenableEventTap() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func handleFn(isDown: Bool) {
        if isDown, !isPressed {
            isPressed = true
            usedWithAnotherKey = false
            onPress?()
        } else if !isDown, isPressed {
            isPressed = false
            if usedWithAnotherKey {
                onCancel?()
            } else {
                onRelease?()
            }
            usedWithAnotherKey = false
        }
    }

    private func handleOtherKey() {
        guard isPressed else { return }
        usedWithAnotherKey = true
    }
}
