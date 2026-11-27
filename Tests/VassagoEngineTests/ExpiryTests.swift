import Testing
@testable import VassagoEngine

@Test func theClipboardIsEmptiedOnceItHasHeldTheSameThingLongEnough() {
    var expiry = Expiry()
    #expect(expiry.check(count: 7, at: 1000, after: 60) == false)
    #expect(expiry.check(count: 7, at: 1059, after: 60) == false)
    #expect(expiry.check(count: 7, at: 1060, after: 60) == true)
}

@Test func aNewCopyStartsTheWaitAgain() {
    var expiry = Expiry()
    #expect(expiry.check(count: 7, at: 1000, after: 60) == false)
    #expect(expiry.check(count: 8, at: 1050, after: 60) == false)
    #expect(expiry.check(count: 8, at: 1100, after: 60) == false)
    #expect(expiry.check(count: 8, at: 1110, after: 60) == true)
}

@Test func nothingIsEmptiedWhileTheSettingIsNever() {
    var expiry = Expiry()
    #expect(expiry.check(count: 7, at: 1000, after: nil) == false)
    #expect(expiry.check(count: 7, at: 90_000, after: nil) == false)
    // Switched on later, the wait still counts from the copy.
    #expect(expiry.check(count: 7, at: 90_000, after: 60) == true)
}

@Test func anEmptiedClipboardIsLeftAloneUntilTheNextCopy() {
    var expiry = Expiry()
    #expect(expiry.check(count: 7, at: 1000, after: 60) == false)
    #expect(expiry.check(count: 7, at: 1060, after: 60) == true)
    // Emptying it moved the counter.
    expiry.emptied(count: 8)
    #expect(expiry.check(count: 8, at: 1061, after: 60) == false)
    #expect(expiry.check(count: 8, at: 90_000, after: 60) == false)
    #expect(expiry.check(count: 9, at: 90_001, after: 60) == false)
    #expect(expiry.check(count: 9, at: 90_061, after: 60) == true)
}
