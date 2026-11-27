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

@Test func aLowerCountReturnsTheOldestClipsOverIt() {
    var history = History(clips: [clip("c"), clip("b"), clip("a")])
    #expect(history.limit(maxCount: 1, maxBytes: 1000).map(\.id) == ["a", "b"])
    #expect(history.clips.map(\.id) == ["c"])
}

@Test func aLowerSizeReturnsTheOldestClipsUntilTheRestFits() {
    var history = History(clips: [clip("c", bytes: 40), clip("b", bytes: 40), clip("a", bytes: 40)])
    #expect(history.limit(maxCount: 100, maxBytes: 100).map(\.id) == ["a"])
    #expect(history.clips.map(\.id) == ["c", "b"])
}

@Test func higherLimitsDropNothingAndHoldForTheNextClips() {
    var history = History(clips: [clip("b"), clip("a")], maxCount: 2)
    #expect(history.limit(maxCount: 3, maxBytes: 1000).isEmpty)
    #expect(history.add(clip("c")).isEmpty)
    #expect(history.add(clip("d")).map(\.id) == ["a"])
}

@Test func theNewestClipStaysWhateverTheNewLimits() {
    var history = History(clips: [clip("b", bytes: 500), clip("a")])
    #expect(history.limit(maxCount: 1, maxBytes: 100).map(\.id) == ["a"])
    #expect(history.clips.map(\.id) == ["b"])
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

@Test func aTitleThatFitsTheListIsLeftAlone() {
    #expect(shortened("ORD-10005") { $0.count <= 10 } == "ORD-10005")
}

@Test func aTitleTooWideForTheListKeepsAsMuchAsFits() {
    // Nine characters and the … are the ten that fit.
    #expect(shortened("explain analyze select") { $0.count <= 10 } == "explain a…")
    // Width is not a count of characters: here a W is as wide as three of the others.
    let width: (String) -> Int = { $0.reduce(0) { $0 + ($1 == "W" ? 3 : 1) } }
    #expect(shortened("WWWWabcdef") { width($0) <= 10 } == "WWW…")
    #expect(shortened("abcdefWWWW") { width($0) <= 10 } == "abcdefW…")
}

@Test func whenNothingFitsOnlyTheEllipsisIsLeft() {
    #expect(shortened("ORD-10005") { _ in false } == "…")
}

@Test func atLaunchClipsWithoutDataAreDroppedAndStrayFilesAreListed() {
    let files: Set = ["a.plist", "a.png", "old.plist", "old.png", ".DS_Store"]
    let kept = reconcile(index: [clip("b"), clip("a")], files: files)
    #expect(kept.clips.map(\.id) == ["a"])
    #expect(kept.strays == [".DS_Store", "old.plist", "old.png"])
}
