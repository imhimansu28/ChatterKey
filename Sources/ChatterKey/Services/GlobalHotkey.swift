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
    private var isPressed = false
    private var usedWithAnotherKey = false
    private var shortcut: HotkeyShortcut = .function

    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onCancel: (() -> Void)?

    var isAccessibilityGranted: Bool { AXIsProcessTrusted() }

    func configure(_ newShortcut: HotkeyShortcut) {
        if shortcut != newShortcut, isPressed {
            isPressed = false
            usedWithAnotherKey = false
            onCancel?()
        }
        shortcut = newShortcut
    }

    func requestAccessibility() {
        let options = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        AXIsProcessTrustedWithOptions(options)
    }

    @discardableResult
    func start() -> Bool {
        installFallbackMonitors()
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
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        owner.reenableEventTap()
                        return Unmanaged.passUnretained(event)
                    }
                    return owner.handleCGEvent(type: type, event: event)
                        ? nil
                        : Unmanaged.passUnretained(event)
                }
            },
            userInfo: pointer
        ) else {
            return globalMonitor != nil || localMonitor != nil
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handleCGEvent(type: CGEventType, event: CGEvent) -> Bool {
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) == 1

        switch shortcut {
        case .function:
            if type == .flagsChanged {
                handleModifier(isDown: flags.contains(.maskSecondaryFn))
                return keyCode == 63
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
        if globalMonitor == nil {
            globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                let fnDown = event.modifierFlags.contains(.function)
                let optionDown = event.modifierFlags.contains(.option)
                let keyCode = event.keyCode
                Task { @MainActor in
                    guard let self else { return }
                    if self.shortcut == .function {
                        self.handleModifier(isDown: fnDown)
                    } else if self.shortcut == .rightOption, keyCode == 61 {
                        self.handleModifier(isDown: optionDown)
                    }
                }
            }
        }
        if localMonitor == nil {
            localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
                let fnDown = event.modifierFlags.contains(.function)
                let optionDown = event.modifierFlags.contains(.option)
                let keyCode = event.keyCode
                Task { @MainActor in
                    guard let self else { return }
                    if self.shortcut == .function {
                        self.handleModifier(isDown: fnDown)
                    } else if self.shortcut == .rightOption, keyCode == 61 {
                        self.handleModifier(isDown: optionDown)
                    }
                }
                return event
            }
        }
    }

    private func handleModifier(isDown: Bool) {
        if isDown, !isPressed {
            isPressed = true
            usedWithAnotherKey = false
            onPress?()
        } else if !isDown, isPressed {
            finishPress()
        }
    }

    private func handleKeyEvent(type: CGEventType, isRepeat: Bool) {
        if type == .keyDown, !isRepeat, !isPressed {
            isPressed = true
            usedWithAnotherKey = false
            onPress?()
        } else if type == .keyUp, isPressed {
            finishPress()
        }
    }

    private func finishPress() {
        isPressed = false
        if usedWithAnotherKey { onCancel?() } else { onRelease?() }
        usedWithAnotherKey = false
    }

    private func reenableEventTap() {
        if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
    }
}
