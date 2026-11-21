/// An integer described.
public func describe(_ value: Int) -> String {
    "int \(value)"
}

/// A string described; no test runs it.
public func describe(_ value: String) -> String {
    "string \(value)"
}

#if DEBUG
/// The build mode, in a debug build.
public func mode() -> String { "debug" }
#else
/// The build mode, in a release build.
public func mode() -> String { "release" }
#endif

/// The platform, with an inactive branch in its body.
public func platform() -> String {
    #if os(Linux)
    return "linux"
    #else
    return "other"
    #endif
}
