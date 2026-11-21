/// Crash markers in functions, on lines the tests ran and lines they didn't.
public enum Crash {
    /// Run by the tests: its force unwrap's line ran.
    public static func unwrapped(_ value: Int?) -> Int {
        value!
    }

    /// Run by no test: nothing of it ran.
    public static func neverRun(_ value: Int?) -> Int {
        value!
    }

    /// Run with a value, so the `else` on the force unwrap's line didn't
    /// run though the line did: a partly run line.
    public static func fallback(_ value: Int?, _ other: Int?) -> Int {
        guard let value else { return other! }
        return value
    }

    /// Run with `flag` false: the force unwrap's own line didn't run.
    public static func branch(_ value: Int?, _ flag: Bool) -> Int {
        if flag {
            return value!
        }
        return 0
    }

    /// Run by no test; its implicitly unwrapped parameter is on a line no
    /// code region covers.
    public static func neverRunSignature(
        _ value: Int!
    ) -> Int {
        0
    }

    /// Run by the tests; its implicitly unwrapped parameter is on a line
    /// no code region covers.
    public static func ranSignature(
        _ value: Int!
    ) -> Int {
        1
    }

    /// Its force unwrap is in an inactive `#if` branch.
    public static func inactive(_ value: Int?) -> Int {
        #if RISKY_NEVER_SET
        return value!
        #else
        return 2
        #endif
    }

    /// Run by the tests; the function nested in it isn't, though its one
    /// line carries the outer function's count.
    public static func outer(_ value: Int?) -> Int {
        func inner(_ other: Int?) -> Int { other! }
        return value ?? 3
    }

    /// Run by the tests: two force unwraps on one line that ran.
    public static func pair(_ first: Int?, _ second: Int?) -> Int {
        first! + second!
    }

    /// Run by no test: a trap, which the signal leaves out.
    public static func unreachable() -> Never {
        fatalError("unreachable")
    }
}
