/// Run by no test, so SwiftMutator makes none of its mutants and lists
/// them as not covered. `Core`'s test code isn't low, so it isn't
/// genuinely under-tested. The `since-unlisted` patch edits it alone.
public func neverCalled(_ value: Int) -> Int {
    if value > 10 {
        return value * 2
    }
    return value + 1
}
