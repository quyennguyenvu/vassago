/// The modifier keys a shortcut can use.
public struct Modifiers: OptionSet, Hashable {
    public let rawValue: UInt8

    public init(rawValue: UInt8) {
        self.rawValue = rawValue
    }

    public static let control = Modifiers(rawValue: 1)
    public static let option = Modifiers(rawValue: 2)
    public static let shift = Modifiers(rawValue: 4)
    public static let command = Modifiers(rawValue: 8)
}

/// The shortcut that opens the list: modifiers with one key.
public struct Hotkey: Equatable {
    public var modifiers: Modifiers
    /// Virtual key code.
    public var keyCode: UInt16

    public init(modifiers: Modifiers, keyCode: UInt16) {
        self.modifiers = modifiers
        self.keyCode = keyCode
    }

    /// Control + Command + V, the default: pinky, thumb and index finger of one hand.
    public static let standard = Hotkey(modifiers: [.control, .command], keyCode: 9)

    /// Control, Option or Command must be held, and Command+Tab stays with the app switcher.
    public var isValid: Bool {
        if keyCode == 48, modifiers.contains(.command) { return false }
        return !modifiers.isDisjoint(with: [.control, .option, .command])
    }

    /// Keycap labels in the order macOS shows them: ⌃ ⌥ ⇧ ⌘, then the key.
    public var keycaps: [String] {
        let symbols: [(Modifiers, String)] = [(.control, "⌃"), (.option, "⌥"), (.shift, "⇧"), (.command, "⌘")]
        return symbols.filter { modifiers.contains($0.0) }.map(\.1) + [keyLabels[keyCode] ?? "Key \(keyCode)"]
    }

    /// The shortcut in words, for anyone who does not read ⌃ as Control: "Control + Command + V".
    public var name: String {
        let words: [(Modifiers, String)] = [(.control, "Control"), (.option, "Option"), (.shift, "Shift"), (.command, "Command")]
        let parts = words.filter { modifiers.contains($0.0) }.map(\.1) + [keyLabels[keyCode] ?? "Key \(keyCode)"]
        return parts.joined(separator: " + ")
    }
}

/// Captures the next shortcut the user presses.
public enum HotkeyRecorder {
    public enum Outcome: Equatable {
        case pending, cancelled, captured(Hotkey)
    }

    /// A key captures a shortcut when it comes with valid modifiers. Escape alone cancels.
    public static func keyPressed(_ keyCode: UInt16, held: Modifiers) -> Outcome {
        if keyCode == 53, held.isEmpty { return .cancelled }
        let hotkey = Hotkey(modifiers: held, keyCode: keyCode)
        return hotkey.isValid ? .captured(hotkey) : .pending
    }
}

/// Labels for the keys of an ANSI keyboard, by virtual key code.
private let keyLabels: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V", 11: "B", 12: "Q",
    13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5",
    24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I",
    35: "P", 36: "Return", 37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/",
    45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space", 50: "`", 51: "Delete", 53: "Esc",
    96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8", 101: "F9", 103: "F11", 109: "F10", 111: "F12",
    118: "F4", 120: "F2", 122: "F1", 123: "←", 124: "→", 125: "↓", 126: "↑",
]
