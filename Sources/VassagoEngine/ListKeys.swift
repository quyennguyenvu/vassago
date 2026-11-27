/// Decides what a key pressed in the open list does.
public enum ListKeys {
    public enum Outcome: Equatable {
        /// Paste the row with this number, 1 to 9.
        case pick(Int)
        /// Return or Enter: paste the highlighted row.
        case pickCurrent
        case startSearch
        case type(String)
        case erase
        /// Left to the menu.
        case pass
    }

    /// `characters` is what the key types with the modifiers held. A bare digit picks its row until `/` starts a
    /// search. From then on every character is typed, digits too, and Command with a digit picks.
    public static func keyPressed(_ characters: String, held: Modifiers, searching: Bool) -> Outcome {
        // Shift only decides which character the key types.
        let held = held.subtracting(.shift)
        if held == (searching ? .command : []), characters.count == 1, let digit = Int(characters), digit > 0 {
            return .pick(digit)
        }
        guard held.isEmpty else { return .pass }
        switch characters {
        case "\r", "\u{3}": return .pickCurrent
        case "\u{7F}" where searching: return .erase
        case "/" where !searching: return .startSearch
        default:
            // Leaves out the arrow keys, Esc and Tab, which type a character nobody reads.
            let readable = !characters.isEmpty && characters.allSatisfy { $0.isLetter || $0.isNumber || $0.isPunctuation || $0.isSymbol || $0 == " " }
            return searching && readable ? .type(characters) : .pass
        }
    }
}
