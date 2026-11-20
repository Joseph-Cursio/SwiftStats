public struct Ledger {
    public struct Entry: Equatable {
        let amount: Int
    }
}

// `Entry` alone names no package type (only `Ledger.Entry`): no pair.
extension Entry: Hashable {}

// A protocol is never a subject, nor is a protocol it extends.
public protocol Model: Equatable & Codable {}

extension Model: Hashable {}

// A conformance through a package protocol is not stored.
public struct Profile: Model {
    let name: String
}

public enum Tier: Int {
    case low
}
