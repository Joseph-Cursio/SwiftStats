# M5 results

**Date:** 2026-11-20 · **Toolchain:** Apple Swift 6.4.2 (Xcode 27), macOS 27.2 SDK, Apple LLVM 21.0.0; SwiftInferProperties is built, tested and scanned under its own `.swift-version` pin, swift.org 6.4.1 with its LLVM 21.0.0 tools · **Machine:** Apple M3, 8 cores, macOS 27.2.1 · **Git:** 2.54.0 (Apple Git-157) · **Tools:** SwiftLint 0.65.1, GRDB 7.12.0, SwiftEffectInference `ba3624d` (linked), SwiftProjectLint 1.1.0 (release build of SwiftProjectLint `6477efac`, product `CLI`), swift-infer 1.160.0 (release build of SwiftInferProperties `79908525`), swift-clone-detector 0.1.0 (release build of SwiftCloneDetector `97eee1c`) · **SwiftStats:** release build of tree `a7ed6c25`, the M5 working tree over `c5f51d1`; `swiftstats` 0.0.1, sha256 `3433c203…6f26`. Tests per public function was re-measured after the links were tightened, with a release build of tree `9759b3c8` (sha256 `5fb328dd…aba1`)

M5 scope (PRD §11): the T2 coverage join (line and region coverage per function, closures folded into their parent), tests per public function, and two signals: risky + untested and the coverage part of uneven clone testing. The done-when packages are SwiftInferProperties (SIP) at `79908525` and swift-algorithms at `5b7143f`. The design is PRD v0.2.11: §6.2, §6.5, §6.6, §7.5, §7.8, §7.13, §7.14, §7.16, §8, §9, §10, §10.1, §11, §13 and D9.

## Done-when

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | On both packages, per-function line and region coverage, checked by an independent checker: (a) per-line data equals `llvm-cov export -format=lcov`; (b) every mapped line lies in some record's line span or in exactly one attachment (corrected wording); (c) records equal `llvm-cov report -show-functions`; (d) demangled names agree with record keys, 100%; (e) a reimplementation of the mapping equals the coverage JSON | Met | `Scripts/coverage-check.py` passes all five checks on both packages, with no exceptions. swift-algorithms: 28 kept files, 4,006 lines, 747 of 747 names agree. SIP: 838 kept files, 59,053 lines, 8,495 of 8,495 names agree. 1(b) was reworded during the build (below). |
| 2 | Unmapped regions listed on both; in-body regions mapped ≥ 95%, attachments and unscanned-file entries counted apart | Met | 0 unmapped entries on both, so the list is empty and the report says "Every export entry in a production file was mapped." In-body regions: 1,755 of 1,755 and 22,135 of 22,135 (100.00%). Attached: 7 entries on 6 owners and 483 entries on 122 owners. Unscanned-file entries: 0 and 0. |
| 3 | Risky + untested produced on both with its counts; on swift-algorithms 12 `forceUnwrap` markers, 12 on mapped lines, 0 untested, no rows; every marker's verdict hand-checked; the fixture's exact rows pass in `swift test` | Met | swift-algorithms: "12 markers: 12 tested (0 on partly run lines), 0 untested, 0 with no coverage data", no rows, as expected. SIP: 2 markers, both with no coverage data, no rows. All 14 verdicts agree with the rule. The `RiskyUntested` suite passes (4 tests). SIP has no crash markers, so it exercises only the race-on-a-type case. |
| 4 | `report` byte-identical twice; a plain `scan` after `scan --coverage` carries it; a SwiftStats rebuild then a plain scan carries (keys match); `git status --porcelain` empty with the default and a non-default store; an interrupt during build and during tests leaves no `swift-build`, `swift-test`, `xctest` or `swiftpm-testing-helper`, and the next `scan --coverage` hits no SwiftPM lock | Met, with limits | Byte-identical reports and carries on both; trees clean after every step on both. The release rebuild left the binary byte-identical, so a debug build stood in for a different build identity; carry never consults the binary identity. Interrupts ran on swift-algorithms only, and the "no lock" evidence is the next `scan --coverage` completing. |
| 5 | Uneven clone testing and tests per public function produced on both; links hand-checked on a sample of 20 per package | Met; links tightened and re-checked, overloads with the same labels still over-count | Uneven clone testing: 5 members (swift-algorithms) and 138 (SIP), every listed copy figure recomputed. The first, name-only links followed their rule on 40 of 40 sampled counts, but a human agreed with only 10 of 20 on swift-algorithms and 15 of 20 on SIP (2 more partly), and the auditors' fresh samples did worse. At the user's request the links were tightened and item 5 re-run. Every count in fresh samples of 20 and an auditor's 10 per package follows the new rule (60 of 60). A human agrees with 12 of 20 and 3 of 10 (5 partly) on swift-algorithms, and 18 of 20 (1 partly) and 9 of 10 on SIP; on the first run's samples, now 13 of 20 and 17 of 20 (1 partly). |

`report` gave byte-identical Markdown and JSON on two runs for each package. Each package's results were then audited independently: the auditors re-derived the numbers from the stored JSON and the stores, re-ran the checker (the swift-algorithms auditor also made its own lcov export), and re-ran `report` and `top`. They confirmed every key number; their findings, and the few wording errors they found in the runs' notes, are folded into the sections below.

## What M5 adds

- **The `coverage` collector**, opt-in with `scan --coverage` and never run by `backfill` or `diff`'s exports; `collectors.coverage.enabled: false` skips it even when `--coverage` asks for it. It finds the toolchain through `<swift> -print-target-info` in the package root, so swiftly's proxy honours `.swift-version`, and runs that toolchain's own `swift`: `build --build-tests`, then `test --skip-build`, both with `--build-system swiftbuild --enable-code-coverage --scratch-path .swiftstats/coverage-build`. Every exit status of `swift test` is accepted: failing tests give `ran` with option `tests: failing` when every bundle wrote its profiles. Profiles are grouped by signature, one group per bundle and both frameworks' processes together. Each group is merged and read with `llvm-profdata show` for per-target counts, and every profile is merged into `swiftstats.profdata`, over which `llvm-cov export` exports all bundles. Identity is `swift:<version line>`, version the `LLVM version` line. A bundle that is no test target, by the coverage toolchain's own `swift package describe`, fails the run. `Package.resolved` is put back as it was, after the run, after a failure and after an interrupt. An interrupt sends SIGINT first, then SIGTERM, then SIGKILL.
- **Decoding and mapping.** Files are kept (scanned production files), unmapped, or dropped as `build`, `outsideRoot`, `testFiles`, `otherPackage` or `otherLanguage`. Entries go to the innermost record holding `regions[0]`'s start; closures fold into it; what lies in no record is attached to the innermost type, else the file. Record lines follow llvm-cov's per-function line rule, file lines its file line rule (equal to lcov DA lines), with partly run lines flagged. A record with no entry has null coverage and a reason, never 0. The rule string is stored as the option `map:`.
- **Tests per public function**, labelled "heuristic: the test's target ran it and the test, or a test helper it calls, calls it with fitting labels or reads it (a subscript: names its type)" (tightened after the done-when hand-checks; the first build linked by name). Records carry their effective `access`. A public `func`, `init` or accessor is linked to a test when its target's own profile ran it, the coverage run's `--skip` regexes didn't leave the test out, and the test, or a test helper of its target that it calls, writes it: a function or initialiser by a call whose argument labels fit its parameters (defaults, variadics, `_` and the trailing closure handled) or a reference with all its labels, a member function only by a call written on something; an accessor by a member read or key path component, never a bare identifier. A concrete type's member also needs the test to name the type, by its simple name or a qualifier that fits the record's module and parent types, or a test file named for the member's file or type; an initialiser's call names its type. Protocol extension members and free functions need no type. Helpers are followed transitively where they are visible, a `private` one only in its file. Witnesses of standard protocols such as `Sequence`, `Collection`, `Equatable` and `CustomStringConvertible` count as reached generically. Operators are never linked. Argument types are never read, so overloads with the same labels are not told apart.
- **Two signals**, both needing an M5 snapshot with coverage: `risky-untested` (crash and race markers no test ran, needing SwiftProjectLint) and `uneven-clone-testing` (needing SwiftCloneDetector; a class with a copy at least 80% covered and one at most 20%, scored by the poor copies' uncovered lines, folded on poor copies).
- **Keeping coverage across rescans.** A rescan that collects no coverage of its own (a plain scan, a `scan --coverage` whose run failed or was skipped, or `diff`'s rescan) carries the snapshot's coverage when the commit and tree state are the same, the map and link rules are the same (the options `map:` and `links:`), and stored keys and the new records match both ways with the same ranges; a requested run that failed or was skipped adds a warning saying so. Otherwise it refuses before writing, naming `scan --coverage` and `--drop-coverage`; `scan --drop-coverage` and `diff --drop-coverage` replace the snapshot without its coverage. A coverage run that ran always replaces held coverage. `backfill` keeps snapshots holding coverage.
- **Store migration v4**: `access`, `typePath` and `typeFile` on `function`; `coverageRun`, `functionCoverage`, `coverageAttachment`, `coverageLine` and `coverageUnmapped`. Scan JSON `schemaVersion: 7`, report 4, top 3, diff 2.
- **Configuration**: `collectors.coverage.{enabled, path, arguments}`; `arguments` takes only `--skip <regex>` pairs.
- **Reports**: a Markdown Coverage section (status, carried date, bundles, lines and regions per scope, records with no data, public functions, saturated lines, the first 50 unmapped entries), roll-ups per production module and project, and per-record coverage deltas in `diff`.
- **`Scripts/coverage-check.py`**, the independent checker, and **`Scripts/record-coverage-fixture.sh`**, which records the `Coverage` and `Risky` fixture packages' real exports.

## Results on the two packages

### Setup

Scratch clones in the session scratchpad, with `--store` and `--config` outside each package. Nothing was written, built or run in the owners' repositories. SIP is a clone of the owner's repository at `79908525`; swift-algorithms is a clone of the local SwiftPM cache mirror at `5b7143f8e2` (`1.2.0-24-g5b7143f`, committed 2026-07-22), with no network. The tools were cloned from the owners' repositories at the commits above and built in those clones, each left clean. Both configs name `swift` as swiftly's proxy, so a package's own `.swift-version` applies where it has one: 6.4.1 for SIP; swift-algorithms has none, so swiftly's default, Xcode's 6.4.2, applies. SIP's config adds `arguments: ["--skip", "MeasuredTests|MeasuredExecutionTests|VerifyPipeline|PerformanceTests"]`.

As in M4, the owner's SIP join files were copied into the clone's git-ignored `.swiftinfer/`. SIP has no `interaction-decisions.json`.

| Copied file | sha256 |
|---|---|
| SIP `.swiftinfer/decisions.json` | `f590bd9dcfa241c0e24a906859d9ab55e3fc12c2853a6705c33a4ad117933d7a` |
| SIP `.swiftinfer/verify-evidence.json` | `95c57c52331579421b807edb38a5a00ecc23886987da853e70e4a6d8d1f83816` |

Both are M4's hashes. Every collector except dependencies ran on both packages, SwiftProjectLint included (M4 had skipped it). Dependencies were skipped on both because they are not resolved, and `swift package resolve` was not run.

The two package runs went on at the same time, on the same machine, from one SwiftStats build.

### What each package gives

| | swift-algorithms `5b7143f` | SIP `79908525` |
|---|---|---|
| Test bundles | 1 (`SwiftAlgorithmsTests`) | 8 |
| `swift test` | passed | failing: exit 1, 6 of 6,939 tests fail |
| Export files kept; dropped build, test files, other | 28; 10, 28, 0 | 838; 482, 1,090, 0 |
| Coverage records, with data, null | 473, 470, 3 | 4,330, 4,327, 3 |
| Attachments (lines, regions) | 6 (7, 7) | 122 (927, 440 after deduplication) |
| Unmapped entries | 0 | 0 |
| Saturated lines | 0 | 9, in 4 files |
| Lines covered | 3,864 / 4,006 (96.46%) | 53,936 / 59,053 (91.33%) |
| Regions covered | 1,600 / 1,758 (91.01%) | 19,469 / 22,543 (86.36%) |
| Functions with data, executed | 470, 448 | 4,327, 4,084 |

- **swift-algorithms' 3 null records** are inside `#if ALGORITHMS_DARWIN_ONLY`: `Double.log(_:)`, `Double.log(onePlus:)` and `Double.root(_:_:)`. All 6 attachments are on iterator types, and all ran.
- **SIP's 3 null records** are `not linked into any test bundle`: two in `soundness-probe` and `SwiftInferEntry.main()` in `swift-infer`. SwiftInferMacro has no coverage data at all.
- **SIP's 6 failing tests** all need sibling repositories outside the clone, as the research predicted (for example "every emitted recipe still exists in the kit"). SwiftStats records no test counts; these come from a manual re-run of the same `swift test --skip-build` command, which had a side effect (below).
- **SIP per module:** SwiftInferCLI 84.84% of lines, SwiftInferCore 97.11%, SwiftInferTemplates 97.94%, SwiftInferTestLifter 95.74%, SwiftInferMacroImpl 90.04%, SwiftInferKitEvidence 98.41%.

### 1. Coverage and the independent checker

`coverage-check.py` was written in its own step (3b), after the mapper and before the steps built on it, and ran against the export, profiles and bundles left in `.swiftstats/coverage-build`: right after both of swift-algorithms' coverage scans and after SIP's first; on SIP's second run it was run later, by the auditor. It finds the toolchain and bundles itself.

| Check | swift-algorithms | SIP |
|---|---|---|
| 1a lcov DA lines | PASS: 28 files, 4,006 lines, 3,864 covered | PASS: 838 files, 59,053 lines, 53,936 covered |
| 1b (corrected) | PASS: 4,006 = 3,999 in record spans + 7 in attachments | PASS: 59,053 = 58,126 in record spans + 927 in attachments |
| 1c `llvm-cov report -show-functions` | PASS: 747 entries (754 rows); 335 single-entry records exact, 2 parents of nested records, 133 folded records' regions | PASS: 8,495 entries (8,978 rows); 2,665 single-entry exact, 3 parents, 1,659 folded |
| 1d demangled names | PASS: 747 of 747 | PASS: 8,495 of 8,495 |
| 1e reimplementation | PASS: 473 records, 6 attachments, 0 differences, order equal | PASS: 4,330 records, 122 attachments, 9 saturated, 0 differences, order equal |

- **Parents of nested records** equal llvm-cov minus the nested records' lines, for example SIP's `DoccPageBuilder.verifiedProperties(in:verified:)` 15 − 4.
- **Reproduced by the auditors.** The checker passed again on swift-algorithms' second coverage run with identical figures, on SIP's first run from saved copies of its export and profiles, and on SIP's second run (7 saturated lines). swift-algorithms' first checker pass can't be re-run: the second run overwrote the build directory, and the checker now fails 1a and 1e on that scan by count-only differences, as expected. The swift-algorithms auditor's own lcov export matched the scans' per-line data on every line; the SIP auditor re-ran the checker, whose 1a compares against lcov, on run 1's saved export and profiles.
- **How independent it is.** The checker anchors entries with the mapper's own rule, as the design allows; only 1a and 1c compare against llvm-cov directly.
- **Done-when 1(b) was reworded.** The design's wording was "records plus attachments add up to each file's lines". Sibling one-line accessors on a shared line each count that line, so record tallies can exceed the file's lines (the fixture's `Accessors.swift` has 7 mapped lines and records summing to 8). The corrected check is that every mapped line lies in some record's span or in exactly one attachment. swift-algorithms never hits the case behind the correction: its record line totals sum to 3,999, and 3,999 + 7 = 4,006, so even the original wording holds there.
- **llvm-cov report's line totals differ from SwiftStats'.** For swift-algorithms' 28 files, `llvm-cov report` gives 4,390 lines with 210 missed (95.22%); SwiftStats gives 3,864 of 4,006 (96.46%). Regions agree exactly (1,758, 158 missed, 91.01%). SwiftStats takes scope lines from lcov DA lines, as designed; `llvm-cov report`'s file rows follow another rule.

**Two coverage runs of one tree.**
- swift-algorithms: the mapped line set and record tallies are identical; 83 of 4,006 lines have different counts (`MinMax.swift:31` reads 183, then 162), and none changes between covered and uncovered.
- SIP: counts differ in 260 files, and the set of covered or partly run lines in 11. 9 records differ in covered lines and 12 in regions, for example `IdempotenceTemplate.inferredEffectSignal(for:)` 11/24 then 3/24. Project covered lines are 53,936 in both, as the per-record changes cancel. Saturated lines: 9, then 7. Uneven clone testing lists 138 items, then 140, with 135 sharing subject and score. The second SIP run is not quite like-for-like (see `Package.resolved` below).

The design's known limit says counts in parallel Swift Testing suites vary "with small changes". On SIP they move which lines count as run, not only how often.

### 2. Unmapped entries and the in-body share

| | swift-algorithms | SIP |
|---|---|---|
| Unmapped entries (kept files; unscanned files) | 0; 0 | 0; 0 |
| In-body regions mapped | 1,755 / 1,755 (100.00%) | 22,135 / 22,135 (100.00%) |
| Attached, counted apart | 7 entries, 7 regions, 6 owners | 483 entries, 489 regions (440 after deduplication, 408 covered), 122 owners |
| Region total | 1,751 record + 7 attached = 1,758 | 22,103 record + 440 attached = 22,543 |

All attachments on both packages are to types. SIP's largest is `SwiftInferCLI::RenderShape`, 65/88 lines and 49/72 regions. With nothing unmapped, the done-when's list is empty on both; the unmapped path is covered by fixture tests.

### 3. Risky + untested

**swift-algorithms.** "0 members of 0 ranked". "12 markers: 12 tested (0 on partly run lines), 0 untested, 0 with no coverage data"; left out: SwiftProjectLint `unconditionalTrap` 29, `unsafeMemoryAPI` 0, and SwiftLint's duplicates 0 each. The 12 markers sit on 11 lines (two on `FlattenCollection.swift:52`); the other 28 of SwiftProjectLint's 40 `forceUnwrap` findings are in `Tests/`. Production code has no other marker kind. This is exactly the design's expectation.

Every marker was checked against the source, the scan's per-line count and a separate lcov export. They agree on every line, every owner record ran, and no line is partly run. 12 tested, 0 disagreements. The swift-algorithms auditor re-checked all 12 the same way.

| # | File:line | Code | Owner record (lines covered) | Count | Verdict |
|---|---|---|---|---|---|
| 1 | Chunked.swift:181 | `subsequence.first!` | `ChunkedOnCollection::subscript(_: Index)` (7/7) | 30 | tested |
| 2 | Compacted.swift:110 | `base[position.base]!` | `CompactedCollection::subscript(_: Index)` (5/5) | 1,800 | tested |
| 3 | FlattenCollection.swift:52 | `lhs.inner!` | `FlattenCollection.Index::static func <` (8/8) | 3,721 | tested |
| 4 | FlattenCollection.swift:52 | `rhs.inner!` | same | 3,721 | tested |
| 5 | FlattenCollection.swift:91 | `index.inner!` | `FlattenCollection::func index(after:)` (8/8) | 455 | tested |
| 6 | FlattenCollection.swift:100 | `position.inner!` | `FlattenCollection::subscript(_: Index)` (6/6) | 230 | tested |
| 7 | FlattenCollection.swift:114 | `end.inner!` | `FlattenCollection::func distance(from:to:)` (20/20) | 209 | tested |
| 8 | FlattenCollection.swift:188 | `index.inner!` | `FlattenCollection::func offsetForward(_:by:limitedBy:)` (56/56) | 1,638 | tested |
| 9 | FlattenCollection.swift:288 | `limit.inner!` | `FlattenCollection::func offsetBackward(_:by:limitedBy:)` (57/57) | 1,142 | tested |
| 10 | Partition.swift:347 | `buffer.baseAddress!` | `Collection::func partitioned(by:)` (57/64) | 5 | tested |
| 11 | Permutations.swift:48 | `lastIndex(where: …)!` | `MutableCollection … ::func nextPermutation(upperBound:)` (40/41) | 16,754 | tested |
| 12 | Product.swift:70 | `element1!` | `Product2Sequence.Iterator::func next()` (33/33) | 14 | tested |

**SIP.** "0 members of 0 ranked", of 6,090 candidates. "2 markers: 0 tested (0 on partly run lines), 0 untested, 2 with no coverage data (2 on a type with no coverage data)"; left out: `unconditionalTrap` 1, the rest 0. SIP's production code holds only 2 `uncheckedSendable` findings and 1 `unconditionalTrap`; its other marker findings are outside `Sources/`, in `Tests/` and in unscanned fixtures. The second coverage run prints the same counts.

| Marker | Verdict | Against the rule | Human view |
|---|---|---|---|
| `@unchecked Sendable` on `LargeStackWorkers.Box` (`LargeStackWorkers.swift:81`) | no coverage data, on a type with no coverage data | right: Box has no function records, only a stored property with no initialiser | disagree: the code that uses Box ran (`run(_:)` 1,019 times, `box.value = body()` on line 60). No wrong row results; it reads "no data" rather than "tested" |
| `@unchecked Sendable` on `CheckPropertyKind` (`CheckProperty.swift:35`) | no coverage data | right: SwiftInferMacro has no coverage data | agree |

**Fixture.** `swift test --filter RiskyUntested` in the scratch SwiftStats copy passed its 4 tests, including the exact rows of the `Risky` fixture package. After the review fixes the fixture also covers `forceCast`, a deinitialiser, a generated file and scores above 1, so on this evidence the empty lists on both packages come from the packages, not from the signal.

SIP can show only the race-on-a-type case; swift-algorithms only tested lines. The line-level untested and partly run cases are exercised by the fixture alone.

### 4. Determinism, carry, rebuild, clean trees, interrupts

**`report` twice.** Byte-identical in both formats on both packages. swift-algorithms: Markdown 20,299 B, JSON 3,585,082 B. SIP: Markdown 58,768 B, JSON 65,693,300 B. The auditors' own `report` runs on store copies were byte-identical too.

**Carry.** A plain `scan` after `scan --coverage` reported coverage `ran` with reason "carried from the scan of 2026-11-20T23:26:15Z" (swift-algorithms) and "carried from the scan of 2026-11-20T23:25:53Z; tests failing (swift test exited 1); coverage merged from the test processes' profiles" (SIP). The coverage object, options and roll-ups equal the coverage scan's; on SIP all 13,557 record keys and ranges are equal. The report adds "Carried from the scan of …: the tree and its functions' lines are unchanged since." and otherwise differs only in the snapshot date, the coverage collector's reason and the other collectors' durations. Signals are unchanged.

**Rebuild, then a plain scan.**
- On both packages, touching a SwiftStatsCore source and running `swift build -c release` recompiled the module but did not relink the product: `swiftstats` kept its inode, mtime and sha256 `3433c203…6f26`. The scan after it carried, but proves nothing about a new build.
- A debug build (sha256 `eb4307a5…b612`) stood in for a different build identity. On both packages its plain scan carried with equal coverage. On swift-algorithms the store recorded the new `swiftstats` identity `sha256:eb4307a5…`, which the auditor confirmed. On SIP that snapshot was later replaced by a release scan, since the store keeps one snapshot per commit, so its identity can no longer be checked.
- **This check is weak by design.** The carry compares commit, tree state, map rule and record keys and ranges; it never consults the SwiftStats binary. So "carries after a rebuild" holds by construction, and what the check shows is that the keys still match.

**Clean trees.** `git status --porcelain` printed nothing after every step on both packages, with the outside store and with the default store. `scan --coverage` without `--store` wrote `.swiftstats/stats.sqlite`; `git check-ignore -v` attributes it and `.swiftstats/coverage-build` to `.swiftstats/.gitignore:1:*`. At the end, `--ignored` shows only `.build/` and `.swiftstats/`, plus `.swiftinfer/` on SIP.

**`Package.resolved` on SIP.** The manual `swift test` re-run used for SIP's test counts wrote `Package.resolved` into the package at 17:32:24, after the coverage scan ended, and it stayed until 17:51:07. Five later scans ran with it: `scan-plain`, `scan-plain-after-rebuild`, `scan-plain-debug-binary`, `scan-coverage-default-store` and `scan-plain-default-store`. Their `dependencies` section gained a `lockfile` with pins that the first scan's lacks; the final release scan matches the first again. The second coverage run also resolved against that lockfile. The clean-tree checks still passed only because SIP's `.gitignore` ignores `Package.resolved`. SwiftStats' own runs did not write it: the coverage run restores the file's earlier state, the fix for review finding 2.

**Interrupts** (swift-algorithms only). A harness started the scan, polled the process tree every 0.1 s, sent SIGINT to the `swiftstats` process once a trigger process appeared, and checked every descendant it had seen 2 s after exit.
- **During the build** (third attempt; the first came after the build had finished and the second was a harness argument error): with every source touched, the signal came at 4.25 s while `swift-build --build-tests` ran with a `vtool` child. `swiftstats` died of SIGINT 0.11 s later; 32 descendants were seen and none was alive 2 s later.
- **During the tests:** the signal came at 8.79 s with `swift-test` and `xctest` running. `swiftstats` died 0.10 s later; 65 descendants were seen and none survived. No `swift-build`, `swift-test`, `xctest` or `swiftpm-testing-helper` was left anywhere on the machine.
- **The next `scan --coverage`** finished with rc 0 in 9.80 s, tests passed, and the checker passed on it. That completion is the evidence of no SwiftPM lock: the results' grep for "lock" read only SwiftStats' one-line output, which carries no SwiftPM text.
- **Nothing was stored** by the interrupted scans: the store's snapshot id is 4 after exactly 4 successful scans into it (AUTOINCREMENT). Its single snapshot row shows nothing on its own, since a unique index allows only one per commit.
- The harness signalled only the `swiftstats` process, not the process group a terminal's Ctrl-C reaches.

### 5a. Uneven clone testing

| | swift-algorithms | SIP |
|---|---|---|
| Members / pool | 5 / 225 | 138 / 2,029 |
| Kinds | near-miss 1, renamed 3, exact 1 | subtree 78, near-miss 32, sequence 28 |
| Copies in generated files; with no mapped line | 0; 211 | 0; 1,025 |
| Classes with fewer than 2 measurable copies | 43 | 293 |
| Folded | 0 | 47 |
| Uncovered lines counted by more than one item | 0 | 35 |

Both lists were recomputed from the scan JSON's clone classes and per-line data, by the runs and again by the auditors: the same members, copy sets, covered/mapped figures and scores. Which class folds into which, and SIP's 35 uncovered lines counted by more than one item, were not checked independently.

**swift-algorithms** (all rows):

| # | Least-covered copy (subject) | Score | Copies (covered/mapped) | Kind |
|---|---|---|---|---|
| 1 | `EitherSequence … ::func index(_:offsetBy:)` (EitherSequence.swift:156) | 10 | `index(_:offsetBy:limitedBy:)` 8/10; `index(_:offsetBy:)` 0/10; `distance(from:to:)` 8/10 | near-miss |
| 2 | `CycledTimesCollection.Index::static func <` (Cycle.swift:93) | 6 | AdjacentPairs.swift:173 3/3; Cycle.swift:93 0/3; Split.swift:438 0/3; Stride.swift:153 3/3; Windows.swift:90 3/3 | renamed |
| 3 | `MutableCollection::func rotate(toStartAt:)` (Rotate.swift:220) | 3 | Rotate.swift:220 0/3; Rotate.swift:280 3/3 | exact |
| 4 | `AdjacentPairsSequence::var underestimatedCount` (AdjacentPairs.swift:122) | 3 | `underestimatedCount` 0/3; `AdjacentPairsCollection::var count` 3/3 | renamed |
| 5 | `IndexedCollection::var indices` (Indexed.swift:68) | 3 | `startIndex` 3/3; `endIndex` 3/3; `indices` 0/3 | renamed |

**SIP** (first 20; copies are measured, at least 80% covered / at most 20%):

| # | Least-covered copy (subject) | Score | Copies | Kind | Folded |
|---|---|---|---|---|---|
| 1 | `LiftedCounterSignal::static func roundTrip(forwardCallee:backwardCallee:sourceLocation:origin:)` | 60 | 16; 11 / 5 | near-miss | 1 |
| 2 | `InteractiveTriage::static func associativeStub(for:customGenerator:)` | 34 | 6; 4 / 2 | near-miss | 5 |
| 3 | `BiconditionalWitnessDetector.Visitor::func visit(_: ClassDeclSyntax)` | 27 | 7; 4 / 3 | subtree | 0 |
| 4 | `TestLifter::static func counterSignal(from:slice:origin:)` | 26 | 6; 1 / 5 | near-miss | 1 |
| 5 | `TemplateRegistry::static func collectMembershipModelLaws(_:into:)` | 24 | 10; 2 / 8 | subtree | 0 |
| 6 | `SwiftInferCommand.Discover::static func scoringRescueWarning(for:)` | 22 | 3; 1 / 2 | near-miss | 2 |
| 7 | `SwiftInferCommand.AcceptCheck::static func runPipeline(…)` | 18 | 7; 4 / 3 | subtree | 0 |
| 8 | `SwiftInferCommand.DiscoverReducers::static func renderDefensiveCopySummary(_:)` | 16 | 6; 2 / 4 | sequence | 1 |
| 9 | `InteractiveTriage::static func emptyRangeStub(for:customGenerator:)` | 15 | 2; 1 / 1 | near-miss | 0 |
| 10 | `SwiftInferCommand.DiscoverReducers::static func renderInteractionCandidates(_:)` | 15 | 2; 1 / 1 | subtree | 1 |
| 11 | `SwiftInferCommand.AcceptBridge::static func run(target:workingDirectory:directory:request:output:diagnostics:now:)` | 15 | 2; 1 / 1 | near-miss | 0 |
| 12 | `ConvertCounterexampleEngine::static func renderInversePair(_:)` | 15 | 6; 1 / 2 | near-miss | 1 |
| 13 | `SwiftInferCommand.Discover::static func focusRescueWarning(for:)` | 15 | 3; 1 / 2 | near-miss | 0 |
| 14 | `AcceptInteractionError::var description` | 12 | 2; 1 / 1 | near-miss | 0 |
| 15 | `InteractiveTriage::static func inversePairStub(for:)` | 12 | 2; 1 / 1 | sequence | 1 |
| 16 | `FunctionScanner::static func scan(file:)` | 12 | 5; 2 / 3 | subtree | 2 |
| 17 | `SwiftInferCommand.Metrics::func run()` | 12 | 5; 1 / 4 | subtree | 0 |
| 18 | `SwiftInferCommand.DiscoverInteraction::static func runInteractiveBranch(suggestions:workingDirectory:target:triageIO:)` | 12 | 10; 6 / 4 | subtree | 0 |
| 19 | `AccumulatorFinder::func visit(_: ClosureExprSyntax)` | 12 | 5; 1 / 4 | subtree | 0 |
| 20 | `CorpusStatusRenderer::static func describe(_:)` | 12 | 12; 8 / 4 | near-miss | 1 |

SIP's row 1 is five poor copies of 12 uncovered lines each: `roundTrip`, `idempotence`, `commutativity`, `monotonicity` and `reduceEquivalence` are 0/12, while `countInvariance` is 12/12. `top uneven-clone-testing --limit 1000` prints all members.

**The links re-run (5b)** ran `scan --coverage` again on both packages. swift-algorithms' uneven clone testing came out byte-identical, Markdown and JSON. SIP's has 139 members against 138 (subtree 79): 136 items are identical, `CalleeNameCollector.freeCalleeName(of:)` (score 6) left, `RoundTripTemplate.docstringCorroborationSignal(for:)` (5) and `IdempotenceTemplate.inferredEffectSignal(for:)` (near-miss, 4) joined, and one class went from 4 to 5. The signal reads only coverage, and covered lines differed in 10 records, the run-to-run variation of §1. The earlier checker, pointed at the new outputs, agrees on all 139.

### 5b. Tests per public function

The first build linked a test when it named the function: by base name for free functions and protocol extension members, and by name with the type's simple name for members, labelled "heuristic: the test's target ran it and the test names it". Its hand-checks (below) found six ways that misled it: (a) overloads sharing a base name, (b) tuple labels and unrelated members, (c) local variables, (d) calls through test helpers, missed, (e) tests `--skip` left out, still counted, and (f) types sharing a simple name. At the user's request the links were tightened (PRD §7.8): calls must fit the function's argument labels, accessors link only through member reads, qualified type names must fit, test helpers are followed, and skipped tests count for nothing. Item 5 was then re-run on both packages with a release build of tree `9759b3c8`, into new stores, with the same configs. The coverage itself didn't move: on swift-algorithms every coverage record equals the first run's apart from `linkedTests`; on SIP, covered lines differed in 10 records, the run-to-run variation of §1. Figures are "first run → re-run".

| Scope | Public | With coverage | Linked | Unlinked | Reached generically | Extension members | Linked tests median / p90 / max | Links |
|---|---|---|---|---|---|---|---|---|
| swift-algorithms, production | 299 | 299 | 94 → 94 | 10 → 10 | 195 | 98 | 5 / 12 / 21 → 3 / 8 / 28 | 593 → 457 over 104 functions |
| SIP, production | 1,350 | 1,350 | 877 → 856 | 456 → 477 | 17 | 1 | 2 / 17 / 147 → 2 / 18 / 1,693 | 9,311 → 18,370 over 1,333 functions |

- **swift-algorithms' 104 counted functions** are 98 protocol extension members, 4 concrete-type members and 2 free functions, in both runs. Every unlinked one has 0 lines covered (the six deprecated `scan` overloads, `rotate(toStartAt:)`, `Sequence::partitioned(by:)` and the two `striding(by:)`), so on this package the unlinked agree trivially. The package has one test target, so the target condition separates almost nothing.
- **swift-algorithms per record:** 55 counts fell, 45 stayed the same and 4 rose; none moved between linked and unlinked. The largest falls are `permutations(ofCount:)`, 21 → 7 for the range overload and 21 → 9 for the `Int?` one, both `min(count:sortedBy:)` 13 → 2, and all four `max(count:…)` 14 → 4. The 4 rises are the lazy `split` overloads, reached through `SplitTests`' `Validator` helper: 1 → 27 for the two `whereSeparator:` ones and 1 → 28 for the two `separator:` ones, the new maximum. The `separator:` counts are right (an auditor checked one, 28 of 28); the `whereSeparator:` ones over-count, since the helper writes both branches and only one test takes the closure branch.
- **SIP per module, linked / unlinked:** SwiftInferCLI 212 → 191 / 148 → 169, SwiftInferCore 422 → 406 / 158 → 174, SwiftInferTemplates 189 → 200 / 120 → 109, SwiftInferTestLifter 53 → 58 / 28 → 23; SwiftInferKitEvidence 1 / 1 and SwiftInferMacroImpl 0 / 1, unchanged.
- **SIP per record:** of the 1,333 counted public functions, 982 are unchanged (569 above 0, 413 at 0), 202 rose (43 of them from 0) and 149 fell (64 of them to 0). By link kind: member 875 linked and 456 unlinked → 854 and 477; 17 witnesses, 1 extension member and 1 free function linked in both runs.
- **SIP's high end is fixture use.** Through helpers, a value type's initialiser counts every test whose fixture builds it:

  | Function | First run → re-run |
  |---|---|
  | `SourceLocation.init(file:line:column:)` | 147 → 1,693 |
  | `FunctionSummary.init(…)` | 72 → 1,455 |
  | `Parameter.init(label:internalName:typeText:isInout:hasDefault:)` | 101 → 1,300 |
  | `SuggestionIdentity.init(canonicalInput:)` | 47 → 553 |
  | `Score.init(signals:)` | 27 → 405 |

  For `SourceLocation.init`, 180 tests write `SourceLocation(…)` themselves; the rest reach it through helpers such as `makeIdempotenceSummary` (53 tests), `makeRoundTripPair` (40) and `makeCommutativitySummary` (39). The tests do run these initialisers, so the counts follow the rule, but the maximum and p90 then measure how often a fixture is used, not how much testing a function gets. While the rule was being built, scoping helpers by visibility brought SIP from 20,996 links (maximum 1,798) to 19,042 (1,694), and the review fixes, chiefly reading what a helper call is written on, brought it to 18,370 (1,693); they took the four test-lifter detectors' `detect(in:)` from 147 links each to 16, 17, 19 and 24.
- **How the re-run's counts were checked.** On swift-algorithms the runner listed every test and helper writing each sampled name and read each call. On SIP the scan gives only counts, so a separate copy of the same tree, differing by one guarded line that writes each record's linked tests to stderr, was scanned; all 1,333 of its lists have exactly the official count. The auditors re-derived every figure above from copies of the stores, and SIP's auditor re-ran `report` to a byte-identical Markdown file.

**Sample of 20 per package (first run).** swift-algorithms: every 6th of the 94 linked records sorted by key (15) and every 2nd of the 10 unlinked (5). SIP: every 58th of the 877 linked and every 91st of the 456 unlinked, in record order. Each count was re-derived by a script that shares no SwiftStats code, then the tests were read by hand, resolving each call to its overload. The re-run checked the same records again under the new rule. A human count counts the tests that reach the overload directly or through a test helper, not through another production function; for rows 6 and 9 of swift-algorithms and rows 8, 15 and 18 of SIP the counts are the re-checked ones, since the first readings counted callers of a forwarding overload or missed helper routes.

**swift-algorithms:**

| # | Public function | Link kind | First run → re-run | Human count | Agrees now (first run) |
|---|---|---|---|---|---|
| 1 | `BidirectionalCollection where Element: Equatable::ends(with:)` | extension | 12 → 6 | 6; the 6 `EndsWithNonEquatableTests` call `ends(with:by:)`, which no longer fits | **yes** (over) |
| 2 | `BidirectionalCollection::startOfSuffix(while:)` | extension | 1 → 1 | 1 | yes (yes) |
| 3 | `Collection where Element: Comparable::max(count:)` | extension | 14 → 4 | 3; the `.max` tuple labels and `Int.max` no longer count, and `testMinMaxSequences` takes the Sequence overload | over by 1 (over by 11) |
| 4 | `Collection::adjacentPairs()` | extension | 12 → 12 | 7; 5 `(0...).prefix(n)` tests use the Sequence overload, with the same labels | over by 5 (same) |
| 5 | `Collection::compacted()` | extension | 3 → 3 | 3 | yes (yes) |
| 6 | `Collection::max(count:sortedBy:)` | extension | 14 → 4 | 1; `testStability` now counts through `assertStability`, but the `.enumerated()` callers take the Sequence overload | over by 3 (over by 13) |
| 7 | `Collection::randomSample(count:)` | extension | 5 → 3 | 2; the `randomSample(count:using:)`-only callers dropped | over by 1 (over by 3) |
| 8 | `Collection::windows(ofCount:)` | extension | 8 → 8 | 8 | yes (yes) |
| 9 | `LazySequenceProtocol … ::joined(by: closure)` | extension | 10 → 6 | 2; bare `joined()` no longer counts | over by 4 (over by 8) |
| 10 | `LazySequenceProtocol::reductions(_:_:)` (exclusive, lazy) | extension | 6 → 3 | 2; the inclusive one-argument calls don't fit | over by 1 (over by 4) |
| 11 | `MutableCollection … ::rotate(subrange:toStartAt:)` | extension | 6 → 4 | 4; the `rotate(toStartAt:)`-only tests dropped | **yes** (partly) |
| 12 | `PermutationsSequence::var count` | member (file match) | 2 → 2 | 2 | yes (yes) |
| 13 | `Sequence where Element: Sequence::joined(by: Element.Element)` | extension | 10 → 6 | 1; arrays resolve to the Collection overload | over by 5 (over by 9) |
| 14 | `Sequence::grouped(by:)` | extension | 2 → 2 | 2 | yes (yes) |
| 15 | `Sequence::minAndMax(by:)` | extension | 8 → 2 | 2; the six `minAndMax()` callers dropped | **yes** (partly) |
| 16–20 | deprecated `scan(_:)`, `scan(into:_:)`, `Sequence::scan(_:_:)`; `Sequence::partitioned(by:)`; `StridingCollection::striding(by:)` | unlinked | 0 → 0 | 0; no test runs these overloads | yes (yes) |

Under each run's own rule, 20 of 20 are right. A human agreed with 10 of 20 in the first run and agrees with 13 of 20 now: rows 1, 2, 5, 8, 11, 12, 14, 15 and the 5 unlinked. The 7 left over-count are all overloads with the same labels that differ only in type, and their total excess over the human counts fell from 67 links to 20.

**SIP:**

| # | Public function | First run → re-run | Human count | Agrees now (first run) |
|---|---|---|---|---|
| 1 | `AcceptBridgeRequest.init(identity:decisionRaw:peerIndex:explicitDecisionsPath:)` | 5 → 5 | 5 | yes (yes) |
| 2 | `IndexStore.upsert(_:into:at:typeShapes:sourceFiles:)` | 7 → 7 | 7 | yes (yes) |
| 3 | `MonotonicityPairResolver.resolve(_:)` | 4 → 4 | 4 | yes (yes) |
| 4 | `VerifierWorkdir.Inputs.init(workdir:userPackage:stubSource:mode:inlinedSources:)` | 37 → 4 | 4; the 33 tests building other nested types named `Inputs` no longer count | **yes** (no) |
| 5 | `CalleeReference.displaySignature` | 1 → 1 | 1 | yes (yes) |
| 6 | `DualStyleNamePair.init(mutating:nonMutating:)` | 2 → 2 | 2 | yes (yes) |
| 7 | `InteractionDecisionsAggregator.Bucket.init(accepted:acceptedAsConformance:rejected:skipped:)` | 1 → 1 | 1 | yes (yes) |
| 8 | `MutationMethod.init(name:isMutating:parameterCount:)` | 8 → 10 | 10; 2 `DiscoverReducersCommandTests` build it through the private `valueSemanticCandidate(…)` | yes (yes, as then read) |
| 9 | `RegisteredGenerator.encode(to:)` | 2 → 0 | 1; the wrong link (`inversePairEncodesAsArray`) is gone, and the real one, through `JSONEncoder` in `roundTripPreservesContents`, writes no `encode(to:)` | partly (partly) |
| 10 | `SetAlgebraShape.isSelfTypedBinaryOp(_:)` | 7 → 7 | 7 | yes (yes) |
| 11 | `TemplateMatch.guardDomainMatch` | 4 → 4 | 4 | yes (yes) |
| 12 | `BiconditionalWitnessDetector.detect(stateTypeName:in: URL)` | 25 → 25 | 0; all 25 call the `String` overload, which has the same labels | no (no) |
| 13 | `IdentityElementTemplate.suggest(for:opsWithIdentitySeed:inheritedTypesByName:carrierKindResolver:)` | 34 → 29 | 29; the 5 `suggest(forLifted:…)` callers are gone | **yes** (partly) |
| 14 | `LiftedTestEmitter.liftedCountInvarianceRegression(funcName:elementTypeName:inputSource:)` | 1 → 1 | 1 | yes (yes) |
| 15 | `TemplateRegistry.applyImpureSubjectVeto(to:summaries:)` | 2 → 7 | 7; 2 direct, 5 through `Self.apply(_:)` | yes (yes, as then read) |
| 16 | `AssociativityPairResolver.Resolved.init(functionCall:)` | 0 → 0 | 0 | yes (yes) |
| 17 | `SwiftInferCommand.Drift.init()` | 0 → 0 | 0 | yes (yes) |
| 18 | `EffectAnnotationAdvice.init(displayName:signature:location:recommendedAnnotation:…)` | 0 → 2 | 2; `rendersAdvice` and `pluralizes`, through the private `advice(_:)` | yes (yes, as then read) |
| 19 | `TemplateMatch.sortedOutputMatch` | 0 → 0 | 2; the tests read `suggestion.match?.sortedOutputMatch`, naming neither `TemplateMatch` nor a matching file | no (no) |
| 20 | `LiftedTestEmitter.UniquifierStub.init(…)` | 0 → 0 | 0 | yes (yes) |

Under the stated rule, 20 of 20 were right in the first run. A human agreed with 15, partly with 2, and disagreed with 3 then; now 17, 1 partly (#9) and 2 (#12, the same-label overload, and #19, a member read that doesn't name its type). The first readings of #8, #15 and #18 missed tests that reach the function through a test helper, so the first run's 15 was generous.

**The auditors' samples in the first run did worse.**
- **swift-algorithms**, 10 linked functions outside the runs' sample. The heuristic matched the auditor's independent count on 10 of 10, but a human agreed with 1 fully (`indexed()`) and 1 partly (`stablePartition(subrange:by:)`, one test direct and one through `stablePartition(by:)`). Seven over-counted, because overloads sharing a base name each got every test that writes the name: the `joined(by:)` overloads got 10 links each against 1 or 2 real callers, and `Sequence::min(count:sortedBy:)` got 13 against 0 direct callers, mostly from the `.min` tuple label in `MinAndMaxTests`. One linked the wrong test: `LazySequenceProtocol::split(maxSplits:omittingEmptySubsequences:whereSeparator:)` was linked to `SplitTests.testLaziness`, which calls only the Equatable `split(separator:)`. Helper-mediated calls were missed: the real `split` caller is `testSequenceDocExamples`, through its `Validator` helper, and `min(count:sortedBy:)` is reached 27 times by `testStability` through `assertStability`. The 6 member and free-function links outside the sample agreed.
- **SIP**, 10 more. The auditor's reimplementation matched 9 counts exactly; the tenth was off by one from the auditor's own regex. A human agreed with 6, partly with 1, and disagreed with 3. Across the 30 sampled links, about 21 agreed, 3 partly and 6 disagreed. The new failure modes: a local variable named like the member counted (`ConstructionUniverse.root(forScanOf:)` had 35 links against about 6 call sites; most tests only declare `let root = …`); helper-mediated calls were missed (`ReducerPurityAnalyzer.analyzeForPurity(_:readingTCANames:)` was unlinked though `ReducerPurityNameTokenTests` calls it through `private static func purity(_:tca:)`); tests excluded by the configured `--skip` still counted, since the link is per target profile (`CorpusPackager.packageMultiModule` was linked to `MultiModuleVerifyMeasuredTests::multiModuleSurveyVerifies`); and type names collided (`SwiftInferCommand.Corpus.init()` was linked to a test that builds `SyntaxSnippetHarvester.Corpus(…)`).

**All 63 earlier links under the new rule.** The runs' 20 and the auditors' 10 per package, plus 3 more swift-algorithms links the auditor checked (`CombinationsSequence::var count`, `chain`, `product`, unchanged at 1, 5 and 5), were kept as an evaluation set, with human counts re-checked in six records: three readings had missed helper routes, two had counted callers of a forwarding overload, and the auditors' `InteractionSuggestionRenderer.render(_:)` was transcribed as 8, while 4 tests call `render(target)` and the other 4 the `render(_:includePossible:)` overload.

| Package | Links | Closer than in the first run | Same distance | Further | Exact now |
|---|---|---|---|---|---|
| swift-algorithms | 33 | 16 | 16 | 1 | 19 |
| SIP | 30 | 9 | 20 | 0 | 26 |

- SIP's 30th, `analyzeForPurity`, went from 0 to 4 links; it has only a lower-bound human count (at least 1), so it is in none of the columns. It is a true link the first run missed.
- The auditors' records now: `root(forScanOf:)` 35 → 6 (about 6), `packageMultiModule` 2 → 1 (1; the skipped measured test is gone), `SwiftInferCommand.Corpus.init()` 1 → 0 (0), `render(_:)` 8 → 4 (4); the other 5 SIP records are unchanged and agree. On swift-algorithms the `joined(by:)` overloads fell from 10 to 6 each (human 1 or 2), `Sequence::min(count:sortedBy:)` from 13 to 2 (human 1), `chunked(on:)` from 5 to 3 (human 2), and `stablePartition(subrange:by:)` from 2 to 1, now exact.
- The one link further off is `LazySequenceProtocol::split(…whereSeparator:)`, 1 → 27 against 1: the `Validator` helper is read whole, whichever branch the test's arguments select.

**Fresh samples under the new rule.** The re-run drew new samples that leave out the 63 links above.
- **swift-algorithms:** the pool was the public records with a count minus those 33, which left 66 linked and 5 unlinked. Sorted by key, every 4th linked one from index 0 (15) and all 5 unlinked; all 15 linked are protocol extension members.
- **SIP:** sorted by key, every 57th of the 856 linked from index 28 and every 95th of the 477 unlinked from index 47; no draw hit a key of the evaluation set.

| # | swift-algorithms public function | First run → re-run | Human count, view |
|---|---|---|---|
| 1 | `BidirectionalCollection where Self == SubSequence::trim(while:)` | 2 → 2 | 1; `testTrimRangeReplaceable` trims an `Array`, which takes the `@_disfavoredOverload` RangeReplaceable one. Over |
| 2 | `BidirectionalCollection::suffix(while:)` | 4 → 1 | 1; `range.suffix(5)` doesn't fit, and the local `let suffix` in PartitionTests no longer counts. Agrees |
| 3 | `Collection where Element: Comparable::min(count:)` | 13 → 5 | 4; `testMinMaxSequences` takes the Sequence overload. Over |
| 4 | `Collection where Self: RangeReplaceableCollection::trimPrefix(while:)` | 2 → 2 | 1; disfavoured, so the `ArraySlice` test takes the other overload. Over |
| 5 | `Collection::combinations<R: RangeExpression>(ofCount:)` | 4 → 4 | 4. Agrees |
| 6 | `Collection::evenlyChunked(in:)` | 2 → 2 | 2. Agrees |
| 7 | `Collection::permutations(ofCount: Int? = nil)` | 21 → 9 | 7; examples 4 and 6 call only the range overload. Over |
| 8 | `Collection::striding(by:)` | 10 → 10 | 10. Agrees |
| 9 | `LazySequenceProtocol where Element: Sequence::joined(by: (Element, Element) -> Separator)` | 10 → 6 | 1 direct; 2 more reach it only through a forwarding overload. Over |
| 10 | `LazySequenceProtocol … ::split(maxSplits:omittingEmptySubsequences:whereSeparator:)` | 1 → 27 | 1; only `testSequenceDocExamples` passes `.closure` to the `Validator` helper. Over |
| 11 | `MutableCollection where Self: BidirectionalCollection::partition(subrange:by:)` | 2 → 2 | 2. Agrees |
| 12 | `MutableCollection::rotate(subrange:toStartAt:)` (the non-bidirectional one) | 6 → 4 | 0 direct; the four tests call it on arrays, which take the bidirectional overload, and it runs only through `stablePartition`. Over |
| 13 | `Sequence where Element: Comparable::minAndMax()` | 8 → 6 | 6; the `by:` callers don't fit. Agrees |
| 14 | `Sequence::adjacentPairs()` | 12 → 12 | 6; the range tests take the Collection overload. Over |
| 15 | `Sequence::keyed(by:)` | 6 → 4 | 4; the `keyed(by:resolvingConflictsWith:)` callers no longer count. Agrees |
| 16–20 | `LazySequenceProtocol::scan(_:_:)`, `MutableCollection::rotate(toStartAt:)`, `Sequence::scan(_:)`, `Sequence::scan(into:_:)`, `StridingSequence::striding(by:)` | 0 → 0 | 0; none ran. Agree |

Under the rule, 20 of 20 are right. A human agrees with 12 of 20: 7 of the 15 linked and all 5 unlinked, which never ran and so say nothing about recall. Of the 8 over-counts, 7 (1, 3, 4, 7, 9, 12, 14) are overloads with the same labels that differ only in types or constraints, and one (10) is the path-insensitive helper.

| # | SIP public function | First run → re-run | Reader view |
|---|---|---|---|
| 1 | `DecisionsLoader.load(startingFrom:explicitPath:fileSystem:)` | 8 → 8 | agrees |
| 2 | `InteractionVerifyOutcomeParser.Result.init(outcome:…)` | 13 → 16 | agrees; 3 through private `entry(…)` helpers, and the common name is always qualified |
| 3 | `SwiftInferCommand.Verify.SurveyRecord.init(…)` | 5 → 12 | agrees; 7 through `Self.record` helpers |
| 4 | `BodySignals.init(hasNonDeterministicCall:…)` | 20 → 113 | **partly**: all 113 are real, 93 through fixture helpers, but 4 `MarkerDispatchTemplateTests` reach it through static stored properties (`Self.front`, `Self.chain`), which aren't followed |
| 5 | `Decisions.init(schemaVersion:records:)` | 56 → 63 | agrees; 7 through helpers |
| 6 | `IndexedTypeShape.InitializerParameter.init(label:typeName:)` | 3 → 9 | agrees; `PropertyLawCore.InitializerParameter(…)` is excluded by its qualifier |
| 7 | `ManifestConditions.read(manifest:)` | 3 → 3 | agrees |
| 8 | `ReducerDiscoverer.discover(directory:)` | 91 → 4 | agrees; `discover(source:file:)` and `discover(file:)` no longer fit |
| 9 | `SemanticIndexEntry.updated(from:)` | 5 → 11 | agrees; `InteractionIndexEntry.updated(from:)` callers don't name the type |
| 10 | `SyntaxSnippetHarvester.Corpus.init(snippets:nodeTypeNames:)` | 1 → 4 | agrees; 3 through `Self.source()`, and no other `Corpus` counts |
| 11 | `AssociativityTemplate.makeConstraint(vocabulary:reducerOps:inheritedTypesByName:)` | 1 → 1 | agrees |
| 12 | `HomomorphismTemplate.suggestMemberForm(for:)` | 1 → 1 | agrees; an unapplied reference with its label, passed to `flatMap` |
| 13 | `LiftedTestEmitter.emptinessAgreement(predicate:measure:holdsWhenPositive:carrier:seed:)` | 1 → 1 | agrees |
| 14 | `ReorderPartitionTemplate.suggest(for:)` | 4 → 4 | agrees |
| 15 | `LiftedSuggestion.commutativity(from:origin:)` | 10 → 12 | agrees; 2 through `commutativityLifted(…)` |
| 16 | `JSONArtifactStore.write(_:to:)` (unlinked) | 0 → 0 | agrees |
| 17 | `ValueSemanticStubEmitter.Inputs.init(typeName:mutationMethods:moduleName:testable:)` (unlinked) | 37 → 0 | **disagrees: 2**, built as `ValueSemanticStubEmitter.emit(.init(typeName:…))`, an implicit `.init` passed as an argument; the first run's 37 came from the `Inputs` collision |
| 18 | `MemberAccessShape.spelling(of:)` (unlinked) | 0 → 0 | agrees; a test's own `spelling(of:style:)` helper doesn't fit |
| 19 | `ViewModelNameHeuristics.isBool(_:)` (unlinked) | 0 → 0 | agrees |
| 20 | `RoleClosureTemplate.role(of:)` (unlinked) | 1 → 0 | agrees; reached only through `suggest`, a production function |

Under the rule, 20 of 20 are right. A reader agrees with 18, partly with 1 (#4), and disagrees with 1 (#17). The first run's counts matched a reader's on only 9 of these 20: 8 linked functions missed helper-reached tests, #8 was over by 87, and #17 and #20 had links from name collisions.

**The auditors' fresh samples.**
- **swift-algorithms**, 10 linked protocol extension members drawn at random from outside every earlier sample. Every count equals the rule, 10 of 10. A human agrees with 3 (`stablePartition(by:)` 1, `cycled(times:)` 7, and the lazy Collection Equatable `split(separator:)` 28, a recall gain from the helper), partly with 5, and disagrees with 2 (the lazy `reductions(into:_:)`, 2 against 0 direct, reached only through a forwarding production overload; the eager `joined(by:)` with an element closure, 6 against 1). Every miss is an overload with the same labels.
- **SIP**, 7 linked and 3 unlinked, drawn at random from outside every earlier sample. Every count equals the rule, 10 of 10. A human agrees with 9, among them `DocumentedRangeTemplate.suggest(for:)` (25, 20 through private helpers) and `PackageTree.init` (8, 2 across suites through a private typealias). The one disagreement is `IndexedTypeShape.init(from: Decoder)`, 15: all are callers of the same-labelled `init(from: TypeShape)`, and `Codable`'s requirements aren't in the witness list.

**The first run's failure modes now:**

| | Failure mode | Now |
|---|---|---|
| (a) | Overloads sharing a base name | Fixed where labels differ (`ends(with:)` 12 → 6, `ReducerDiscoverer.discover(directory:)` 91 → 4); open where only types or constraints differ, the main error left on swift-algorithms |
| (b) | Tuple labels and unrelated members | Fixed: the `.max` and `.min` tuple labels and `Int.max` no longer count (`Sequence::min(count:sortedBy:)` 13 → 2) |
| (c) | Local variables | Fixed (`ConstructionUniverse.root(forScanOf:)` 35 → 6) |
| (d) | Calls through test helpers, missed | Followed (`analyzeForPurity` 0 → 4, `applyImpureSubjectVeto` 2 → 7, `testStability` through `assertStability`); a helper is read whole, so `Validator` over-counts the lazy `whereSeparator:` overloads |
| (e) | Tests `--skip` left out, counted | Fixed (`CorpusPackager.packageMultiModule` 2 → 1); swift-algorithms' config has no `--skip` |
| (f) | Types sharing a simple name | Fixed (`VerifierWorkdir.Inputs.init` 37 → 4, `SwiftInferCommand.Corpus.init()` 1 → 0, `ValueSemanticStubEmitter.Inputs.init` 37 → 0) |

The figure is produced and labelled a heuristic, as decided. On SIP, where most public functions are members of concrete types, a reader now agrees with 27 of 30 fresh links, though helpers make the distribution's high end a count of fixture use. On swift-algorithms, where 98 of the 104 counted functions are protocol extension members and many overloads differ only in type, 22 of the 40 linked functions sampled in the re-run (both runner samples and the auditor's) still over-count.

## Times

Release build, this Mac. The two package runs overlapped in time: SIP's first `scan --coverage` (17:25:53 to 17:31:18) overlapped swift-algorithms' first coverage scan, its reports, its plain scan, its interrupt runs and the start of its second coverage scan, and SIP's first reports and its manual test re-run overlapped swift-algorithms' rebuilds and debug-binary scan. SIP's manual test re-run (17:32:23 to 17:35:03) also ran at the same time as SIP's own first `report` and `top` runs. The swift-algorithms audit (files dated 17:40 to 17:45) ran during SIP's rebuild and debug-binary scan. Times taken in those windows include CPU contention.

| Run | swift-algorithms | SIP |
|---|---|---|
| First scan without coverage (`--no-store`, config check) | 2.96 s | 70.12 s |
| First `scan --coverage`, cold coverage build | **34.39 s** (collector 28.9 s) | **324.52 s** (collector 313.6 s) |
| Second `scan --coverage`, warm build, default store | 9.80 s | 160.55 s |
| Plain scan carrying coverage | 7.52 s; 6.69 s after the rebuild | 41.94 s, 42.03 s, 41.78 s, 41.78 s |
| Plain scan with the debug binary | 15.91 s | 218.09 s |
| `report`, Markdown (two runs) | 2.24 s, 1.68 s | 2.11 s, 2.18 s |
| `report`, JSON (two runs) | 1.57 s, 1.66 s | 2.75 s, 2.73 s |
| `top risky-untested`, `top uneven-clone-testing` | 1.37 to 1.64 s | 1.61 to 1.87 s |
| `scan --coverage` with the tightened links (tree `9759b3c8`), warm build | 12.06 s (collector 7.2 s) | 162.48 s (collector 150.9 s) |

- **SIP's cold coverage run:** the build took about 168 s (to the last bundle's mtime at about 17:28:41), the tests about 140 s (to the last profile at 17:31:01), and the remaining 17 s or so covers merging, export, `show`, decoding, mapping and the store write. SwiftStats' own share was not timed apart from the LLVM tools, so the design's bound of under 15 s for it is not shown either way. The design expected about 150 s of build and 150 s of tests cold.
- **The plain scans** include SwiftProjectLint, which M4's runs skipped; the carry reads only the old coverage rows. §12 criterion 1 (swift-collections) was not re-measured for M5.
- **`report` on SIP:** 2.11 to 2.18 s for Markdown and 2.73 to 2.75 s for JSON, against M4's 2.59 s on a snapshot with no coverage and no SwiftProjectLint findings. The design's bound is not more than 10% slower than M4; the slowest run, JSON at 2.75 s, is 6% over M4's figure, and the comparison is not like-for-like.

## Decisions

Decided for M5 (the user, during planning):

- **The done-when packages are SIP and swift-algorithms.**
- **Risky + untested counts a marker as untested when it sits on a line no test ran.** Markers keep the line rule, and the signal also counts markers on partly run lines.
- **Tests per public function links a test when its target's own coverage ran the function and the test names it**, labelled a heuristic.
- **Tests build in `<package>/.swiftstats/coverage-build`.**
- **An empty risky + untested list counts when its counts are printed** and a fixture test shows the signal yields rows.
- **A plain scan carries earlier coverage when the tree is the same and every stored coverage key still names a record with the same range**; otherwise it refuses, naming `scan --coverage` and `--drop-coverage`.

Decided during the review:

- **Coverage needs Swift Build's per-target bundles.** Every SwiftPM command passes `--build-system swiftbuild` (Swift 6.2 or later), and a bundle that is no test target fails the run. The test targets come from the coverage toolchain's own `swift package describe`, not the PATH toolchain's.
- **`Package.resolved` is put back** as it was before the run.
- **Files that aren't Swift are their own drop class, `otherLanguage`**, kept out of the mapped share.
- **An extension member's access is capped by the extended type** when the module declares it, not by the extension's modifier, for records and the API surface alike (PRD §7.5).
- **A test also names a function through its parameter clause and its `@Test` `arguments:` collections**, never its display name or traits. The label was reworded with the user's agreement, from "its body names it" to "the test names it".
- **Deinitialisers, like initialisers, don't count as running** in the race-on-a-type rule.
- **A requested coverage run that failed or was skipped still carries, with a warning** saying so; damaged held coverage gives an error naming both `scan --coverage` and `--drop-coverage`.

Decided after the done-when hand-checks:

- **Tighten the links** (the user, after seeing item 5's samples): calls must fit the function's argument labels, accessors link only through member reads, qualified type names must fit, test helpers are followed, and tests `--skip` leaves out count for nothing (PRD §7.8). The label became "heuristic: the test's target ran it and the test, or a test helper it calls, calls it with fitting labels or reads it (a subscript: names its type)".
- **The coverage run records the link rule** as the option `links:`, and a carry refuses coverage linked by another rule ("its functions were linked to tests by another rule"), so a store holding the first build's links can't carry them.
- **Left open:** whether helpers should count for value-type initialisers. As built they do, so SIP's fixture initialisers count most of its tests (5b).

Choices made while building, where the design left room or strict SwiftLint forced a shape:

- **The carry's record check goes both ways**: a production record with no stored coverage also refuses. A carried reason keeps the original run's reason. A `scan --coverage` whose run fails carries the held coverage with a warning, or is refused, like a plain rescan; only a run that ran replaces held coverage.
- **Duplicate markers merge only when the column is known**, since SwiftProjectLint gives none; this gives swift-algorithms' 12 markers on 11 lines.
- **Files are risky + untested subjects too**, for global and file-level markers. In the race-on-a-type verdict a type's attachments neither clear it nor give it data, since summed attachments can't tell a lazy getter from a stored-property initialiser. An attachment-only type stays in the pool, so crash markers on its attachment lines are judged by line. Production is inferred for type and file markers, since the stored snapshot has no targets.
- **`functionCoverage` stores `reason` and `link`**, so a carried report can tell witnesses and extension members apart; `saturated` is a list of `{file, line}`; uneven clone testing's copies sit under `clone.coverage`, as `clone.copies` was already M4's count.
- **Record lines include the entries' skipped `#if` regions**, as llvm's per-function view does.
- **Access:** setters take a written `private(set)` level; subscripts with no accessor records count as public functions; free functions link by a fitting call, bare or module-qualified (by base name in the first build); operators are always unlinked.
- **A `--skip` regex may not be empty or start with `-`**, so no flag gets past the allowlist. Reasons redact the toolchain directory as `<toolchain>`.

## Review

Each of the eight implementation steps (01 to 07, with 03b, the checker) was reviewed as it was built. Those reviews raised 24 findings (1 high, 6 medium, 17 low); all were fixed, one of them in the next step. The high one was the coverage fixture's nested package matching the repository's `Packages/` ignore rule, so it would never have been committed.

The finished code then had an adversarial review across eight areas: the run, mapping, links, the store, carrying, signals, tests and conformance to the design. A verifier reproduced each claim. 25 findings were confirmed (2 high, 7 medium, 16 low), none contested or refuted. Three pairs were the same defect (#1/#23, #2/#24, #17/#21), so there were 22 distinct defects. 21 were fixed in four groups, each code change with a regression test that fails with the fix undone, except the help text (#14), which has no test; #25 was fixed in PRD v0.2.11. Each group's fix was then checked in turn; those checks found 5 more defects, all fixed. After the fixes, 512 tests in 104 suites passed (377 in 80 after M4, 483 in 102 before the review), and strict SwiftLint was clean. The test-link label was reworded after that run, which changed one test's expected text (`MarkdownCoverageTests`). No full `swift test` is recorded on the measured tree `a7ed6c25`; only `swift test --filter RiskyUntested` ran on it (4 tests).

| # | Finding | Fix |
|---|---|---|
| 1, 23 | (high) Toolchains whose default build system is native (Swift 6.3 and earlier) build one merged test bundle, so every public function read as unlinked, with no warning | `--build-system swiftbuild` on every SwiftPM command; a toolchain that rejects it, or a bundle that is no test target, fails the run with a reason |
| 2, 24 | The coverage build wrote `Package.resolved` into the package root, dirtying the tree, and coverage then dropped out of `report` after the next plain scan | The file is saved before the first SwiftPM command and restored after success, failure and interrupt |
| 3 | A top-level entry with no statement-line regions gave 0 of 0 instead of null; inactive top-level `#if` statements read as untested | The record stays null; uncovered statement lines become skipped ranges |
| 4 | C targets' files counted as `otherPackage` drops | New drop class `otherLanguage` |
| 5 | An extension member's access was capped by the extension's modifier | Capped by the extended type when the module declares it |
| 6 | Backticked member names could never be linked | Backticks stripped before lookups |
| 7 | An implicit `.init(…)` never counted as a call of its type | Counts as a call of the binding's annotated type |
| 8 | A parameterized test's signature and `@Test` arguments weren't read | Read for names and calls, traits excluded |
| 9 | Witness detection missed `LosslessStringConvertible` and superclass conformances | Both added |
| 10 | No test detected coverage rows left when a snapshot is replaced | Test only; the cascade was right |
| 11 | Carrying onto a dirty tree with the same hash was never tested | Unit and scan tests, plus a refusal-order test |
| 12 | A requested coverage run that was skipped silently carried old coverage and lost its reason | Carries with a warning; a refusal names the skip |
| 13 | Damaged held coverage blocked every rescan, and `--drop-coverage` couldn't get past it | A cheap holds-coverage check first; `--drop-coverage` replaces it |
| 14 | `backfill --help` still said only history and tool results are held | Reworded |
| 15 | A deinit cleared an `@unchecked Sendable` type the tests only built | Deinitialisers left out with initialisers |
| 16 | Risky tests couldn't detect wrong scoring, a swapped `byRule` pair or a reversed order | Fixture functions with 2 and with 1-of-2 untested markers; exact rows, scores and payloads asserted |
| 17, 21 | The 80%/20% thresholds were never tested at the boundary | Boundary test at 4/5 and 1/5, 7/9 and 2/9 |
| 18 | `CloneFolding` output wasn't in ordinal order as documented | Sorted by ordinal |
| 19 | Generated-file exclusion of both signals was untested | A generated fixture file and tests; uneven clone testing counts generated copies apart |
| 20 | No test could detect a broken runner tie | A test where only the runner rule can tie groups to bundles |
| 22 | `forceCast` was never exercised | A fixture `as!` and marker-identity rows |
| 25 | The PRD still described behaviour M5 changed (the tier flag, per-collector replacement, the codecov JSON) | PRD v0.2.11 (§6.2, §6.5, §6.6, §7.8) |
| check | The bundle guard used test targets from the PATH toolchain's description | Uses the coverage toolchain's own `swift package describe` |
| check | The parameterized-test fix also read `@Test` traits, so `.timeLimit(.minutes(1))` could link `minutes` | Only the `arguments:` collections are read |
| check | The link label still said "its body names it" | Reworded after the user agreed |
| check | The damaged-coverage error didn't mention `--drop-coverage` | It names both ways out |
| check | A generated type with an attached stored-property initialiser still counted as a risky + untested candidate | Left out when all its rows are in generated files |

**Tightening the links** (5b) was built and reviewed the same way. Each piece of the new rule was reverted on its own and rebuilt, and each time named tests failed or, for the cycle guard, the ping/pong test hung (stopped after 90 s). Reverting accessors-as-member-reads needed two places undone, since candidates come from member reads; undoing only the match check passed. A review of the change then raised findings of which thirteen were real, fixed in the eight groups below, each with a regression test. Overloads with the same labels were confirmed but only documented, since no rule that ignores types can separate them; a partial fix through `@_disfavoredOverload` was not taken, since it would undercount `Array.trimPrefix`, which can reach only the disfavoured overload. Each fix and each of the reviewers' 13 mutants was then undone in turn, and a named test failed on all 29 undos. The Coverage fixture's expectations didn't move: its 33 public functions keep their counts (25 linked, 8 unlinked or null). On tree `9759b3c8`, `swift build --build-tests` gives no warnings, `swift test` passes 532 tests in 108 suites, and strict SwiftLint reports 0 violations.

| Finding | Fix |
|---|---|
| (medium) A call reached a test helper whatever it was written on | A call on `self`, `Self` or `super` reaches only members of the caller's own types; a chain of names reaches no free helper, a chain ending in a type of the target (typealiases resolved) only that type's members, and another capitalised name none |
| (medium) `--skip` read Swift Testing IDs unlike Swift Testing | The location is where the `@Test` attribute's name starts; the IDs and tags of `@Suite` types the test's ID passes through are matched; `tag:`, `id:` and backticks are read as Swift Testing reads them |
| (low) Bare calls in a test-target extension of a production type were missed | `Self(…)`, `Self.init(…)` and `self.init(…)` call the enclosing type's initialiser; bare calls there also count as calls on `self` |
| (low) A nested test type couldn't reach an enclosing type's static helper | Every enclosing type, and what each inherits, counts as around the caller |
| (low) Calling a closure-valued property, `x.maker()`, didn't read it | A member called with no argument labels also counts as a member read |
| (low) Module qualifiers used the target name | The C99 module name |
| (low) Carried coverage kept the old link counts | The run records `links:`, and the carry refuses coverage linked by another rule |
| Dead code: an unused initialiser, and a no-record fallback that would have bypassed the skip filter and helper expansion | Removed; the fallback returns nil |

## Known limits

- **Test links still over-count and under-count.** Argument types are never read, so overloads with the same labels (Sequence vs Collection, lazy vs eager, `Int?` vs a range, `detect(stateTypeName:in:)` with `String` vs `URL`) each get every fitting call; this is the main error left on swift-algorithms. A helper is read as everything it writes, whichever branch the test takes (`Validator`: 27 links against 1). Through helpers, value types' initialisers count every test whose fixture builds them (`SourceLocation.init` 1,693), so SIP's p90 and maximum measure fixture use; whether helpers should count for initialisers is left open. Missed: `emit(.init(…))` and `.init() as T`, fixtures built in stored properties, member reads that name neither the type nor a matching file (`suggestion.match?.sortedOutputMatch`), and functions reached only generically (`encode(to:)` through `JSONEncoder`). `Codable`'s `init(from:)` and `encode(to:)` aren't witnesses, so they are linked as members, through the callers of a same-labelled overload where there is one (31 on SIP, 1 of them linked). On fresh samples under the tightened rule a human agreed with 12 of 20 and 3 of 10 on swift-algorithms, and 18 of 20 and 9 of 10 on SIP; the first, name-only rule got 10 of 20 and 1 of 10, and 15 of 20 and 6 of 10, on its own samples. The figure is a heuristic, and labelled one.
- **Swift 6.1 and the native build system are not supported.** Coverage needs `--build-system swiftbuild`, accepted by Swift 6.2 and later; Swift 6.1.2 fails with "this toolchain's swift doesn't accept `--build-system swiftbuild`, and coverage needs Swift Build's test bundles, one per test target (Swift 6.2 or later)". On 6.3.3 with Swift Build, the fixture built into per-target bundles by hand, but only with a scratch developer directory and extra linker flags the collector can't pass, so a full end-to-end scan on 6.3.3 was not verified on this machine. 6.2.4's bundle layout was checked; its build failed here for SDK and deployment-target reasons.
- **`llvm-cov report`'s line totals differ from SwiftStats'** (4,390 against 4,006 lines on swift-algorithms), since SwiftStats follows lcov's DA lines. Regions agree.
- **Done-when 1(b) was reworded**, and swift-algorithms never exercises the shared-line case that motivated it.
- **Risky + untested:** a type's stored-property initialisers and lazy getters are attached coverage and, in the race-on-a-type verdict, neither count as running nor give the type data; a type with attached coverage and no function is counted wherever it is declared, generated files included, as the store keeps no file for a type; a marker on a line where other code ran reads as tested, and one reached only by crashing exit tests reads as untested. On SIP the one verdict a reader would call wrong (`LargeStackWorkers.Box`) is harmless but reads "no coverage data". Neither package exercises the untested or partly run line cases.
- **Coverage varies between runs** more than the design said: on SIP the set of run lines moved in 11 files and uneven clone testing gained two items; the links re-run's coverage moved covered lines in 10 records and gave 139 members against the first run's 138.
- **The carry never consults the SwiftStats build**, only the map and link rule strings (`map:` and `links:`): a rebuild that changes how tests are linked without changing the `links:` rule, such as the witness list or the access rules, keeps the old links until `scan --coverage` runs again. A `DecodingError` from a held report's warnings still comes through raw, not as damaged coverage.
- **The interrupt checks ran only on swift-algorithms**, signalled only the `swiftstats` process, and show no SwiftPM lock only by the next scan completing.
- **No timeout on the coverage run**, so a test that hangs blocks the scan; SwiftStats' own share of its time was not measured.
- **A Swift file with lone-CR line endings** makes `llvm-cov` reject the export, which fails the collector (PRD §7.8).
- **The scan's own `swift package describe`, run with the PATH toolchain, still creates `<root>/.build`**, as before M5. Both clean-tree results rely on `.build/` being ignored, as it is in both packages.
- **SwiftInferProperties' temporary copy can still copy a `Package.resolved`** that the coverage build is rewriting at the same moment; putting the file back afterwards doesn't stop that.
- **SwiftStats records no test counts**: SIP's 6,939 tests and 6 failures come from a manual re-run, which left the `Package.resolved` that changed five later scans' `dependencies` section (disclosed above).
- **Dependencies were not resolved** on either package, so the dependencies collector was skipped in every run.
- **Not in M5**, as the PRD says: per-type test-to-code ratios, tests not keeping up by coverage, and the partial (coverage-based) genuinely under-tested. Each needs per-test attribution that one run can't give.
