import PropertyBased
@testable import SwiftStatsCore
import Testing

/// Properties of `.swiftstats.yml` globs (PRD §10.1, design §4.1.5,
/// decided U8 and B27), over globs and paths from a small alphabet
/// (`GlobGen`): a glob with no wildcard matches exactly its own text and
/// the paths under it, its metacharacters literal; `./p/` and `p` are one
/// glob; and a glob without `**` matches a path only when each of its
/// components matches the path's component in that place, so `*` and `?`
/// never cross `/` (P10.2). And the direct matcher answers as the regular
/// expression it replaced, wherever that reference runs in bounded time
/// (`GlobPatternPBT+Agreement`). `GlobPatternTests` holds the fixed
/// examples, B17's edges among them; each property here has its own,
/// calling its shared check, and meta-tests that feed a planted defect's
/// output to that check.
@Suite("Glob patterns: properties", .tags(.pbt))
struct GlobPatternPBT {
    /// How a glob with no wildcard matches a path, by PRD §10.1.
    enum LiteralMatch: Equatable {
        /// The path doesn't match.
        case miss
        /// The path is a folder or file under the glob's text.
        case under
        /// The path is the glob's text.
        case whole
    }

    /// P10.2's base runs, over the engine's 100: one input costs a few
    /// microseconds, and the rarest antecedent, a star glob without `**`
    /// matching a path under it, comes in 19 of the meta-test's 1,000 cases
    /// (design D14: `(1 - 0.019)^800`, about 2 * 10^-7, is the most a run
    /// misses it; 600 runs would miss it about 10^-5 of the time). The next
    /// rarest, a wildcard joined by a mark filled as the bare wildcard and
    /// the mark, comes in 23.
    static let shapeRuns = 800
    /// What P10.2's tally counts when a glob with no wildcard matches its
    /// path as a whole.
    static let literalWhole = "a literal glob matching its own text"
    /// What it counts when a glob with no wildcard matches a path under it.
    static let literalUnder = "a literal glob matching a path under it"
    /// What it counts when a glob with no wildcard misses its path.
    static let literalMiss = "a literal glob missing its path"
    /// What it counts when a glob with no wildcard holds a metacharacter.
    static let literalMetacharacter = "a literal glob holding a regex metacharacter"
    /// What it counts when a glob starts with `./`.
    static let rootPrefixed = "a glob starting ./"
    /// What it counts when a glob ends in `/`.
    static let slashEnded = "a glob ending in /"
    /// What it counts when a glob with a star or `?` and no `**` matches.
    static let starMatch = "a star glob without ** matching its path"
    /// What it counts when such a glob matches a path under it.
    static let starUnder = "a star glob without ** matching a path under it"
    /// What it counts when a glob holds one of B27's split star forms.
    static let splitStar = "a glob holding a split star form"
    /// What it counts when a glob holds a wildcard or `/` joined by a mark.
    static let markedWildcard = "a glob holding a wildcard joined by a combining mark"
    /// What it counts when a path ends in a line break.
    static let breakEnded = "a path ending in a line break"
    /// What it counts when a path ends in a rarer line break: a vertical
    /// tab, form feed, next line, line separator or paragraph separator.
    static let rarerBreakEnded = "a path ending in a rarer line break"
    /// What it counts when a path holds a rarer line break before its last
    /// scalar.
    static let rarerBreakInside = "a path holding a rarer line break before its end"
    /// What it counts when the path fills one wildcard across a `/`.
    static let slashCrossed = "a wildcard filled across /"
    /// What it counts when the path fills one wildcard across a line
    /// break.
    static let breakCrossed = "a wildcard filled across a line break"
    /// What it counts when the path fills a `?` with a letter and a
    /// combining mark.
    static let markFilled = "a ? filled with a letter and a combining mark"
    /// What it counts when the path fills a wildcard joined by a mark with
    /// what the bare wildcard and the mark would match.
    static let markedFilled = "a wildcard joined by a mark filled as the bare wildcard and the mark"
    /// What it counts when the path fills one metacharacter otherwise.
    static let metacharacterMissed = "a metacharacter filled otherwise"
    /// The antecedents P10.2 must reach at least once each.
    static let shapeAntecedents = [
        literalWhole, literalUnder, literalMiss, literalMetacharacter, rootPrefixed, slashEnded, starMatch, starUnder,
        splitStar, markedWildcard, breakEnded, rarerBreakEnded, rarerBreakInside, slashCrossed, metacharacterMissed,
        markedFilled
    ]

    /// The separator.
    static let separator: Unicode.Scalar = "/"
    /// The line breaks PRD §10.1 names: line feed, vertical tab, form feed,
    /// carriage return, next line, line separator, paragraph separator.
    static let lineBreaks: Set<Unicode.Scalar> = ["\n", "\u{0B}", "\u{0C}", "\r", "\u{85}", "\u{2028}", "\u{2029}"]
    /// The line breaks besides line feed and carriage return.
    static let rarerLineBreaks = Set(GlobGen.rarerLineBreaks.joined().unicodeScalars)
    /// The metacharacters of a regular expression.
    static let metacharacters = Set(GlobGen.metacharacters.joined().unicodeScalars)
    /// The atoms whose edge fills take a wildcard across a `/` or a line
    /// break, or give a `?` a letter and a mark.
    static let wildcardAtoms = Set(GlobGen.wildcards + GlobGen.splitStars)

    /// Records an issue naming `subject`, in ASCII, for each law in `laws`
    /// that fails; whether all hold.
    static func holds(_ laws: [(holds: Bool, law: String)], subject: String) -> Bool {
        for law in laws where law.holds == false {
            Issue.record(Comment(rawValue: PBTTrace.ascii("\(subject) fails: it \(law.law)")))
        }
        return laws.allSatisfy(\.holds)
    }

    /// Whether `core` holds no wildcard: no Character `*` or `?` (one a
    /// combining mark joins is ordinary text).
    static func isLiteral(_ core: String) -> Bool {
        core.contains { $0 == "*" || $0 == "?" } == false
    }

    /// Where `path` may be taken to end, by PRD §10.1: its end, or before
    /// one line break that ends it, `\r\n` counting as one.
    static func ends(of path: [Unicode.Scalar]) -> [Int] {
        if path.count >= 2, path[path.count - 2] == "\r", path[path.count - 1] == "\n" {
            return [path.count, path.count - 2]
        }
        if let last = path.last, lineBreaks.contains(last) {
            return [path.count, path.count - 1]
        }
        return [path.count]
    }

    /// How `core`, a glob with no wildcard, matches `path`, by PRD §10.1:
    /// every Character matches itself, scalar for scalar, and a match
    /// extends to the paths under it, through a `/` and then no line break;
    /// one line break ending the path is ignored.
    static func literalMatch(core: String, path: String) -> LiteralMatch {
        let glob = Array(core.unicodeScalars)
        let scalars = Array(path.unicodeScalars)
        let candidates = ends(of: scalars).map { scalars[..<$0] }
        if candidates.contains(where: { $0.elementsEqual(glob) }) {
            return .whole
        }
        let folder = glob + [separator]
        let under = candidates.contains { candidate in
            candidate.starts(with: folder)
                && candidate.dropFirst(folder.count).allSatisfy { lineBreaks.contains($0) == false }
        }
        return under ? .under : .miss
    }

    /// `core`'s components, split at each `/`, when it holds no `**` and
    /// each of its `/` scalars is a Character of its own; else none. A
    /// core that has them has at least one, maybe empty.
    static func components(of core: String) -> [String] {
        let characters = Array(core)
        let doubleStar = zip(characters, characters.dropFirst()).contains { $0 == "*" && $1 == "*" }
        let joinedSlash = characters.contains { $0 != "/" && $0.unicodeScalars.contains(separator) }
        guard doubleStar == false, joinedSlash == false else {
            return []
        }
        return core.split(separator: "/", omittingEmptySubsequences: false).map(String.init)
    }

    /// `path`'s components, split at each `/` scalar.
    static func components(ofPath path: String) -> [String] {
        path.unicodeScalars
            .split(separator: separator, omittingEmptySubsequences: false)
            .map { String(String.UnicodeScalarView($0)) }
    }

    /// Each component of `input`'s core paired with the path's component in
    /// the same place, as far as both go; none when the core has no
    /// component reading (a path always has a component, maybe empty).
    static func componentPairs(of input: GlobCase) -> [(glob: String, path: String)] {
        Array(zip(components(of: input.core), components(ofPath: input.path)))
    }

    /// The classes `input` falls in, for P10.2's tally and the generator's
    /// meta-test, `coreMatched` saying whether its core matches its path.
    static func shapeLabels(of input: GlobCase, coreMatched: Bool) -> [String] {
        let core = input.core
        let literal = isLiteral(core)
        let match = literal ? literalMatch(core: core, path: input.path) : .miss
        let globParts = components(of: core)
        let starred = literal == false && globParts.isEmpty == false
        let pathParts = components(ofPath: input.path).count
        let pathScalars = Array(input.path.unicodeScalars)
        let wildcardEdge = input.edgeAtom.map { wildcardAtoms.contains(input.atoms[$0]) } == true
        return [
            (literal && match == .whole, literalWhole),
            (literal && match == .under, literalUnder),
            (literal && match == .miss, literalMiss),
            (literal && core.unicodeScalars.contains(where: metacharacters.contains), literalMetacharacter),
            (input.hasRootPrefix, rootPrefixed),
            (input.trailingSlashes > 0, slashEnded),
            (starred && coreMatched, starMatch),
            (starred && coreMatched && pathParts > globParts.count, starUnder),
            (input.atoms.contains(where: GlobGen.splitStars.contains), splitStar),
            (input.atoms.contains(where: GlobGen.markedWildcards.contains), markedWildcard),
            (ends(of: pathScalars).count > 1, breakEnded),
            (pathScalars.last.map(rarerLineBreaks.contains) == true, rarerBreakEnded),
            (pathScalars.dropLast().contains(where: rarerLineBreaks.contains), rarerBreakInside),
            (wildcardEdge && input.edgeFill.unicodeScalars.contains(separator), slashCrossed),
            (wildcardEdge && input.edgeFill.unicodeScalars.contains(where: lineBreaks.contains), breakCrossed),
            (input.edgeAtom.map { GlobGen.metacharacters.contains(input.atoms[$0]) } == true, metacharacterMissed),
            (wildcardEdge && input.edgeFill.unicodeScalars.elementsEqual("e\u{301}".unicodeScalars), markFilled),
            (input.edgeAtom.map { GlobGen.markedWildcards.contains(input.atoms[$0]) } == true, markedFilled)
        ]
        .filter(\.0)
        .map(\.1)
    }

    /// Whether what matching `input` gave obeys P10.2: `matched`, the glob
    /// as written against the path; `coreMatched`, its core against the
    /// path; `sameGlob`, whether the two are equal globs; and `partMatches`,
    /// each core component against the path's component in its place (none
    /// when the core has no component reading). Records an issue for each
    /// law that fails.
    static func checkShape(
        _ input: GlobCase,
        matched: Bool,
        coreMatched: Bool,
        sameGlob: Bool,
        partMatches: [Bool]
    ) -> Bool {
        var laws = [
            (matched == coreMatched, "answers \(matched) as written but \(coreMatched) without ./ and trailing /"),
            (sameGlob, "isn't the same glob as its core")
        ]
        if isLiteral(input.core) {
            let expected = literalMatch(core: input.core, path: input.path) != .miss
            laws.append((coreMatched == expected, "answers \(coreMatched) with no wildcard, expected \(expected)"))
        }
        let globParts = components(of: input.core)
        if globParts.isEmpty == false, coreMatched {
            let pathParts = components(ofPath: input.path)
            laws.append((
                pathParts.count >= globParts.count,
                "matches a path of \(pathParts.count) components, fewer than its \(globParts.count)"
            ))
            if let missed = partMatches.firstIndex(of: false) {
                laws.append((false, "matches, but its component \(missed) misses the path's component \(missed)"))
            }
        }
        return holds(laws, subject: "the glob")
    }

    // MARK: P10.2

    /// Invariant: a glob with no wildcard matches exactly its own text and
    /// the paths under it, metacharacters and all; `./p/` and `p` are one
    /// glob, matching the same paths; and a glob without `**` matches a
    /// path only when the path has as many components or more and each of
    /// the glob's matches the path's in its place, so `*` and `?` never
    /// cross `/`.
    /// Why it holds: PRD §10.1's glob paragraph (one leading `./` and every
    /// trailing `/` ignored; `*` and `?` within one component; every other
    /// Character matching itself; every match extending to the paths
    /// under it, decided U8; one line break ending the path ignored) and
    /// `GlobPattern`'s header.
    /// Why it might not: the core never starts with `./` (only one is
    /// dropped, so `././p` isn't `./p`), is never `.` (`./` reads as the
    /// root prefix before an empty glob, not as `.` and a trailing `/`:
    /// pinned in `GlobPatternTests`) and never ends in a Prepend scalar
    /// (the `/` after it would join it and not be dropped); the converse of
    /// the component law fails on line breaks (a component ending in one
    /// matches alone, as the path's end, but not within the path), so only
    /// the implication is asserted.
    /// Oracle: PRD §10.1 read on scalars for literal globs; metamorphic
    /// otherwise; planted defects: a star crossing `/`, a `?` matching
    /// `/`, the leading `./` kept, the trailing `/` kept, no folder
    /// extension, `.` read as a wildcard, `\r\n` not ignored as one
    /// break, no final break ignored, the folder extension crossing a
    /// line break, a next line or paragraph separator not read as a line
    /// break, and the glob read in scalars, each detected.
    /// Tier: Strict (stop-ship).
    @Test(
        """
        a glob with no wildcard matches its own text and the paths under it, ./p/ is p, and without ** each \
        component matches in its place
        """,
        .timeLimit(PBTBudget.timeLimit)
    )
    func globsKeepTheirShape() async {
        let latch = FirstFailureLatch()
        let tally = AntecedentTally()
        await propertyCheck(count: PBTBudget.runs(Self.shapeRuns), input: GlobGen.unbounded) { input in
            PBTTrace.note(input)
            let coreMatched = GlobPattern(input.core).matches(input.path)
            Self.shapeLabels(of: input, coreMatched: coreMatched).forEach(tally.fire)
            let passed = Self.checkShape(
                input,
                matched: GlobPattern(input.glob).matches(input.path),
                coreMatched: coreMatched,
                sameGlob: GlobPattern(input.glob) == GlobPattern(input.core),
                partMatches: Self.componentPairs(of: input).map { GlobPattern($0.glob).matches($0.path) }
            )
            if passed == false {
                PBTTrace.firstFailure(input, latch: latch)
            }
        }
        tally.report()
        tally.requireFired(Self.shapeAntecedents, unlessFailed: latch, sourceLocation: #_sourceLocation)
    }
}
