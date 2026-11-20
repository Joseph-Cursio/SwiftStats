//
//  FamilyCommits.swift
//  SwiftStatsCore
//
//  A snapshot's history as the clone signals read it: each family's
//  history row, and the commits that changed it, from the stored commit
//  log and change lists (store v3).
//

/// A snapshot's families' history rows and commits.
struct FamilyCommits {
    /// The history rows by family.
    private let rows: [FamilyRef: FamilyHistoryRow]
    /// The commit-log positions of each family's commits.
    private let ordinals: [FamilyRef: [Int]]
    /// The commit log, newest first.
    private let log: [HistoryLogEntry]

    /// The history of `snapshot`.
    init(_ snapshot: StoredSnapshot) {
        rows = Dictionary(snapshot.familyHistory.map { (FamilyRef(id: $0.family, file: $0.file), $0) }) { first, _ in
            first
        }
        ordinals = Dictionary(grouping: snapshot.familyChanges) { FamilyRef(id: $0.family, file: $0.file) }
            .mapValues { changes in changes.map(\.commitOrdinal) }
        log = snapshot.historyCommits
    }

    /// The history row of `family`; nil when the snapshot has none.
    func row(_ family: FamilyRef) -> FamilyHistoryRow? {
        rows[family]
    }

    /// Whether `family` is production code outside generated files: its
    /// root's (or first accessor's) role, and its history row's flag.
    func isProduction(_ family: FunctionFamily) -> Bool {
        guard (family.root ?? family.accessors.first)?.role == .production,
              let row = rows[FamilyRef(family)] else {
            return false
        }
        return row.generated == false
    }

    /// The commits that changed `family`, sweeps left out, newest first.
    func commits(of family: FamilyRef) -> [HistoryLogEntry] {
        (ordinals[family] ?? [])
            .sorted()
            .compactMap { $0 < log.count ? log[$0] : nil }
            .filter { $0.sweep == false }
    }
}
