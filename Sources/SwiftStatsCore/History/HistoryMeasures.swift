//
//  HistoryMeasures.swift
//  SwiftStatsCore
//
//  Each family's numbers from its lineage and the commits' facts (PRD
//  §7.13): churn in the window with sweeps set apart, fixes and their
//  age-weighted score, reverts, repeated fixes, tests changed alongside,
//  first and last change; and the pairs of families that change together.
//

import Foundation

/// Turns lineages into per-family history.
struct HistoryMeasures {
    /// Scores are rounded to this many steps per unit: four decimal places.
    private static let roundingScale = 10_000.0
    /// The share a fix keeps after one half-life.
    private static let halfLifeShare = 0.5

    /// The lineages and the scan families joined to them.
    let chain: HistoryChain
    /// Each commit's facts, newest first.
    let facts: [CommitFacts]
    /// The analysed commit's time.
    let anchor: Int
    /// The options.
    let options: HistoryOptions
    /// Finds tests by name.
    let tests: TestNameMatcher
    /// Generated files.
    let generated: Set<String>
    /// The position in the commit log of each logged commit's index in `facts`.
    let logOrdinals: [Int: Int]

    /// Rounds a score to four decimal places, so the JSON is stable.
    private static func rounded(_ value: Double) -> Double {
        (value * roundingScale).rounded() / roundingScale
    }

    /// Every scan family's history, by file, line and id.
    func families() -> [FamilyHistory] {
        let allFamilies = chain.families.map { family, lineage in
            let line = family.startLine
            let isGenerated = generated.contains(family.file)
            let matchingTests = tests.matches(file: family.file, typeName: TestNameMatcher.typeName(of: family.id))
            guard let lineage else {
                return FamilyHistory(
                    family: family.id,
                    file: family.file,
                    line: line,
                    generated: isGenerated,
                    changes: nil,
                    sweepChanges: nil,
                    allChanges: nil,
                    fixes: nil,
                    allFixes: nil,
                    fixScore: nil,
                    fixRate: nil,
                    reverts: nil,
                    repeatedFixes: nil,
                    testChanges: nil,
                    hasTests: matchingTests.isEmpty == false,
                    firstSeen: nil,
                    lastChanged: nil,
                    tracedBy: .uncommitted,
                    changedBy: nil
                )
            }
            return history(of: family, lineage: chain.lineages[lineage], matchingTests: matchingTests)
        }
        return allFamilies.sorted { lhs, rhs in
            (lhs.file, lhs.line, lhs.family) < (rhs.file, rhs.line, rhs.family)
        }
    }

    /// The history of `family` from `lineage`.
    private func history(of family: FunctionFamily, lineage: Lineage, matchingTests: Set<String>) -> FamilyHistory {
        let changes = lineage.changes.map { facts[$0] }
        let recent = changes.filter(\.inWindow)
        let counted = recent.filter { fact in fact.isSweep == false }
        let fixes = changes.filter(\.isFix)
        let recentFixes = counted.filter(\.isFix)
        let halfLife = Double(options.halfLifeDays * HistoryCollector.day)
        let score = fixes.reduce(0.0) { total, fix in
            total + pow(Self.halfLifeShare, Double(max(0, anchor - fix.time)) / halfLife)
        }
        let fixTimes = fixes.map(\.time).sorted()
        let repeatSpan = options.repeatWindowDays * HistoryCollector.day
        let repeated = fixTimes.indices.dropFirst().filter { index in
            fixTimes[index] >= anchor - options.windowDays * HistoryCollector.day
                && fixTimes[index] - fixTimes[index - 1] <= repeatSpan
        }.count
        return FamilyHistory(
            family: family.id,
            file: family.file,
            line: family.startLine,
            generated: generated.contains(family.file),
            changes: counted.count,
            sweepChanges: recent.count - counted.count,
            allChanges: changes.count,
            fixes: recentFixes.count,
            allFixes: fixes.count,
            fixScore: Self.rounded(score),
            fixRate: counted.isEmpty ? nil : Self.rounded(Double(recentFixes.count) / Double(counted.count)),
            reverts: counted.filter(\.isRevert).count,
            repeatedFixes: repeated,
            testChanges: counted.filter { fact in fact.testNames.isDisjoint(with: matchingTests) == false }.count,
            hasTests: matchingTests.isEmpty == false,
            firstSeen: lineage.birth.map { HistoryCollector.date(facts[$0].time) },
            lastChanged: changes.map(\.time).max().map(HistoryCollector.date),
            tracedBy: lineage.weakest.map(TracedBy.init) ?? .key,
            changedBy: CommitOrdinals(lineage.changes.compactMap { logOrdinals[$0] })
        )
    }

    /// Pairs of families changed together by at least `minimumSupport`
    /// non-sweep commits in the window.
    func coupling(minimumSupport: Int) -> [CouplingPair] {
        var byCommit: [Int: [Int]] = [:]
        var changeCounts: [Int: Int] = [:]
        for (position, entry) in chain.families.enumerated() {
            guard let lineage = entry.lineage else {
                continue
            }
            let changes = chain.lineages[lineage].changes
            for commit in changes where facts[commit].inWindow && facts[commit].isSweep == false {
                byCommit[commit, default: []].append(position)
                changeCounts[position, default: 0] += 1
            }
        }
        var support: [Int: [Int: Int]] = [:]
        for positions in byCommit.values {
            let sorted = positions.sorted()
            for (offset, first) in sorted.enumerated() {
                for second in sorted[(offset + 1)...] {
                    support[first, default: [:]][second, default: 0] += 1
                }
            }
        }
        var pairs: [CouplingPair] = []
        for (first, partners) in support {
            for (second, count) in partners where count >= minimumSupport {
                var (left, right) = (chain.families[first].family, chain.families[second].family)
                var (leftCount, rightCount) = (changeCounts[first] ?? 0, changeCounts[second] ?? 0)
                if (right.id, right.file) < (left.id, left.file) {
                    swap(&left, &right)
                    swap(&leftCount, &rightCount)
                }
                pairs.append(CouplingPair(
                    familyA: left.id,
                    fileA: left.file,
                    familyB: right.id,
                    fileB: right.file,
                    support: count,
                    changesA: leftCount,
                    changesB: rightCount
                ))
            }
        }
        return pairs.sorted { lhs, rhs in
            (rhs.support, lhs.familyA, lhs.fileA, lhs.familyB, lhs.fileB)
                < (lhs.support, rhs.familyA, rhs.fileA, rhs.familyB, rhs.fileB)
        }
    }
}
