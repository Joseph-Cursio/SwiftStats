//
//  CouplingSignalHarness.swift
//  SwiftStatsCoreTests
//
//  A small package scanned with hand-made index results and a hand-made
//  history, for hidden coupling (M7, design §8.1): a library `Lib` with
//  types, free functions, an `Array` extension and a generated file; a
//  library `Other` depending on `Lib`, declaring a type of a path `Lib`
//  declares too and extending `Lib`'s types, by plain, qualified and
//  typealias heads; a library `Third` declaring one of those as well; a
//  library `App`, depending on none, extending another module's type of
//  a name only `Lib` declares; and a test target `LibTests`. Every record
//  gets a USR shaped as Swift mangles one: its context's (the extended
//  type's, then the extension's module and `E`, for an extension
//  member), then its name; `unseen()` has none and `bridged()` a `c:`
//  one. The index lists the production types, with USRs of the same
//  shape, and the family references and family type references a test
//  gives; the history holds the pairs a test gives, cut at a
//  `coupling.min_support` of 3. The snapshot is stored and read back, so
//  the signal reads it as a report would.
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// Stores the small package with hand-made index results and history.
enum CouplingSignalHarness {
    /// The hand-made index facts and history pairs.
    struct Facts {
        /// The history's coupling pairs, in its order.
        var pairs: [CouplingPair] = []
        /// The family references, each family named by its root's short
        /// name (such as `alpha`).
        var references: [IndexFamilyReference] = []
        /// The family type references, each family named by its root's
        /// short name.
        var typeReferences: [IndexFamilyTypeReference] = []
        /// The collector, history or index, that didn't run; nil when both
        /// ran.
        var missing: String?
    }

    /// The package's files.
    static let files = [
        "Sources/Lib/Lib.swift": """
            struct Shared {
                func alpha() -> Int { 1 }
                func beta() -> Int { 2 }
                struct Nested {
                    func gamma() -> Int { 3 }
                }
                func bridged() -> Int { 18 }
            }
            struct Holder {
                func zeta() -> Int { 4 }
            }
            struct Box {
                func theta() -> Int { 5 }
            }
            struct Twin {
                func iota() -> Int { 6 }
            }
            func caller() -> Int { 7 }
            func callee() -> Int { 8 }
            func throughProtocol() -> Int { 9 }
            func witnessing() -> Int { 10 }
            func typeUser() -> Int { 11 }
            func unseen() -> Int { 12 }
            func loneOne() -> Int { 13 }
            func loneTwo() -> Int { 14 }
            func loneThree() -> Int { 15 }
            extension Array {
                func firstPart() -> Int { 16 }
                func secondPart() -> Int { 17 }
            }

            """,
        "Sources/Lib/Made.generated.swift": """
            func made() -> Int { 1 }

            """,
        "Sources/Other/Other.swift": """
            struct Shared {
                func delta() -> Int { 1 }
            }
            struct Holder {
                struct Inside {
                    func epsilon() -> Int { 2 }
                }
            }
            extension Box {
                func eta() -> Int { 3 }
            }
            extension Twin {
                func kappa() -> Int { 4 }
            }
            extension Lib.Box {
                func mu() -> Int { 5 }
            }
            typealias Crate = Box
            extension Crate {
                func nu() -> Int { 6 }
            }

            """,
        "Sources/App/App.swift": """
            extension Box {
                func audit() -> Int { 1 }
            }

            """,
        "Sources/Third/Third.swift": """
            struct Twin {
                func lambda() -> Int { 1 }
            }

            """,
        "Tests/LibTests/LibTests.swift": """
            func testIt() {}

            """
    ]

    /// The package's targets.
    static let targets = [
        DescribedTarget(
            name: "App",
            type: "library",
            moduleType: "SwiftTarget",
            path: "Sources/App",
            sources: ["App.swift"]
        ),
        DescribedTarget(
            name: "Lib",
            type: "library",
            moduleType: "SwiftTarget",
            path: "Sources/Lib",
            sources: ["Lib.swift", "Made.generated.swift"]
        ),
        DescribedTarget(
            name: "LibTests",
            type: "test",
            moduleType: "SwiftTarget",
            path: "Tests/LibTests",
            sources: ["LibTests.swift"],
            targetDependencies: ["Lib"]
        ),
        DescribedTarget(
            name: "Other",
            type: "library",
            moduleType: "SwiftTarget",
            path: "Sources/Other",
            sources: ["Other.swift"],
            targetDependencies: ["Lib"]
        ),
        DescribedTarget(
            name: "Third",
            type: "library",
            moduleType: "SwiftTarget",
            path: "Sources/Third",
            sources: ["Third.swift"]
        )
    ]

    /// The production types the index lists, by target and path.
    static let types = [
        ("Lib", "Box"), ("Lib", "Holder"), ("Lib", "Shared"), ("Lib", "Shared.Nested"), ("Lib", "Twin"),
        ("Other", "Holder"), ("Other", "Holder.Inside"), ("Other", "Shared"), ("Third", "Twin")
    ]

    /// The type each extension member's USR names as its context, by the
    /// member's name, as its target, its type path: the type the
    /// extension's head means, whatever it spells.
    static let extended = [
        "audit": ("Logging", "Box"), "eta": ("Lib", "Box"), "firstPart": ("Swift", "Array"),
        "kappa": ("Lib", "Twin"), "mu": ("Lib", "Box"), "nu": ("Lib", "Box"), "secondPart": ("Swift", "Array")
    ]

    /// The support history cut the pairs at.
    static let minimumSupport = 3

    /// The pair of the families named `first` and `second` (short names),
    /// with `support` and each family's changes, as history writes it.
    static func pair(
        _ first: String,
        _ second: String,
        support: Int,
        changes: (Int, Int),
        in snapshot: StoredSnapshot
    ) throws -> CouplingPair {
        let lhs = try #require(snapshot.functions.first { $0.name == first })
        let rhs = try #require(snapshot.functions.first { $0.name == second })
        return CouplingPair(
            familyA: lhs.key,
            fileA: lhs.file,
            familyB: rhs.key,
            fileB: rhs.file,
            support: support,
            changesA: changes.0,
            changesB: changes.1
        )
    }

    /// The package scanned at commit `c1`, stored in `store` and read back
    /// without index results or history: its records, for naming pairs.
    static func plain(in store: SnapshotStore) throws -> StoredSnapshot {
        let package = try TemporaryPackage(files, targets: targets)
        defer { package.remove() }
        return try store.load(id: try store.save(try SnapshotHarness.scan(package, commit: "c1")))
    }

    /// The package scanned at commit `c1`, holding index results and a
    /// history with `facts`, stored in `store` and read back.
    static func stored(_ facts: Facts, in store: SnapshotStore) throws -> StoredSnapshot {
        let package = try TemporaryPackage(files, targets: targets)
        defer { package.remove() }
        let scanned = try SnapshotHarness.scan(package, commit: "c1")
        let index = try index(of: scanned, facts: facts)
        return try store.load(id: try store.save(snapshot(scanned, index: index, facts: facts)))
    }
}
