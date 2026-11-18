# M1a results

**Date:** 2026-11-18 · **Toolchain:** Apple Swift 6.4.2 (Xcode 27), macOS 27.2 SDK · **Machine:** Apple M3, 8 cores

M1a scope (PRD §11): link SwiftCodeMetrics `0.3.0`, reusing the M0 parse; the three complexity scores on every record and the library's definition version (§7.3); size and shape per function, type and file, with distributions per module and project (§7.2); a minimal `.swiftstats.yml` (§10.1); `schemaVersion: 2`.

## Done-when

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | SwiftLint parity on swift-algorithms: for every `func` and `init`, SwiftLint 0.65.1's `cyclomatic_complexity` (0 when it reports nothing) equals SwiftStats' SwiftLint-compatible count | Met | `SwiftLintParityTests`: 674 records checked at swift-algorithms `5b7143f`, 212 of them non-zero, no mismatches. The test takes every `func` and `init` record by kind, so a record whose score failed to join counts as a mismatch, and it requires the scan to have no warnings. |
| 2 | The AllKinds fixture's golden JSON, regenerated with the new fields, matches exactly | Met | `Tests/Fixtures/AllKinds.golden.json`; `GoldenScanTests` |
| 3 | Two runs give byte-identical output | Met | `GoldenScanTests.deterministic`; three release scans of swift-collections are byte-identical |
| 4 | Scan time on swift-collections recorded next to the M0 baseline, within §12's 30-second budget | Met | 3.8 s (below) |

## What a scan now reports

- **Each function record** gains `complexity` (cognitive, decision count, SwiftLint-compatible count, whether SwiftLint scores the kind, maximum nesting, result builder, syntax errors), `parameterCount` (for `func`, `init` and `subscript`) and `isDocumented` (a `///` or `/** */` comment; for an accessor, on its property or subscript).
- **`metrics`**, once per report: the SwiftCodeMetrics release, the complexity definition version, the SwiftLint release the count was checked against, and whether the package's `.swiftlint.yml` sets `ignores_case_statements`, which the count honours. Every score in a scan comes from the same definition, so the version is stored once rather than on each record.
- **`types`**: every type declaration and extension, nested and local ones included, with its lexical name, kind, stripped lines, member count and `#if` condition.
- **`files`**: physical and stripped lines per file.
- **`rollups`**: per module, then for the project's production modules and its test modules. Each holds counts by function kind and type kind, documented functions, and nearest-rank distributions (count, total, min, median, p90, max) of function length, parameter count, maximum nesting, the three complexity scores, type body length, type member count and file length. Over no values, min, median, p90 and max are absent rather than 0 (§6.5).
- **`configuration`**: the `excluded` globs from `.swiftstats.yml` and the files they left out.

## Joining scores to records

SwiftCodeMetrics and SwiftStats find the same declarations: on the fixture, every record starts at the same line and column in both tools, and the keys agree once SwiftStats' module prefix and file suffix are removed. Scores are therefore joined on file, start position and kind. A `subscript` with explicit accessors has no score of its own; its accessors carry them. Any other record the library doesn't score gets a warning.

The one place the tools differ: SwiftCodeMetrics also scores functions declared inside a macro's arguments (`#expect(throws:) { func helper() … }`), where SwiftStats keeps no record, and leaves them out of the enclosing function's score. Each such score is reported as a warning rather than dropped (§12). swift-collections and swift-algorithms scan with no warnings of either kind.

## Stripped lines

One rule for functions, types and files (§7.2): a line counts when it holds a token that isn't part of an attribute. So `@inlinable` on its own line above a member counts toward neither the member nor the type that holds it, nor the file. M0 already excluded a declaration's own attributes; attributes nested inside a function body now follow the same rule, which changes no value in the AllKinds fixture.

## Configuration

`.swiftstats.yml` in the package root, or `--config <path>`:

- `excluded`: path globs relative to the package root. `*` and `?` stay within a path component, `**` spans components, and a plain path also excludes everything under it.
- The other §10.1 keys (`generated`, `history`, `signals`, `collectors`, `store`) are accepted, with a warning that names the file read and says they have no effect yet. Any other key, or a key given twice, is an error. An empty `excluded:` or an empty file means nothing is excluded.

## Timing (PRD §12 criterion 1)

Release build, warm file cache, `swiftstats scan <package> -o <file>`, wall-clock including `swift package describe`:

| Package | Files | Records | Types | M0 | M1a |
|---|---|---|---|---|---|
| swift-collections (`9c63a690`) | 709 | 7,197 | 2,157 | 0.88 s | **3.8 s** |

The increase is the SwiftCodeMetrics pass and the type and file measures, all over the trees M0 already parsed. It is well inside the 30-second budget.
