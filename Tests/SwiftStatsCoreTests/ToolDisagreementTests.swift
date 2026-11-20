//
//  ToolDisagreementTests.swift
//  SwiftStatsCoreTests
//
//  Tool disagreement (PRD §8) on the Ledger fixture: which suggestions
//  each step of the funnel removes, the order of what is left, and its table.
//

import Foundation
@testable import SwiftStatsCore
import Testing

@Suite("Tool disagreement")
struct ToolDisagreementTests {
    @Test("a unique function with a heuristic non_idempotent callee and an idempotence row is listed, replay first")
    func listed() throws {
        let signal = try SignalHarness.signal(.toolDisagreement, of: try LedgerFixture.snapshot())

        #expect(signal.leftOut == nil)
        // A lower-scored replay row sorts first, then the row resting on an
        // annotation alone, then the heuristic one.
        #expect(signal.items.map(\.subject) == [
            "Core::Ledger::func restage(_: Int) -> Int",
            "Core::Ledger::func forward(_: Int) -> Int",
            "Core::Ledger::func stage(_: Int) -> Int"
        ])
        #expect(signal.items.map(\.score) == [30, 40, 80])
        #expect(signal.items.map(\.rank) == [1, 2, 3])
        #expect(signal.members.count == 3)
        let stage = try #require(signal.items.last)
        #expect(stage.property?.identity == "0x0000000000000001")
        #expect(stage.property?.template == "idempotence")
        #expect(stage.effect == SignalItem.Effect(
            inferred: EffectFacts.Inferred(
                tier: .nonIdempotent,
                depth: 1,
                anchor: .heuristic,
                via: ["from the callee-name prefix `insert` (in `insertRow`)"]
            ),
            purity: .pure,
            source: .purity,
            shape: nil
        ))
        #expect(signal.items[1].effect?.inferred?.anchor == .declared)
        #expect(signal.items[1].effect?.inferred?.via == ["calls `push(_:)`"])
    }

    @Test("ambiguous, shadowed and annotated functions never disagree, and the rule counts each step's removals")
    func funnel() throws {
        let snapshot = try LedgerFixture.snapshot()
        let signal = try SignalHarness.signal(.toolDisagreement, of: snapshot)
        let inference = { (key: String) in
            snapshot.functions.first { $0.key == key }?.facts?.effect?.function?.inference
        }

        #expect(inference("Core::First::func apply(_: Int) -> Int") == .ambiguous)
        #expect(inference("Core::Second::func apply(_: Int) -> Int") == .ambiguous)
        #expect(inference("Core::Draft::func persist() -> Int") == .shadowed)
        #expect(inference("Core::Ledger::func touch(_: Int) -> Int") == .annotated)
        // Twelve rows of the value and replay classes; the round-trip and
        // commutativity rows are outside the pool.
        #expect(signal.candidates == 12)
        let funnel = "of 12 suggestions, removed: 2 shared signature, 2 shadowed or declared, "
            + "3 not a production func or unmapped, 1 no body-inferred tier, 1 inferred tier not non_idempotent"
        #expect(signal.rule.hasPrefix(ToolDisagreement.rule + "; " + funnel + ". "))
        #expect(signal.rule.contains("so this list mainly calibrates SwiftEffectInference's heuristics"))
        let pinned = String(EffectInferenceRevision.pinned.prefix(10))
        #expect(signal.rule.hasSuffix(
            "SwiftEffectInference \(pinned) here, unknown in swift-infer "
                + "(possibly stale after a resolve without a rebuild)"
        ))
    }

    @Test("the table shows the suggestion, the inference's reasons, anchor and depth, and purity only when not pure")
    func table() throws {
        let signal = try SignalHarness.signal(.toolDisagreement, of: try LedgerFixture.snapshot())
        let rows = SignalHarness.rows(signal)

        #expect(rows.first == "| # | Function | Score | Template | SIP tier / score | Via | Anchor | Depth | Source "
            + "| Purity | Member |")
        #expect(rows.last == "| 3 | `Ledger::func stage(_: Int) -> Int` (Sources/Core/Ledger.swift:5) | 80 "
            + "| idempotence | Strong / 80 | from the callee-name prefix `insert` (in `insertRow`) | heuristic | 1 "
            + "| purity |  | yes |")
    }

    @Test("without SwiftInferProperties the signal is left out, naming it")
    func leftOut() throws {
        let snapshot = try SignalHarness.stored(
            LedgerFixture.files,
            targets: LedgerFixture.targets,
            tools: SnapshotHarness.noTools
        )
        let signal = try SignalHarness.signal(.toolDisagreement, of: snapshot)

        #expect(signal.leftOut == "needs swiftinferproperties: skipped, `swift-infer` not found on PATH; "
            + "set collectors.swiftinferproperties.path")
        #expect(signal.rule == ToolDisagreement.rule)
        #expect(signal.candidates == 0)
    }
}
