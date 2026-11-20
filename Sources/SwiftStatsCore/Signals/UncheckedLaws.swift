//
//  UncheckedLaws.swift
//  SwiftStatsCore
//
//  Unchecked laws (PRD §8): easy law coverage to add. The pool is the
//  production types with a law-check pair outside generated files. A type
//  is listed when at least one such pair is not run and its witnesses are
//  written by hand, scored by how many; the signal isn't ranked. Pairs
//  whose witnesses the compiler synthesises are left out and counted: they
//  are lawful by construction, though not guaranteed to be.
//

/// The unchecked-laws signal.
enum UncheckedLaws {
    /// The provenances a listed pair can have: every way the type comes to conform.
    static let provenances: Set<LawCheck.Provenance> = [.codable, .declared, .rawValueEnum]

    /// The rule as reports state it, before the pairs are counted.
    static let rule = "production types with a hand-written witness for a conformance the kit checks, "
        + "and no check run"

    /// The signal over `snapshot`.
    static func compute(_ snapshot: StoredSnapshot) -> SignalComputation {
        let pairs = snapshot.lawChecks.filter { $0.generated == false }
        let byType = Dictionary(grouping: pairs, by: \.type)
        let synthesized = pairs.filter { $0.state == .unchecked && $0.implementation == .synthesized }.count
        let kitDependency = snapshot.scanFacts?.kitDependency == true
        let leftOut = "; \(synthesized) unchecked pairs with synthesised witnesses are left out: lawful by "
            + "construction, though not guaranteed (floating-point members, members with their own ==)"
        return SignalComputation(
            rule: rule + leftOut,
            candidates: byType.count,
            scored: byType.compactMap { type, checks in
                let unchecked = checks.filter { check in
                    check.state == .unchecked && check.implementation == .custom
                        && provenances.contains(check.provenance)
                }
                guard unchecked.isEmpty == false,
                      let first = checks.min(by: { ($0.file, $0.line) < ($1.file, $1.line) }) else {
                    return nil
                }
                let draft = SignalItem.Draft(
                    subject: type,
                    file: first.file,
                    line: first.line,
                    laws: SignalItem.Laws(
                        protocols: unchecked.map(\.protocolName).sorted(),
                        kitDependency: kitDependency
                    )
                )
                return SignalScore(draft, score: Double(unchecked.count))
            }
        )
    }
}
