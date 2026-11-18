/// A documented public store.
public actor Store {
    public var items: [String] = []
    var cache: [String: Int]!

    /// Loads the items.
    public func load() async -> [String] {
        precondition(items.count < 1_000)
        return items
    }

    func refresh() {
        Task { await self.reload() }
    }

    private func reload() async { }
}

@MainActor
public final class Screen {
    public var title: String!

    public init() { }

    func show() {
        let pointer = unsafe UnsafeRawPointer(bitPattern: 1)
        _ = pointer
    }
}

open class Base { }
