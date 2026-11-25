/// A payload named as `Foundation.Data` is: `IndexCore` declares
/// `measure(_:)` once for each, in two files that import one module each, so
/// the two overloads have one key and two USRs.
public struct Data {
    /// The payload's size.
    public let size: Int

    /// A payload of `size`.
    public init(size: Int) {
        self.size = size
    }
}
