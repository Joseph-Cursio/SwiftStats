import Foundation
@testable import SwiftStatsCore
import Testing

/// Properties of SwiftStats' readers and mappers at the integer edges
/// (design §4.1.8, B25, P15.1): every numeric field of a decoded tool
/// record at 0, 1 and `Int.max - 3` through `Int.max` comes back mapped,
/// failed or unknown, as the reader's and the mapper's rules say, and
/// nothing traps. One property per path from a tool's output to its
/// mapper: swift-clone-detector's JSON to `CloneMapper`, copies on line 1
/// of a file starting with a byte order mark included (B25's 04b);
/// results.jsonl keys to `MutantKey.description` (04a) and
/// `MutationMapper`; SwiftLint's and SwiftProjectLint's JSON to
/// `FindingMapper`; outskirts' locations to `DeadCodeMapper`; and
/// type-check timing lines to `TimingMapper` (B1, B18). Each reads its
/// tool's bytes as the collector does and maps them onto one measured
/// package of three files, built once per test: `Plain.swift` and
/// `Marked.swift`, scanned, and `Other.swift`, outside every target's
/// directory and never scanned. Each property has its examples, calling its shared check, and a
/// meta-test that feeds a planted defect's output to that check. The
/// examples written before each B25 fix (`CloneRunTests`,
/// `MutationOutcomeTests`, `TimingFigureTests+Saturation`) stay where
/// they are.
@Suite("Integer edges: properties", .tags(.pbt))
struct IntegerEdgesPBT {
    /// A measured package of the scanned files every path maps onto.
    struct Library {
        /// The package, measured as a scan measures it.
        let harness: MappingHarness
        /// Its root, as its real path.
        let root: String

        /// Its measurements.
        var measured: ScanMeasurements {
            harness.measured
        }

        /// The key of `first()`, the record holding line 1 of the file
        /// without a byte order mark; empty if there is none.
        var firstKey: String {
            records(in: IntegerEdgeGen.plainFile).first { $0.range.start.line == 1 }?.key ?? ""
        }

        /// The scanned hash of the file without a byte order mark; empty if
        /// it wasn't parsed.
        var plainHash: String {
            measured.parsed.first { $0.file.path == IntegerEdgeGen.plainFile }?.file.sha256 ?? ""
        }

        /// A timing mapper onto the package, nothing changed.
        var timingMapper: TimingMapper {
            TimingMapper(measured: measured, root: root, build: root + "/.swiftstats/index-build", changedFiles: [])
        }

        /// The package, measured.
        init() throws {
            harness = try MappingHarness(TemporaryPackage(IntegerEdgesPBT.sources))
            root = BuildFixture.realPath(harness.package.root)
        }

        /// The function records of `file`.
        func records(in file: String) -> [FunctionRecord] {
            measured.records.filter { $0.file == file }
        }

        /// Removes the package.
        func remove() {
            harness.remove()
        }
    }

    /// What every property's tally counts when a record comes back mapped:
    /// attached to a record of the package.
    static let mapped = "mapped onto a record"
    /// What it counts when the record's output is refused or the record
    /// skipped.
    static let failed = "failed"
    /// What it counts when the record comes back, but no record of the
    /// package holds it: on a file, unscanned or unmapped.
    static let unknown = "unknown"
    /// What it counts when some field is at `Int.max`.
    static let largest = "a field at Int.max"
    /// What it counts when some field is at 0.
    static let zero = "a field at 0"

    /// The package's files: `first()` alone on line 1 of a file without a
    /// byte order mark, then a type and its method; a function in a file
    /// starting with one; and a file outside every target's directory,
    /// never scanned. No record is nested in another, and no type
    /// or record holds line 0 or a line past the files' ends.
    static let sources = [
        IntegerEdgeGen.plainFile: """
            public func first() -> Int { 1 }
            public struct Box {
                public func doubled() -> Int {
                    2
                }
            }

            """,
        IntegerEdgeGen.markedFile: "\u{FEFF}func marked() -> Int {\n    let value = 1\n    return value + value\n}\n",
        IntegerEdgeGen.unscannedFile: "let other = 1\n"
    ]

    /// The function records of each scanned file, as `libraryIsAsStated`
    /// pins them: none nested in another.
    static let recordSpans = [
        IntegerEdgeGen.plainFile: [span(1, 1, 1, 32), span(3, 5, 5, 5)],
        IntegerEdgeGen.markedFile: [span(1, 4, 4, 1)]
    ]
    /// The lines of each scanned file holding a token: every line but the
    /// empty one ending it (no comment and no attribute), as
    /// `libraryIsAsStated` pins them.
    static let tokenLines = [IntegerEdgeGen.plainFile: 1...6, IntegerEdgeGen.markedFile: 1...4]

    /// Records an issue naming `subject`, in ASCII, for each law in `laws`
    /// that fails; whether all hold.
    static func holds(_ laws: [(holds: Bool, law: String)], subject: String) -> Bool {
        for law in laws where law.holds == false {
            Issue.record(Comment(rawValue: PBTTrace.ascii("\(subject) fails: it \(law.law)")))
        }
        return laws.allSatisfy(\.holds)
    }

    /// The labels for `values`, numbers a record holds: at `Int.max`, at 0.
    static func edgeLabels(_ values: [Int]) -> [String] {
        [(values.contains(Int.max), largest), (values.contains(0), zero)].filter(\.0).map(\.1)
    }

    @Test("""
        the package every path maps onto holds first() on line 1 alone, Box from line 2, and marked() after a \
        byte order mark, each scanned file's token lines as stated, and leaves the file outside its targets \
        unscanned
        """)
    func libraryIsAsStated() throws {
        let library = try Library()
        defer { library.remove() }

        let plain = library.records(in: IntegerEdgeGen.plainFile)
        let marked = library.records(in: IntegerEdgeGen.markedFile)
        #expect(plain.map(\.key) == ["Lib::func first() -> Int", "Lib::Box::func doubled() -> Int"])
        #expect(plain.map(\.range) == Self.recordSpans[IntegerEdgeGen.plainFile])
        #expect(marked.map(\.range) == Self.recordSpans[IntegerEdgeGen.markedFile])
        #expect(library.measured.types.map(\.range) == [Self.span(2, 1, 6, 1)])
        #expect(library.measured.files.map(\.path).sorted() == [IntegerEdgeGen.markedFile, IntegerEdgeGen.plainFile])
        #expect(library.firstKey == "Lib::func first() -> Int")
        #expect(library.plainHash.isEmpty == false)
        let holdsToken = { (line: Substring) in
            line.unicodeScalars.contains { scalar in scalar.properties.isWhitespace == false && scalar != "\u{FEFF}" }
        }
        for (path, lines) in Self.tokenLines {
            let written = (Self.sources[path] ?? "")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated()
                .filter { holdsToken($0.element) }
                .map { $0.offset + 1 }
            let measured = library.measured.files.first { $0.path == path }?.strippedLines
            #expect(written == Array(lines), "the lines of \(path) written with a token")
            #expect(measured == lines.count, "the token lines the scan counts in \(path)")
        }
    }
}
