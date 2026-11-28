//
//  CoveragePBT+Export.swift
//  SwiftStatsCoreTests
//
//  P2.6: decoding any document returns an export or throws
//  `CoverageFailure`, never another error and never a trap; a well-formed
//  document decodes to its files and entries, every count from `Int64.max`
//  up to `UInt64.max` read as `Int64.max`, rows longer than llvm writes
//  them read with the extras ignored; and a document with one fault fails
//  with the decoder's reason for it.
//

import Foundation
import PropertyBased
@testable import SwiftStatsCore
import Testing

/// P2.6.
extension CoveragePBT {
    /// What decoding a document gives.
    typealias Decoded = Result<CoverageExport, any Error>

    /// P2.6's base runs, over the engine's 100: one decode of a document of
    /// a few hundred bytes costs well under a millisecond. The rarest
    /// antecedent, a row longer than llvm writes, comes in 179 of the
    /// meta-test's 1,000 documents, which 100 runs would meet; but a wrong
    /// version, the one input on which a type check that ignores the
    /// version fails, comes in 71 (design D14: `(1 - 0.071)^200`, about
    /// 4 * 10^-7, is the most a run misses it).
    static let exportRuns = 200
    /// What P2.6's tally counts when a document should decode.
    static let decodes = "a document that decodes"
    /// What it counts when one that decodes holds a count past `Int64.max`.
    static let saturates = "a count past Int64.max read as Int64.max"
    /// What it counts when one that decodes holds a row longer than llvm
    /// writes it.
    static let longRow = "a row longer than llvm writes"
    /// What it counts when a document fails with a reason of its own.
    static let refusedWithReason = "a document refused with a reason of its own"
    /// What it counts when a document fails as unreadable.
    static let unreadable = "a document that can't be read"
    /// The antecedents P2.6 must reach at least once each.
    static let exportAntecedents = [decodes, saturates, longRow, refusedWithReason, unreadable]

    /// The classes `draft` falls in, for P2.6's tally and the generator's
    /// meta-test.
    static func exportLabels(of draft: ExportDraft) -> [String] {
        let normalized = draft.normalized
        switch normalized.expected {
        case .accepted:
            let saturated = normalized.counts.contains { count in
                if case .clamped = count {
                    return true
                }
                return false
            }
            let long = normalized.files.contains { $0.segments.contains { $0.extras > 0 } }
                || normalized.functions.contains { $0.regions.contains { $0.extras > 0 } }
            return [(true, decodes), (saturated, saturates), (long, longRow)].filter(\.0).map(\.1)

        case .refused:
            return [refusedWithReason]

        case .unknown:
            return []

        case .unreadable:
            return [unreadable]
        }
    }

    /// Whether `decoded`, what decoding a document gave, is what `expected`
    /// says: an export or a `CoverageFailure`, never another error; the
    /// files and entries expected, with the reason expected, or a reason
    /// saying the document can't be read. Records an issue for each law
    /// that fails.
    static func checkDecoded(_ expected: ExportDraft.Expected, decoded: Decoded) -> Bool {
        let subject = "decoding the document"
        let failure: CoverageFailure?
        switch decoded {
        case .success:
            failure = nil

        case .failure(let error):
            guard let coverageFailure = error as? CoverageFailure else {
                return holds([(false, "throws \(error), not a CoverageFailure")], subject: subject)
            }
            failure = coverageFailure
        }
        let reason = failure.map { "fails: \($0.description)" } ?? "decodes"
        switch expected {
        case let .accepted(files, functions):
            guard case .success(let export) = decoded else {
                return holds([(false, reason + ", where it should decode")], subject: subject)
            }
            return holds(
                [
                    (export.files == files, "reads files \(export.files), expected \(files)"),
                    (export.functions == functions, "reads entries \(export.functions), expected \(functions)")
                ],
                subject: subject
            )

        case .refused(let expectedReason):
            return holds(
                [(failure?.description == expectedReason, reason + ", expected: " + expectedReason)],
                subject: subject
            )

        case .unknown:
            return true

        case .unreadable:
            let read = failure?.description.hasPrefix(ExportDraft.unreadablePrefix) == true
            return holds([(read, reason + ", where it can't be read")], subject: subject)
        }
    }

    // MARK: P2.6

    /// Invariant: decoding any document returns an export or throws
    /// `CoverageFailure`; a well-formed one decodes to its files and
    /// entries, counts from `Int64.max` up to `UInt64.max` read as
    /// `Int64.max`, rows longer than llvm writes read with the extras
    /// ignored; a document with one fault fails with the decoder's reason.
    /// Why it holds: `CoverageExport`'s header and `decode(_:)`'s doc
    /// comment (anything it doesn't read fails with a reason), PRD §7.8
    /// ("Reading the export"), `CoverageCount`'s header (counts as 64-bit
    /// integers, one beyond `Int64.max` kept as `Int64.max`).
    /// Why it might not: rows are read with no end check, so extra elements
    /// are accepted (design §4.1.3); a count spelled `3.0` or `1e2` reads
    /// as JSONDecoder decides, so such documents check totality only; a
    /// negative count, which llvm never writes, reads as spelled.
    /// Oracle: the generating model (`ExportDraft.expected`); planted
    /// defects: a count past `Int64.max` refused, an export with unsorted
    /// segments read, a decoding error passed through unwrapped, and a
    /// type check that ignores the version, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        "decoding any document returns or throws CoverageFailure, reading counts past Int64.max as Int64.max",
        .timeLimit(PBTBudget.timeLimit)
    )
    func decodingIsTotal() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.exportRuns), input: CoverageExportGen.export) { input in
            PBTTrace.note(input)
            Self.exportLabels(of: input.draft).forEach(tally.fire)
            let decoded = Decoded { try CoverageExport.decode(input.data) }
            if Self.checkDecoded(input.draft.expected, decoded: decoded) == false {
                PBTTrace.firstFailure(input, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.exportAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }

    @Test("each recorded export decodes, every count read as JSONSerialization reads it")
    func recordedExportsDecode() throws {
        for data in try Self.recordedData() {
            let decoded = Decoded { try CoverageExport.decode(data) }
            let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let payload = (object?["data"] as? [[String: Any]])?.first
            let segments = (payload?["files"] as? [[String: Any]] ?? []).flatMap { $0["segments"] as? [[Any]] ?? [] }
            let functions = payload?["functions"] as? [[String: Any]] ?? []
            let counts = segments.compactMap { $0[2] as? Int64 }
                + functions.flatMap { function in
                    [function["count"] as? Int64] + (function["regions"] as? [[Any]] ?? []).map { $0[4] as? Int64 }
                }
                .compactMap(\.self)
            let export = try decoded.get()

            #expect(Self.checkDecoded(.unknown, decoded: decoded))
            #expect(export.files.flatMap(\.segments).map(\.executionCount)
                + export.functions.flatMap { [$0.count] + $0.regions.map(\.executionCount) } == counts)
        }
    }

    @Test("""
        a row longer than llvm writes reads with its extras ignored, and counts at Int64.max, past it, at \
        UInt64.max and past that read as Int64.max three times, then fail
        """)
    func longRowsAndCountEdges() {
        let edges = ["9223372036854775807", "9223372036854775808", "18446744073709551615"].map { spelling in
            #"{"count":\#(spelling),"filenames":["a"],"name":"f","regions":[[1,2,3,4,\#(spelling),0,0,0,9,9]]}"#
        }
        let document = #"{"data":[{"files":[],"functions":[\#(edges.joined(separator: ","))]}],"#
            + #""type":"llvm.coverage.json.export","version":"3.0.1"}"#
        let past = document.replacingOccurrences(of: "18446744073709551615", with: "18446744073709551616")
        let regions = (0..<3).map { _ in
            CoverageRegion(
                start: SourcePosition(line: 1, column: 2),
                end: SourcePosition(line: 3, column: 4),
                executionCount: Int64.max,
                fileID: 0,
                expandedFileID: 0,
                kind: 0
            )
        }
        let functions = regions.map { region in
            CoverageExportFunction(name: "f", count: Int64.max, filenames: ["a"], regions: [region])
        }

        let decoded = Decoded { try CoverageExport.decode(Data(document.utf8)) }
        let failed = Decoded { try CoverageExport.decode(Data(past.utf8)) }

        #expect(Self.checkDecoded(.accepted(files: [], functions: functions), decoded: decoded))
        #expect(Self.checkDecoded(.unreadable, decoded: failed))
    }

    @Test("a planted defect's decoding fails P2.6's law")
    func decodingDefectsDetected() throws {
        let segment = ExportDraft.addedSegment
        let file = ExportDraft.File(name: 0, segments: [segment, segment])
        let function = ExportDraft.Function(name: 1, count: .clamped(UInt64.max), files: [0], regions: [])
        let sound = ExportDraft(files: [file], functions: [function], extraKeys: false, fault: .sound)
        let misordered = ExportDraft(files: [file], functions: [function], extraKeys: false, fault: .misordered)
        let newer = ExportDraft(files: [file], functions: [function], extraKeys: false, fault: .wrongVersion("3.0.2"))
        let cut = ExportDraft(files: [file], functions: [function], extraKeys: false, fault: .truncated(9))
        let export = try CoverageExport.decode(sound.data)
        let unreadableFailure = CoverageFailure(description: ExportDraft.unreadablePrefix + "no")
        let raw = DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: "cut"))

        #expect(Self.checkDecoded(sound.expected, decoded: .success(export)))
        #expect(export.functions.first?.count == Int64.max)
        PlantedDefect.expectDetected("a count past Int64.max refused", sourceLocation: #_sourceLocation) {
            Self.checkDecoded(sound.expected, decoded: .failure(unreadableFailure))
        }
        PlantedDefect.expectDetected("unsorted segments read", sourceLocation: #_sourceLocation) {
            Self.checkDecoded(misordered.expected, decoded: .success(export))
        }
        PlantedDefect.expectDetected("a decoding error passed through", sourceLocation: #_sourceLocation) {
            Self.checkDecoded(cut.expected, decoded: .failure(raw))
        }
        PlantedDefect.expectDetected("a type check that ignores the version", sourceLocation: #_sourceLocation) {
            Self.checkDecoded(newer.expected, decoded: .success(export))
        }
    }
}
