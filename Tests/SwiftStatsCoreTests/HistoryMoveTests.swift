import Foundation
@testable import SwiftStatsCore
import Testing

/// Files moved to another target (PRD §7.13): the link is a module-moved
/// key however git saw the move, and the other history rules still see
/// the moved file's old functions.
@Suite("Moves across targets")
struct HistoryMoveTests {
    /// The first day's date, as history writes it.
    private static let dayZero = HistoryCollector.date(HistoryRepository.dayZero)

    /// A seven-line function `name` whose return adds `last`.
    private static func body(_ name: String, last: String) -> String {
        """
        public struct Shape {
            func \(name)() -> Int {
                let first = 1
                let second = 2
                let third = 3
                let fourth = 4
                let fifth = 5
                let sixth = 6
                return first + second + third + fifth + sixth + \(last)
            }
        }

        """
    }

    @Test("a private member moved to another target is linked by a module-moved key, like a public one")
    func privateMember() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            "Sources/Old/Shape.swift": "struct Shape {\n    private func helper() -> Int {\n        1\n    }\n}\n",
            "Sources/New/Keep.swift": "func keep() {}\n"
        ])
        try repository.commit("Add the shape", day: 0)
        try repository.move("Sources/Old/Shape.swift", to: "Sources/New/Shape.swift")
        try repository.commit("Move it to New", day: 4)

        let helper = try #require(try repository.history().family("func helper()"))

        #expect(helper.allChanges == 1)
        #expect(helper.firstSeen == Self.dayZero)
        #expect(helper.tracedBy == .moduleMovedKey)
    }

    @Test("a function renamed and edited while its file moves to another target is matched by a similar body")
    func renameDuringMove() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            "Sources/Old/Sum.swift": Self.body("total", last: "fourth"),
            "Sources/New/Keep.swift": "func keep() {}\n"
        ])
        try repository.commit("Add the sum", day: 0)
        try repository.move("Sources/Old/Sum.swift", to: "Sources/New/Sum.swift")
        try repository.write(["Sources/New/Sum.swift": Self.body("sum", last: "fourth * 2")])
        try repository.commit("Move and rename the sum", day: 4)

        let sum = try #require(try repository.history().family("New::Shape::func sum()"))

        #expect(sum.allChanges == 2)
        #expect(sum.firstSeen == Self.dayZero)
        #expect(sum.tracedBy == .similarBody)
    }

    @Test("declarations sharing a line keep their own histories through a move to another target")
    func sharedLine() throws {
        let repository = try HistoryRepository()
        defer { repository.remove() }
        try repository.write([
            "Sources/Old/Point.swift": "struct Point { init() {}; func norm() -> Int { 0 } }\n",
            "Sources/New/Keep.swift": "func keep() {}\n"
        ])
        try repository.commit("Add the point", day: 0)
        try repository.write(["Sources/Old/Point.swift": "struct Point { init() {}; func norm() -> Int { 1 } }\n"])
        try repository.commit("Change norm", day: 1)
        try repository.move("Sources/Old/Point.swift", to: "Sources/New/Point.swift")
        try repository.commit("Move it to New", day: 4)
        let history = try repository.history()

        let norm = try #require(history.family("New::Point::func norm()"))
        let initializer = try #require(history.family("New::Point::init()"))

        #expect(norm.allChanges == 2)
        #expect(initializer.allChanges == 1)
        #expect(initializer.firstSeen == Self.dayZero)
    }
}
