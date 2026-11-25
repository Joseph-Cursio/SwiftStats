/// A class with an `init`, a `deinit` and two methods.
public final class Session {
    /// The session's name.
    public let name: String

    /// A session named `name`.
    public init(name: String) {
        self.name = name
    }

    deinit {
        print("closing")
    }

    /// Opens the session.
    public func open() -> String {
        "open " + name
    }

    /// Closes the session.
    public func close() -> String {
        "close " + name
    }
}

/// A version with a custom `==`.
public struct Version: Equatable {
    /// The major number.
    let major: Int

    /// A version of `major`.
    public init(major: Int) {
        self.major = major
    }

    /// Versions are equal when their major numbers are.
    public static func == (lhs: Version, rhs: Version) -> Bool {
        lhs.major == rhs.major
    }
}
