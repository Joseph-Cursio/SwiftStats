import Core
import Testing

/// Checks every sign exactly.
@Test func signIsExact() {
    #expect(sign(5) == 1)
    #expect(sign(1) == 1)
    #expect(sign(-5) == -1)
    #expect(sign(-1) == -1)
    #expect(sign(0) == 0)
}
