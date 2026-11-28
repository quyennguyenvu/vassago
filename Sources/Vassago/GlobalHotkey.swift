import Carbon.HIToolbox
import Foundation
import VassagoEngine

/// Registers the shortcut with macOS. This needs no permission and no key hook.
final class GlobalHotkey {
    /// Called on the main thread when the shortcut is pressed.
    var onPress: () -> Void = {}

    private var registration: EventHotKeyRef?

    init() {
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        // The dispatcher target also delivers the press while a menu is open.
        let status = InstallEventHandler(
            GetEventDispatcherTarget(),
            { _, _, context in
                let hotkey = Unmanaged<GlobalHotkey>.fromOpaque(context!).takeUnretainedValue()
                // Out of the event handler first: the press opens a menu, which runs an event loop of its own.
                DispatchQueue.main.async { hotkey.onPress() }
                return noErr
            },
            1, &pressed, Unmanaged.passUnretained(self).toOpaque(), nil)
        if status != noErr { Diagnostics.note("[hotkey] no handler for the press: status \(status)") }
    }

    var isRegistered: Bool {
        registration != nil
    }

    /// False when macOS refuses the shortcut. Nothing is registered then.
    func register(_ hotkey: Hotkey) -> Bool {
        unregister()
        var modifiers = 0
        if hotkey.modifiers.contains(.control) { modifiers |= controlKey }
        if hotkey.modifiers.contains(.option) { modifiers |= optionKey }
        if hotkey.modifiers.contains(.shift) { modifiers |= shiftKey }
        if hotkey.modifiers.contains(.command) { modifiers |= cmdKey }
        let id = EventHotKeyID(signature: 0x5641_5353, id: 1)
        let status = RegisterEventHotKey(
            UInt32(hotkey.keyCode), UInt32(modifiers), id, GetEventDispatcherTarget(), 0, &registration)
        Diagnostics.note(status == noErr ? "[hotkey] registered \(hotkey.name)" : "[hotkey] macOS refused \(hotkey.name): status \(status)")
        return status == noErr
    }

    func unregister() {
        if let registration { UnregisterEventHotKey(registration) }
        registration = nil
    }
}
