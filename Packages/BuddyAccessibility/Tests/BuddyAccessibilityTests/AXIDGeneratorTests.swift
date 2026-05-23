import Testing
@testable import BuddyAccessibility

@Suite("AXIDGenerator")
struct AXIDGeneratorTests {
    @Test("issues e_N in order")
    func sequential() {
        var gen = AXIDGenerator()
        #expect(gen.next() == "e_1")
        #expect(gen.next() == "e_2")
        #expect(gen.next() == "e_3")
    }

    @Test("two generators are independent")
    func independent() {
        var a = AXIDGenerator()
        var b = AXIDGenerator()
        _ = a.next(); _ = a.next()
        #expect(b.next() == "e_1")
    }
}
