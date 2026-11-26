import Testing
@testable import VassagoEngine

@Test func readsPlainVersionsAndReleaseTags() {
    #expect(Version("0.2.0")?.text == "0.2.0")
    #expect(Version("v1.10.3")?.text == "1.10.3")
}

@Test(arguments: ["", "1.2", "1.2.3.4", "1.2.x", "v1.2.3-beta", "1..3", "-1.2.3", "latest"])
func refusesAnythingElse(text: String) {
    #expect(Version(text) == nil)
}

@Test func ordersByNumberNotByText() throws {
    #expect(try #require(Version("0.9.0")) < #require(Version("0.10.0")))
    #expect(try #require(Version("1.0.0")) > #require(Version("0.99.99")))
    #expect(try #require(Version("v0.2.0")) == #require(Version("0.2.0")))
}
