import Foundation
import Carbon.HIToolbox
import AppKit

/// Registers ⌃⌥Space system-wide so work can be captured without switching apps.
///
/// Carbon's hot key API is used deliberately: unlike a global event monitor it
/// needs no accessibility permission, so there's nothing for the student to approve.
final class GlobalHotkey {
    static let shared = GlobalHotkey()

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (() -> Void)?

    private let signature: OSType = 0x4C4B_5241 // 'LKRA'

    private init() {}

    var isRegistered: Bool { hotKeyRef != nil }

    func register(action: @escaping () -> Void) {
        unregister()
        self.action = action

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, event, userData in
            guard let userData, let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            GetEventParameter(
                event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID
            )
            let monitor = Unmanaged<GlobalHotkey>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { monitor.action?() }
            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(), callback, 1, &eventType,
            Unmanaged.passUnretained(self).toOpaque(), &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        RegisterEventHotKey(
            UInt32(kVK_Space),
            UInt32(controlKey | optionKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        hotKeyRef = nil
        if let eventHandler { RemoveEventHandler(eventHandler) }
        eventHandler = nil
        action = nil
    }
}
