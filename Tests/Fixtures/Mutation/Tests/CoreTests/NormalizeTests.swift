import Core
import Testing

/// Checks `normalizedA`'s percentages and its log exactly.
@Test func normalizedAScalesToPercentages() {
    var log: [Int] = []
    #expect(normalizedA([1, 3], log: &log) == [25, 75])
    #expect(log == [2])
}

/// A total of zero leaves the values as they are, and is still logged.
@Test func normalizedAKeepsAZeroTotal() {
    var log: [Int] = []
    #expect(normalizedA([0, 0, 0], log: &log) == [0, 0, 0])
    #expect(log == [3])
}
