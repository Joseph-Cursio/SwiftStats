//
//  FamilyMatcher.swift
//  SwiftStatsCore
//
//  Matches function families between two snapshots (PRD §6.6): by key, then
//  by key apart from its file-scoped part, then by a unique non-trivial
//  body hash. Everything else is added or removed.
//

/// Matches families between an older and a newer snapshot.
enum FamilyMatcher {
    /// One matched pair of families.
    struct Match {
        /// The family in the older snapshot.
        let old: FunctionFamily
        /// The family in the newer snapshot.
        let new: FunctionFamily
        /// How they were matched.
        let method: MatchMethod
    }

    /// The outcome of matching.
    struct Result {
        /// The matched families.
        let matches: [Match]
        /// Families only in the older snapshot.
        let removed: [FunctionFamily]
        /// Families only in the newer snapshot.
        let added: [FunctionFamily]
        /// Problems worth reporting.
        let warnings: [String]
    }

    /// The matches between `old` and `new`, and what is left on each side.
    static func match(old: [FunctionFamily], new: [FunctionFamily]) -> Result {
        // 1. The same key, held by one family on each side.
        let oldByID = Dictionary(grouping: old, by: \.id)
        let newByID = Dictionary(grouping: new, by: \.id)
        var matches: [Match] = []
        var warnings: [String] = []
        var leftOld: [FunctionFamily] = []
        for (id, families) in oldByID.sorted(by: { $0.key < $1.key }) {
            if families.count == 1, let others = newByID[id], others.count == 1 {
                matches.append(Match(old: families[0], new: others[0], method: .key))
            } else {
                leftOld += families
                if families.count > 1 || (newByID[id]?.count ?? 0) > 1 {
                    warnings.append("key held by several records, matched by location instead: \(id)")
                }
            }
        }
        let matchedNew = Set(matches.map(\.new.id))
        let leftNew = new.filter { matchedNew.contains($0.id) == false || (newByID[$0.id]?.count ?? 0) > 1 }

        // 2. The same key apart from ` @ <file>` and collision locations,
        // held by one family on each side.
        let paired = pairUnique(leftOld, leftNew) { KeyForm.withoutFile($0.id, file: $0.file) }
        matches += paired.pairs.map { Match(old: $0.0, new: $0.1, method: .fileScopedKey) }

        // 3. A unique, non-trivial body hash, with the same kind and module.
        let byHash = matchByHash(paired.unmatchedOld, paired.unmatchedNew)
        let hashOld = Set(byHash.map(\.old.identity))
        let hashNew = Set(byHash.map(\.new.identity))
        return Result(
            matches: matches + byHash,
            removed: paired.unmatchedOld.filter { hashOld.contains($0.identity) == false },
            added: paired.unmatchedNew.filter { hashNew.contains($0.identity) == false },
            warnings: warnings
        )
    }

    /// Pairs the families whose `form` is held by exactly one family on
    /// each side; a form shared by several is no evidence of which is which.
    private static func pairUnique(
        _ old: [FunctionFamily],
        _ new: [FunctionFamily],
        form: (FunctionFamily) -> String
    ) -> Pairing<FunctionFamily> {
        let oldGroups = Dictionary(grouping: old, by: form)
        let newGroups = Dictionary(grouping: new, by: form)
        var pairs: [(FunctionFamily, FunctionFamily)] = []
        var paired: Set<String> = []
        for (key, group) in oldGroups {
            if group.count == 1, let others = newGroups[key], others.count == 1 {
                pairs.append((group[0], others[0]))
                paired.insert(key)
            }
        }
        return Pairing(
            pairs: pairs,
            unmatchedOld: old.filter { paired.contains(form($0)) == false },
            unmatchedNew: new.filter { paired.contains(form($0)) == false }
        )
    }

    /// Matches families whose body hash, kind and module occur once on each
    /// side and whose body, braces aside, has more than one stripped line.
    private static func matchByHash(_ old: [FunctionFamily], _ new: [FunctionFamily]) -> [Match] {
        let signature: (FunctionFamily) -> String = { "\($0.bodyHash)\u{0}\($0.kind.rawValue)\u{0}\($0.module)" }
        let oldBySignature = Dictionary(grouping: old, by: signature)
        let newBySignature = Dictionary(grouping: new, by: signature)
        return oldBySignature.compactMap { value, families in
            guard families.count == 1, families[0].bodyLines > 1,
                  let others = newBySignature[value], others.count == 1 else {
                return nil
            }
            return Match(old: families[0], new: others[0], method: .bodyHash)
        }
    }
}
