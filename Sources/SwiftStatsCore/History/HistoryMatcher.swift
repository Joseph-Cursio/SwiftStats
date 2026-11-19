//
//  HistoryMatcher.swift
//  SwiftStatsCore
//
//  What one commit did to each function family it touched (PRD §7.13):
//  the families of the old and new versions of the changed files, matched
//  with diff's rules (§6.6) plus three that only history uses: the same key
//  across a move to another target, the same name after a signature change,
//  and a similar body. A family's change is any §6.6 status but a pure move.
//

/// Matches families across one commit.
enum HistoryMatcher {
    /// The share of lines two bodies must share for a similar-body match.
    static let similarity = 0.7
    /// Above this many candidate pairs, similar bodies aren't looked for.
    private static let maximumSimilarPairs = 250_000

    /// The events of a commit whose changed files were `old` before and `new`
    /// after. `moduleMoves` maps an old file to its new module when a rename
    /// moved it to another target.
    static func events(old: CommitSide, new: CommitSide, moduleMoves: [String: String]) -> [HistoryEvent] {
        let (movedSide, originalModules) = moved(old, moduleMoves: moduleMoves)
        let oldFamilies = FunctionFamily.families(movedSide.rows)
        var originalIDs: [FamilyRef: String] = [:]
        for family in oldFamilies {
            if let module = originalModules[family.file] {
                originalIDs[FamilyRef(family)] = module + "::" + stripModule(family.id)
            }
        }
        let newFamilies = FunctionFamily.families(new.rows)
        let base = FamilyMatcher.match(old: oldFamilies, new: newFamilies)
        // A key that only matched because its module was rewritten is a
        // module-moved key, however git saw the move.
        var matches = base.matches.map { match -> FamilyMatcher.Match in
            guard originalModules[match.old.file] != nil,
                  match.method.uncertainty < MatchMethod.moduleMovedKey.uncertainty else {
                return match
            }
            return FamilyMatcher.Match(old: match.old, new: match.new, method: .moduleMovedKey)
        }
        let moduleMoved = pairUnique(base.removed, base.added) { family in
            stripModule(KeyForm.withoutFile(family.id, file: family.file))
        }
        matches += moduleMoved.pairs.map { FamilyMatcher.Match(old: $0.0, new: $0.1, method: .moduleMovedKey) }
        let renamed = pairUnique(moduleMoved.unmatchedOld, moduleMoved.unmatchedNew, form: nameForm)
        matches += renamed.pairs.map { FamilyMatcher.Match(old: $0.0, new: $0.1, method: .sameName) }
        let similar = similarPairs(renamed.unmatchedOld, renamed.unmatchedNew, old: movedSide, new: new)
        matches += similar.pairs.map { FamilyMatcher.Match(old: $0.0, new: $0.1, method: .similarBody) }

        let reference: (FunctionFamily) -> FamilyRef = { family in
            let ref = FamilyRef(family)
            return FamilyRef(id: originalIDs[ref] ?? ref.id, file: ref.file)
        }
        var events: [HistoryEvent] = []
        for match in matches {
            let changed = isChanged(match)
            let oldRef = reference(match.old)
            let newRef = FamilyRef(match.new)
            if changed || oldRef != newRef {
                events.append(HistoryEvent(old: oldRef, new: newRef, changed: changed, method: match.method))
            }
        }
        events += similar.unmatchedOld.map { HistoryEvent(old: reference($0), new: nil, changed: true, method: nil) }
        events += similar.unmatchedNew.map { HistoryEvent(old: nil, new: FamilyRef($0), changed: true, method: nil) }
        return events
    }

    /// `side` with the rows of each file `moduleMoves` moves to another
    /// target rewritten as if they had always been in it, keeping their line
    /// hashes for similar bodies, and each moved file's original module, for
    /// the chain's original ids.
    private static func moved(
        _ side: CommitSide,
        moduleMoves: [String: String]
    ) -> (side: CommitSide, originalModules: [String: String]) {
        var movedSide = CommitSide(rows: [], lines: side.lines)
        var originalModules: [String: String] = [:]
        for row in side.rows {
            guard let module = moduleMoves[row.file], module != row.module else {
                movedSide.rows.append(row)
                continue
            }
            let moved = Self.row(row, inModule: module)
            if let hashes = side.lines[row.file + "\u{0}" + row.key] {
                movedSide.lines[moved.file + "\u{0}" + moved.key] = hashes
            }
            originalModules[row.file] = originalModules[row.file] ?? row.module
            movedSide.rows.append(moved)
        }
        return (movedSide, originalModules)
    }

    /// `key` without its leading `<module>::`.
    static func stripModule(_ key: String) -> String {
        guard let range = key.range(of: "::") else {
            return key
        }
        return String(key[range.upperBound...])
    }

    /// Whether a matched family changed: a member's body, its members, its
    /// name or signature, or its access, but not only its file or module.
    private static func isChanged(_ match: FamilyMatcher.Match) -> Bool {
        let members = MemberPairing.pair(match.old, match.new)
        if members.pairs.contains(where: { $0.0.bodyHash != $0.1.bodyHash })
            || members.unmatchedOld.isEmpty == false || members.unmatchedNew.isEmpty == false {
            return true
        }
        let (old, new) = (match.old, match.new)
        if stripModule(KeyForm.withoutFile(old.id, file: old.file))
            != stripModule(KeyForm.withoutFile(new.id, file: new.file)) {
            return true
        }
        return KeyForm.hasFileSegment(old.id, file: old.file) != KeyForm.hasFileSegment(new.id, file: new.file)
    }

    /// `row` as if its file were in `module`.
    private static func row(_ row: FunctionRow, inModule module: String) -> FunctionRow {
        var moved = row
        moved.key = module + "::" + stripModule(row.key)
        moved.parentKey = row.parentKey.map { module + "::" + stripModule($0) }
        moved.module = module
        return moved
    }

    /// The form a signature change keeps: file, kind, enclosing type, name,
    /// and whether it is a type-level member.
    private static func nameForm(_ family: FunctionFamily) -> String {
        let core = stripModule(family.id)
        let enclosing = core.range(of: "::", options: .backwards).map { String(core[..<$0.lowerBound]) } ?? ""
        let declaration = core.range(of: "::", options: .backwards).map { String(core[$0.upperBound...]) } ?? core
        let typeLevel = declaration.hasPrefix("static ") || declaration.hasPrefix("class ")
        let name = family.root?.name ?? family.members[0].name
        return [family.file, family.kind.rawValue, enclosing, name, typeLevel ? "type" : "instance"]
            .joined(separator: "\u{0}")
    }

    /// Pairs the families whose `form` is held by exactly one family on each side.
    private static func pairUnique(
        _ old: [FunctionFamily],
        _ new: [FunctionFamily],
        form: (FunctionFamily) -> String
    ) -> Pairing<FunctionFamily> {
        let oldGroups = Dictionary(grouping: old, by: form)
        let newGroups = Dictionary(grouping: new, by: form)
        var pairs: [(FunctionFamily, FunctionFamily)] = []
        var paired: Set<String> = []
        for (value, group) in oldGroups.sorted(by: { $0.key < $1.key }) {
            if group.count == 1, let others = newGroups[value], others.count == 1 {
                pairs.append((group[0], others[0]))
                paired.insert(value)
            }
        }
        return Pairing(
            pairs: pairs,
            unmatchedOld: old.filter { paired.contains(form($0)) == false },
            unmatchedNew: new.filter { paired.contains(form($0)) == false }
        )
    }

    /// Families of the same kind and module whose bodies share at least
    /// `similarity` of their lines, each the other's only best match.
    private static func similarPairs(
        _ old: [FunctionFamily],
        _ new: [FunctionFamily],
        old oldSide: CommitSide,
        new newSide: CommitSide
    ) -> Pairing<FunctionFamily> {
        guard old.isEmpty == false, new.isEmpty == false, old.count * new.count <= maximumSimilarPairs else {
            return Pairing(pairs: [], unmatchedOld: old, unmatchedNew: new)
        }
        let oldLines = old.map { lines(of: $0, in: oldSide) }
        let newLines = new.map { lines(of: $0, in: newSide) }
        var bestForOld: [Int: BestMatch] = [:]
        var bestForNew: [Int: BestMatch] = [:]
        for (oldIndex, family) in old.enumerated() where oldLines[oldIndex].count >= HistoryParser.minimumSimilarLines {
            for (newIndex, other) in new.enumerated()
            where other.kind == family.kind && other.module == family.module
                && newLines[newIndex].count >= HistoryParser.minimumSimilarLines {
                let score = jaccard(oldLines[oldIndex], newLines[newIndex])
                guard score >= similarity else {
                    continue
                }
                bestForOld[oldIndex] = better(bestForOld[oldIndex], index: newIndex, score: score)
                bestForNew[newIndex] = better(bestForNew[newIndex], index: oldIndex, score: score)
            }
        }
        var pairs: [(FunctionFamily, FunctionFamily)] = []
        var pairedOld: Set<Int> = []
        var pairedNew: Set<Int> = []
        for (oldIndex, best) in bestForOld.sorted(by: { $0.key < $1.key }) where best.tied == false {
            if let back = bestForNew[best.index], back.tied == false, back.index == oldIndex {
                pairs.append((old[oldIndex], new[best.index]))
                pairedOld.insert(oldIndex)
                pairedNew.insert(best.index)
            }
        }
        return Pairing(
            pairs: pairs,
            unmatchedOld: old.indices.filter { pairedOld.contains($0) == false }.map { old[$0] },
            unmatchedNew: new.indices.filter { pairedNew.contains($0) == false }.map { new[$0] }
        )
    }

    /// The better of `current` and a candidate, marking a tie.
    private static func better(
        _ current: BestMatch?,
        index: Int,
        score: Double
    ) -> BestMatch {
        guard let current else {
            return BestMatch(index: index, score: score, tied: false)
        }
        if score > current.score {
            return BestMatch(index: index, score: score, tied: false)
        }
        if score == current.score {
            return BestMatch(index: current.index, score: score, tied: true)
        }
        return current
    }

    /// A family's body lines: its root's, or its accessors' together.
    private static func lines(of family: FunctionFamily, in side: CommitSide) -> [UInt64] {
        let rows = family.root.map { [$0] } ?? family.accessors
        let all = rows.flatMap { side.lines[$0.file + "\u{0}" + $0.key] ?? [] }
        return Array(Set(all)).sorted()
    }

    /// The Jaccard similarity of two sorted, unique lists.
    static func jaccard(_ lhs: [UInt64], _ rhs: [UInt64]) -> Double {
        var shared = 0
        var left = 0
        var right = 0
        while left < lhs.count, right < rhs.count {
            if lhs[left] == rhs[right] {
                shared += 1
                left += 1
                right += 1
            } else if lhs[left] < rhs[right] {
                left += 1
            } else {
                right += 1
            }
        }
        let union = lhs.count + rhs.count - shared
        return union == 0 ? 0 : Double(shared) / Double(union)
    }
}
