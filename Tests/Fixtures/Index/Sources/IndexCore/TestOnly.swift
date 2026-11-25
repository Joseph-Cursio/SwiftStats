/// A public function only tests call: library API.
public func publicOnlyTests() -> Int {
    3
}

/// An internal function only a test calls.
func onlyTestsCall() -> Int {
    let base = 20
    return base + 1
}

/// An internal function nothing calls.
func neverCalled() -> Int {
    4
}

/// The arguments of a parameterized test.
public func cases() -> [Int] {
    [1, 2, 3]
}

#if INDEX_FIXTURE_FLAG
/// A function under a flag the manifest never defines.
func flagged() -> Int {
    5
}
#endif

#if DEBUG
/// The build mode, active in debug.
public func buildMode() -> String {
    "debug"
}
#else
/// The build mode, inactive in debug.
public func buildMode() -> String {
    "release"
}
#endif
