//
//  MutationMapper.swift
//  SwiftStatsCore
//
//  Maps a SwiftMutator run's mutants onto the scan (M6, design §3). A
//  mutant's path is relative to the project SwiftMutator ran in, the
//  package. Its file is sorted first match winning: under a `.build`
//  folder, outside the root, in a test target's directory, not Swift, and
//  in no target's directory are dropped by design (each kept with its class
//  as its reason); a production file the scan didn't parse is unmapped
//  (`excluded` or `not parsed`); a parsed one is kept. Paths compare in
//  NFC, and kept files whose paths are equal case-folded get a warning. In
//  a kept file, a mutant whose file hash (a not-covered one's tree hash)
//  isn't the scanned bytes' hash is unmapped `file changed`, `symlink` for
//  a symbolic link's `link:` hash (SwiftMutator hashes the path a link
//  points to, SwiftStats the bytes), `no file hash` when none is recorded.
//  The rest are anchored (`MutantAnchoring`) and placed by their anchor
//  (`PositionPlacement`): on the innermost production record holding it,
//  else attached to the innermost type, else to the file. The report also
//  lists the run's tree, every Swift path of its last header, each
//  production path `tested` by the run and every other one `untested`
//  (`MutationMapper+Report`, whose pieces a `--since` merge uses too).
//

import Foundation

/// Maps a SwiftMutator run's mutants onto the scan's records.
struct MutationMapper {
    /// Where a mutant went.
    struct Placed: Equatable {
        /// Where.
        let place: MutationPlace
        /// The record's key, the type's owner text or the file's path.
        let owner: String?
        /// Why it is unmapped, or the class that dropped it.
        let reason: String?
        /// Its anchor in the scanned file.
        let anchor: SourcePosition?
    }

    /// The rule the `map:` option records: what changes it changes where
    /// mutants go.
    static let rule = "kept = scanned production files whose bytes hash to the mutant's fileSHA256; point = (line, "
        + "UTF-8 column, +3 on line 1 after a BOM); anchor = the token starting at the point, else the next token for "
        + "relational, logical and boundary swaps, else the last character of the previous token; anchor to the "
        + "innermost record holding it, top-level code by statement lines; closures folded; else innermost type, "
        + "else file"
    /// Why a kept file's mutant tested other bytes than the scan read.
    static let fileChanged = "file changed"
    /// Why a kept file's mutant whose file SwiftMutator hashed as a
    /// symbolic link is unmapped.
    static let symlink = "symlink"
    /// Why a kept file's mutant with no file hash is unmapped.
    static let noFileHash = "no file hash"
    /// Why a mutant at a point its file doesn't hold is unmapped.
    static let noSuchPosition = "position outside its file"
    /// The folder name whose files are build products, at any depth.
    private static let buildFolder = ".build"
    /// What a path relative to the root may start with.
    private static let currentDirectory = "./"
    /// What a Swift file's name ends with.
    static let swiftExtension = ".swift"

    /// Sorts the mutants' files.
    private let classifier: PackageFileClassifier
    /// Places anchors.
    private let placement: PositionPlacement
    /// The parsed files, by path.
    private let parsed: [String: ParsedFile]
    /// The parsed files' paths, by their NFC spelling.
    private let spellings: [String: String]
    /// Kept files whose paths are equal case-folded, each group sorted.
    private let caseFolded: [[String]]

    /// The problems the mapping found in the scan's files: kept files whose
    /// paths differ only in case.
    var warnings: [ScanWarning] {
        caseFolded.map { paths in
            MutationSession.warning(
                paths.joined(separator: ", ") + " differ only in case, which a case-insensitive volume can't tell "
                    + "apart, so their mutants may be mapped to the wrong one"
            )
        }
    }

    /// A mapper onto `measured`, the package with `targets`, whose
    /// configuration excludes `excluded`.
    init(measured: ScanMeasurements, targets: [TargetSummary], excluded: [GlobPattern]) {
        let paths = Set(measured.files.map(\.path))
        classifier = PackageFileClassifier(targets: targets, parsed: paths, excluded: excluded)
        placement = PositionPlacement(measured: measured)
        let files = measured.parsed.map(\.file)
        parsed = Dictionary(files.map { ($0.path, $0) }) { first, _ in first }
        spellings = Dictionary(files.map { (Self.normalized($0.path), $0.path) }) { first, _ in first }
        let testModules = Set(targets.filter(\.isTest).map(\.name))
        let production = measured.parsed.filter { testModules.contains($0.module) == false }.map(\.file.path)
        caseFolded = Dictionary(grouping: Set(production)) { Self.normalized($0).lowercased() }.values
            .filter { $0.count > 1 }
            .map { $0.sorted() }
            .sorted { $0.joined() < $1.joined() }
    }

    /// `path` in Unicode's canonical composition (NFC), as SwiftMutator's
    /// own report also looks paths up.
    static func normalized(_ path: String) -> String {
        path.precomposedStringWithCanonicalMapping
    }

    /// The record of the run that left `results`, the `ordinal`th of the
    /// snapshot, kept at `resultsFile` (from the package root), testing
    /// the tree of `git`, whose kills `suspects` judged.
    static func run(
        _ results: MutationResults,
        ordinal: Int,
        resultsFile: String,
        git: GitState?,
        suspects: SuspectReport
    ) -> MutationRunRecord {
        let facts = results.facts
        return MutationRunRecord(
            ordinal: ordinal,
            identity: MutationAdapter.identity(of: facts),
            version: facts.version,
            startedAt: facts.startedAt,
            endedAt: results.end?.endedAt,
            endReason: results.end?.reason,
            commit: git?.commit,
            dirty: git?.isDirty ?? false,
            mode: facts.since == nil ? .full : .since,
            sessions: results.sessions,
            since: facts.since.map { MutationSinceRevision(ref: $0.ref, commit: $0.commit, mergeBase: $0.mergeBase) },
            carriedFrom: nil,
            resultsFile: resultsFile,
            resultsSHA256: results.sha256,
            formatVersions: results.formatVersions,
            operators: facts.operators.sorted(),
            skipCoverage: facts.skipCoverage,
            listsNotCovered: results.listsNotCovered,
            workers: facts.workers,
            timeoutSeconds: facts.timeoutSeconds,
            stopsAtFirstFailure: facts.stopsAtFirstFailure,
            suspectsJudged: suspects.read ? JSONFlag(suspects.suspectsChecked) : nil,
            mutantsDiscovered: facts.mutantsDiscovered,
            mutantsDropped: facts.mutantsDropped,
            controlRuns: results.controlRuns,
            controlFailures: results.controlFailures,
            toolchain: facts.testCommandVersion?.split(whereSeparator: \.isNewline).first.map(String.init),
            testExecutableSHA256: facts.testExecutableSHA256,
            sdkEnvironment: facts.sdkEnvironment.isEmpty ? nil : MutationAdapter.sdkEnvironment(facts.sdkEnvironment)
        )
    }

    /// The mutant `recorded`, placed as `placed`, tested by run `ordinal`,
    /// whose kill `suspects` judged.
    static func mutant(
        _ recorded: RecordedMutant,
        placed: Placed,
        run ordinal: Int,
        suspects: SuspectReport
    ) -> Mutant {
        Mutant(
            path: recorded.key.path,
            line: recorded.key.line,
            column: recorded.key.column,
            occurrence: recorded.key.occurrence,
            operatorID: recorded.key.operatorID,
            anchor: placed.anchor,
            verdict: recorded.verdict,
            outcome: recorded.outcome,
            activated: recorded.activated.flag,
            endedBy: recorded.endedBy,
            exitStatus: recorded.exitStatus,
            killedBy: recorded.killedBy,
            killedByComplete: recorded.killedByComplete.flag,
            failedTestCount: recorded.failedTestCount,
            suspectOnly: suspects.judgement(of: recorded).flag,
            fileSHA256: recorded.fileSHA256,
            before: recorded.before,
            after: recorded.after,
            description: recorded.description,
            run: ordinal,
            session: recorded.session,
            durationSeconds: recorded.durationSeconds,
            carried: false,
            reused: recorded.reused,
            rerun: recorded.rerunBecause,
            place: placed.place,
            owner: placed.owner,
            reason: placed.reason
        )
    }

    /// Where a mutant in a file of `fileClass`, which isn't kept, goes:
    /// unmapped for its reason, or dropped by its class.
    private static func notKept(_ fileClass: PackageFileClass) -> Placed {
        switch fileClass {
        case .kept:
            unmapped(PackageFileClassifier.notParsedReason)

        case let .unmapped(_, _, reason):
            unmapped(reason)

        case .build:
            dropped(MutationDropped.buildReason)

        case .outsideRoot:
            dropped(MutationDropped.outsideRootReason)

        case .testFile:
            dropped(MutationDropped.testFilesReason)

        case .otherLanguage:
            dropped(MutationDropped.otherLanguageReason)

        case .otherPackage:
            dropped(MutationDropped.otherPackageReason)
        }
    }

    /// Why a mutant with file hash `hash` can't be mapped in a kept file
    /// whose scanned bytes hash to `scanned`; nil when it can.
    private static func hashRefusal(_ hash: String?, scanned: String) -> String? {
        guard let hash else {
            return noFileHash
        }
        if hash.hasPrefix(MutationTree.linkPrefix) {
            return symlink
        }
        return hash == scanned ? nil : fileChanged
    }

    /// A mutant dropped by `reason`, its class.
    private static func dropped(_ reason: String) -> Placed {
        Placed(place: .dropped, owner: nil, reason: reason, anchor: nil)
    }

    /// A mutant unmapped for `reason`.
    private static func unmapped(_ reason: String) -> Placed {
        Placed(place: .unmapped, owner: nil, reason: reason, anchor: nil)
    }

    /// Where `mutant` goes, anchored with `anchorings`, which gains each
    /// kept file's anchoring the first time one of its mutants needs it.
    func place(_ mutant: RecordedMutant, anchorings: inout [String: MutantAnchoring]) -> Placed {
        place(mutant.key, fileSHA256: mutant.fileSHA256, after: mutant.after, anchorings: &anchorings)
    }

    /// Where the mutant at `key`, whose file hashed to `fileSHA256` and
    /// which makes `after`, goes, anchored with `anchorings` as `place`
    /// takes them.
    func place(
        _ key: MutantKey,
        fileSHA256: String?,
        after: String,
        anchorings: inout [String: MutantAnchoring]
    ) -> Placed {
        let fileClass = classify(key.path)
        guard case .kept(let path, _) = fileClass, let file = parsed[path] else {
            return Self.notKept(fileClass)
        }
        if let reason = Self.hashRefusal(fileSHA256, scanned: file.sha256) {
            return Self.unmapped(reason)
        }
        let anchoring = anchorings[path] ?? MutantAnchoring(file)
        anchorings[path] = anchoring
        guard let anchor = anchoring.anchor(
            line: key.line,
            column: key.column,
            operatorID: key.operatorID,
            after: after
        ) else {
            return Self.unmapped(Self.noSuchPosition)
        }
        switch placement.place(at: anchor, end: nil, in: path) {
        case .record(let owner):
            return Placed(place: .record, owner: owner, reason: nil, anchor: anchor)

        case .type(let owner):
            return Placed(place: .type, owner: owner, reason: nil, anchor: anchor)

        case .file:
            return Placed(place: .file, owner: path, reason: nil, anchor: anchor)

        case .unmapped(let reason):
            return Placed(place: .unmapped, owner: nil, reason: reason, anchor: anchor)
        }
    }

    /// The class of the file at `path`, relative to the project: a leading
    /// `./` taken off, under a `.build` folder at any depth a build product,
    /// else as `PackageFileClassifier` sorts it, spelled as the scan spells
    /// the parsed file of the same NFC spelling, if any.
    func classify(_ path: String) -> PackageFileClass {
        var relative = path
        while relative.hasPrefix(Self.currentDirectory) {
            relative.removeFirst(Self.currentDirectory.count)
        }
        let normal = Self.normalized(relative)
        if normal.split(separator: "/").contains(Substring(Self.buildFolder)) {
            return .build
        }
        return classifier.classify(spellings[normal] ?? normal)
    }
}
