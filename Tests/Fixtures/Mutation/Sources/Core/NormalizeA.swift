/// `values` as whole percentages of their total, with how many it gave
/// appended to `log`. Tested exactly. The first copy of a clone pair
/// whose second, `normalizedB`, no test runs: uneven clone testing. The
/// copy's statements end in a call whose result is discarded, so its
/// RemoveSideEffects mutant sits past the copy's last character.
public func normalizedA(_ values: [Int], log: inout [Int]) -> [Int] {
    let total = values.reduce(0, +)
    let scaled = total == 0 ? values : values.map { $0 * 100 / total }
    log.append(scaled.count)
    return scaled
}
