import Foundation
@testable import SwiftStatsCore
import Testing

/// Tests per public function (M5), a heuristic: a test counts when its
/// target's own test process ran the function and its body names it, by
/// the rule of the function's kind. Checked on a small package with two
/// libraries, two test targets and a hand-written export, and on the Coverage fixture's
/// recorded real export.
@Suite("Coverage test links")
struct CoverageLinkTests {
    /// What the mapping says about a record's tests.
    private struct Linked: Equatable, CustomStringConvertible {
        /// The link rule.
        let link: CoverageLink?
        /// The linked tests.
        let tests: Int?

        var description: String {
            "\(link?.rawValue ?? "-") \(tests.map(String.init) ?? "-")"
        }
    }

    /// Each record's link rule and linked tests in `report`, by key.
    private static func linked(_ report: CoverageReport) -> [String: Linked] {
        Dictionary(uniqueKeysWithValues: report.records.map { ($0.key, Linked(link: $0.link, tests: $0.linkedTests)) })
    }

    @Test("""
        a concrete type's member counts a test of a target that ran it whose body names the member (a call of the \
        type for an initialiser) and the type, or whose file is named for the type, even when another module \
        declares a protocol of the type's name; a subscript counts the type alone; an operator is never named
        """)
    func members() throws {
        let linked = Self.linked(try LinkPackage.report())

        // `Kit` declares a protocol `Bag`, but `Lib`'s `Bag` is a struct.
        // `init`: `growsWithType` and `otherGrow` call `Bag(…)`, and both
        // targets ran it.
        #expect(linked["Lib::Bag::init(items: [Int])"] == Linked(link: .member, tests: 2))
        // `grow`: `growsByName` through its file `BagTests.swift`,
        // `growsWithType` through `Bag`; not `growsWithoutType`, which
        // names no `Bag`, nor `otherGrow`, whose target didn't run it.
        #expect(linked["Lib::Bag::func grow() -> Int"] == Linked(link: .member, tests: 2))
        #expect(linked["Lib::Bag::var total: Int { get }"] == Linked(link: .member, tests: 1))
        #expect(linked["Lib::Bag::func index(of: Int) -> Int?"] == Linked(link: .member, tests: 1))
        #expect(linked["Lib::Bag::subscript(offset: Int) -> Int"] == Linked(link: .subscript, tests: 2))
        #expect(linked["Lib::Bag::static func +(lhs: Bag, rhs: Bag) -> Bag"] == Linked(link: .member, tests: 0))
        // Run by no test process: no test counts, but it has data.
        #expect(linked["Lib::Bag::func never() -> Int"] == Linked(link: .member, tests: 0))
        // A container's accessors count through the type's name; only the
        // setter ran.
        #expect(linked["Lib::Box::subscript(_: Int) -> Int / { get }"] == Linked(link: .subscript, tests: 0))
        #expect(linked["Lib::Box::subscript(_: Int) -> Int / { set }"] == Linked(link: .subscript, tests: 1))
    }

    @Test("""
        a member matching a requirement of a standard protocol its type declares, in any file of the module, \
        through a refinement or a package protocol, is a witness with no tests counted; one matching a requirement \
        of a protocol its type doesn't conform to, as its own module declares it, is a member
        """)
    func witnesses() throws {
        let linked = Self.linked(try LinkPackage.report())
        let witness = Linked(link: .witness, tests: nil)

        #expect(linked["Lib::Bag::var startIndex: Int { get }"] == witness)
        #expect(linked["Lib::Bag::func index(after: Int) -> Int"] == witness)
        #expect(linked["Lib::Bag::func hash(into: inout Hasher)"] == witness)
        #expect(linked["Lib::Bag::static func ==(lhs: Bag, rhs: Bag) -> Bool"] == witness)
        #expect(linked["Lib::Bag::var endIndex: Int { get }"] == witness)
        #expect(linked["Lib::Bag::subscript(_: Int) -> Int"] == witness)
        #expect(linked["Lib::Loop::func index(before: Int) -> Int"] == witness)
        #expect(linked["Lib::Plain::func next() -> Int?"] == Linked(link: .member, tests: 0))
        // `Loop` conforms to `Lib`'s `Ring`, not to `Kit`'s, which refines
        // `Hashable`.
        #expect(linked["Lib::Loop::func hash(into: inout Hasher)"] == Linked(link: .member, tests: 0))
    }

    @Test("""
        a free function and a protocol extension member count a test of a target that ran them whose body names \
        them, a protocol extension's initialiser or subscript one that names the protocol; a container, a \
        non-public or generated function has no link, and one without data no tests
        """)
    func othersAndNulls() throws {
        let report = try LinkPackage.report()
        let linked = Self.linked(report)

        #expect(linked["Lib::func helper() -> Int"] == Linked(link: .function, tests: 2))
        #expect(linked["Lib::Sequence::func tally() -> Int"] == Linked(link: .extensionMember, tests: 1))
        #expect(linked["Lib::Ring::func spin() -> Int"] == Linked(link: .extensionMember, tests: 1))
        // `spinsRing` names `Ring`; `growsWithoutType` names only `Loop`.
        #expect(linked["Lib::Ring::init(spun: Int)"] == Linked(link: .extensionMember, tests: 1))
        #expect(linked["Lib::Ring::subscript(spin: Int) -> Int"] == Linked(link: .extensionMember, tests: 1))
        #expect(linked["Lib::Box::subscript(_: Int) -> Int"] == Linked(link: nil, tests: nil))
        #expect(linked["Lib::Bag::func hidden() -> Int"] == Linked(link: nil, tests: nil))
        #expect(linked["Lib::func generated() -> Int"] == Linked(link: nil, tests: nil))
        let absent = try #require(report.records.first { $0.key == "Lib::func absent() -> Int" })
        #expect(absent.reason == CoverageMapper.noData)
        #expect(Linked(link: absent.link, tests: absent.linkedTests) == Linked(link: .function, tests: nil))
    }

    @Test("the Coverage fixture's public functions get the links worked out by hand from its tests")
    func fixture() throws {
        let report = try #require(try CoverageFixture.report().coverage)
        let linked = Self.linked(report).filter { $0.value.link != nil }
        let member = { (tests: Int) in Linked(link: .member, tests: tests) }
        let function = { (tests: Int?) in Linked(link: .function, tests: tests) }

        #expect(linked == [
            "Probe::Box::init()": member(1),
            "Probe::Box::subscript(_: Int) -> Int / { get }": Linked(link: .subscript, tests: 1),
            "Probe::Box::subscript(_: Int) -> Int / { set }": Linked(link: .subscript, tests: 0),
            "Probe::Box::var both: Int { get }": member(1),
            "Probe::Box::var both: Int { set }": member(0),
            "Probe::Box::var doubled: Int { get }": member(1),
            "Probe::Box::var watched { didSet }": member(1),
            "Probe::Box::var watched { willSet }": member(1),
            // Run through `Settings`, but no test names `Clamped`.
            "Probe::Clamped::init(wrappedValue: Int)": member(0),
            "Probe::Clamped::var wrappedValue: Int { get }": member(0),
            "Probe::Clamped::var wrappedValue: Int { set }": member(0),
            "Probe::Counter::func add(_: [Int])": member(1),
            // `addsAndDoubles` and the XCTest `testEmptyCounter`.
            "Probe::Counter::func doubled() -> Int": member(2),
            "Probe::Counter::init()": member(2),
            "Probe::Settings::init()": member(1),
            "Probe::func anyLarge(_: [Int]) -> Bool": function(1),
            "Probe::func bomFirst() -> Int": function(1),
            "Probe::func bomSecond() -> Int": function(1),
            "Probe::func describe(_: Int) -> String": function(1),
            "Probe::func describe(_: String) -> String": function(0),
            "Probe::func firstSecret() -> Int": function(1),
            "Probe::func fromHelper() -> Int": function(1),
            "Probe::func lefts(_: [Int]) -> [Side]": function(1),
            "Probe::func mode() -> String #if !(DEBUG)": function(nil),
            "Probe::func mode() -> String #if DEBUG": function(1),
            "Probe::func neverCalled() -> Int": function(0),
            // Run by `SwiftTestKitTests` alone, whose `onlyKitRuns` names it.
            "Probe::func onlyKit() -> Int": function(1),
            "Probe::func outer(_: Bool) -> Int": function(1),
            "Probe::func platform() -> String": function(1),
            "Probe::func sameLine() -> Int": function(1),
            "Probe::func secondSecret() -> Int": function(0),
            "Probe::func withDefault(_: (Int) -> Int) -> Int": function(1),
            "Unlinked::func unlinked() -> Int": function(nil)
        ])
    }
}
