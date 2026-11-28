//
//  CoverageExportGen.swift
//  SwiftStatsCoreTests
//
//  `llvm-cov export` documents for P2.6, drawn as decisions
//  (`ExportDraft`): up to three files of up to five segments, up to three
//  function entries of up to three regions; counts small, at the edges of
//  `Int64` (negative ones included, which llvm never writes and the
//  decoder reads as spelled), past `Int64.max` up to `UInt64.max`, and,
//  rarely, in a spelling whose reading isn't labelled; rows longer than
//  llvm writes; the members llvm writes that aren't read; file names
//  needing escapes or not ASCII; region kinds llvm defines and one it
//  doesn't. Most documents have no fault; the rest have one, each class
//  alike.
//

import PropertyBased
@testable import SwiftStatsCore

/// Generators of export documents.
enum CoverageExportGen {
    /// The file names documents use: plain, with a space, not ASCII, and
    /// holding a quote and a backslash.
    static let filenames = [
        "/p/Sources/A.swift", "/p/Sources/B c.swift", "/p/Sources/Caf\u{E9}.swift", "/p/Sources/q\"u\\o.swift"
    ]
    /// The function names they use.
    static let functionNames = ["$s5Probe8platformSSyF", "main", "$s4main3fooyyFyyXEfU_"]
    /// Counts past `Int64.max` within `UInt64`, beside a drawn one.
    static let clampedEdges: [UInt64] = [UInt64(Int64.max) + 1, UInt64.max]
    /// Counts within `Int64` at its edges.
    static let edgeCounts: [Int64] = [Int64.max, Int64.min, -1]
    /// Spellings whose reading isn't labelled.
    static let unlabelledSpellings = ["3.0", "1e2", "-0", "0.5"]
    /// Spellings out of range: past `UInt64.max`, far past it, and below
    /// `Int64.min`.
    static let outOfRangeSpellings = [
        "18446744073709551616", "100000000000000000000000000000", "-9223372036854775809"
    ]
    /// The keys a member fault leaves out.
    static let missingKeys = [
        "count", "data", "filename", "filenames", "files", "functions", "name", "regions", "segments", "type",
        "version"
    ]
    /// The keys and row fields a mistyping hits.
    static let mistypedKeys = ExportDraft.mistypings.keys.sorted()
    /// The kinds of row a count out of range or a short row hits.
    static let rowKinds = ["segment", "region"]
    /// The rows a count out of range hits.
    static let countTargets = ["segment", "region", "function"]
    /// Wrong types: a near miss and another tool's.
    static let wrongTypes = ["llvm.coverage.json.export.v2", "llvm.profdata"]
    /// Wrong versions: the one before and the one after.
    static let wrongVersions = ["2.0.1", "3.0.2"]
    /// The fewest elements past one (forced).
    static let twoElements = 2
    /// Element counts of the data array other than one.
    static let dataCounts = [0, twoElements]
    /// The largest small count (assumed: enough to differ, and to tie).
    static let smallCount: Int64 = 9
    /// How many files a document has (assumed: enough for a later file).
    static let fileCount = 0...3
    /// How many segments a file has (assumed, as above).
    static let segmentCount = 0...5
    /// How many entries a document has (assumed, as above).
    static let functionCount = 0...3
    /// How many regions an entry has (assumed, as above).
    static let regionCount = 0...3
    /// How many files an entry names.
    static let entryFiles = 1...2
    /// Line and column steps between segments.
    static let step = 0...3
    /// Lines and columns of regions (assumed: small, any order).
    static let regionPlaces = 1...40
    /// Region kinds: llvm's four and one it doesn't define.
    static let regionKinds = CoverageRegion.codeKind...(CoverageRegion.gapKind + 1)
    /// Extra row elements.
    static let extras = 0...2
    /// The largest offset a cut or a changed byte draws, modulo the
    /// document's length.
    static let largestOffset = 9_999

    /// Weight of a small count.
    static let smallWeight = 4.0
    /// Weight of each other class.
    static let classWeight = 1.0
    /// Weight of a spelling whose reading isn't labelled, rare so most
    /// documents have a labelled outcome.
    static let unlabelledWeight = 0.05
    /// Weight of no fault.
    static let soundWeight = 6.0
    /// Weight of no extra row element.
    static let plainWeight = 4.0
    /// The share of documents whose objects hold the members not read.
    static let extraKeyRate: Float = 0.5

    /// A count as spelled.
    static let count = Gen.frequency(
        (smallWeight, Gen<Int64>.value(in: 0...smallCount).map(ExportDraft.Count.value)),
        (classWeight, Pick.element(of: edgeCounts).map(ExportDraft.Count.value)),
        (classWeight, Pick.element(of: clampedEdges).map(ExportDraft.Count.clamped)),
        (classWeight, Gen<UInt64>.value(in: (UInt64(Int64.max) + 1)...UInt64.max).map(ExportDraft.Count.clamped)),
        (unlabelledWeight, Pick.element(of: unlabelledSpellings).map(ExportDraft.Count.spelled))
    )

    /// How many elements follow a row's.
    static let extraElements = Gen.frequency(
        (plainWeight, Gen.always(0)),
        (classWeight, Gen<Int>.value(in: extras))
    )

    /// A segment.
    static let segment = zip(
        Gen<Int>.value(in: step),
        Gen<Int>.value(in: step),
        count,
        Gen.bool,
        Gen.bool,
        Gen.bool,
        extraElements
    )
    .map(ExportDraft.Segment.init)

    /// A position of a region.
    static let place = zip(Gen<Int>.value(in: regionPlaces), Gen<Int>.value(in: regionPlaces))
        .map(SourcePosition.init)

    /// A region.
    static let region = zip(
        place,
        place,
        count,
        Gen<Int>.value(in: 0...1),
        Gen<Int>.value(in: regionKinds),
        extraElements
    )
    .map(ExportDraft.Region.init)

    /// A file.
    static let file = zip(Pick.element(of: Array(filenames.indices)), segment.array(of: segmentCount))
        .map(ExportDraft.File.init)

    /// A function entry.
    static let function = zip(
        Pick.element(of: Array(functionNames.indices)),
        count,
        Pick.element(of: Array(filenames.indices)).array(of: entryFiles),
        region.array(of: regionCount)
    )
    .map(ExportDraft.Function.init)

    /// The fault: none, most often, or one of each class alike.
    static let fault = Gen.frequency(
        (soundWeight, Gen.always(ExportDraft.Fault.sound)),
        (classWeight, Pick.element(of: wrongTypes).map(ExportDraft.Fault.wrongType)),
        (classWeight, Pick.element(of: wrongVersions).map(ExportDraft.Fault.wrongVersion)),
        (classWeight, Pick.element(of: dataCounts).map(ExportDraft.Fault.dataCount)),
        (classWeight, Gen.always(ExportDraft.Fault.misordered)),
        (classWeight, Pick.element(of: missingKeys).map(ExportDraft.Fault.missing)),
        (classWeight, Pick.element(of: mistypedKeys).map(ExportDraft.Fault.mistyped)),
        (
            classWeight,
            zip(Pick.element(of: countTargets), Pick.element(of: outOfRangeSpellings)).map(ExportDraft.Fault.outOfRange)
        ),
        (classWeight, Pick.element(of: rowKinds).map(ExportDraft.Fault.shortRow)),
        (classWeight, Gen<Int>.value(in: 0...largestOffset).map(ExportDraft.Fault.truncated)),
        (classWeight, zip(Gen<Int>.value(in: 0...largestOffset), Gen<UInt8>.value()).map(ExportDraft.Fault.badByte))
    )

    /// P2.6's input: an export document.
    static let export = zip(
        file.array(of: fileCount),
        function.array(of: functionCount),
        Gen.bool(extraKeyRate),
        fault
    )
    .map { files, functions, extraKeys, fault in
        GeneratedExport(draft: ExportDraft(files: files, functions: functions, extraKeys: extraKeys, fault: fault))
    }
    .eraseToAny()
}
