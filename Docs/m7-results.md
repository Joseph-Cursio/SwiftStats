# M7 results

**Date:** 2026-11-25 · **Toolchain:** Apple Swift 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1, Xcode 27.2) for SwiftStats (its `.swift-version` names `xcode`), swift-algorithms and SEI (swiftly's default, `xcode`); SIP's `.swift-version` selects swift.org 6.4.1, so its T1 build, store and `libIndexStore.dylib` are 6.4.1's · **Machine:** Apple M3, 8 cores, macOS 27.2.1 · **Tools:** outskirts 3.28.0 (release build of `a1e5d6e1`, used in place, sha256 `742c60c4…4bc0`), indexstore-db's `IndexStore` product linked at `64aa0b2` (tag `swift-6.4.2-RELEASE`), SwiftLint 0.65.1, SwiftProjectLint `6477efac`, swift-infer `79908525`, swift-clone-detector `97eee1c`; SwiftMutator `b16642de` results carried from M6, not run · **SwiftStats:** release build of tree `638b071a`, the uncommitted M7 working tree over `fff063a`; `swiftstats` 0.0.1, 47,912,264 bytes, sha256 `9f72492d…7212`. The done-when fixes came after the runs, in tree `3428b623`, and changed only `Scripts/index-check.py` (below). Nothing is committed.

M7 scope (design v2, from PRD §11's M7 row): T1, SwiftStats' own debug build with the index store, type-check timings and compiler warnings; a USR on every record; the index side of coupling (module edges, cross-module fan-in, test referrers, USR type cycles, family references); dead code from outskirts; and three signals, hidden coupling, dead but tested and test-only production code. The gating packages are swift-algorithms at `5b7143f` and SwiftEffectInference (SEI) at `c8644fd`, scanned with copies of M6's stores; SwiftInferProperties (SIP) at `79908525` is a non-gating third package. The design is `m7-design-v2.md` with its "As built" notes, which override its first text; its §12 lists the PRD changes for v0.2.13, and `Docs/PRD.md` in this tree is v0.2.13 with them applied. The design isn't in the repository: it was kept outside it, with the implementation steps' notes and the done-when's logs. Bare § numbers below are the design's; the PRD's are written "PRD §".

## Done-when

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | Every record for code compiled in the build configuration gets a USR, re-derived by an independent checker reading the store through libIndexStore; the only accepted reasons for none are top-level code, an inactive `#if` branch and a plugin target | Met | swift-algorithms: 753 of 756, the 3 without in `RandomSample.swift:17, :24, :29` under `#if ALGORITHMS_DARWIN_ONLY`; 21 secondary accessor USRs; 225 of the 753 are `c:` USRs. SEI: 826 of 826. The checker's own join (u2) gives the same primary and secondary USR per record on both, and its reasons (u4) the same, with `target not built`, `file not indexed`, `file changed during the scan`, `disagreement` and `unexplained` 0. |
| 2 | Records without one are listed with the reason, none unexplained | Met | swift-algorithms' Markdown lists all 3 with `inactive #if branch` and prints "Every compiled record has a USR."; the JSON lists them too. SEI has none to list. u4 agrees on both. |
| 3 | Every case where USR and syntactic key disagree is listed, definitions with no record apart | Met | 0 of each kind on both; u5 equal. The Markdown prints "No USR and key disagree.", "Every definition the index read has a record." and "No key collision to separate." swift-algorithms declares no protocol, so it has no requirement either. |
| 4 | The dead-but-tested list is produced; an empty list counts when its funnel is printed and a fixture test shows rows | Met | Empty on both, with its funnel: "473 production functions = 0 production-dead + 473 used" and "336 production functions = 1 production-dead + 335 used; 1 = 0 listed + 1 with no mutant that ran". The checker's `signals` mode re-derives every item, score, order and funnel count of all three signals. The fixture tests (8 tests in 3 suites) pass; dead but tested lists `onlyTestsCall()` at `Sources/IndexCore/TestOnly.swift:7`. |
| 5 | `report` byte-identical twice, a plain rescan carries, trees clean, an interrupt leaves no process | Met | Byte-identical reports on both; a plain scan carries the three T1 collectors with coverage and mutation, rows equal, also with a SwiftStats rebuilt with a comment added; `git status --porcelain` empty after every step, with an outside store and with the default store. On SEI, SIGINT to the process group and SIGTERM to `swiftstats` each left no process 1.06 s and 1.08 s after the signal; no snapshot was written, and the next `scan --index` finished. |

Step 2 asked for 0 differences in every checker mode. That held on both gating packages, but only under the readings of design §4.1 that implementation step 5b chose, given to the checker as `--local-containers enclosing --requirements package`. Under §4.1 as it was written, the checker's default then, u7 fails: 231 of swift-algorithms' 756 records have other referrers, and family references are 6,554 against the scan's 438. The design had never recorded step 5b's readings; only its step notes did. After the done-when they were adopted rather than the code changed: §4.1 gained an As-built note, and the checker made them its defaults (part 2 below). No criterion turns on them: criteria 1 to 3 rest on u2, u4 and u5, and dead but tested reads no referrers. Neither of the other two signals, also empty, was re-run under the literal readings. Hidden coupling doesn't turn on them on the gating packages: swift-algorithms has no coupling pairs, and SEI's four pairs are all members of `ConstructionFacts`, while the audit's listing of SEI's differences under the literal readings (one direct family reference dropped, `BodyEffectInferrer.combine` to `BodyInference.Anchor.strongest`; 49 requirement references added, all to `ConstructionMemo.Slot.==`; two family-type references to `BodyInference.Anchor` dropped) has no reference between the two families of a pair, so their classes (1 referencing each other, 3 sharing a type) stand. For test-only it was only argued: witnesses are left out before references count.

Each package's runs were then audited independently. On each gating package's first scan the auditors re-ran every checker mode (`usr`, `build`, `dead`, `rows`, `signals` and u0) on copies of the stores; for the second scan they read the runners' checker logs, since step 7 had overwritten the build output `build` needs. SIP's auditor re-ran every mode but `dump` and u0, reading the runner's u0 logs instead. All three re-ran `report` (byte-identical to the runners'). Planted defects failed as they should on the gating packages: a changed or swapped USR (u2), a changed reason (u4, swift-algorithms), one reference more or a flipped witness (u7), one ms more (`build`), an emptied dead-code block or a dropped outskirts entry (`dead`) and a perturbed dump (u0, swift-algorithms). None was planted for `rows` or `signals`, or on SIP. The auditors re-timed nothing, so every time below rests on the runners' measurements. They confirmed the runners' figures and statuses but made four corrections: the runners had shown u7's rule difference as a printed "option wording" note when it was a substantive reading (all three audits); SIP's `dead` failure came from design §5.4 disagreeing with itself, not only with the code; SIP's second build swapped which of the macro target's two units per file was kept, which the runner's "identical to scan 1" left out; and SIP's "4,330 candidates" for test-only is the pool, the funnel's candidates being 2,757. Their corrections are folded into the sections below.

## What M7 adds

- **`scan --index`**, opt-in (also with `--no-store`, `--coverage` and `--mutation`), runs three collectors that fail and compare separately: **`build`** (the T1 build, type-check timings, compiler warnings), **`index`** (USRs, references, coupling; in process) and **`periphery`** (outskirts). Otherwise all three are skipped "not requested; scan --index runs it". `backfill` and `diff`'s scans of other revisions never run them; `scan --drop-index` and `diff --drop-index` replace a snapshot holding T1 results that can't be kept.
- **The T1 build** runs in its own persistent directory, `.swiftstats/index-build`, with the coverage collector's toolchain (the toolchain's own `swift`, so an interrupt reaches SwiftPM): `swift build --build-tests --build-system swiftbuild -c debug -v --no-color-diagnostics`, with `-index-include-locals`, `-debug-time-function-bodies`, `-debug-time-expression-type-checking` and `-debug-diagnostic-names`, each its own argument. Before each build the root package's intermediates are deleted, so every root file is re-timed and re-diagnosed while dependencies stay built. Its own `swift package describe` gives outskirts its manifest JSON and the C99-name-to-target map; every stored module is a target name. `Package.resolved` is put back, `.swiftstats/index.lock` keeps a second `scan --index` out, the scanned files are hashed again after the build, and a failed build names `swiftstats-build.stderr`, where Swift Build prints its errors, with the first 20 cleaned lines from the first error.
- **The index reader**: indexstore-db's `IndexStore` product, pinned by revision, the only file importing it being `Index/IndexStoreReader.swift`, behind the `IndexStoreSource` seam (so unit tests run the real traversal over recorded reader output). `Package.resolved` gains `indexstore-db` and `swift-lmdb` (branch `release/6.4.x`, resolved but never compiled). A unit filter classes every unit (`system`, `otherPackage`, `otherModule`, `stale`, `duplicate`, `variant`, `kept`), comparing real paths, and moves stale and other-module units out of the store before outskirts reads it.
- **USRs on records**: each non-implicit function-like definition goes to the innermost record holding its line and UTF-8 column, kind and subkind compatible (the `init` accessor read by its raw subkind 1016); a shorthand subscript's getter becomes the record's secondary accessor USR. A record without one gets the first reason that applies, and the scan lists disagreements (several USRs on a record, one USR on several), definitions with no record (protocol requirements, property and subscript requirements' accessors included) and key collisions the USR separates. XCTest's `@objc` methods keep their `c:` USRs.
- **Index coupling**: referrers per record by the container's target (same production target, other production targets, test targets), with a property's reads and writes routed to its accessors and a package-declared protocol's requirement counted for its witnesses; `witness`; module edges with reference and importing-file counts; package-declared types with fan-in; USR type cycles (Tarjan, edges between a type and its nested types left out); family references (`direct` or through a `requirement`) and family-type references.
- **Dead code via outskirts 3.28.0**, built from source by the user and set as `collectors.periphery.path`: two runs over SwiftStats' store, test targets as roots (`roots`) and with `--exclude-tests` (`production`), with `--retain-public-modules` (library-product targets and the targets they re-export with `@_exported import`), `--retain-codable-properties` and `--retain-equatable-properties`. Entries are classed (build, outside the root, test, unscanned, file changed, local, production), unused ones mapped to records (by USR, a property's accessors, every record a type owns in any file, an extension's range, else position), and dead lines summed over maximal covered units. `LineRatio` gains `deadLines`; `deadCodeExcluded` is true exactly when outskirts ran.
- **Type-check timings and compiler warnings**: per record, the sum of its function-body entries and its slowest expression, whole ms; attachments to types and files; `typecheck.*` roll-ups that leave out records nested in a body. Warnings become findings of tool `swiftc`, rule = diagnostic ID, category = group, macro expansions at their origin.
- **Three signals**, each with its rule and a funnel: `hidden-coupling` (pairs of production families changed together, with no static dependency; `signals.hidden-coupling.support` 3 and `.confidence` 50%), `dead-but-tested` (production-dead functions with a mutant that ran; left out without mutation results) and `test-only-production` (functions referenced only from test targets, leaving out library API, witnesses and overrides, `@objc`, entry points and deinitializers).
- **Store migration v6**: ten `function` columns and `indexScan`, `indexUnit`, `indexFile`, `usrDisagreement`, `moduleEdge`, `typeIndex`, `familyReference`, `familyTypeReference`, `couplingPair`, `buildScan`, `timingAttachment`, `deadScan`, `deadDeclaration`, `deadRecord`, `deadLines`; history's change-coupling pairs are now a table (`couplingPair`) as well as in the report blob. Scan JSON `schemaVersion: 9`, report 6, top 5, diff 4 (a `usr` match rule and `usr changed` facts); trend stays 1 with new metric names.
- **Carrying T1 results**: a rescan whose build didn't run carries the group when the commit, the tree, the rule strings, the records (full spans, families), the type records and every file hash still match; otherwise it refuses before writing, naming `scan --index` and `--drop-index`. Refusals the git state settles, and held coverage and mutation the scan won't collect, are decided before the build starts. `backfill` keeps T1 snapshots.
- **Configuration**: `collectors.build.enabled`, `collectors.index.enabled`, `collectors.periphery.{enabled, path}`, and the hidden-coupling limits.
- **Reports**: Markdown sections "Build and index" and "Dead code" and the three signal tables; `scan` prints a warning line when a requested build, index read or outskirts run failed or was skipped.
- **`Scripts/index-check.py`**, the independent checker (10,298 lines; modes `dump`, `build-lines`, `build`, `usr` with checks u1 to u8, `rows`, `dead`, `signals` and the optional `coverage-names`), with its own ctypes reader over `libIndexStore.dylib` and no SwiftStats code. The modes for steps 2a, 2b, 5a, 5b, 6a, 6b and 9a to 9c were written before that rule's first real run, by another agent than the rule's code; u8 (added at step 7a's review), `rows` (the gaps step), `coverage-names` (review C35) and step 3c's build-mode rule changes (its review fix) came after real scans; **`Scripts/record-index-fixture.sh`**; and the **Index fixture** (`Tests/Fixtures/Index` and `IndexDep`, every case recorded once) with the **Diff** fixture's before and after recordings.

## Results on the two packages

### Setup

Scratch clones in the session scratchpad (`m7-done/`), with `--store` and `--config` outside each package. Nothing was built or run in the owners' repositories. SwiftStats was cloned locally at the M7 tree (commit `08108532`, tree `638b071a`) and built for release: 236.58 s by SwiftPM's count, 245.5 s wall, no warnings, the new pins taken from SwiftPM's cache. outskirts was checked in place: commit `a1e5d6e1`, clean tree, sha256 `742c60c4…4bc0`, `outskirts version` 3.28.0. The packages are fresh detached clones: swift-algorithms `5b7143f8e2` and SEI `c8644fd19e` from M6's clones, SIP `7990852508` from M5's.

The stores are copies of M6's (swift-algorithms sha256 `69d17fd3…a459`, SEI `69d67df3…e7eb`; schema v5, one snapshot each, 1,442 and 1,584 mutants), each with a pristine copy. The configs are M6's with `collectors.periphery.path` added; SEI's keeps its three-test `--skip`. SIP's config is new and minimal (coverage's `swift`, build, index and periphery), so its SwiftProjectLint, swift-infer and clone-detector runs were skipped "not found on PATH". The other tools are the ones M6 used, their hashes equal to the identities in M6's stores. The checker ran as `python3 -I -B` with `TMPDIR` in the scratch folder.

swift-algorithms ran from 15:33 to 15:50 UTC and SEI alongside it, to about 15:53. The outskirts drafts part ran from about 15:35 to 15:54: a debug build of outskirts, its whole test suite (8:23), a self-scan and a 192 s release build. SIP ran from 15:55 to 16:12 with the others finished, and performance from 16:15 to 16:23 with nothing else running. The gating parts' times were measured while each other's builds and the drafts part's builds and tests ran, so they are indicative; step 9 re-measured alone.

### What each package gives

| | swift-algorithms `5b7143f` | SEI `c8644fd` | SIP `79908525` (non-gating) |
|---|---|---|---|
| Records; with a USR | 756; 753 | 826; 826 | 13,557; 13,556 |
| Secondary accessor USRs; `c:` USRs | 21; 225 | 0; 0 | 1; 0 |
| Units kept; other package; system; duplicate | 56; 14; 96; 0 | 57; 125; 63; 0 | 1,955; 534; 99; 3 |
| Stale, other-module and quarantined units | 0 | 0 | 0 |
| Occurrences read | 27,349 | 52,298 | 1,054,887 |
| Module edges | 2 | 5 | 79 (35 package, 44 dependency) |
| Production types; type cycles | 75; 0 | 73; 1 (5 types) | 1,143; 20 (the largest 11 types) |
| Family references; family-type references | 438; 727 | 456; 689 | 6,702; 12,454 |
| Records timed; attachments; total type-check ms (first build) | 753; 109; 2,545 | 826; 103; 3,966 | 13,557; 2,165; 140,802 |
| Function-body and expression entries (first build) | 2,219; 7,085 | 26,666; 76,450 | 86,629; 518,907 |
| Compiler warnings | 0 | 0 | 35 (10 more from dependencies dropped) |
| outskirts results, `roots`; `production` | 1 (a test-target parameter, dropped); 0 | 3; 3 | 16 (8 in test targets); 31 |
| Records dead; dead lines | 0; 0 | the property `firstBindingName`'s getter in both runs; 4 and 4 | roots run 1 record, production run 21; dead lines roots CLI 8, production CLI 120, Core 17, Templates 9 |
| Retained public modules | `Algorithms` | `SwiftEffectInference` | 6 library targets |

The type cycles are the first measurement under §4.3's rule. The research's three swift-algorithms cycles were all type-and-nested-type pairs, which the rule leaves out, so there are none; SEI's one cycle is the research's five types (`ConstructionChecker`, `ConstructionFacts`, `PurityInferrer`, `RawDeclaration`, `TypeShapeCollector`).

### 0. Carry from the M6 stores

A plain `scan` with the M7 build, on a copy of each M6 store, in the fresh clone: rc 0, 5.79 s and 5.0 s. The store migrated to v6 and coverage and `swiftmutator` read `ran`, "carried from the scan of 2026-11-22T08:19:58Z" and "…08:20:34.481Z" (SEI: "…09:10:31Z" and "…09:11:44.479Z"). The design probe's `cmp.py` found `mutant` (1,442 and 1,584 rows), `functionCoverage`, `coverageLine`, `coverageRun`, `mutationRun`, `mutationFile`, `mutationScan`, `mutationSuspect`, `coverageAttachment`, `coverageUnmapped`, `finding` (1,179 and 292) and `propertyCandidate` equal; `function` differed only by v6's ten appended columns, null on every row, with its 36 M6 columns equal on all 756 and 826 rows. The pristine copies' hashes didn't change, and no refusal stopped the step.

### 1. T1 scans

`scan --index`, history read, coverage and mutation carried, into each store:

| | swift-algorithms | SEI |
|---|---|---|
| Whole scan | **24.80 s** | **35.63 s** |
| `build` collector (first build, dependencies included) | 16,619 ms (SwiftPM "Build complete! (12.82 sec)", swift-numerics compiled too) | 27,599 ms (SwiftPM 22.04 s, swift-syntax 603.0.2 compiled too) |
| `index` collector | 178 ms | 225 ms |
| `periphery` collector (both runs) | 1,015 ms (roots ≈0.45 s, production ≈0.38 s, from file times) | 765 ms |
| `<scratch>` size | 150,320 KB | 538,516 KB |

- **outskirts' label** reads `git:a1e5d6e1eaeeda3be492f1a24f7e45aa57039345 (3.28.0)` on all three packages, as the setup expected; `BinaryIdentity` didn't withhold it.
- **The scan's warnings were empty** on both; every collector ran except dependencies (not resolved).
- **The scans leave a `.build/` in the package root** holding only `.lock`, `CACHEDIR.TAG` and `.buildSystem_debug`. SEI's was born during step 0's plain scan, so a T0 collector's SwiftPM call makes it, not the T1 build. All three packages ignore `.build/`, so `git status` stays empty.

### 2. The independent checker

| Mode | swift-algorithms | SEI |
|---|---|---|
| u0 `IndexStoreReaderLiveTests` against the checker's `dump` | 0 differences: 166 units (96 system), 70 dumped, 69 records, 29,072 occurrences | 0 differences: 245 units (63 system), 182 dumped, 178 records, 310,805 occurrences |
| u1 unit set and quarantine | 56 units equal; quarantine 0 = 0 | 57 equal; 0 = 0 |
| u2 primary and secondary USR per record | 753 / 753 and 21 / 21 | 826 / 826 and 0 / 0 |
| u3 definitions on their name token | 774 | 826 |
| u4 reasons | inactive `#if` 3; the five fault reasons 0 | all 0 |
| u5 disagreements, no-record, collisions | 0 / 0 / 0 | 0 / 0 / 0 |
| u6 `swift demangle` against the key | 549 checked, 225 `c:` skipped | 826 checked |
| u7 referrers, witness, edges, types, cycles, family references | 756 records 0 differ; edges 2/2; types 75/75; family references 438/438; family-type 727/727 | 826 records 0 differ; edges 5/5; types 73/73; 456/456; 689/689 |
| u8 and `rows` (every M7 row against the scan JSON) | PASS | PASS (35 ok) |
| `build` (every `ms\t` and `warning:` line accounted for, by its own patterns) | stderr 9,347 lines, 9,304 = 9,304 entries, 3 of 3 warning lines (the manifest-command lines), stdout 762 lines, 0 left over; 753/753 records; 2,545 = 2,545 ms | stderr 103,201 and stdout 1,732 lines, 0 left over; 3 of 3; 3,966 = 3,966 ms |
| `dead` (runs outskirts itself from §5.2's words) | own runs 0.49 s and 0.40 s; 1 and 0 results equal to the kept files; `deadRecord` 0/0 | own runs 0.58 s and 0.30 s; 3 and 3 equal; `deadRecord` 1/1 per run; dead lines 4/4 |
| `signals` | PASS, 0 items in all three | PASS (34 ok) |

- **u0's variable** takes the dump's path alone (the dump names its store and library), not `<out>:<dump.json>` as §11 wrote it; it was run that way.
- **What the checker trusts** is listed in each mode's header: the scan JSON's record ranges, M3's `couplingPair` rows, and for `rows` and u8 the scan JSON as the truth for the store.

**The §4.1 readings.** Step 5b wrote two readings of §4.1 into SwiftStats and into its `references:` rule string, and its notes called both deviations from §4.1's text: a local named as a reference's container is followed up its `childOf` chain to the enclosing declaration (as written, a non-record container was kept as its own USR), and only requirements of protocols the package declares count for their witnesses (as written, every protocol requirement did). It ran u7 with matching flags and noted that u7's pass then shows agreement with the checker's readings, not a derivation from the design. The runners passed the same flags. The checker printed "`references:` differs from design 4's text (a deviation the step should explain)", and the runners listed that as a wording note. The audits ran u7 under the design's text, then the checker's default:

| §4.1 as written (`--local-containers symbol --requirements protocol`) | Records whose referrers differ | Family references (the scan's) | Family-type references (the scan's) |
|---|---|---|---|
| swift-algorithms | 231 of 756 | 6,554 (438), 6,116 of them via requirement, from 1,282 references to 47 requirements of protocols the package doesn't declare | — |
| SEI | 405 of 826 | 504 (456) | 687 (689) |
| SIP | 7,384 of 13,557 | 7,636 (6,702) | 12,316 (12,454) |

On swift-algorithms each reading alone fails too: the local one moves 12 records, the requirement one 229, with 7,180 family references. Production types also differ on swift-algorithms and SIP. On SIP, 4,851 of the 5,048 references to requirements went to 7 requirements of protocols the package doesn't declare.

The audits found no As-built note adopting either reading; the choice was recorded only in step 5b's notes. The decision afterwards was to adopt the readings, not to change the code: §4.1 gained an "As built (step 5b, adopted at the done-when)" note giving both readings, why (a local's USR is never a record, so references inside it vanished from family references; expanding `Equatable.==` made every comparison in the package a reference to every package witness), these figures, and the as-built rule string. The checker now defaults to `enclosing` and `package` and calls the literal options "design 4.1's original text"; its rule-text line no longer fires under the defaults. An independent check of that fix found the note narrower than the code (`ReferenceResolver.container(of:)` follows a local whichever relation names it, `baseOf` and `extendedBy` included, and keeps a local with no `childOf`); the note was reworded, and SwiftStats' shorter rule string was kept as built.

**Re-runs after the fix**, on store copies, with the checker's defaults: swift-algorithms and SEI pass `usr`, `build`, `dead`, `signals` and `rows` on scan 1 (swift-algorithms 83, 37, 68, 35 and 35 checks ok) and `usr`, `dead`, `signals` and `rows` on scan 2. `build` couldn't be re-run on either package's scan 2: step 7's `scan --coverage --index` overwrote step 4's build output, and no copy was kept. With both readings literal the checker fails on swift-algorithms exactly as the audit's run did.

**Printed, not failed.** `usr` notes design gaps: on SEI, 3 type identities `(module, typePath, typeFile)` each naming several local types of one name in different functions (`Finder` ×3 in production; `Collector` ×4 and `Finder` ×16 in tests), the open gap step 5b's review raised (below). `dead` still prints that its `classes:` and `map:` texts differ from the design's, a wording difference the fix left. The store's nullability of `indexFile.sha256` and `typeIndex.usr` differs from §9.1's text.

### 3. The four criteria

1. **USRs.** swift-algorithms' Markdown: `| production | 470 of 473 | 21 | 0 |` and `| tests | 283 of 283 | 0 | 225 |`, "Records without a USR: 3 (3 inactive #if branch)". The three are `Double`'s `root(_:_:)`, `log(_:)` and `log(onePlus:)`, inside `#if ALGORITHMS_DARWIN_ONLY` (`RandomSample.swift:13`), a flag the manifest never defines. SEI: 336 of 336 and 490 of 490. The roll-ups' fault reasons are 0 on both.
2. **Listed with the reason.** All 3 on swift-algorithms, in the Markdown (at most 50) and the JSON; none on SEI.
3. **Disagreements.** None of any kind on either; the Markdown says so in three lines.
4. **Dead but tested, and the other two signals**, all empty on both packages with their funnels, as §8 expected:

| | swift-algorithms | SEI |
|---|---|---|
| Dead but tested | 473 production functions = 0 production-dead + 473 used | 336 = 1 production-dead + 335 used; 1 = 0 listed + 1 with no mutant that ran (only not covered: `firstBindingName`'s getter); 3 unused production declarations = 1 property with accessor records + 2 others |
| Test-only production code | 473 = 3 without a USR + 470; 470 = 299 public API of a library product + 34 witnesses or overrides + 137 candidates; 137 = 0 listed + 133 with a production reference + 4 with none | 336 = 0 + 336; 336 = 98 public API + 41 witnesses or overrides + 197 candidates; 197 = 0 listed + 190 + 7 |
| Hidden coupling | 0 pairs (0 of 128 commits in the window) | 4 pairs, all production: 1 referencing each other + 3 sharing or nesting a type; 0 listed |

§8.2 expected SEI to add only the unused property `components` and no production-dead function. On this tree `components` is retained (`--retain-equatable-properties`), and the unused property is `firstBindingName` (`Internal/SyntaxHelpers.swift:40`), a computed one. By step 9b's reading, which §5.4's `property` rule gives, its getter record is a production-dead function: the funnel's 1. No mutant ran on it, so nothing is listed. `index-check.py signals` re-derived every item, score, order and funnel count of all three signals. On the Index fixture, `swift test --filter 'DeadButTestedFixtureTests|TestOnlyFixtureTests|HiddenCouplingFixtureTests'` passed 8 tests in 3 suites in 9.59 s: dead but tested lists `onlyTestsCall()`, test-only lists 3 (a setter only a test writes, `onlyTestsCall()` and `index-support`'s `parseLine(_:)`), hidden coupling lists `formatLine` with `parseLine`.

### 4. Second T1 scan

| | swift-algorithms | SEI |
|---|---|---|
| Whole scan | 11.52 s | 14.40 s |
| `build` (root package only) | 4,787 ms (SwiftPM 3.39 s; 32 `Compiling` lines against 116) | 7,650 ms (SwiftPM 5.11 s) |
| `index`; `periphery` | 102 ms; 691 ms | 214 ms; 762 ms |
| Timing locations against scan 1 | root function entries 1,926 (1,187 distinct) and expression entries 6,625 (3,948 distinct), equal as multisets; 753 records and 109 attachments, the same sets | 14,570 = 14,570 locations outside the build directory; 826 records and 103 attachments equal |
| Checker modes | every mode PASS, u0 0 differences | every mode PASS, u0 0 differences |

The totals differ only by the dependency entries a root-only rebuild doesn't repeat (swift-algorithms' build-directory entries 662 → 21; SEI's swift-syntax locations 60,187 → 21) and by timing noise (swift-algorithms' total 2,545 → 2,418 ms). The manifest-command lines (3 → 0) appear only when manifests compile.

### 5. Determinism, carry, rebuild, clean trees, lint

**`report` twice**, on each store after step 4, byte-identical in both formats, the store's hash unchanged: swift-algorithms JSON `c666e879…090ca` (6,276,450 B) and Markdown `165c0cf4…a0e9` (45,716 B); SEI JSON `21047bef…0462` (6,677,420 B) and Markdown `0385e718…66bb` (56,473 B). The auditors' runs gave the same hashes 40 minutes later.

**Carry.** A plain `scan` after `scan --index`, in 4.84 s and 4.39 s: `build`, `index` and `periphery` read "carried from the scan of 2026-11-25T15:40:56Z" (SEI: "…15:40:29Z"), coverage and `swiftmutator` carried too, and every row table was equal (all the M7 tables, `function`'s 46 columns, 650 and 612 roll-up rows, the mutants), apart from the snapshot date, the report blob and the reasons and durations in `collectorRun`. The checker's `rows` passed on the carried snapshots.

**Rebuild, then a plain scan.** A clone of the M7 tree with one comment line added to `Model/LineRatio.swift`, built for release (258.40 s by SwiftPM's count, 318.3 s wall, while the other parts ran; sha256 `2202f8c3…b760`). Its plain scans carried all five on both packages with every table equal; only the `swiftstats` collector's identity (`inputs:0aeaa68e…` → `inputs:06ae4be6…`, label `git:08108532…+dirty`) and durations changed. As in M5 and M6, the carry compares the rule strings, records and files, never the SwiftStats binary.

**Clean trees.** `git status --porcelain` printed nothing after every step on both packages with the outside store, and in a second clone of each with the default store (`scan --index` in 22.51 s and 36.2 s, a plain scan carrying, `report`); `--ignored` shows only `.build/` and `.swiftstats/`, whose `.gitignore` holds `*`.

**Lint findings with `<scratch>` populated.** swift-algorithms' `.swiftstats/` held 39 `.swift` files (swift-numerics' checkout among them); every scan JSON had 1,179 findings (SwiftLint 763, SwiftProjectLint 371, swiftstats 45), none under `.swiftstats/` or `.build/`. SEI's 292 SwiftProjectLint findings had none either; SwiftLint finds nothing on SEI with its own config, so that half shows only that SwiftLint never reads `.swiftstats/`.

### 6. Interrupt (SEI)

A harness started `scan --index` as its own process group with `.swiftstats/index-build` removed, recorded the descendants with `ps -axo pid,ppid,pgid,command` every second, and sent the signal 5 s after `swift-build` appeared.

| | SIGINT to the process group | SIGTERM to `swiftstats` |
|---|---|---|
| Alive at the signal | `swift-build` only | 7: `swift-build`, 5 `swift-frontend`s (each its own process group) and a zombie |
| `swiftstats` ended | by SIGINT, 1.01 s later | by SIGTERM, 1.01 s later |
| Descendants alive afterwards | 0 at +1.06 s, still 0 at +4.2 s (19 seen in all) | 0 at +1.08 s (19 seen) |

After both tries the store's hash was unchanged (`65be1eb1…325c`), no snapshot or scan JSON was written, `Package.resolved` was absent before and after (SEI's `.gitignore` lists it), and `git status` was empty. The next `scan --index` finished in 26.89 s (build 18,918 ms) with no lock refusing it, though stale `.lock` files were left, and every checker mode passed on it. The auditor noted that the SIGINT try caught the build before any compiler process had started. Each fresh build after removing the directory ran SwiftPM's own fetch of swift-syntax from GitHub.

### 7. The llvm-cov USR join (optional, non-gating)

`scan --coverage --index` on a further copy of each M6 store (27.63 s and 46.7 s), then `index-check.py coverage-names`, which looks for an export function named `$s` + each `s:` USR whose first region lies inside its record.

| | swift-algorithms | SEI |
|---|---|---|
| At the done-when | 455 of 528 agree (434 by USR, 21 by `usrAccessor`); 73 exceptions, all explained (72 initializers whose export holds only the allocating `fC` entry, which agrees; 1 subscript with explicit `_read`/`set`, `TestUtilities.swift:65`); exit 1, as the mode then exited whenever an exception remained | 805 of 826 agree; 21 exceptions: 20 initializers (`fC`, explained) and 1 that no rule explained; exit 1 |
| After the fix | 527 of 528 agree (434 by USR, 21 by `usrAccessor`, 72 by `fC`); 1 explained exception (the subscript); exit 0 | 825 of 826 agree (805 by USR, 20 by `fC`); 1 explained exception; exit 0 |

225 `c:` USRs were skipped on swift-algorithms. SEI's unexplained record was `EffectSymbolTable.runInferencePass(…, deadline: ContinuousClock.Instant, …)` (`EffectSymbolTable.swift:327`). Its USR names the type `_Concurrency.ContinuousClock.Instant`, by the module that declares it in source; the export's symbol, whose first region 333:7–376:6 lies inside the record, names `Swift.ContinuousClock.Instant`, the ABI module `@_originallyDefinedIn` gives. So §3.7's premise, that a record's symbol is `$s` + its USR, fails for any signature mentioning such a re-homed type. SwiftStats doesn't use this join, so nothing in the scan changed. The fix counts an initializer agreeing through `fC` as an agreement, adds a third explained kind (the USR's and a candidate's `swift demangle --tree-only` trees equal once module names are set aside), and exits 0 when only explained exceptions remain (1 for an unexplained one, 2 for carried input). Planted faults still fail: `Instant` changed to `Instent` in that USR (exit 1), one initializer's range shrunk to its first character (exit 1), and the carried `scan-1.json` (exit 2).

### 8. SIP, non-gating

`swiftly use` in the clone selected Swift 6.4.1 through its `.swift-version`. Two `scan --index` runs into a new store, history on.

| | Scan 1 (first build) | Scan 2 (root-only rebuild) | Expected (design probes) |
|---|---|---|---|
| Whole scan | 196.23 s | 133.63 s | — |
| `build` | 122,800 ms (SwiftPM 112.39 s; 2,999 compile lines) | 93,291 ms (SwiftPM 90.88 s; 2,104) | ≈132 s (144 s real); ≈111 s |
| `index` | 5,046 ms | 4,991 ms | — |
| outskirts `roots`; `production` | ≈6.00 s; ≈1.60 s (collector 7,840 ms) | ≈5.99 s; ≈1.58 s | ≈6.8 s; 1.75 s |
| `<scratch>` | 2,781,500 KB | 2,749,416 KB | ≈2.7 GB |
| T0 collectors before the build | 46.70 s (SwiftLint 36,475 ms, cold cache) | 15.32 s | — |

- **USRs**: 13,556 of 13,557; the one without is `soundness-probe`'s top-level code (`main.swift:117`), an accepted reason. 1 secondary accessor USR (`Probe.Run`'s subscript in `SwiftInferCoreTests`), 0 `c:`, 20 definitions with no record, all protocol requirements, 0 disagreements and collisions.
- **`SwiftInferMacroImpl`'s three files** each have two units with the same triple, `arm64-apple-macos26.0`, so they are `duplicate`, not `variant`. Scan 2 swapped which unit of each pair was kept: all six unit files carried the same modification time after the second build. SwiftStats and the checker agree within each scan and the records are the same, but the choice isn't stable across builds, so `usr` run on scan 1's JSON against the store as scan 2 left it fails u1, and only u1.
- **outskirts**: the `roots` run gave 16 results, 8 in test targets, among them the 2 unused locals (`peer`, `InteractionBridgeWriterTests.swift:81` and `:137`), classed `test`; the `production` run gave 31 (CLI 17, Templates 7, Core 5, MacroImpl 2), as the probe found.
- **Module edges** against the manifest, transcribed by hand: the 35 package edges equal the 36 declared target dependencies less `SwiftInferMacro → SwiftInferMacroImpl`, which the manifest declares and the code names only in `#externalMacro` (`CheckProperty.swift:84`), as expected. Dependency edges are imports, so they differ from declared products: `SwiftInferMacroImpl → PropertyLawCore` is declared but never imported, and 17 imports reach modules only transitively available.
- **Checker**: `usr` (83 checks ok; u7 references 732,568, edges 79/79, types 1,143, cycles 20, family references 6,702 of which 231 via requirement), `build` (606,864 stderr lines, 605,536 entries, 129 of 129 warning lines, 140,802 ms, 35 of 35 warnings), `rows`, `signals` and u0 (2,591 units, 2,483 records, 1,446,128 occurrences, 0 differences) passed on both scans. u6 passes because of a review fix: keys keep the source's spelling of `extension [OracleDiscoverBead]`, and the checker now reads `[T]` as `Array` before comparing with the demangled USR.

**`dead` and design §5.4.** `dead` failed on both scans: `deadRecord` rows 11 against the scan's 1 in the `roots` run and 31 against 21 in `production`, against the scan JSON and the store; everything else (outskirts' outputs, classes, dead lines, roll-ups) agreed. The 10 extra rows are `CheckPropertyMacro`'s records under outskirts' two `redundantPublicAccessibility` entries (`public struct CheckPropertyMacro` at `CheckPropertyMacro.swift:13`, by the type rule all 10 of its function records, and `expansion(of:providingPeersOf:in:)` at `:15`, by USR one of them). SwiftStats maps only entries with hint `unused` (`DeadCodeRules.cover(of:)`); the checker followed §5.4's body sentence, "for each `production` entry". The audit pointed out that §5.4 disagreed with itself: its own `map:` rule string begins "outermost unused declarations". swift-algorithms and SEI have no production entry of another hint, so SIP was the first package where it mattered. Step 6b had already recorded the `unused`-only mapping as a deviation in its notes and run the checker on SIP with `--map-hints unused`; the done-when's runner ran it without the flag. The as-built reading was adopted: §5.4's body now says "each `production` entry with hint `unused`", an As-built note explains that a `redundantPublicAccessibility` entry is about a used declaration's access level, not dead code, and the checker's `--map-hints` now defaults to `unused` (`all` is "design 5.4's original body text"). With it, `dead` passes on both scans (134 checks ok); with `all` it fails as before. Deadness, dead lines, roll-ups and signal inputs never differed.

**The lists, read.** The runner, an agent as in M6, read each item and the code and judged it worth attention or not, with no bar; the auditor spot-checked the notes. Dead but tested was left out ("needs swiftmutator: skipped, not requested"): step 8 makes no mutation run.

*Hidden coupling*: 136 pairs = 20 with a test or helper family + 116 production; 116 = 20 referencing each other + 0 through a protocol + 79 sharing or nesting a type + 9 referencing the other's type + 8 without a static dependency; 8 = 7 listed + 1 below the limits (396 of 1,512 commits in the 90-day window). The prototype's "about 12" became 8 under this rule.

| # | Family ~ partner (support; changes; confidence) | Worth attention? | Note |
|---|---|---|---|
| 1 | `InteractiveTriage.valueLawStub` (CLI) ~ `TemplateRegistry.collectValueLawSuggestions` (Templates) (5; 6/5; 100%) | Yes | The value-law templates and the CLI's stub writer change in lockstep with no shared type: one law catalogue known in two modules |
| 2 | `Evidence.init` ~ `FunctionSummary.init` (Core) (3; 5/4; 75%) | Yes | `Evidence` copies `FunctionSummary`'s fields on purpose ("decoupled from the parsing", `Evidence.swift:107`), so each new field lands in both |
| 3 | `FunctionScanner.scanCorpus(directory:)` (Core) ~ `DiscoverArtifacts.init` (Templates) (3; 5/4; 75%) | Somewhat | Pipeline plumbing; a shared carrier type would make it one edit |
| 4 | `FunctionScanner.scanCorpus(source:file:)` ~ `DiscoverArtifacts.init` (3; 4/4; 75%) | No | #3 through the other overload |
| 5 | `InteractiveTriage.totalityStub` (CLI) ~ `collectValueLawSuggestions` (3; 17/5; 60%) | Yes | #1's coupling again |
| 6 | `Evidence.init` ~ `FunctionScannerVisitor.makeSummary` (Core) (3; 5/5; 60%) | Yes | #2's lockstep again |
| 7 | `SwiftInferCommand.Discover.makePipelineResult` (CLI) ~ `FunctionScannerVisitor.makeTypeDecl` (Core) (3; 10/6; 50%) | No | A field threaded from the scanner to the pipeline result, at the confidence floor |

4 of 7 worth attention, two findings in all (the law catalogue; `Evidence` mirroring `FunctionSummary`).

*Test-only production code*: 4,330 production functions = 1 without a USR + 4,329; 4,329 = 1,349 public API of a library product + 222 witnesses or overrides + 1 entry point (`SwiftInferEntry.main()`) + 2,757 candidates; 2,757 = 19 listed + 2,726 with a production reference + 12 with none. All 19 are production-dead in outskirts' production run too (19 of its 21 dead records). Yes: `DiscoverInteraction.runPipeline(target:…)` (25 test referrers; the CLI takes `run(...)` instead), `VerifyInteractionSurvey.run(target:…)` (17; the single-target wrapper the CLI doesn't call), `Query.renderEntries(_:totalMatched:)` (6; legacy output kept alive by its tests), `TemplateRegistry.namesForDiagnostic(_:cap:)` (4; the diagnostic it caps is gone) and `CensusRun.zeroRowTemplates(against:)` (1; documented as "the answer this artifact exists for", called by nothing). Somewhat: 4 (`CensusRun.read(from:)`, `MemberBlockInspector.initializers(in:)`, `RenderShape.inverseExpression(context:)`, `NotApplied.reachSide(…)`). No: 10 documented test seams and counters (`runProcessForTesting`, `applyDomainInferenceForTesting`, `SyntaxCorpusSource.init(corpus:…)`, the curated recipe tables and similar). 5 of 19 worth attention, 4 more somewhat; the prototype expected about 20.

*Type cycles*: 20 over 1,143 production types and 3,801 edges; u7 computes the same 20. Yes: the 11-type knot around `InteractiveTriage`'s stub writing; `ReplayReport`, `StrategistDispatchEmitter`, `SwiftInferCommand.Verify` and `VerifyEvidenceRecorder` (a command type in a cycle with its emitters); `DocstringAdvisoryRenderer` ↔ `SwiftInferCommand.Discover` (the renderer takes `Discover.DocstringAdviceItem`, `DocstringAdvisoryRenderer.swift:15`); `AssociativityTemplate` ↔ `CommutativityTemplate` (a shared verb list in one of them, `AssociativityTemplate+Signals.swift:13`). Somewhat: 7 pairs and small groups that call each other both ways. No: 9 (a type and its private visitor, a spec and its emitter, two stages of one lifter). 4 of 20 worth attention, 7 somewhat.

### 9. Performance

- **T0 unchanged** (PRD §12 criterion 1): `scan --no-store` of swift-collections at `a807eb67` (`1.7.6-27-ga807eb67`, M6's clone; 710 files, 7,236 records), alternating builds: M7 15.597, 14.192, 14.284 s (median 14.284 s), M6 14.186, 14.292, 14.233 s (median 14.233 s), +0.4%, within the spread. Under 30 s. M7's lists the three T1 collectors as skipped "not requested". As in M6, measured at a describe, not a named tag.
- **`report` on a T1 snapshot**, against the same snapshot without T1, bar +10%: swift-algorithms Markdown 1.088 s against 1.057 s (+2.9%), JSON 1.137 against 1.084 s (+4.9%); SEI Markdown 1.102 against 1.069 s (+3.1%), JSON 1.125 against 1.103 s (+2.0%); medians of 5, alternating, each set of outputs byte-identical. Met. `scan --drop-index` can't make a snapshot without T1 of an unchanged tree (it drops only results that can't be kept), so the comparison snapshot came from a plain M7 scan onto the pristine M6 store, and every table not holding T1 results was checked equal to the T1 snapshot's.
- **T1 times** were recorded per package (below); the step has no bar.

### The outskirts drafts

A read-only `gh api` found **3.28.1**, published 2026-11-25T13:51:47Z, newer than 3.28.0 (2026-11-23); its notes list one fix, #434, a redundant-public false positive for public members of an extension declared in another module than its type. As the design asks, the PR's branch was rebased onto 3.28.1 (`0da160ab`) in scratch: no conflicts, `range-diff` marks both commits equal, and the code the drafts cite is unchanged between the tags.

| Check on the rebased branch | Result |
|---|---|
| Debug build with tests | 32.08 s, the same 24 upstream warnings as before |
| Filtered suite | 48 tests, 0 failures (2:55.7) |
| Whole `OutskirtsTests` target | 1,132 tests, 0 failures (8:23); 3.28.1's new test is in `AccessibilityTests`, so the count didn't change |
| Self-scan, `--strict` | "No unused code detected", 35.4 s |
| Regressions, 3.28.0 / 3.28.1 / branch | fixture 20 / 20 / 19 (the one removal is the `@Test` parameter at `IndirectMore.swift:11:28`), SEI 90 / 90 / 90, swift-algorithms 13 / 13 / 13 |
| Issue's reproducer | 3.28.0, 3.28.1 and the branch each report only `NoLibType.swift:2:1`'s unused import; with the three `@testable` imports removed it still builds and its 3 tests pass |
| PR's reproducer | 3.28.0 and 3.28.1 report both unused parameters, with and without `--disable-unused-import-analysis`; the branch reports none, and `--explain` shows all three retained by `SwiftTestingRetainer` |

Five version lines moved from 3.28.0 to 3.28.1 (three in `pr.md`, two in `issue.md`, the issue's opener among them), each checked on a release build of the 3.28.1 tag (192.49 s, sha256 `90d29311…6136`). The read for accuracy found five problems, fixed afterwards: the PR's reproducer listing had lost the blank lines that put `viaSupportParameterized` on line 4, as the quoted `ViaSupport.swift:4:30` needs, so both drafts now list one captioned block per file, each byte-identical to its file in the reproducer repository; the PR said macOS 27.2 where `sw_vers` gives 27.2.1 (installed 2026-11-11, before every run); two PR claims had no log behind them (now logged and copied beside the drafts); the issue's `Package.swift` listing put a label comment above the tools-version line; and "all three test files" now names them, since `Support.swift` keeps its import. Both drafts keep the marker `<!-- Opener: rewrite in your own words before posting. -->` on line 1 and one collapsed block labelled with the model. **Nothing was posted**, and the openers are still the drafts' own.

## Times and performance

Release builds, this Mac. The gating parts' times were taken while the other package's part and the outskirts drafts' builds and tests ran; the step-9 rows ran alone.

| Run | swift-algorithms | SEI | SIP |
|---|---|---|---|
| Plain scan carrying M6's coverage and mutation into v6 (step 0) | 5.79 s | 5.0 s | — |
| First `scan --index`, gating run | **24.80 s** (build 16,619 ms, index 178, periphery 1,015) | **35.63 s** (27,599, 225, 765) | **196.23 s** (122,800, 5,046, 7,840) |
| Second `scan --index`, root-only rebuild | 11.52 s (4,787, 102, 691) | 14.40 s (7,650, 214, 762) | 133.63 s (93,291, 4,991, 7,834) |
| First `scan --index`, alone (step 9) | **18.91 s** (build 11,607 ms, SwiftPM 8.30 s; index 91; periphery 687) | **29.67 s** (21,192, SwiftPM 16.21 s; 210; 786) | — |
| Root-only rebuild, alone (step 9) | **10.87 s** (4,070, SwiftPM 2.76 s; 89; 692) | **13.78 s** (7,068, SwiftPM 4.38 s; 209; 762) | — |
| outskirts runs, `roots` / `production` (step 9) | ≈0.30 / 0.21 s | ≈0.38 / 0.23 s | ≈6.00 / 1.60 s (scan 1) |
| Plain scan carrying the T1 group; after the comment rebuild | 4.84 s; 5.57 s | 4.39 s; 5.27 s | — |
| `scan --index` into the default store; plain scan after it | 22.51 s; 5.59 s | 36.2 s; — | — |
| `scan --coverage --index` (step 7) | 27.63 s | 46.7 s | — |
| `scan --index` after the interrupts | — | 26.89 s (build 18,918 ms) | — |
| `report` on the T1 snapshot, Markdown; JSON (median of 5) | 1.088 s; 1.137 s | 1.102 s; 1.125 s | — |
| `<scratch>` after the first build | 150,320 KB | 538,516 KB | 2,781,500 KB |

- **The build dominates T1.** The index read takes under a quarter of a second on the gating packages and 5 s on SIP; outskirts' two runs about a second there and 7.8 s on SIP. On SIP, whose own code dominates its build, the root-only rebuild still takes 76% of the first's collector time (93.3 s of 122.8 s); on swift-algorithms and SEI it is 35% and 33% alone.
- **The reports grow** with the T1 blocks: swift-algorithms' Markdown from 33,897 to 45,716 B and its JSON from 5,394,546 to 6,276,450 B; SEI's from 43,075 to 56,473 B and 5,534,826 to 6,677,420 B. SIP's report JSON is 69,769,301 B.
- **SwiftStats' own release build** took 236.58 s (SwiftPM), against the design probe's 224.6 s for `fff063a`; the two were not measured alike, so this isn't the cost of the new dependency.

**Performance against M6**: T0 and the `report` bar are in Results, part 9; both met.

## Decisions

The user's M7 answers (decisions.md, 2026-11-24):

- **The index reader** is indexstore-db's `IndexStore` product, linked, pinned by revision `64aa0b2` (tag `swift-6.4.2-RELEASE`); PRD D3 becomes "SEI, SwiftCodeMetrics and indexstore-db's IndexStore reader".
- **Coupling**: M7 stores the index side (module edges, cross-module fan-in, USR type cycles). PRD §7.6's T0 syntax coupling and the cross-check against it move to a new M7b, and the PRD records that §7.6 was never built.
- **Packages**: swift-algorithms (`5b7143f`) and SEI (`c8644fd`) gate, from copies of M6's stores; an empty dead-but-tested list counts with its funnel printed and a fixture yielding rows. SIP is a non-gating third package for cross-module coupling, test-only and hidden coupling. The PRD says SEI is single-module.
- **outskirts**: pin 3.28.0 (`a1e5d6e1`), built from source, identity the binary's SHA-256, the tag as label. Draft a PR (Swift Testing's parameter check for `@Test` in files importing Testing indirectly) and an issue (a missed unused `@testable` import), each with an opener marked for the user to rewrite; post nothing until the user says so.

Adopted as recommended, not asked (decisions.md): building with `-index-include-locals`; one persistent T1 build directory with the listed flags, root intermediates deleted and a stale-unit filter; T1 opt-in with coverage's same-tree carry, `--drop-index`, refusal before the run and backfill keeping it; dead as outskirts with `--exclude-tests`, tested as a mutant that ran; the three retention flags; one primary USR per record with a secondary accessor USR and body-less requirements listed apart; cross-snapshot disagreements as a fixture test and a `diff` "same USR" rule; store v6 and scan 9; test-only from the index with its five exclusions; hidden coupling's definition and limits; timings per record with no diff direction and warnings classified by diagnostic ID.

The design's own choices (argued in it): one `--index` flag and three collectors; the coverage collector's `swift` for the build; `--no-color-diagnostics`; the T1 session's own describe; target names for every module; coverage keeping its range mapping, the llvm-cov USR join a checker mode only; the `IndexStoreSource` seam; recordings as the checker's reader output, not binary stores; and no per-record timing diff.

Decided during the build and the reviews (by the implementers and fixers, within the design, each recorded as an As-built note unless said):

- **Step 5b's two readings of §4.1** (locals followed to the enclosing declaration; only package-declared protocols' requirements expand), recorded at first only in step 5b's notes, then adopted after the done-when.
- **Step 6a's reading of §5.3's `local` class**: only variables other than parameters, by the index's `local` property or a position inside a function record. The index also marks local functions, local types' members and parameters as local, and §5.3's literal text would drop `unusedHelper()`, which the design's own fixture test needs mapped. The checker defaults to it (`--local-rule plan`). §5.3's C13 As-built note shortens the rule string to "local variables (…)", but no note explains this reading.
- **Step 6b's mapping of only `unused` production entries** (entries of other hints are listed and counted but cover nothing), and its `map:` rule string, which states the mapping as built rather than §5.4's text (kept after step 6b's review). Both were recorded only in step 6b's notes, as deviations, until the done-when.
- **Step 9b's reading of §8.2**: an unused property's accessor records count as production-dead functions, as §5.4's `property` rule gives, though §8.2 expected none on SEI. Recorded in step 9b's notes; the checker counts the same way.
- **Carried type-check totals** are read from the held snapshot's `typecheck.milliseconds.total` rows, not re-added from the build rows, which hold whole ms while the total is summed in hundredths and rounded once.
- **A carried reader prints no warning line**: a carry happens only when this scan's build didn't run, and then the build's line is printed (C25).
- **A held family id must be a family of the rescan**, or the carry refuses (C22).
- **Re-exported targets are retained** with library-product targets, for outskirts and for test-only's public-API exclusion (C14); **nested records are dead with their outermost covered ancestor** and judged with it (C23); **a private type nested in a plain one is nested** for hidden coupling and cycles (C10); **property and subscript requirements' accessors are requirements** (C6/C33); **inactive `#if` needs a read unit** for the file (C9).
- **Local types of one name share a type identity**: step 5b's review raised it as medium; it was reported as an open design gap with no code change.

Decided after the done-when (the fixes, below): §4.1's step-5b readings and step 6b's `unused`-only mapping (§5.4) adopted as built, with As-built notes and as the checker's defaults; `coverage-names` counting `fC` agreements, explaining the ABI-module case and exiting 0 when only explained exceptions remain; the drafts' five accuracy fixes and their 3.28.1 version lines.

Not decided: whether SwiftStats moves its outskirts pin to 3.28.1; posting the drafts, with the openers in the user's own words; and, since outskirts' CONTRIBUTING asks for an issue per PR (`Closes #N`), whether to open the PR's own issue first or drop the line.

## Review

The design went through four critiques before the build (correctness, contract, testability, scope and signals). Of their 62 findings, 59 were accepted and 3 in part (2 scope and signals, 1 testability); none was rejected. Three questions were settled by a probe of the designer's own (unit dependencies carry module names; the `init` accessor's raw subkind 1016; a default implementation's definition carries `overrideOf`).

Each of the 19 implementation steps (01, 02a to 10) was reviewed as it was built, with the checker's mode for a rule written first in steps 2a, 2b, 5a, 5b, 6a, 6b and 9a to 9c, by another agent than the rule's code. The reviews raised 51 findings (1 high, 11 medium, 39 low); step 07b had none. All were fixed, except part of one step-5a finding the fixer showed wrong; two of step 5b's, the shared identity of same-named local types (medium), left as an open gap, and the remark that u7 isn't independent of the Swift code (low), recorded in the step notes; and step 6b's finding that its `map:` rule string departs from §5.4's text (low), kept as built and recorded as a deviation in the step notes. Step 5b's finding that the index read every occurrence twice was fixed, with no measurable effect on time (below). The high one, in step 5b: a type and its private nested type weren't treated as nested, so their references to each other made false type cycles. Among the medium ones: the computed C99 name didn't follow SwiftPM's rule (01); the fixture had no key collision for the USR to separate (02a); local types' members were counted inside the enclosing body (02b); `index.lock` was released when the build returned, not held for the whole group (03b); every unit of a `path: "."` target was classed stale and quarantined (04a); a mutation scan refused by a placeholder named a command that would be refused again, and check u8 didn't exist (07a); and hidden coupling's cross-target owner fallback found a type by name that the root's target can't see (09c). Tests grew from 822 in 176 suites after M6 to 839 in 179 after step 01 and 1,145 in 238 after step 10.

**Three gaps** were closed next, before the adversarial review:

- **The `typecheck.*` roll-ups** (design §6.4) had been built by no step; step 10's notes said so. They were built (`TypeCheckRollup`, `TypeCheckTotals`, `TypeCheckRollupBuilder`), stored, carried and read by the Markdown, following the checker's reading. A review of them raised 5 low findings; 4 were fixed (a held snapshot missing some total rows was carried with 0 for them, now `damagedIndex`), and the fifth, carrying totals from roll-up rows rather than rebuilding them, was accepted and written into the design.
- **The u8 checker mode**: step 7a's review found that u8 didn't exist; it was added to `usr --store` for the index tables. The gap was the rest: a new `rows` mode compares every M7 row of a snapshot (index, build, dead code, `swiftc` findings, roll-ups, collector runs) with the scan JSON that saved it. The checker grew from 8,870 to 9,576 lines.
- **The index collector slowdown**: step 5b's review reported that the collector read every occurrence twice, making SIP's index collector 4.6 times slower; its fixer removed the double read, which made no measurable difference. Measured in release at the gaps step, SIP's took 5,776 and 5,702 ms against step 5a's 1,914 and 1,828, about 3 times, from the passes step 5b added, each linear in the occurrences; no pass was worse than linear. Two fixes (a per-reference copy of the whole counting pass, and a dedup set grown from empty) brought it to 4,821 and 4,759 ms. The target of under 3 s wasn't met; it would need interning USRs or merging passes. The done-when measured 5,046 and 4,991 ms.

After them, 1,153 tests in 240 suites passed.

The finished code then had an adversarial review across eleven areas: the build session, the index reader, the USR join, references and coupling, outskirts and dead code, the store and `diff`, carrying and saving, signals, reports and the CLI, tests and fixtures, and conformance to the design. A verifier reproduced each claim. 37 findings were confirmed (14 medium, 23 low, none high), none contested and none refuted. Some are one defect seen from two areas: C6 and C33, C17 and C36, C18 and C28 (with C34 naming more help texts), and C0, C5 and C7 share one cause. They were fixed in six groups. Each group's fix was checked independently, and what the check found was corrected; behaviour fixes came with tests the fixers showed to fail with the fix undone. Findings are numbered from 0.

**Paths** (C0, C5, C7, C13). The check found that a source the scan excludes, inside a linked target directory, got its manifest spelling in the index units but its real path in dead code and `swiftc` findings, so `dead` failed; corrected by building every real-path table from the describe's sources.

| # | Finding | Fix |
|---|---|---|
| 0 | (medium) A symlinked target directory or source file lost all its timings and warnings, and the index failed: the compiler prints real paths, the scan keeps the link's | `SourcePaths`: every source and every printed path resolved once with realpath(3) in NFC, shared by the timing mapper, the warning reader, the unit filter and outskirts' reader |
| 5 | (medium) The unit filter compared real main files with describe paths never resolved, so symlinked or case-mismatched sources' units were classed stale and quarantined | Rule 4 compares real paths; unit and record paths take the describe's spelling |
| 7 | (medium) A symlinked source file's unit was moved out of the store; its records read `file not indexed` or `inactive #if branch` | The same fix |
| 13 | (medium) Production files in a directory a test target shares were classed `test` and dropped from dead code | Classed by the scanned file's own target; the directory fallback only for files the scan didn't parse |

**USRs** (C6/C33, C8, C9). The check found SIP's u6 failure on sugared keys recorded only in notes; corrected in the checker, which now reads `[T]`, `[K: V]` and `T?` as the types they name, so `usr` passes on SIP.

| # | Finding | Fix |
|---|---|---|
| 6, 33 | (medium) Protocol property and subscript requirements' accessors were listed as `outsideRecords`, so criterion 3 would fail on SIP (12 getters) | A definition no record holds is a requirement when its `childOf` names a protocol, or its `childOf` or `accessorOf` names a property the same file defines as a protocol's child |
| 8 | A shorthand subscript holding a local computed property lost its secondary accessor USR | "Accessor records of its own" means records named `subscript` |
| 9 | `inactive #if branch` was given in a file with no read unit, masking `file not indexed` and `target not built` | Only when the file is a read unit's main file |

**Build** (C1, C2, C3, C4, C30, C31). The check found nothing.

| # | Finding | Fix |
|---|---|---|
| 1 | A failed build pointed at the task log, which holds none of the errors, and its reason was mostly Swift Build's `info:` target graph | The line names `swiftstats-build.stderr` first; the reason drops `info:` lines and keeps the first 20 from the first error |
| 2 | A message could end early at a quoted source line ending ` [word]` | It runs to the last continuable line after which the text ends with an ID or group |
| 3 | Every `flock` failure read as another scan holding the lock | Only `EWOULDBLOCK`; others read `could not lock .swiftstats/index.lock: <strerror>` |
| 4 | Leftover API and untested failure paths in the build session | `SwiftToolchain.bin` removed; tests of each failure path |
| 30 | (medium) Re-recording the unchanged fixture broke `recordedFailure`: the failing build's recording was racy | Built with `-j 1` and normalised; three fresh recordings byte-identical |
| 31 | Tests left about 20 temporary directories per run | Removed by the tests |

**Dead code and signals** (C10, C11, C12, C14, C15, C16, C23, C24, C29). The check found that C12's warning had no end-to-end test, and that the checker's `@_exported import` pattern missed `@_exported public import` and an attribute on its own line; both corrected (a scan-and-carry test; the pattern).

| # | Finding | Fix |
|---|---|---|
| 10 | (medium) Hidden coupling's nesting test needed equal type files, so a private type nested in a plain one wasn't nested | `TypeIdentity.isNested(in:)` either way, as the cycle graph reads it |
| 11 | The positional container's type and file fallbacks were never exercised | Test |
| 12 | Unplaced package type definitions (inside a macro's closure) were dropped silently | A scan warning naming them, kept by a carry |
| 14 | (medium) Public API a library module re-exports with `@_exported import` wasn't retained and read as dead | Re-exported package targets retained, transitively, and listed in `libraryModules` |
| 15 | An outskirts run stopped by a signal was never tested | Test |
| 16 | `PeripheryEntryClass.ordered`, unused public API | Removed |
| 23 | (medium) Dead but tested missed dead subscripts with explicit accessors and dead functions with local helpers, counting their nested records as used | A record is dead with its nearest covered ancestor; only the outermost is judged and listed, with all their mutants (funnel term `I`) |
| 24 | Unused `CaseIterable` conformances | Removed |
| 29 | (medium) No test covered Tarjan's on-stack guard | Tests (edges into a finished component, a 10,000-type chain) |

**Carry** (C19, C20, C21, C22, and two checks the fixer was asked for: `swiftc` categories across a carry, verified with no change, and design notes for the carried type-check totals). The check found one As-built note splitting a section's list from its lead sentence; corrected by moving it.

| # | Finding | Fix |
|---|---|---|
| 19 | (medium) No test covered a scan asking for both `--index` and `--mutation`: both gate guards could be removed with every test passing | Two tests |
| 20 | (medium) Carrying a held T1 snapshot whose index read failed was untested | Test suite |
| 21 | Rule-string and type-file refusals were partly tested | One test per rule, eight in all, and a type-file test |
| 22 | Family membership was recomputed with the current code, so a rebuild that regroups families still carried | Refused when a held family id isn't a family of the rescan; a regrouping that keeps every held id still carries |

**CLI and reports** (C17/C36, C18/C28/C34, C25, C26, C27, C32, C35). The check found nothing.

| # | Finding | Fix |
|---|---|---|
| 17, 36 | A test and suite still said `--drop-index` "drops nothing yet" | Renamed |
| 18, 28, 34 | Help texts disagreed with behaviour: `trend` left out `typecheck.*` and `tests.lineRatio.deadLines` and footnoted a count as a time; `diff`'s USR matching and `scan --format json`'s list | Help texts corrected; the footnote only under the millisecond metrics |
| 25 | (medium) `scan --index` printed nothing when outskirts or the index read didn't run, though the help said it would | `Warning: index: …` and `Warning: periphery: …` lines |
| 26, 27 | The Dead code section hid that a not-collected status was carried, and nothing tested it | The carry line on that path too, in both sections; tests |
| 32 | The checker labelled missing `typecheck.*` roll-ups "not built yet" | Text corrected |
| 35 | The optional `coverage-names` mode was never built | Built |

After the review fixes, on the measured tree `638b071a`: `swift build --build-tests` gives no warnings, `swift test` passes 1,197 tests in 252 suites (twice), and strict SwiftLint reports 0 violations.

**The done-when fixes**, after the runs, in tree `3428b623`. Only `Scripts/index-check.py` changed (+233 −83), with the design's notes and the drafts outside the repository:

| # | Problem | Fix |
|---|---|---|
| 1 | u7 passed only under step 5b's readings of §4.1, which the design had never recorded; the runners showed the difference as a wording note | §4.1's As-built note adopts both readings with the measured effect; the checker's defaults are now `enclosing` and `package`; its rule-text line compares the reading in force. An independent check found the note narrower than the code; reworded |
| 2 | `dead` failed on SIP: §5.4's body mapped every hint, its rule string and SwiftStats only `unused` | The body says hint `unused`; an As-built note explains why; the checker's default is `--map-hints unused` |
| 3 | `coverage-names` exited 1 on SEI for a re-homed type, and counted `fC` agreements as exceptions | `fC` agreements count; the ABI-module case is an explained kind; exit 0 when only explained exceptions remain |
| 4 | Five accuracy problems in the outskirts drafts | Fixed in the drafts and their backup (above) |

Re-run on store copies with the new defaults, `usr`, `build`, `dead`, `signals` and `rows` passed on both gating packages (all five on scan 1; `build` couldn't be re-run on scan 2) and on SIP's scan 2; on SIP's scan 1 all pass but `usr`, whose u1 fails from the unit swap. `dump` and u0, which the fixes don't touch, weren't re-run; `coverage-names` exits 0 on both gating packages. The store copies' hashes didn't change and the clones stayed clean. `swift build --build-tests` gives no warnings, `swift test` passes 1,197 tests in 252 suites, and strict SwiftLint reports 0 violations.

## Known limits

- **M7b is not built.** PRD §7.6's T0 coupling values (SwiftCodeMetrics' fan-out, type coupling and cycles, module coupling) were never built in any milestone, and the cross-check of the index side against them, with the differences listed, is M7b. M7's coupling figures are checked only against the independent checker's own computation.
- **Left for the "Later" row** (added to PRD §11 in v0.2.13): coverage and mutation roll-ups with dead code excluded beyond the ratio (the `deadRecord` rows make them a report-time addition), the outskirts run without `--retain-public` for PRD §7.5's redundant-public findings, type-level readings of test-only and dead but tested, and moving the outskirts pin to 3.28.1 or later with the dead-code checks rerun.
- **The signals judge functions only.** A production type or stored property used only by tests, or dead, isn't listed; a computed property is judged only through its accessor records, as SEI's `firstBindingName` getter was. `typeIndex` stores the referrers a type-level reading would need.
- **All three signals are empty on both gating packages.** Dead but tested has rows only on the Index fixture: SIP had no mutation run, so it was left out there. Hidden coupling's and test-only's real rows come from SIP alone, and an agent, not a human, read them (4 of 7 and 5 of 19 worth attention). Test-only's "no reference at all" term is mostly local functions referenced only by their parent (11 of SIP's 12), which its wording overstates (a review note).
- **u7 confirms SwiftStats' readings, not the design's.** The checker was given step 5b's readings of §4.1, and the done-when made them its defaults, so u7 can't detect a departure from §4.1 as first written. Those readings change the figures a lot (231 of swift-algorithms' records, 7,384 of SIP's); no gating criterion turned on them, nor SEI's hidden-coupling classes (see the Done-when section), but no signal was re-run under the literal readings and SIP's lists weren't re-read under them. SwiftStats' `references:` rule string is shorter than the rule it applies: it names only a local variable, and only for calledBy and containedBy, while the walk also follows a local named by `baseOf` or `extendedBy` and stops at a local with no `childOf`. It was kept as built. The checker's help text for `--local-containers` (`index-check.py:356-358`) and `ReferenceResolver.swift`'s header comment (:9-11) use the same narrower wording, and the checker's header still lists "a package type definition no compatible type record holds" as failed (`index-check.py:442`), which review C12 made a printed listing.
- **The checker's `dead` mode also takes an implementation reading by default**: step 6a's reading of §5.3's `local` class (`--local-rule plan`), which no As-built note explains (C13's note only shortens the rule string to "local variables (…)"). The audits didn't raise it; on the fixture the literal reading would move `unusedHelper()` to `local` and drop dead lines 22 → 19 and 26 → 23.
- **Same-named local types share a type identity** (`SwiftEffectInference::Finder` ×3; on SIP `SwiftInferCore::Collector` ×6), so their `typeIndex` row and family-type references merge. Open since step 5b's review. An unmeasured type inside a macro's closure in a type of the same kind is placed on the enclosing type and not warned of.
- **The kept unit of a duplicate pair can change between builds**: SIP's macro target swapped all three on the second build, the six units having one modification time. The records were the same, but a checker run against an older scan's JSON fails u1 once the store has been rebuilt; re-checking needs the build output and store as that scan left them. For a different reason `build` couldn't be re-run on either gating package's scan 2: step 7 rebuilt into the same directory, overwriting that build's output, and no copy was kept.
- **outskirts is pinned at 3.28.0** though 3.28.1 is out (one fix, #434, a redundant-public false positive; SwiftStats maps only hint `unused` to records). A 3.28.1 binary would run with SwiftStats' version warning and break comparability with every earlier `periphery` result. 3.28.0's errors stay in the rules: an unused import missed when the module's types appear only in signatures of functions the file calls; a function called only from an inactive `#if` branch reported unused; a non-test helper target used only by tests analysed as production; unused parameters of a parameterized `@Test` reported in a file that sees `Testing` only through a re-export (dropped with test-target results).
- **The outskirts drafts are not posted.** Their openers are still the drafts' own and must be rewritten by the user; the PR's own issue isn't drafted; the `patches/` files are still the 3.28.0-based ones (same content as the rebased commits); and the issue's historical "3.28.0 did not" line wasn't re-checked on 3.28.1.
- **The T1 directory is large and never removed**: after a first build alone (step 9), 147 MiB on swift-algorithms and 528 MiB on SEI (147 and 526 MiB after the gating runs' first builds), and 2.65 GiB on SIP. Deleting `.swiftstats/index-build` is safe and costs a dependency build, which re-fetches dependencies (SwiftPM fetched swift-syntax from GitHub after each removal on SEI).
- **T1 is slow on packages whose own code dominates**: SIP's scans took 196 s and 134 s, its root-only rebuild 76% of the first build, and its index read about 5 s, over the 3 s the gaps step aimed for.
- **Timings vary between runs** (16–36% median per function in the research) and depend on the machine's load, which no identity names; they are stored as collected, with no direction and no per-record diff. The gating parts' times here were taken with other builds and tests running: the other gating package's and the outskirts drafts' (an outskirts build, its 8-minute test suite and a release build).
- **Interrupts**: a scan killed outright (SIGKILL) can leave `swift-build` running, and the next `scan --index` may then wait on SwiftPM's scratch lock. The interrupt check ran on SEI only, and its SIGINT reached the build before any compiler process had started; the sampler takes one sample a second, so a process living under a second could be missed.
- **The scans leave `<package>/.build/`** with lock files, from a T0 collector's SwiftPM call. All three packages ignore it; in one that doesn't, it shows as untracked.
- **`scan --drop-index` can't produce a snapshot without T1 of an unchanged tree**, by design; the `report` bar was measured against a snapshot built from the pristine M6 store instead.
- **Carry limits**: a SwiftStats rebuild that regroups families while keeping every held family id still carries; the carry never consults the SwiftStats build, only the rule strings, as M5's and M6's carries. No automated test migrates a v5 store already holding coverage and mutation rows; step 0's live run covers it.
- **`coverage-names` is a checker mode only**, non-gating, and its ABI-module rule accepts any module rename, not only `@_originallyDefinedIn`'s. The Index fixture's figures under the new rule (97 of 99 agree, 2 explained) are recomputed from its earlier recording, not re-run.
- **Compiler warnings from macros** all carry one ID, `bridged_warning` (24 of SIP's 35), so classification by ID lumps them; plugin targets' warnings have no ID and are counted apart.
