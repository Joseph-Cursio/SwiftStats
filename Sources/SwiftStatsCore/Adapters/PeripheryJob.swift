//
//  PeripheryJob.swift
//  SwiftStatsCore
//
//  What a run of the `periphery` collector needs (M7, design §5): the
//  `outskirts` executable, what the T1 build left, the scan's records and
//  files, the `index` collector's run (whose report, when it ran, gives
//  the retained modules and the local USRs, its quarantine having run
//  already) and the factory that opens the index store when it didn't.
//

import Foundation

/// One run of the `periphery` collector, as the T1 group asks for it.
struct PeripheryJob {
    /// The `outskirts` executable.
    let executable: URL
    /// What the T1 build left.
    let products: BuildSession.Products
    /// The scan the entries are classed against.
    let scan: IndexAdapter.Scan
    /// The `index` collector's run.
    let index: IndexAdapter.Run
    /// Opens the index store when the `index` collector didn't run.
    let opening: (_ store: URL, _ library: URL) throws -> any IndexStoreSource
}
