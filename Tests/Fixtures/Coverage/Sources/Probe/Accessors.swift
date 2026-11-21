/// Storage with accessors of every shape.
public struct Box {
    /// The stored value.
    public var storage = 0
    /// A one-line getter and setter; the tests run only the getter.
    public var both: Int { get { storage } set { storage = newValue } }
    /// One-line observers; the tests run both.
    public var watched = 0 { willSet { storage = newValue } didSet { storage += 1 } }
    /// An implicit getter.
    public var doubled: Int { storage * 2 }
    /// A lazy value, whose getter and closure share a start.
    public lazy var cached: Int = { storage + 1 }()
    /// A one-line getter and setter; the tests run only the getter.
    public subscript(index: Int) -> Int { get { storage + index } set { storage = newValue - index } }

    /// An empty box.
    public init() {}
}
