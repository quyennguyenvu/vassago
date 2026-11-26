import Testing
@testable import VassagoEngine

@Test func theDefaultIsControlCommandV() {
    #expect(Hotkey.standard == Hotkey(modifiers: [.control, .command], keyCode: 9))
    #expect(Hotkey.standard.isValid)
    #expect(Hotkey.standard.name == "Control + Command + V")
}

@Test func aShortcutNeedsControlOptionOrCommand() {
    #expect(!Hotkey(modifiers: [], keyCode: 9).isValid)
    #expect(!Hotkey(modifiers: [.shift], keyCode: 9).isValid)
    #expect(Hotkey(modifiers: [.shift, .command], keyCode: 9).isValid)
}

@Test func commandTabStaysWithTheAppSwitcher() {
    #expect(!Hotkey(modifiers: [.command], keyCode: 48).isValid)
    #expect(!Hotkey(modifiers: [.command, .shift], keyCode: 48).isValid)
    #expect(Hotkey(modifiers: [.control], keyCode: 48).isValid)
}

@Test func showsKeycapsInMacOSOrder() {
    #expect(Hotkey.standard.keycaps == ["⌃", "⌘", "V"])
    #expect(Hotkey(modifiers: [.command, .shift, .control], keyCode: 49).keycaps == ["⌃", "⇧", "⌘", "Space"])
    #expect(Hotkey(modifiers: [.control], keyCode: 200).keycaps == ["⌃", "Key 200"])
}

@Test func recordsAKeyWithModifiers() {
    let expected = Hotkey(modifiers: [.control, .option], keyCode: 6)
    #expect(HotkeyRecorder.keyPressed(6, held: [.control, .option]) == .captured(expected))
}

@Test func ignoresWhatCannotBeAShortcut() {
    #expect(HotkeyRecorder.keyPressed(0, held: []) == .pending)
    #expect(HotkeyRecorder.keyPressed(0, held: [.shift]) == .pending)
    #expect(HotkeyRecorder.keyPressed(48, held: [.command]) == .pending)
}

@Test func escapeAloneCancelsARecording() {
    #expect(HotkeyRecorder.keyPressed(53, held: []) == .cancelled)
    // With a modifier it is a shortcut like any other.
    #expect(HotkeyRecorder.keyPressed(53, held: [.control]) == .captured(Hotkey(modifiers: [.control], keyCode: 53)))
}
