#if canImport(Darwin)
import Darwin
#endif

public final class Resource {
    private var handle: Int

    public init(handle: Int) {
        self.handle = handle
    }

    deinit {
        handle = 0
    }

    #if DEBUG
    public func describe() -> String { "debug \(handle)" }
    #else
    public func describe() -> String { "\(handle)" }
    #endif

    public func load() async throws -> Int { handle }
    public func load() -> Int { handle }
}

public actor Counter {
    private var count = 0

    public func increment() -> Int {
        count += 1
        return count
    }
}

private func secretHelper() -> Int { 42 }

fileprivate extension String {
    func shouted() -> String { uppercased() }
}

public func generic<Element: Comparable>(_ items: [Element]) -> Element? where Element: Sendable {
    items.max()
}
