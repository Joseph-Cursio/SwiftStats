/// A count a generator wrote, shared without isolation.
nonisolated(unsafe) public var generatedCount = 0

/// A worker a generator wrote, which no test runs. Its stored-property
/// initialiser is coverage attached to the type.
public final class GeneratedWorker: @unchecked Sendable {
    /// The work done so far.
    public var tally = 0

    /// A new worker.
    public init() {}

    /// `value`, unwrapped.
    public func work(_ value: Int?) -> Int {
        value!
    }
}
