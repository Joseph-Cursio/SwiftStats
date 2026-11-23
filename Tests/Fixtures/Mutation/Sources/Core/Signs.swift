/// The sign of `value`: 1, -1 or 0. Tested exactly, so every mutant is
/// killed: in no list. The `--since` patch renames its file.
public func sign(_ value: Int) -> Int {
    if value > 0 {
        return 1
    }
    return value == 0 ? 0 : -1
}
