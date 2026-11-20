import PropertyLawKit
@testable import Core

// A refactor writeout: Size is a Semigroup only in test builds.
extension Size: Semigroup {
    public static func combine(_ lhs: Size, _ rhs: Size) -> Size {
        lhs
    }
}
