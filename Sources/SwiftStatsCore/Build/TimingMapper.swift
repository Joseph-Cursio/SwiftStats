//
//  TimingMapper.swift
//  SwiftStatsCore
//
//  Maps the T1 build's type-check timing entries onto the scan (M7, design
//  §6.2). Each entry is classed, first that applies: `synthesized`
//  (`<invalid loc>`), `macro` (a `@__swiftmacro_…` buffer), `build` (under
//  the build directory), `outsideRoot`, `fileChanged` (a scanned file whose
//  bytes changed during the scan), `unscanned` (in the root, a file the
//  scan didn't parse), else mapped: placed by its position (line, UTF-8
//  column) on the innermost record of any role holding it, test and helper
//  records included, else the innermost type, else the file
//  (`PositionPlacement`); a position a record holds inside a local type
//  declared in it, outside the type's members (a stored property's
//  implicit accessors), goes to that type. Paths are the compiler's
//  absolute paths (a linked target directory's files under their real
//  path, a linked file under its link), resolved and looked up among the
//  scanned files' real paths, then the describe's other sources'
//  (`SourcePaths`), so a file reached through a symbolic link or spelled
//  in another case is the scanned file, or the source as the manifest
//  spells it; any other path is made relative to the root's real path,
//  compared in NFC. Per record and attachment, the function-body entries
//  are summed and the largest expression entry kept, in hundredths, each
//  rounded to whole milliseconds once, half up; a sum stops at `Int.max`
//  hundredths rather than trapping, and so does every other sum of entries
//  (those left out, the totals), though the reader's twelve-digit bound
//  keeps real builds far below it. Nothing is deduplicated, since the
//  emit-module job's second check is time the build spent too. A
//  function's entry includes its local functions' but not its local types'
//  members', which the compiler checks after it (the Index fixture's
//  recorded build), so the total adds only the function-body entries on
//  records not nested in a body, on types and on files.
//

import Foundation

/// Maps type-check timing entries to records, types and files.
struct TimingMapper {
    /// Where an entry went.
    enum Placement: Hashable {
        /// Under the build directory: dropped.
        case build
        /// Attached to the file at this path.
        case file(String)
        /// In the scanned file at this path, which changed during the scan:
        /// dropped.
        case fileChanged(String)
        /// In a macro expansion's buffer: unmapped.
        case macro
        /// Outside the package root: dropped.
        case outsideRoot
        /// On the record with this key.
        case record(String)
        /// At `<invalid loc>`, a synthesized member: unmapped.
        case synthesized
        /// Attached to the type with this owner text.
        case type(String)
        /// In the root, in the file at this path, which the scan didn't
        /// parse: dropped.
        case unscanned(String)
    }

    /// What mapping the entries gave.
    struct Mapped: Hashable {
        /// The records holding an entry, by key.
        let records: [BuildRecordTiming]
        /// The types and files holding an entry, by what they attach to,
        /// then owner.
        let attachments: [BuildAttachment]
        /// The entries no position in the package holds.
        let unmapped: BuildUnmapped
        /// The entries left out.
        let dropped: BuildDropped
        /// The totals.
        let totals: BuildTotals
        /// The function-body time on each record, type and file the totals
        /// count (records nested in a body left out), in hundredths: what
        /// each roll-up scope's total adds (`TypeCheckTotals`).
        let counted: [Placement: Int]
    }

    /// Where a path the compiler printed lies.
    private enum Location: Hashable {
        /// Under the build directory.
        case build
        /// At this path in the package.
        case inRoot(String)
        /// Outside the package root.
        case outsideRoot
    }

    /// The classes of entries left unplaced.
    private enum LeftOut {
        /// Under the build directory.
        case build
        /// In a file that changed during the scan.
        case fileChanged
        /// In a macro expansion's buffer.
        case macro
        /// Outside the package root.
        case outsideRoot
        /// At `<invalid loc>`.
        case synthesized
        /// In a file the scan didn't parse.
        case unscanned
    }

    /// One record's, type's or file's entries, in hundredths.
    private struct Figures {
        /// The sum of its function-body entries, stopping at `Int.max`;
        /// nil when none.
        var functions: Int?
        /// Its largest expression entry; nil when none.
        var slowest: Int?
    }

    /// The rule the `map:` option records: what changes it changes the
    /// figures.
    static let rule = "type-check entries in hundredths of a ms by name position (line, UTF-8 column) to the "
        + "innermost record of any role, else type, else file, a local type before the record declaring it; "
        + "per record the sum of function-body entries (inclusive of local functions, not local types' members) "
        + "and the largest expression entry, whole ms half up; totals leave out records nested in a body, "
        + "local types' members not nested"
    /// What a macro expansion buffer's file name starts with.
    static let macroBufferPrefix = "@__swiftmacro_"
    /// Half a millisecond, in hundredths: where rounding goes up.
    private static let halfMillisecond = 50
    /// The kinds of record whose body holds its local functions' entries.
    static let bodyKinds: Set<FunctionKind> = [.function, .initializer, .deinitializer, .accessor, .topLevelCode]

    /// Places positions on records of every role.
    private let placement: PositionPlacement
    /// The scanned files, then any other sources, by real path.
    private let paths: SourcePaths
    /// The build directory's real path.
    private let build: String
    /// The scanned files whose bytes changed during the scan.
    private let changed: Set<NFCPath>
    /// The scanned files' paths, by their NFC spelling.
    private let spellings: [NFCPath: String]
    /// The keys of the records nested in a body.
    private let nested: Set<String>

    /// A mapper onto `measured`, the package whose root's real path is
    /// `root`, built in the directory whose real path is `build`; the
    /// scanned files `changedFiles` (relative to the root) changed during
    /// the scan.
    init(measured: ScanMeasurements, root: String, build: String, changedFiles: Set<String>) {
        self.init(
            measured: measured,
            paths: SourcePaths(root: root, files: measured.files),
            build: build,
            changedFiles: changedFiles
        )
    }

    /// A mapper onto `measured`, whose scanned files are `paths`, built in
    /// the directory whose real path is `build`; the scanned files
    /// `changedFiles` (relative to the root) changed during the scan.
    init(measured: ScanMeasurements, paths: SourcePaths, build: String, changedFiles: Set<String>) {
        placement = PositionPlacement(measured: measured, roles: .every)
        self.paths = paths
        self.build = build
        changed = Set(changedFiles.map(NFCPath.init))
        spellings = Dictionary(measured.files.map { (NFCPath($0.path), $0.path) }) { first, _ in first }
        nested = Self.nestedInBody(measured.records, types: measured.types)
    }

    /// `hundredths` of a millisecond, never negative, as whole
    /// milliseconds, half up; it can't overflow, even at `Int.max`.
    static func milliseconds(_ hundredths: Int) -> Int {
        let perMillisecond = BuildLineGrammar.hundredthsPerMillisecond
        return hundredths / perMillisecond + (hundredths % perMillisecond + halfMillisecond) / perMillisecond
    }

    /// `first` plus `second`, two times or sums of them in hundredths, or
    /// `Int.max` when that overflows: entries are tool output, bounded
    /// one by one but not in number.
    static func sum(_ first: Int, _ second: Int) -> Int {
        let (total, overflow) = first.addingReportingOverflow(second)
        return overflow ? Int.max : total
    }

    /// The keys of `records` nested in a body: those with an ancestor
    /// (`parentKey`) of a kind in `bodyKinds` reached without passing
    /// through a type of `types` (one lying inside an ancestor and holding
    /// its child). A subscript's accessors, whose parent is the subscript,
    /// aren't, nor are a local type's members, which the compiler checks
    /// apart from the body declaring the type.
    static func nestedInBody(_ records: [FunctionRecord], types: [TypeRecord]) -> Set<String> {
        let byKey = Dictionary(records.map { ($0.key, $0) }) { first, _ in first }
        let typesByFile = Dictionary(grouping: types, by: \.file)
        let inBody = records.filter { record in
            var seen: Set<String> = [record.key]
            var child = record
            while let key = child.parentKey, seen.insert(key).inserted, let ancestor = byKey[key] {
                let between = (typesByFile[child.file] ?? []).contains { type in
                    ancestor.range.contains(type.range) && type.range.contains(child.range)
                }
                if between {
                    return false
                }
                if bodyKinds.contains(ancestor.kind) {
                    return true
                }
                child = ancestor
            }
            return false
        }
        return Set(inBody.map(\.key))
    }

    /// The class `placement` leaves its entry in; nil when it placed it.
    private static func leftOut(_ placement: Placement) -> LeftOut? {
        switch placement {
        case .build:
            .build

        case .fileChanged:
            .fileChanged

        case .macro:
            .macro

        case .outsideRoot:
            .outsideRoot

        case .synthesized:
            .synthesized

        case .unscanned:
            .unscanned

        case .file, .record, .type:
            nil
        }
    }

    /// The records among `figures`, by key.
    private static func records(_ figures: [Placement: Figures]) -> [BuildRecordTiming] {
        figures.compactMap { placement, held -> BuildRecordTiming? in
            guard case .record(let key) = placement else {
                return nil
            }
            return BuildRecordTiming(
                key: key,
                milliseconds: held.functions.map(milliseconds),
                slowestExpression: held.slowest.map(milliseconds)
            )
        }
        .sorted { $0.key < $1.key }
    }

    /// The types and files among `figures`, by what they attach to, then
    /// owner.
    private static func attachments(_ figures: [Placement: Figures]) -> [BuildAttachment] {
        figures.compactMap { placement, held -> BuildAttachment? in
            let owner: (String, FindingTarget)
            switch placement {
            case .type(let name):
                owner = (name, .type)

            case .file(let path):
                owner = (path, .file)

            case .build, .fileChanged, .macro, .outsideRoot, .record, .synthesized, .unscanned:
                return nil
            }
            return BuildAttachment(
                owner: owner.0,
                attachedTo: owner.1,
                milliseconds: held.functions.map(milliseconds),
                slowestExpression: held.slowest.map(milliseconds)
            )
        }
        .sorted { ($0.attachedTo.rawValue, $0.owner) < ($1.attachedTo.rawValue, $1.owner) }
    }

    /// Where `path`, as the compiler printed it, lies: under the build
    /// directory, else at a path in the package (`SourcePaths`), else
    /// outside the root.
    private func locate(_ path: String) -> Location {
        if path.hasPrefix(build + "/") {
            return .build
        }
        return paths.packagePath(of: path, in: nil).map(Location.inRoot) ?? .outsideRoot
    }

    /// Where `entry` goes.
    func place(_ entry: TimingEntry) -> Placement {
        place(entry, locating: locate)
    }

    /// Where `entry` goes, its path's location given by `locating`.
    private func place(_ entry: TimingEntry, locating: (String) -> Location) -> Placement {
        guard let place = entry.place else {
            return .synthesized
        }
        let name = place.path.split(separator: "/").last.map(String.init) ?? place.path
        if name.hasPrefix(Self.macroBufferPrefix) {
            return .macro
        }
        let inRoot: String
        switch locating(place.path) {
        case .build:
            return .build

        case .outsideRoot:
            return .outsideRoot

        case .inRoot(let path):
            inRoot = path
        }
        let relative = NFCPath(inRoot)
        if changed.contains(relative) {
            return .fileChanged(relative.spelling)
        }
        guard let path = spellings[relative] else {
            return .unscanned(relative.spelling)
        }
        let position = SourcePosition(line: place.line, column: place.column)
        switch placement.place(at: position, end: nil, in: path) {
        case .record(let key):
            return placement.localTypeOwner(at: position, inRecord: key, in: path).map(Placement.type) ?? .record(key)

        case .type(let owner):
            return .type(owner)

        case .file, .unmapped:
            // Only an end unmaps a position, and entries have none.
            return .file(path)
        }
    }

    /// `entries` mapped.
    func map(_ entries: [TimingEntry]) -> Mapped {
        var figures: [Placement: Figures] = [:]
        var left: [LeftOut: (entries: Int, hundredths: Int)] = [:]
        let printed = Set(entries.compactMap { $0.place?.path })
        let locations = Dictionary(uniqueKeysWithValues: printed.map { ($0, locate($0)) })
        for entry in entries {
            let placed = place(entry) { locations[$0] ?? locate($0) }
            guard let leftOut = Self.leftOut(placed) else {
                var held = figures[placed] ?? Figures()
                switch entry.kind {
                case .function:
                    held.functions = Self.sum(held.functions ?? 0, entry.hundredths)

                case .expression:
                    held.slowest = max(held.slowest ?? 0, entry.hundredths)
                }
                figures[placed] = held
                continue
            }
            let tally = left[leftOut] ?? (0, 0)
            left[leftOut] = (tally.entries + 1, Self.sum(tally.hundredths, entry.hundredths))
        }
        let count = { (leftOut: LeftOut) -> BuildEntryCount in
            let tally = left[leftOut] ?? (0, 0)
            return BuildEntryCount(entries: tally.entries, milliseconds: Self.milliseconds(tally.hundredths))
        }
        let counted = figures.compactMapValues(\.functions).filter { placement, _ in
            guard case .record(let key) = placement else {
                return true
            }
            return nested.contains(key) == false
        }
        return Mapped(
            records: Self.records(figures),
            attachments: Self.attachments(figures),
            unmapped: BuildUnmapped(synthesized: count(.synthesized), macro: count(.macro)),
            dropped: BuildDropped(
                build: count(.build),
                outsideRoot: count(.outsideRoot),
                fileChanged: count(.fileChanged),
                unscanned: count(.unscanned)
            ),
            totals: BuildTotals(
                functionEntries: entries.count { $0.kind == .function },
                expressionEntries: entries.count { $0.kind == .expression },
                milliseconds: Self.milliseconds(counted.values.reduce(0, Self.sum))
            ),
            counted: counted
        )
    }
}
