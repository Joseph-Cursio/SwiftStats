# M2 results

**Date:** 2026-11-19 · **Toolchain:** Apple Swift 6.4.2 (Xcode 27), macOS 27.2 SDK · **Machine:** Apple M3, 8 cores · **Tools:** SwiftProjectLint 1.1.0 (release build at `6477efac`), SwiftLint 0.65.1, GRDB 7.12.0

M2 scope (PRD §11): the snapshot store (SQLite through GRDB, forward-only migrations), `report` and `diff`, and each snapshot's metadata per §6.2 with every collector's build identity, SwiftStats' own included. The design is PRD v0.2.8: D9, §6.2, the new §6.6, §9 and §10.

## Done-when

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Diffing a snapshot with itself is empty | Met | `SnapshotDiffTests.selfDiff`: empty though SwiftLint, SwiftProjectLint and the dependency graph were all skipped, which counts as "not collected", not "not comparable". |
| 2 | On a fixture commit that adds, changes, moves and deletes one function each, the diff shows exactly those four, and the move shows as a move | Met | `DiffFixtureTests.fourChanges` on `Tests/Fixtures/Diff` (`before` → `after`, committed into a repository made at test time): exactly one family each added, removed, changed and moved. The moved function carries a nested function, which moves with it as one change. The only function delta is the changed function's own. `DiffFixtureTests.rollups` checks the roll-up deltas against hand-counted values. |
| 3 | Two snapshots of one commit, taken by SwiftStats builds from different commits, diff with SwiftStats' measurements listed as not comparable | Met | `SnapshotDiffTests.differentBuilds`: one commit scanned into two stores (a store keeps one clean snapshot per commit) with different build identities; `swiftstats` is not comparable ("different builds"), and no function or roll-up delta is reported. `BuildInfoTests.embedded` checks that a real build embeds the checkout's commit and a build-input hash. |
| 4 | Re-running `report` gives byte-identical output | Met | `SnapshotReportTests.byteIdentical` (JSON and Markdown, each from a fresh connection). On swift-algorithms and swift-collections, two `report --format json` runs compared equal with `cmp`. |

## What M2 adds

- **`swiftstats scan`** stores a snapshot in `.swiftstats/stats.sqlite` (or `store:`, or `--store`) and prints one line. `--format json` or `-o` still give the scan JSON, now `schemaVersion: 4`: each function record gains `bodyLines`, its body's stripped lines without its own braces. `--no-store` skips the store.
- **`swiftstats report`**: the working tree's snapshot (HEAD's, or its uncommitted one while that still matches the tree), or `--commit`'s, as Markdown or JSON. The Markdown leads with the signals (none until M3), then the collectors, the project roll-up with findings per 1k stripped lines, and per-module detail. The JSON is a document of its own (`schemaVersion: 1`) holding the snapshot block and the scan report.
- **`swiftstats diff <older> [<newer>]`**: function families added, removed, moved, renamed, access-changed or changed, with how each match was made; metric deltas grouped into worse, better and neutral; and the collectors that weren't compared, with why. A revision with no snapshot is scanned first from a checkout of a temporary index, which leaves nothing in the repository.
- **Snapshot metadata**: package, commit, branch, date, dirtiness and a hash of the changes, the toolchain, and for each collector its status, version, build identity (with a commit label when it is certain), options and run time.

## Decisions

Recorded in the PRD (v0.2.8). The ones the plan's review changed:

- **Tables, not one blob.** The first plan stored only the compressed scan report. A critic decoded an M1a report with the M1b model and it failed, so the report is now only for `report --format json`, and only for a build with the same `schemaVersion`; `diff`, trends and signals read typed tables (`function`, `finding`, `rollupMetric`) that migrations carry forward. Roll-up numbers are rows named by path, so a new roll-up field needs no migration.
- **Build identity is a content hash.** An external tool's identity is its binary's SHA-256; the commit of its source is only a label, and only when the binary is no older than that commit in a clean checkout of the tool. SwiftStats' identity is a hash of its build inputs, embedded by a build-tool plugin with read-only git, so docs-only commits and debug versus release builds don't break comparisons.
- **Comparability has three outcomes**: compared, not comparable (ran in both, different build, version or options) and not collected (missing in one or both). Only "not comparable" makes a diff non-empty, which keeps done-when 1 true on machines without every tool.
- **Families.** Changes are reported per function with its nested functions and accessors, so a moved function with a nested one is one move, and editing a nested function is one change.
- **Matching**: same key; the same key apart from its file-scoped part (a private function that moved, or one that stopped being private), only when one family on each side has it; a unique body hash whose body, braces aside, has more than one stripped line; then nested records by their anchor's new key.
- **`diff` exports from a temporary index, not a worktree or `git archive`**: nothing is left in the repository even when interrupted, and, unlike `git archive`, `export-ignore` files are kept.
- **`report` defaults to the working tree's snapshot**, not the latest by date, since `diff` stores scans of old commits. A dirty snapshot counts only while its hash of the changes matches the tree's.
- **`scan` prints a summary rather than JSON by default.** `Scripts/compare-sitrep.py` now passes `--no-store`.
- **Enum values in kebab-case** (`not-comparable`, `body-hash`), following `swift-testing`.

## Timing

Release build, warm caches. The store adds about 2 s per scan: reading the toolchain (`swift --version`, `swiftly use`, `xcrun`), hashing the tool binaries, and writing the rows.

| Package | `scan --no-store` | `scan` (stored) | `report` | `diff` of two unscanned commits |
|---|---|---|---|---|
| swift-algorithms `5b7143f` | 2.0 s | 3.6–4.5 s | — | 4.8 s (`1.2.1` → HEAD, HEAD already stored) |
| swift-collections `294059c7` | 12.3 s | 14.0–14.2 s | 1.3 s | 30.4 s (HEAD~5 → HEAD, both exported) |

`report` includes `swift package describe` (about 0.6 s), which names the package to look up. Each stored swift-collections snapshot holds 7,225 function rows, 19,577 finding rows, 3,229 roll-up numbers and the deflated report; a store with three of them is 9.2 MB.

On swift-algorithms, `1.2.1` → HEAD shows 20 added, 169 changed, 4 removed and 2 renamed functions. Most of the changes come from a swift-format commit; a spot check of `offsetBackward` shows real token changes (a `guard let` rewritten), not just layout, which the body hash ignores.

## Review

The plan was reviewed before any code (four critics: PRD consistency, diff semantics, store and git, build identity, which built a test plugin to check SwiftPM's sandbox); the decisions above came out of that. The finished work then had an adversarial review: four reviewers, each checked by a verifier. Of 24 claimed defects, 19 were confirmed, 1 judged plausible and 4 refuted. Each fix has a regression test:

- **Matching.** A one-line body laid out over three lines counted as evidence of a rename, since the check used the whole record's lines; records now carry `bodyLines`. Two private functions of one name in renamed files were paired by file order and labelled certain; step 2 now needs one family on each side. Nested functions in a computed property were paired by position; they now pair by key under their accessor.
- **Comparability.** Project roll-up findings were compared when SwiftStats' own results weren't, though SwiftStats chooses which files they count. And the Markdown said "no function changes" when functions hadn't been compared.
- **Stale dirty snapshots.** `report` and `diff --include-dirty` reused a dirty snapshot after the tree changed again; the stored hash of the changes is now compared.
- **Git configuration.** The dirty check and the build-input hash both went through `git diff`, which runs a user's external diff tool; with one set, a dirty tree was stored as HEAD's clean snapshot. Both now use a diff whose form no setting changes, and the plugin hashes untracked inputs as blobs (the shell had been dropping NUL bytes).
- **Export.** `git archive` drops `export-ignore` files, so diffs reported them as added; revisions are now checked out from a temporary index.
- **Smaller ones.** `diff X X --rescan` deleted its own first scan; a store kept in the package made every scan dirty; an external tool's commit label could name a commit pulled after the binary was built; a multi-line failure reason broke Markdown tables; a repository with no commits gave the label `git:HEAD`.
- **Tests.** The done-when 3 test scanned identical trees, so it couldn't see measurements leak through; it now changes the code between the two builds.

## Not done

- `diff` doesn't compare dependencies yet (direct dependencies, pins, the graph); it reports only whether the collector compares. A revision scanned from an export has no resolved `.build`, so its graph is always "not collected".
- Run times are recorded but not yet shown in trends (M3).
- Storing a snapshot costs about 2 s, mostly `swift --version`, `swiftly use` and hashing the tool binaries; they could run alongside the collectors.
- Collectors don't yet attach to an existing snapshot (M5): a rescan replaces the whole snapshot.
- HTML reports wait for the trend charts.
