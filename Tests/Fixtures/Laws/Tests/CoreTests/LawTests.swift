import Core
import Extras
import PropertyLawKit
import Testing

struct LawTests {
    @Test func money() async throws {
        try await checkComparablePropertyLaws(for: Money.self, using: Money.gen())
        try await checkSemigroupPropertyLaws(using: Money.gen())
    }

    @Test func numbers() async throws {
        try await checkFloatingPointPropertyLaws(for: Fixed.self, using: Fixed.gen())
        try await checkHashablePropertyLaws(for: Grade.self, using: Grade.gen(), laws: .ownOnly)
        try await PropertyLawKit.checkHashablePropertyLaws(for: Rank.self, using: Rank.gen())
        try await checkEquatablePropertyLaws(for: Ledger.Entry.self, using: Ledger.Entry.gen())
    }

    @Test func ambiguous() async throws {
        try await checkRawRepresentablePropertyLaws(for: Tier.self, using: Tier.gen())
    }

    @Test func unresolved() async throws {
        try await checkEquatablePropertyLaws(using: generator)
        try await checkAll(Point.self)
        try await checkValueSemanticPropertyLaws(for: Point.self)
        let text = "try await checkEquatablePropertyLaws(for: Point.self, using: Point.gen())"
        #expect(text.isEmpty == false)
    }

    func checkAll<T: Equatable>(_ type: T.Type) async throws {
        try await checkEquatablePropertyLaws(for: T.self, using: T.gen())
    }

    // A marker outside the discovery plugin's file is inert:
    // (checkEquatablePropertyLaws for Point suppressed by user marker)
}
