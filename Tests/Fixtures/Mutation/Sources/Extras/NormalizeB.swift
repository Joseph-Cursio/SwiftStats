/// `normalizedA`'s copy, which no test runs.
public func normalizedB(_ values: [Int], log: inout [Int]) -> [Int] {
    let total = values.reduce(0, +)
    let scaled = total == 0 ? values : values.map { $0 * 100 / total }
    log.append(scaled.count)
    return scaled
}
