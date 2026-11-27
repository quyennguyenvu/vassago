import Testing
@testable import VassagoEngine

@Test func aBareDigitPicksUntilASearchStarts() {
    #expect(ListKeys.keyPressed("3", held: [], searching: false) == .pick(3))
    #expect(ListKeys.keyPressed("3", held: [], searching: true) == .type("3"))
    // A layout that types digits with Shift held still picks.
    #expect(ListKeys.keyPressed("1", held: [.shift], searching: false) == .pick(1))
    // No row is numbered 0.
    #expect(ListKeys.keyPressed("0", held: [], searching: false) == .pass)
}

@Test func commandWithADigitPicksDuringASearch() {
    #expect(ListKeys.keyPressed("3", held: [.command], searching: true) == .pick(3))
    #expect(ListKeys.keyPressed("0", held: [.command], searching: true) == .pass)
    // Outside a search it stays with the menu, as before.
    #expect(ListKeys.keyPressed("3", held: [.command], searching: false) == .pass)
}

@Test func slashStartsASearchAndIsTextOnceInIt() {
    #expect(ListKeys.keyPressed("/", held: [], searching: false) == .startSearch)
    #expect(ListKeys.keyPressed("/", held: [], searching: true) == .type("/"))
}

@Test(arguments: ["a", "A", "đ", "ơ", " ", "-", "+", "!", "0"])
func aSearchTakesWhatCanBeRead(typed: String) {
    #expect(ListKeys.keyPressed(typed, held: [], searching: true) == .type(typed))
    #expect(ListKeys.keyPressed(typed, held: [.shift], searching: true) == .type(typed))
    // Outside a search these stay with the menu, as before.
    #expect(ListKeys.keyPressed(typed, held: [], searching: false) == .pass)
}

@Test func deleteTakesBackACharacterOfASearch() {
    #expect(ListKeys.keyPressed("\u{7F}", held: [], searching: true) == .erase)
    #expect(ListKeys.keyPressed("\u{7F}", held: [], searching: false) == .pass)
}

@Test(arguments: [false, true])
func returnAndEnterPickTheCurrentRow(searching: Bool) {
    #expect(ListKeys.keyPressed("\r", held: [], searching: searching) == .pickCurrent)
    #expect(ListKeys.keyPressed("\u{3}", held: [], searching: searching) == .pickCurrent)
}

@Test(arguments: [false, true])
func theRestStaysWithTheMenu(searching: Bool) {
    // An arrow key, Esc, Tab, and a dead key, which types nothing yet.
    for typed in ["\u{F700}", "\u{1B}", "\t", ""] {
        #expect(ListKeys.keyPressed(typed, held: [], searching: searching) == .pass)
    }
    #expect(ListKeys.keyPressed("a", held: [.control], searching: searching) == .pass)
    #expect(ListKeys.keyPressed("a", held: [.command], searching: searching) == .pass)
    #expect(ListKeys.keyPressed("1", held: [.option], searching: searching) == .pass)
    #expect(ListKeys.keyPressed("1", held: [.control, .command], searching: searching) == .pass)
}
