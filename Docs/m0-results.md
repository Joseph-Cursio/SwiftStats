# M0 results

**Date:** 2026-11-17 · **Toolchain:** Apple Swift 6.4.2 (Xcode 27), macOS 27.2 SDK · **Machine:** Apple M3, 8 cores

M0 scope (PRD §11): `swiftstats scan --format json`, T0 only, no store and no git. It finds targets with `swift package dump-package`, walks them with swift-syntax 603.0.2, and emits one record per PRD §6.1a kind plus a `sitrep` block of Sitrep-compatible counts. Output carries `schemaVersion: 1`.

## Done-when

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | A fixture covering every §6.1a kind produces checked-in golden JSON exactly | Met | `Tests/Fixtures/AllKinds` → `AllKinds.golden.json`; `GoldenScanTests` |
| 2 | On Sitrep's test inputs and on swift-algorithms, the `sitrep` block matches `sitrep -f json` field by field, with deliberate differences listed | Met | `Scripts/compare-sitrep.py`; matches on Sitrep's inputs and nine packages (below) |
| 3 | Lines inserted above or reformatting leave key and body hash unchanged; moving a file keeps a non-private key; a signature change changes the key | Met | `FunctionKeyStabilityTests` |
| 4 | Two runs on the same tree give byte-identical output | Met | `GoldenScanTests.deterministic` |
| 5 | Scan time on swift-collections recorded as the §12 baseline | Met | 0.94 s (below) |

## Sitrep comparison

`Scripts/compare-sitrep.py <package>` runs Sitrep (built from `~/GitHub_projects/Sitrep`, commit `ae446f9`) on a tree of symlinks to exactly the files SwiftStats scanned, then compares every field.

| Package | Files | Result |
|---|---|---|
| Sitrep `Tests/SitrepCoreTests/Inputs` (wrapped in a one-target package) | 12 | match |
| SwiftStats | 57 | match |
| swift-algorithms | 56 | match |
| swift-argument-parser | 166 | match |
| swift-collections | 709 | match |
| swift-syntax | 572 | match |
| swift-composable-architecture | 118 | match |
| GRDB.swift | 413 | match |
| swift-nio | 478 | match |
| SwiftLint | 711 | match |

**Deliberate differences from running Sitrep on a whole directory:**

- **File set.** SwiftStats scans the files of the targets in `Package.swift`. Sitrep scans every `.swift` file under the path, which also picks up `Package.swift`, `.build/`, files in no target, and DocC tutorial code inside `.docc` bundles (which SwiftPM never compiles).
- **Ties.** Where Sitrep's longest file or longest type depends on file-system or dictionary order, SwiftStats takes the first file in path order and the alphabetically first type name. Import order breaks count ties by name. No tie occurred in the comparisons above.

Sitrep's own quirks are reproduced, not fixed, inside the `sitrep` block (PRD §7.1): non-empty rather than stripped lines, top-level-only type counts, types inside actors and closures counted as top-level, file bodies joined without a separator, and the two different SwiftUI rules.

## Timing baseline (PRD §12 criterion 1)

Release build, warm file cache, `swiftstats scan <package> -o <file>`, wall-clock time including `swift package dump-package`:

| Package | Files | Records | Time |
|---|---|---|---|
| swift-collections (1.7.6 + 1 commit, `9c63a690`) | 709 | 7,197 | **0.94 s** |
| swift-syntax | 572 | 20,742 | 1.84 s |
| swift-protobuf | 288 | 25,826 | 2.01 s |
| swift-nio | 478 | 10,124 | 1.21 s |
| GRDB.swift | 413 | 7,649 | 1.18 s |
| swift-format | 260 | 2,094 | 1.05 s |
| SwiftLint | 711 | 4,188 | 0.76 s |
| swift-argument-parser | 166 | 1,564 | 0.48 s |
| swift-composable-architecture | 118 | 1,644 | 0.48 s |
| swift-algorithms | 56 | 756 | 0.38 s |

The §12 target is under 30 s for swift-collections. Parsing is sequential; there is no need to parallelise yet.

## Key uniqueness

All ten packages above scan with **no key collisions**. Getting there needed three rules beyond the PRD's key definition, found by scanning them:

- Local functions of one name in sibling blocks of a function (swift-nio, GRDB) are numbered `#2`, `#3`, … in source order.
- Declarations inside freestanding macro arguments (SwiftLint's `#example { … }`) get no record, as macro input.
- Unmodified extensions of a type the file declares `private` (GRDB's tests) are file-scoped, so their members' keys carry the file.

Collisions that remain in other code are disambiguated by file, then line, and reported as warnings, never dropped.

## Known limits

- The top-level-code record's range runs from the first to the last top-level statement, so it can enclose a global function declared between them. Mapping uses the innermost record, so results inside that function still land on it.
- Tests are recognised syntactically: `@Test`, or `test…` instance methods with no parameters on classes descending from `XCTestCase` through classes declared in the same target. A base class from another module isn't followed.
- A package whose `.swift-version` names a toolchain swiftly doesn't know (vapor's `6.4.x-snapshot-2026-09-04`) can't be scanned, because `dump-package` fails; the error is reported.
