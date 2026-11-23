//
//  MutationCopy.swift
//  SwiftStatsCore
//
//  One clone copy with its mutants (M6, uneven clone testing, mutation
//  part, design §7.4): the mapped mutants of its file whose anchor lies in
//  its inclusive range, whatever they were placed on, counted as a
//  function's are, with the function score they come to and the family
//  naming the copy.
//

/// A clone copy and its mutants.
struct MutationCopy {
    /// The verdicts of mutants the tests didn't kill.
    private static let notKilled: Set<MutationVerdict> = [.survived, .timedOut, .noCoverage, .notCovered]

    /// The copy.
    let instance: CloneInstance
    /// Its mutants, by anchor, then key.
    let mutants: [Mutant]
    /// Those mutants counted.
    let counts: MutationCounts
    /// What they come to.
    let figures: MutationFigures
    /// The family naming it, by M4's copy-to-family rule; `<file>:<line>`
    /// when no family holds it.
    let family: String

    /// Its function score: killed of its scored mutants.
    var score: MutationScore {
        figures.functionScore
    }

    /// Its mutants the tests didn't kill (survived, timed out, no coverage
    /// or not covered), by anchor, then key.
    var unkilled: [Mutant] {
        mutants.filter { Self.notKilled.contains($0.verdict) }
    }

    /// Its file.
    var file: String {
        instance.file
    }

    /// Its first line.
    var start: Int {
        instance.range.start.line
    }

    /// Its last line.
    var end: Int {
        instance.range.end.line
    }

    /// The copy as an item lists it.
    var listed: SignalItem.MutatedCopy {
        SignalItem.MutatedCopy(
            file: file,
            line: start,
            family: family,
            killed: score.killed,
            scored: score.scored,
            runButUnchecked: figures.runButUnchecked,
            unrun: figures.unrun
        )
    }

    /// A copy of `instance` holding `mutants`, named by `family`.
    init(instance: CloneInstance, mutants: [Mutant], family: String) {
        self.instance = instance
        self.mutants = mutants
        self.family = family
        counts = MutationCounts(mutants)
        figures = MutationFigures(counts)
    }

    /// Whether this copy lies inside `other`: the same file, within its
    /// lines, as uneven clone testing's coverage part judges copies.
    func lies(inside other: Self) -> Bool {
        file == other.file && other.start <= start && end <= other.end
    }
}
