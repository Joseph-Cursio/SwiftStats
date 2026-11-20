import Core
import PropertyLawKit
import Testing

// `Money` here is the suite's own type, not Core's.
struct KitEvidenceRecorderTests {
    struct Money: Hashable {
        let cents: Int
    }

    @Test func records() async throws {
        try await checkHashablePropertyLaws(for: Money.self, using: Money.gen())
    }
}

// A test-target extension makes no pair; Bare gains a test-only Equatable.
extension Bare: Equatable {}

// Function-local types are the test's own, not Core's Point and Pin, even
// nested in another local type.
struct LocalTypeTests {
    @Test func locals() async throws {
        struct Point: Equatable {
            let x: Int
        }
        struct Outer {
            struct Pin: Hashable {}

            func check() async throws {
                try await checkHashablePropertyLaws(for: Pin.self, using: Pin.gen())
            }
        }
        try await checkEquatablePropertyLaws(for: Point.self, using: Point.gen())
        try await Outer().check()
    }
}
