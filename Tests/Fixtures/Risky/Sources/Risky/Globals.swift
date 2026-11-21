/// A global count, shared without isolation.
nonisolated(unsafe) public var globalCount = 0

/// A number parsed when first read, which no test does.
public let globalParsed = try! Settings.parse("7")
