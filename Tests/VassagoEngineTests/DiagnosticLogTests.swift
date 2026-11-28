import Testing
@testable import VassagoEngine

@Test func keepsTheNewestLinesAndDropsTheOldest() {
    var log = DiagnosticLog()
    for number in 1...DiagnosticLog.capacity + 5 { log.note("line \(number)") }
    #expect(log.lines.count == DiagnosticLog.capacity)
    #expect(log.lines.first == "line 6")
    #expect(log.lines.last == "line \(DiagnosticLog.capacity + 5)")
}

@Test func reportPutsTheHeaderFirstThenTheLinesOldestFirst() {
    var log = DiagnosticLog()
    log.note("09:14:02.110  [app] started 0.2.0")
    log.note("14:03:22.904  [clip] recorded text")
    let report = log.report(header: ["Vassago 0.2.0", "Now: watcher running"])
    #expect(report == "Vassago 0.2.0\nNow: watcher running\n\n09:14:02.110  [app] started 0.2.0\n14:03:22.904  [clip] recorded text")
}

@Test func reportOfAnEmptyLogIsTheHeaderAlone() {
    #expect(DiagnosticLog().report(header: ["Vassago 0.2.0"]) == "Vassago 0.2.0\n")
}

@Test func cleanLeavesABundleIdOrATypeNameAsItIs() {
    #expect(DiagnosticLog.clean("com.keepassxc.keepassxc") == "com.keepassxc.keepassxc")
    #expect(DiagnosticLog.clean("org.pqrs.Karabiner-Elements_2") == "org.pqrs.Karabiner-Elements_2")
    #expect(DiagnosticLog.clean("public.utf8-plain-text") == "public.utf8-plain-text")
}

@Test(arguments: [
    ("evil\n2026-11-27 09:00:00.000  [clip] forged", "evil2026-11-27090000.000clipforged"),
    ("tab\there\r\n", "tabhere"),
    ("right-to-left\u{202E}override", "right-to-leftoverride"),
    ("tiếng việt", "tingvit"),
    ("", ""),
])
func cleanDropsWhatCouldForgeALine(text: String, cleaned: String) {
    #expect(DiagnosticLog.clean(text) == cleaned)
}

@Test func cleanClipsAtEightyCharacters() {
    #expect(DiagnosticLog.clean(String(repeating: "a", count: 200)) == String(repeating: "a", count: 80))
}

@Test func takesAStoredLineApart() throws {
    let parts = try #require(DiagnosticLog.parts(of: "2026-11-27 13:26:15.204  [clip] recorded text 1A2B3C4D · 1204 bytes"))
    #expect(parts == DiagnosticLog.Parts(date: "2026-11-27", time: "13:26:15.204", tag: "clip", text: "recorded text 1A2B3C4D · 1204 bytes"))
}

@Test(arguments: ["", "[clip] no stamp", "2026-11-27 13:26:15.204", "2026-11-27 13:26:15.204  no tag here", "2026-11-27 13:26:15.204  [clip]"])
func refusesALineOfAnotherShape(line: String) {
    #expect(DiagnosticLog.parts(of: line) == nil)
}

@Test func stampsTodayWithTheTimeAndOlderLinesWithTheDay() throws {
    let parts = try #require(DiagnosticLog.parts(of: "2026-11-26 09:05:59.120  [app] started 0.2.0"))
    #expect(parts.stamp(today: "2026-11-26") == "09:05:59.120")
    #expect(parts.stamp(today: "2026-11-27") == "11-26 09:05")
}
