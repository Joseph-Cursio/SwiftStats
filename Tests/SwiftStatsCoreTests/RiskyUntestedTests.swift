//
//  RiskyUntestedTests.swift
//  SwiftStatsCoreTests
//
//  Risky + untested (PRD §8, M5) on the Risky fixture: its real coverage
//  run, recorded, with SwiftProjectLint's markers faked at each risky line
//  and SwiftStats' own implicitly unwrapped optionals; every marker's
//  verdict, the generated file's markers left out, and the signal's exact
//  rows, counts and payloads.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Risky untested")
struct RiskyUntestedTests {
    /// The verdict text of `verdict`, as the tests write it.
    private static func text(_ verdict: MarkerVerdict) -> String {
        switch verdict {
        case .noData(let reason):
            "no data: \(reason)"

        case .tested(let partlyRun):
            partlyRun ? "tested, partly run" : "tested"

        case .untested:
            "untested"
        }
    }

    @Test("every marker gets the verdict of the first case that applies, and only production markers are judged")
    func verdicts() throws {
        let snapshot = try RiskyFixture.stored()
        let coverage = try #require(snapshot.coverage?.report)
        let judge = MarkerJudge(snapshot, coverage: coverage)
        let markers = RiskMarker.markers(in: snapshot.findings.filter(judge.isProduction))
        let crash = RiskyFixture.crash
        let race = RiskyFixture.race
        let globals = RiskyFixture.globals

        let verdicts = markers.map { marker in
            "\(marker.file):\(marker.line ?? 0) \(marker.rule): \(Self.text(judge.verdict(marker)))"
        }

        #expect(verdicts.sorted() == [
            // Case 1: a function no test bundle links, an inactive #if branch.
            "Sources/Orphan/Orphan.swift:3 forceUnwrap: no data: in a function with no coverage data",
            "\(crash):10 forceUnwrap: untested",
            // Case 3: a partly run line counts as tested.
            "\(crash):16 forceUnwrap: tested, partly run",
            "\(crash):23 forceUnwrap: untested",
            // Case 4: an unmapped signature line in a function that ran nothing.
            "\(crash):31 implicitlyUnwrappedOptional: untested",
            // Case 5: the same in a function that ran.
            "\(crash):39 implicitlyUnwrappedOptional: no data: on a line with no code region in a function that ran",
            "\(crash):47 forceUnwrap: no data: in an inactive #if branch",
            "\(crash):5 forceUnwrap: tested",
            // Case 3's override: the nested function ran nothing, though
            // its one line carries the outer function's count.
            "\(crash):56 forceUnwrap: untested",
            // Two findings on one line, without columns, are two markers.
            "\(crash):62 forceUnwrap: tested",
            "\(crash):62 forceUnwrap: tested",
            // Two untested markers in one function.
            "\(crash):72 forceUnwrap: untested",
            "\(crash):73 forceUnwrap: untested",
            // A tested and an untested marker in one function.
            "\(crash):79 forceUnwrap: tested",
            "\(crash):81 forceUnwrap: untested",
            "\(crash):88 forceCast: tested",
            // Globals hold no code region, so their file has no line data.
            "\(globals):2 nonisolatedUnsafe: no data: in a file with no coverage data",
            "\(globals):5 forceTry: no data: in a file with no coverage data",
            // Case 2: `work` ran; only the initialiser ran; nothing ran; no code.
            "\(race):16 uncheckedSendable: untested",
            "\(race):2 uncheckedSendable: tested",
            "\(race):30 uncheckedSendable: untested",
            "\(race):41 uncheckedSendable: no data: on a type with no coverage data",
            "\(race):46 nonisolatedUnsafe: tested",
            // A stored property without an initialiser holds no region.
            "\(race):57 implicitlyUnwrappedOptional: no data: on a line with no code region outside functions",
            // A stored-property initialiser the tests ran, and one they didn't.
            "\(race):59 forceTry: tested",
            "\(race):76 forceTry: untested",
            // Case 2: a type whose only code, attached to it, ran: no
            // function has data, so coverage can't say.
            "\(race):90 uncheckedSendable: no data: on a type with no coverage data",
            // Case 2: only the initialiser and the deinitialiser ran, as
            // building and releasing an instance runs them.
            "\(race):97 uncheckedSendable: untested"
        ])
        #expect(markers.filter { $0.rule == "forceCast" }.map(\.isRace) == [false])
        // The test files' markers and the trap are never judged: a test
        // function's, and the global's in a file above every test function.
        #expect(markers.contains { $0.file.hasPrefix("Tests/") } == false)
        #expect(markers.contains { $0.rule == "unconditionalTrap" } == false)
        // Nor are the generated file's function, type and file markers.
        #expect(markers.contains { $0.file == RiskyFixture.generated } == false)
        let generated = snapshot.findings.filter { $0.file == RiskyFixture.generated }
        #expect(generated.map(\.attachedTo.rawValue).sorted() == ["file", "function", "type"])
        #expect(snapshot.findings.contains { $0.file.hasPrefix("Tests/") && $0.rule == "forceUnwrap" })
        #expect(snapshot.findings.contains { $0.file == "Tests/RiskyTests/Support.swift" && $0.attachedTo == .file })
    }

    @Test("the fixture lists the functions and types holding an untested marker, by score, then region coverage")
    func rows() throws {
        let snapshot = try RiskyFixture.stored()
        let signal = try SignalHarness.signal(.riskyUntested, of: snapshot)

        #expect(signal.leftOut == nil)
        // 27 production functions, 9 types and 2 files have coverage data;
        // the generated file's function, type and file aren't counted, the
        // type though its stored-property initialiser is attached to it.
        #expect(signal.candidates == 38)
        let attached = snapshot.coverage?.report.attachments.filter { $0.attachedTo == .type }.map(\.owner)
        #expect(attached?.contains("Risky::GeneratedWorker") == true)
        #expect(signal.rule.hasPrefix(RiskyUntested.rule + "; 28 markers: 9 tested (1 on partly run lines), "
            + "11 untested, 8 with no coverage data (2 in a file with no coverage data, 1 in a function with no "
            + "coverage data, 1 in an inactive #if branch, 1 on a line with no code region in a function that ran, "
            + "1 on a line with no code region outside functions, 2 on a type with no coverage data); left out: "))
        #expect(signal.rule.contains("swiftprojectlint unconditionalTrap 1 (deliberate unreachable code)"))
        #expect(signal.rule.hasSuffix(RiskyUntested.limits))
        #expect(signal.members.count == signal.items.count)
        #expect(SignalHarness.rows(signal) == [
            "| # | Function, type or file | Score | Untested by rule | On partly run lines | Lines | Regions "
                + "| Member |",
            "| --- | --- | --- | --- | --- | --- | --- | --- |",
            // Two untested markers score 2, listed first though other
            // subjects' regions are as low.
            "| 1 | `Crash::static func twice(_: Int?, _: Int?) -> Int` (Sources/Risky/Crash.swift:71) | 2 | "
                + "forceUnwrap 2/2 | 0 | 0/4 (0%) | 0/1 (0%) | yes |",
            "| 2 | `Crash::static func neverRun(_: Int?) -> Int` (Sources/Risky/Crash.swift:9) | 1 | "
                + "forceUnwrap 1/1 | 0 | 0/3 (0%) | 0/1 (0%) | yes |",
            "| 3 | `Crash::static func neverRunSignature(_: Int!) -> Int` (Sources/Risky/Crash.swift:30) | 1 | "
                + "implicitlyUnwrappedOptional 1/1 | 0 | 0/3 (0%) | 0/1 (0%) | yes |",
            "| 4 | `Crash::static func outer(_: Int?) -> Int / func inner(_: Int?) -> Int` "
                + "(Sources/Risky/Crash.swift:56) | 1 | forceUnwrap 1/1 | 0 | 0/1 (0%) | 0/1 (0%) | yes |",
            "| 5 | `UnbuiltSettings` (Sources/Risky/Race.swift:76) | 1 | forceTry 1/1 | 0 | 0/2 (0%) | 0/2 (0%) "
                + "| yes |",
            "| 6 | `Untouched` (Sources/Risky/Race.swift:30) | 1 | uncheckedSendable 1/1 | 0 | 0/4 (0%) | 0/2 (0%) "
                + "| yes |",
            "| 7 | `OnlyBuilt` (Sources/Risky/Race.swift:16) | 1 | uncheckedSendable 1/1 | 0 | 2/5 (40%) "
                + "| 2/3 (66.67%) | yes |",
            "| 8 | `Crash::static func branch(_: Int?, _: Bool) -> Int` (Sources/Risky/Crash.swift:21) | 1 | "
                + "forceUnwrap 1/1 | 0 | 5/6 (83.33%) | 3/4 (75%) | yes |",
            // One untested marker of two scores 1: untested, then all.
            "| 9 | `Crash::static func mixed(_: Int?, _: Bool) -> Int` (Sources/Risky/Crash.swift:78) | 1 | "
                + "forceUnwrap 1/2 | 0 | 6/7 (85.71%) | 3/4 (75%) | yes |",
            "| 10 | `Released` (Sources/Risky/Race.swift:97) | 1 | uncheckedSendable 1/1 | 0 | 5/8 (62.50%) "
                + "| 3/4 (75%) | yes |"
        ])
        #expect(signal.items.map(\.score) == [2, 1, 1, 1, 1, 1, 1, 1, 1, 1])
    }

    @Test("an item carries its markers by rule and its subject's coverage, and the JSON round-trips")
    func payloads() throws {
        let snapshot = try RiskyFixture.stored()
        let signal = try SignalHarness.signal(.riskyUntested, of: snapshot)
        let item = try #require(signal.items.first { $0.subject == "Risky::OnlyBuilt" })

        let json = try JSONSerialization.jsonObject(with: try ScanReportEncoder.encode(item)) as? [String: Any]
        let markers = json?["markers"] as? [String: Any]

        let keys: Set<String> = ["rank", "subject", "file", "line", "score", "member", "markers", "coverage"]
        #expect(json.map { Set($0.keys) } == keys)
        #expect(markers?["byRule"] as? [String: [Int]] == ["uncheckedSendable": [1, 1]])
        #expect(markers?["onPartlyRunLines"] as? Int == 0)
        // The type's initialiser and `work` (1 of 2 regions), and its
        // stored property's initialiser (1 of 1).
        #expect(item.coverage?.regions == CoverageTally(covered: 2, total: 3))
        #expect(try JSONDecoder().decode(SignalItem.self, from: try ScanReportEncoder.encode(item)) == item)
        // Untested, then all markers, by rule.
        let byRule = { (subject: String) in signal.items.first { $0.subject == subject }?.markers?.byRule }
        #expect(byRule("Risky::Crash::static func twice(_: Int?, _: Int?) -> Int") == ["forceUnwrap": [2, 2]])
        #expect(byRule("Risky::Crash::static func mixed(_: Int?, _: Bool) -> Int") == ["forceUnwrap": [1, 2]])
    }

    @Test("findings merge only when tool, rule, file, line and a known column agree; other rules aren't markers")
    func markerIdentity() {
        let row = { (tool: String, rule: String, line: Int, column: Int?) in
            FindingRow(
                snapshotId: 1,
                tool: tool,
                rule: rule,
                kind: .defect,
                severity: "warning",
                message: "m",
                file: "Sources/Lib/Lib.swift",
                line: line,
                column: column,
                attachedTo: .function,
                owner: "Lib::func f()"
            )
        }
        var unscanned = row("swiftprojectlint", "forceUnwrap", 9, nil)
        unscanned.attachedTo = .unscanned
        let rows = [
            row("swiftprojectlint", "forceUnwrap", 3, nil),
            row("swiftprojectlint", "forceUnwrap", 3, nil),
            row("swiftstats", "implicitlyUnwrappedOptional", 4, 10),
            row("swiftstats", "implicitlyUnwrappedOptional", 4, 10),
            row("swiftstats", "implicitlyUnwrappedOptional", 4, 20),
            row("swiftlint", "force_unwrapping", 3, 5),
            row("swiftstats", "precondition", 5, 1),
            row("swiftprojectlint", "unsafeMemoryAPI", 6, nil),
            row("swiftprojectlint", "uncheckedSendable", 7, nil),
            row("swiftprojectlint", "forceCast", 8, nil),
            row("swiftlint", "force_cast", 8, 5),
            unscanned
        ]

        let markers = RiskMarker.markers(in: rows)

        #expect(markers.map { "\($0.rule)@\($0.line ?? 0):\($0.column ?? 0)" } == [
            "forceUnwrap@3:0", "forceUnwrap@3:0", "implicitlyUnwrappedOptional@4:10",
            "implicitlyUnwrappedOptional@4:20", "uncheckedSendable@7:0", "forceCast@8:0"
        ])
        #expect(markers.map(\.isRace) == [false, false, false, false, true, false])
    }
}
