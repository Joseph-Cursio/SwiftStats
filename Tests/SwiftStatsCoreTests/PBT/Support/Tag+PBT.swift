//
//  Tag+PBT.swift
//  SwiftStatsCoreTests
//
//  The tags property-based suites carry. Every property suite is tagged
//  `pbt`, which an Xcode test plan can select or skip. `swift test` can't
//  filter by tag (its `--filter` and `--skip` take regular expressions over
//  test names; `--filter tag:pbt` matches nothing), so from the command
//  line the suites' names select them: every property suite is named
//  `<Subject>PBT`, and `swift test --filter 'PBT$'` runs them alone. A walk
//  too slow for every run is also tagged `soak`, and is enabled only when
//  `PBTBudget.scale` is above 1, since a plain `swift test` can't exclude
//  a tag.
//

import Testing

extension Tag {
    /// A property-based suite.
    @Tag static var pbt: Self
    /// A walk run only in a long run, when `SWIFTSTATS_PBT_SCALE` is above 1.
    @Tag static var soak: Self
}
