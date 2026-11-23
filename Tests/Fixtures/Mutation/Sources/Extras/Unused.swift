/// How far apart `left` and `right` are. Run by no test, in a module with
/// little test code: genuinely under-tested.
public func unused(_ left: Int, _ right: Int) -> Int {
    if left > right {
        return left - right
    }
    return right - left
}
