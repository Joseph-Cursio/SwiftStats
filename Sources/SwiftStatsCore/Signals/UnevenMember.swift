//
//  UnevenMember.swift
//  SwiftStatsCore
//
//  A clone class the tests cover unevenly (M5, uneven clone testing): its
//  measurable copies and those at most 20% covered, before nested members
//  fold into the ones holding them.
//

/// A clone class with a well covered and a poorly covered copy.
struct UnevenMember {
    /// The class.
    let cloneClass: CloneClass
    /// Its copies with a mapped line, in the class's order.
    let copies: [MeasuredCopy]
    /// Those at most 20% covered.
    let poor: [MeasuredCopy]

    /// The uncovered mapped lines of its poorly covered copies, each once:
    /// what its score counts.
    var uncovered: [LinePlace] {
        var seen: Set<LinePlace> = []
        return poor.flatMap { copy in copy.uncovered.map { LinePlace(file: copy.file, line: $0) } }
            .filter { seen.insert($0).inserted }
    }

    /// Its least covered copy: the lowest share, then the most uncovered
    /// lines, then file, then first line. A member has a poorly covered
    /// copy, so there is one.
    var leastCovered: MeasuredCopy {
        let sorted = poor.sorted { lhs, rhs in
            (lhs.share, -lhs.uncovered.count, lhs.file, lhs.start)
                < (rhs.share, -rhs.uncovered.count, rhs.file, rhs.start)
        }
        return sorted[0]
    }

    /// Whether every poorly covered copy of `other` lies inside one of this
    /// member's poorly covered copies.
    func holds(_ other: Self) -> Bool {
        other.poor.allSatisfy { copy in poor.contains { copy.lies(inside: $0) } }
    }
}
