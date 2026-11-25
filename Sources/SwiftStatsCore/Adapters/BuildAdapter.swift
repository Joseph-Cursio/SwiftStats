//
//  BuildAdapter.swift
//  SwiftStatsCore
//
//  The `build` collector (M7, design §1): SwiftStats' own T1 build of the
//  package, in `.swiftstats/index-build`, which gives the type-check
//  timings, the compiler warnings and the index store the `index` and
//  `periphery` collectors read. The three run only when asked for with
//  `scan --index`, never in `backfill`, in `diff`'s scans of other
//  revisions or with `--rerun`; every scan lists their statuses, so a
//  snapshot says how to run them when it didn't. The build's `swift` is
//  the coverage collector's (`collectors.coverage.path`, else PATH), as
//  SwiftMutator's test command's is, so it takes no `path` of its own.
//

/// The `build` collector's name and statuses, and the reason the T1 group
/// shares when a scan didn't ask for it.
enum BuildAdapter {
    /// The collector's name in a snapshot and in `.swiftstats.yml`.
    static let name = "build"
    /// Why a scan that didn't ask for the T1 group skipped each of its
    /// collectors (`build`, `index` and `periphery` alike).
    static let notRequestedReason = "not requested; scan --index runs it"
    /// Why a requested build is skipped until the T1 session is wired into
    /// the scan (a placeholder; design §13, removed in step 3c).
    static let notBuiltReason = "the index build is not built yet"
    /// The error `collectors.build.path` gives: the build has no
    /// executable of its own.
    static let pathError = "the build uses the coverage collector's swift; set collectors.coverage.path"
}
