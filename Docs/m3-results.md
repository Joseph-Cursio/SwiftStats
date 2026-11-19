# M3 results

**Date:** 2026-11-19 · **Toolchain:** Apple Swift 6.4.2 (Xcode 27), macOS 27.2 SDK · **Machine:** Apple M3, 8 cores · **Git:** 2.54.0 (Apple Git-157) · **Tools:** SwiftLint 0.65.1, GRDB 7.12.0

M3 scope (PRD §11): the history collector (churn, stability, change-coupling pairs, bug-fix density, reverts), `backfill`, `top` and `trend`, and five signals: hotspot, bug-prone, unstable fixes, safe to leave, and tests not keeping up (by test file name). The design is PRD v0.2.9: §6.2, §7.13, §8, §9, §10 and §10.1.

## Done-when

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | On two repos, the top 20 hotspots are labelled and at least 12 are judged worth attention; the labels are kept as a test fixture | **Waiting on labels** | Both lists are in `Tests/Fixtures/HotspotLabels/`: SwiftProjectLint's rules package (`Packages/SwiftProjectLintRules`) at `6477efac57`, and SwiftInferProperties at `7990852508`. Every `label` is still `null`. `LabelFixtureTests.hotspots` checks the files now, and checks for at least 12 `worth` labels once all 20 are filled in. `SWIFTSTATS_LABEL_REPOS=1 swift test --filter LabelFixtureTests` rebuilds both lists from the repositories and finds no unlabelled entry in either top 20. |
| 2 | A backfilled trend of stripped lines and median complexity is produced for one repo | Met | `swiftstats backfill --weekly` on SwiftInferProperties scanned 29 commits in 3 min 8 s, with 0 failed. One commit (`e0f692ed88`) was scanned with its `.swift-version` pin removed. `trend fileLength.total --part production` and `trend cognitive.median --part production` are below. |

### The backfilled trend (SwiftInferProperties, production code)

Stripped lines grew about 6.6×, from 10,520 to 69,473. Median cognitive complexity stayed at 1 in every snapshot, and the 90th percentile stayed at 5. The code grew a lot without its typical function getting harder to follow. No point is marked as a break: one build scanned every commit.

| Commit | Date | Stripped lines | Median cognitive |
|---|---|---|---|
| `80968c492e` | 2026-05-03 | 10,520 | 1 |
| `7f32ac4116` | 2026-05-17 | 28,887 | 1 |
| `dc4dd98d1b` | 2026-06-14 | 28,581 | 1 |
| `bfe27ec356` | 2026-07-05 | 34,784 | 1 |
| `ccee70f105` | 2026-08-02 | 50,173 | 1 |
| `6e172c88fe` | 2026-08-30 | 56,787 | 1 |
| `f87bb2417c` | 2026-10-04 | 62,326 | 1 |
| `e0f692ed88` | 2026-10-11 | 67,190 | 1 |
| `7990852508` | 2026-11-14 | 69,473 | 1 |

The table shows 9 of the 29 weekly points. `trend` prints all 29.

## What M3 adds

- **History in every stored scan.** `scan` reads history for the commit it scans, unless `--no-history` is given. `--no-store` stays git-free. History is read from the repository, never from the scanned directory, and is anchored at the commit's committer date, so a commit's history reads the same whenever it is scanned. It comes from one `git log` walk with every output-changing setting pinned on the command line. Every changed file version is parsed with the scan's own rules, through `git cat-file --batch`, and functions are traced through renames and moves. Each family records its least certain link (`tracedBy`). Scan JSON is now `schemaVersion: 5`.
- **Per family:** changes in the window (sweeps aside), sweeps, all-time changes, first seen, last changed, fixes in the window and all-time, fix rate, an age-weighted fix score, reverts, repeated fixes, and how many changes also touched a test file matching by name. Change-coupling pairs are kept in the JSON.
- **Signals** in `report` (report JSON `schemaVersion: 2`), with `swiftstats top <signal>` ranking every candidate with a score above zero and marking the members.
- **`swiftstats trend <metric>`**: a roll-up number over the clean snapshots of HEAD's first-parent line, with breaks where the numbers stop being comparable.
- **`swiftstats backfill`**: past first-parent commits, either every Nth or one per ISO week, exported like `diff`'s and scanned without history. Tools are left out unless `--with-tools` is given.
- **Store migration v2**: the `historyRun` and `familyHistory` tables.
- **`Scripts/label-sample.py`** writes the label fixtures, and keeps any labels already filled in when it is run again.

## History on the labelled repositories

Release build, in place, from a clean checkout.

| Package | Commits (in window) | Families | Traced by key | History | Whole scan |
|---|---|---|---|---|---|
| SwiftProjectLintRules `6477efac57` | 467 (196) | 2,472 | 81% (plus 15% file-scoped key) | 1.8 s | 8.0 s |
| SwiftInferProperties `7990852508` | 1,512 (396) | 13,499 | 86% | 4.9 s | 20.5 s |

The less certain links on SwiftInferProperties:

| Link | Families |
|---|---|
| `same-name` | 620 |
| `body-hash` | 483 |
| `file-scoped-key` | 465 |
| `similar-body` | 245 |
| `module-moved-key` | 46 |

Both repositories merge by `merge`. There were 5 sweeps on the rules package and 13 on SwiftInferProperties.

The top hotspots look like the right places. On the rules package they are the large syntax visitors that keep being revised: `NonInjectedNondeterminismVisitor`, `ConcreteTypeUsageVisitor` and `DirectInstantiationVisitor`. On SwiftInferProperties they are the interactive triage stubs, `InteractiveTriage.totalityStub` and `handleAccept`, followed by `StubApplicationArity.declineReason`. Whether they deserve attention is for the labels to say.

## Fix detection

Only 3 commits in each repository's window match the default fix patterns. Neither repository writes subjects in a `fix:` style, so the defaults find little. `Tests/Fixtures/FixLabels/` holds the matched commits plus a sample of unmatched ones, 30 per repository. Once those are labelled `fix` or `not-fix`, they give the precision and recall that PRD §13 asks for. `LabelFixtureTests.fixes` already computes precision when every label is filled in. Both repositories may need their own `history.fix_patterns`.

## Decisions

These are recorded in the PRD (v0.2.9). Here are the ones the design review changed:

- **History runs in the snapshot scanner, not in `PackageScanner`.** A scan of an exported revision can still read the repository's history, and `--no-store` stays free of git.
- **A lineage starts from the analysed commit's own files**, parsed the same way as every past version, rather than from the scan. The scan's families are joined to it afterwards. On a dirty tree, a function that exists only in uncommitted code gets null history, never zero.
- **History-only matching rules** apply after `diff`'s rules: `module-moved-key`, `same-name` and `similar-body` (at least 3 lines and 70% shared, each the other's only best match). A pure move is not a change.
- **Sweeps** are commits that touch more than `bulk_files` (30) Swift files, or that `ignore_revs` or `.git-blame-ignore-revs` names. They are left out of churn, fixes, reverts and coupling, and counted separately.
- **Fix exclusions**: lint and warning cleanups and `style:`/`chore:` subjects are not fixes.
- **Ranked membership** keeps the nearest-rank top 10% of all candidates, with ties at the cut. `top` ranks beyond membership, so a 20-item list exists even where membership is shorter.
- **Nested packages** are scanned on their own. That is why the labelled SwiftProjectLint package is its rules package.
- **Backfill picks never move.** Every Nth counts from the package's first commit, and a weekly pick is the week's latest commit in UTC. No manifest cache is kept.

## Review

The design was critiqued before any code was written, and the decisions above came out of that critique. The finished code then had an adversarial review across four dimensions: the history walk, lineage, signals and store, and the commands. A verifier checked each claimed defect by reproducing it. 15 findings were kept and none refuted. Writing their regression tests turned up a 16th defect. Each defect is fixed and has a test. Each fix was also undone, one at a time, to confirm its test then fails.

- **Scope of the package's code.** The `Sources/<X>/` and `Tests/<X>/` fallback also covered files that exist at the analysed commit but that no target compiles. Fixtures, files a target excludes and files of commented-out targets became tests, test changes and sweep members. Now a file the commit holds counts only when a target compiles it.
  - Commits that changed none of the package's Swift files, such as docs or a nested package, were counted and listed as fixes. In SwiftInferProperties, 5 of the 8 fix commits sampled earlier were docs-only, and its commit count falls from 2,603 to 1,512.
  - A package its HEAD doesn't hold yet made history fail. Now its families get null history.
- **Git configuration.** The committer-date query ignored `log.showSignature`, so history failed on a signed HEAD for a user who shows signatures. Every git call that formats commit data now pins signatures off.
- **Moves to another target.**
  - Similar-body matching couldn't see a moved file's old bodies, so a rename during the move lost the lineage.
  - Declarations sharing a line swapped histories.
  - A move git detected was labelled `key`, while one it missed was labelled `module-moved-key`. Both are now `module-moved-key`.
- **Signals.**
  - A subscript with explicit `get`/`set` never had a cognitive score, so it could never be a hotspot or safe to leave. It now takes its accessors' highest.
  - A report's "N more" pointer sent users to `top`'s default 20. It now passes `--limit` when the members don't fit.
  - `top --format json` didn't say how many items it cut. It now records `ranked` and `members`.
- **Backfill.**
  - It looked up existing snapshots under HEAD's package name, so a snapshot holding history, taken before a rename, was replaced on every run. It now looks up by commit.
  - In a package newer than its repository, every pick before the package existed failed. Only commits holding the manifest are picked now.
  - `--rerun` could replace a snapshot whose dependency graph or tool results the new scan couldn't collect. It now keeps any snapshot holding results the new scan lacks.
- **Trend.**
  - A tool metric broke at every point when the tool ran on neither side. A break now needs a collector that ran on only one side, or results that don't compare.
  - The off-line count included snapshots of commits HEAD can't reach.
- **Found by the new tests: an M2 hang.** `BinaryIdentity` looked for a tool's `.build` directory by walking up with `deletingLastPathComponent`. Past `/`, that gives `/..` and never ends. Any tool binary outside a `.build` directory hung the snapshot scan. The search now uses the path's components.

## Not done

- **Done-when 1 needs your labels.** Fill in `label` in `Tests/Fixtures/HotspotLabels/*.json` with `"worth"` or `"not-worth"` (20 per repository), and in `Tests/Fixtures/FixLabels/*.json` with `"fix"` or `"not-fix"` (30 per repository). Then run `swift test --filter LabelFixtureTests`.
- **Fix precision and recall** come from those labels. Repository-specific `fix_patterns` may follow.
- **Hidden coupling** (pairs with no static dependency), along with a table and a `top` view of the pairs, waits for M7, as the PRD says.
