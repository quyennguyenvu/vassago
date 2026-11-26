import Testing
@testable import VassagoEngine

private func clip(_ id: String, bytes: Int = 10, digest: String? = nil) -> Clip {
    Clip(id: id, kind: .text, title: id, bytes: bytes, digest: digest ?? id)
}

@Test func aNewClipGoesOnTop() {
    var history = History()
    #expect(history.add(clip("a")).isEmpty)
    #expect(history.add(clip("b")).isEmpty)
    #expect(history.clips.map(\.id) == ["b", "a"])
}

@Test func copyingTheSameContentAgainReplacesTheOlderClip() {
    var history = History(clips: [clip("b"), clip("a", digest: "same")])
    #expect(history.add(clip("c", digest: "same")).map(\.id) == ["a"])
    #expect(history.clips.map(\.id) == ["c", "b"])
}

@Test func theOldestClipLeavesWhenTheCountIsPassed() {
    var history = History(clips: [clip("b"), clip("a")], maxCount: 2)
    #expect(history.add(clip("c")).map(\.id) == ["a"])
    #expect(history.clips.map(\.id) == ["c", "b"])
}

@Test func theOldestClipsLeaveUntilTheSizeFits() {
    var history = History(clips: [clip("b", bytes: 40), clip("a", bytes: 40)], maxBytes: 100)
    #expect(history.add(clip("c", bytes: 70)).map(\.id) == ["a", "b"])
    #expect(history.clips.map(\.id) == ["c"])
}

@Test func theClipJustAddedStaysEvenWhenItAloneIsOverTheSize() {
    var history = History(maxBytes: 100)
    #expect(history.add(clip("a", bytes: 500)).isEmpty)
    #expect(history.clips.map(\.id) == ["a"])
}

@Test func removingAClipReturnsItForDeletion() {
    var history = History(clips: [clip("b"), clip("a")])
    #expect(history.remove(id: "a")?.id == "a")
    #expect(history.remove(id: "a") == nil)
    #expect(history.clips.map(\.id) == ["b"])
}

@Test func clearingReturnsEveryClip() {
    var history = History(clips: [clip("b"), clip("a")])
    #expect(history.removeAll().map(\.id) == ["b", "a"])
    #expect(history.clips.isEmpty)
}

@Test(arguments: [
    ("ORD-10005", "ORD-10005"),
    ("\n\n  first line\nsecond", "first line"),
    ("a \t b\u{00A0}  c", "a b c"),
    ("   \n\t\n", ""),
])
func theTitleIsTheFirstLineWithItsWhitespaceTidied(text: String, expected: String) {
    #expect(title(forText: text) == expected)
}

@Test func aLongTitleIsCutToSixtyCharacters() {
    let sixty = String(repeating: "x", count: 60)
    #expect(title(forText: sixty) == sixty)
    #expect(title(forText: sixty + "y") == String(repeating: "x", count: 59) + "…")
}

@Test func atLaunchClipsWithoutDataAreDroppedAndStrayFilesAreListed() {
    let files: Set = ["a.plist", "a.png", "old.plist", "old.png", ".DS_Store"]
    let kept = reconcile(index: [clip("b"), clip("a")], files: files)
    #expect(kept.clips.map(\.id) == ["a"])
    #expect(kept.strays == [".DS_Store", "old.plist", "old.png"])
}
