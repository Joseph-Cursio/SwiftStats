# M1b results

**Date:** 2026-11-18 · **Toolchain:** Apple Swift 6.4.2 (Xcode 27), macOS 27.2 SDK · **Machine:** Apple M3, 8 cores · **Tools:** SwiftProjectLint 1.1.0 (release build at `6477efac`), SwiftLint 0.65.1

M1b scope (PRD §11): the SwiftProjectLint adapter on its 1.1.0 JSON (§7.15); risk markers (§7.4); API surface (§7.5); the test inventory and test-to-code ratios, no dead-code exclusion yet (§7.8); SwiftLint violations, normal rules (§7.7); dependencies (§7.14). `schemaVersion: 3`.

## Done-when

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | SwiftProjectLint and SwiftLint findings on swift-algorithms and one more package map to functions per §12 criterion 2 (at least 95% of in-body results), with unmapped ones listed | Met | Every finding in a scanned file attaches to a function, type or file: 100% (table below). The only findings outside the scan are 17 SwiftProjectLint findings in swift-collections' two manifests, listed in the report as `unscanned`. |
| 2 | SwiftLint violation counts per rule equal `swiftlint lint --reporter json` on swift-algorithms | Met | `SwiftLintParityTests.violationCounts`: 763 violations, equal per rule to `swiftlint lint --reporter json --quiet --force-exclude --config <empty> <target directories>`, none unscanned. Run on the targets' directories rather than the bare root; see "SwiftLint" below. |
| 3 | A fixture package gives hand-checked golden counts for SwiftStats' own markers, the API surface and the test inventory | Met | `Tests/Fixtures/Inventory` and `InventoryFixtureTests`: each expected number is worked out by hand from the sources, with the working in comments. |
| 4 | Direct dependencies match `swift package describe` on two packages, and the transitive graph matches `show-dependencies` when `.build` is resolved | Met | `DependencyParityTests` on swift-algorithms (swift-numerics) and SwiftCodeMetrics (swift-syntax), each read independently of SwiftStats' decoders. |

### Where findings attach

| Package | Tool | Findings | Function | Type | File | Unscanned |
|---|---|---|---|---|---|---|
| swift-algorithms `5b7143f` | SwiftProjectLint | 371 | 310 | 61 | 0 | 0 |
| | SwiftLint | 763 | 479 | 60 | 224 | 0 |
| | SwiftStats | 45 | 45 | 0 | 0 | 0 |
| swift-collections `9c63a690` | SwiftProjectLint | 2,759 | 2,499 | 231 | 12 | 17 |
| | SwiftLint | 10,284 | 7,155 | 1,481 | 1,648 | 0 |
| | SwiftStats | 6,441 | 6,441 | 0 | 0 | 0 |

Locations give a line only, so a finding whose line lies in a function always attaches to the innermost one; the in-body share is 100% by construction. What the check really guards is a finding falling outside the scan, which is now limited to files SwiftPM compiles in no target.

## What a scan now reports

- **`findings`**: every SwiftProjectLint issue, SwiftLint violation and SwiftStats marker, with tool, rule (SwiftProjectLint's case name, SwiftLint's rule identifier), kind, severity, message and where each location attaches (`function`, `type`, `file` or `unscanned`, with the function's key or the type's name).
- **`collectors`**: for SwiftProjectLint, SwiftLint and the dependency graph: `ran`, `skipped` (with the reason) or `failed` (exit status and the end of its output), the tool's version and what it was run with.
- **`tests`**: one record per test: framework, kind, cases, assertions, trials, and whether it is generated.
- **`dependencies`**: the direct dependencies with their requirements, `Package.resolved`'s pins, and the resolved graph.
- **On each function record:** `isAsync`. **On each file record:** `generated`. **On each target:** its dependencies within the package.
- **In each roll-up:**
  - findings by tool and rule, and by tool and kind;
  - `async` functions;
  - the API surface: declarations by effective access level, implicitly internal ones, public ones and how many are documented, classes and `final` ones, and over-exposed ones from SwiftProjectLint;
  - the test summary: tests by framework and kind, generated tests, helpers, parameterized cases, assertions per test, tests without assertions, and the line-ratio counts.
- A tool that didn't run has no entry in any roll-up, rather than zeros.

## Decisions

Recorded in the PRD (v0.2.6): D8 for generated code, new §7.16 for findings, and notes in §7.4, §7.5, §7.7, §7.8, §7.14 and §7.15. The ones that changed a plan:

- **SwiftProjectLint runs twice.** `enabled_only` turns opt-in rules on but every unlisted rule off, so the second run names the eight opt-in rules SwiftStats reads. An `opt_in_rules` key upstream would make it one run (§15).
- **SwiftLint lints the targets' directories.** A plain `swiftlint lint` in swift-collections' root also linted `.build/checkouts`, a worktree and the benchmarks package: 146,559 of 156,843 violations were outside the scan, and the scan took 38 s instead of 12 s. A target at the root gives its files, and a directory inside another is left out, so no file is linted twice.
- **SwiftLint's configuration is always named.** Otherwise a `.swiftlint.yml` above the package changes the counts. Naming one turns off nested configurations, which are reported in a warning.
- **The dependency graph never resolves.** `show-dependencies` runs with `--disable-automatic-resolution`, so it neither fetches nor writes `Package.resolved`.
- **XCTestCase subclasses are found across the package.** swift-collections' tests subclass `CollectionTestCase` from a support target, so only 15 of its 1,235 tests were recognised before.
- **A `@Test` inside an `#if` in the attribute list is a test.** It was counted as a helper before.
- **The `pbt-seeds` join waits for M4**, and **ratios per type wait for M5.**

## Figures

| | swift-algorithms | swift-collections |
|---|---|---|
| Tests (Swift Testing / XCTest) | 0 / 224 | 13 / 1,222 |
| Test lines ÷ production lines | 2,217 ÷ 4,592 | 22,560 ÷ 52,867 |
| Public declarations, documented | 369, 146 | 3,348, 1,592 |
| SwiftStats markers | 45 `precondition` | 5,745 `unsafe`, 693 `precondition`, 3 IUOs |
| Direct dependencies (resolved) | swift-numerics 1.1.1 | none |

## Timing (PRD §12 criterion 1)

Release build, warm caches, `swiftstats scan <package> -o <file>`, wall-clock including `swift package describe`. Two runs of each gave byte-identical output.

| Package | M1a | M1b, collectors off | M1b, all collectors |
|---|---|---|---|
| swift-algorithms | — | 0.6 s | 2.0 s |
| swift-collections | 3.8 s | 4.0 s | 11.8 s |

The T0 scan stays well inside the 30-second budget. The external tools account for the rest, mostly SwiftLint and SwiftProjectLint's two runs; per-collector times wait for the snapshot store (M2), since a timing in the JSON would break byte-identical output.

## Review

An adversarial review of the M1b diff (four reviewers, each checked by a verifier) confirmed 11 defects, each fixed with a regression test. The scans above are unchanged by the fixes:

- SwiftLint linted a file twice when one target's directory held another's, and linted the whole root for a target there; it also picked up a `.swiftlint.yml` from above the package.
- A finding on a type declared between top-level statements attached to the file's top-level code instead of the type.
- The API surface counted locals inside top-level statements, and tuple labels as names.
- `@MainActor` inside an `#if` in a declaration's attributes wasn't counted.
- A literal case count past `Int.max` crashed the scan; it is now unknown.
- `show-dependencies` could fetch over the network and write `Package.resolved` mid-scan; a disabled `dependencies` collector reported `ran`; an unreadable `Package.resolved` looked absent.

## Not done

- Collector run times are not recorded per collector (M2).
- The swift-algorithms checkout used here was resolved during M1b (`swift package show-dependencies` created `.build/checkouts` and a git-ignored `Package.resolved`), which done-when (4) needs.
