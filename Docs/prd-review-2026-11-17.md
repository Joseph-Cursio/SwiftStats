# SwiftStats PRD review, 2026-11-17

Review of PRD v0.1 (`prd-v0.1.md`), which produced v0.2. Seven reviewers checked the PRD against the local source of each tool; a second agent per reviewer then tried to refute every finding against the same source.

Verdicts: **confirmed** = verified as stated; **partly** = issue real, proposed text corrected by the verifier (the corrected text is the one shown). No finding was refuted.

Line numbers refer to the repos as they were on 2026-11-17.

## Sitrep

### 1. §7.1 — error, confirmed

> function count, documented function count

**Issue.** Sitrep does not report either number. `Results` declares `functionCount` and `documentedFunctionCount`, but nothing ever increments them and neither `Report` nor the text report contains them. Sitrep's README says function counts are tracked but "aren't currently reported". Sitrep's `Function` model also has no comments field, so a documented-function count can't come from it without changing the model (only `Type` keeps comments). The same claim is repeated in §7.5 ("extends Sitrep's documented-function count").

**Evidence.** Sitrep/Sources/SitrepCore/Results.swift:53-57 (declared, initialised to 0); a grep for functionCount/documentedFunctionCount finds no other uses in Sources or Tests; Report.swift:14-64 has no function fields; Scan.swift:231-272 (text report) has none; Function.swift:21-38 (stored fields are name, parameters, isStatic, throwingStatus, returnType only); README.md: "how many functions you have ... These aren't currently reported".

**Verifier.** Results.swift:53-57 declares functionCount and documentedFunctionCount, set to 0. A grep finds no other use in Sources or Tests. Report.swift has no function fields, and the text report (Scan.swift:231-272) prints none. README line 20 says function counts are tracked but 'aren't currently reported'. Function.swift stores only name, parameters, isStatic, throwingStatus and returnType. Node has no comments, so only Type carries comments. The proposed §7.5 wording is accurate.

**Change.** Remove "function count, documented function count" from §7.1 and move them to §7.2 / §7.5 as new SwiftStats metrics: "Function count and documented function count. Sitrep declares these counters but never fills them in or reports them." In §7.5 change "(extends Sitrep's documented-function count)" to "(new; Sitrep tracks doc comments on types only and reports no documentation figures)".

### 2. §7.1 — misleading, partly

> lines of code (raw and stripped)

**Issue.** Sitrep's "stripped" (reported as "Source lines of code") only drops empty lines. Comments are kept, and so are lines holding only spaces. The comment-removing `BodyStripper` exists but is switched off ("THIS CODE IS DISABLED RIGHT NOW"), and `Type.init` ignores the stripped body it is passed. Sitrep's README says "minus comments and whitespace", but the code doesn't do that. §7.2 then uses "stripped lines" for function length without defining the term, so readers will assume comments are excluded.

**Evidence.** Sitrep/Sources/SitrepCore/Extensions.swift:36-40 (`removingDuplicateLineBreaks` keeps lines where `isEmpty == false`); FileVisitor.swift:153 (file stripped body), :184-199 (BodyStripper disabled, empty string passed); Type.swift:50 (`strippedBody = body.removingDuplicateLineBreaks()`, ignores the parameter); SitrepCoreTests.swift:121 expects 23 stripped lines for Inputs/nesting.swift, which has 31 lines, 8 of them empty, and keeps all its comment lines.

**Verifier.** The diagnosis holds. removingDuplicateLineBreaks (Extensions.swift:36-40) drops only lines that are completely empty, so comments and lines holding only spaces are both kept. BodyStripper is commented out (FileVisitor.swift:184-199), and Type.init ignores the strippedBody it is passed (Type.swift:50). The test expects 23 lines for nesting.swift, which is 31 lines minus 8 empty ones. The proposed wording 'non-blank' is wrong, though: a line of only spaces is blank but Sitrep counts it. Separately, Sitrep's project total for stripped lines is lower than the true sum. Each file's stripped body has no trailing newline and the bodies are joined directly (Scan.swift:149), so every file boundary loses a line.

**Change.** In §7.1 write: "lines of code: raw, and non-empty (Sitrep calls this 'source lines of code', but it still counts comments and lines holding only spaces)". In §7.2 define the term once: "Stripped lines exclude blank lines (including lines holding only whitespace) and comments. This differs from Sitrep's figure, which keeps comments and whitespace-only lines; report both during M0 so the difference is visible."

### 3. §7.1 — misleading, partly

> UIKit vs SwiftUI lines, counts of structs / classes / enums / protocols / extensions, imports, inheritance

**Issue.** "inheritance" suggests a general inheritance or conformance statistic. Sitrep reports exactly three hard-coded counts: UIViewController subclasses, UIView subclasses, and structs conforming to View (JSON key `inheritances`). The UIKit counts check only the first inherited type, so a subclass of a subclass is missed, while the UIKit line count follows the whole chain. The list also leaves out these view counts, which the text report shows as their own lines. "imports" also needs a definition: it is the number of import statements per module name, which works out to files importing each module.

**Evidence.** Sitrep/Sources/SitrepCore/Scan.swift:182-186 (the three `inheritances` stats); Results.swift:70-82 (`inheritance.first == "UIView"` / `"UIViewController"`, and `contains("View")` for SwiftUI); Results.swift:85-104 (UIKit lines walk descendants via `extending(from:)`); Scan.swift:264-268 (text report lines for UIKit View Controllers, UIKit Views, SwiftUI Views); FileVisitor.swift:132-136 and Scan.swift:145 (imports kept in an NSCountedSet).

**Verifier.** Verified. The report's 'inheritances' list is exactly three hard-coded stats (Scan.swift:182-186). The UIKit view and view controller counts test only inheritance.first, so FeatureViewController: BaseViewController in the fixture is not counted, and the SwiftUI count uses contains("View") (Results.swift:70-82). UIKit lines walk the whole descendant chain via extending(from:). Imports go into an NSCountedSet, which gives a count per module. The proposed list repeats the 'non-blank' mistake, because Sitrep's source-line figures include whitespace-only lines.

**Change.** Replace the §7.1 list with: "Files scanned; total lines and non-empty lines; longest file and longest type (in non-empty lines); counts of structs, classes, enums, protocols and extensions; import counts per module; UIKit view controller, UIKit view and SwiftUI view counts (direct subclasses or conformers only); UIKit and SwiftUI lines of code."

### 4. §11 (M0) — gap, confirmed

> Sitrep's existing stats reproduced

**Issue.** The done-when line doesn't say whether "reproduced" means matching Sitrep's numbers exactly, quirks included. Sitrep has several quirks a per-function design will naturally fix: (1) type counts include only top-level declarations, so nested types aren't counted; (2) longest type is keyed by bare name, so a type and all its extensions add together, and same-named types in different modules or files merge; (3) longest file is reported by last path component only; (4) file bodies are joined with no separator, so a file without a trailing newline merges its last line into the next file's first; (5) the "stripped" and UIKit quirks above. Without a stated rule, M0 can't pass or fail cleanly.

**Evidence.** Sitrep/Sources/SitrepCore/Scan.swift:124 (iterates `rootNode.types` only); SitrepCoreTests.swift:156-158 expects classes 8 and enums 1, although Inputs/nesting.swift adds a nested `InnerClass` and `TestEnum`; Scan.swift:119-129 and :161-164 (lengths summed per name); SitrepCoreTests.swift:231-234 (extensions count towards the type, issue #1); Scan.swift:190 (`lastPathComponent`); Scan.swift:148-149 (`totalCode += file.results.body`).

**Verifier.** Each quirk checks out. (1) collate walks only rootNode.types (Scan.swift:124), and the test expects classes 8 and enums 1, so the nested InnerClass and TestEnum are not counted. (2) Lengths are summed by bare name (Scan.swift:119-129, 161-164), and testLongestType says extensions count towards the type. (3) The longest file is reported by lastPathComponent (Scan.swift:190). (4) File bodies are concatenated with no separator (Scan.swift:148). The stripped total is worse than (4) suggests: stripped bodies never end in a newline, so a line merges at every file boundary, not only after files missing a trailing newline. The proposed done-when rule, equal numbers or each difference listed and explained, handles all of this.

**Change.** Change M0's done-when to: "Sitrep's stats reproduced on Sitrep's own test fixtures (Tests/SitrepCoreTests/Inputs) and on one real package, with numbers equal to `sitrep -f json` or each difference listed and explained (e.g. nested types counted, comments stripped, types keyed by module + name); plus per-function records with ranges."

### 5. §7.1 — gap, confirmed

> Files scanned

**Issue.** Sitrep counts every `.swift` file found by a recursive walk of the given path, including hidden directories such as `.build/checkouts` and test folders, unless they are listed in `.sitrep.yml`. SwiftStats elsewhere bases its file sets on the `Package.swift` targets (§7.8). Every Sitrep total (files, lines, type counts, imports) changes with this choice, so §7.1 should say which discovery rule applies.

**Evidence.** Sitrep/Sources/SitrepCore/Scan.swift:67-98 (FileManager enumerator with default options; the only filters are the `.swift` extension and `excluded` prefixes); Configuration.swift:5-27 (`excluded` is the only setting); README "Configuration" section (the example excludes `.build` and `Tests` by hand).

**Verifier.** detectFiles (Scan.swift:67-98) uses FileManager's enumerator with default options, so it includes hidden directories such as .build. Its only filters are the .swift extension and the excluded prefixes. Configuration's only setting is 'excluded', and Sitrep.swift loads <path>/.sitrep.yml when one exists. The README example excludes .build and Tests by hand. The proposed text matches §7.8's use of the targets in Package.swift.

**Change.** Add to §7.1: "Sitrep scans every .swift file under the path, minus `.sitrep.yml` exclusions. SwiftStats scans the source files of the package's targets, split into production and test. For M0 comparisons, run Sitrep with `.build` and the test folders excluded."

### 6. §6.1 — gap, confirmed

> (Sitrep's `Function` model does not store this today.)

**Issue.** Correct but understated. No Sitrep model stores a location: `Function`, `Type` and `Node` have no line or range, and `File` has only a URL. `Function` also can't supply the fallback key's "signature": it keeps only argument labels (`firstName`), so `f(_ a: Int)` and `f(_ b: String)` look identical, and it has no parameter types or body. It covers only `func` declarations, so initialisers, deinitialisers, subscripts, accessors and closures are not functions to Sitrep. The enclosing-type chain is available through the weak `parent` link.

**Evidence.** Sitrep/Sources/SitrepCore/Function.swift:25-38; Type.swift:25-41; Node.swift:20-33; File.swift:15-20; FileVisitor.swift:77-118 (only `visit(_ node: FunctionDeclSyntax)`; parameters mapped from `$0.firstName.text`); File.swift:28 (parses without a SourceLocationConverter).

**Verifier.** Function, Type and Node have no line or range fields, and File keeps only a url. FileVisitor overrides visit only for FunctionDeclSyntax, so init, deinit, subscripts and accessors are not recorded. Parameters are mapped from firstName.text only, so f(_ a: Int) and f(_ b: String) both record ["_"]. Parameter types and function bodies are not stored. The proposed parenthesis is accurate.

**Change.** Replace the parenthesis with: "(Sitrep stores no source locations for any declaration. Its `Function` keeps only the name, argument labels, static flag, throws kind and return type, and it covers `func` declarations only. SwiftStats needs ranges, parameter types for the signature, and records for `init`, `deinit`, subscripts and accessors.)"

### 7. §14 (Q1) — gap, partly

> Sitrep is Apache-2.0 and SwiftSyntax-based, so either works. Extending keeps its stats compatible; a fork allows a per-function data model without upstream constraints.

**Issue.** "Either works" is overstated, and the costs aren't given. (a) Extending as a library dependency is effectively closed: `Function`, `Type`, `Node` and `Comment` are internal, and so are all members of `Results` and `File`. A client of `SitrepCore` gets only the aggregate `Report`. (b) Sitrep requires swift-syntax `from: "602.0.0"`, i.e. 602.x only (resolved to 602.0.0). SwiftEffectInference, SwiftProjectLint, SwiftInferProperties and SwiftCloneDetector all pin swift-syntax 603.0.2, so SitrepCore and the SwiftEffectInference library (§9) can't resolve in one package graph. (c) Extending upstream means PRs: the last upstream commit is 2026-09-11 (merging the author's own PRs #47 and #49), and the previous merge was 2026-04-16, so turnaround is months. Sitrep is also an aggregate reporter on swift-tools 5.8 / macOS 10.15, so per-function records, snapshots and SQLite are unlikely to fit upstream. (d) A fork is small: SitrepCore is about 1,140 lines in 12 files. But it needs a swift-syntax 603 bump, a move from Swift 5 to the Swift 6 language mode the SwiftStats skeleton uses (mutable classes with weak parent links), and Apache-2.0 duties (keep LICENSE and copyright headers, mark changed files). The licence is precisely "Apache License v2.0 with Runtime Library Exception". A third option is missing: reimplement Sitrep's ten or so stats in SwiftStats' own T0 visitor and use the `sitrep` binary only as a test oracle.

**Evidence.** Sitrep/Sources/SitrepCore/Function.swift:14, Type.swift:14, Node.swift:14, Comment.swift:14 (no `public`); Results.swift:13-57 (public struct, internal members); File.swift:15-20; Report.swift:14 (the only public data type); Package.swift:23 (`from: "602.0.0"`) and Package.resolved (602.0.0); SwiftEffectInference/Package.swift:30, SwiftProjectLint/Package.swift:48, SwiftInferProperties/Package.swift:118 (`exact: "603.0.2"`); SwiftCloneDetector Package.resolved 603.0.2; `git log` in Sitrep (shallow clone fetched 2026-11-16): ae446f9 2026-09-11, bfc5a26 2026-04-16; README Credits and LICENSE tail (Runtime Library Exception); SwiftStats/Package.swift (swift-tools 6.2, `.swiftLanguageMode(.v6)`, macOS 14).

**Verifier.** Most of this checks out. Function, Type, Node and Comment are internal, and Results' members are internal. Sitrep requires from: "602.0.0", which allows 602.x only, and its Package.resolved has 602.0.0. SwiftEffectInference, SwiftProjectLint, SwiftInferProperties and SwiftCloneDetector all pin or resolve 603.0.2. SitrepCore is 1,144 lines in 12 files. The licence is Apache 2.0 with Runtime Library Exception. SwiftStats uses Swift 6 language mode while Sitrep is on swift-tools 5.8. In the shallow clone, the last two merges are 2026-09-11 (PRs #47 and #49 from Joseph-Cursio) and 2026-04-16. One claim is overstated: 'A client of SitrepCore gets only the aggregate Report'. File.debugPrint() is public and returns the full per-file tree as JSON, including function names and labels and type bodies, though still with no source locations. Scan.parse and collate are also public. The wording should allow for that.

**Change.** Rewrite Q1 as: "**Fork, extend or reimplement Sitrep?** Sitrep is Apache-2.0 (with Runtime Library Exception) and built on SwiftSyntax. Using it as a dependency doesn't work in practice: its data model is internal (the public API offers the aggregate `Report` and a debug JSON dump of each file's tree, with no source locations), and it requires swift-syntax 602.x while SwiftEffectInference and the other tools pin 603.0.2, so the two can't share a package graph. Extending upstream means PRs to a project that merges a few times a year, and per-function records are outside its scope. A fork is small (about 1,100 lines) but needs a swift-syntax 603 bump, Swift 6 language mode and Apache-2.0 attribution. Reimplementing the ten or so stats in SwiftStats' own visitor, with `sitrep -f json` as a test oracle, avoids both. Recommended: reimplement." Update M0's scope to "Decide fork, extend or reimplement Sitrep".

**Checked and correct:**

- §1: Sitrep reports project-wide totals (line counts, type counts, imports), with no per-function output (Report.swift:14-64; Scan.swift:170-214).
- §1/§3: Sitrep reports a single longest file and a single longest type, not distributions (Report.swift:33-35).
- §7.1: files scanned, raw lines, longest file and type, UIKit and SwiftUI lines of code, counts of structs/classes/enums/protocols/extensions, and imports are all reported, in both text and JSON (Report.swift:25-63; Scan.swift:200-213, 231-272).
- §6.1: Sitrep's `Function` model has no source range or line fields (Function.swift:25-38).
- §14 Q1: Sitrep is SwiftSyntax-based (SwiftSyntax and SwiftParser products, Package.swift:6-11) and licensed under Apache 2.0 (LICENSE; headers say 'with Runtime Library Exception').
- Structure: Sitrep ships a `SitrepCore` library product and a thin `Sitrep` executable (ArgumentParser: -c, -f text|json, -i, -p) (Package.swift:18-21; Sources/Sitrep/Sitrep.swift).
- Header: Sitrep is by Paul Hudson / Hacking with Swift, at github.com/twostraws/Sitrep (README Credits; git remote).
- Maintenance: upstream is alive but slow. The last commit is 2026-09-11 (merge of the author's PRs #47 and #49) and the previous one 2026-04-16 (checked in the local shallow clone, fetched 2026-11-16).
- swift-syntax: Sitrep requires 602.x (`from: "602.0.0"`, resolved 602.0.0), swift-tools-version 5.8, macOS 10.15.

## SwiftProjectLint

### 1. §7.15 — error, confirmed

> SwiftProjectLint has roughly 220 rules across 14 categories

**Issue.** The count is 218 rules in 13 categories. RuleIdentifier has 220 cases, but two are sentinels (unknown, fileParsingError) that are not rules. PatternCategory has 14 cases, but the 14th, `other`, holds only those two sentinels.

**Evidence.** SwiftProjectLint README.md:11, :21, :52 ("218 rules across 13 categories"); Packages/SwiftProjectLintModels/Sources/SwiftProjectLintModels/RuleIdentifier.swift:298-313 (selectableRules = allCases minus sentinels; the doc comment notes the README count was once wrong "by roughly a quarter"); RuleIdentifier+Category.swift:146-148 (`.fileParsingError, .unknown` → `.other`).

**Verifier.** I checked this in the source. RuleIdentifier has 220 `case` lines. `selectableRules` is allCases minus the two sentinels (`unknown`, `fileParsingError`), which leaves 218. PatternCategory has 14 cases, and `.other` maps only those two sentinels (RuleIdentifier+Category.swift:146-148). The README says "218 rules in 13 categories" at lines 11, 21 and 52.

**Change.** SwiftProjectLint has 218 rules in 13 categories (RuleIdentifier.selectableRules; the README gives the same count).

### 2. §7.15 — error, confirmed

> emits JSON (file, line, rule, category, severity), CSV

**Issue.** These are not the JSON field names. The report is `{summary, issues}`. Each issue has `ruleName`, `category`, `severity`, `message`, `suggestion`, an optional `symbol` and `locations: [{filePath, lineNumber}]`. `ruleName` holds the display name ("Force Unwrap"), not the camelCase case name the PRD uses throughout (`forceUnwrap`). `category` holds the Swift case name ("codeQuality"). Paths are relative to the project root. There is no column and no end line. The `file`/`line`/`rule` names belong to the pbt-seeds manifest (PBTSeed), not to the JSON. CSV columns are Rule, Category, File Path, Line, Severity, Message, Suggestion, with one row per location.

**Evidence.** Sources/Core/Export/CodableLintIssue.swift:4-34; LintReport.swift; ReportSummary.swift (totalIssues, errorCount, warningCount, infoCount); JSONFormatter.swift; CSVFormatter.swift:8-16; Sources/Core/Export/PBTSeed.swift:9-13 (file, line, symbol, rule, kind); sample output Docs/roadtest/output/lint-report.json ("ruleName" : "Map Used For Side Effects", root-relative "filePath").

**Verifier.** The source matches the finding. LintReport is {summary, issues}. CodableLintIssue has severity, message, locations[{filePath, lineNumber}], suggestion, ruleName (= `RuleIdentifier.rawValue`, the display name), category (String(describing:) of the case) and an optional symbol. The CSV header is Rule, Category, File Path, Line, Severity, Message, Suggestion, with one row per location. The roadtest lint-report.json shows root-relative paths and display-name ruleName values. Because rawValue is the display name, `RuleIdentifier(rawValue:)` is the right mapping.

**Change.** SwiftProjectLint emits JSON: a `summary` of counts and an `issues` array. Each issue has `ruleName`, `category`, `severity`, `message`, `suggestion`, an optional `symbol`, and `locations` (a list of `filePath` + `lineNumber`, relative to the project root). `ruleName` is the rule's display name ("Force Unwrap"), so the adapter maps it to the case names used in this document through `RuleIdentifier(rawValue:)`. There is no column or end line. It also emits CSV and a `pbt-seeds` manifest (`file`, `line`, `symbol`, `rule`, `kind`, …) that swift-infer consumes.

### 3. §7.15 — error, confirmed

> (`swiftLintSuppression`, `swiftProjectLintSuppression`)

**Issue.** Neither identifier exists. The real case names keep 'lint' in lower case.

**Evidence.** Packages/SwiftProjectLintModels/Sources/SwiftProjectLintModels/RuleIdentifier.swift:108-109 (`case swiftlintSuppression = "SwiftLint Suppression"`, `case swiftprojectlintSuppression = "SwiftProjectLint Suppression"`). Every other rule name the PRD gives exists with that exact spelling.

**Verifier.** RuleIdentifier.swift:108-109 defines `swiftlintSuppression` and `swiftprojectlintSuppression`. The PRD's camel-case spellings do not exist.

**Change.** Count of `swiftlint:disable` and SwiftProjectLint suppression comments (`swiftlintSuppression`, `swiftprojectlintSuppression`), per module and over time.

### 4. §6.4 — misleading, confirmed

> Every metric carries a **kind**, adopted from SwiftProjectLint's `CandidateInventory`

**Issue.** This overstates what CandidateInventory is. It is a fixed set of three rules (pureFunctionCandidate, pureClosureCandidate, pureMutatorCandidate), used only to stop the text report listing them. No finding carries a kind: the JSON, CSV and pbt-seeds outputs have no census/defect field. SwiftStats has to keep its own rule → kind table. That also means §7.15's "Each rule is tagged census or defect" is SwiftStats' job, not something SwiftProjectLint provides. impureClosureInventory calls itself a census in its doc comment but is not in CandidateInventory, which shows the code has no single list.

**Evidence.** Sources/Core/Export/CandidateInventory.swift:53-57 (inventoryRules, three rules), :76-82 (split); Sources/CLI/SwiftProjectLintCLI.swift:198-238 (used only on the text path); CodableLintIssue.swift (no kind field); RuleIdentifier.swift:267-274 (impureClosureInventory: "A census rather than a defect report").

**Verifier.** CandidateInventory.inventoryRules contains exactly three rules (pureFunctionCandidate, pureClosureCandidate, pureMutatorCandidate). It is used only in the CLI's text render path. CodableLintIssue and PBTSeed have no census/defect field. impureClosureInventory's doc comment calls it "A census rather than a defect report", yet it is not in inventoryRules.

**Change.** Every metric carries a **kind**. The idea comes from SwiftProjectLint's `CandidateInventory`, which keeps three census rules (`pureFunctionCandidate`, `pureClosureCandidate`, `pureMutatorCandidate`) out of its text report. SwiftProjectLint's outputs do not carry a kind, so SwiftStats keeps its own rule-to-kind table and checks it against `CandidateInventory` on each release.

### 5. §7.15 — contradiction, confirmed

> `missingEquatableOnPureResult`: pure function whose result type isn't `Equatable`, so it is hard to property-test

**Issue.** It is listed under census rules. CandidateInventory explicitly leaves it out of the census because it names a conformance to add, which is an edit. That is the PRD's own §6.4 test for a defect.

**Evidence.** Sources/Core/Export/CandidateInventory.swift:29-31 ("`.missingEquatableOnPureResult` seeds the same pipeline and is **not** here — it names a conformance to add, which is an edit."); MissingEquatableOnPureResultVisitor.swift:21 ("not one of `CandidateInventory`'s collapsed census rules").

**Verifier.** The source matches the finding. CandidateInventory.swift says missingEquatableOnPureResult "is **not** here — it names a conformance to add, which is an edit". MissingEquatableOnPureResultVisitor.swift:21 repeats that it is not a collapsed census rule. The PBTSeed `requires` field is set only by this rule, which matches "still seeds".

**Change.** Move it to the defect list (under Testability): `missingEquatableOnPureResult`: pure function refused as a property-test candidate only because its result isn't `Equatable`; adding the conformance makes it testable. It still seeds pbt-seeds, but it asks for an edit, so it is a defect.

### 6. §7.8 — error, confirmed

> **Tests with no assertions** (SwiftProjectLint `testMissingAssertion`, `testMissingExpect`, `testMissingRequire`)

**Issue.** Only testMissingAssertion means "no assertions", and it checks only Swift Testing `@Test` functions with neither `#expect` nor `#require`. testMissingExpect flags a `@Test` with no `#expect`, which may still have `#require`. testMissingRequire was narrowed: it now flags a `@Test` that force-unwraps, `try!`s or `as!`s where `#require` would fail just that test. None of the three looks at XCTest, so XCTest methods with no `XCTAssert*` are not covered.

**Evidence.** Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/CodeQuality/Visitors/TestMissingAssertionVisitor.swift:3,12 (recognizedMacros ["expect","require"]); TestMissingRequireVisitor.swift:4-20; Docs/rules/test-missing-expect.md; Docs/rules/test-missing-require.md.

**Verifier.** The three visitors match the finding. TestMissingAssertionVisitor treats `expect` and `require` as assertions and checks only `@Test` functions. TestMissingExpectVisitor recognizes only `expect`, so a test with `#require` alone is still flagged. TestMissingRequireVisitor's doc says it was narrowed to traps (`!`, `try!`, `as!`). None of the three files mentions XCT.

**Change.** **Tests with no assertions**: Swift Testing tests from SwiftProjectLint `testMissingAssertion`; XCTest tests with no `XCTAssert*` computed by SwiftStats at T0. A defect-kind metric: these tests pass whatever the code does. Related, counted separately: `testMissingExpect` (a test that checks preconditions with `#require` but never asserts a result) and `testMissingRequire` (a test that traps through `!`, `try!` or `as!` where `#require` would fail just that test).

### 7. §7.15 — gap, confirmed

> SwiftStats reads the JSON and maps each finding to a function by line range

**Issue.** Several rules the PRD depends on are off by default, so a default run gives the adapter no findings for them: testMissingAssertion, testMissingExpect, testMissingRequire (§7.8) and duplicateStructShape, duplicateEnumMapping, parallelEnumShape, scatteredEnumMapping (§7.12). There is no `--rules` flag. The only way to turn them on is `enabled_only` in a config file, and that runs only the listed rules, so SwiftStats has to pass a config that lists every rule it wants. A default run also skips nested packages (`--include-nested-packages`). And the CLI exits 1 or 2 whenever it finds warnings or errors, so a non-zero exit is not a failed run.

**Evidence.** Packages/SwiftProjectLintConfig/Sources/SwiftProjectLintConfig/Configuration/LintConfiguration.swift:107-145 (optInRules), :168-176 (enabled_only intersects; otherwise opt-in rules removed); Sources/CLI/SwiftProjectLintCLI.swift:16-77 (options: format, threshold, target-type, categories, config, include-nested-packages); Sources/CLI/ExitCodes.swift; Docs/rules/test-missing-assertion.md ("Opt-in: yes — enable via `enabled_only`").

**Verifier.** LintConfiguration.optInRules includes all seven listed rules. resolveRules intersects with `enabled_only` when it is set, and otherwise subtracts the opt-in rules. The CLI options are format, threshold, target-type, categories, config and include-nested-packages; there is no rules flag. ExitCodes returns 1 for warnings and 2 for errors. The test-missing-assertion doc says "enable via `enabled_only`".

**Change.** Add: **Invocation.** Several rules used here are opt-in (`testMissingAssertion`, `testMissingExpect`, `testMissingRequire`, `duplicateStructShape`, `duplicateEnumMapping`, `parallelEnumShape`, `scatteredEnumMapping`). SwiftStats runs SwiftProjectLint with its own config whose `enabled_only` lists every rule it consumes, plus `--include-nested-packages`, and records that rule list in the snapshot. Exit codes 1 and 2 mean findings, not failure.

### 8. §7.6 — error, confirmed

> SwiftProjectLint already builds a package graph and reports `circularDependency`, `layerDependency` and `undeclaredTargetDependency` at T0; use those for module-level structure

**Issue.** Only undeclaredTargetDependency (and its mirror, unusedTargetDependency) works at module level from Package.swift. circularDependency is a type-level rule: it looks at stored-property and parameter references between types and finds only length-2 cycles (A→B→A), skipping weak and protocol references. layerDependency checks folder 'layers' declared in `architectural_layers` with `may_depend_on`, and reports nothing without that config.

**Evidence.** Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/Architecture/Visitors/CircularDependencyVisitor.swift:5-10; Docs/rules/circular-dependency.md ("detects length-2 cycles (A→B→A)"); Docs/rules/layer-dependency.md ("In a single-target app, the layers are folders"; `may_depend_on` config); Docs/rules/undeclared-target-dependency.md; RuleIdentifier.swift:81 (unusedTargetDependency).

**Verifier.** The source matches the finding. CircularDependencyVisitor's doc says it collects types referenced via stored properties and parameters and detects length-2 cycles (A→B→A), suppressing weak and protocol references. layer-dependency.md says layers are folders configured with `may_depend_on`, and a layer without it is not checked. undeclaredTargetDependency compares imports with Package.swift. unusedTargetDependency exists (RuleIdentifier.swift:81).

**Change.** Cycles in the type and module dependency graphs. For module structure, take SwiftProjectLint's `undeclaredTargetDependency` and `unusedTargetDependency` (imports compared with `Package.swift`). Its `circularDependency` finds only two-type cycles through stored properties and parameters, and `layerDependency` checks folder layers only when `architectural_layers` is configured. Use indexstore-db for full type- and function-level cycles.

### 9. §7.4 — contradiction, confirmed

> take them from the adapter (§7.15) rather than reimplementing. SwiftStats computes only the concurrency-shape counts itself.

**Issue.** Several markers in the list below this sentence have no SwiftProjectLint rule. Implicitly unwrapped optionals: forceUnwrap visits only `ForceUnwrapExprSyntax`, and no rule reports IUO declarations. `precondition` is deliberately not reported. `fatalError` and `preconditionFailure` share one rule, `unconditionalTrap`, which skips `required init?(coder:)`; they can be told apart only by parsing the message. The `unsafe` expression keyword is not detected: unsafeMemoryAPI covers `Unsafe*Pointer`, `OpaquePointer`, `Unmanaged`, `unsafeBitCast` and the `withUnsafe…` calls. todoComment also counts `HACK`. So SwiftStats has to compute more than the concurrency-shape counts.

**Evidence.** Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/CodeQuality/Visitors/ForceUnwrapVisitor.swift:13; UnconditionalTrapVisitor.swift:5-12, :24 (trapFunctions ["fatalError","preconditionFailure"]), :36 (coder exemption); MemoryManagement/Visitors/UnsafeMemoryAPIVisitor.swift:1-37 (visits IdentifierTypeSyntax and FunctionCallExprSyntax only); TodoCommentVisitor.swift (markers TODO, FIXME, HACK).

**Verifier.** The visitors match the finding. ForceUnwrapVisitor visits only ForceUnwrapExprSyntax, and no rule reports IUO declarations. UnconditionalTrapVisitor covers only fatalError and preconditionFailure, deliberately excludes precondition, and skips `required init?(coder:)`; the callee name appears in the message. UnsafeMemoryAPIVisitor visits only IdentifierTypeSyntax and FunctionCallExprSyntax, and nothing handles UnsafeExprSyntax. TodoCommentVisitor's markers include HACK. So the PRD's claim that SwiftStats computes only the concurrency-shape counts is wrong.

**Change.** Most of these are already SwiftProjectLint rules (`forceUnwrap`, `forceTry`, `forceCast`, `unconditionalTrap`, `uncheckedSendable`, `nonisolatedUnsafe`, `unsafeMemoryAPI`, `todoComment`); take them from the adapter (§7.15). SwiftStats computes the rest itself: implicitly unwrapped optionals, `precondition`, the `unsafe` keyword, and the concurrency-shape counts. `unconditionalTrap` covers `fatalError` and `preconditionFailure` together and skips `required init?(coder:)`; split it by the callee named in the message if separate counts are wanted.

### 10. §7.5 — misleading, confirmed

> (SwiftProjectLint `couldBePrivate`, `couldBePrivateMember`, `protocolCouldBePrivate`), as a count and as a share of each access level

**Issue.** The three rules flag only declarations with no explicit access modifier (implicit `internal`) that are used in one file. couldBePrivate covers top-level types, couldBePrivateMember covers functions and properties, and protocolCouldBePrivate covers protocols. None of them finds `public` that could be `internal`, so a share for each access level cannot come from them. They also hold back where narrowing would hide a pure function from tests (PropertyTestCandidacy).

**Evidence.** Docs/rules/could-be-private.md ("Top-level type declarations … with no explicit access modifier"); Docs/rules/could-be-private-member.md:21-22 ("Does **not** flag members with explicit access modifiers"); Docs/rules/protocol-could-be-private.md; PropertyTestCandidacy.swift:46-55.

**Verifier.** The three rule docs say they flag only declarations with no explicit access modifier: top-level types, members, and protocols respectively. They skip explicit public, internal and so on, so no access-level share beyond implicit internal can come from them. One correction to the finding's rationale: the rules do not hold back on property-test candidates. could-be-private-member.md says "The finding is **not suppressed**". They add a caveat to the message instead. The proposed change does not depend on that claim and is accurate.

**Change.** **Over-exposed declarations**: implicitly `internal` declarations used only in their own file (SwiftProjectLint `couldBePrivate` for types, `couldBePrivateMember` for functions and properties, `protocolCouldBePrivate`), as a count and as a share of implicitly internal declarations. Over-exposed `public` API needs indexstore-db (§7.6) or Periphery (§7.6a).

### 11. §7.15 — misleading, confirmed

> these are built on SwiftEffectInference's `PurityInferrer` (via `PropertyTestCandidacy`) … the reverse points to version skew between the two tools' copies of SwiftEffectInference

**Issue.** Two problems. (1) pureFunctionCandidate and pureMutatorCandidate go through PropertyTestCandidacy, which lives in SwiftProjectLintVisitors and calls PurityInferrer. pureClosureCandidate calls PurityInferrer.isPure directly. (2) The "reverse" case has a built-in cause besides version skew. PropertyTestCandidacy accepts `.pureButPartial` (throwing) functions as candidates. SwiftEffectInference's `inferredEffect(for:)` returns nil for any function with a `throws` clause, so it never calls those pure. Neither the JSON nor pbt-seeds says whether a candidate is partial, so SwiftStats has to check the `throws` clause itself before blaming skew. SwiftProjectLint pins SwiftEffectInference by revision, so skew can be checked directly.

**Evidence.** Packages/SwiftProjectLintVisitors/Sources/SwiftProjectLintVisitors/PropertyTestCandidacy.swift:84-117 (`.pure` and `.pureButPartial` both candidates); SwiftEffectInference/Sources/SwiftEffectInference/PurityInferrer.swift:29-39, :293-300, :341; Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/Testability/Visitors/PureClosureCandidateVisitor.swift:51; PureFunctionCandidateVisitor.swift:43; PureMutatorCandidateVisitor.swift:41; SwiftProjectLint Package.swift:84-87 (SEI pinned by `revision:`).

**Verifier.** PureClosureCandidateVisitor holds its own `PurityInferrer()` and calls `isPure(closure)` directly. The function and mutator visitors go through PropertyTestCandidacy. PropertyTestCandidacy.candidate accepts both `.pure` and `.pureButPartial`. In SwiftEffectInference, `inferredEffect`/`isPure` return nil/false via `wholeDomainRefutation`, which returns `.declaredThrows` for any throws clause. Package.swift pins SwiftEffectInference by `revision:`. Minor nuance: the candidate's message text does say "partial", but no structured field does. This does not affect the proposed change.

**Change.** **Not** an independent purity opinion: these are built on SwiftEffectInference's `PurityInferrer` (function and mutator candidates through SwiftProjectLint's `PropertyTestCandidacy`; closure candidates call it directly), with filters for whether the function is a sensible property-test candidate. A function SwiftEffectInference calls pure but SwiftProjectLint doesn't nominate shows a candidacy filter at work. The reverse is expected for throwing functions: SwiftProjectLint nominates them as partial candidates and SwiftEffectInference does not call them pure. Any other reverse case points to version skew. Record the SwiftEffectInference revision SwiftProjectLint pins.

### 12. §14 Q8 — misleading, confirmed

> should SwiftProjectLint's census rules leave its human-facing reports entirely and stay only in its JSON and `pbt-seeds` output?

**Issue.** Part of this is already done. Since commit 1747b3a3 (2026-07-26) the text report has kept the three census rules out of the listing, only counting them in a footer; `--categories testability` brings them back. The HTML report still lists them one per line. JSON and CSV stay complete on purpose. So the open question is narrower than written.

**Evidence.** Sources/CLI/SwiftProjectLintCLI.swift:198-238 ("Only `text` collapses"); Sources/Core/Export/HTMLFormatter.swift (no CandidateInventory use); git show 1747b3a3 "Stop enumerating the property-test candidate census in the text report".

**Verifier.** Commit 1747b3a3 (2026-07-26) is titled "Stop enumerating the property-test candidate census in the text report". SwiftProjectLintCLI.render collapses census rules only for `text` and only when `testability` is not selected. HTMLFormatter makes no use of CandidateInventory. JSON and CSV stay complete on purpose.

**Change.** **Census rules in SwiftProjectLint's reports:** its text report already counts the census rules without listing them (since July 2026). Once SwiftStats exists, should the HTML report do the same, and should the census counts leave the human-facing summary entirely, staying only in JSON, CSV and `pbt-seeds`?

### 13. §7.15 — gap, confirmed

> SwiftStats reads the JSON

**Issue.** The JSON leaves out per-function facts that SwiftProjectLint computes and SwiftStats would want. LintIssue has `role` (comparator, predicate, …), `effect` (with provenance), `testReachability`, `requires` (missing Equatable conformances) and `mutates`. These reach only the pbt-seeds manifest (as `kind`, `role`, `restriction`, `effect`, `requires`, `mutates`), or the `Core` library product. The JSON also has no field for nested packages that were skipped, while pbt-seeds has `skippedPackages`.

**Evidence.** Packages/SwiftProjectLintModels/Sources/SwiftProjectLintModels/LintIssue.swift:38-74; Sources/Core/Export/CodableLintIssue.swift (only symbol added); Sources/Core/Export/PBTSeed.swift:9-76; PBTSeedManifest.swift:5-19 (skippedPackages); Package.swift:26-30 (`.library(name: "Core")`).

**Verifier.** LintIssue has role, effect, testReachability, requires and mutates. CodableLintIssue adds only symbol. PBTSeed carries role, restriction, effect, requires and mutates, and PBTSeedManifest has skippedPackages. Core is a library product. One practical note: getting both outputs means running SwiftProjectLint twice, once with `--format json` and once with `--format pbt-seeds`, and pbt-seeds includes only seed rules that have a symbol.

**Change.** SwiftStats reads the JSON for every finding and the `pbt-seeds` manifest for seed facts the JSON omits (`kind`, `role`, `restriction`, `effect`, `requires`, `mutates`, `skippedPackages`), joining the two on file, line and symbol.

### 14. §7.15 — gap, partly

> maps each finding to a function by line range, the same way as SwiftLint and coverage results

**Issue.** Cross-file rules report one issue with several `locations`, for example circularDependency, duplicateStructShape and parallelEnumShape. A single finding can therefore land in several functions or files. The PRD does not say whether such a finding counts once or once per location. CSV writes one row per location, so counts from CSV and JSON differ.

**Evidence.** Packages/SwiftProjectLintModels/Sources/SwiftProjectLintModels/LintIssue.swift:22-31 ("supports issues that span multiple files or lines"); CSVFormatter.swift:20-32 (row per location); CodableLintIssue.swift:17.

**Verifier.** The schema does allow several locations (LintIssue.locations), and CSV writes one row per location. But the cited rules do not emit multi-location issues. CircularDependencyVisitor, DuplicateStructShapeVisitor and ParallelEnumShapeVisitor each call addIssue with a single filePath and lineNumber, once per member. Every addIssue/LintIssue construction in the rule packages passes one location. The roadtest lint-report.json has 0 of 873 issues with more than one location. So the proposed example is wrong, and the JSON/CSV count difference does not arise today.

**Change.** Add: The JSON allows a finding to carry several `locations`, though no current rule emits more than one (cross-file rules such as `duplicateStructShape` report once per member). If one does, store it once, link it to each function it names, and count it once in roll-ups.

### 15. §6.4 — suggestion, confirmed

> on SwiftProjectLint's own code, 76% of findings were census items (460 pure functions, 204 pure closures)

**Issue.** The figure can be traced, but the PRD gives no source or date, and the repo has two versions of it. The CandidateInventory doc comment says 876 findings, 664 candidates, 460 functions and 204 closures. The road test write-up says 884 findings, 672 candidates, 464 functions and 208 closures. Both come to 76%. The buried defect was a Lossy Struct Rebuild finding, at line 1438 of a 1768-line report.

**Evidence.** Sources/Core/Export/CandidateInventory.swift:5-13; Docs/roadtest/README.md:977-985; commit 1747b3a3 (2026-07-26).

**Verifier.** CandidateInventory.swift gives 876 findings, of which 664 are candidates (460 functions, 204 closures), which is 76%. Docs/roadtest/README.md:977-985 gives 884 findings, 672 candidates, 464 functions and 208 closures, also 76%. It says the Lossy Struct Rebuild finding sat at line 1438 of a 1768-line report. Commit 1747b3a3 is dated 2026-07-26.

**Change.** Motivation: in a July 2026 road test on SwiftProjectLint's own code, 76% of findings were census items (460 pure functions and 204 pure closures out of 876 findings; see `CandidateInventory.swift` and `Docs/roadtest/README.md`). They buried a real defect, a `lossyStructRebuild` finding at line 1438 of a 1768-line report, which went unread.

### 16. §7.15 — suggestion, partly

> **Idempotency:** `idempotencyViolation`, `missingIdempotencyKey`, `nonIdempotentInRetryContext`, and the related replay rules

**Issue.** The 'related replay rules' are not named. Also, idempotencyViolation checks only functions that declare an effect with `@lint.effect`, and unannotated callees are silent. On an unannotated package, a zero count means 'not checked', not 'clean'.

**Evidence.** RuleIdentifier.swift:225-232 (onceContractViolation, unannotatedInStrictReplayableContext, tupleEqualityWithUnstableComponents, nonIdempotentActionName); Docs/rules/idempotency-violation.md ("Unannotated callees are silent").

**Verifier.** The idempotency category holds exactly those seven rules (RuleIdentifier+Category.swift:130-132). idempotencyViolation says unannotated callees are silent. Five of the seven depend on annotations. But nonIdempotentInRetryContext, onceContractViolation and unannotatedInStrictReplayableContext key off `@lint.context`, not `@lint.effect`. tupleEqualityWithUnstableComponents and nonIdempotentActionName are shape-based and need no annotation. So "declared `@lint.effect` contracts" is too narrow.

**Change.** **Idempotency:** `idempotencyViolation`, `missingIdempotencyKey`, `nonIdempotentInRetryContext`, `onceContractViolation`, `unannotatedInStrictReplayableContext`, `tupleEqualityWithUnstableComponents`, `nonIdempotentActionName`. The first five check `@lint.effect` / `@lint.context` annotations, so report them alongside the count of annotated functions; zero on an unannotated package means not checked. The last two are shape-based and run everywhere.

### 17. §7.15 — gap, partly

> Also consumed by other sections: risk markers (§7.4), over-exposure (§7.5), module structure (§7.6), assertion-free tests (§7.8), duplicated knowledge (§7.12)

**Issue.** Several existing rules would obviously feed SwiftStats but are not mentioned. Defects: lossyStructRebuild (the defect from the §6.4 story), lossyRoundTrip, subsumedCondition, contradictedClockDeterminism, unreachableEffectClosure, missingEquatableOnStateType, catchWithoutHandling, discardedTryResult, potentialRetainCycle. Concurrency escape hatches for §7.4: preconcurrencyImport, preconcurrencyConformance, retroactiveConformance, taskDetached, dispatchSemaphoreInAsync. A census: impureClosureInventory (impure closures grouped by why), the natural partner of pureClosureCandidate. For §7.6: unusedTargetDependency. For dead code §7.6a: unusedProtocolAbstraction, unusedProtocolRequirement (opt-in). For §7.5 documentation coverage: missingDocumentation (public declarations only by default), which under §7.15's source-of-truth rule should be the source.

**Evidence.** RuleIdentifier.swift:81, 106, 118, 128-129, 110, 156, 127, 207, 244, 64-65, 88, 265-292; Docs/rules/impure-closure-inventory.md; Docs/rules/missing-documentation.md; LintConfiguration.swift:125 (unusedProtocolRequirement opt-in).

**Verifier.** All the named rules exist in RuleIdentifier, and unusedProtocolRequirement is opt-in. The overstatement is missingDocumentation. DocumentationVisitor checks only `public` struct, class and function declarations; it skips `open`, enums, protocols, actors and properties. It also reports only the missing ones, so it cannot supply a coverage denominator, and it should not be described as the source for public-API documentation coverage. Also, §7.6a names Periphery as its primary source, so the protocol rules can only supplement it.

**Change.** Add to the defect list: **Correctness:** `lossyStructRebuild`, `lossyRoundTrip`, `subsumedCondition`, `contradictedClockDeterminism`, `catchWithoutHandling`, `discardedTryResult`, `potentialRetainCycle`. Add to §7.4 escape hatches: `@preconcurrency` (`preconcurrencyImport`, `preconcurrencyConformance`), `@retroactive` (`retroactiveConformance`), `Task.detached` (`taskDetached`). Add as census: `impureClosureInventory` (closures refused as pure, grouped by reason). Use `unusedTargetDependency` in §7.6 and `unusedProtocolAbstraction` / `unusedProtocolRequirement` (opt-in) alongside Periphery in §7.6a. In §7.5, use `missingDocumentation` as a cross-check only: it flags undocumented `public` structs, classes and functions, so SwiftStats still counts the documented and undocumented public declarations itself.

**Checked and correct:**

- Every rule name the PRD gives exists in RuleIdentifier.swift with that exact spelling, except swiftLintSuppression and swiftProjectLintSuppression: forceUnwrap, forceTry, forceCast, unconditionalTrap, uncheckedSendable, nonisolatedUnsafe, unsafeMemoryAPI, todoComment, couldBePrivate, couldBePrivateMember, protocolCouldBePrivate, circularDependency, layerDependency, undeclaredTargetDependency, testMissingAssertion, testMissingExpect, testMissingRequire, duplicateStructShape, duplicateEnumMapping, parallelEnumShape, scatteredEnumMapping, parallelListDrift, pureFunctionCandidate, pureClosureCandidate, pureMutatorCandidate, missingEquatableOnPureResult, extractableTotalKernel, globalMutableState, nonInjectedNondeterminism, singletonUsage, directInstantiation, fatProtocol, godViewModel, singleImplementationProtocol, lawOfDemeter, actorReentrancy, fireAndForgetTask, swallowedTaskError, missingCancellationCheck, unboundedTaskGroup, blockingIOOnMainActor, idempotencyViolation, missingIdempotencyKey, nonIdempotentInRetryContext (missingIdempotencyKey is implemented: MissingIdempotencyKeyVisitor.swift).
- CandidateInventory exists (Sources/Core/Export/CandidateInventory.swift). It holds pureFunctionCandidate, pureClosureCandidate and pureMutatorCandidate. They are counted but not listed in the text report and are kept in JSON, CSV and pbt-seeds.
- §6.4 wording matches CandidateInventory: census = nominates, nothing to do per item; extractableTotalKernel is a defect ('pure logic trapped in an impure method', a claim that can be wrong and is worth reading each time).
- The 76% / 460 / 204 figures trace to CandidateInventory.swift:5-8 (876 findings, 664 candidates) and commit 1747b3a3 (2026-07-26); Docs/roadtest/README.md:977-979 gives a nearby 884/672/464/208, also 76%.
- The real defect that went unread in the road test is documented (a Lossy Struct Rebuild finding, at line 1438 of a 1768-line report).
- Output formats are text, json, html, csv and pbt-seeds (Sources/CLI/OutputFormat.swift). swift-infer reads the pbt-seeds manifest via `discover --seeds` (SwiftInferProperties Sources/SwiftInferCore/SeedManifest.swift, SwiftInferCommand.Discover+SeedFocus.swift).
- JSON findings include `category` and `severity`, and a single line number per location that can be mapped into a function's range.
- pureFunctionCandidate and pureMutatorCandidate go through PropertyTestCandidacy, which calls SwiftEffectInference's PurityInferrer().verdict(for:) (PropertyTestCandidacy.swift:102-117; PropertyTestCandidacy+Mutator.swift:73).
- SwiftProjectLint links SwiftEffectInference as a package dependency, pinned by revision (Package.swift:84-87), so 'the two tools' copies of SwiftEffectInference' is accurate.
- Findings carry no census/defect kind in any machine output (CodableLintIssue, PBTSeed).
- IUOs are not reported by any SwiftProjectLint rule; precondition is deliberately not reported; fatalError and preconditionFailure share unconditionalTrap (UnconditionalTrapVisitor.swift).
- swiftlintSuppression covers swiftlint:disable plus :next, :this and :previous; swiftprojectlintSuppression covers swiftprojectlint:disable plus :next and :this, so the suppression-density metric is supported once the names are fixed.
- undeclaredTargetDependency compares imports with Package.swift target dependencies at T0 (Docs/rules/undeclared-target-dependency.md).
- parallelListDrift is enabled by default (not in optInRules).
- pureMutatorCandidate, missingEquatableOnPureResult and extractableTotalKernel all seed pbt-seeds (PBTSeedsFormatter.swift:146-160), consistent with §7.15 and Q8 mentioning pbt-seeds.

## SwiftInferProperties and SwiftPropertyLaws

### 1. §7.11 — error, partly

> Templates that fired (idempotence, round-trip, commutativity, monotonicity, count-invariance, reduce-equivalence, algebraic structure)

**Issue.** Three of the seven names are not template names. `count-invariance` and `reduce-equivalence` are TestLifter detector patterns. When promoted they are filed under the templates `invariant-preservation` and `associativity`. `algebraic structure` is a RefactorBridge / suggest-refactors cluster shape (`algebraicStructure`), not a template. The algebraic templates are `associativity`, `identity-element`, `inverse-pair` and `commutativity`. The list also leaves out most of the catalogue: about 58 distinct template strings are emitted, including `codable-round-trip`, `dual-style-consistency`, `idempotence-lifted`, `involution`, `homomorphism`, `differential-equivalence`, `predicate`, `role-postcondition`, `composition`, `determinism`, `equivalence-class` and others. Interaction-invariant families (conservation, cardinality, ...) sit in a separate list.

**Evidence.** SwiftInferProperties/Sources/SwiftInferCore/TemplateName.swift:21-200 (canonical enum: round-trip, codable-round-trip, idempotence, commutativity, associativity, idempotence-lifted, dual-style-consistency, monotonicity, involution, binary-idempotence, homomorphism, ..., inverse-pair, identity-element, composition, invariant-preservation, replay-idempotence). Sources/SwiftInferCLI/InteractiveTriage+AcceptM5.swift:9-12 ("countInvariance → invariant-preservation, reduceEquivalence → associativity"). Sources/SwiftInferTestLifter/LiftedCounterSignal.swift:12. Sources/SwiftInferCLI/SwiftInferCommand.SuggestRefactors.swift:273 ("algebraic-structure cluster"). Grep of `templateName: "…"` literals across Sources gives about 58 distinct names.

**Verifier.** Verified: TemplateName.swift has round-trip, codable-round-trip, idempotence-lifted, dual-style-consistency, inverse-pair, identity-element, invariant-preservation and others. InteractiveTriage+AcceptM5.swift:9-12 maps countInvariance to invariant-preservation and reduceEquivalence to associativity. `algebraicStructure` is a ClusterShape in RefactorClusterAnalyzer.swift:53 and SuggestRefactors.swift:273. The literal grep finds 56 distinct `templateName:` strings (the finding says about 58). Suggestion.templateName and SemanticIndexEntry.templateName are plain Strings. One error in the proposed text: it sends the reader to 'see RefactorBridge below' for the algebraic-structure cluster. That cluster comes from RefactorClusterAnalyzer, reported by `swift-infer suggest-refactors`. RefactorBridge is a different mechanism: Option B conformance proposals in discover --interactive.

**Change.** - Template name, stored as SwiftInferProperties writes it (a free string, not a fixed enum; about 60 exist and the list grows). Common ones: `idempotence`, `round-trip`, `commutativity`, `associativity`, `identity-element`, `inverse-pair`, `monotonicity`, `invariant-preservation`, `dual-style-consistency`. Test-derived patterns (count-invariance, reduce-equivalence) arrive under `invariant-preservation` and `associativity`. "Algebraic structure" is not a template. It is a per-type cluster that `swift-infer suggest-refactors` reports.

### 2. §7.11 — error, partly

> Tier (Strong / Possible)

**Issue.** The tier set is wrong and incomplete. `Tier` has six cases: Verified, Strong, Likely, Possible, Suppressed, Advisory. The index and the decision records store the score-derived label: Strong ≥75, Likely 40–74, Possible 20–39. Possible is hidden unless `--include-possible` is passed, and Suppressed never surfaces. Verified means a Strong suggestion whose `swift-infer verify` run passed. It is only set at discover render time and in `DecisionRecord.tier`. Advisory marks unscored, documentation-only rows (`equivalence-class`, `consumer-producer-chain`, synthesized `determinism`). The same problem affects §1 and the §8 "Untested property" row, which key on Strong alone.

**Evidence.** SwiftInferProperties/Sources/SwiftInferCore/Tier.swift:7-120 (cases verified/strong/likely/possible/suppressed/advisory; init(score:) thresholds 75/40/20; isVisibleByDefault false for possible and suppressed). Sources/SwiftInferCore/SemanticIndexEntry.swift:50-54 (tier string "Strong"/"Likely"/"Possible"/"Suppressed"). Sources/SwiftInferCLI/SwiftInferCommand.Query.swift ("--tier: Strong, Likely, Possible, Suppressed, or Advisory").

**Verifier.** Tier.swift confirms six cases (verified, strong, likely, possible, suppressed, advisory), thresholds 75/40/20, Possible hidden by default in discover, Verified set only by promotion and in DecisionRecord.tier, and Advisory for equivalence-class, consumer-producer-chain and the synthesized determinism row. The proposed change gets the JSON adapter wrong, though. `swift-infer index` includes Possible by default: SwiftInferCommand.Index.swift:155-165 and :235-244 use `possible.resolved(otherwise: true)`, and you pass `--no-include-possible` to drop them. So 'Possible rows only appear when the adapter runs with --include-possible' is false for the index path that §9 relies on.

**Change.** - Tier: Strong / Likely / Possible (score-derived), plus Advisory for unscored rows. Store the score too. `swift-infer index` includes Possible rows by default, but `discover` hides them unless run with `--include-possible`, so record which one ran and with which flags. Treat Verified (Strong and passed `swift-infer verify`) as a separate flag, not a tier.

In §8, change "Untested property" to: "Strong- or Likely-tier candidate (not Advisory), no property test".

### 3. §7.11 — error, confirmed

> Decision status from `.swiftinfer/decisions.json` (suggested / accepted / rejected / suppressed)

**Issue.** The file path is right but the status values are wrong. `Decision` has four stored values: `accepted`, `acceptedAsConformance`, `rejected`, `skipped`. "Suggested" is not stored; it is the absence of a record. "Suppressed" is not a decision. It is either a tier (score below 20 or vetoed, never shown) or a source-comment marker `// swiftinfer: skip <hash>`. Records are keyed by suggestion identity hash, not by file or function. The v2 interaction surface has its own `.swiftinfer/interaction-decisions.json`.

**Evidence.** SwiftInferProperties/Sources/SwiftInferCore/Decisions.swift:9-41 (enum Decision: accepted, acceptedAsConformance, rejected, skipped) and :62-97 (DecisionRecord.identityHash, template, scoreAtDecision, tier, decision, timestamp). Sources/SwiftInferCLI/DecisionsLoader.swift:26-27. Sources/SwiftInferCore/SkipMarkerScanner.swift:1-17.

**Verifier.** Decisions.swift:36-41 defines Decision as accepted, acceptedAsConformance, rejected and skipped. DecisionRecord is keyed by identityHash and holds template, scoreAtDecision, tier, decision, timestamp and signalWeights. 'Suppressed' is a Tier case, plus the `// swiftinfer: skip <hash>` marker in SkipMarkerScanner.swift. 'Suggested' is never stored. One join detail to keep in mind: decisions.json stores the hash without the `0x` prefix, while index.json uses the `0x` display form.

**Change.** - Decision status from `.swiftinfer/decisions.json`, joined by identity hash: undecided (no record) / accepted / acceptedAsConformance / rejected / skipped. Count `// swiftinfer: skip <hash>` markers separately as suppressed.

### 4. §7.11 — gap, confirmed

> Pair partner for two-function properties (e.g. `encode` ↔ `decode`), stored as a link

**Issue.** The JSON output does not carry a resolvable partner. `.swiftinfer/index.json` writes `secondaryFunctionName` only for `round-trip`, `differential-equivalence` and `emptiness-agreement`. It holds a bare display name such as `decode(_:)`, with no file, line or type. The other two-function templates (`inverse-pair`, `dual-style-consistency`, `identity-element` pairings, `homomorphism`) record only the primary function. The full pair (two `Evidence` rows, each with file:line) is available only in memory, by linking the library.

**Evidence.** SwiftInferProperties/Sources/SwiftInferCLI/SwiftInferCommand.Index+Projection.swift:103-105 (location from evidence.first only), :176-208 (twoFunctionTemplates = round-trip, differential-equivalence, emptiness-agreement; secondaryFunctionName = evidence[1].displayName). Sources/SwiftInferCore/SemanticIndexEntry.swift:96-104.

**Verifier.** In SwiftInferCommand.Index+Projection.swift, buildEntry takes location from evidence.first only, and twoFunctionTemplates is exactly round-trip, differential-equivalence and emptiness-agreement. secondaryFunctionName is evidence[1].displayName, a bare name with no location. The comment there also says dual-style-consistency recovers its pair from a hand-maintained table because its index entry records only one name.

**Change.** - Pair partner for two-function properties (e.g. `encode` ↔ `decode`), stored as a link. From the index JSON this is a bare name, and only for round-trip, differential-equivalence and emptiness-agreement. SwiftStats resolves it to a function record by name within the primary's type and file, and records the link as unresolved when that is ambiguous. Partners for other templates need the library adapter, which sees both evidence rows.

### 5. §7.11 — gap, confirmed

> Property-test candidates (T0, SwiftInferProperties)

**Issue.** The section does not say what identity and location a suggestion carries, which the identity resolver (§6.1) needs. Each index entry has an `identityHash` (`0x` + 16 hex digits; SHA-256 of template + canonical signature). It is stable across file moves but changes when the signature changes. It also has `location` as `file:line` of the first evidence only, with no column, no end line and no USR, plus `primaryFunctionName`, `typeName` and `qualifiedTypeName`. So suggestions map to functions by line falling inside a function's range, as with SwiftLint. `subjectFingerprint` gives a body hash that can serve the §9 caching rule.

**Evidence.** SwiftInferProperties/Sources/SwiftInferCore/SuggestionIdentity.swift:4-17. Sources/SwiftInferCore/SemanticIndexEntry.swift:28-63, 187-197. Sources/SwiftInferCore/BodySignals.swift:70 (SourceLocation.description = "file:line"). No USR appears anywhere in Suggestion or SemanticIndexEntry.

**Verifier.** Templates build SuggestionIdentity from template plus canonical signature, with no file path (for example `"associativity|" + canonicalSignature`). The display form is 0x plus 16 hex characters. SemanticIndexEntry has location as `file:line` from the first evidence (SourceLocation.description), plus primaryFunctionName, typeName, qualifiedTypeName and subjectFingerprint. There is no USR field. Lifted suggestions hash template and callee names instead, which is still location-independent.

**Change.** Add: "Each suggestion carries an identity hash (template + canonical signature; stable across moves, changes when the signature changes) and the file:line of its first function. No USR. SwiftStats maps it by line into the function's source range and keeps the hash as the join key for decisions and generated tests."

### 6. §7.8 — contradiction, confirmed

> **Generated** tests (e.g. `Tests/Generated/SwiftInfer/`), reported separately and excluded from ratios by default

**Issue.** The example path is stale, and it contradicts the rule above it ("use the test targets declared in `Package.swift`"). Since #414, accepted stubs go to `<test-target-dir>/Generated/SwiftInfer/<TemplateName>/<Suite>.swift`, for example `Tests/FooTests/Generated/SwiftInfer/...`, or to `--output-dir`. `Tests/Generated/` is only the fallback, and SwiftInferProperties itself warns that no SwiftPM target builds it, so it is never inside a declared test target. Other generated outputs are missed: `.../Generated/SwiftInferRefactors/<TypeName>/<Protocol>.swift`, `.../Generated/SwiftInferTraces/`, `Tests/Generated/SwiftInfer/Scaffolds.generated.swift`, and SwiftPropertyLaws' `Tests/<Target>Tests/PropertyLawTests.generated.swift`. Detection by file header is more reliable than by path.

**Evidence.** SwiftInferProperties/Sources/SwiftInferCLI/GeneratedStubDestination.swift:3-21, 62-101 (generatedRoot = chosen test-target directory + "Generated"; legacy Tests/Generated is "built by nothing"). Sources/SwiftInferCLI/SwiftInferCommand.Discover.swift:186-190, 245-258. Sources/SwiftInferCLI/InteractiveTriage+StubFile.swift:144-169 (header lines "// Auto-generated by `swift-infer discover --interactive` — do not edit.", "// Source: <path>:<line>", "// Suggestion identity: 0x…", "// Template: …"). SwiftPropertyLaws/Plugins/PropertyLawDiscoveryPlugin/plugin.swift:62-69. SwiftPropertyLaws/Sources/PropertyLawDiscoveryTool/GeneratedFileEmitter.swift:101 ("// GENERATED by PropertyLawDiscoveryPlugin — DO NOT EDIT").

**Verifier.** GeneratedStubDestination.swift:3-21 records that legacy Tests/Generated is built by nothing (#414), and resolve() chooses `<test target dir>/Generated` or --output-dir. InteractiveTriage+StubFile.swift:145 writes the 'Auto-generated by `swift-infer discover --interactive`' header with Source, Suggestion identity and Template lines. The SwiftPropertyLaws plugin writes Tests/<Target>Tests/PropertyLawTests.generated.swift with the header '// GENERATED by PropertyLawDiscoveryPlugin — DO NOT EDIT'. Trace replays (Tests/Generated/SwiftInferTraces) and Scaffolds.generated.swift have different headers, but they still go to the legacy Tests/Generated location, so the proposal's 'unbuilt' clause covers them.

**Change.** - **Generated** tests, found by their header rather than their folder: SwiftInferProperties stubs start with "// Auto-generated by `swift-infer discover --interactive`" (usually under `<test target>/Generated/SwiftInfer/`), and SwiftPropertyLaws files start with "// GENERATED by PropertyLawDiscoveryPlugin" (`PropertyLawTests.generated.swift`). Reported separately and excluded from ratios by default. Files under the legacy `Tests/Generated/` are in no test target and never run; report them as unbuilt.

### 7. §7.8 — gap, partly

> **Property-based** tests (detected via the property-testing library's API, e.g. swift-property-based)

**Issue.** No concrete entry points are named, and the obvious one misses most property tests in these repos. swift-property-based's entry point is `propertyCheck(count:input:perform:)`, called inside a Swift Testing `@Test`. Neither SwiftPropertyLaws' `check<Protocol>PropertyLaws(...)` nor SwiftInferProperties' generated stubs call `propertyCheck`. Both run through `SwiftPropertyBasedBackend().check(...)` from PropertyLawKit. There are also two attribute forms on production types or functions, outside test targets: `@PropertyLawSuite` (plus `@ValueSemanticTests`, `@DefensiveCopyTests`, `@StableIdentityTests`, `@InteractionInvariantTests`) and SwiftInfer's `@CheckProperty(...)`. swift-property-based precondition-checks for a Swift Testing context, so the XCTest column will always be empty for this library.

**Evidence.** swift-property-based/Sources/PropertyBased/PropertyCheck.swift:104-113 (propertyCheck; precondition Test.Case.current != nil), PropertyCheck+Pack.swift (variadic overloads), FixedSeedTrait.swift:65, EnableShrinkTrait.swift:40-48, MaximumAttemptsTrait.swift:35. grep finds no `propertyCheck(` in SwiftPropertyLaws/Sources or in SwiftInferProperties' emitters. SwiftPropertyLaws/Sources/PropertyLawKit/Internal/Backends/SwiftPropertyBasedBackend.swift:6,14. SwiftInferProperties/Sources/SwiftInferTemplates/LiftedTestEmitter+SharedStubShape.swift:26. SwiftPropertyLaws/Sources/PropertyLawMacro/PropertyLawMacro.swift:41-190. SwiftInferProperties/Sources/SwiftInferMacro/CheckProperty.swift:67-83.

**Verifier.** Verified: propertyCheck(count: = 100, ...) has a Test.Case.current precondition. Neither SwiftPropertyLaws nor SwiftInferProperties' emitters call propertyCheck; the generated stubs use SwiftPropertyBasedBackend(). @PropertyLawSuite and its sibling macros exist, and so does @CheckProperty. Two parts of the proposed change are overstated. (1) 'These sit on production code': CheckProperty.swift says it is 'applied in client test targets'. @PropertyLawSuite expands to a peer @Suite/@Test, so it needs Testing wherever it sits. It can be in any target, not necessarily production. (2) 'These libraries need Swift Testing, so expect no XCTest property tests' holds for swift-property-based but not for SwiftPropertyLaws. Its check functions are `async throws` and throw PropertyLawViolation on failure (PropertyLawSuiteRunner.swift:18), so they work from an XCTest method. Also, the kit's check functions take `options: LawCheckOptions`, not `count:`.

**Change.** - **Property-based** tests: a test that calls `propertyCheck(` (swift-property-based; Swift Testing only), a `check…PropertyLaws(` function (SwiftPropertyLaws; usable from Swift Testing or XCTest, since it throws on violation), or `SwiftPropertyBasedBackend().check(` (generated stubs). Count the attribute forms as well: `@PropertyLawSuite` and its sibling macros, and `@CheckProperty(...)`. These expand to tests wherever they are attached, so scan every target for them, not only test targets. Record the trial count where one is given (`count:` for propertyCheck, default 100; `options:` for the kit).

### 8. §7.11 — gap, confirmed

> Whether a matching property test exists

**Issue.** No matching rule is given. A rule exists for generated tests: every SwiftInfer stub carries `// Suggestion identity: 0x…` and `// Source: <path>:<line>`, which join exactly to the index's `identityHash` and `location`. An `accepted` decision also implies a stub was written. A hand-written test can only be matched heuristically, by the function under test appearing inside a property-test body. `swift-infer verify` results in `.swiftinfer/verify-evidence.json` (outcome `measured-bothPass` etc., keyed by identity hash) add a third state: checked by the tool but with no test in the repo.

**Evidence.** SwiftInferProperties/Sources/SwiftInferCLI/InteractiveTriage+StubFile.swift:144-169. Sources/SwiftInferCore/VerifyEvidence.swift:26-30, 124. Sources/SwiftInferCLI/VerifyEvidenceStore.swift:32.

**Verifier.** The stub header carries '// Suggestion identity: <0x display>' and '// Source: path:line' (InteractiveTriage+StubFile.swift:145-169). VerifyEvidenceOutcome has the values measured-bothPass, measured-edgeCaseAdvisory, measured-defaultFails, measured-error and architectural-coverage-pending, stored in .swiftinfer/verify-evidence.json and keyed by identityHash (normalized, no 0x). The stub line and the index both use the 0x form, so the exact match in the proposal works. Strip the 0x to join to verify-evidence.

**Change.** - Whether a matching property test exists: exact for generated tests (the stub's `// Suggestion identity:` line matches the suggestion's hash), heuristic for hand-written ones (the function is called inside a property-test body). Also record the `swift-infer verify` outcome from `.swiftinfer/verify-evidence.json` when present.

### 9. §7.11 — misleading, confirmed

> Per type: suggested conformances (RefactorBridge)

**Issue.** RefactorBridge proposals have no machine-readable output. `RefactorBridgeOrchestrator.proposals(...)` runs only inside `discover --interactive`, where it feeds the Option B prompt, and is never written to JSON. A trace exists only after acceptance: an `acceptedAsConformance` decision and a file `.../Generated/SwiftInferRefactors/<TypeName>/<Protocol>.swift`. Proposals target kit-defined `Semigroup`, `Monoid`, `CommutativeMonoid`, `Group`, `Semilattice`, plus stdlib `SetAlgebra` and `Numeric` (for a ring shape). `swift-infer suggest-refactors` is a different, text-only cluster report over index.json. To get unaccepted proposals, SwiftStats would have to link `SwiftInferCLI` and call the public `RefactorBridgeOrchestrator.proposals`.

**Evidence.** SwiftInferProperties/Sources/SwiftInferCLI/SwiftInferCommand.Discover+Run.swift:295-305 (only call site, inside InteractiveTriage.Context). Sources/SwiftInferCLI/RefactorBridgeProposal.swift:3-35. Sources/SwiftInferCLI/RefactorBridgeOrchestrator.swift:61,84 (public). protocolName literals in RefactorBridge*.swift: CommutativeMonoid, Group, Monoid, Numeric, Semigroup, Semilattice, SetAlgebra. Sources/SwiftInferCLI/SwiftInferCommand.SuggestRefactors.swift:1-60 (renders text; no JSON flag).

**Verifier.** The only call to RefactorBridgeOrchestrator.proposals is in SwiftInferCommand.Discover+Run.swift:302, inside the InteractiveTriage.Context build. The orchestrator is public (RefactorBridgeOrchestrator.swift:7, :30). The protocolName literals in the RefactorBridge files are Semigroup, Monoid, CommutativeMonoid, Group, Semilattice, SetAlgebra and Numeric. suggest-refactors reads index.json and renders clusters as text, with no JSON flag.

**Change.** - Per type: suggested conformances (RefactorBridge: Semigroup, Monoid, CommutativeMonoid, Group, Semilattice, SetAlgebra, Numeric). Only accepted ones can be read from files (`acceptedAsConformance` and `Generated/SwiftInferRefactors/`). Open proposals need the library adapter. If that isn't built, leave this field out rather than infer it.

### 10. §9 — misleading, confirmed

> fall back to parsing its JSON output (SwiftMutator, SwiftCloneDetector, SwiftProjectLint and SwiftInferProperties emit JSON)

**Issue.** `swift-infer discover` (the default subcommand) only prints human-readable text; it has no `--format json`. The JSON a consumer can read is the SemanticIndex: `swift-infer index --target <T>` writes `.swiftinfer/index.json` (top level: `schemaVersion`, `updatedAt`, `entries`, `typeShapes`, `interactionEntries`, `sourceFileByTypeName`). It runs once per target and upserts into one file. Entries leave out the explainability text ("why suggested" / "why this might be wrong"), so the index cannot meet §13's "always store tier, confidence and reason" for property candidates without the library. Other JSON files are `decisions.json`, `verify-evidence.json` and `kit-evidence.json`.

**Evidence.** SwiftInferProperties/Sources/SwiftInferCLI/SwiftInferCommand.swift:56-86 (defaultSubcommand Discover). Sources/SwiftInferCLI/SwiftInferCommand.Discover.swift:15-258 (no format/json option). Sources/SwiftInferCLI/SwiftInferCommand.Index.swift:1-3, 120-133 (`--target` required, "Resolved to Sources/<target>/"). Sources/SwiftInferCLI/IndexStore.swift:21, 69-109. Sources/SwiftInferCore/SemanticIndexEntry.swift:12-16 ("The full evidence is recoverable from a fresh discover run"). Sources/SwiftInferCore/Evidence.swift:80-91 (ExplainabilityBlock not persisted).

**Verifier.** defaultSubcommand is Discover. Discover's options include no format or JSON output (target, sources, includePossible, ..., outputDir). `index` requires `--target` (a non-optional String, resolved to Sources/<target>/) and writes .swiftinfer/index.json with the keys schemaVersion, updatedAt, entries, typeShapes, interactionEntries and sourceFileByTypeName (IndexStore.swift:65-66). SemanticIndexEntry's own doc says the full evidence is recoverable only from a fresh discover run, and no why-text field is persisted.

**Change.** Change to: "... and fall back to parsing JSON output (SwiftMutator, SwiftCloneDetector, SwiftProjectLint; for SwiftInferProperties, the `.swiftinfer/index.json` written by `swift-infer index --target <T>`, run once per target). The index has no 'why' text, so the reason field for property candidates needs the library adapter or is left empty."

### 11. §7.11 / 8 — gap, confirmed

> declared conformances whose laws SwiftPropertyLaws does / doesn't check

**Issue.** "Does / doesn't check" mixes two questions, and the PRD names no way to detect either. (a) Does the kit have laws for this protocol? It covers 33 protocols (`KnownProtocol`): the stdlib set (Equatable through StringProtocol) plus kit-defined Semigroup, Monoid, CommutativeMonoid, Group, Semilattice and Ring. (b) Does this project actually run them for this type? SwiftPropertyLaws writes no report. The signs are: a `check<Protocol>PropertyLaws(for: T.self …)` call in a test; `@PropertyLawSuite` on the type; a generated `@Test func <protocol>_<TypeName>` in `PropertyLawTests.generated.swift`; or, when the project opts in through `KitEvidenceRecorder.record`, rows in `.swiftinfer/kit-evidence.json`. Checks inherit (`checkHashable…` also runs Equatable's laws; `checkComparable…` likewise), and `// property-law-suppress: <protocol>_<TypeName>` markers or `.skip(...)` suppressions mean deliberately unchecked.

**Evidence.** SwiftPropertyLaws/Sources/PropertyLawCore/KnownProtocol.swift:10-42 (33 cases), :163-200 (inheritance chain), :254-256 (checkFunctionName = "check<Name>PropertyLaws"). Sources/PropertyLawCore/PropertyLawTestStub.swift:12-27 (test name `<fragment>_<TypeName>`). Sources/PropertyLawDiscoveryTool/GeneratedFileEmitter.swift:101-106, 205-215. README.md "What it covers" and "Suppressions". SwiftInferProperties/Sources/SwiftInferKitEvidence/KitEvidenceRecorder.swift:1-35. Sources/SwiftInferCore/KitEvidenceStore.swift:25.

**Verifier.** KnownProtocol has 33 cases: the stdlib set from equatable through stringProtocol, plus semigroup, monoid, commutativeMonoid, group, semilattice and ring. checkFunctionName is `check<Name>PropertyLaws`. subsumedProtocols maps hashable and comparable to equatable. The generated-file header references `// property-law-suppress: <protocol>_<TypeName>` markers. KitEvidenceRecorder.record exists and is opt-in. Its doc confirms that PropertyLawKit itself never writes kit-evidence.json.

**Change.** - Per type: each declared conformance, tagged as (1) not covered by SwiftPropertyLaws, (2) covered but not run here, (3) run, or (4) suppressed. "Run" means a `check<Protocol>PropertyLaws(for: T.self…)` call, `@PropertyLawSuite` on the type, a generated `<protocol>_<TypeName>` test, or a row in `.swiftinfer/kit-evidence.json`. A check also covers the protocols it inherits from (Hashable covers Equatable).

In §8, change "Unchecked laws" to: "declared conformance the kit covers (state 2), no check run".

### 12. §8 — error, partly

> SwiftInferProperties suggests idempotence *and* SwiftEffectInference says idempotent or pure | Two independent signals; higher confidence.

**Issue.** The two signals are not independent. SwiftInferProperties links SwiftEffectInference (pinned by revision). It uses SEI's `PurityInferrer` as its purity oracle (`PackagePurity`). It reads declared `@Idempotent` / `@NonIdempotent` / `@lint.effect` annotations through SEI's parser to corroborate or veto idempotence. It withholds laws on witness-refuted impure subjects. An idempotence suggestion has therefore already been filtered by SEI's own view. The same version-skew caveat as §7.15 applies, because SwiftInferProperties has its own pinned copy of SEI.

**Evidence.** SwiftInferProperties/Package.swift:120-140 (SwiftEffectInference at revision ba3624d…, product linked into SwiftInferCore). Sources/SwiftInferCore/PackagePurity.swift:1-12 ("SEI's PurityInferrer judges one declaration at a time ... every file the scan judges is judged by its oracle"). Sources/SwiftInferTemplates/IdempotenceTemplate+DeclaredEffect.swift:1-40. Sources/SwiftInferTemplates/TemplateRegistry+PurityVeto.swift:1-75.

**Verifier.** Confirmed that the signals are not independent. Package.swift pins SwiftEffectInference at revision ba3624d (SEI has no tags) and links it into SwiftInferCore. PackagePurity uses SEI's PurityInferrer as its oracle. IdempotenceTemplate+DeclaredEffect reads @Idempotent and @NonIdempotent through SEI's parser. TemplateRegistry+PurityVeto withholds laws on witness-refuted impure subjects. The proposed rule 'count agreement as corroboration only where the SEI tier was inferred' does not fix this. SEI's inferred purity is exactly the oracle SwiftInferProperties uses for its veto, and with --resolve-effects its inferred callee effects feed the idempotence score too. So agreement on an inferred tier is not independent either.

**Change.** | **Tool agreement** | SwiftInferProperties suggests idempotence *and* SwiftEffectInference says idempotent or pure | Not two independent signals. SwiftInferProperties already uses SEI's purity oracle, reads its annotations and (with `--resolve-effects`) its inferred effects. Report agreement, but don't raise confidence for it, and record the SEI revision each tool used. |

### 13. §8 — misleading, partly

> e.g. idempotence suggested but tier is `non_idempotent` | One tool is wrong; calibration data for both.

**Issue.** A declared `@NonIdempotent` makes SwiftInferProperties veto the idempotence suggestion, so this case cannot arise from a declaration. With `--resolve-effects` on, an inferred retry-hostile callee demotes the suggestion by 45 points rather than vetoing it. The disagreement is therefore real only for an inferred `non_idempotent` tier, and when the adapter ran without `--resolve-effects`, or when the two tools used different SEI revisions. Without saying this, version skew and flag differences would be read as one tool being wrong.

**Evidence.** SwiftInferProperties/Sources/SwiftInferTemplates/IdempotenceTemplate+DeclaredEffect.swift:22-40 ("a declaration vetoes, an inference demotes"). Sources/SwiftInferCLI/SwiftInferCommand.Discover.swift:68-88 (`--resolve-effects`, opt-in, "Demotes (-45) rather than vetoes").

**Verifier.** Confirmed that a declaration vetoes and an inference demotes by 45 (IdempotenceTemplate+DeclaredEffect.swift and the Discover --resolve-effects help text). The proposal misses one thing. `swift-infer index`, the JSON path §9 uses, has no --resolve-effects option, and no config key sets it. So an index-based adapter never sees inferred retry-hostile effects, and inferred-tier disagreements are expected there by construction. Also, with --resolve-effects a demoted suggestion can still surface, so a disagreement can remain even with the flag on.

**Change.** | **Tool disagreement** | e.g. idempotence suggested but SEI's *inferred* tier is `non_idempotent` (a declared tier already vetoes it) | Expected when candidates come from `swift-infer index`, which never resolves inferred effects. A real disagreement only when the candidate came from `discover --resolve-effects` and both tools used the same SEI revision. Record the source, flags and both revisions before treating it as calibration data. |

### 14. §8 — misleading, partly

> **Missing template?** | pure function, no property candidates

**Issue.** "No property candidates" needs a definition. A seeded pure function that matches no template gets a synthesized `determinism` row in the Advisory tier, which SwiftInferProperties itself calls a tautology. Possible-tier rows are missing unless the adapter passes `--include-possible`. The kit-coverage deferral (`assumedKitCoverage`) also removes laws the carrier's conformances already cover. Without these exclusions the signal reports spurious misses or hides real ones.

**Evidence.** SwiftInferProperties/Sources/SwiftInferCore/Tier.swift:47-62 (advisory: synthesized `determinism` law "for a seeded pure function that matched no template"). Sources/SwiftInferCore/ProtocolCoverageMap.swift:1-24. Sources/SwiftInferCore/ProtocolCoverageAudit.swift:1-15.

**Verifier.** Confirmed that Advisory `determinism` is synthesized for seeded pure functions that match no template (Tier.swift), and that assumedKitCoverage defers laws already covered by the type's conformances (ProtocolCoverageMap.swift). But the instruction to 'run with --include-possible' is wrong for the index adapter, which includes Possible by default (SwiftInferCommand.Index.swift:235-244). It only applies to discover.

**Change.** | **Missing template?** | pure function with no scored candidate (ignore Advisory rows such as `determinism`; include Possible rows, which `swift-infer index` does by default) | May reveal a template SwiftInferProperties lacks, or a law it left to SwiftPropertyLaws because a conformance already covers it. |

### 15. §14 — gap, partly

> linking SwiftInferProperties / SwiftMutator as libraries pins their versions together; parsing JSON keeps them independent.

**Issue.** The question leaves out the hard constraints that settle most of it. SwiftInferProperties pins swift-syntax at exactly 603.0.2. It depends on SwiftEffectInference by revision, not version. Under SwiftPM's rules a package with a revision-based dependency can't be required by version, so SwiftStats could depend on it only by branch, revision or local path. If SwiftStats also links SEI directly (as §9 proposes), both must resolve to the same SEI revision. Sitrep, the M0 base, requires `apple/swift-syntax` from 602.0.0. That accepts 603.0.2, but under the old URL, which SwiftPM warns about when it differs from `swiftlang/swift-syntax`.

**Evidence.** SwiftInferProperties/Package.swift:117-130 (swift-syntax exact 603.0.2; SwiftEffectInference revision ba3624d…, comment "SEI carries no version tags yet"). SwiftPropertyLaws/Package.swift:26-30 (swiftlang URL, exact 603.0.2, comment on SwiftPM URL-identity warnings). GitHub_projects/Sitrep/Package.swift:23 (apple/swift-syntax from 602.0.0).

**Verifier.** Verified: SwiftInferProperties pins swift-syntax exact 603.0.2 and SEI by revision. SEI has 0 git tags, and SwiftPM does not let a version-based dependency have a revision-based dependency. Sitrep uses apple/swift-syntax from 602.0.0. Three problems with the finding. (1) The evidence is wrong about SwiftPropertyLaws: its Package.swift:98 uses swiftlang swift-syntax `from: "603.0.0"`, not exact 603.0.2. (2) SEI itself pins swift-syntax exact 603.0.2, so linking SEI, which §9 already proposes, fixes swift-syntax regardless. 'Parsing index.json avoids all of this' is overstated. (3) Sitrep is not yet the M0 base; M0 is 'decide fork vs extend', and the current SwiftStats Package.swift does not depend on Sitrep. So 'either way' only applies if Sitrep code is reused.

**Change.** 3. **Library vs CLI adapters:** SwiftEffectInference and SwiftInferProperties both pin swift-syntax at exactly 603.0.2, so linking either one fixes SwiftStats' swift-syntax version. SwiftInferProperties also pins SEI by revision (SEI has no version tags), so SwiftStats could depend on it only by branch, revision or path, and linking SEI directly as well forces both onto that one revision. Parsing `.swiftinfer/index.json` avoids the SwiftInferProperties constraints but loses the explanation text and RefactorBridge proposals. If SwiftStats reuses Sitrep's code, Sitrep's swift-syntax requirement (apple URL, from 602.0.0) should move to the swiftlang URL to match.

**Checked and correct:**

- §7.11: `.swiftinfer/decisions.json` is the correct decisions file path (SwiftInferCLI/DecisionsLoader.swift:26-27; SwiftInferCore/Decisions.swift:60,118).
- §7.11: `idempotence`, `round-trip`, `commutativity` and `monotonicity` are real template names with those exact spellings (SwiftInferCore/TemplateName.swift).
- §7.11: count-invariance and reduce-equivalence are real TestLifter detector names (SwiftInferTestLifter/LiftedCounterSignal.swift:12; SwiftInferCLI/ConvertCounterexampleEngine.swift:62-63), though they are not template names.
- §1/§7.11: a Strong tier exists (score ≥ 75; SwiftInferCore/Tier.swift).
- §7.11: `encode` ↔ `decode` is a valid two-function round-trip example; the round-trip template emits evidence as [forward, inverse].
- §7.11: T0 classification holds for discover/index: it is SwiftSyntax-only and needs no build (the verify subcommand does build, but that is optional).
- §7.11: SwiftPropertyLaws checks laws of declared protocol conformances, including Equatable and Hashable (README 'What it covers'; KnownProtocol.swift).
- §7.8: swift-property-based is the property-testing library in use. SwiftPropertyLaws' only backend is SwiftPropertyBasedBackend, and SwiftInferProperties depends on SwiftPropertyLaws (README 'Relationship to SwiftPropertyLaws').
- §7.11: RefactorBridge is SwiftInferProperties' per-type conformance-suggestion feature (SwiftInferCLI/RefactorBridgeProposal.swift).
- §7.15: swift-infer consumes a seeds manifest (`--seeds`, `.pbt/seeds.json`) on both discover and index (SwiftInferCommand.Discover.swift:243; SwiftInferCommand.Index.swift).
- §7.7: the type-check timeout that compiled locally and failed only on CI is recorded in SwiftInferProperties at commit bbd634c (SwiftInferCLI/SwiftInferCommand.Index+Projection.swift:119-122).
- §9: SwiftEffectInference ships as a library product and is already linked as one by SwiftInferProperties (Package.swift:126-140).
- §7.11 identity: suggestion identity is a stable hash usable as a join key, with no USR involved (SwiftInferCore/SuggestionIdentity.swift).

## SwiftEffectInference and SwiftIdempotency

### 1. §7.10 — error, confirmed

> ### 7.10 Side-effect tier (T0/T1, SwiftEffectInference)

**Issue.** SwiftEffectInference is syntax-only. It needs no build and no index store, so it is T0, not T0/T1. Some of its passes do need every source file in the package parsed at once (the cross-file symbol table and ConstructionFacts), but that is still T0.

**Evidence.** /Users/josephcursio/xcode_projects/SwiftEffectInference/Package.swift:30-38: the only dependency is swift-syntax (SwiftSyntax and SwiftParser). EffectAnnotationParser.swift:171-173 matches attribute names as written and never expands macros. ConstructionFacts.build(from: [SourceFileSyntax]) and EffectSymbolTable.applyBodyInference(to: [SourceFileSyntax]) both take parsed source files only.

**Verifier.** Checked at the revision consumers pin (ba3624d) and at local HEAD. The only dependencies are SwiftSyntax and SwiftParser, and the sources import only those plus Foundation. There is no index store or build step. applyBodyInference(to: [SourceFileSyntax]) and ConstructionFacts.build(from:) take parsed trees only. §6.3 defines T0 as source files only (SwiftSyntax), so the tier is T0. The proposed one-line note on cross-file passes is accurate.

**Change.** ### 7.10 Side-effect tier (T0, SwiftEffectInference)

Syntax only; no build. The cross-file passes need every production source in the package parsed in one run.

### 2. §7.10 — gap, partly

> Tier on the lattice `pure < observational < idempotent < externally_idempotent < non_idempotent`

**Issue.** The order is right, and so is the snake_case spelling for the doc-comment grammar and the README. But the PRD reads as if SwiftEffectInference returns one tier per function. It does not. There are three separate engines, and SwiftStats has to combine them in a precedence order. (1) The declared tier comes from EffectAnnotationParser. (2) `pure` can only come from PurityInferrer, because call-site and body inference never infer `pure`. (3) observational, idempotent and non_idempotent come from body inference, as the lub of the function's callees. `externally_idempotent` is never inferred from a heuristic. A function with no recognised callees gets no tier at all. Most functions will have no tier, so the field needs a 'none' value. The Swift enum cases are camelCase (`externallyIdempotent`, `nonIdempotent`), and `externallyIdempotent` carries a `keyParameter`.

**Evidence.** SwiftEffectInference/Sources/SwiftEffectInference/Effect.swift:65-77 (cases pure, observational, idempotent, externallyIdempotent(keyParameter:), nonIdempotent). CallSiteEffectInferrer.swift:90-94 ('No `externally_idempotent` inference', 'No `pure` inference'). BodyEffectInferrer.swift:159-165 (combine returns nil when no callee resolves). PurityInferrer.swift:293-294 (inferredEffect returns .pure or nil and never another tier). EffectSymbolTable.lookupWithProvenance gives the order declared > upward-inferred > nil.

**Verifier.** Most of this checks out. Effect.swift has cases pure, observational, idempotent, externallyIdempotent(keyParameter:) and nonIdempotent. CallSiteEffectInferrer says it does no pure or externally_idempotent inference. BodyEffectInferrer.combine returns nil when no callee resolves. PurityInferrer.inferredEffect returns only .pure or nil. lookupWithProvenance orders declared > upward > nil. One claim is wrong: that pure can only come from PurityInferrer and that body inference yields only observational, idempotent or non_idempotent. Body inference takes the lub of callee results, and a callee's declared effect enters at depth 0 with a .declared anchor. So a body whose callees are all declared pure is inferred pure, and a declared externally_idempotent callee can push the lub to externally_idempotent. SwiftInferProperties' EffectResolver doc says so directly ('f(x) = g(x) + 1 with a pure g infers pure'). The proposed text needs to say that.

**Change.** - Tier on the lattice `pure < observational < idempotent < externally_idempotent < non_idempotent`, or **none** when nothing applies (the common case). Store the snake_case spelling; the Swift cases are `externallyIdempotent` / `nonIdempotent`. For `externally_idempotent`, also store the key parameter when one was declared.
- SwiftEffectInference has no single per-function call. Resolve in this order: declared annotation (`EffectAnnotationParser`), then `pure` from `PurityInferrer`, then the body-inferred tier (`EffectSymbolTable` + `BodyEffectInferrer`, the lub of the callees' tiers).
- Name-based guesses never give `pure` or `externally_idempotent`. Body inference reaches them only through callees declared with those tiers, so a body-inferred `pure` means only that nothing it calls is worse than pure. It is not a purity verdict.

### 3. §7.10 — gap, confirmed

> Whether the tier was **declared** (annotation) or **inferred**, plus the reason / evidence

**Issue.** The PRD doesn't say which annotations count or which package defines them, and SwiftIdempotency isn't mentioned anywhere in the PRD. There are two declaration grammars. The first is SwiftIdempotency's marker macros (`@Pure`, `@Observational`, `@Idempotent`, `@ExternallyIdempotent(by:)`, `@NonIdempotent`). The second is the `/// @lint.effect <tier>` doc comment. If the two disagree on one declaration, the parser returns nil. `transactional_idempotent` is read as `non_idempotent`. `@EffectUnknown` (or `@lint.effect unknown`) and `@ClockDeterministic` are separate yes/no questions that sit off the lattice. On evidence: the library returns typed provenance, not a single 'reason'. Positions, where present, are `AbsolutePosition` byte offsets, not file:line.

**Evidence.** EffectAnnotationParser.swift:59-75 (default recognition set, which matches SwiftIdempotency's macros), :288-300 (collision returns nil), :344-375 (doc-comment tokens; transactional_idempotent becomes .nonIdempotent), and the isClockDeterministic / declaresUnknownEffect predicates at about :423-489. SwiftIdempotency/Sources/SwiftIdempotency/Idempotent.swift:25-63, Pure.swift:36, EffectUnknown.swift:48. Evidence types: EffectSymbolTable.swift:410-414 `EffectProvenance` (.declared / .bodyInferred(depth:) / .callSite(reason:)); BodyEffectInferrer.swift:33-54 `BodyInference.anchor` (.declared / .heuristic) and `depth`; `PurityRefutation` (PurityRefutation.swift, with a `description`); `CallSiteEffectInferrer.inferenceReason(for:)`. NondeterminismSource.position and AmbientTimeWitness.position are `AbsolutePosition`.

**Verifier.** Checked at ba3624d. The default AttributeRecognition is Pure, Idempotent, NonIdempotent, Observational and ExternallyIdempotent, matched by name. When the attribute form and the doc-comment form disagree, parseEffect returns nil. `transactional_idempotent` maps to .nonIdempotent. @EffectUnknown / `@lint.effect unknown` and @ClockDeterministic have their own predicates (declaresUnknownEffect, isClockDeterministic) in EffectAnnotationParser+Markers.swift. EffectProvenance is .declared / .bodyInferred(depth:) / .callSite(reason:). BodyInference carries an anchor and a depth. PurityRefutation conforms to CustomStringConvertible. NondeterminismSource and AmbientTimeWitness positions are AbsolutePosition. The macros exist in SwiftIdempotency, and the PRD never mentions SwiftIdempotency. A conflicting declaration can be detected: compare parseEffect(leadingTrivia:) with the combined result. Recording it as 'conflicting declaration' is therefore feasible.

**Change.** - **Declared** means a SwiftIdempotency marker macro (`@Pure`, `@Observational`, `@Idempotent`, `@ExternallyIdempotent(by:)`, `@NonIdempotent`) or a `/// @lint.effect <tier>` doc comment. SwiftEffectInference reads both by name, so SwiftIdempotency doesn't need to be in the build. If the two forms disagree on one declaration, the tier is withdrawn; record that as 'conflicting declaration', not 'none'.
- Record `@EffectUnknown` and `@ClockDeterministic` as separate flags. They are not tiers.
- **Evidence** stored per function: provenance (declared / body-inferred with hop depth / call-site heuristic with its reason string), anchor (declared or heuristic), and for purity the `PurityRefutation` case and its description. Convert any `AbsolutePosition` to file:line with SwiftSyntax's `SourceLocationConverter`.

### 4. §7.10 — misleading, confirmed

> Answers the original "is it pure?" and "is it idempotent?" questions as one field

**Issue.** This is misleading on both counts. The lattice's `idempotent` means replay idempotence: calling the function twice has the effect of calling it once. It does not mean value idempotence, `f(f(x)) == f(x)`, which is what SwiftInferProperties' idempotence template means. SwiftIdempotency's README says these are 'two unrelated things'. Also, the tier loses the purity verdict's partial case. A throwing function that is otherwise pure is `pureButPartial` from `verdict(for:)`, but it gets no `pure` tier from `inferredEffect(for:)`.

**Evidence.** SwiftIdempotency/README.md:24-52 ('Two kinds of idempotency': value vs replay). SwiftInferProperties/Sources/SwiftInferTemplates/IdempotenceTemplate+DeclaredEffect.swift:77-84 (declared idempotent 'claims RE-INVOCATION stability ... weaker than the law here'). SwiftEffectInference PurityInferrer.swift:29-39 (PurityVerdict pure / pureButPartial / refuted) and :316-322 (whole-domain path returns .declaredThrows).

**Verifier.** SwiftIdempotency's README separates value idempotence from replay idempotence and calls them unrelated. SwiftInferProperties' declared-effect signal notes that the declared idempotent claim is weaker than f(f(x)) == f(x). PurityVerdict has pure, pureButPartial and refuted. inferredEffect is .pure only when wholeDomainRefutation is nil, and that returns .declaredThrows for any throwing function. So a pure-but-partial function gets no pure tier, and a single field loses that verdict. Storing the purity verdict as its own field is sound and matches what SwiftInferProperties itself stores (FunctionSummary.purityVerdict).

**Change.** - Store two fields, not one: the **side-effect tier** (retry-safety, as above) and the **purity verdict** from `PurityInferrer.verdict(for:)` (`pure` / `pure_but_partial` / `refuted`, with the refutation).
- The tier's `idempotent` means replay idempotence (safe to run twice). It says nothing about value idempotence, `f(f(x)) == f(x)`, which is SwiftInferProperties' idempotence template (§7.11).

### 5. §6.1 / 7.10 — gap, partly

> Each collector declares its **cost tier**, its inputs, and the identity it reports against.

**Issue.** SwiftEffectInference reports no identity or location of its own. The per-declaration calls (`EffectAnnotationParser.parseEffect(declaration:)`, `PurityInferrer.verdict(for:)`) take a `FunctionDeclSyntax`, so SwiftStats can attach their results to its own records as it walks the tree. Body inference is different. It is keyed only by `FunctionSignature` (base name plus argument labels), with no enclosing type, file or line. Same-signature methods in different types overwrite each other within a file and are merged across files. And there is no public call for initialisers or subscripts.

**Evidence.** SwiftEffectInference/Sources/SwiftEffectInference/Internal/FunctionSignature.swift:3-24 (name + argumentLabels only). BodyEffectInferrer.swift:118-132 returns `[FunctionSignature: BodyInference]` and assigns `results[signature] = inference` (same at the pinned revision ba3624d, lines 187 and 208). EffectSymbolTable merges same-signature upward results across files with mergedInference. No public API takes InitializerDeclSyntax or SubscriptDeclSyntax.

**Verifier.** Confirmed: FunctionSignature holds only name and argumentLabels. BodyEffectInferrer.inferEffects assigns results[signature], so same-signature methods within a file overwrite each other. runInferencePass merges across files with mergedInference (lub). No public API takes InitializerDeclSyntax or SubscriptDeclSyntax, so initialisers get nothing. The claim about subscripts is overstated. PurityInferrer has public isPure(_: AccessorBlockSyntax) and refutation(for: AccessorBlockSyntax), and a subscript's or computed property's accessor block can be passed to them. SwiftInferProperties already does this for getters (SoundPurity.verdict(forGetter:)). Subscripts get no declared or body-inferred tier, but they can get a purity answer.

**Change.** Add under §7.10: SwiftEffectInference reports no location. SwiftStats walks the syntax itself and calls the per-declaration APIs (annotation, purity) on each `FunctionDeclSyntax`, so those results land on the right record. Body-inferred tiers are keyed only by `name(label:)`. A signature shared by more than one declaration in the package gets an inferred tier marked **ambiguous**, not copied to every declaration. Initialisers get no tier. Subscripts and computed properties get no declared or body-inferred tier, but they can get a purity answer from `PurityInferrer` on their accessor block.

### 6. §8 — error, partly

> SwiftInferProperties suggests idempotence *and* SwiftEffectInference says idempotent or pure | Two independent signals; higher confidence.

**Issue.** These are not independent. SwiftInferProperties already links SwiftEffectInference and reads the declared tier into its idempotence score: a declared `idempotent` adds +15. An optional EffectResolver adds inferred tiers on top. And `pure` is no evidence for value idempotence. SwiftInferProperties' own code says pure is 'orthogonal (`x + 1` is pure and not idempotent)' and deliberately ignores it. The tier's `idempotent` is replay idempotence, a weaker claim than the template's `f(f(x)) == f(x)`.

**Evidence.** SwiftInferProperties/Sources/SwiftInferTemplates/IdempotenceTemplate+DeclaredEffect.swift:1 (`import SwiftEffectInference`), :74-84 (declared idempotent gives weight +15), :106-112 (`.observational, .pure` return nil; 'x + 1 is pure and not idempotent'). Sources/SwiftInferCore/EffectResolver.swift:10 (opt-in inferred effects).

**Verifier.** The diagnosis is right. IdempotenceTemplate+DeclaredEffect.swift imports SwiftEffectInference, gives a declared idempotent +15, returns nil for .observational/.pure with the 'x + 1 is pure and not idempotent' comment, and EffectResolver adds opt-in inferred tiers. The proposed replacement signal is close to a tautology, though. TemplateRegistry+PurityVeto.swift already vetoes every suggestion whose subject SEI's PurityInferrer refutes with a witness (it reads purityVerdict == .refuted). So nearly every live idempotence suggestion already has a pure or pure_but_partial subject, and 'idempotence suggested and verdict pure/pure_but_partial' would flag almost all of them. That carries no extra information. The row should go rather than be redefined.

**Change.** Drop the **Tool agreement** row. SwiftEffectInference gives no independent evidence for an idempotence suggestion. SwiftInferProperties already reads the declared tier (+15 for `idempotent`; a veto for `non_idempotent` / `externally_idempotent`) and withholds suggestions whose subject `PurityInferrer` refutes. `pure` says nothing about `f(f(x)) == f(x)` (`x + 1` is pure). Independent confirmation comes from a passing property test or mutation results (§7.9), not from the tier. In M4's done-when, change 'Tool agreement / disagreement table' to 'Tool disagreement table'.

### 7. §8 — error, confirmed

> e.g. idempotence suggested but tier is `non_idempotent` | One tool is wrong; calibration data for both.

**Issue.** When the tier is declared, this can't happen. SwiftInferProperties vetoes the idempotence suggestion outright if the function is declared `non_idempotent` or `externally_idempotent`. It can only happen with an inferred tier, and then SwiftInferProperties has already marked the suggestion down by 45 (if its optional resolver ran). Even then neither tool need be wrong: replay idempotence and value idempotence are different properties. A function can return `f(f(x)) == f(x)` and still write a log row each call.

**Evidence.** SwiftInferProperties/Sources/SwiftInferTemplates/IdempotenceTemplate+DeclaredEffect.swift:86-104 (declared nonIdempotent / externallyIdempotent give weight Signal.vetoWeight), :45-66 (inferred nonIdempotent gives -45). Sources/SwiftInferCore/Signal.swift:16 (vetoWeight = Int.min). SwiftIdempotency/README.md:24-52.

**Verifier.** Lines 86-104 of IdempotenceTemplate+DeclaredEffect.swift give declared nonIdempotent and externallyIdempotent Signal.vetoWeight (Int.min), which collapses the suggestion to .suppressed. Lines 46-68 give an inferred nonIdempotent or externallyIdempotent -45, and only when the opt-in EffectResolver or SeedEffectResolver ran. The README's distinction between value and replay idempotence backs the point that both tools can be right at once. The proposed row is accurate and keeps calibration value for SEI's heuristics.

**Change.** | **Tool disagreement** | idempotence suggested, but the function's body-inferred tier is `non_idempotent` (a declared `non_idempotent` already vetoes the suggestion) | Either the inference is wrong or the function returns a stable value while repeating a side effect. Worth a look; calibration data for SwiftEffectInference's heuristics. |

### 8. §7.15 — misleading, confirmed

> the reverse points to version skew between the two tools' copies of SwiftEffectInference

**Issue.** SwiftProjectLint doesn't hold a copy of SwiftEffectInference. It depends on it by commit SHA, in its root package and two nested packages. And the reverse case (SPL nominates, SEI doesn't call it pure) has two causes that aren't version skew. (1) SPL nominates `pureButPartial` functions, so a throwing function that is otherwise pure gets a pureFunctionCandidate finding even though `inferredEffect(for:)`/`isPure` return nil for it. (2) SPL builds `ConstructionFacts` per package and passes them to every PurityInferrer it creates. If SwiftStats uses `PurityInferrer()` with the default `.empty`, the two tools disagree about any function that constructs a type whose initialiser is impure. That case shows up in the first direction (SEI pure, SPL not), and the PRD would wrongly put it down to a candidacy filter.

**Evidence.** SwiftProjectLint/Package.swift:75-87 (SEI by revision ba3624d754c3c9150c946f66468c2c356be3e7e0); Packages/SwiftProjectLintVisitors/Package.swift:34-35 and Packages/SwiftProjectLintIdempotencyRules/Package.swift:36-37 (same SHA). SwiftInferProperties/Package.swift:125-127 pins the same SHA. SwiftProjectLint/Packages/SwiftProjectLintVisitors/Sources/SwiftProjectLintVisitors/PropertyTestCandidacy.swift:109-117 (`.pureButPartial` gives a candidate with isPartial = true). SwiftProjectLintVisitors/PurityInferrer.swift:56-60 (constructionFacts from PackagePurity.current). SwiftEffectInference README.md:15 ('a consumer should pass the same table to every inferrer it creates') and :28 ('pin the same revision ... carries no version tags').

**Verifier.** SwiftProjectLint's root Package.swift and its SwiftProjectLintVisitors and SwiftProjectLintIdempotencyRules packages all pin SEI at revision ba3624d754c3c9150c946f66468c2c356be3e7e0, and SwiftInferProperties pins the same SHA. PropertyTestCandidacy.candidate switches on verdict(for:) and nominates .pureButPartial with isPartial = true. SPL's PurityInferrer wrapper builds SEI's PurityInferrer with constructionFacts from PackagePurity.current. So comparing against a default PurityInferrer() with isPure would produce false disagreements in both directions, as the finding says. With the same facts and verdict(for:), the remaining extra filters in SPL (candidacy shape, PackagePurityJoin) only make it stricter, so the reverse case comes down to revision skew. The proposed text is correct.

**Change.** To compare like with like, SwiftStats builds `ConstructionFacts` from the package's production sources, passes them to every `PurityInferrer`, and compares on `verdict(for:)`, not `isPure`. Then a function SwiftEffectInference calls pure (or pure but partial) that SwiftProjectLint doesn't nominate shows a candidacy filter at work. The reverse means the two tools ran different SwiftEffectInference revisions. Both pin it by commit SHA (it has no version tags), so record SwiftStats' SEI revision and SwiftProjectLint's pinned one in the snapshot (§6.2).

### 9. §9 — gap, confirmed

> Adapters prefer linking a tool's library product (SwiftEffectInference already ships as a library) and fall back to parsing its JSON output

**Issue.** The library product is real. But SwiftEffectInference has no CLI and emits no JSON, so there is nothing to fall back to. Linking is the only route. SwiftProjectLint's output doesn't carry the tier either, so the tier can't be read second-hand. Linking also has costs the PRD leaves out. SEI pins swift-syntax at exactly 603.0.2 via the swiftlang URL. Sitrep uses `apple/swift-syntax` from 602.0.0, and SwiftPM warns when one package is reached through two URLs, which bears on §14 Q1. SEI has no version tags, so SwiftStats must pin it by revision. §14 Q3 lists only SwiftInferProperties and SwiftMutator.

**Evidence.** SwiftEffectInference/Package.swift:13-17 (single .library product), :30 (swift-syntax exact 603.0.2, swiftlang URL); README.md:28 ('there is no CLI and no process boundary ... pin by revision'); docs/SwiftEffectInference Design v0.2.md:265 ('No executable; this is a library only'). /Users/josephcursio/GitHub_projects/Sitrep/Package.swift:23 (apple/swift-syntax from 602.0.0). SwiftInferProperties IdempotenceTemplate+DeclaredEffect.swift:15-21 (`.pbt/seeds.json` 'carries the idempotency violation but not the tier').

**Verifier.** SEI has one .library product. Its README says there is no CLI and no process boundary and that consumers pin by revision. The design doc says 'No executable; this is a library only'. The package pins swiftlang/swift-syntax exact 603.0.2 and carries no tags. Sitrep's Package.swift:23 uses apple/swift-syntax from 602.0.0, and SEI's own Package.swift comment notes that SwiftPM warns when one identity is reached through different URLs. SwiftInferProperties notes that seeds.json carries the violation but not the tier. The proposed §9 and §14 Q3 wording is accurate.

**Change.** - **Adapters** prefer linking a tool's library product and fall back to parsing its JSON output (SwiftMutator, SwiftCloneDetector, SwiftProjectLint and SwiftInferProperties emit JSON). SwiftEffectInference is library-only, with no CLI or JSON, so it must be linked. Linking it fixes SwiftStats to swift-syntax 603.0.2, spelled with the `swiftlang/swift-syntax` URL, and to a pinned SEI commit (it has no version tags).

And in §14 Q3: "linking SwiftEffectInference (required: it has no CLI), SwiftInferProperties or SwiftMutator as libraries pins their versions, and swift-syntax's, together."

### 10. §7.10 / 6.2 — gap, confirmed

> One run of SwiftStats, tagged with: commit SHA, branch, dirty flag, date, toolchain version (`swiftly use` output), and which collectors ran and with what versions.

**Issue.** Body inference has a wall-clock budget, 30 seconds by default. Multi-hop inference stops when the time runs out, and nothing tells the caller it stopped early. So on a large package or a slow machine, inferred tiers can change between snapshots of the same commit, and the snapshot diff would show changes that aren't real.

**Evidence.** SwiftEffectInference at the pinned revision ba3624d, Sources/SwiftEffectInference/EffectSymbolTable+BodyInference.swift:39-71 (`wallClockBudget: Duration = .seconds(30)`; `if ContinuousClock.now >= deadline { return }` in both the hop loop and the per-file loop, returning Void).

**Verifier.** At ba3624d, EffectSymbolTable+BodyInference.swift has wallClockBudget: Duration = .seconds(30) by default. It checks `if ContinuousClock.now >= deadline { return }` in both the multi-hop loop and the per-file loop of runInferencePass, and returns Void with no indication that it stopped early. SwiftInferProperties' EffectResolver doc also mentions this 30 s budget. Results can therefore vary with machine speed. Fixing maxHops and a non-binding budget, and recording both, is a sound mitigation. (SwiftStats should also fix and record the multiHop flag, which defaults to false.)

**Change.** Add to §7.10: Body inference stops at a wall-clock budget (30 s by default) and doesn't report that it stopped. SwiftStats sets a fixed hop count (`maxHops`), a budget large enough not to bind, and records both in the snapshot, so inferred tiers are repeatable between runs.

### 11. §13 — suggestion, confirmed

> Inferred stats (purity, properties) look more certain than they are | Always store tier, confidence and reason alongside the value

**Issue.** SwiftEffectInference has no confidence value. It does say how much weight a tier can bear: the anchor (whether a name guess was needed to reach it), the hop depth, and the provenance kind. The PRD should say those stand in for 'confidence' for this tool, or adapters will invent a number.

**Evidence.** SwiftEffectInference BodyEffectInferrer.swift:12-69 (`BodyInference.depth` and `.anchor`, default `.heuristic`); EffectSymbolTable.swift:410-414 (`EffectProvenance`). No confidence field anywhere in Sources/.

**Verifier.** No confidence field exists anywhere in SEI's Sources (the only match for 'confidence' is a doc comment). BodyInference exposes depth and anchor (default .heuristic), and EffectProvenance gives the provenance kind. SwiftInferProperties has a Score and a Tier (Score.swift, Tier.swift). The proposed §13 wording also removes the ambiguity of 'tier' between SIP's tier and the side-effect tier.

**Change.** | Inferred stats (purity, properties) look more certain than they are | Always store the tool's own strength measure and reason alongside the value: SwiftInferProperties' tier and score; for side-effect tiers, provenance, anchor (declared / heuristic) and hop depth. Don't invent a confidence number where a tool gives none. |

### 12. §7.8 / 7.11 — suggestion, confirmed

> **Property-based** tests (detected via the property-testing library's API, e.g. swift-property-based)

**Issue.** SwiftIdempotency ships its own idempotency test API, and detection by swift-property-based's API won't see it. `assertIdempotentProperty(over:)` and `assertIdempotentEffectsProperty` wrap `propertyCheck`, so a test that calls them never names it directly. `#assertIdempotent`, `assertIdempotentEffects` and the `@IdempotencyTests` suite macro are example-based checks. 'Whether a matching property test exists' (§7.11) will miss these.

**Evidence.** SwiftIdempotency/Sources/SwiftIdempotencyPropertyBased/AssertIdempotentProperty.swift:47, AssertIdempotentEffectsProperty.swift:42; Sources/SwiftIdempotencyTestSupport/AssertIdempotentEffects.swift:98; Sources/SwiftIdempotency/assertIdempotent.swift:43,54; Sources/SwiftIdempotency/Idempotent.swift:69-86 (`@IdempotencyTests`).

**Verifier.** In SwiftIdempotency, assertIdempotentProperty (AssertIdempotentProperty.swift:47, calling propertyCheck at :53) and assertIdempotentEffectsProperty (:42, calling propertyCheck at :48) wrap propertyCheck. So a test that calls them never names propertyCheck, and API-based detection misses it. #assertIdempotent (assertIdempotent.swift:43, 54), assertIdempotentEffects (SwiftIdempotencyTestSupport/AssertIdempotentEffects.swift:98) and the @IdempotencyTests extension macro (Idempotent.swift:83) exist as described. @IdempotencyTests generates its @Test methods by macro expansion, so a syntax-only inventory would not see them as tests either. That reinforces the point.

**Change.** - **Property-based** tests (detected via the property-testing library's API, e.g. swift-property-based's `propertyCheck`, and wrappers built on it such as SwiftIdempotency's `assertIdempotentProperty` / `assertIdempotentEffectsProperty`)
- **Idempotency checks** (SwiftIdempotency's `#assertIdempotent`, `assertIdempotentEffects`, `@IdempotencyTests`), counted separately and linked to the function they exercise

**Checked and correct:**

- Lattice tier names and order `pure < observational < idempotent < externally_idempotent < non_idempotent` match the SwiftEffectInference README (README.md:6) and the doc-comment grammar (EffectAnnotationParser.swift:344-375); the code's rank order is pure=0 ... nonIdempotent=4 (Effect.swift:85-93). Only the Swift enum casing differs (camelCase).
- §9 'SwiftEffectInference already ships as a library': true. Package.swift declares one `.library(name: "SwiftEffectInference")` product; there is no executable.
- §7.15: SwiftProjectLint's pureFunctionCandidate / pureMutatorCandidate / pureClosureCandidate are built on SwiftEffectInference's PurityInferrer through PropertyTestCandidacy (SwiftProjectLintVisitors/PropertyTestCandidacy.swift:109, PropertyTestCandidacy+Mutator.swift:73; PureClosureCandidateVisitor.swift:51). SPL's own PurityInferrer is a thin wrapper around SEI's (SwiftProjectLintVisitors/PurityInferrer.swift:47-60). It is not an independent purity opinion.
- SwiftProjectLint depends on SwiftEffectInference (it does not vendor it), at revision ba3624d in its root Package.swift and in the SwiftProjectLintVisitors and SwiftProjectLintIdempotencyRules nested packages. SwiftInferProperties pins the same SHA, so the two consumers agree today. (Side note: SPL's untracked local Package.resolved still records 5fbee6f, and the local SwiftEffectInference checkout is at c8644fd, behind the pinned ba3624d. The public API checked here is the same at both revisions.)
- Reason / evidence data does exist: PurityRefutation (with description), EffectProvenance, BodyInference.anchor and depth, and CallSiteEffectInferrer.inferenceReason.
- SwiftIdempotency defines the attribute macros SwiftEffectInference recognises by default: @Pure, @Idempotent, @NonIdempotent, @Observational, @ExternallyIdempotent(by:), plus @ClockDeterministic and @EffectUnknown off the lattice. SwiftIdempotency's README gives the same five-tier order.
- §7.15 idempotency rule names `idempotencyViolation` and `nonIdempotentInRetryContext` appear in SwiftIdempotency's README (lines 119, 275) as SwiftProjectLint rules.

## SwiftMutator and SwiftCloneDetector

### 1. §7.9 — error, confirmed

> Mutants generated, killed, survived, timed out, per function

**Issue.** Leaves out two outcomes SwiftMutator reports: build errors and not covered. It also doesn't say how the score treats each one. A crash (`runtimeError`) counts as a kill. Timeouts and not-covered mutants count as survivors. Build errors are left out of the score. If SwiftStats works out its own score with different rules, its numbers won't match SwiftMutator's.

**Evidence.** SwiftMutator/Sources/muterCore/TestReporting/OutcomeCounts.swift:5-21 (MutantVerdict: killed = failed|runtimeError, survived = passed, timedOut, buildError, notCovered) and :39-44 (JSON `mutantsByOutcome` keys killed/survived/timedOut/buildErrors/notCovered). Raw per-mutant values: TestReporting/TestSuiteOutcome.swift:3-11 (`passed`, `failed`, `buildError`, `runtimeError`, `noCoverage`, `timeout`). Score: TestReporting/mutationScoring.swift:1-7 (killed ÷ every mutant but build errors). Docs/test_report_json_example.md:79 "Mutation scores ignore build errors."

**Verifier.** I checked OutcomeCounts.swift. MutantVerdict maps failed and runtimeError to killed, passed to survived, plus timeout, buildError and noCoverage, and the JSON `mutantsByOutcome` has the keys killed, survived, timedOut, buildErrors and notCovered. mutationScoring.swift scores killed (failed or runtimeError) out of every mutant except build errors, so timeouts and not-covered mutants count against the score as survivors do. §7.9 lists neither build errors nor not covered, and doesn't say how the score is worked out. The proposed wording is accurate.

**Change.** - Mutants per function by outcome: killed (a failed test or a crash), survived, timed out, not covered (tests passed without running the mutant's code), build error
- **Mutation score** per function / module / project, worked out as SwiftMutator does: killed ÷ all mutants except build errors. Timeouts and not-covered mutants count as survivors.

### 2. §7.9 / 6.1 — gap, confirmed

> Surviving mutants listed with operator and location

**Issue.** SwiftMutator doesn't group results by function. The JSON report groups them by file (`fileReports[].appliedOperators[]`), so SwiftStats has to map each mutant to a function by line. The PRD doesn't say which fields to use, and two of them are traps. `mutationPoint.filePath` is the path in the mutated copy, not the project. The project-relative path is `path`. Also, every file with no coverage gets one placeholder row: an empty `mutationPoint`, line 0, no `path` and no `key`. That row isn't a mutant and must be skipped, or it will count as an unmapped result.

**Evidence.** SwiftMutator/Sources/muterCore/TestReporting/MuterTestReport.swift:335 (grouped by `point.filePath`), :363-376 (placeholder `.null` point with `.noCoverage` for `filesWithoutCoverage`), :251-256 (`path` relative to the project, `key`). MutationSchemata/MutationSchema.swift:149-152 and MutationPosition.swift:4-13 (`mutationOperatorId`, `filePath`, `position.line/column/utf8Offset`). Docs/test_report_json_example.md, "`path`, `key` and `durationSeconds`" table. A grep of Sources/Docs/README finds no per-function grouping.

**Verifier.** MuterTestReport.swift groups results by `point.filePath` (line 335). The comment on `path` says it is relative to the project, while `mutationPoint` gives the path in the mutated copy. `filesWithoutCoverage` produces a FileReport with one AppliedMutationOperator: mutationPoint `.null` (MutationPosition defaults to line 0), outcome `.noCoverage`, and no path or key. Nothing groups by function. §6.1 only says in general terms that results are mapped by source range; it doesn't cover these field traps. One minor point: in the JSON the outcome is the raw value `noCoverage`, and 'skipped (no coverage)' is only the text-report label. The proposal's identifying test (no `key`, line 0) is still correct.

**Change.** Add under §7.9: "SwiftMutator reports mutants per file, not per function. The adapter maps each mutant to a function by `path` + `mutationPoint.position.line`/`column`. It uses `path` (relative to the project), not `mutationPoint.filePath`, which points into the mutated copy. It skips the one-row `skipped (no coverage)` placeholder for each untested file (no `key`, line 0)."

### 3. §9 / 11 (M6) / 13 — contradiction, confirmed

> Caching: T2/T3 results are reused when the function's source hash hasn't changed since the last snapshot.

**Issue.** This rule isn't sound for mutation results, and it goes against SwiftMutator's own reuse rules, which were measured. A mutant's verdict depends on the tests and on the rest of the code, not only on the function's own source. A new test can kill an old survivor, and a change to a helper can change a kill. So `run --reuse` retests every result when any non-test file changes. When a test file changes, it retests every survivor and every kill that no unchanged test still explains. Even so, SwiftMutator's README recommends a full run now and then. Caching by the function's own source hash would keep stale verdicts. The same objection applies to coverage (T2), which depends on the tests.

**Evidence.** SwiftMutator/README.md:3009-3075 ("Reusing an earlier run"), especially :3030 ("A changed file other than a test file ... every result tested before the change is tested again") and :3068 ("Run a full run now and then"). Docs/reuse-2026-10.md: 4.2 min against 27.3 min with nothing changed, and 19.0 min against 26.6 min after one test file changed. README.md:2210 "Mutating only what a branch changed" (`--since`, `--changed-lines`). Docs/since-2026-11.md: a four-file PR took 2.7 min against 27.3 min.

**Verifier.** README 'Reusing an earlier run' says a changed non-test file retests every result tested before the change, and changed test files retest every survivor and every kill no unchanged test still holds. It also advises 'Run a full run now and then'. It measures 4.2 vs 27.3 min and 19.0 vs 26.6 min. `--since` and `--changed-lines` exist (README line 2210 onward; since-2026-11.md gives 2.7 min and 50 s). Caching by the function's own source hash would keep verdicts that a test or helper change has made stale. Coverage depends on the tests in the same way. §9, §13 and M6 all describe source-hash caching, so the contradiction is real and the proposed edits fit.

**Change.** §9 Caching: "T3: SwiftStats doesn't cache mutation results itself. It runs SwiftMutator with `run --reuse <previous results.jsonl>`, which keeps only the results that still hold after source or test changes, and uses `--since <ref> --changed-lines` for a branch diff. T2: coverage is reused only when no source or test file has changed." §13: change the mitigation to "Opt-in tier; incremental runs through SwiftMutator's `--reuse` and `--since`; a full run now and then." §11 M6: change "SwiftMutator join + caching" to "SwiftMutator join + `--reuse` / `--since` runs".

### 4. §9 — gap, partly

> fall back to parsing its JSON output (SwiftMutator, SwiftCloneDetector, SwiftProjectLint and SwiftInferProperties emit JSON)

**Issue.** SwiftMutator does emit JSON (`-f json`). But the JSON report has no per-mutant file hash, so SwiftStats can't check that a mutant's line still matches the source it is mapping onto. The results file every run writes, `results.jsonl`, does have one: `fileSHA256` on each mutant line, plus the header's `project.files` hashes. It is also written as each mutant finishes, so it survives a stopped run. If SwiftStats reads it, note that a not-covered mutant is stored there as `outcome: passed` with `activated: false`.

**Evidence.** SwiftMutator/Docs/results-file.md:1-15 (always written, one JSON line per mutant), :185-212 (`mutant` record: `path`, `line`, `column`, `mutationOperatorId`, `outcome`, `activated`, `fileSHA256`). MuterTestReport.swift:234-260 (`AppliedMutationOperator` has no file hash; `sourceChange` is left out when the file has changed).

**Verifier.** Docs/results-file.md confirms the file is always written, one line per mutant as each finishes, with `fileSHA256` per mutant and hashes in the header's `project.files`. It also confirms that a not-covered mutant is stored as `outcome: passed` with `activated: false`. AppliedMutationOperator has no file hash. But the proposed text says to read results.jsonl 'or the `-f json` report' and then check `fileSHA256`, which the JSON report doesn't have. It also leaves out the file's reading rules ('Reading it'): key by path, operator, line, column and occurrence; the last line for a key wins (reruns); a `retired` line drops earlier results; skip a cut-off last line; refuse an unknown `formatVersion`. An adapter that ignores these would count stale or duplicate results.

**Change.** Add to §9 Adapters: "For SwiftMutator, read the run's `results.jsonl` (the `-f json` report has no file hashes). Follow the file's reading rules: key mutants by `path`, `mutationOperatorId`, `line`, `column` and `occurrence`; the last `mutant` line for a key wins; a `retired` line drops earlier results for its keys; skip a line that doesn't parse; refuse an unknown `formatVersion`. Before mapping a mutant, compare its `fileSHA256` with the snapshot's hash of that file, and report mutants from changed files as unmapped. Read `outcome: passed` with `activated: false` as not covered."

### 5. §14 (Q3) — error, partly

> linking SwiftInferProperties / SwiftMutator as libraries pins their versions together

**Issue.** SwiftMutator can't be linked as a library today. Its only product is the `swift-mutator` executable, and its report types are internal (not `public`). So for SwiftMutator the only option is parsing its output.

**Evidence.** SwiftMutator/Package.swift:11-13 (products: only `.executable(name: "swift-mutator", ...)`). Sources/muterCore/TestReporting/MuterTestReport.swift:6 (`struct MuterTestReport` is internal).

**Verifier.** Confirmed for SwiftMutator: its Package.swift has only `.executable(name: "swift-mutator", targets: ["muter", "muterCore"])`, SwiftPM can't depend on an executable product as a library, and `struct MuterTestReport` is internal. But the proposed Q3 text drops SwiftInferProperties, which the original question names and which does ship library products (SwiftInferCore, SwiftInferTemplates, SwiftInferCLI and others). The rewrite would lose that case. SwiftCloneDetectorKit and SwiftEffectInference are correctly described as libraries.

**Change.** "Library vs CLI adapters: SwiftEffectInference, SwiftInferProperties (`SwiftInferCore` and others) and SwiftCloneDetector (`SwiftCloneDetectorKit`) ship library products. Linking them pins their versions together; parsing their JSON keeps them independent. SwiftMutator has no library product, so it can only be read from its results file or JSON report."

### 6. §6.3 — misleading, partly

> | T3 | Mutation testing | hours |

**Issue.** Overstated for a typical run, and it leaves out the fast incremental modes. SwiftMutator's own measurements of the whole SwiftProjectLint repo (2,463 mutants) give 19 to 39 minutes, depending on workers and release mode. Hours apply only to large runs or slower machines. `--since` on a PR takes seconds to minutes, which matters for the PR-reviewer use case in §5.

**Evidence.** SwiftMutator/Docs/release-and-workers-2026-10.md:44-50 (2,463 mutants: 39.2 min with 2 workers, 26.6 min with 4, 18.9 min in release), :25 (1 h 31 min on an 8-core machine), :116 (1,771 slower mutants estimated at one to two hours). Docs/since-2026-11.md (2.7 min for a four-file PR, 50 s with `--changed-lines`).

**Verifier.** release-and-workers-2026-10.md shows 2,463 mutants on SwiftProjectLint taking 39.2 min with 2 workers, 26.6 min with 4 and 18.9 min in release mode. since-2026-11.md shows 2.7 min and 50 s for a PR. So 'hours' overstates a typical whole run, and the `--since` mode matters for the PR-reviewer use case. Still, 'hours' isn't wrong in every case: 1 h 31 min on an 8-core machine, and one to two hours estimated for another project. Those figures come from an 18-core M5 Pro with `--skip-coverage`, so they shouldn't go into the table as if typical. The other cells are one or two words, and the proposed cell is far longer.

**Change.** | T3 | Mutation testing | tens of minutes to hours for a whole package; minutes for a branch with `--since` |

### 7. §8 (Weak tests / Genuinely under-tested) — gap, partly

> low test-to-code ratio, low coverage, low mutation score

**Issue.** With coverage on (the default), SwiftMutator doesn't create mutants in code no test ran. An untested function therefore has no mutation score at all, not a low one. A file no test ran shows up as a single `skipped (no coverage)` row. As written, the most under-tested functions would drop out of this signal for lack of a score. The tool also reports evidence of weak tests that the PRD doesn't use: kills made only by suspect tests (`killedOnlyBySuspectTests`, `mutationScoreWithoutSuspectOnlyKills`) and not-covered mutants.

**Evidence.** SwiftMutator/README.md:1302-1306 ("With coverage on, a mutant in code that coverage says no test ran is never made ... `--skip-coverage` makes them all"). Docs/test_report_json_example.md, `killedOnlyBySuspectTests` and `killingTestSummary.mutationScoreWithoutSuspectOnlyKills`.

**Verifier.** README lines 1302-1306 confirm it: with coverage on, a mutant in code no test ran is never made, the score leaves it out, and an untested file shows as one `skipped (no coverage)` row. `killedOnlyBySuspectTests` and `mutationScoreWithoutSuspectOnlyKills` exist in the JSON report docs. So the most under-tested functions would have no score. However, finding #0 has SwiftStats compute scores as SwiftMutator does, and folding these functions into the module and project score as low would break that match. The 'counts as low' rule should apply to the derived signals only.

**Change.** Add under the table: "For these signals, a function SwiftMutator made no mutants in because coverage found it untested counts as having a low mutation score, not a missing one. Module and project scores still follow SwiftMutator's rule; run it with `--skip-coverage` to get real scores for that code. Weak tests also uses SwiftMutator's not-covered mutants and suspect-only kills (`killedOnlyBySuspectTests`)."

### 8. §12 — gap, confirmed

> At least 95% of coverage / mutation / SwiftLint results map onto a function record.

**Issue.** SwiftMutator deliberately mutates code outside function bodies: stored-property and global initial values, default arguments, and top-level statements in `main.swift`. These mutants have no enclosing function. Without a rule for them, the 95% target counts them as failures to map, and they are hidden from the per-function view.

**Evidence.** SwiftMutator/README.md:884-895 ("Mutants outside function bodies": stored property / global initial values, default arguments, `main.swift` statements).

**Verifier.** README 'Mutants outside function bodies' (lines 884-895) confirms mutants in stored-property and global initial values, default arguments, and top-level statements in `main.swift`. None of these has an enclosing function, so as written the 95% mapping target in §12 would count them as failures, and nothing in §6.1 handles them. Attaching them to the enclosing type, file or function is consistent with the per-type roll-ups the PRD already uses. 'Attach to the file' implicitly covers `main.swift` statements.

**Change.** Add to §6.1: "Mutants and coverage regions outside a function body (property and global initial values, default arguments) attach to the enclosing type or file, and a default argument to its function. They count as mapped."

### 9. §8 (Best property-test target) — suggestion, partly

> A property test here likely kills those mutants.

**Issue.** This is an untested claim, stated as likely. SwiftMutator can check it. With `propertyTests` globs (or `--property-tests`), its JSON report adds `propertyKillSummary`, which splits kills into those made only by examples, only by properties, or by both, and names the property tests that killed the most mutants. The PRD doesn't use this output.

**Evidence.** SwiftMutator/Docs/test_report_json_example.md, `propertyKillSummary` table (`killedOnlyByExamples`, `killedOnlyByProperties`, `killedByBoth`, `properties`). MuterTestReport.swift:19-21.

**Verifier.** `propertyKillSummary` exists, is enabled by `propertyTests` or `--property-tests`, and splits kills between examples and properties. But it is a top-level summary of the whole run, not a per-function one, so on its own it can't confirm that a property test killed a given function's survivors. Per-mutant `killingTests` in the JSON (or `killedBy` in the results file) can. The PRD's 'likely' is already hedged, so this is a minor refinement.

**Change.** Why it matters: "A property test here may kill those mutants. Check it after the test is written: rerun SwiftMutator on the function's file, with `propertyTests` globs, and see whether the former survivors are now killed and by which test (each mutant's `killingTests`)."

### 10. §7.12 — error, partly

> broken down by **clone type** (1 = exact copy, 2 = renamed identifiers, 3 = edited copy)

**Issue.** SwiftCloneDetector's JSON output doesn't label clones by type. Each clone has only `fingerprint`, `mass`, `lineSpan`, `similarity` and `instances`. The top-level `mode` is just "type1-2" or "type3", and it says "type1-2" even for a mixed `--all` run. In the JSON, a near-miss (Type-3) clone can be told apart only by a non-null `similarity`. The default pass finds Type-1 and Type-2 together and never separates them, and sequence clones look like subtree clones. The per-clone pass is available only in text output (`[exact]`, `[near-miss]`, `[sequence]`) and in the library's `CloneClass.pass`. Type-2 also covers changed literals, not only renamed identifiers. The tool calls the groups "clone classes".

**Evidence.** SwiftCloneDetector/Sources/SwiftCloneDetectorKit/CloneReportJSON.swift:30-36 (per-clone fields), Reporters.swift:107-117 (`mode: nearMiss ? "type3" : "type1-2"`). swift-clone-detector/CloneDetectorCommand.swift:176-208 (`--type1` is exact-only; the default normalisation is `.type2`; `reportsNearMiss` is true only when near-miss is the single pass). CloneClass.swift:22 (`pass`). DetectionPass.swift:46-55. Normalization.swift:19-22 (Type-2 renames identifiers and literals).

**Verifier.** Confirmed. The JSON Clone has only fingerprint, mass, lineSpan, similarity and instances. `mode` is "type3" only when near-miss is the single pass, and otherwise "type1-2". The default normalisation is `.type2`, which renames identifiers and literals. `CloneClass.pass` is public in the Kit but missing from the JSON. But the proposed text leaves out the sequence pass. In an `--all` run, sequence classes also have a nil similarity, so they can't be told apart from exact or renamed classes in the JSON. The 'take the difference' route also needs separate runs per pass, not `--all`.

**Change.** "Clone classes (SwiftCloneDetector's term), broken down by kind: exact (1), renamed identifiers or literals (2), near-miss (3) and sequence (runs of statements or members). The tool's JSON doesn't label a class's kind, so the adapter either links `SwiftCloneDetectorKit` and reads `CloneClass.pass`, or runs each pass on its own: `--type1` for exact, the default pass minus the `--type1` results for renamed, `--type3` for near-miss and `--sequence` for sequence."

### 11. §7.12 — error, confirmed

> and by **size** (lines / tokens)

**Issue.** SwiftCloneDetector doesn't count tokens. It reports `mass`, the size of the shared subtree in AST nodes, and `lineSpan`, the lines the first instance spans. Its minimum-size settings are also in AST nodes (`--min-mass`) and lines (`--min-lines`).

**Evidence.** SwiftCloneDetector/Sources/SwiftCloneDetectorKit/CloneClass.swift:13-14 ("Size of the shared subtree in AST nodes"). CloneReportJSON.swift:32-33 (`mass`, `lineSpan`). Reporters.swift:41-44 (lineSpan is the first instance's end line − start line + 1).

**Verifier.** CloneClass.swift documents mass as the 'Size of the shared subtree in AST nodes'. The JSON has `mass` and `lineSpan`, and lineSpan is the first instance's end line minus its start line plus one. Tokens aren't counted anywhere. The proposed wording is correct.

**Change.** "and by size (lines, and mass in AST nodes)"

### 12. §7.12 — gap, confirmed

> Percentage of code in clones, per module and project, overall and per clone type

**Issue.** The tool doesn't report a percentage or a total line count. Its only aggregate is `duplicatedLines`: for each class, the first instance's line span × (instances − 1). That counts the redundant copies, not all cloned code. It counts raw lines, including blanks and comments inside the fragment, while §7.2 uses stripped lines. Instances can also overlap across passes in a merged run. So SwiftStats has to work out the percentage itself from instance ranges and its own line counts. The PRD should say which measure it uses.

**Evidence.** SwiftCloneDetector/Sources/SwiftCloneDetectorKit/Reporters.swift:41-52 (`duplicatedLineCount`), CloneReportJSON.swift:50-58 (report has `fileCount`, `duplicatedLines`, `cloneCount`; no total lines). LineSpan.swift:19-25 (raw line difference).

**Verifier.** Reporters.swift: `duplicatedLineCount` sums the first instance's lineSpan × (instances − 1) for each class. The report holds fileCount, duplicatedLines and cloneCount, with no total line count and no percentage. lineSpan is a raw line difference, so blank and comment lines inside a fragment count. CloneClass+Merge drops a class only when every instance lies inside a stronger or equal claim, so instances can still overlap across passes. SwiftStats has to compute the percentage itself, and the proposed definition is sound.

**Change.** "Percentage of code in clones: lines covered by any clone instance (merged, counted once), divided by the module's or project's lines, both counted as in §7.2. Also store the tool's own `duplicatedLines` (redundant copies only) for comparison with its output."

### 13. §7.12 — misleading, confirmed

> For each function: the clone groups it belongs to and its twins

**Issue.** Clone fragments aren't functions. They are subtrees rooted at any of 14 anchor kinds: functions, but also single statements, `if`/`guard`/`switch`/`for`/`while`, closures, variable declarations, accessors and members. The sequence pass adds runs of consecutive statements or members, which can span several declarations. One instance may sit inside a function, cover part of one, or cover several. Only when both instances are whole functions is there a clean function-to-function twin.

**Evidence.** SwiftCloneDetector/Sources/SwiftCloneDetectorKit/AnchorKinds.swift:13-29. README.md "Sequence clones" and "No single pass finds everything" (duplication spanning more than one declaration). DetectionPass.swift:19-20.

**Verifier.** AnchorKinds.swift lists 14 root kinds: codeBlockItem, memberBlockItem, function, init, subscript, accessor, variable, closure, if, guard, for, while, switch and switchCase. DetectionPass.swift says the sequence pass matches runs of consecutive statements or members, spanning more than one declaration. So 'clone groups it belongs to and its twins' assumes the fragments are whole functions, which they often aren't. The proposed overlap-based wording is right.

**Change.** "For each function: the clone classes whose instances overlap it, with the share of its lines covered. A function's twins are the functions that overlap the other instances of the same class. Mark whether the instance is the whole function or part of it."

### 14. §8 (Divergent clones) — gap, confirmed

> clone twins where git shows a fix or change to one copy but not the other

**Issue.** Exact and renamed clones (Type 1/2) drop out of SwiftCloneDetector's report as soon as one copy is changed in structure, which is what a real fix does. So the current snapshot no longer shows those two copies as twins, and the signal can't be computed from the current clone report alone. The clone's `fingerprint` doesn't help: it hashes mass, instance count and file paths, so it changes when one copy changes.

**Evidence.** SwiftCloneDetector/Sources/SwiftCloneDetectorKit/CloneFingerprint.swift:13-32 (fingerprint folds mass, instance count, sorted paths). README.md "How it works" (exact structural match; near-miss pass needed once a statement is inserted). DetectionPass.swift:16-18.

**Verifier.** The subtree pass compares structure exactly under normalisation, so a structural fix to one copy removes the class from the exact report, and only the near-miss pass might still match it. cloneFingerprint hashes mass, instance count, a near-miss similarity bucket and sorted paths, so a change to one copy alters it. The current exact report can't show twins that have diverged. The PRD keeps per-commit snapshots and T0 backfill, so the proposal to use an earlier snapshot's twins, or the near-miss pass, is workable.

**Change.** Definition: "Clone twins from an earlier snapshot (or from the near-miss pass, `--type3` / `--all`, in the current one) where git shows a change to one copy since that snapshot and none to the other."

### 15. §9 — suggestion, partly

> Adapters prefer linking a tool's library product (SwiftEffectInference already ships as a library) and fall back to parsing its JSON output (SwiftMutator, SwiftCloneDetector, ...)

**Issue.** SwiftCloneDetector also ships a library, `SwiftCloneDetectorKit`. Its public finders (`CloneFinder`, `NearMissFinder`, `SequenceCloneFinder`) return `CloneClass` values that carry `pass`, which the JSON leaves out. If the CLI is used instead, the adapter has to handle three things: exit code 2 means clones were found, not failure; instance paths are the scan path joined with the relative file path, not normalised; and the JSON `version` is a fixed "0.1.0", so it won't tell builds apart.

**Evidence.** SwiftCloneDetector/Package.swift (products: `.library(name: "SwiftCloneDetectorKit", ...)`). CloneFinder.swift:13,55, NearMissFinder.swift:19,89, SequenceCloneFinder.swift:21,107 (public). swift-clone-detector/CloneDetectorCommand.swift:32 (`kClonesFoundExitCode = 2`). CommandLineSupport.swift:64-67 (path built from the argument). ToolInfo.swift:13 (`version = "0.1.0"`).

**Verifier.** Confirmed. Package.swift has the `SwiftCloneDetectorKit` library product. CloneFinder, NearMissFinder and SequenceCloneFinder are public and return CloneClass values that carry `pass`. `kClonesFoundExitCode = 2`. Directory paths are built as path + '/' + item without normalising. ToolInfo.version is the fixed "0.1.0". But 'record the tool's git commit' isn't generally possible for an installed binary. Recording the executable's path and SHA-256 works in every case, and matches how SwiftMutator records its own provenance.

**Change.** "Adapters prefer linking a tool's library product (SwiftEffectInference and SwiftCloneDetectorKit already ship as libraries) ... For the SwiftCloneDetector CLI, exit code 2 means clones were found, not a failure. Pass the package root so paths are stable. Its version string is fixed at 0.1.0, so record the executable's path and SHA-256 (or its git commit when built from source)."

### 16. §7.12 / 6.2 — gap, confirmed

> **Clone ratio over time** (from snapshots), to show whether duplication is growing

**Issue.** Clone counts depend heavily on settings. Defaults are `--min-mass 20` (AST nodes), `--min-lines 2`, `--similarity 0.85`, `--min-identifier-overlap 0.25` and `--min-distinctiveness 1.55`. Generated files are skipped by default and test files are scanned. The README's own examples use other values (60, 90, 40). The PRD doesn't fix the settings, and §6.2 records collector versions but not their options. A trend is only valid if every snapshot used the same settings and passes.

**Evidence.** SwiftCloneDetector/Sources/swift-clone-detector/CloneDetectorCommand.swift:16-28 (defaults), :140-147 (`--include-generated`, off by default). README.md "Usage" (examples with `--min-mass 60/90/40`).

**Verifier.** CloneDetectorCommand.swift sets the defaults: min-mass 20, min-lines 2, similarity 0.85, min-identifier-overlap 0.25 and min-distinctiveness 1.55. `--include-generated` is off, and nothing excludes tests by default. The README examples use `--min-mass` 60, 90 and 40. §6.2 records collector versions but not their options, so a trend across snapshots taken with different settings would be meaningless. The proposed edits are sound.

**Change.** Add to §7.12: "SwiftStats runs SwiftCloneDetector with fixed settings (`--all`, the tool's defaults unless configured) and stores them in the snapshot. Trends compare only snapshots with the same settings. Test targets are reported separately from production code." In §6.2, change "with what versions" to "with what versions and options".

**Checked and correct:**

- SwiftMutator emits JSON: `-f json` / `--report json:path` (README.md:1253-1262), plus results.jsonl and summary.json
- SwiftMutator JSON gives operator and location per mutant: `mutationPoint.mutationOperatorId` (e.g. RelationalOperatorReplacement, SwapTernary), `path`, `mutationPoint.position.line/column`, `key`, `testSuiteOutcome` (MuterTestReport.swift:234-258, MutationSchema.swift:149-152)
- Killed, survived and timed out are real SwiftMutator categories (`mutantsByOutcome.killed/survived/timedOut`)
- A mutation score per file and per project exists in the tool (`fileReports[].mutationScore`, `globalMutationScore`); per function has to be derived by SwiftStats, as §7.9 implies
- §9 diagram: 'SwiftMutator JSON → Mutation adapter' is accurate as an input source
- §6.3: mutation testing needs a build and a test run per mutant, so it is the costliest tier and right to make opt-in
- §6.2: SwiftMutator's JSON `run` block records its version, executable SHA-256 and toolchain (`testCommandVersion`), which fits the snapshot provenance in §6.2 (Docs/test_report_json_example.md, `run`)
- SwiftCloneDetector emits JSON (`--format json`) and SARIF; output uses sorted keys and is byte-stable (README 'Output formats', Reporters.swift:25-29)
- SwiftCloneDetector detects Type 1, Type 2 (default) and Type 3 (`--type3`/`--near`) clones, and not Type 4 (README 'What it catches', CloneDetectorCommand.swift:55-65)
- SwiftCloneDetector is syntax-only (SwiftSyntax/SwiftParser, no build), so T0 in §7.12 is correct
- SwiftCloneDetector reports per-instance file path and start/end line and column, enough to map onto function source ranges (CloneReportJSON.swift:13-27)
- SwiftCloneDetector has a stable per-clone `fingerprint` that ignores line drift, usable for tracking a clone class across snapshots while it is unchanged (CloneFingerprint.swift:13-32)

## Third-party tools (SwiftLint, llvm-cov, indexstore-db, git, Periphery, SwiftPM)

### 1. §7.3 — gap, confirmed

> Cyclomatic complexity** (match SwiftLint's `cyclomatic_complexity` counting so numbers agree)

**Issue.** The PRD doesn't say what SwiftLint's counting is, and it differs from textbook McCabe in ways that decide whether numbers agree. SwiftLint starts at 0, not 1. It adds 1 for each `if` (each `else if` too), `guard`, `for`, `while`, `repeat` and `catch`, and for each `case` including `default`; each `fallthrough` takes 1 off. It does not count `&&`, `||`, `??`, the ternary `?:` or `#if`. It measures only `func` and `init` bodies: computed-property accessors, subscripts, `deinit` and top-level closures get no score. Closures inside a function count towards that function. Nested functions are skipped. `ignores_case_statements` (default false) turns off the `case` and `fallthrough` counting.

**Evidence.** SwiftLint/Source/SwiftLintBuiltInRules/Rules/Metrics/CyclomaticComplexityRule.swift: Visitor visits only FunctionDeclSyntax and InitializerDeclSyntax (lines ~77-93); ComplexityVisitor starts at `complexity = 0` and counts ForStmt, IfExpr, GuardStmt, RepeatStmt, WhileStmt, CatchClause, SwitchCase, with FallThroughStmt as -1, and skips nested func/init. RuleConfigurations/CyclomaticComplexityConfiguration.swift: warning 10, error 20, `ignores_case_statements` = false. Checked with swiftlint 0.65.1 at `warning: 0` on a test file: a function with guard + if(&&) + 3-case switch (`??` and a ternary inside) scored 5; a one-`if` method scored 1; a straight-line method was not reported; a computed property with if/else-if was not reported; two `if`s inside a `map` closure scored 2 for the enclosing method.

**Verifier.** Checked SwiftLint source (GitHub_projects/SwiftLint, 0.65.1-21): Visitor only handles FunctionDeclSyntax and InitializerDeclSyntax. ComplexityVisitor starts at 0, adds 1 for For/If/Guard/Repeat/While/Catch/SwitchCase, takes 1 off for fallthrough, and skips nested func/init. The config is warning 10, error 20, ignores_case_statements false. Ran swiftlint 0.65.1 with warning 0 on a test file: guard + if(&&) + 3-case switch (with ?? and ternary) scored 5, a one-if function 1, a closure with two ifs 2. The straight-line function and the computed property with if/else-if were not reported. The proposed text is accurate.

**Change.** - **Cyclomatic complexity**, counted the way SwiftLint's `cyclomatic_complexity` counts it so the numbers agree: start at 0; +1 for each `if`, `else if`, `guard`, `for`, `while`, `repeat`, `catch` and `case` (including `default`); −1 for each `fallthrough`; `&&`, `||`, `??`, `?:` and `#if` are not counted. Closures count towards the function that contains them; nested functions are scored separately. Honour `ignores_case_statements` from the package's `.swiftlint.yml`. SwiftLint scores only `func` and `init`, so accessors, subscripts and `deinit` get a SwiftStats-only score, marked as such. Record the SwiftLint version, since the counting has changed between releases.

### 2. §11 — gap, confirmed

> Complexity numbers match SwiftLint on a sample package

**Issue.** SwiftLint only prints a function's complexity when it breaks the warning threshold (default 10), and never for a function scoring 0. So there's nothing to compare against unless the check sets the threshold to 0, and functions that print nothing count as 0.

**Evidence.** CyclomaticComplexityRule.swift validate(): a violation (with "currently complexity is N" in the reason) is only appended when `complexity > parameter.value`. Run with `cyclomatic_complexity: {warning: 0}`, swiftlint 0.65.1 reported every function scoring 1 or more and nothing for the function scoring 0.

**Verifier.** validate() only appends a violation when complexity > parameter.value. With warning 0, functions scoring 0 (a straight-line func, a branchless init) printed nothing and every other function printed its score. Without that setup there is nothing to compare against.

**Change.** Complexity numbers match SwiftLint on a sample package (SwiftLint run with `only_rules: [cyclomatic_complexity]` and `warning: 0`; functions SwiftLint doesn't report count as 0; accessors and `deinit` left out of the comparison)

### 3. §7.3 — misleading, confirmed

> Cognitive complexity** (Sonar's measure, which treats flat `switch`/`guard` more fairly)

**Issue.** Half right. The SonarSource spec does count a whole `switch` once, not once per case. But it says nothing about `guard`. A `guard` scores +1 if it is treated as an `if`, the same as cyclomatic, and 0 only if it is treated as an early exit, which the spec doesn't penalise. So whether `guard` gets fairer treatment depends on a choice SwiftStats hasn't made yet (§14 Q6).

**Evidence.** SonarSource, "Cognitive Complexity", v1.7, 29 August 2023: "A switch and all its cases combined incurs a single structural increment"; "because an early return can often make code much clearer, no other jumps or early exits cause an increment"; `guard` is not mentioned anywhere in the document.

**Verifier.** Read the SonarSource PDF (29 August 2023, Version 1.7). It says a switch and all its cases get a single structural increment, and that no early exits other than labelled jumps cause an increment. 'guard' appears nowhere in the document. Its null-coalescing example is `a?.myObj`, so ignoring optional chaining and ?? is supported. Whether guard counts is genuinely open.

**Change.** - **Cognitive complexity** (SonarSource's specification, v1.7, 2023). It counts a whole `switch` once rather than per case, adds a penalty for nesting, and ignores optional chaining and `??`. The spec doesn't cover `guard`; whether a `guard` counts like an `if` or is free like an early return is decided under §14 Q6.

### 4. §14 — gap, confirmed

> **Cognitive complexity rules for Swift-specific constructs** (`guard`, `if let`, result builders): adopt Sonar's rules as-is or adapt?

**Issue.** The list mixes up what the spec already settles and what is actually open. Settled: closures add no increment of their own but raise the nesting level; `?.` and `??` are ignored; each `catch` is +1; `else` and `else if` are +1 with no nesting penalty; `#if` is +1; labelled `break`/`continue` is +1; each run of like logical operators is +1; recursion is +1. Open: `guard`; comma-separated condition lists; optional binding and `if case`; `try?`/`try!`; `defer`; `repeat`; multi-pattern cases and `where` clauses; result-builder bodies.

**Evidence.** SonarSource "Cognitive Complexity" v1.7, Appendix B1–B3: increments for if, else if, else, ternary, switch, for, while, do while, catch, labelled jumps, sequences of binary logical operators, recursion. Nesting level is raised by those plus "nested methods and method-like structures such as lambdas". "Cognitive Complexity ignores null-coalescing operators". `#if` is listed among the conditionals. None of guard, if let, defer, try? or result builders appears.

**Verifier.** Spec v1.7 settles these: lambdas and nested methods add no structural increment but raise nesting; null-coalescing is ignored; each catch is +1; else if / else are hybrid increments with no nesting increment; #if is listed among the conditionals (and the example scores it +1); goto and labelled break/continue are +1; each sequence of like logical operators is +1; recursion is +1. No mention of guard, defer, optional binding, try? or builders. The proposed Q6 matches the spec.

**Change.** 6. **Cognitive complexity for Swift.** SonarSource's spec already covers closures (no increment, but they raise the nesting level), `?.` and `??` (ignored), `catch`, `else`/`else if`, `#if`, labelled `break`/`continue` and runs of `&&`/`||`. Still to decide: does `guard` count like an `if` or as a free early exit? Is a comma-separated condition list one run of `&&`? Do optional binding, `if case`, `try?` and `defer` add anything? Do the `if`/`switch` inside result-builder bodies (e.g. SwiftUI `body`) count in full?

### 5. §7.8 — error, confirmed

> **Line coverage** and **region/branch coverage** per function (`swift test --enable-code-coverage` → `llvm-cov export`)

**Issue.** Swift has no branch coverage in `llvm-cov`; only line and region coverage are available. The export also needs work before it can be joined. Function names are mangled. Closures and autoclosures (e.g. the right-hand side of `&&` and `??`) are separate function records. Accessors are their own records. There are no per-function line totals. And the export includes test files and SwiftPM's generated `test_entry_point.swift`.

**Evidence.** Test package built with Swift 6.4.2 (Xcode), `swift test --enable-code-coverage`, reading `.build/out/Products/Debug/codecov/Demo.json` (llvm.coverage.json.export 3.0.1). Every function had `branches: []` and `mcdc_records: []`, and the file summary showed `branches.count 0`. Function names were `$s4Demo8classify_4flagSSSi_SbtF`, its autoclosures `...SbtFSbyKXEfu_` / `...fu0_`, a closure `...SbtFS2iXEfU_`, and the getter `$sSi4DemoE12isEvenNumberSbvg`. Function objects carry only name, count, regions, branches, mcdc_records and filenames. The `files` list included Tests/DemoTests/DemoTests.swift and .build/.../test_entry_point.swift. A generic method called with two types produced one record (functions 7 = instantiations 7).

**Verifier.** Swift 6.4.2, swift test --enable-code-coverage, JSON at the --show-codecov-path location (llvm.coverage.json.export 3.0.1). Every function has empty branches, and totals.branches.count is 0. Function keys are only branches, count, filenames, mcdc_records, name, regions. Names are mangled. The && and ?? autoclosures (fu_/fu0_) and closures (fU_) are separate records, as is the getter (...Sbvg). Box.map called with Int and String produced one record. The files list includes test_entry_point.swift and DemoTests.swift.

**Change.** - **Line coverage** and **region coverage** per function (`swift test --enable-code-coverage`, then the JSON at `swift test --show-codecov-path`). Swift emits no branch records, so there is no branch coverage. Function names are mangled; demangle them with `swift demangle`. Closures and autoclosures (the right-hand side of `&&`, `||`, `??`) appear as separate functions and are folded into their enclosing function by source range. Accessors are separate records too. The export has no per-function line totals, so line coverage is worked out from the file's segments over the function's range. Test files and generated sources are dropped. Generic functions get one record each in debug builds.

### 6. §1 — error, confirmed

> 40% branch coverage

**Issue.** The example uses a metric SwiftStats can't produce for Swift: `llvm-cov` has no branch coverage for Swift code (see §7.8).

**Evidence.** llvm-cov export of a Swift package: all `branches` arrays empty and `totals.branches.count` 0 (Swift 6.4.2, see the §7.8 finding).

**Verifier.** Swift coverage export has no branch data (verified above), so '40% branch coverage' names a metric SwiftStats can't produce. Region coverage is available.

**Change.** *"pure, complex, 40% region coverage, 6 surviving mutants, 2 untested Strong-tier property candidates, changed 14 times this quarter"*

### 7. §11 — error, confirmed

> Per-function line + branch coverage; "risky + untested" signal

**Issue.** M5 can't be done as written, because Swift coverage has no branch data.

**Evidence.** See the §7.8 finding: `branches` is empty for every Swift function in the llvm-cov export.

**Verifier.** Same evidence: no branch records for Swift. M5's done-when criterion can't be met as written. Line + region coverage with closures folded in is achievable.

**Change.** Per-function line + region coverage, with closures folded into their parent; "risky + untested" signal

### 8. §6.1 — error, confirmed

> **USR** (Unified Symbol Resolution) from indexstore-db: stable across renames of the file and unambiguous for overloads. Needs a build.

**Issue.** A USR is not stable across file renames for `private` and `fileprivate` declarations: their mangling includes a discriminator derived from the file name. The PRD also doesn't list what does change a USR. A USR encodes the module, the enclosing type or extension context, the base name, the argument labels, the parameter and result types and effects (`throws`, `async`), and the generic signature. So renaming the function, changing labels or types, moving it to another type or module, or changing it from `private` to `internal` all give a new USR. Moving a non-private function to another file in the same module keeps it. Accessors have their own USRs (`…vg` getter vs `…vp` property).

**Evidence.** Compiled the same file as A.swift and as Renamed.swift with `-index-store-path` and read the USRs through libIndexStore.dylib: `private func helper` went from `s:1M6helper33_807E3D81CC6CDD898084F3279464DDF9LLyS2iF` to `s:1M6helper33_3F7496E3A018B091969AC2F1D23D1FD0LLyS2iF`, while internal `labelled(count:)` stayed `s:1M8labelled5countS2i_tF` in both. Demangled: `M.(helper in _807E…)(Swift.Int) -> Swift.Int`.

**Verifier.** Compiled the same source as A.swift and Renamed.swift with -index-store-path. The private helper's USR changed from s:1M6helper33_807E...LLyS2iF to s:1M6helper33_3F74...LLyS2iF, while internal s:1M8labelled5countS2i_tF stayed the same. The index also holds separate accessor USRs (…Sbvg vs …Sbvp). The mangling encodes module, context, name, labels, types and effects, so the listed changes all alter the USR.

**Change.** 1. **USR** (Unified Symbol Resolution) from the index store, read with indexstore-db. Unambiguous for overloads. It stays the same when a non-private function moves to another file in the same module. It changes when the function is renamed, its argument labels, parameter or return types or effects change, it moves to another type or module, or its access changes to or from `private`/`fileprivate`. `private` and `fileprivate` USRs also change when the file is renamed, because they include a file-based discriminator. Needs a build.

### 9. §6.1 — suggestion, confirmed

> External tools report locations as file:line (coverage, mutants, SwiftLint), so **every function record must store its source range** so results can be mapped back to it.

**Issue.** Two sources give the USR directly, which the PRD doesn't mention. An llvm-cov function name is the mangled symbol, and `s:` plus the name without its leading `$s` equals the indexstore USR. Periphery's JSON has an `ids` field holding USRs. Joining on these needs no range mapping, which matters for the 95% mapping target (§12).

**Evidence.** Coverage function `$s4Demo8classify_4flagSSSi_SbtF` vs index USR `s:4Demo8classify_4flagSSSi_SbtF`; `$s4Demo3BoxV3mapyACyqd__Gqd__xXElF` vs `s:4Demo3BoxV3mapyACyqd__Gqd__xXElF` (same test build, USRs read from .build/out/v5 via libIndexStore). Periphery 2.21.2 `--format json` result: `"ids": ["s:4Demo3BoxV"]`, `"location": ".../Demo.swift:1:15"`.

**Verifier.** Coverage names $s4Demo8classify_4flagSSSi_SbtF and $s4Demo3BoxV3mapyACyqd__Gqd__xXElF match the index USRs s:4Demo8classify_4flagSSSi_SbtF and s:4Demo3BoxV3mapyACyqd__Gqd__xXElF. The getter $s…Sbvg matches the index's s:…Sbvg. Periphery 2.21.2 JSON has ids such as ['s:4Demo3BoxV']. Closure records have no USR, but the §7.8 change already folds those by range.

**Change.** Add after the paragraph: "Two sources carry the USR already: an `llvm-cov` function name is the mangled symbol (USR = `s:` + the name without its leading `$s`), and Periphery's JSON lists USRs in `ids`. Join those on USR when the index is available, and by source range otherwise."

### 10. §6.1 / 7.6 — gap, confirmed

> Needs a build.

**Issue.** The PRD doesn't say where SwiftPM puts the index store, and the location now depends on the build system. Swift 6.4's default backend (`swiftbuild`) writes it under `.build/out/` (seen as `.build/out/v5`), not the old `.build/<triple>/debug/index/store`. Tools that guess the old path break; Periphery 2.21.2 does (see the §7.6a finding). SwiftPM indexes debug builds by default, and test targets always. indexstore-db also needs a database directory and the toolchain's `libIndexStore.dylib`.

**Evidence.** swift-package-manager Sources/Build/BuildPlan/BuildPlan.swift:53-75 (`.auto` mode: index for debug builds, and always for test targets; path `<buildProducts>/index/store` under the native build system). Sources/SwiftBuildSupport/SwiftBuildSystem.swift:1052-1075 (path handled by the PIF builder in `.auto` mode). `swift build --help`: `--build-system` default `swiftbuild`, `native` deprecated. In the test build the store was `.build/out/v5` by default and `.build/arm64-apple-macosx/debug/index/store/v5` with `--build-system native`. indexstore-db Sources/IndexStoreDB/IndexStoreDB.swift:79: `init(storePath:databasePath:library:...)`.

**Verifier.** `swift build --help` gives a --build-system default of swiftbuild, with native deprecated. The test package's store was at .build/out/v5. BuildPlan.swift indexStoreArguments in .auto mode indexes debug builds, and test targets always. Periphery 2.21.2 failed looking for .build/debug/index/store.

**Change.** Add to §6.1 item 1: "SwiftPM writes the index store during debug builds. Its location depends on the build system: under `.build/out/` with the default Swift Build backend, and `.build/<triple>/debug/index/store` with `--build-system native`. SwiftStats finds the store rather than hard-coding a path, and records which build system produced it. indexstore-db also needs a database directory and the toolchain's `libIndexStore.dylib`."

### 11. §7.13 — contradiction, partly

> **Tracking through renames and moves:** follow history by function identity (§6.1) rather than file path.

**Issue.** This contradicts §6.1 and the backfill plan. USR identity needs a build, but backfill and history run T0 only, so past commits have no USRs. Even with a build, a USR changes when a function is renamed or its signature changes (and for private functions, when the file is renamed). The fallback key "breaks when code moves". Neither identity tracks a function through a rename on its own.

**Evidence.** PRD §6.1 ("Needs a build"; fallback "breaks when code moves"), §7.13 ("T1–T3 are not backfilled by default"). USR test: private function USR changed on file rename; USR encodes name and labels (`s:1M8labelled5countS2i_tF`).

**Verifier.** The contradiction is real. History (TH) and backfill (T0) don't build past commits, so they have no USRs. A USR changes on a function rename, a signature change, and (for private functions) a file rename, and the fallback key breaks on moves. But the proposed text blames only backfill running T0. The history collector itself is TH and doesn't build either, so the reason should cover both.

**Change.** **Tracking through renames and moves:** neither identity in §6.1 survives a rename on its own, and past commits have no USRs, because neither the history collector nor backfill builds them. Match functions between neighbouring commits by syntax: same fallback key first, then the same body hash under a new name or file, then a similar body. Record each match with how it was made, so a guessed rename can be told apart from a certain one.

### 12. §7.13 — error, partly

> Use `git log --follow` for files and `git log -L` (or diffing parsed syntax trees between commits) for functions.

**Issue.** Git has no built-in Swift funcname driver. Without one, `git log -L :name:file` uses the default pattern, which only matches lines starting at column 0, so methods inside types fail with "no match". With a custom `diff.swift.xfuncname` it works, but `-L` matches by regex (overloads are ambiguous), walks one file, and loses the history when the function moves to another file. `--follow` handles one file at a time and uses a similarity guess; in a test it credited the new file with the old file's history.

**Evidence.** git 2.54.0 (Apple Git-157): `git help gitattributes` lists built-in drivers ada, bash, …, golang, kotlin, objc, python, rust, scheme, tex, with no swift. In a test repo, `git log -L :compute:F.swift` (indented method) gave "fatal: -L parameter 'compute' starting at line 1: no match", with or without `*.swift diff=swift`. With `-c diff.swift.xfuncname='^[ \t]*(func|struct)[ \t].*$'` it worked, and it followed a whole-file `git mv`. After moving the method into a new H.swift it showed only the move commit. `git log --follow -- H.swift` listed G.swift's earlier commits as H's. `git help log`: `--follow` "works only for a single file"; `-L` is "limited to a walk starting from a single revision".

**Verifier.** Confirmed with git 2.54.0. The gitattributes built-in drivers include golang and kotlin but no swift. `git log -L :compute:F.swift` on an indented method fails with 'no match'. With `*.swift diff=swift` plus `-c diff.swift.xfuncname=...` it follows the function through both commits. The proposed text says only the -c pattern is needed, but normally the `diff=swift` attribute is needed too. Without it, my test gave incomplete history (one commit of two).

**Change.** Use `git log --follow` for single files only; its rename detection is a similarity guess and can credit a new file with another file's history. For functions, diff parsed syntax trees between commits. Git has no built-in Swift driver, so `git log -L :name:file` needs a `*.swift diff=swift` attribute and a `diff.swift.xfuncname` pattern (passed with `-c`). Even then it matches by regex (overloads are ambiguous) and loses a function that moves to another file. Use `git log -L <start>,<end>:<file>` with the record's source range only as a cross-check.

### 13. §7.6a — error, confirmed

> **Test-only code**: production declarations referenced only from test targets

**Issue.** Periphery doesn't produce this. It treats XCTest test methods as roots, so code used only by XCTest counts as used and isn't reported. Periphery 2.21.2 doesn't recognise Swift Testing `@Test` functions: it reports the tests themselves as unused, and code used only by them as plain "unused", mixed in with truly dead code. Getting test-only code takes a second pass or an index query.

**Evidence.** Periphery 2.21.2 on a test package: `func onlyUsedByXCTest()` called only from an XCTestCase method was not reported; `func onlyUsedByTests()` called only from a Swift Testing `@Test` was reported `unused`, and so was `function.free classifies()` (the `@Test` itself, DemoTests.swift:3:12). `periphery scan --help` has no option about test-only references.

**Verifier.** Periphery 2.21.2 on a test package: onlyUsedByXCTest (called only from an XCTestCase method) was not reported unused, only redundantPublicAccessibility. onlyUsedByTests (called only from an @Test) was reported unused, and so was the @Test function classifies() itself. With --retain-public, labelled(count:) and helper, used only via the @Test, were also reported unused. There is no test-only option in scan --help.

**Change.** - **Test-only code**: production declarations referenced only from test targets. Periphery doesn't report this. Work it out from the index: production declarations whose only references come from test targets. Periphery 2.21.2 also doesn't recognise Swift Testing `@Test` functions: it reports them, and code only they use, as unused. Drop results inside test targets, and treat "unused" in a Swift Testing package as "unused or test-only" until checked against the index.

### 14. §7.6a — misleading, confirmed

> **Unused parameters** and **unused imports**

**Issue.** Periphery does report unused parameters and unused enum cases. But it only reports unused imports of modules it scanned, meaning the package's own targets. An unused `import Foundation` or third-party import is not reported.

**Evidence.** Periphery 2.21.2 JSON on a test package: `var.parameter unusedFlag ['unused']`, `enumelement green ['unused']`, and `module Util ['unused']` for an unused `import Util` of a sibling target. An unused `import Foundation` in the same file was not reported.

**Verifier.** Periphery 2.21.2 reported `module Util ['unused']` for the unused import of a sibling target and `var.parameter unusedFlag ['unused']`. The unused `import Foundation` in the same file was not reported.

**Change.** - **Unused parameters** and **unused imports** (Periphery reports imports only of the package's own modules; unused imports of Foundation, system or third-party modules are not detected)

### 15. §7.6a — gap, confirmed

> Use **Periphery** as the primary source.

**Issue.** Several things the adapter must handle are missing. Periphery needs a build and runs `swift build` itself. Version 2.21.2 looks for the old native index path, so with Swift 6.4's default build system it fails unless given `--index-store-path` (which skips its build) or `-- --build-system native`. Without `--retain-public`, all public API of a library with no in-package caller is reported unused; with it, redundant-public findings disappear. The JSON gives kind, name, accessibility, `hints` (`unused`, `redundantPublicAccessibility`, ...), `ids` (USRs) and `location` (file:line:col). The section's heading says T0/T1, but everything from Periphery is T1.

**Evidence.** `periphery version` gives 2.21.2. A default scan ran `swift build --target DemoTests`, then failed with "index store path does not exist: .../.build/debug/index/store". `--index-store-path .build/out` (after `swift build --build-tests`) worked, and so did `-- --build-system native`. Without `--retain-public`, `struct Box`, `classify(_:flag:)` and other public API were reported `unused`. With it they weren't, and no `redundantPublicAccessibility` result appeared. Without it, `entry()` and `NotUsedOutside` got `redundantPublicAccessibility`. `periphery scan --help` lists `--format json`, `--retain-public`, `--index-store-path` ("Implies '--skip-build'") and `--disable-redundant-public-analysis`.

**Verifier.** A default `periphery scan` failed with 'index store path does not exist: .../.build/debug/index/store'. `--index-store-path .build/out` worked, after warnings that it implies --skip-build. Without --retain-public, public API (Box, classify, utilThing...) was reported unused. With it, those and the redundantPublicAccessibility result disappeared. The JSON has kind, name, hints, ids (USRs) and location. Help lists --retain-public, --index-store-path and --disable-redundant-public-analysis. The -- --build-system native route is not used in the proposed text.

**Change.** Use **Periphery** as the primary source (T1: it needs a build and an index store). Run it as `periphery scan --format json --index-store-path <store>` after SwiftStats's own build, rather than letting Periphery build: version 2.21.2 looks for the old native index path and fails with Swift 6.4's default build system. For libraries pass `--retain-public`; note that this hides Periphery's redundant-public findings, so run once without it if those are wanted for §7.5. Its JSON gives kind, accessibility, `hints`, USRs (`ids`) and `file:line:col`.

### 16. §7.7 — misleading, partly

> **Type-check time per function** (`-Xfrontend -debug-time-function-bodies`). Motivation: the 12-arm `+` chain in SwiftInferProperties that passed locally and timed out on the CI runner.

**Issue.** Under SwiftPM the flag has to go through `-Xswiftc`. With Swift 6.4's default build system its output only appears with `-v`. It covers only files that were recompiled, so it needs a clean build. Each function appears more than once (one line per frontend job). Lines are keyed by file:line:col and a description, not a USR. The motivating case was a single expression in a test target that the local toolchain type-checked fine. The CI failure came from an older toolchain, so local timing may not have flagged it, and the expression-level flag is `-warn-long-expression-type-checking`.

**Evidence.** Test package, Swift 6.4.2. `swift build -Xswiftc -Xfrontend -Xswiftc -debug-time-function-bodies` after a touch printed no timings; adding `-v` printed lines like `9.49ms	.../Demo.swift:7:13	global function Demo.(file).classify(_:flag:)`, with getters repeated. `-Xswiftc -Xfrontend -Xswiftc -warn-long-function-bodies=1` printed `warning: global function 'classify(_:flag:)' took 9ms to type-check (limit: 1ms)` without `-v`. With `--build-system native` the timings printed without `-v`. SwiftInferProperties commit bbd634c: the chain was in SuggestionRendererStatsTests (a test file); "Local Swift 6.3.1 type-checks it fine; the GitHub-hosted macOS runner's older toolchain trips the type-checker timeout".

**Verifier.** Confirmed: under the default build system the timings print only with -v (0 lines without it, many with it), and only for recompiled files. Lines are keyed by file:line:col. Commit bbd634c puts the chain in a test file and blames the CI runner's older toolchain. Two parts of the proposal are wrong. The repeats I saw were six identical entries at one location (the implicit accessors of a stored property), not one per compiler job; other functions appeared once. And 'Local timings flag such expressions as slow' overclaims, since the commit says the local toolchain type-checked it fine.

**Change.** - **Type-check time per function**: `swift build -v -Xswiftc -Xfrontend -Xswiftc -debug-time-function-bodies` from a clean build, test targets included (without `-v` the default build system prints no timings). Lines are keyed by file:line:col, not USR, and implicit accessors can repeat at one location, so sum the entries per location and map them to a function by source range. Also collect `-warn-long-expression-type-checking=<ms>` warnings for single slow expressions. Motivation: the 12-arm `+` chain in a SwiftInferProperties test, which type-checked locally but timed out on the CI runner's older toolchain. Local timings can show that an expression is slow; they can't show whether another toolchain will time out.

### 17. §7.14 — error, confirmed

> Direct and transitive package dependencies (from `Package.resolved`)

**Issue.** `Package.resolved` is a flat list of pins (identity, kind, location, version/revision/branch). It includes transitive packages but doesn't say which are direct or who depends on whom. It leaves out `path:` dependencies. Many libraries don't commit it: swift-algorithms ignores it, and swift-collections has none at the root. The graph comes from `swift package show-dependencies --format json`, but that needs dependencies resolved (possibly over the network), so it isn't strictly T0.

**Evidence.** swift-package-manager Sources/PackageGraph/ResolvedPackagesStore.swift:508-512 (V3: version, originHash, pins). Sources/Workspace/Workspace+ResolvedPackages.swift:152-154: `.edited, .fileSystem, .custom` produce no pin. Sources/Commands/Utilities/DependenciesSerializer.swift:131-146: JSONDumper prints identity, name, url, version, path, traits and nested `dependencies`. SwiftProjectLint/Package.resolved has 11 pins and none of its six `.package(path: "Packages/...")` deps. swift-algorithms/.gitignore:7 is `Package.resolved`; `git -C swift-collections ls-files` shows Package.resolved only under Benchmarks/ and Utils/.

**Verifier.** JSONDumper in DependenciesSerializer.swift prints nested dependencies. Workspace+ResolvedPackages.swift returns no pin for .edited/.fileSystem/.custom. SwiftProjectLint's Package.resolved has 11 pins and none of its path: deps (there are seven, not six as the evidence says, which doesn't matter). swift-algorithms' .gitignore line 7 is Package.resolved, and swift-collections has Package.resolved only under Benchmarks/ and Utils/. The proposed text is accurate.

**Change.** - Direct dependencies from `Package.swift` (`swift package dump-package`). The full graph, with transitive edges, from `swift package show-dependencies --format json`. Pinned versions from `Package.resolved` when it exists. It is a flat list of remote pins, with no edges, no direct/transitive flag and no `path:` dependencies, and many libraries don't commit it. Resolving dependencies may need the network, so treat this collector as T0 only when `.build` already holds resolved checkouts.

### 18. §6.2 — error, confirmed

> toolchain version (`swiftly use` output)

**Issue.** `swiftly use` reports which toolchain swiftly selected, not a compiler version. With the Xcode toolchain selected it prints just `xcode (default)`. It can also print a swiftly update banner, and it doesn't exist on machines without swiftly. `swift --version`, run in the package directory so a `.swift-version` file is honoured, gives the actual compiler version.

**Evidence.** In the scratch package: `swiftly use` printed an update banner and then `xcode (default)`, while `swift --version` printed `Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1)`. In SwiftInferProperties: `swiftly use` printed `Swift 6.4.1 (/Users/.../SwiftInferProperties/.swift-version)`, while `swift --version` printed `Apple Swift version 6.4.1 (swift-6.4.1-RELEASE)`. `swiftly use --help`: "print the currently in-use toolchain ... based on the current working directory and `.swift-version` files".

**Verifier.** In the scratch package `swiftly use` printed a banner and then 'xcode (default)', while swift --version gave 'Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 ...)'. In SwiftInferProperties it printed 'Swift 6.4.1 (.../.swift-version)' against 'Apple Swift version 6.4.1 (swift-6.4.1-RELEASE)'. xcrun --show-sdk-version gives 27.2.

**Change.** toolchain version (first line of `swift --version`, run in the package directory), plus the swiftly selection and its source (`swiftly use`, if swiftly is installed) and the SDK version (`xcrun --show-sdk-version`)

### 19. §13 — suggestion, confirmed

> | Coverage needs a passing test suite | Record partial snapshots and say which collectors failed |

**Issue.** A detail that changes the mitigation: when any test fails, SwiftPM writes no coverage JSON (and no merged `.profdata`), but the raw `.profraw` files are still written. So coverage can still be recovered from a failing run.

**Evidence.** Test package with a failing test, `swift test --enable-code-coverage`: the codecov directory held only `Swift Testing…profraw` and `XCTest…profraw`, with no Demo.json and no default.profdata. After fixing the test, Demo.json and default.profdata appeared.

**Verifier.** After adding a failing @Test, swift test --enable-code-coverage exited 1. The codecov directory held only 'Swift Testing…profraw' and 'XCTest…profraw', with no Demo.json and no default.profdata. With all tests passing, the JSON was produced.

**Change.** | Coverage needs a passing test suite | SwiftPM writes no coverage JSON when a test fails, but the `.profraw` files remain. Merge them with `llvm-profdata` and export with `llvm-cov` to record coverage marked "tests failing", or record a partial snapshot and say which collectors failed |

**Checked and correct:**

- SwiftLint rule identifier is `cyclomatic_complexity` and the option is `ignores_case_statements` (default false); default thresholds warning 10 / error 20 (CyclomaticComplexityConfiguration.swift).
- SwiftLint counts each `case` (including `default`) unless `ignores_case_statements` is set, and `fallthrough` subtracts 1 (CyclomaticComplexityRule.swift).
- Sonar cognitive complexity counts a whole `switch` once (spec v1.7, 2023), so 'treats flat switch more fairly' holds for `switch`.
- Open question 6 is right that `guard`, `if let` and result builders are not covered by the Sonar spec.
- `llvm-cov export` (via SwiftPM `--enable-code-coverage`) gives per-function region coverage for Swift, with region ranges that can be mapped to source; generic functions appear once in debug builds, not once per specialisation.
- SwiftPM `swift test --show-codecov-path` gives the JSON path (`.build/out/Products/Debug/codecov/<Package>.json` with Swift 6.4.2's default backend).
- Coverage does need a passing test suite to get SwiftPM's JSON (§13 risk is real).
- USRs are unambiguous for overloads (labels and types are encoded), need a build, and stay the same when an internal/public function's file is renamed.
- indexstore-db reads the raw index produced by `-index-store-path` and needs a store path, a database path and libIndexStore (README; IndexStoreDB.swift init).
- SwiftPM produces an index store for debug builds by default (BuildPlan.swift `.auto` mode).
- `-debug-time-function-bodies` still works with Swift 6.4.2 and reports per-function times keyed by file:line:col.
- `git log --follow` works for one file at a time (git help log).
- `git log -L` follows a whole-file rename once a Swift funcname pattern is supplied.
- Periphery 2.21.2 detects unused parameters, unused enum cases (`enumelement`), unused imports of the package's own modules, and redundant public accessibility (`redundantPublicAccessibility`); it has JSON output and needs a build/index store.
- Periphery retains XCTest test methods as roots; `--retain-public` exists for library API (the PRD's 'public / open API used by other packages' caveat is right).
- `Package.resolved` does include transitive (non-direct) remote packages, e.g. SwiftProjectLint's 11 pins.
- `swift package show-dependencies --format json` gives the nested dependency graph (identity, url, version, path, dependencies).
- `swiftly use` with no argument prints the selected toolchain and where the selection came from (`.swift-version` or default).

## Design consistency and milestones

### 1. §6.1 — error, partly

> Fallback key: module + file path + enclosing type + signature + line range

**Issue.** The fallback key changes on almost every commit. A line range moves whenever any line above the function is added or removed, and the file path changes when a file moves. Every snapshot diff, trend, cache lookup and history join keyed on it would then see delete-plus-add instead of change. Source ranges are already stored separately (as the same section notes), so they don't need to be part of the key.

**Evidence.** Design reasoning. §7.13 needs 'follow history by function identity', §9 caching needs a key that survives unrelated edits, and §10 diff needs matched records. All three break if inserting a line above a function changes its key.

**Verifier.** The problem is real. A key that includes the line range changes whenever a line above the function is added or removed, which is worse than the PRD's 'breaks when code moves'. But the proposed key leaves out things Swift lets overloads differ by. Two functions can differ only in return type, in `async`, in `static` vs instance, or in generic constraints. Under the proposed key those overloads collide.

**Change.** Fallback key: module + enclosing type path (including any extension `where` clause) + declaration kind and `static` / `class` modifier + name + generic signature + parameter labels and types + `async` / `throws` + return type + `#if` condition. Add the file path only for `private` / `fileprivate` declarations. File path and line range are attributes of the record, not part of its key. A rename or signature change produces a new key. Between adjacent snapshots, a removed record and an added record with the same body hash are matched as one function and the link is recorded.

### 2. §6.1 — misleading, confirmed

> USR ... stable across renames of the file and unambiguous for overloads

**Issue.** Overstated. Swift USRs come from mangled names. For `private` / `fileprivate` declarations the mangled name contains a private discriminator derived from the file, so renaming the file changes the USR. Any USR also changes when a parameter type changes. A USR is unambiguous, but it is no more stable than a signature-based key.

**Evidence.** /Users/josephcursio/xcode_projects/SwiftCloneDetector/.build/arm64-apple-macosx/debug/codecov/SwiftCloneDetector.json contains mangled names such as `...V7collect33_BAE9315D5EA23627539D42F545956542LL_9fileIndex...` (the `33_<hash>LL` private discriminator).

**Verifier.** Swift USRs are built from mangled names. Private declarations carry a `33_<hash>LL` discriminator derived from the file, and I verified one in the SwiftCloneDetector llvm-cov export: the private `collect(...fileIndex...)` from CloneFinder.swift:98. Any USR also changes when the signature changes. So 'stable across renames of the file' is overstated for private and fileprivate declarations.

**Change.** USR (Unified Symbol Resolution) from indexstore-db: unambiguous, including for overloads, but needs a build. It changes when a signature changes, and for `private` / `fileprivate` declarations when the file is renamed.

### 3. §11 — contradiction, partly

> M7 | T1: indexstore-db identity ... | USR identity replaces fallback key

**Issue.** This contradicts §7.13 and the backfill design. Backfill runs T0 only (§7.13: 'T1–T3 are not backfilled by default'), so historical snapshots never have USRs. If the USR becomes the primary key at M7, every snapshot from M2 to M6, and every backfilled one, needs a key migration that can't be done without building old commits. Function-level history would then cross two key schemes.

**Evidence.** PRD §7.13 'Backfilled trends ... runs the T0 collectors on each' and 'T1–T3 are not backfilled by default'; §11 M2 store before M7.

**Verifier.** The contradiction is real. Backfill runs T0 only (§7.13), so snapshots from M2 to M6 and every backfilled one have no USR, and making the USR the primary key at M7 would split history across two key schemes. The proposed done-when needs fixing, though. If the walker records code in every `#if` branch (as the §6.1a proposal does), records in branches that aren't compiled can never get a USR, so a flat 99% may not be reachable.

**Change.** Make the syntactic key (§6.1) the permanent primary key from M0. At M7 the USR becomes an extra attribute on each record, filled when a build is available and used to resolve collisions and cross-file references. No stored keys are rewritten. M7 done when: on two packages, every record for code compiled in the build configuration gets a USR, records without one are listed with the reason, and every case where USR and syntactic key disagree is listed.

### 4. §11 — contradiction, confirmed

> M1 | T0: size, shape, complexity, risk markers, API surface, test inventory

**Issue.** M1 relies on M4. §7.4 says to take risk markers from the SwiftProjectLint adapter (§7.15). §7.5 takes over-exposure from SwiftProjectLint `couldBePrivate*`. §7.8 takes assertion-free tests from `testMissingAssertion` and related rules. That adapter is scheduled for M4.

**Evidence.** PRD §7.4 'take them from the adapter (§7.15)'; §7.5; §7.8; §11 M4 'SwiftProjectLint (with census/defect tagging)'.

**Verifier.** Three M1 items depend on the SwiftProjectLint adapter, which §11 schedules for M4. §7.4 takes risk markers from it ('take them from the adapter (§7.15)'). §7.5 takes over-exposure from `couldBePrivate*`, and §7.8 takes assertion-free tests from `testMissingAssertion`. All of these rules exist in RuleIdentifier.swift.

**Change.** Move the SwiftProjectLint JSON adapter into M1. It is JSON parsing plus line-range mapping, the same work the coverage join needs. Keep the other adapters in M4. Alternatively, strike risk markers, over-exposure and assertion-free tests from M1 and list them under M4.

### 5. §11 — contradiction, confirmed

> M3 | ... hotspot, hidden-coupling and bug-prone signals

**Issue.** Hidden coupling is defined as 'high change coupling, no static dependency' (§8). Static dependencies come from §7.6, which is T1 via indexstore-db and scheduled for M7. M3 can't produce the signal as defined.

**Evidence.** PRD §7.13 'Flag pairs with no static dependency between them (from §7.6)'; §7.6 '(T1, via indexstore-db)'; §11 M7.

**Verifier.** Hidden coupling is defined as high change coupling with no static dependency (§8, §7.13 'from §7.6'). §7.6 is T1 via indexstore-db and is scheduled for M7, so M3 can't produce the signal as defined.

**Change.** M3 produces change-coupling pairs only. The hidden-coupling signal moves to M7. If a T0 approximation is wanted earlier, say which one (e.g. 'no shared type or function name reference in either body') and label the signal as approximate until M7.

### 6. §11 — gap, confirmed

> M1 | ... test inventory and test-to-code ratios

**Issue.** Two of the §7.8 ratio variants can't be computed at M1. 'Dead code (§7.6a) excluded on the production side' needs Periphery (M7). 'Tests per public function' needs a test-to-function mapping, and the PRD never says where that mapping comes from at T0. Coverage (M5) or the index (M7) would provide it.

**Evidence.** PRD §7.8 'dead code (§7.6a) excluded'; §7.6a Periphery; §11 M5, M7.

**Verifier.** Dead-code exclusion on the production side needs Periphery, which is in M7. The PRD gives no T0 source for a test-to-function mapping. §7.13 mentions finding tests 'via coverage or naming', but only for history, not for §7.8.

**Change.** At M1, compute ratios without dead-code exclusion and record that the exclusion is missing. Add the exclusion at M7. Define 'tests per public function' as coverage-based (a test covers the function) and schedule it at M5. Until then, drop it or define a named-based heuristic and label it as one.

### 7. §11 — gap, partly

> | Later | HTML trend charts, SwiftUI viewer, Xcode-project support | — |

**Issue.** Several catalogue items and signals have no milestone: SwiftLint violations (§7.7, also used in the §12 95% criterion), compiler warnings (§7.7), dependencies (§7.14), SwiftPropertyLaws / RefactorBridge data (§7.11) and the 'Unchecked laws' signal, plus 'Missing template?', 'Uneven clone testing', 'Clone hotspot', 'Tests not keeping up', 'Unstable fixes' and 'Safe to leave'. A builder can't tell when they are due or what they depend on.

**Evidence.** PRD §11 rows M0–M7 compared with §7.7, §7.11, §7.14 and the §8 signal table.

**Verifier.** The gap is real. SwiftLint violations, compiler warnings, dependencies, the SwiftPropertyLaws data (a local repo exists) and several signals have no milestone. Some of the proposed assignments are wrong, though. 'Unstable fixes' and 'Safe to leave' use git history only, so they are available at M3, not M4. 'Missing template?' needs SwiftEffectInference and SwiftInferProperties, which makes it M4. Putting SwiftLint in M1 conflicts with §7.7, which tags build health as T1, so §7.7 would need retagging first.

**Change.** Add a table under §11 mapping every §8 signal to the first milestone that has all its inputs: Unstable fixes, Safe to leave → M3. Clone hotspot, Missing template?, Unchecked laws → M4 (add a SwiftPropertyLaws adapter to M4). Tests not keeping up → M3 if tests are found by naming, M5 if found by coverage. Uneven clone testing → M6. Put dependency counts (§7.14) in M1 and compiler warnings in M7. SwiftLint: either retag it T0 in §7.7 (its non-analyzer rules need no build) and schedule it in M1, or keep it T1 and schedule it in M7.

### 8. §7.4 — error, confirmed

> SwiftStats computes only the concurrency-shape counts itself.

**Issue.** SwiftProjectLint doesn't cover three listed markers: implicitly unwrapped optionals (no rule exists), `precondition` (deliberately excluded), and `fatalError` inside `required init?(coder:)` (exempt). SwiftStats would have to compute those itself. A linter-derived count is also not a census of the code. It drops anything suppressed inline or disabled in the target repo's `.swiftprojectlint.yml`, so counts differ between repos for reasons unrelated to the code.

**Evidence.** /Users/josephcursio/xcode_projects/SwiftProjectLint/Packages/SwiftProjectLintRules/Sources/SwiftProjectLintRules/CodeQuality/Visitors/UnconditionalTrapVisitor.swift:5-24 (only `fatalError`, `preconditionFailure`; `precondition` excluded) and :35 (`required init?(coder:)` exemption). RuleIdentifier.swift has no implicitly-unwrapped rule. SwiftProjectLintCLI.swift:67 loads `.swiftprojectlint.yml` from the project root by default.

**Verifier.** Verified in SwiftProjectLint. UnconditionalTrapVisitor matches only `fatalError` and `preconditionFailure`, deliberately excludes `precondition`, and exempts `required init?(coder:)`. No rule detects implicitly unwrapped optionals. The CLI loads `.swiftprojectlint.yml` from the project root by default, and a `--config` option exists. LintConfiguration has `enabled_only` and an opt-in rule set, so a config that enables every rule is possible.

**Change.** SwiftStats computes the concurrency-shape counts, implicitly unwrapped optionals and `precondition` calls itself. The rest come from SwiftProjectLint, which the adapter runs with `--config` pointing at a SwiftStats-owned file that enables every rule, so the target repo's configuration doesn't change the counts. Inline suppressions still apply and are counted separately (§7.15).

### 9. §7.15 — contradiction, confirmed

> `missingEquatableOnPureResult`: pure function whose result type isn't `Equatable`

**Issue.** It is listed under 'Census rules', but the source the PRD names for the census idea classifies it as a defect. CandidateInventory says it names a conformance to add, which is an edit, and leaves it out of the census set.

**Evidence.** /Users/josephcursio/xcode_projects/SwiftProjectLint/Sources/Core/Export/CandidateInventory.swift:33-35 ('`.missingEquatableOnPureResult` seeds the same pipeline and is **not** here — it names a conformance to add, which is an edit') and :52-56 (inventoryRules = pureFunctionCandidate, pureClosureCandidate, pureMutatorCandidate).

**Verifier.** CandidateInventory.swift says `.missingEquatableOnPureResult` is not in the census set, because 'it names a conformance to add, which is an edit'. `inventoryRules` holds exactly pureFunctionCandidate, pureClosureCandidate and pureMutatorCandidate.

**Change.** Move `missingEquatableOnPureResult` to the defect list under Testability. Census rules are exactly SwiftProjectLint's `CandidateInventory.inventoryRules`: `pureFunctionCandidate`, `pureClosureCandidate`, `pureMutatorCandidate`.

### 10. §7.15 — gap, partly

> SwiftStats reads the JSON ... Each rule is tagged census or defect (§6.4).

**Issue.** The JSON carries no kind field. Only three rules are census in code, and the other ~217 would need a table maintained in SwiftStats that drifts as rules are added. The JSON `ruleName` is the display string ('Force Unwrap'), not the case names the PRD uses (`forceUnwrap`). `locations` is an array, so multi-location findings (duplicate shapes, cycles) need an attribution rule. The report has no schema or tool version.

**Evidence.** /Users/josephcursio/xcode_projects/SwiftProjectLint/Sources/Core/Export/CodableLintIssue.swift:13-33 (`ruleName = issue.ruleName.rawValue`, `locations: [IssueLocation]`). LintReport.swift (only `summary` and `issues`). RuleIdentifier.swift:102 `case forceUnwrap = "Force Unwrap"`.

**Verifier.** The facts check out. CodableLintIssue has no kind field, `ruleName` is the display rawValue ('Force Unwrap'), and `locations` is an array. LintReport has only `summary` and `issues`. `suppressionKey` is derived from the rawValue. But the proposal says 'no second table in SwiftStats', which it can't keep: until SwiftProjectLint emits `kind`, the JSON gives no way to know which rules are census, so SwiftStats still needs a list of the three census names.

**Change.** Census is SwiftProjectLint's `CandidateInventory.inventoryRules`, and every other rule is a defect. Preferred: SwiftProjectLint adds `kind` and `schemaVersion` to its JSON. Until it does, SwiftStats keeps a three-entry list of the census rules' display names ('Pure Function Candidate' and so on), and any rule not on the list is a defect. The adapter keys rules on the JSON `ruleName` string, the same string the suppression keys are derived from. A finding with several locations counts once, against the function holding its first location. The other locations are stored as links.

### 11. §6.4 — contradiction, confirmed

> Census values are counted, rolled up and fed to other tools, but never listed one per line in a human-facing report.

**Issue.** Other parts of the PRD list census items one per line. 'Untested property' and 'Missing template?' list property candidates and pure functions, `swiftstats top untested-property` prints them, and §7.12 lists 'for each function: ... its twins'. As written, the rule forbids the main output of §8.

**Evidence.** PRD §8 rows 'Untested property', 'Missing template?'; §10 `swiftstats top <signal>`; §7.12.

**Verifier.** §6.4 forbids listing census values one per line. Yet the §8 signals 'Untested property' and 'Missing template?' list property candidates and pure functions, which §6.4 itself gives as census examples. `top untested-property` (§10) and §7.12's per-function twins do the same.

**Change.** Add: 'Raw census metrics are never listed per item. A derived signal (§8) may list items selected by a census metric, because the signal makes them actionable. That is where census data becomes a to-do list.'

### 12. §7.6a — contradiction, confirmed

> ### 7.6a Dead code (T0/T1)

**Issue.** Only commented-out code is T0. Periphery builds the package and reads the index store, and unreachable-code warnings need a compile, so the rest is T1. §9's diagram adds to the confusion by listing Periphery among the tool adapters next to the T0 tools.

**Evidence.** /Users/josephcursio/xcode_projects/SwiftProjectLint/.periphery.yml (index_exclude vs report_exclude; 'the files stay indexed'). PRD §11 already puts Periphery in M7 (T1).

**Verifier.** Periphery builds the package and reads the index store. Unreachable-code warnings come from the compiler. Only the commented-out-code heuristic is syntax-only, which fits §11 already placing Periphery in M7 (T1).

**Change.** Retitle to 'Dead code (T1; commented-out code T0)'. In §9, show Periphery as a T1 input from the build / index store.

### 13. §7.8 — error, confirmed

> Line coverage and region/branch coverage per function

**Issue.** Swift doesn't emit branch coverage. An `llvm-cov export` of a Swift package has zero branch records, so the M5 'line + branch coverage' done-when can't be met. The export also gives closures and autoclosures their own function records and includes dependency checkouts under `.build/checkouts`. Both affect the join and the 95% mapping criterion.

**Evidence.** /Users/josephcursio/xcode_projects/SwiftCloneDetector/.build/arm64-apple-macosx/debug/codecov/SwiftCloneDetector.json: totals.branches.count = 0, and the sum of per-function branches = 0. In that project's own sources, 71 of 299 function records are closures (`fU_` / `fu0_`). The first record is from `.build/checkouts/swift-argument-parser`.

**Verifier.** I checked the SwiftCloneDetector export. totals.branches.count is 0, and the per-function branch arrays sum to 0 across 20,982 records. The first record comes from .build/checkouts/swift-argument-parser. Closure records (`fU_` / `fu0_`) make up about 67 of the 299 records under Sources/, which differs slightly from the finding's figure of 71 but confirms the point.

**Change.** Line and region coverage per function. (Swift's coverage mapping has no branch records.) Closure records roll up into the enclosing function by source range. Files under `.build/` are excluded. M5 done when: per-function line and region coverage, and the 'risky + untested' signal.

### 14. §7.3 — gap, partly

> Complexity numbers match SwiftLint on a sample package

**Issue.** Not testable as written. SwiftLint prints a complexity only for functions over the threshold (default warning 10). It starts counting at 0, not McCabe's 1. It measures only `func` and `init` bodies: closures count toward the enclosing function, nested functions are skipped and counted separately, and accessors, subscripts and deinit get no number. `ignores_case_statements` changes the result. 'Match' needs those choices fixed and a way to obtain SwiftLint's numbers for every function.

**Evidence.** /Users/josephcursio/GitHub_projects/SwiftLint/Source/SwiftLintBuiltInRules/Rules/Metrics/CyclomaticComplexityRule.swift:77-113 (visits FunctionDecl and InitializerDecl only, reports only when complexity > threshold) and :116-170 (`complexity = 0`, case/fallthrough handling, nested func/init skipped). CyclomaticComplexityConfiguration.swift:7-9 (warning 10, ignores_case_statements false).

**Verifier.** The SwiftLint behaviour is as described: CyclomaticComplexityRule visits only FunctionDecl and InitializerDecl, starts at `complexity = 0`, skips nested func and init, counts closures in the enclosing function, defaults to warning 10 with `ignores_case_statements: false`, and reports only when complexity is above the threshold. That last point breaks the proposed done-when. Even with `warning: 0`, a straight-line function has complexity 0, and 0 > 0 is false, so it is never reported. 'Every func and init' can't be met from the parsed output alone.

**Change.** Cyclomatic complexity follows SwiftLint's `cyclomatic_complexity` with `ignores_case_statements: false`: base 0, closures counted in the enclosing function, nested functions separate. SwiftStats computes the same number for accessors, subscripts and deinit as an extension. M1 done when: SwiftLint is run on swift-algorithms with `cyclomatic_complexity: { warning: 0 }`. For every `func` and `init`, the value SwiftLint reports, or 0 if it reports nothing, equals SwiftStats's value.

### 15. §7.2 — gap, confirmed

> Function length (stripped lines)

**Issue.** 'Stripped lines' is never defined. Sitrep, whose stats M0 must reproduce, counts non-empty lines and keeps comments, because its comment stripper is disabled. Whitespace-only lines also count. Either SwiftStats reproduces that quirk (and function length then includes doc comments) or M0 can't 'reproduce Sitrep's stats'.

**Evidence.** /Users/josephcursio/GitHub_projects/Sitrep/Sources/SitrepCore/FileVisitor.swift:150-154 (`strippedBody = body.removingDuplicateLineBreaks()`) and :185-199 (BodyStripper 'DISABLED RIGHT NOW'). Extensions.swift:34-39 (filters only `isEmpty` lines). Type.swift:50.

**Verifier.** Verified in Sitrep. `removingDuplicateLineBreaks` keeps every line that isn't empty, so whitespace-only lines count. The comment-stripping BodyStripper is marked 'DISABLED RIGHT NOW', and both files and types use `body.removingDuplicateLineBreaks()`, so comments are counted. The PRD never defines 'stripped lines'.

**Change.** Add to §7.2: 'Stripped lines: lines of the declaration's body that contain at least one token after comments and whitespace are removed. Doc comments and attributes don't count.' Add to §7.1: 'Sitrep's "source lines" (non-empty lines, comments included) is kept as a separate field, `sitrepLines`, for comparison.'

### 16. §6.1 — gap, confirmed

> Every metric must be attached to the same function.

**Issue.** The PRD never says what a 'function' is, and the tools disagree. Sitrep counts only `func` declarations. SwiftLint counts `func` and `init`. llvm-cov and SwiftMutator report closures. Macros, `#if` branches, extensions, accessors, subscripts, deinit, nested functions, protocol requirements, top-level code and generated files all need a rule before the M0 walker can be written.

**Evidence.** /Users/josephcursio/GitHub_projects/Sitrep/Sources/SitrepCore/FileVisitor.swift:77 (only FunctionDeclSyntax creates a Function). SwiftLint CyclomaticComplexityRule.swift:77-93. The llvm-cov closure records cited above.

**Verifier.** Sitrep creates a Function only for FunctionDeclSyntax (FileVisitor.swift:76). SwiftLint covers func and init. llvm-cov gives closures their own records (verified). The PRD has no definition of a function.

**Change.** Add §6.1a 'What counts as a function'. Records: `func`, `init`, `deinit`, `subscript`, explicit accessors (`get` / `set` / `willSet` / `didSet`, including computed-property bodies), nested functions (own record with a parent link), and one synthetic record per file for top-level code. Not records: closures (results map to the enclosing record), protocol requirements without a body, and macro expansions (results inside them are reported as unmapped). Extension members belong to the extended type. Code in every `#if` branch is walked, and the condition is stored. Files matching configured generated-code globs are marked `generated`. Sitrep's 'function count' is the `func` subset.

### 17. §6.2 — contradiction, partly

> One run of SwiftStats, tagged with: commit SHA, branch, dirty flag

**Issue.** This contradicts §1's 'one snapshot per commit'. It also doesn't say what happens when T0 runs now and `--tier 3` later on the same commit, or when the tree is dirty. If the store lives in `.swiftstats/` inside the repo (§14 Q4), the store itself makes `git status` dirty on every run after the first.

**Evidence.** PRD §1 'keeps one snapshot per commit', §6.2 'One run', §10 `--tier 2/3`, §14 Q4.

**Verifier.** The ambiguity is real: §6.2 says 'one run' while §1 says 'one snapshot per commit', and the PRD doesn't cover tier add-ons or dirty trees. The proposal contradicts itself, though. It keys dirty snapshots by commit + hash of the changed files, but also says the next dirty scan of the same commit replaces the old one, which a different hash would not do under that key.

**Change.** A snapshot is one commit plus one working-tree state. Each collector run attaches its results to that snapshot, so a later `--tier 3` adds to the T0 snapshot rather than starting a new one. Each collector's run time and version are recorded. A dirty tree gets at most one working snapshot per commit, which records a hash of the changed files. The next dirty scan of that commit replaces it. `diff`, `trend` and `backfill` use clean snapshots unless `--include-dirty` is given. The dirty check ignores `.swiftstats/`.

### 18. §9 — error, partly

> T2/T3 results are reused when the function's source hash hasn't changed since the last snapshot.

**Issue.** Wrong cache key. A function's coverage and mutation score depend on the tests, and coverage also depends on its callers. Adding a test changes kills and coverage with no change to the function's source, so this rule would report stale results as current.

**Evidence.** Design reasoning. §8 'Weak tests' and 'Best property-test target' would read stale mutation data straight after the user writes the test the report suggested.

**Verifier.** The rule in §9 is wrong: a new test changes kills and coverage without changing the function's source. But the finding itself says coverage depends on callers, and its proposed key covers only the function and the test sources, so a change to a production caller still leaves stale results. Also, a single test run produces coverage for every function, so caching coverage gains nothing.

**Change.** Coverage is not cached: one test run produces it for every function. Mutation results for a function are reused only when its source hash, the hash of all test-target sources, `Package.resolved`, the toolchain and SwiftMutator's version are all unchanged. Changes elsewhere in production code can still change them, so reused results are marked as cached, with the snapshot they came from, and `--tier 3 --fresh` reruns everything.

### 19. §10 — gap, confirmed

> Command shape (illustrative):

**Issue.** There is no configuration file, yet the PRD repeatedly says 'configurable': churn windows, fix-commit patterns, thresholds, generated-test paths and collector enablement. A builder hits this in week one.

**Evidence.** PRD §7.8 'excluded from ratios by default', §7.13 'configurable windows' and 'configurable' patterns, §8 'Thresholds should be configurable'. The sibling tools use repo-root YAML: SwiftProjectLint `.swiftprojectlint.yml` (SwiftProjectLintCLI.swift:67), Sitrep `Configuration.parse` (Configuration.swift:30), `.periphery.yml`.

**Verifier.** The PRD says 'configurable' in several places (§7.8, §7.13, §8) but defines no configuration file. The sibling tools use repo-root YAML: SwiftProjectLint's `--config` defaults to `.swiftprojectlint.yml`, Sitrep has `Configuration.parse`, and SwiftProjectLint has a `.periphery.yml`.

**Change.** Add §10.1 Configuration: '`.swiftstats.yml` in the package root, YAML like the sibling tools; command-line flags override it. Keys: `excluded` and `generated` path globs, `history.window` (default 90d), `history.fix_patterns`, `signals.<name>.threshold`, `collectors.<name>.enabled` and `.path`, `store` path. Unknown keys are an error.'

### 20. §9 — gap, partly

> Store: one SQLite database per package

**Issue.** No schema versioning for either output. The JSON report has no version field, the SQLite store has no migration plan, and report determinism (ordering, ties at decile boundaries, float formatting) is unspecified. Snapshots are meant to last for years and be diffed, so these matter from M2.

**Evidence.** PRD §9, §10, §11 M2. A migration library is available locally: /Users/josephcursio/GitHub_projects/GRDB.swift (DatabaseMigrator).

**Verifier.** The gap is real, and GRDB, which has DatabaseMigrator, is available locally. The proposal has two problems. 'Stored snapshots are never rewritten' conflicts with migrations, which do rewrite stored rows to the new schema. And 'byte-identical output' fails if the header timestamp is the time the report ran.

**Change.** Every JSON output carries `schemaVersion`. The SQLite store records its version in `PRAGMA user_version` and upgrades with forward-only migrations (GRDB's `DatabaseMigrator`). Migrations change the schema, never the measured values. Reports are deterministic: records sort by signal score, then identity key; JSON keys are sorted; percentiles use nearest-rank; the only timestamp is the snapshot's own date. Running a report twice on the same snapshot gives byte-identical output.

### 21. §13 — gap, confirmed

> Coverage needs a passing test suite | Record partial snapshots and say which collectors failed

**Issue.** Only coverage gets failure handling. The PRD doesn't say what happens when SwiftProjectLint, Periphery, SwiftMutator or SwiftLint isn't installed, or one of them crashes. It also doesn't keep 'not collected' apart from zero. 'Genuinely under-tested' would then flag every function whenever coverage is missing, and an absent effect tier would read as no evidence. SwiftEffectInference also has a separate `unknown` state outside its five-tier lattice.

**Evidence.** PRD §8 rows built on low coverage or low mutation score. /Users/josephcursio/xcode_projects/SwiftEffectInference/Sources/SwiftEffectInference/EffectAnnotationParser.swift:440-456 (`unknown` is deliberately not an `Effect` case).

**Verifier.** §13 handles failure for coverage only. The PRD doesn't say what happens when a tool is missing, and doesn't keep null apart from zero. EffectAnnotationParser.swift notes that `unknown` is deliberately not an `Effect` case.

**Change.** Add §6.5 Collector status: each collector records `ran`, `cached`, `skipped (tool not found)` or `failed (exit code, last 20 lines of stderr)`. A missing value is stored as null, never 0. A derived signal whose inputs are missing is left out of the report with the reason, not computed. Effect tier allows `unknown` and 'not inferred' as distinct values.

### 22. §6.2 — gap, confirmed

> which collectors ran and with what versions

**Issue.** The tools' version strings don't identify a build. SwiftProjectLint reports '1.0.0' after 1,697 commits with no tags, so two snapshots with very different rule behaviour would record the same version. The toolchain field relies on `swiftly use`, which only exists on machines with swiftly and reports the selection, not the compiler.

**Evidence.** /Users/josephcursio/xcode_projects/SwiftProjectLint/Sources/CLI/SwiftProjectLintCLI.swift:10 (`version: "1.0.0"`). In that repo, `git tag` is empty and `git rev-list --count HEAD` = 1697.

**Verifier.** SwiftProjectLintCLI.swift:10 has `version: "1.0.0"`, `git tag` is empty, and `git rev-list --count HEAD` is 1697. `swiftly use` reports the selection rather than the compiler, and only machines with swiftly have it.

**Change.** For each collector, record its version string plus the git commit of the tool's source when it is a local build (or a SHA-256 of the binary otherwise). Record the toolchain as `swift --version` output, plus the `swiftly use` selection when swiftly is present.

### 23. §12 — misleading, partly

> On my own packages, the top-10 lists from derived signals lead to tests I actually write.

**Issue.** Three of the four criteria can't be measured as written. 'Useful enough' and 'lead to tests' have no measure. The 30-second criterion doesn't say whether adapters (SwiftProjectLint with its cross-file rules, SwiftInferProperties, SwiftCloneDetector) count as T0, or whether TH is included, which `scan` runs by default (§10). The 95% criterion includes SwiftLint, many of whose rules are file- or line-level (file length, trailing newline, property lines), so 95% can't be reached. Coverage records for dependency checkouts would also distort it.

**Evidence.** PRD §10 '`swiftstats scan` — T0 + TH collectors'; §6.3 TH 'seconds–minutes'. llvm-cov export includes `.build/checkouts` records (see the coverage finding above).

**Verifier.** Mostly real. 'Useful enough' and 'lead to tests' have no measure, and the 30-second criterion doesn't say whether TH and adapters are included. The proposal has two problems. Its criterion 2 says each result maps to 'exactly one record', which nested functions (own records with a parent link) break, because a location inside a nested function lies inside both. And requiring every adapter (SwiftProjectLint's cross-file rules, SwiftInferProperties) to fit in 30 seconds is unverified, so it may be unreachable.

**Change.** 1. `swiftstats scan --no-history` on swift-collections at a named tag, with the T0 collectors, finishes in under 30 seconds on this Mac with a warm build. Adapter times are recorded separately in each snapshot. 2. Every coverage region, mutant and function-scoped SwiftLint violation whose location lies inside a function body maps to the innermost enclosing record. Results outside any function are counted and reported as unmapped, never dropped. 3. Over the first four weeks of use on two of my packages, at least half the items in each top-10 list are judged worth acting on. Each test written from a list is logged. 4. At least one SwiftInferProperties or SwiftEffectInference calibration-cycle document cites a disagreement found by SwiftStats.

### 24. §11 — misleading, confirmed

> M2 ... Two snapshots of one repo diff cleanly / M3 ... Hotspot list on a real package looks sensible on review

**Issue.** Neither done-when is testable. 'Cleanly' and 'looks sensible' have no pass or fail.

**Evidence.** PRD §11.

**Verifier.** 'Diff cleanly' and 'looks sensible on review' have no pass or fail. The proposed done-whens are testable and consistent with a key that leaves out file path and line range.

**Change.** M2 done when: diffing a snapshot with itself is empty. On a fixture commit that adds, changes, moves and deletes one function each, the diff shows exactly those four, and a move shows as a move. Re-running `report` gives byte-identical output. M3 done when: on two repos, I label the top 20 hotspots and at least 12 are judged worth attention, with the labels kept as a test fixture. A backfilled trend of stripped lines and median complexity is produced for one repo.

### 25. §14 — contradiction, partly

> 7. Overlap with SwiftProjectLint: ... should SwiftStats always take them from SwiftProjectLint (recommended ...) or compute them itself

**Issue.** §7.15 'Source of truth' and §7.4 already state the decision, so the question is listed as open and closed at once. The undecided part is what happens when SwiftProjectLint isn't installed.

**Evidence.** PRD §7.15 'SwiftProjectLint is the source and SwiftStats only counts and joins'; §7.4 'take them from the adapter'.

**Verifier.** The inconsistency is real: §7.4 and §7.15 state the decision as fact while Q7 lists it as open. The proposed 'SwiftProjectLint is the source' is too broad, though. SwiftProjectLint has no rule for implicitly unwrapped optionals or `precondition` (finding #7), so SwiftStats has to compute those itself.

**Change.** Move it to a 'Decided' list: SwiftProjectLint is the source for every measure it has a rule for. §7.4 lists the few that SwiftStats computes itself. Without SwiftProjectLint, its metrics show as 'not collected' (§6.5), not zero, and the report says so.

### 26. §14 — suggestion, confirmed

> 1. Fork or extend Sitrep?

**Issue.** This should be decided now, because M0 depends on it, and the code favours neither option. Sitrep's `Function` and `Type` models are internal, so extending through the `SitrepCore` library can't reach per-function data without upstream changes. A fork brings Yams, the report code and the disabled stripper. All of SitrepCore is about 1,100 lines.

**Evidence.** /Users/josephcursio/GitHub_projects/Sitrep/Sources/SitrepCore/Function.swift:14 (`class Function: Node`, not public). Only `File`, `Configuration`, `Results`, `Report` and `Scan` are public. `wc -l` of SitrepCore is 1144 lines. Package.swift depends on Yams and swift-syntax from 602.0.0.

**Verifier.** Verified in Sitrep. `class Function: Node` is internal, and the only public types are Configuration, File, Report, Results and Scan. SitrepCore is 1,144 lines. Package.swift depends on Yams and swift-syntax from 602.0.0. Sitrep has `--format json` and test inputs under Tests/SitrepCoreTests/Inputs. SwiftEffectInference, SwiftProjectLint and SwiftInferProperties pin swift-syntax `exact: "603.0.2"`.

**Change.** Decided: neither. SwiftStats reimplements Sitrep's counts on swift-syntax 603.0.2 (the version the sibling tools pin), credits Sitrep, and keeps a compatibility test comparing its `sitrep` block with Sitrep's `--format json` output. Source ranges can be offered upstream separately.

### 27. §14 — suggestion, confirmed

> 3. Library vs CLI adapters: linking SwiftInferProperties / SwiftMutator as libraries pins their versions together

**Issue.** The real constraint is swift-syntax, and one adapter has no choice. SwiftEffectInference has no CLI or JSON, so it must be linked. It, SwiftProjectLint and SwiftInferProperties all pin swift-syntax `exact: "603.0.2"`, so linking any of them locks SwiftStats to the same exact version, and every one of them must move together.

**Evidence.** swift-syntax `exact: "603.0.2"` in /Users/josephcursio/xcode_projects/SwiftEffectInference/Package.swift:30, SwiftProjectLint/Package.swift:48 and SwiftInferProperties/Package.swift:118. The SwiftEffectInference README has no CLI section.

**Verifier.** The SwiftEffectInference README says 'there is no CLI and no process boundary'. The package ships only a library product. It, SwiftProjectLint and SwiftInferProperties all pin swift-syntax `exact: "603.0.2"`. SwiftMutator and SwiftCloneDetector use ranges and emit JSON.

**Change.** Decided: link SwiftEffectInference, which has no CLI, and pin swift-syntax 603.0.2 to match it. Use JSON for SwiftProjectLint, SwiftInferProperties, SwiftCloneDetector, SwiftMutator and Periphery, so they can move independently. Record each tool's commit (§6.2).

### 28. §14 — suggestion, partly

> 2. Store ... 4. Where snapshots live ... 5. Cross-package comparison ... 6. Cognitive complexity rules ... 8. Moving census rules out of SwiftProjectLint

**Issue.** These can be decided now. Leaving them open blocks M2 (store, location) and M1 (cognitive complexity). Q8 is a SwiftProjectLint decision, not a SwiftStats one.

**Evidence.** PRD §9 already recommends SQLite. CandidateInventory.swift already withholds census rules from human-facing reports while keeping them in JSON and pbt-seeds (lines 26-29).

**Verifier.** These can be decided now, and Q8 is largely done already: CandidateInventory.swift keeps census rules in the summary, JSON and seeds but stops listing them one per line. The proposed Q6 contradicts itself. Sonar's spec says nothing about Swift's `guard` or `if let`, so 'as written, with guard scored like if' is already an adaptation. Q4 has a problem too. The user works on two machines and syncs through GitHub, so a git-ignored store keeps separate history on each machine (only T0 can be rebuilt with backfill), and the proposal should say so.

**Change.** Q2: SQLite, plus `report --format json` per snapshot for anyone who wants git-diffable files. Q4: `.swiftstats/stats.sqlite` in the package (git-ignored), with `--store <path>` for research corpora. T1–T3 history is per machine, and T0 history can be rebuilt with `backfill`. Q5: store raw counts and normalise per 1k stripped lines at report time. Q6: adopt Sonar's rules. For Swift constructs Sonar doesn't cover, `guard` adds +1 with no nesting increment, and `if let` adds nothing beyond its `if`. Every Swift-specific choice is listed in a table. Q8: move to SwiftProjectLint's backlog, since CandidateInventory already does most of it.

### 29. §13 — gap, confirmed

> | Function-level history is expensive on long histories | Limit to a time window; cache per-commit parse results |

**Issue.** Several risks a builder will hit are missing from §13. (1) swift-syntax lockstep across linked tools. (2) Tool-version drift: live snapshots taken months apart use different tool builds, so trends mix tool changes with code changes. (3) Stale caches (see §9). (4) Relative thresholds: top-decile membership shifts when other code changes, so signal diffs churn without cause. (5) Test inventory reads `Package.swift`, which means evaluating the manifest with `swift package dump-package` on every backfilled commit. That is slow, runs repo code, and may fail on old manifests. (6) Unversioned tool output formats break adapters silently.

**Evidence.** PRD §7.8 'use the test targets declared in Package.swift'; §8 'defaults should be relative'; swift-syntax exact pins cited above; SwiftProjectLint LintReport has no schema version.

**Verifier.** §13 has none of these rows. The exact swift-syntax pins, SwiftProjectLint's unversioned LintReport and tools changing between snapshots are all verified. Reading targets from Package.swift means running the manifest, which is Swift code, on every backfilled commit.

**Change.** Add rows. 'swift-syntax pinned exactly by linked tools | Link only SwiftEffectInference; record pins.' 'Tool versions change between snapshots | Record tool commit; mark trend breaks where a collector changed; `backfill --rerun` with current tools.' 'Relative thresholds shift when other code changes | `diff` compares raw scores, not signal membership.' 'Manifest evaluation per backfilled commit | Cache target layout per `Package.swift` hash; fall back to `Sources/` and `Tests/` with a warning.' 'Tool output format changes | Adapters check `schemaVersion` or fail loudly with the tool commit.'

### 30. §10 — gap, confirmed

> `swiftstats diff <sha-a> <sha-b>` — what got better / worse between two snapshots

**Issue.** The PRD doesn't say what happens when the two snapshots ran different collectors or tool versions, or when a snapshot for one SHA doesn't exist. The reviewer use case in §5 usually has no snapshot of the base.

**Evidence.** PRD §5 'diff of two snapshots'; §6.2 records collector versions but nothing uses them.

**Verifier.** §6.2 records collector versions, but §10's `diff` never uses them, and nothing covers a SHA that has no snapshot. That is the usual case for the PR reviewer in §5.

**Change.** `diff` compares only metrics both snapshots have from the same collector version, and lists the rest as 'not comparable'. If a SHA has no snapshot, it runs a T0 scan of it in a temporary worktree (as `backfill` does) before diffing.

### 31. §11 — suggestion, partly

> M0 | Decide fork vs extend Sitrep; function identity with source ranges | Sitrep's existing stats reproduced, plus per-function records with ranges

**Issue.** M0 mixes a decision with a build, and its done-when is untestable. Reproducing Sitrep's stats exactly would also mean copying its non-empty-line quirk.

**Evidence.** See the Sitrep stripped-lines and fork findings above.

**Verifier.** The criticism is fair: M0 mixes a decision with a build, and its done-when can't be tested. The proposed criterion (3) conflicts with finding #0's key, which adds the file path for `private` / `fileprivate` declarations. Moving the file of a private function would change its key.

**Change.** M0 scope: `swiftstats scan --format json`, T0 only, with no store and no git. Find targets via `swift package dump-package` and walk them with swift-syntax 603.0.2. Emit one record per §6.1a kind: key, kind, file, start and end line and column, stripped lines, body hash, parent key, `#if` condition, role (production / test / helper), plus a `sitrep` block of Sitrep-compatible project counts. Output carries `schemaVersion: 1`. M0 done when: (1) a fixture package covering every §6.1a kind produces checked-in golden JSON exactly. (2) On Sitrep's test inputs and on swift-algorithms, the `sitrep` block matches Sitrep's `--format json` field by field, and any deliberate difference is listed. (3) Inserting lines above a function or reformatting it leaves its key unchanged. Moving its file leaves the key of a non-private function unchanged, and changing its signature changes it. (4) Two runs on the same tree give byte-identical output. (5) The scan time on swift-collections is recorded as the §12 baseline.

### 32. §7.11 — error, confirmed

> Tier (Strong / Possible)

**Issue.** These tier names are out of date. SwiftInferProperties has `verified`, `strong`, `likely`, `possible`, `suppressed` and `advisory`. The 'Untested property' signal ('Strong-tier candidate') would miss `verified`, which ranks above `strong`.

**Evidence.** /Users/josephcursio/xcode_projects/SwiftInferProperties/Sources/SwiftInferCore/Tier.swift:7-45.

**Verifier.** SwiftInferCore/Tier.swift has the cases verified, strong, likely, possible, suppressed and advisory, and `verified` ranks above `strong`. 'Strong / Possible' is out of date.

**Change.** Tier (Verified / Strong / Likely / Possible; Suppressed and Advisory stored but not surfaced). In §8, 'Untested property' becomes: Verified- or Strong-tier candidate, no property test.

### 33. §7.15 — error, confirmed

> (`swiftLintSuppression`, `swiftProjectLintSuppression`)

**Issue.** The rule identifiers are spelled differently in SwiftProjectLint.

**Evidence.** /Users/josephcursio/xcode_projects/SwiftProjectLint/Packages/SwiftProjectLintModels/Sources/SwiftProjectLintModels/RuleIdentifier.swift:108-109 (`swiftlintSuppression`, `swiftprojectlintSuppression`).

**Verifier.** RuleIdentifier.swift:108-109 spells them `swiftlintSuppression` and `swiftprojectlintSuppression`.

**Change.** (`swiftlintSuppression`, `swiftprojectlintSuppression`)

**Checked and correct:**

- Sitrep is Apache-2.0 licensed and SwiftSyntax-based (/Users/josephcursio/GitHub_projects/Sitrep/LICENSE, Package.swift)
- Sitrep's Function model stores no source range (Sources/SitrepCore/Function.swift)
- SwiftProjectLint CandidateInventory exists, and its numbers match the PRD: 76% of findings, 460 pure functions, 204 pure closures (Sources/Core/Export/CandidateInventory.swift:5-7)
- extractableTotalKernel is treated as a defect (listed) in CandidateInventory, consistent with §6.4 and §7.15
- SwiftProjectLint emits JSON, CSV, HTML and pbt-seeds formats (Sources/CLI/SwiftProjectLintCLI.swift:16-22)
- SwiftProjectLint JSON fields include file, line, rule, category and severity, plus message, suggestion and symbol (CodableLintIssue.swift)
- SwiftProjectLint rule identifiers exist as named: forceUnwrap, forceTry, forceCast, unconditionalTrap, uncheckedSendable, nonisolatedUnsafe, unsafeMemoryAPI, todoComment, couldBePrivate, couldBePrivateMember, protocolCouldBePrivate, circularDependency, layerDependency, undeclaredTargetDependency, testMissingAssertion, testMissingExpect, testMissingRequire, duplicateStructShape, duplicateEnumMapping, parallelEnumShape, scatteredEnumMapping, parallelListDrift, pureFunctionCandidate, pureClosureCandidate, pureMutatorCandidate, missingEquatableOnPureResult, extractableTotalKernel
- SwiftProjectLint has about 220 rule cases (RuleIdentifier.swift)
- SwiftEffectInference ships as a library with no CLI (Sources/ has a single library target; README)
- SwiftEffectInference's five-tier lattice spellings match §7.10: pure, observational, idempotent, externally_idempotent, non_idempotent (EffectAnnotationParser.swift:354-357)
- SwiftCloneDetector has a `--format json` output (README)
- SwiftLint's rule identifier is `cyclomatic_complexity`
- Milestone order M2 (store) before M3 (history) is consistent; M3 needs the store and M1 complexity, both earlier
- M4's divergent-clones signal needs git history from M3, which comes earlier
- M6's best-property-target signal needs property candidates from M4, which come earlier
