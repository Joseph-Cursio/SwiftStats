import Core
import PropertyLawKit

// The package declares its own Group, so Group is not the kit's: no pair.
public protocol Group {}

public struct Team: Group, Equatable {
    let members: Int
}

// Another Tier, so `Tier` alone is ambiguous from the tests.
public enum Tier: String {
    case gold
}

// Extensions in another module, written bare and module-qualified.
extension Point: Hashable {}

extension Core.Bare: Identifiable {
    public var id: Int { 0 }
}
