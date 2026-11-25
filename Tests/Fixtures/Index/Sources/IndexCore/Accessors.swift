/// Storage with every accessor shape the USR join tells apart.
public struct Storage {
    /// The stored values.
    var values = [1, 2, 3]
    /// A stored cache the observers and coroutines use.
    var cache = 0

    /// An empty storage.
    public init() {}

    /// A shorthand subscript: one record, whose getter the index defines at
    /// its `{` (a secondary accessor USR).
    public subscript(position: Int) -> Int {
        values[position]
    }

    /// A subscript with explicit `get` and `set`: accessor records, no
    /// secondary USR.
    public subscript(slot slot: Int) -> Int {
        get {
            values[slot]
        }
        set {
            values[slot] = newValue
        }
    }

    /// A shorthand computed property.
    public var count: Int {
        values.count
    }

    /// A computed property with explicit `get` and `set`.
    public var head: Int {
        get {
            values[0]
        }
        set {
            values[0] = newValue
        }
    }

    /// A stored property with `willSet` and `didSet`.
    public var observed = 0 {
        willSet {
            cache = newValue
        }
        didSet {
            cache += oldValue
        }
    }

    /// Explicit `_read` and `_modify`.
    public var coroutine: Int {
        _read {
            yield cache
        }
        _modify {
            yield &cache
        }
    }

    /// An unused computed property: outskirts lists it, its getter record
    /// follows.
    var unusedComputed: Int {
        values.count * 2
    }
}

/// A property with `unsafeAddress` and `unsafeMutableAddress`.
public struct Addressed {
    /// The memory the property reads and writes.
    let base: UnsafeMutablePointer<Int>

    /// Addressed storage over `base`.
    public init(base: UnsafeMutablePointer<Int>) {
        self.base = base
    }

    /// The value at `base`.
    public var value: Int {
        unsafeAddress {
            UnsafePointer(base)
        }
        unsafeMutableAddress {
            base
        }
    }
}

/// A property with an `init` accessor (raw subkind 1016 in the index).
public struct Initialized {
    /// The stored value the `init` accessor initializes.
    var stored: Int

    /// The value, initialized through its `init` accessor.
    public var value: Int {
        @storageRestrictions(initializes: stored)
        init(initialValue) {
            stored = initialValue
        }
        get {
            stored
        }
        set {
            stored = newValue
        }
    }

    /// A value of `value`.
    public init(value: Int) {
        self.value = value
    }
}
