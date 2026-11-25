//
//  IndexAdapter.swift
//  SwiftStatsCore
//
//  The `index` collector (M7, design §2–§4): it reads the index store the
//  T1 build wrote, in process, through indexstore-db's `IndexStore`
//  reader, for the records' USRs, references and coupling. It runs only
//  with the T1 group (`scan --index`, `BuildAdapter`), and, linked rather
//  than run, takes no `path`.
//

/// The `index` collector's name and statuses.
enum IndexAdapter {
    /// The collector's name in a snapshot and in `.swiftstats.yml`.
    static let name = "index"
    /// Why a requested index read is skipped until the reader is built
    /// (a placeholder; design §13, removed in step 5a), whatever the build
    /// did.
    static let notBuiltReason = "the index reader is not built yet"
}
