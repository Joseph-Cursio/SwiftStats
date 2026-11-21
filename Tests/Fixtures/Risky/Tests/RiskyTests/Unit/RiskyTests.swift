@testable import Risky
import Testing

@Test func crashes() {
    #expect(Crash.unwrapped(1) == 1)
    #expect(Crash.fallback(2, nil) == 2)
    #expect(Crash.branch(nil, false) == 0)
    #expect(Crash.ranSignature(nil) == 1)
    #expect(Crash.inactive(nil) == 2)
    #expect(Crash.outer(nil) == 3)
    #expect(Crash.pair(1, 2) == 3)
    #expect(Crash.mixed(4, false) == 4)
    #expect(Crash.cast(5) == 5)
}

@Test func races() {
    let worked = Worked()
    worked.work()
    #expect(worked.count == 1)
    #expect(OnlyBuilt().count == 0)
    Tally.bump()
    #expect(Settings().parsed == 5)
    let boxed = Boxed()
    boxed.value = 3
    #expect(boxed.value == 3)
    #expect(Released().count == 0)
}
