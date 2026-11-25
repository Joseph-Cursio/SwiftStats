//
//  IndexHarness+DeadButTested.swift
//  SwiftStatsCoreTests
//
//  What dead but tested states on the Index fixture (M7, design §8.2):
//  its rule with the functions funnel of the fixture's 93 production
//  functions, the declarations funnel of the `production` run's eight
//  unused production entries (five functions, the type `Unused`, its
//  extension, the unused computed property), and outskirts entries made
//  by hand to add to the fixture's results.
//

@testable import SwiftStatsCore

extension IndexHarness {
    /// The fixture's unused production declarations, as the `production`
    /// run reports them with the index: five functions, the type `Unused`,
    /// its extension and the computed property, covering the nine
    /// production-dead functions.
    static let declarationsFunnel = "8 unused production declarations = 5 function entries matching a record + 0 "
        + "function entries matching no record + 1 type entries + 1 extension entries + 1 property entries with "
        + "accessor records + 0 others (parameters, imports, enum cases, stored properties, typealiases); 9 = the "
        + "distinct records F, T, E and V cover"
    /// The declarations funnel's D clause, which states no sum of numbers.
    static let coveredClause = "9 = the distinct records F, T, E and V cover"
    /// The fixture's production functions.
    private static let productionFunctions = 93
    /// Of those, the functions the `production` run's entries cover with
    /// the index.
    private static let productionDead = 9
    /// The parts of the production-dead functions with no mutant that ran,
    /// in the funnel's order.
    private static let unrunTerms = [
        "only not covered or no coverage",
        "only build errors",
        "no mutant",
        "only survived or timed out in a run with coverage off"
    ]

    /// The functions funnel of the fixture's production functions, `dead`
    /// of them production-dead, with `listed` listed, `partial` in files
    /// without full results and the rest counted in `unrun`'s order (only
    /// not covered or no coverage, only build errors, no mutant, only
    /// survived or timed out with coverage off).
    static func functionsFunnel(listed: Int, partial: Int, unrun: [Int], dead: Int) -> String {
        let total = unrun.reduce(0, +)
        let parts = zip(unrun, unrunTerms).map { "\($0) \($1)" }.joined(separator: " + ")
        let used = productionFunctions - dead
        return "\(productionFunctions) production functions = \(dead) production-dead + \(used) used; \(dead) = "
            + "\(listed) listed + \(total) with no mutant that ran + \(partial) in files without full mutation "
            + "results (unresolved or unlisted); \(total) = " + parts
    }

    /// Dead but tested's rule with the index: the fixture's nine
    /// production-dead functions, `listed` listed, `partial` in files
    /// without full results and the rest counted in `unrun`'s order, and
    /// the fixture's declarations funnel.
    static func deadButTestedRule(listed: Int, partial: Int, unrun: [Int]) -> String {
        let functions = functionsFunnel(listed: listed, partial: partial, unrun: unrun, dead: productionDead)
        return DeadButTested.rule + "; " + functions + "; " + declarationsFunnel
    }

    /// An unused production entry of the `production` run at `ordinal`,
    /// listed under `TestOnly.swift`'s file, covering no record.
    static func deadEntry(_ ordinal: Int, kind: String, name: String, ids: [String]) -> DeadCodeDeclaration {
        DeadCodeDeclaration(
            run: .production,
            ordinal: ordinal,
            hint: DeadCodeMapper.unusedHint,
            hintText: nil,
            kind: kind,
            name: name,
            accessibility: "internal",
            attributes: [],
            modifiers: [],
            ids: ids,
            modules: ["IndexCore"],
            entryClass: .production,
            file: "Sources/IndexCore/TestOnly.swift",
            line: 1,
            column: 1,
            place: .file,
            owner: nil,
            module: "IndexCore",
            strippedLines: nil
        )
    }

    /// `entry` with `hint` and of `entryClass`.
    static func retagged(
        _ entry: DeadCodeDeclaration,
        hint: String,
        entryClass: PeripheryEntryClass
    ) -> DeadCodeDeclaration {
        DeadCodeDeclaration(
            run: entry.run,
            ordinal: entry.ordinal,
            hint: hint,
            hintText: entry.hintText,
            kind: entry.kind,
            name: entry.name,
            accessibility: entry.accessibility,
            attributes: entry.attributes,
            modifiers: entry.modifiers,
            ids: entry.ids,
            modules: entry.modules,
            entryClass: entryClass,
            file: entry.file,
            line: entry.line,
            column: entry.column,
            place: entry.place,
            owner: entry.owner,
            module: entry.module,
            strippedLines: entry.strippedLines
        )
    }
}
