//
//  Lineage.swift
//  SwiftStatsCore
//
//  One family's line of descent through history: the commits that changed it, the
//  commit that added it and the least certain link in between.
//

/// One family's line of descent.
struct Lineage {
    /// Indices of the commits that changed it, newest first.
    var changes: [Int] = []
    /// The commit that added it; nil if the walk ended first.
    var birth: Int?
    /// The least certain link in its descent.
    var weakest: MatchMethod?

    /// Records a link made by `method`.
    mutating func link(_ method: MatchMethod?) {
        guard let method else {
            return
        }
        if weakest.map({ method.uncertainty > $0.uncertainty }) ?? (method != .key) {
            weakest = method
        }
    }
}
