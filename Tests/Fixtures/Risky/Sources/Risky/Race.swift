/// A counter whose method the tests ran.
public final class Worked: @unchecked Sendable {
    /// Times worked.
    public var count = 0

    /// A new counter.
    public init() {}

    /// Counts once.
    public func work() {
        count += 1
    }
}

/// A counter the tests built, and nothing more.
public final class OnlyBuilt: @unchecked Sendable {
    /// Times worked.
    public var count = 0

    /// A new counter.
    public init() {}

    /// Counts once.
    public func work() {
        count += 1
    }
}

/// A worker nothing of which ran.
public final class Untouched: @unchecked Sendable {
    /// A new worker.
    public init() {}

    /// Works.
    public func work() -> Int {
        4
    }
}

/// A class with no code of its own.
public final class Bare: @unchecked Sendable {}

/// Shared state behind a static method the tests ran.
public enum Tally {
    /// The shared count.
    nonisolated(unsafe) public static var shared = 0

    /// Counts once.
    public static func bump() {
        shared += 1
    }
}

/// Settings parsed when built.
public struct Settings {
    /// A name set later.
    public var name: String!
    /// A number parsed by the stored property's initialiser.
    public let parsed = try! Settings.parse("5")

    /// New settings.
    public init() {}

    /// `text` as a number.
    public static func parse(_ text: String) throws -> Int {
        guard let value = Int(text) else {
            throw ParseError.notANumber
        }
        return value
    }
}

/// Settings no test builds.
public struct UnbuiltSettings {
    /// A number parsed by the stored property's initialiser.
    public let parsed = try! Settings.parse("6")

    /// New settings.
    public init() {}
}

/// Why text didn't parse.
public enum ParseError: Error {
    /// It wasn't a number.
    case notANumber
}

/// A box whose only code is its stored property's initialiser, which ran
/// when the tests built it.
public final class Boxed: @unchecked Sendable {
    /// The boxed value.
    public var value = 0
}

/// A counter the tests built, and nothing more; its deinitialiser ran when
/// the built instance was released.
public final class Released: @unchecked Sendable {
    /// Times worked.
    public var count = 0

    /// A new counter.
    public init() {}

    deinit {
        count = -1
    }

    /// Counts once.
    public func work() {
        count += 1
    }
}
