# M0 results

**Date:** 2026-11-17 · **Toolchain:** Apple Swift 6.4.2 (Xcode 27), macOS 27.2 SDK · **Machine:** Apple M3, 8 cores

M0 scope (PRD §11): `swiftstats scan --format json`, T0 only, no store and no git. It finds targets and their source files with `swift package describe --type json`, walks them with swift-syntax 603.0.2, and emits one record per PRD §6.1a kind plus a `sitrep` block of Sitrep-compatible counts. Output carries `schemaVersion: 1`.

## Done-when

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | A fixture covering every §6.1a kind produces checked-in golden JSON exactly | Met | `Tests/Fixtures/AllKinds` → `AllKinds.golden.json`; `GoldenScanTests` |
| 2 | On Sitrep's test inputs and on swift-algorithms, the `sitrep` block matches `sitrep -f json` field by field, with deliberate differences listed | Met | `Scripts/compare-sitrep.py`; Sitrep's inputs and 13 packages (below) |
| 3 | Lines inserted above or reformatting leave key and body hash unchanged; moving a file keeps a non-private key; a signature change changes the key | Met | `FunctionKeyStabilityTests`, `FunctionCollectorEdgeCaseTests` (trailing commas, initialiser closures) |
| 4 | Two runs on the same tree give byte-identical output | Met | `GoldenScanTests.deterministic`; swift-syntax scanned twice gives the same SHA-1 |
| 5 | Scan time on swift-collections recorded as the §12 baseline | Met | 0.88 s (below) |

## Sitrep comparison

`Scripts/compare-sitrep.py <package>` runs Sitrep (built from `~/GitHub_projects/Sitrep`, commit `ae446f9`) on a tree of symlinks to exactly the files SwiftStats scanned, then compares every field.

| Package | Files | Result |
|---|---|---|
| Sitrep `Tests/SitrepCoreTests/Inputs`, wrapped in a one-target package excluding the `ObjCExamples` folder (SwiftPM rejects a mixed-language target) | 12 | match |
| SwiftStats | 61 | match |
| swift-algorithms | 56 | match |
| swift-argument-parser | 172 | match |
| swift-collections | 709 | match |
| swift-syntax | 572 | match |
| swift-composable-architecture | 118 | match |
| GRDB.swift | 413 | match |
| swift-nio | 479 | match |
| SwiftLint | 711 | match |
| swift-protobuf | 288 | match |
| swift-format | 260 | match |
| lottie-ios | 288 | match |
| swift-testing | 302 | differs: parser version (below) |

**Deliberate differences:**

- **File set.** SwiftStats scans the files SwiftPM compiles for each target. Sitrep scans every `.swift` file under the path, which also picks up `Package.swift`, `.build/`, files in no target, resources, and DocC tutorial code inside `.docc` bundles.
- **Ties.** Where Sitrep's longest file or longest type depends on file-system or dictionary order, SwiftStats takes the first file in path order and the alphabetically first type name. Import order breaks count ties by name.
- **A type name declared with different first parents** (lottie-ios declares `LottieAnimationViewBase` on `UIView` for iOS and on `NSView` for macOS). Sitrep keeps whichever declaration it reads last, in file-system order. SwiftStats takes the first in path order and emits a `sitrep:` warning when the choice changes the UIKit or SwiftUI line counts; the comparison script then reports any difference in those two counts as a note. On lottie-ios the counts happened to agree.
- **Parser version.** Sitrep is built against swift-syntax 602.0.0, SwiftStats against 603.0.2. Newer syntax parses differently: Sitrep misparses module selectors (`#Testing::sourceLocation`) and drops the types that follow in the file. On swift-testing that gives 22 classes, 243 structs and 646 extensions in SwiftStats against 21, 240 and 638 in Sitrep, plus knock-on differences in the longest type and one `XCTest` import. A reviewer confirmed the cause by rewriting `X::y` to `X.y` in a copy, after which Sitrep reports exactly SwiftStats' numbers.

Inside the `sitrep` block, Sitrep's own quirks are reproduced, not fixed (PRD §7.1): non-empty rather than stripped lines, top-level-only type counts, types inside actors and closures counted as top-level, file bodies joined without a separator, and the two different SwiftUI rules.

## Timing baseline (PRD §12 criterion 1)

Release build, warm file cache, `swiftstats scan <package> -o <file>`, wall-clock time including `swift package describe`:

| Package | Files | Records | Time |
|---|---|---|---|
| swift-collections (1.7.6 + 1 commit, `9c63a690`) | 709 | 7,197 | **0.88 s** |
| swift-protobuf | 288 | 25,826 | 1.77 s |
| swift-syntax | 572 | 20,742 | 1.54 s |
| swift-testing | 302 | 2,925 | 1.34 s |
| swift-nio | 479 | 10,125 | 1.26 s |
| GRDB.swift | 413 | 7,649 | 1.21 s |
| lottie-ios | 288 | 1,985 | 0.86 s |
| SwiftLint | 711 | 4,188 | 0.76 s |
| swift-format | 260 | 2,094 | 0.51 s |
| swift-argument-parser | 172 | 1,584 | 0.48 s |
| swift-composable-architecture | 118 | 1,644 | 0.48 s |
| swift-algorithms | 56 | 756 | 0.37 s |

The §12 target is under 30 s for swift-collections. Parsing is sequential; there is no need to parallelise yet.

## Key uniqueness

All twelve packages above scan with **no key collisions** (about 87,000 records). Rules beyond the PRD's key definition, each found by scanning real code or by the review:

- Local functions of one name in sibling blocks of a function (swift-nio, GRDB) are numbered `#2`, `#3`, … in source order.
- Declarations inside freestanding macro arguments (SwiftLint's `#example { … }`, `#Preview`) get no record, as macro input.
- Unmodified extensions of a type the file declares `private` (GRDB's tests) are file-scoped, so their members' keys carry the file. A private type nested in an extension is tracked under its full path.
- Local declarations in a stored property's or global's initialiser closure are keyed under the property: `Holder::let first: Int = <initializer> / func helper()`.
- Declarations inside top-level statements (`do { func run() }` in `main.swift`) have the top-level-code record as parent.
- Trailing commas (SE-0439) are ignored in keys and body hashes.

Collisions that remain in other code are disambiguated by file, then line, then column, with children following their own parent, and are reported as warnings, never dropped.

## Review

After the first build, a review workflow sent four reviewers at the code, each required to reproduce every finding against the release binary on probe packages: identity keys, discovery against SwiftPM, measurements and the `sitrep` block, and robustness. A second agent per reviewer re-ran each finding and tried to refute it. **30 findings were confirmed and 2 refuted**; the confirmed ones came down to about 16 distinct defects, all fixed in the commits that follow `31f0c16`:

| Area | Defect | Fix |
|---|---|---|
| Keys | Closure-local functions in property initialisers collided with members, dragging the real member's key onto a line number | Initialiser context scope |
| Keys | Nested functions in top-level statements had no parent | Top-level record is their parent |
| Keys | Top-level statements inside `#if` were skipped | Collected from every branch |
| Keys | `#elseif B \|\| C` stored without parentheses | Parenthesised |
| Keys | Trailing commas changed keys | Ignored |
| Keys | Private type nested in an extension file-scoped an unrelated type | Full path tracked |
| Keys | Collision fallback re-pointed children to the wrong parent; same-line collisions kept duplicate keys | Parent by identity; column suffix |
| Discovery | Resources, symlinked directories, bundle directories, `Sources/` test targets, `path: "."`, `..` in `exclude` disagreed with SwiftPM | Sources from `swift package describe` |
| Measures | Byte order mark shifted line-1 columns by 3 | Offset added |
| Measures | XCTest methods returning a value counted as tests | Void only |
| Sitrep | Duplicate type names with different parents depended on order | First in path order, with a warning |
| Sitrep | Parser-version difference not documented | Listed above |
| CLI | Failure reason lost when the tool writes it to stdout | stdout fallback, last 20 lines |
| CLI | Every failure exited 64 with usage text | Only a bad path is a usage error |

The two refuted findings: a target whose directory is missing is dropped without a warning (the package is invalid and SwiftPM refuses it, so no output is wrong), and done-when (2) has no automated test (it is a comparison against an external binary, recorded here).

## Known limits

- The top-level-code record's range runs from the first to the last top-level statement, so it can enclose a global function declared between them. Mapping uses the innermost record, so results inside that function still land on it.
- Tests are recognised syntactically: `@Test`, or `test…` instance methods with no parameters and no return value on classes descending from `XCTestCase` through classes declared in the same target. A base class from another module isn't followed.
- A package whose `.swift-version` names a toolchain swiftly doesn't know (vapor's `6.4.x-snapshot-2026-09-04`) can't be scanned, because `swift package describe` fails. The CLI shows swiftly's reason and exits 1.
- `swift package describe`, like `dump-package`, writes a manifest cache under the scanned package's `.build/`.
