import Probe
import Testing

@Test func addsAndDoubles() {
    var counter = Counter()
    counter.add([1, 2])
    #expect(counter.total == 6)
    #expect(counter.doubled() == 12)
}
