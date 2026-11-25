//
//  PeripheryAdapter.swift
//  SwiftStatsCore
//
//  The `periphery` collector (M7, design §5): dead code from outskirts
//  3.28.0, a fork of Periphery, run over the index store the T1 build
//  wrote. It runs only with the T1 group (`scan --index`,
//  `BuildAdapter`). `collectors.periphery.path` names the `outskirts`
//  executable, else `outskirts` on PATH; never `periphery` on PATH, whose
//  JSON and test retention differ.
//

/// The `periphery` collector's name, executable and statuses.
enum PeripheryAdapter {
    /// The collector's name in a snapshot and in `.swiftstats.yml`.
    static let name = "periphery"
    /// outskirts' executable on PATH.
    static let executableName = "outskirts"
    /// Why a requested run whose `outskirts` resolves is skipped until the
    /// collector is built (a placeholder; design §13, removed in step 6a).
    static let notBuiltReason = "the outskirts collector is not built yet"
}
