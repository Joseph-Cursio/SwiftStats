//
//  TimingMapperTests.swift
//  SwiftStatsCoreTests
//
//  Mapping the T1 build's type-check timings onto the scan (M7, design
//  §6.2), on the Index fixture's recorded build: where its entries go, the
//  classes of entries left out, a changed file, and the build block's JSON.
//  Tests on recorded data assert places, sets and counts, never times
//  (`TimingFigureTests` checks figures on hand-written entries).
//

import Foundation
@testable import SwiftStatsCore
import Testing

/// The timing mapper, on the Index fixture's recorded build.
@Suite("Timing mapper")
struct TimingMapperTests {
    /// The recorded build's entry of `kind` at `place`.
    private static func recorded(
        _ output: BuildOutput,
        _ kind: TimingEntry.Kind,
        at place: BuildPlace
    ) throws -> TimingEntry {
        try #require(output.entries.first { $0.kind == kind && $0.place == place })
    }

    @Test("recorded entries go to the record holding their name position, of any role, else its type, else its file")
    func recordedPlaces() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let output = try fixture.output()
        let mapper = fixture.mapper(changedFiles: [])
        let place = { (kind: TimingEntry.Kind, file: String, line: Int, column: Int) in
            let entry = BuildPlace(path: fixture.root + "/" + file, line: line, column: column)
            return mapper.place(try Self.recorded(output, kind, at: entry))
        }
        let accessors = "Sources/IndexCore/Accessors.swift"
        let ring = "Sources/IndexCore/Ring.swift"
        let locals = "Sources/IndexCore/Locals.swift"
        // A shorthand getter, timed at its `{`.
        #expect(try place(.function, accessors, 29, 27) == .record("IndexCore::Storage::var count: Int { get }"))
        // A get-only subscript's implicit `_read` at its keyword, its getter at its `{`.
        #expect(try place(.function, ring, 25, 12) == .record("IndexCore::Ring::subscript(_: Int) -> Int"))
        #expect(try place(.function, ring, 25, 44) == .record("IndexCore::Ring::subscript(_: Int) -> Int"))
        // A local function, on its own record.
        #expect(
            try place(.function, locals, 27, 10)
                == .record("IndexCore::func summarize(_: [Int]) -> Int / func unusedHelper() -> Int")
        )
        // A stored property's implicit accessors, on its type.
        #expect(try place(.function, accessors, 4, 9) == .type("IndexCore::Storage"))
        // A local type's stored property's getter, on the local type, not the function declaring it.
        #expect(try place(.function, locals, 7, 13) == .type("IndexCore::Square"))
        // A local type's method, on its own record.
        #expect(
            try place(.function, locals, 9, 14)
                == .record("IndexCore::func layout(_: Int) -> Int / Square::func area() -> Int")
        )
        // A global's initialiser, on its file.
        #expect(try place(.expression, ring, 32, 21) == .file(ring))
        // A test function.
        #expect(
            try place(.function, "Tests/IndexCoreTests/IndexCoreTests.swift", 32, 16)
                == .record("IndexCoreTests::IndexCoreTests::func needlessTry()")
        )
        // Line 1 of a file starting with a byte order mark, its bytes counted.
        let bom = "Sources/IndexCore/Bom.swift"
        #expect(try place(.function, bom, 1, 16) == .record("IndexCore::func bomFirst() -> Int"))
        // Two functions on one line, placed apart.
        #expect(try place(.function, locals, 17, 6) == .record("IndexCore::func left() -> Int"))
        #expect(try place(.function, locals, 17, 32) == .record("IndexCore::func right() -> Int"))
    }

    @Test("every recorded record is timed but the two under inactive conditions, and the classes are counted")
    func recordedClasses() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let output = try fixture.output()
        let mapped = fixture.mapper(changedFiles: []).map(output.entries)
        let timed = Set(mapped.records.map(\.key))
        let untimed = Set(fixture.measured.records.map(\.key)).subtracting(timed)
        #expect(untimed == [
            "IndexCore::func flagged() -> Int #if INDEX_FIXTURE_FLAG",
            "IndexCore::func buildMode() -> String #if !(DEBUG)"
        ])
        #expect(mapped.unmapped.synthesized.entries == 37)
        #expect(mapped.unmapped.macro.entries == 172)
        #expect(mapped.dropped.build.entries == 42)
        #expect(mapped.dropped.outsideRoot.entries == 7)
        #expect(mapped.dropped.unscanned.entries == 0)
        #expect(mapped.dropped.fileChanged.entries == 0)
        #expect(mapped.totals.functionEntries == 213)
        #expect(mapped.totals.expressionEntries == 377)
        #expect(Set(mapped.attachments.map(\.attachedTo)) == [.type, .file])
    }

    @Test("local functions are nested in a body and left out of the totals; a local type's method is not")
    func recordedNesting() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let measured = fixture.measured
        #expect(TimingMapper.nestedInBody(measured.records, types: measured.types) == [
            "IndexCore::func layout(_: Int) -> Int / func padded(_: Int) -> Int",
            "IndexCore::func summarize(_: [Int]) -> Int / func unusedHelper() -> Int",
            "IndexCore::func choose(_: Bool) -> Int / func pick() -> Int",
            "IndexCore::func choose(_: Bool) -> Int / func pick() -> Int #2"
        ])
    }

    @Test("an emit-module job's second check of a body is counted beside the first")
    func recordedDuplicates() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let output = try fixture.output()
        let mapper = fixture.mapper(changedFiles: [])
        let name = BuildPlace(path: fixture.root + "/Sources/IndexCore/Locals.swift", line: 2, column: 13)
        let layout = output.entries.filter { $0.kind == .function && $0.place == name }
        #expect(layout.allSatisfy { mapper.place($0) == .record("IndexCore::func layout(_: Int) -> Int") })
        #expect(layout.count == 2)
    }

    @Test("a file that changed during the scan drops its entries, and its records are left untimed")
    func changedFile() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let output = try fixture.output()
        let ring = "Sources/IndexCore/Ring.swift"
        let mapped = fixture.mapper(changedFiles: [ring]).map(output.entries)
        let ringEntries = output.entries.count { $0.place?.path == fixture.root + "/" + ring }
        #expect(ringEntries > 0)
        #expect(mapped.dropped.fileChanged.entries == ringEntries)
        #expect(mapped.records.contains { $0.key.hasPrefix("IndexCore::Ring::") } == false)
        #expect(mapped.attachments.contains { $0.owner == ring } == false)
    }

    @Test("the build block's JSON names what the independent checker reads")
    func blockKeys() throws {
        let fixture = try BuildFixture()
        defer { fixture.remove() }
        let output = try fixture.output()
        let report = BuildReport(
            output: output,
            timings: fixture.mapper(changedFiles: []).map(output.entries),
            warnings: fixture.warningReader(changedFiles: []).read(output.diagnostics),
            changedFiles: 0,
            complete: true
        )
        let encoded = try JSONEncoder().encode(report)
        let object = try #require(try JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        #expect(Set(object.keys) == [
            "complete", "records", "attachments", "unmapped", "dropped", "totals", "changedFiles",
            "unparsedTimingLines", "escapedLines", "otherWarningLines", "warningsDropped", "warningsUnmapped",
            "pluginWarnings"
        ])
        let unmapped = try #require(object["unmapped"] as? [String: [String: Int]])
        #expect(Set(unmapped.keys) == ["synthesized", "macro"])
        #expect(Set(try #require(unmapped["macro"]).keys) == ["entries", "milliseconds"])
        let dropped = try #require(object["dropped"] as? [String: Any])
        #expect(Set(dropped.keys) == ["build", "outsideRoot", "fileChanged", "unscanned"])
        let record = try #require((object["records"] as? [[String: Any]])?.first)
        #expect(Set(record.keys).isSubset(of: ["key", "milliseconds", "slowestExpression"]))
        #expect(report.otherWarningLines == 5)
        #expect(report.warningsDropped == 1)
        #expect(try JSONDecoder().decode(BuildReport.self, from: JSONEncoder().encode(report)) == report)
    }
}
