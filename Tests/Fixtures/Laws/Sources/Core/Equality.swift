// `==` makes Equatable custom.
public struct Point: Equatable {
    let x: Int

    public static func == (lhs: Point, rhs: Point) -> Bool {
        lhs.x == rhs.x
    }
}

// Swift.Equatable is Equatable, synthesised.
public struct Size: Swift.Equatable {
    let width: Int
}

// A class writes its own equality and hashing, whatever it declares.
public final class Handle: Equatable, Hashable {
    let id = 0
}

// hashValue, hash(into:) and == each make Hashable custom.
public struct Key: Hashable {
    public var hashValue: Int { 0 }
}

public struct Slot: Hashable {
    public func hash(into hasher: inout Hasher) {}
}

public struct Pin: Hashable {
    public static func == (lhs: Pin, rhs: Pin) -> Bool { true }
}

// A test-target extension adds Equatable: no pair, one test-only conformance.
public struct Bare {}

// A local type is never a subject, and a check outside a test target runs nothing.
public func makeLocal() async throws -> Bool {
    struct Local: Equatable {}
    try await checkEquatablePropertyLaws(for: Handle.self, using: Handle.gen())
    return Local() == Local()
}
