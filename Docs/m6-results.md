# M6 results

**Date:** 2026-11-22 · **Toolchain:** Apple Swift 6.4.2 (swiftlang-6.4.2.1.9, Xcode 27.2), macOS 27.2 SDK, LLVM 21.0.0; neither package has a `.swift-version`, so swiftly's default, Xcode's 6.4.2, built, tested and mutated both · **Machine:** Apple M3, 8 cores, macOS 27.2.1 · **Git:** 2.54.0 (Apple Git-157) · **Tools:** SwiftMutator 0.1.0 (release build of SwiftMutator `b16642de`, which contains `13f96a46`; sha256 `5138cbf1…5ba8`), SwiftLint 0.65.1, GRDB 7.12.0, SwiftEffectInference `ba3624d` (linked), SwiftProjectLint 1.1.0 (release build of SwiftProjectLint `6477efac`, product `CLI`), swift-infer 1.160.0 (release build of SwiftInferProperties `79908525`), swift-clone-detector 0.1.0 (release build of SwiftCloneDetector `97eee1c`) · **SwiftStats:** release build of tree `0d16ddb5`, the M6 working tree over `383a2de` after the review fixes; `swiftstats` 0.0.1, sha256 `ea90cd17…4efb`. The done-when fixes came after the runs, in tree `e9f24c5d` (below)

M6 scope (PRD §11): T3, SwiftMutator's results joined per function through `results.jsonl`, with `scan --mutation --since <rev>` runs merged per file, same-tree rescans carrying the results, and four signals: weak tests, best property-test target, genuinely under-tested and the mutation part of uneven clone testing. The done-when packages are swift-algorithms at `5b7143f` and SwiftEffectInference (SEI) at `c8644fd`. The design is PRD v0.2.12: §6.2, §6.3, §6.5, §6.6, §7.8, §7.9, §7.13, §8, §9, §10, §10.1, §11, §13, §15 and D9.

## Done-when

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | On both packages, per-function mutation figures match SwiftMutator's own JSON report, by an independent checker | Met | `Scripts/mutation-check.py base` passes checks a to g with 0 differences on both base runs, and again on both full runs of the branch commit, the three resumed runs and the run after the forced kill. swift-algorithms: 1,442 rows (1,404 tested, 38 not covered), 1,404 report entries joined one to one, 255 records. SEI: 1,584 rows (1,413 tested, 171 not covered), 1,413 entries, 295 records. |
| 2 | ≥ 95% of in-body mutants mapped, the rest listed | Met | 1,440 of 1,440 and 1,580 of 1,580 (100.00%). Attached to types: 2 and 4, all stored-property initial values. Dropped and unmapped: 0 on both, so the list is empty and the report says "Every mutant in a production file was mapped." |
| 3 | Weak-tests and best-property-target lists produced (an empty list counts with a printed funnel and a fixture test showing rows), uneven clone mutation too, and genuinely under-tested produced, expected empty on single-module packages, with the fixture showing rows | Met | swift-algorithms: weak tests 5, best property target 4, uneven clone mutation 4, genuinely under-tested 0 with the single-module funnel line (4 with the optional ratio set to 1.0). SEI: 26, 42, 5 and 0 (8 with the ratio). The checker's `signals` mode re-derives every item, score, order and funnel count on both, both configs. Fixture tests list rows for all four: the Mutation fixture end to end for three, `PropertyTargetHarness` snapshots (a fake swift-infer index and hand-made mutation results) for best property target. The done-when runners, agents rather than a human, read up to 20 items per list, and an audit corrected one read: 11 of 17 worth attention on swift-algorithms (weak tests 0 of 5) and 44 of 53 on SEI. The design's human read was not done. |
| 4 | A `--since` run on a branch updates only the changed files' results: unchanged files' rows carried untouched, changed files retested, their unchanged functions keeping their verdicts, checked by store rows per function | Met; swift-algorithms' unlisted side branch partly met | swift-algorithms: 1,347 carried rows identical, 95 fresh rows only in the two changed files, 472 unchanged functions (16 shifted) with 1,433 mutants and 0 verdict differences. SEI: 1,496, 88, and 331 functions (18 shifted) with 1,571 mutants and 0 differences. No killed↔timedOut flip needed the exception. A full run on each branch commit agrees on every retested mutant; staleness among carried rows is 0 of 1,347 and 1 of 1,496. Side branches: the unlisted one on swift-algorithms needed a new file, and SEI's exposed a checker gap, fixed afterwards. |
| 5 | `report` byte-identical twice, a plain rescan carries, trees clean, an interrupt leaves no process and `--resume` finishes | Met; the design's stricter interrupt check was partly met in the runs and fixed afterwards | Byte-identical reports and carries on both, also with a SwiftStats binary rebuilt with a change; trees clean after every step with both stores. Interrupts (swift-algorithms: SIGINT to the process group, SIGTERM to `swiftstats`; SEI: SIGINT): every process gone within 0.5 s, every resume finished with the base's key set. The design also asked that `pending.json` name the results file after an interrupt; it didn't, on any run. Fixed after the runs and checked with the real SwiftMutator on the Mutation fixture, not re-run on either package. |

Each package's runs were then audited independently. The auditors re-derived the numbers from the stores, the results files, SwiftMutator's report and the scan JSON, re-ran every checker mode and `report` and `top` on copies of the stores (all byte-identical to the runs' outputs), and ran no SwiftMutator. They re-timed nothing, so every time and performance figure below rests on the runners' measurements alone. They confirmed every headline number and the runners' statuses: Met, except Partly met for swift-algorithms' unlisted side branch (no file fit, so a new one stood in) and for the interrupt check, and SEI's unlisted side branch Met for SwiftStats though the checker as shipped failed on it. They corrected one hand read (`CombinationsSequence.count`, below), called one note misleading, found three small count errors in the runs' notes and a design "as-built note" credited in part 3 that doesn't exist, and pointed out that the runs' terminal output hid a refused mutation step. Their corrections are folded into the sections below; the figures are the audited ones.

## What M6 adds

- **The `swiftmutator` collector**, opt-in with `scan --mutation` (also with `--no-store`), never run by `backfill` or `diff`'s scans; `collectors.swiftmutator.enabled: false` skips it even when asked. It runs alone, after every other collector, in a temporary copy under `.swiftstats/mutation/work/`: a `git clone --shared` of the package's repository (a full checkout; no objects copied) at the scanned commit, with the uncommitted and untracked changes laid over it, skip-worktree, assume-unchanged and filtered files copied from the work tree, and every scanned file's SHA-256 checked against the scan, a differing file byte-copied and counted. A warm `swift build --build-tests` keeps `build-cache/` current between runs. SwiftStats writes the config (`muter.conf.yml`, passed with `-c`) and runs `swift-mutator run --skip-update-check`, with `--workers` and `--timeout` only when `options.workers` and `options.timeout` are set; `arguments` takes only `--skip <regex>` pairs, coverage's allowlist. The results file is found through SwiftMutator's log folder and copied to `runs/<id>/`, with `swift-mutator report -f json` beside it for the suspect flags. Identity is `sha256:` plus the results header's `executableSHA256`. Exits map to `ran` or `failed` by termination reason and status; SwiftMutator gets SIGTERM, 35 s, then SIGKILL, while coverage keeps M5's policy. `pending.json` records a run that `scan --mutation --resume` can continue, and a run's results are kept until its snapshot is stored. An orphaned SwiftMutator, left by a scan killed outright, is found by its own lock and refused, naming its pid.
- **Reading and mapping.** `results.jsonl` formats 1 to 4 per header, sessions and `projectDelta`, the last line of a key winning, `retired`, unparseable lines skipped, not covered from the last header's `mutantsNotCovered`, completeness against the last header's count. Mutants map through M5's file classes and placement: a hash gate on the new `FileRecord.sha256`, NFC paths compared by bytes, the BOM's column shift, an anchor inside a token, then the innermost record, else the innermost type, else the file. The rule string is stored as the option `map:`.
- **Figures.** Mutation score is SwiftMutator's formula (killed ÷ killed, survived, no coverage and timed out; multiplied before dividing), per record, module, project and every mutant, the last printed beside SwiftMutator's own truncated percent for a single full run. Function score also counts not-covered mutants as unkilled; it is the signals' figure.
- **`scan --mutation --since <rev>`** runs `swift-mutator run --since <full SHA>` and merges per file with the clean snapshot of `<rev>`: retested files take the new rows, files with the same hash keep the base's rows (`carried`, with their run's provenance), deleted files are dropped, changed files SwiftMutator tested nothing in are `unlisted`, and files with no usable result are `unresolved`. Six refusals come before SwiftMutator starts (no snapshot, no results, incomplete results, not an ancestor, another build or settings, a changed manifest). Test files changed since the base are listed, since their effect on carried verdicts isn't retested.
- **Keeping results across rescans.** A rescan whose `swiftmutator` didn't run carries the held results when the tree, the map rule and every record and file hash still match, with state `ran` and "carried from the scan of …"; otherwise it refuses before writing, naming `scan --mutation` and `--drop-mutation`. Refusals the git state settles come before anything runs. `backfill` keeps snapshots holding mutation results.
- **Store migration v5**: `mutationScan`, `mutationRun`, `mutationFile`, `mutationSuspect` and `mutant` (one row per mutant). Scan JSON `schemaVersion: 8` (adding `files[].sha256` and the mutation block), report 5, top 4, diff 3; trend stays 1.
- **Configuration**: `collectors.swiftmutator.{enabled, path, arguments, options.workers, options.timeout}`; `signals.weak-tests.{coverage, score, mutants}`, `signals.genuinely-under-tested.{coverage, score, mutants, ratio}` and `signals.uneven-clone-mutation.{high, low, mutants}`, with defaults 80/50/3, 20/20/3 (ratio unset) and 80/20/2.
- **Four signals**: `weak-tests` (line coverage at least 80% and function score under 50% with a mutant that ran and wasn't checked, or a kill only suspect tests made; scored by survived and timed-out mutants and suspect-only kills), `genuinely-under-tested` (at most 20% covered, function score under 20%, in a module with no test code or a test-to-code ratio below the project's or, when set, below `ratio`; scored by unkilled mutants), `best-property-target` (an algebraic SwiftInferProperties suggestion of any tier and unkilled mutants, plus a two-function law's partner's) and `uneven-clone-mutation` (a clone copy at least 80% killed and one at most 20%). Each rule prints its thresholds and a funnel whose parts add up.
- **Reports**: a Markdown Mutation section (status, runs, settings, scores per scope, functions by state, mutants by operator, killing-test limits, suspects, files by disposition, dropped and unmapped), per-record and roll-up mutation deltas in `diff`, mutation metrics in `trend`. A side whose results leave files out compares scores only.
- **`Scripts/mutation-check.py`**, the independent checker (modes `base`, `merge`, `since`, `signals`, each written before its first real run), **`Scripts/record-mutation-fixture.sh`**, and the **Mutation fixture** (`Core` and `Extras`, with a function for each signal but best property target, which `PropertyTargetHarness` snapshots cover, since recording swift-infer is out of scope).

## Results on the two packages

### Setup and the SEI baseline

Scratch clones in the session scratchpad, with `--store` and `--config` outside each package. Nothing was built or changed in the owners' repositories; only read-only git commands ran there (clone, archive, log, cat-file, and one auditor's plain `git status`, whose transient lock changed SEI's `.git` mtime). swift-algorithms is a clone of M5's mirror clone at `5b7143f8e2` (`1.2.0-24-g5b7143f`); SEI is a clone of the owner's repository at `c8644fd19e` (committed 2026-10-30), the revision the SEI probe measured and the owner's `main`. SwiftStats links SEI at `ba3624d`, which is 7 commits ahead; that doesn't affect which commit is scanned. The other tools are M5's builds, used in place. SwiftMutator is the probe's release build of `b16642de`, used as it was.

Unlike M5, dependencies were resolved in both packages, from the SwiftPM cache (swift-numerics 1.1.1, swift-syntax 603.0.2), so the dependencies collector ran. SEI's config adds `["--skip", "chainClassifiesInLinearTime|subclassNamesakesScale|selfInClassesScale"]` to both `collectors.coverage.arguments` and `collectors.swiftmutator.arguments`: three wall-clock ratio tests that make a control run fail without it. Neither config sets `options.workers` or `options.timeout`. A third config per package adds `signals.genuinely-under-tested.ratio: 1.0`, read only by `report` and `top`.

**SEI baseline (design §9 step 0): passed.** `swift test` with the skip printed "Test run with 393 tests in 37 suites passed after 1.758 seconds". `swift-mutator mutate-without-running` planned 1,413 mutants in 20 files with 171 in `mutantsNotCovered`, the design's expected figures.

A first `scan --no-store` of each package ran every collector except coverage and swiftmutator ("not requested") and history (`--no-store`): 756 records in 56 files and 826 in 57.

The runs went one after another; only one SwiftMutator run was ever active, and none overlapped CPU-heavy work, apart from the deliberate scan while an orphaned run was alive (§7). swift-algorithms ran from 02:19 to 07:52 and SEI from 03:10 to 08:32, interleaved by part.

### What each package gives

| | swift-algorithms `5b7143f` | SEI `c8644fd` |
|---|---|---|
| Production files tested; holding mutants | 28; 28 | 22; 21 |
| SwiftMutator run | 1,404 tested (16 more dropped in inactive `#if` branches), 38 not covered | 1,413 tested, 171 not covered |
| Stored rows | 1,442 | 1,584 |
| Killed (crash kills), survived, timed out, no coverage, build error, not covered | 1,144 (630), 222, 37, 0, 1, 38 | 1,031 (24), 377, 4, 1, 0, 171 |
| Mutation score | 1,144 / 1,403 (81.54%; SwiftMutator: 81%) | 1,031 / 1,413 (72.97%; SwiftMutator: 72%) |
| Kills naming no test | 616 (53.85%), all crash kills | 24 (2.33%), all crash kills |
| Kills judged for suspects; suspect-only kills | 514 of 514; 0 | 1,007 of 1,007; 0 |
| Production functions: scored, only not covered, no mutant | 240, 15, 218 of 473 | 272, 23, 41 of 336 |
| Records with mutants; attachments | 255; 2 | 295; 4 |
| Workers, per-mutant limit (SwiftMutator's default), control runs | 4, 28.69 s, 14 (0 failed) | 4, 25.60 s, 14 (0 failed) |
| Lines covered (coverage collector) | 3,864 / 4,006 | 3,249 / 3,557 |
| Test lines / production lines (the one module's ratio) | 2,217 / 4,592 | 3,336 / 3,916 |

- **Timeouts.** SwiftMutator reran every timeout alone under the same limit; all 37 and all 4 timed out again.
- **Against earlier real runs of the same commits**, by key: swift-algorithms has 0 verdict differences from the step 04d and step 05 runs (17 outcome differences each, all failed↔runtimeError). SEI has 0 from the probe's skip run, and 1 from step 08a's run: `ConstructionCollector.swift:595:12`, killed in 08a by a wall-clock test outside the skip list, survived here and in both probe runs. No list changed.

### 1. Base runs and times

Each base snapshot came from `scan --coverage --mutation` with every collector, at B, into a new store.

| Part | swift-algorithms | SEI |
|---|---|---|
| Whole scan | **2,472.57 s** (41:13) | **1,049.31 s** (17:29) |
| SwiftMutator (`swift-mutator run`, timed by SwiftStats) | 2,441.175 s (header: 2,429.0 s) | 995.168 s (header: 968.918 s) |
| Warm build, cold cache | 9.941 s | 19.904 s |
| `swift-mutator report` | 0.210 s | 0.273 s |
| The whole `swiftmutator` step (stored) | 2,452.822 s | 1,016.801 s |
| **SwiftStats' own share of the step** (copy, hash check, reading, mapping) | **1.496 s** (1.706 s with the report) | **1.456 s** (1.729 s) |
| Everything beyond SwiftMutator and the warm build | 21.45 s: coverage 14.087, other collectors 5.013, SwiftStats' mutation share 1.706, the rest 0.65 | 34.24 s: coverage 25.925, other collectors 5.478, mutation share 1.729, the rest 1.106 |

- **The design's budget** is under 30 s for SwiftStats' own share beyond SwiftMutator and the warm build. The share is 1.5 to 1.7 s on both packages, and about 1.4 s in every later run. The rest of the scan is mostly the coverage run, which is M5's.
- **The split above can't be re-checked.** SwiftMutator's, the warm build's and the report's times come from SwiftStats' lines in `.swiftstats/mutation/swift-mutator.log`, which every later scan overwrites; the auditors could check only that they add up to the stored step time, which they do.
- **The warm build with a warm cache:** 3.552 s, 3.183 s and 3.250 s on swift-algorithms (the since run, the full run of the branch commit, the run after the forced kill); 7.449 s, 5.346 s, 5.431 s and 6.083 s on SEI (the since run, the full run of the branch commit, side branches T and U). Whether it shortens SwiftMutator's own run was not measured.
- **Against the probes:** SwiftMutator took 2,441 s against step 04d's 2,610.2 s and the probe's 44.1 min on swift-algorithms, and 995 s against the probe's 989 s on SEI.
- Trees were clean afterwards, with no `work/` or `pending.json` left.

### 2. The independent checker

`mutation-check.py base` shares no SwiftStats code. It ran against the scan JSON, the stored results file, the scanned sources and SwiftMutator's JSON report, once with the report SwiftStats stored and once with a report it made itself; the outputs differ only in the report path.

| Check | swift-algorithms | SEI |
|---|---|---|
| a. Own reader of `results.jsonl` gives the scan's mutants | PASS: 1 session, format 4, 1,404 tested keys, 38 not covered, 0 lines that don't parse; 1,442 keys, 0 missing, 0 extra, 0 verdict or field differences; 25 run facts, complete, 1,404 of 1,404 | PASS: 1 session, format 4, 1,413 tested, 171 not covered; 1,584 keys, 0 differences; complete, 1,413 of 1,413 |
| b. Verdicts equal SwiftMutator's report | PASS: 1,404 keyed entries one to one, 0 placeholders; `mutantsByOutcome` equal; `globalMutationScore` 81 = 81; 28 file scores | PASS: 1,413 entries one to one, 1 keyless placeholder skipped (`ImportCollector.swift`, no coverage); 72 = 72; 20 file scores |
| c. Suspect-only flags, tri-state | PASS: false 514, null 928 | PASS: false 1,007, null 577 |
| d. Own placement, plus a column-exact text check | PASS: record 1,440, type 2; anchors at the point 1,079, previous token 360, next token 3; text check 425 end-anchored, 1,017 start, 3 past trivia, 0 failures | PASS: record 1,580, type 4; anchors 1,228, 345, 11; text 441, 1,143, 11, 0 failures |
| e. Counts from the report's outcomes equal records, attachments and roll-ups | PASS: 255 records, 0 differences; Algorithms and production 1,144/1,403 = 81.54 | PASS: 295 records, 0 differences; 1,031/1,413 = 72.97 |
| f. Not-covered rows | PASS: 38 listed, 38 rows, all on records | PASS: 171, 171, all on records |
| g. Stored rows | PASS: store v5; `mutationScan` 1, `mutationRun` 1, `mutationFile` 57, `mutationSuspect` 0, `mutant` 1,442; 40 roll-up numbers | PASS: 1, 1, 58, 0, 1,584; 40 roll-up numbers |

- **How independent it is.** The checker trusts the scan JSON's record ranges and top-level statement lines, which M5's checker verified against llvm-cov; everything else it derives itself. It was written in plan step 4d, before any real run was accepted.
- **End-anchored points.** 65 on swift-algorithms and 96 on SEI (RelationalOperatorReplacement's `false` constants, SwapTernary's first link, RemoveSideEffects before `}`) start the next token; the design's rule takes the token before them, and the text check confirms each.
- **M5's `coverage-check.py`** passed every check on swift-algorithms. On SEI it failed 1d on 1 of 648 names: the initializer of a class declared inside a function (`Finder` in `bindsPattern(named:in:)`, `ConstructionChecker.swift:365`), whose demangled name the checker couldn't parse. SwiftStats' record was right, and 1e's reimplementation agreed on all 336 records. The checker was fixed after the runs; on a rerun of the base scan in a clone at `c8644fd`, the old checker reports 647 of 648 and the new one 648 of 648, with every other check unchanged. The base scans' coverage builds were later overwritten by the branch-commit scans, so these passes rest on the runners' original outputs: re-run on swift-algorithms' base scan JSON afterwards, the checker fails 8 checks against the C-tree export, and SEI's fix was checked by rescanning in a clone.

### 3. Mapped share

| | swift-algorithms | SEI |
|---|---|---|
| In-body mutants mapped to records | 1,440 / 1,440 (100.00%) | 1,580 / 1,580 (100.00%) |
| Attached, counted apart | 2, to types, both killed | 4, to types, all killed |
| Dropped (build, outside the root, test files, other language, other package) | 0, 0, 0, 0, 0 | 0, 0, 0, 0, 0 |
| Unmapped | 0 | 0 |
| Files: tested, not mutated | 28, 29 | 22, 36 |

Every attachment is a FlipBooleanLiteral on a stored property's initial value, for example `internal var striding: Bool = false` (`Stride.swift:89:35`) and `var hasRefutations = false` (`ConstructionFacts.swift:110:26`). Even counted as unmapped, the share would be 99.86% and 99.75%. With nothing unmapped, the list is empty on both; the unmapped path is covered by fixture tests (the Coverage fixture's excluded file, and changed-file, symlink and non-UTF-8 cases).

### 4. The four lists

| | swift-algorithms | SEI |
|---|---|---|
| Weak tests | 5 of 155 candidates | 26 of 181 |
| Genuinely under-tested | 0 of 155, single-module line printed | 0 of 181, single-module line printed |
| … with `ratio: 1.0` | 4 | 8 |
| Best property-test targets | 4 of 13 functions with results | 42 of 63 |
| Uneven clone testing (mutation) | 4 of 85 classes with two measured copies | 5 of 39 |

- **Funnels.** Weak tests on swift-algorithms: "473 production functions = 470 with coverage data + 3 without; 470 = 155 with at least 3 scored mutants + 100 with fewer + 0 with only build errors + 215 with none + 0 without results; 155 = 151 at least 80% covered + 4 less; 151 = 5 listed + 0 under 50% only through code no test ran + 146 not under 50% and with no suspect-only kill". SEI's last line is "164 = 26 listed + 3 under 50% only through code no test ran + 135 not under 50% …". Suspects were judged for every kill by a failing test among those candidates (446 and 858).
- **Genuinely under-tested on the default config** prints "one production module: its ratio is the project's, so no function can be listed", as the design expected for both packages. 4 and 8 functions are at most 20% covered with a function score under 20%; all are counted as "in a module whose test code isn't low".
- **The ratio variant.** With `ratio: 1.0` the one module (0.48 and 0.85 test lines per production line) counts as low, and the list becomes exactly those 4 and 8 functions. The value 1.0 was step 08a's and is a choice: the decision added the key and named no value. Its report differs from the default only in that section.
- **The checker's `signals` mode** passed on both packages and both configs: schema 5 and the limits; nothing left out; the module ratios re-derived from the roll-ups (Algorithms 2,217/4,592 and SwiftEffectInference 3,336/3,916, `notLow`, or `belowRatio` with the ratio); every list's candidates, rule and funnel numbers, item order, scores, ranks and payloads. It trusts the stored clone ranges, `partnerKey` and coverage tallies. The auditors' own SQL derivation gave the same weak-tests and ratio lists, in order.
- **The fixture.** On the Mutation fixture, `Core.clamp` is weak tests' row, `Extras.normalizedB` and `Extras.unused` are genuinely under-tested's (`Extras`' ratio is below the project's), `Core.neverCalled` is counted but not listed, the clone pair is uneven clone mutation's row, and best property target is covered by `PropertyTargetHarness` snapshots (a fake swift-infer index and hand-made mutation results, stored and read back).

**Hand reads.** A reader read up to 20 items per list and package, read the function and its tests, and judged each worth attention or not. There was no bar.

**swift-algorithms** (all rows; ROR = RelationalOperatorReplacement):

| List | # | Function | Score | Killed / scored | Worth attention? | Note |
|---|---|---|---|---|---|---|
| Weak tests | 1 | `SplitCollection::func index(after:)` (Split.swift:508) | 8 | 6/14 | No | One survivor is a `precondition` made `true`; two `<`→`!=` survivors are equivalent; the five timeouts stop the index reaching `endIndex`, so the tests hang on them, which counts as "ran but unchecked" |
| | 2 | `Collection::func chunks(ofCount:)` (Chunked.swift:863) | 2 | 1/3 | No | Both survivors are in `precondition(count > 0, …)`; only a trap test could kill them |
| | 3–5 | `StridingCollection::init(base:stride:)`, `StridingSequence::init(base:stride:)`, `WindowsOfCountCollection::init(base:windowSize:)` | 2 each | 1/3 each | No | The same `precondition` boundary pattern |
| Ratio 1.0 | 1 | `InterspersedMapSequence.Index::func hash(into:)` (Intersperse.swift:598) | 6 | 0/6 | Yes, minor | The index's `Hashable` conformance never runs |
| | 2 | `CycledTimesCollection.Index::static func <` (Cycle.swift:93) | 3 | 0/3 | Yes, minor | Never runs; sibling index types' `<` are killed |
| | 3 | `Sequence::func partitioned(by:)` (Partition.swift:278) | 3 | 0/3 | Yes | Every test calls it on an `Array`, which takes the `Collection` overload |
| | 4 | `SplitCollection.Index::static func <` (Split.swift:438) | 3 | 0/3 | Yes, minor | As #2 |
| Best target | 1 | `AdjacentPairsSequence::var underestimatedCount` (AdjacentPairs.swift:123) | 2 | 0/2 | Yes, minor | No test reads it on a sequence base; a non-negativity property wouldn't kill either mutant |
| | 2 | `CombinationsSequence::var count` (Combinations.swift:63) | 2 | 0/2 | Yes, minor (audited) | The runner called both survivors equivalent. The auditor showed `66:20` (`n + 1`→`n - 1`) is not: for `"ABCD".combinations(ofCount: ...2)` it counts 16 instead of 11, and no test checks that range |
| | 3 | `MutableCollection::func partition(subrange:by:)` (Partition.swift:124) | 1 | 0/1 | No | The one unkilled mutant makes the loop endless; it timed out |
| | 4 | `StridingCollection::func striding(by:)` (Stride.swift:136) | 1 | 0/1 | Yes, minor | No test strides a `StridingCollection` again; a composition property fits |
| Uneven clone | 1 | `SplitCollection.Index::init(baseRange:…)` (Split.swift:405) | 4 | 1/5 against five siblings at 5/5 | Yes, minor | The same gap as ratio #4 |
| | 2 | `CycledTimesCollection.Index::static func <` (Cycle.swift:93) | 6 | 0/3 and 0/3 against three at 3/3 | Yes, minor | Ratio #2 and #4 |
| | 3 | `ExclusiveReductionsSequence::func distance(from:to:)` (Reductions.swift:326) | 2 | 0/2 against 2/2 | Yes, minor; debatable | A `case` arm for a backward distance never runs. The auditor noted the type is a forward-only `Collection`, so the arm is reachable only through a distance its contract doesn't allow |
| | 4 | `AdjacentPairsSequence::var underestimatedCount` (AdjacentPairs.swift:122) | 2 | 0/2 against 2/2 | Yes, minor | Best target #1 |

11 of 17 are worth attention (the runner's 10, plus `CombinationsSequence.count` after the audit), all but one minor. Weak tests on this package is noise: 4 of its 5 items are survivors in `precondition` guards, which no test can kill without trap tests, and the fifth counts hangs as unchecked. The other lists name the same few functions no test runs.

**SEI** (first rows of weak tests and best target, all rows of the others; RSE = RemoveSideEffects):

| List | # | Function | Score | Killed / scored | Worth attention? | Note |
|---|---|---|---|---|---|---|
| Weak tests | 1 | `TypeShapeCollector::recordStorage(_:of:into:)` (ConstructionCollector.swift:490) | 17 | 14/31 | Yes | 11 survivors in the optional-defaults rule; the tests assert only `refuted`, and the checker's fallback refutes anyway, masking a wrong `hasDefault` |
| | 2 | `ConstructionFacts::reachableScopes(from:chain:)` (ConstructionFacts+Resolution.swift:92) | 13 | 5/20 | Yes | No test constructs a function-local type or extends a nested type |
| | 3 | `ConstructionChecker::literalElementExpectations(of:_:)` (ConstructionChecker.swift:236) | 11 | 2/15 | Yes | A base-less `.init` inside tuple, array and dictionary literals; one test kills anything |
| | 4 | `ConstructionFacts::mentions(_:)` (ConstructionFacts.swift:141) | 10 | 9/19 | No | A pre-filter: its survivors only cost time, or are masked |
| | 5 | `ConstructionChecker::sequenceExpectations(of:in:sequence:)` (ConstructionChecker.swift:225) | 8 | 7/16 | Yes | `.init` after a ternary or `??` is untested |
| | 6 | `ConstructionChecker::transparentParent(of:_:)` (ConstructionChecker.swift:214) | 7 | 1/10 | Yes | `.init` through `try`, `await` or a ternary branch |
| | 7 | `CallShape::scan(_:from:labels:)` (ConstructionDeclaration.swift:244) | 7 | 12/25 | Yes | The variadic branch never runs; three survivors are likely equivalent |
| | 8 | `EffectSymbolTable::mergedInference(existing:incoming:)` (EffectSymbolTable.swift:382) | 6 | 0/6 | Yes, minor | Needs a two-pass test where the losing side has the stronger anchor |
| | 9 | `CallShape::reaches(_:)` (ConstructionDeclaration.swift:225) | 6 | 4/13 | Yes | The loop skipping omittable parameters never runs |
| | 10 | `ConstructionFacts::bodiesCrossed(from:)` (ConstructionFacts+Resolution.swift:117) | 6 | 3/9 | Yes | The local-type gap of #2 |
| Ratio 1.0 | 1 | `PurityRefutation::phrase(for:)` (PurityRefutation.swift:207) | 7 | 0/7 | Yes, minor | Message strings no test reads |
| | 2 | `EffectAnnotationParser::extractByLabel(from:)` (EffectAnnotationParser.swift:317) | 6 | 0/6 | Yes | `@ExternallyIdempotent(by:)` is never parsed in a test |
| | 3 | `Substring::firstIdentifier()` (EffectAnnotationParser.swift:553) | 6 | 0/6 | Yes | Reached only through #4 |
| | 4 | `EffectAnnotationParser::extractByQualifier(from:)` (EffectAnnotationParser.swift:382) | 5 | 0/5 | Yes | The doc-comment form is never parsed |
| | 5 | `EffectSymbolTable::declaration(matching:)` (EffectSymbolTable.swift:196) | 4 | 0/4 | Yes | Public API that nothing in SEI or its tests calls |
| | 6 | `EffectAnnotationParser::isClockDeterministic(declaration: VariableDeclSyntax)` (EffectAnnotationParser.swift:430) | 3 | 0/3 | Yes, minor | Its `FunctionDeclSyntax` twin is 3/3 |
| | 7 | `TotalityChecker::visit(_: AsExprSyntax)` (PurityInferrer.swift:942) | 3 | 0/3 | Yes, minor | Reached only on operator-folded trees, which SEI's callers never make |
| | 8 | `VariableDeclSyntax::firstBindingName` (SyntaxHelpers.swift:40) | 3 | 0/3 | No | Dead code: nothing uses it |
| Best target | 1 | `ConstructionFacts::mentions(_:)` (predicate, Possible) | 10 | 9/19 | No | Weak tests #4 |
| | 2 | `CallShape::reaches(_:)` (predicate, Possible) | 9 | 4/13 | Yes; the property fits | Pure over value types |
| | 3 | `DeclarationShape::accepts(_:)` (predicate, Possible) | 9 | 13/22 | Yes; the property fits | Pure over value types |
| | 4 | `EffectAnnotationParser::extractByLabel(from:)` (value-round-trip, Advisory, blocked) | 6 | 0/6 | Yes; the property doesn't fit | A parser with no printer; ratio #2 |
| | 5 | `Substring::firstIdentifier()` (idempotence, Possible) | 6 | 0/6 | Yes; the property doesn't fit | The suggested idempotence property would kill none of the 6 |
| | 6 | `ConstructionChecker::isLocallyBound(_:at:)` (predicate, Advisory, blocked) | 6 | 7/13 | Yes, minor | Init and closure parameters untested |
| | 7 | `DeclarationShape::acceptsOrdinaryArguments(_:against:)` (predicate, Possible) | 6 | 22/28 | Yes, minor; the property fits | 4 of 6 survivors equivalent |
| | 8 | `EffectAnnotationParser::extractByQualifier(from:)` (guard-domain, Likely) | 5 | 0/5 | Yes | Ratio #4 |
| | 9 | `ConstructionFacts::fitsUnmemoised(_:_:depth:)` (predicate, Advisory, blocked) | 4 | 9/13 | No (mostly) | Depth-bound mutants only move where a cycle is cut |
| | 10 | `PurityInferrer::isAmbientFormatting(_:)` (predicate, Possible) | 4 | 15/19 | Yes, minor | Syntax guards; example tests fit better than a property |
| Uneven clone | 1 | `ConstructionFacts::localTypeName(of:)` (ConstructionFacts+Resolution.swift:188) | 4 | 0/4 against `declaredName(of:)` 4/4 | Yes | No test declares a local type |
| | 2 | `DeclarationShape::from(declaration: InitializerDeclSyntax)` (ConstructionDeclaration.swift:273) | 4 | 1/5 against its function twin 5/5 | Yes | Default and variadic flags checked only for functions |
| | 3 | `ConstructionChecker::isLocallyBound(_:at:)` (ConstructionChecker.swift:343) | 2 | 0/2 against 2/2 | Yes, minor | Best target #6 |
| | 4 | `TotalityChecker::visit(_: AsExprSyntax)` (PurityInferrer.swift:942) | 3 | 0/3 against two at 3/3 | Yes, minor | Ratio #7 |
| | 5 | `EffectAnnotationParser::isClockDeterministic(declaration: VariableDeclSyntax)` (EffectAnnotationParser.swift:430) | 3 | 0/3 against 3/3 | Yes, minor | Ratio #6 |

Read in all: weak tests 17 of 20 worth attention (4 minor; not: #4, a pre-filter, #13, duplicated trivia appends, and #18, whose survivors are mostly hangs the tests detect), ratio list 7 of 8 (3 minor), best target 15 of 20 (7 minor), uneven clone 5 of 5 (3 minor): 44 of 53. The SEI auditor read 10 items the runner hadn't (weak tests 21 to 26, best target 21 to 24) and judged 9 of them worth attention.

- **On SEI the lists are mostly real gaps**, clustered in construction resolution: function-local types, contextual `.init` types, memberwise and initializer shapes, generic-parameter shadowing and call-shape matching. SEI's own conservative rules ("a call no known initializer accepts refutes anyway", "looser is the safe direction") let mutants that narrow matching survive tests that only assert `refuted`, and weak tests surfaces that.
- **Equivalent mutants still appear** on both: `<`→`!=` on unit-step indices, a pre-filter's `true` mutants, duplicated trivia appends, early-guard bypasses.
- **Best property target's property often doesn't fit.** It fits 4 of SEI's 20 read (pure functions of plain values) and doesn't fit 2; for 1 of them (`firstIdentifier`'s idempotence) it would kill none of its 6 mutants; syntax-tree predicates rank high though example tests suit them better. On swift-algorithms the suggested property fits 1 of the 4.
- **The lists overlap.** On both packages the same never-run functions appear in up to three lists.

### 5. `--since`, read as changed files

On each package a branch commit C from B (a) changes one function's body in file F1 so later lines shift, (b) renames file F2 unchanged with `git mv`, and (c) changes only a comment in a test file. `scan --coverage --mutation --since <B>` ran on C into a copy of the base store, giving S_C. `mutation-check.py since` and `merge`, written before step 6's first real `--since` run, checked it; each runner also wrote a second check of its own, and the auditors a third.

| | swift-algorithms | SEI |
|---|---|---|
| C | `572754b9` | `96b5a59c` |
| F1, the edit | `Stride.swift`: `StridingSequence.Iterator.next()`, +2 lines; 16 later functions shift by 2, 11 of them holding 70 mutants (2 timed out, 12 survived) | `EffectSymbolTable.swift`: `record(signature:effect:)`, +4 −2 lines; 18 later functions shift by 2, 16 of them holding 66 mutants |
| F2 | `Cycle.swift` → `Cycled.swift`, 13 mutants | `ClockDeterminismRefuter.swift` → `ClockDeterminismRefutation.swift`, 14 mutants; 4 private functions' keys name the file |
| Test comment | `ChunkedTests.swift:58` | `EffectSymbolTableTests.swift:66` |
| Since scan | rc 0, **188.50 s**, 7.4% of a full run of C (2,536.66 s); SwiftMutator 170.917 s; 90 mutants in 2 files; 2 workers, 20 s limit | rc 0, **105.42 s**, 10.3% of a full run (1,026.89 s); SwiftMutator 76.773 s; 79 mutants in 2 files; 4 workers, 20 s limit |
| Reason | "merged: 2 files retested since 5b7143f8e2, 26 carried; 1 test file changed since 5b7143f8e2, so carried verdicts weren't retested against them" | "merged: 2 files retested since c8644fd19e, 20 carried; 1 test file changed …" |
| Carried | 54 unchanged paths (26 holding rows), 1,347 rows identical on 14 columns, `carried` 1, run commit = `carriedFrom` = B | 55 paths (19 holding rows), 1,496 rows identical |
| Fresh | 95 rows, only in F1 (82) and F2's new path (13); retested = SwiftMutator's own selection = `since.files` less tests | 88 rows, F1 74 and F2 14; the same equalities |
| Gone | F2's old path `deleted` with 0 rows; no S_B row of F1 left; the test file `changedTest` | the same |
| Per function | 472 unchanged functions (16 shifted), 1,433 mutants: **0 differences, 0 flips**; the one changed function is `next()` | 331 (18 shifted), 1,571 mutants: **0 differences, 0 flips**; F2's 4 path-keyed functions also equal once the path is swapped |
| Signal membership outside F1 and F2 | 432 of 432 functions with equal line tallies; every list the same, ratio variant included | 301 of 302 equal tallies; every list the same |
| `merge` check | 1,442 keys (1,347 carried), 0 differences; totals and roll-ups equal S_B's | 1,584 keys (1,496 carried), 0 differences |
| Full run of C, separate store | F1 + F2: 95 keys, 0 verdict differences; carried: 0 of 1,347 differ (15 outcome-only, failed↔runtimeError) | F1 + F2: 88 keys, 0 differences; carried: **1 of 1,496 differs** |

- **The per-function check** compares, for every function whose key and body hash are equal in S_B and S_C, the multiset of (operator, line − its start, column, occurrence, before, after, verdict) and the counts, for unchanged files and for F1's unchanged functions, whose rows are fresh and whose keys shifted. The decided pass bar is zero differences, except a killed↔timedOut flip that a solo rerun shows to be timing. No flip happened, though both since runs used a 20 s limit against the bases' 28.69 s and 25.60 s.
- **Merged scores** equal the bases' (81.54% and 72.97%), labelled as over merged results ("94.44% of mutants carried from c8644fd19e" on SEI). Kills judged for suspects fell from 514 to 486 and from 1,007 to 949: the since runs judged no suspects, so their fresh kills are null.
- **SEI's one stale row.** `ConstructionFacts.swift:180:37` (ROR, `nowRefuted == refuted` → `false`, which removes a fixed-point loop's early `break`) was killed at B after 21.49 s, under a 25.60 s limit, by a wall-clock assertion in `ConstructionCostTests.swift:172`, a test outside the skip list. The full run of C timed it out at 24.07 s under a 24.04 s limit. Solo reruns timed out at C (after 70.5 s) and at B (after 64.3 s). It is a carried row, so it counts as staleness, not failure. The solo reruns ran under SwiftMutator's automatic limits of 70.52 s and 64.28 s, not the arbitrated runs' 25.60 s and 24.04 s, so they show the mutant hangs, not what the original limit would give.
- **SEI's one unequal tally**, `TypeShapeCollector.components(of:)` (8/8 lines at B, 7/8 in S_C, 8/8 again in the full run of C), is run-to-run coverage variation in the since scan's own coverage run; it is in no list.
- **A solo rerun** of a timeout (`Stride.swift:188:17`) was run on swift-algorithms only to show the procedure; it timed out after 40.1 s, as in every run.

**Side branches**, each from B:

| | swift-algorithms | SEI |
|---|---|---|
| T: the test comment alone | `e8c54ee7`, rc 0, 16.03 s. SwiftMutator: nothing to mutate, no results file. All 1,442 rows carried, `changedTest` set, the reason says so; `since` and `merge` pass | `f65e4754`, rc 0, 24.93 s. All 1,584 carried; both checks pass |
| U: an edit to a function no test runs, in a file with no tested mutant | `8b41404e`, rc 0, 26.59 s. **No existing file qualifies** (every one of the 28 production files holds a tested mutant), so U adds `Sources/Algorithms/Dormant.swift` with one function no test calls. No results file; the path `unlisted`, its function `notListed`, the results complete; `since` and `merge` pass | `577e9efb`, rc 0, 49.03 s. Fits the wording: `ImportCollector.swift`, whose 4 mutants are all not covered. No results file; `unlisted`, 2 functions `notListed`, not covered 171 → 167, complete. `merge` passed; `since` **failed s4** on the 2 dropped rows of `ImportVisitor.visit`, which had moved one line |

The SEI s4 failure was a checker gap: the design drops an unlisted path's rows on purpose, and s4 didn't leave such functions out. The checker was fixed after the runs. On copies of the SEI stores it now passes ("1 unchanged in unlisted paths, expected to hold no rows; 0 differences"), and it fails, as it should, on a copy with a row inserted into that file and on one with a killed verdict flipped to survived.

### 6. Determinism, carry, rebuild, clean trees, lint

**`report` twice.** Byte-identical in both formats, on S_B and S_C of both packages, and byte-equal to the reports of the earlier parts; the stores' hashes didn't change.

| | S_B Markdown | S_B JSON | S_C Markdown | S_C JSON |
|---|---|---|---|---|
| swift-algorithms | 32,809 B | 5,391,615 B | 34,071 B | 5,392,342 B |
| SEI | 41,987 B | 5,531,900 B | 43,462 B | 5,550,322 B |

**Carry.** A plain `scan` after `scan --coverage --mutation`, on a copy of each base store, carried both results. Every mutation table (1,442 and 1,584 mutant rows) and coverage table was row-for-row equal, and so were all 556 and 518 roll-up numbers. `swiftmutator` read `ran`, "carried from the scan of 2026-11-22T08:20:34.481Z" (swift-algorithms) and "… 2026-11-22T09:11:44.479Z" (SEI), with the identity, options and duration kept; no warnings. On SEI a plain scan into the default store after the resume carried too.

**Rebuild, then a plain scan.**
- Touching a SwiftStatsCore source and running `swift build -c release` recompiled the module but didn't relink the product, as in M5: the binary kept its inode, mtime and sha256. The scan after it carried, but proves nothing about a new build.
- A rebuild that does change the binary: in an APFS clone of the tree, `trend`'s help text was changed and the product rebuilt (sha256 `686103ea…5794` and `15d85392…704b`). Its plain scans carried with every table and roll-up equal, while the `swiftstats` collector's identity changed.
- As in M5, the carry compares commit, tree state, the `map:` rule and record and file hashes, never the SwiftStats binary, so this check shows only that the keys still match.

**Clean trees.** `git status --porcelain` printed nothing after every step on both packages, with an outside store and with the default store. `.swiftstats/stats.sqlite` is ignored by `.swiftstats/.gitignore:1:*`. At the end `--ignored` shows only `.build/`, `.swiftstats/` and `Package.resolved`. After every completed run `.swiftstats/mutation` held only `.lock`, `build-cache/`, `muter.conf.yml`, `runs/` and `swift-mutator.log`, with no `work/`, no `pending.json`, and no SwiftMutator side folders beside the package.

**Lint findings with an interrupted run's `work/` in place.** That `work/` held 114 and 116 `.swift` files outside `.build`. A `scan --no-store` with it present gave findings equal, entry for entry, to the first scan made before any `.swiftstats/` existed: 1,179 on swift-algorithms (SwiftLint 763, SwiftProjectLint 371, swiftstats 45) and 292 on SEI. None mentions `.swiftstats`. On SEI, SwiftLint finds nothing with the package's own config and is given only the target directories, so that half shows only that SwiftLint never reads `.swiftstats/`.

### 7. Interrupts, resume and the orphan (swift-algorithms; one SEI interrupt)

A harness started `swiftstats scan --mutation` as its own process-group leader, recorded every descendant of `swiftstats` and of SwiftMutator with its process group every second (`ps -axo pid,ppid,pgid,command`), sent the signal once the results file held at least 20 mutant lines, then checked every 0.25 s for up to 60 s that no recorded pid or member of a recorded group was alive, and watched 5 s more. A process living under a second can be missed.

| | SIGINT to the process group | SIGTERM to `swiftstats` | SIGKILL to `swiftstats` | SEI: SIGINT to the group |
|---|---|---|---|---|
| Mutant lines at the signal | 21 | 21 | 23 | 23 |
| `swiftstats` ended | by SIGINT, 0.38 s later | by SIGTERM, 0.40 s later | at once | by SIGINT, 0.06 s later |
| Processes recorded; alive afterwards | 233; none at the first check, at most about 0.41 s after the signal | 232; none, about 0.43 s | SwiftMutator orphaned (parent 1) with 13 recorded processes, by design; after SIGTERM to its pid, all 32 gone within about 0.48 s | 132; none, 0.03 s after `swiftstats` exited |
| Results file's last session | `interrupted` (`detail: SIGTERM`) | `interrupted` | `interrupted`, after the stop | `interrupted` |
| `pending.json` names the results file | **no** | **no** | **no** | **no** |
| `--resume` | rc 0, 2,554.88 s; key set equal to the base's (1,442), 0 verdict differences; checker passes | rc 0, 2,501.34 s; equal, 0 differences; checker passes | — | rc 0, 1,009.76 s; equal (1,584), 0 verdict and 0 outcome differences; checker passes |

- **A Ctrl-C reaches `swiftstats` alone.** SwiftMutator led its own process group in every run (Foundation's `Process` makes each child a group leader), so the group SIGINT reached only `swiftstats`, whose stop policy then sent SwiftMutator one SIGTERM. SwiftMutator's clean stop killed its descendants and wrote the end line. The design said the terminal's SIGINT also reached SwiftMutator through the group; that sentence was wrong and was corrected after the runs.
- **No SwiftMutator lock refused a resume.** Each resumed in its kept copy (swift-algorithms: "20 results still hold, so 1384 mutants are left to test"; SEI: "23 results still hold, so 1390 mutants are left to test") and stored 2 sessions, complete.
- **The forced kill.** With the orphan still running, the next `scan --mutation` refused the mutation step and left `work/` and `pending.json` untouched: "a SwiftMutator run an earlier scan started is still running in .swiftstats/mutation/work (process 19296); stop it, or wait for it to end, then scan again". It stored a snapshot carrying the base's results and exited 0. **The terminal showed none of this**: only "Stored a snapshot …" and the log path; the refusal and the pid were only in the scan JSON's warnings. After the orphan was stopped, the next `scan --mutation` warned "swiftmutator: discarding the interrupted run of 2026-11-22T13:06:15Z", got its build cache back from the copy (warm build 3.25 s, against 9.94 s cold), ran in full (rc 0, 2,496.88 s) and gave the base's key set.
- **That run's verdicts differed from the base's in one mutant**, `Permutations.swift:437:33` (ROR, `<`→`!=` in `.values.sorted(by: { $0.0 < $1.0 })`): it survived, though it was killed in the base run, both resumes, the full run of C and steps 04d and 05. A likely cause, not verified, is `Dictionary.values`' order under Swift's per-process hash seed. This is a killed→survived flip between two full runs at the same commit, which the decided `--since` pass bar would not excuse.

**Why `pending.json` named no file.** It is written with `resultsFile` null before SwiftMutator starts, and the step names the file only after `command.run` returns; on an interrupt, the signal handler stops SwiftMutator and `swiftstats` ends by the signal, so that never happens. Every resume still found the file through the fallback, the only results file in the only run folder of the copy's log folder, which a second run folder would defeat. This was the only sub-check of the design's interrupt procedure not met. It was fixed after the runs (below), and checked with the real SwiftMutator on a git copy of the Mutation fixture: after a SIGINT at 8 mutant lines, `pending.json` named `pkg_muter_logs/Nov 22, 2026 at 9:00 AM/results.jsonl`, no process was left, and `scan --mutation --resume` completed. It was not re-run on either done-when package.

## Times and performance

Release builds, this Mac, one run at a time. The swift-algorithms audit (files dated 07:56 to 08:04) overlapped the start of SEI's part 3, and possibly its first T0 runs, from 08:03:26.

| Run | swift-algorithms | SEI |
|---|---|---|
| `scan --no-store`, no coverage or mutation | 2.69 s | 3.63 s |
| Base `scan --coverage --mutation`, cold builds | **2,472.57 s** (SwiftMutator 2,441.175 s) | **1,049.31 s** (995.168 s) |
| `scan --coverage --mutation --since B` on C | 188.50 s | 105.42 s |
| Full `scan --coverage --mutation` of C | 2,536.66 s | 1,026.89 s |
| Since, test comment only; since, unlisted | 16.03 s; 26.59 s | 24.93 s; 49.03 s |
| Resumes of an interrupted run | 2,554.88 s, 2,501.34 s | 1,009.76 s |
| Full run after the forced kill | 2,496.88 s | — |
| Plain scan carrying coverage and mutation | 6.83 s, 6.61 s, 7.33 s | 7.25 s, 7.79 s, 8.84 s; 6.94 s on the default store |
| `report` on S_B, Markdown; JSON | 1.75 s, 1.19 s; 1.22 s, 1.23 s | 1.54 s, 1.13 s; 1.28 s, 1.12 s |
| `report` on S_C, Markdown; JSON | 1.46 s, 1.42 s; 1.45 s, 1.44 s | 1.42 s, 1.30 s; 1.36 s, 1.32 s |

**Performance against M5** (design §9 step 8). `Docs/m5-results.md` has no SEI figures, so the baseline is M5's final build (sha256 `5fb328dd…aba1`, sources equal to `383a2de`), measured here, alternating with M6's, in a separate clone of each package and with M6's config less `collectors.swiftmutator`.

| | swift-algorithms M5 | M6 | SEI M5 | M6 |
|---|---|---|---|---|
| T0 `scan --no-store`, median of 6 | 2.645 s | 2.65 s (2.65 s with its own config) | 3.415 s | 3.405 s (3.39 s) |
| Plain stored scan carrying coverage | 6.26 to 6.36 s | 6.22 to 6.46 s | median 7.19 s | median 7.23 s |
| `swiftstats` collector (parsing and hashing) | 322 to 325 ms | 322 to 325 ms | 301 to 311 ms | 301 to 315 ms |
| `report` Markdown, median of 5, each binary's own coverage-only snapshot | 1.05 s | 1.07 s (+1.9%) | 1.05 s | 1.05 s (+0.0%) |
| `report` JSON, same | 1.09 s | 1.10 s (+0.9%) | 1.09 s | 1.07 s (−1.8%) |
| `report` on S_B (coverage and mutation), against M5's coverage-only figure | | 1.09 s (+3.8%), 1.15 s (+5.5%) | | 1.18 s (+12.4%), 1.23 s (+12.8%) |

- **T0 is unchanged**: the medians differ by 0.005 s and 0.01 s, within run-to-run spreads of 0.14 s and about 0.25 s.
- **File hashing adds no measurable time.** Reading and hashing the scanned files takes 0.91 ms (56 files, 444,994 B) and 1.10 ms (57 files, 668,657 B) per pass, and every hash equals the scan's.
- **PRD §12 criterion 1** (swift-collections T0 under 30 s; M5 didn't re-measure it): a clone of the local SwiftPM mirror at `a807eb67`, 710 files and 7,236 records: M5 15.65 s and 14.31 s, M6 14.63 s and 14.31 s. It was measured with `scan --no-store` at `1.7.6-27-ga807eb67`, not at a named tag as the criterion asks.
- **The `report` bar** is "not more than 10% slower than M5's on the same snapshot". M5 can't open a v5 store ("written by a newer SwiftStats"), so the runs compared each binary on a snapshot of the same kind, its own coverage-only one, where M6 is within the bar on both packages. On a snapshot holding mutation results, which M5 can't produce, M6's `report` is 3.8% and 5.5% over M5's coverage-only figure on swift-algorithms and 12.4% and 12.8% on SEI. Met only under the same-kind reading.

## Decisions

Decided for M6 (the user, during planning):

- **The done-when packages are swift-algorithms and SEI**, SEI after a probe of its full-run cost (16.5 min with three wall-clock tests skipped, 92 min without).
- **`--since` merges**: SwiftMutator runs `--since <the base snapshot's commit>`, files with an unchanged hash keep the base's rows and changed files take the new run's. A merged snapshot has no score SwiftMutator computed; SwiftStats reports its formula over the merged rows, labelled.
- **The done-when's "only the changed functions' results" is read as changed files**, with the unchanged functions in changed files keeping their verdicts, checked per function on store rows.
- **Absolute thresholds**, configurable under `signals.<name>`: weak tests below 50%, genuinely under-tested below 20%, at least 3 scored mutants, uneven clone mutation 80/20 with at least 2 mutants per copy.
- **The research critic's recommendations U2 to U14**: the temporary copy and the config SwiftStats writes, the argument allowlist and `--skip-update-check`; SwiftMutator's coverage left on, results without `mutantsNotCovered` leaving out the low-score rule; suspect flags from `swift-mutator report -f json`; same-tree carries as `ran` and per-row provenance across commits; the ratio as context for weak tests and the module-against-project comparison for genuinely under-tested; the exit states; the version bumps; best target over all tiers; the clone signal's mutation part as its own signal; genuinely under-tested scored by unkilled mutants.
- **The score multiplies before dividing**, as SwiftMutator's source does.
- **The design's two open questions**: genuinely under-tested keeps the module comparison and gains an optional absolute `signals.genuinely-under-tested.ratio`, unset by default; the `--since` pass bar excuses only a killed↔timedOut flip that a solo rerun shows to be timing.

Decided during the reviews (by the fixers, within the design):

- **A full checkout, not a sparse one**, so a package's in-repository siblings are in the copy.
- **A changed manifest refuses a `--since` run** before it starts (refusal 6), rather than marking every file unresolved after it.
- **Refusals come before the run, and a run's results are kept until stored**: `pending.json` records them under `kept`, and `scan --mutation --resume` stores them without running SwiftMutator.
- **`diff` and `trend` compare only scores** on a side whose results leave files out, in every scope.
- **A report without `killingTestSummary` judged no suspects**: `suspectsJudged` is false, and the checker was changed to match.
- **Weak tests' suspects are matched by name only**, since stored killing tests carry no file; the contested finding was kept as intended and documented.
- **A full run that finds nothing to test stores an empty result**, which carries like any other and can't be a `--since` base.

Decided after the done-when runs (the fixes, below): a failed or refused requested run prints a warning on standard error and the exit status stays 0, as for a failed requested `--coverage` run. The fixer also gave coverage the same line, a small extension beyond the request.

Not decided: the ratio value 1.0 used for the ratio variant.

## Review

The design went through four critiques before the build (correctness, contract, testability, scope and signals). Of their 58 findings, 52 were accepted and 6 in part; none was rejected whole.

Each of the 17 implementation steps (01 to 08d, with 4d the checker) was reviewed as it was built. Fourteen reviews raised 45 findings (11 medium, 34 low); steps 01, 04a and 04c had none. All were fixed, except two parts the fixers rejected as departures from the design (step 02's switch of the recording script to `git archive`, and step 06's "skip HEAD" when naming a base) and one payload shape kept and written into the design (step 08b). Among the medium ones: the work copy's overlay diffed against HEAD rather than the scanned commit (03a); the standard stop policy signalled only a child's pid where M5 signalled its process group (03c); a resume overwrote its kept copy with a changed file, so SwiftMutator refused it for ever (03d); suspect tests de-duplicated by name (04b); the checker writing bytecode caches into `Scripts/` (04d); a resumed `--since` run that failed its guard staying resumable (06); configured limits printed rounded (08a); and an incomplete result's percent hidden in one column and shown in the next (08d). After step 08d, 777 tests in 165 suites passed (532 in 108 after M5).

The finished code then had an adversarial review across ten areas: the work copy and run, stopping and resuming, reading, mapping and figures, the store and `diff`, the `--since` merge, carrying and saving, signals and reports, tests and fixtures, and conformance to the design. A verifier reproduced each claim. 29 findings were confirmed (11 medium, 18 low, none high), 1 was contested and kept as intended, and none was refuted. Two pairs are the same defect (2/28, 22/26), so there were 27 distinct defects. They were fixed in five groups, each behaviour change with a regression test shown to fail with the fix undone. Findings are numbered as the code's comments cite them, from 0.

| # | Finding | Fix |
|---|---|---|
| 0 | (medium) The sparse checkout left out a package's in-repository siblings, so a `.package(path: "../Core")` package failed the warm build | A full detached checkout (objects still shared), with the rest of the repository's changes laid over it |
| 1 | LFS, git-crypt, skip-worktree and assume-unchanged differences in files the scan didn't parse slipped into the copy | Such files are found with `git ls-files` and byte-copied from the work tree, counted in "copy fixed n files" |
| 2, 28 | Production code kept only for tests (a `MutationExit.judge` overload, `ScratchRegistry.registered(_:)`) | Removed |
| 3 | (medium) After a SIGKILL of `swiftstats`, SwiftMutator kept running, and the next scan deleted its copy and started a second run on the same paths | SwiftMutator's own lock is probed first; a live one fails the step naming its pid and touches nothing. SIGQUIT joined the cleanup signals |
| 4, 16 | (medium) A save refusal decided only after a 17 to 44 minute run threw the results away, with no way to resume | Refusals the git state settles come before anything runs; held coverage is decided just before SwiftMutator starts; results are kept until stored, and `--resume` stores them |
| 5 | The report join wasn't one to one: a kill with no readable report entry was stored as judged "not suspect-only" | Such kills are null and counted in a warning |
| 6 | The checker expected `suspectsJudged` null for a report without a summary; the scan wrote false | The checker changed; the scan was right |
| 7 | No test pinned which header gives a multi-session file's resumable facts | Test only |
| 8 | NFC normalisation was a no-op on Swift strings, and its test couldn't fail | `NFCPath` compares by UTF-8 bytes; the case-fold warning also catches NFC/NFD pairs |
| 9 | (medium) `diff` and `trend` read the rows dropped for unlisted or unresolved files as improvements | Counts are left out on a side with gaps, with a warning; scores still compare; `trend` gives no value there |
| 10 | No test of `diff` refusing held results or `diff --drop-mutation` | Test only |
| 11 | An unreachable `MarkdownDiff` branch for a full run with carried mutants | Removed |
| 12 | (medium) A `Package.swift` change left unchanged files carried, though which files are compiled or mutated may differ | Refusal 6 before SwiftMutator starts, plus a merge guard for paths that stopped being production |
| 13 | (medium) A test file deleted since the base wasn't listed as changed | Marked `changedTest` and counted in the note |
| 14 | No test of a `--since` run onto a merged base | Test only; no bug found |
| 15 | (medium) A same-tree carry kept stale placement when the rescan had records the held results never mapped | The added-record check, and a refusal for a now-parsed file whose mutants weren't mapped |
| 17 | Genuinely under-tested's line-coverage tie-break untested | Test |
| 18 | Uneven clone mutation's de-duplication and tie-break untested | Tests |
| 19 | The ratio's equality edge and best target's self-partner filter untested | Tests |
| 20 | `MutationCopy.counts` stored and never read | Removed |
| 21 | (medium) `MutationInterruptTests` flaky in the full suite | The wait, lookup and stop run on one thread; the fake waits 600 s |
| 22, 26 | (medium) The `--since` settings guards (timeout, `.swift-version`, SDK environment, test executable) had no test that detects their removal | Tests |
| 23 | The "nothing on standard input" assertion couldn't fail | The fakes compare stdin's device with `/dev/null` |
| 24 | The single-module sentence untested with a ratio set | Test |
| 25 | The UTF-8 back-off in the last-character anchor untested | Test |
| 27 | A full run with nothing to test stored no mutation block | An empty result (full, complete, nothing listed) is stored and carried; refused as a `--since` base |
| contested | Weak tests' suspects are matched by name only, though SwiftMutator judges a suspect by name and file | Kept; documented, with a test that same-named suspects merge |

Each group's fix was then checked in turn. The checks found 6 more problems, all fixed:

| Group | Problem | Fix |
|---|---|---|
| Work copy and run | (medium) `MutationInterruptTests` still flaked, now at the registry lookup | The whole wait, lookup and stop on one thread |
| Work copy and run | The SIGQUIT end-to-end test wrote a macOS crash report on every run | The end-to-end test sends SIGTERM only; a test checks SIGQUIT is in the list. Ten earlier reports were left in `~/Library/Logs/DiagnosticReports` |
| Work copy and run | A nothing-tested result's Markdown said "changed since the base" and ended a line with "; ." | Files-only details for results no run made |
| Saving | The up-front held-coverage check had no test of its own | Test |
| Reading | `unreportedKills` couldn't fail: its recorded report had `suspectsChecked` false | The test sets it true |
| Signals | The suspect doc text said every same-named suspect is listed, though identical entries merge | Reworded; test |

After the review fixes, on the measured tree `0d16ddb5`: `swift build --build-tests` gives no warnings, `swift test` passes 817 tests in 174 suites (twice), and strict SwiftLint reports 0 violations.

**The done-when fixes**, after the runs, in tree `e9f24c5d`:

| # | Problem | Fix |
|---|---|---|
| 1 | (medium) `pending.json` didn't name the results file after an interrupt | SwiftMutator's run is started with work the interrupt does after the stop policy has stopped SwiftMutator and before `swiftstats` exits: it finds the results file as discovery does and rewrites `pending.json` naming it, or removes it when the file has no readable header. The waiting step stays blocked meanwhile, since the interrupt holds the registry lock. Tests: `MutationInterruptRecordTests` (named file used over a second run folder; record removed for an empty file), both failing with the fix undone. Checked on the Mutation fixture with the real SwiftMutator (§7) |
| 2 | (low) A failed or refused requested run was invisible on the terminal | After "Stored a snapshot …", standard error gets `Warning: swiftmutator: this scan's mutation run failed (<reason>)`, or the carry's own warning when held results were carried; coverage the same. Exit status stays 0. `UnrunNoticeTests` (3 tests); a CLI check with a fake `swift-mutator` that exits 64. Not re-checked against a real orphan |
| 3 | `mutation-check.py since` s4 didn't leave out functions in unlisted paths | They are expected to hold no rows. Passes on SEI's U stores; fails on two deliberately wrong stores |
| 4 | `coverage-check.py` 1d couldn't parse a local type's initializer whose return type names its own context | The member is everything before the first local type after it. 648 of 648 on a rerun of SEI's base scan |
| 5 | The design said a terminal Ctrl-C reaches SwiftMutator through the process group | Corrected: it reaches `swiftstats` alone, and the stop policy stops SwiftMutator |

On tree `e9f24c5d`: `swift build --build-tests` gives no warnings, `swift test` passes 822 tests in 176 suites (twice, 48.6 s and 49.2 s), and strict SwiftLint reports 0 violations.

## Known limits

- **The interrupt fix is checked only on the fixture.** The done-when runs used tree `0d16ddb5`, before it; no interrupt was re-run on swift-algorithms or SEI with the fixed build. A record left by a scan killed outright (SIGKILL) still names no file, and its resume relies on the log folder holding exactly one run folder with one results file.
- **SwiftMutator's verdicts depend on timing and order.** Its default per-mutant limit changes from run to run (28.69 s, 20 s and 30.57 s on swift-algorithms; 25.60 s, 20 s and 24.04 s on SEI), and refusal 5 compares only the recorded option (`timeout: default`), so a merge combines rows judged under different limits. Seen in the runs: SEI's one stale carried row (`ConstructionFacts.swift:180:37`, a kill by a wall-clock assertion racing the limit); step 08a's kill of `ConstructionCollector.swift:595:12` by a wall-clock test; swift-algorithms' `Permutations.swift:437:33` flipping killed→survived between two full runs of the same commit, which the decided pass bar would not excuse, so a `--since` check could fail on it alone; and 9 to 20 failed↔runtimeError outcome changes per rerun on swift-algorithms (0 or 1 on SEI). Stating options doesn't make runs repeatable.
- **The solo reruns** that arbitrate a flip ran under SwiftMutator's automatic limit for a single mutant (70.52 s and 64.28 s on SEI), far longer than the runs they arbitrate. Only staleness accounting relied on them.
- **Carried verdicts go stale** after test-only and callee changes: `--since` retests only changed production files. Changed test files are listed in the reason; a full `scan --mutation` now and then is the remedy.
- **Killing-test attribution is thin.** SwiftMutator stops a mutant's tests at the first failure, crash kills usually name no test (616 of swift-algorithms' 1,144 kills name none), and since runs judge no suspects, so a merge's fresh kills are unjudged (486 of 514 and 949 of 1,007 judged in S_C). Weak tests' suspects are matched by name only.
- **The suspect-only arm has no real evidence.** Neither package had a suspect-only kill or a suspect test (SEI's skip removes the flaky tests by design), so that arm of weak tests is exercised by fixture tests alone.
- **Genuinely under-tested is empty on a single-module package** unless `signals.genuinely-under-tested.ratio` is set, and both done-when packages have one module. The value 1.0 used in the runs was a choice; at 1.0 both modules count as low, and the list reduces to functions at most 20% covered with a score under 20%, here all code no test ran.
- **The signals' precision varies by package.** Weak tests on swift-algorithms is noise: `precondition` boundary survivors and timeouts that are hangs. Equivalent mutants appear on both packages. Best property target often suggests a property that wouldn't kill its mutants. Hand reads found 11 of 17 and 44 of 53 items worth attention.
- **No human read the lists.** The design asks for a human to read up to 20 items per list; the done-when runners and auditors who read them, and judged the precision figures above, were agents.
- **The `report` bar is met only under the "same kind of snapshot" reading**: on a snapshot holding mutation results, M6 is 12.4% and 12.8% over M5's coverage-only figure on SEI. M5 can't open a v5 store, so no same-snapshot comparison exists.
- **Timing splits came from an overwritten log.** The base and since runs' split of the mutation step into SwiftMutator, warm build and report rests on log lines later scans replaced; only their sum is in the store.
- **One side branch departed from its wording**: swift-algorithms has no file with no tested mutant, so its unlisted branch used a new file. SEI's met the wording.
- **Both checkers had gaps that the runs found** (`since` s4 on unlisted paths, `coverage-check.py` on local types' initializers). Both are fixed and re-checked on stored data, not by a fresh done-when pass.
- **A refused mutation step still exits 0**, as a failed `--coverage` run does; it now prints a warning. An orphaned warm build (`swift build`), as opposed to SwiftMutator, isn't detected.
- **The interrupt checks** ran on swift-algorithms (three signals) and once on SEI (SIGINT); the harness samples every second, so a process living under a second could be missed. Stopping SwiftMutator can take its full 35 s grace; here it took under half a second.
- **The copy leaves things out**: submodules, git-ignored non-Swift files a build needs, and checkout-changing local config such as `core.autocrlf`; outside git, a `.package(path:)` outside the package. `--resume` re-runs only the hash check, and its tree check covers only the package. In a repository that doesn't ignore `.build/`, every `--resume` is refused as "the tree has changed", because the first scan's `swift package describe` creates an untracked `.build/` after the git state is read (found in step 03d; real packages ignore it). Nested packages' manifests aren't checked by refusal 6.
- **No overall time limit** on a mutation run, and `runs/` is never pruned.
- **A resumed run's carried date** is when its first session started, inside the interrupted scan, not when the resume ran.
- **The carry never consults the SwiftStats build**, only the `map:` rule, as M5's coverage carry.
- **Coverage varies between runs**: SEI's since scan read 7/8 lines in a function the base and the full run read as 8/8. Weak-tests and genuinely-under-tested membership of carried functions holds only while their coverage holds.
- **`trend` doesn't mark merged points** (schema 1).
