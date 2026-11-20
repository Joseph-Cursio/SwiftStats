# M4 results

**Date:** 2026-11-20 · **Toolchain:** Apple Swift 6.4.2 (Xcode 27), macOS 27.2 SDK; SwiftInferProperties is scanned under its own `.swift-version` pin, 6.4.1 · **Machine:** Apple M3, 8 cores · **Git:** 2.54.0 (Apple Git-157) · **Tools:** SwiftLint 0.65.1, GRDB 7.12.0, SwiftEffectInference `ba3624d` (linked), swift-infer 1.160.0 (release build of SwiftInferProperties `79908525`), swift-clone-detector 0.1.0 (release build of SwiftCloneDetector `97eee1c`)

M4 scope (PRD §11): adapters for SwiftEffectInference, SwiftInferProperties and SwiftCloneDetector, law detection as SwiftStats' own measurement, history's commit lists, store migration v3, and six signals: untested property, tool disagreement, missing template, unchecked laws, divergent clones and clone hotspot. The packages are M3's: SwiftInferProperties (SIP) and SwiftProjectLint's rules package (SPLR, `Packages/SwiftProjectLintRules`). The design is PRD v0.2.10: §6.2, §6.5, §6.6, §7.10–§7.13, §8, §9, §10, §10.1, §11, §12, §13 and §15.

## Done-when

| # | Criterion | Status | Evidence |
|---|---|---|---|
| 1 | On both packages, the tool-disagreement table is produced; a package with no rows counts when its funnel is printed, since a fixture test shows the signal yields rows | Met | SIP lists 4 rows (below). SPLR lists none and prints its funnel: of 37 suggestions, 9 shared signature, 0 shadowed or declared, 4 not a production func or unmapped, 24 no body-inferred tier, 0 inferred tier not `non_idempotent`. `ToolDisagreementTests` ("a unique function with a heuristic non_idempotent callee and an idempotence row is listed, replay first") produces three rows from a fixture. |
| 2 | On both packages, the divergent-clones list is produced against an earlier snapshot made with `swiftstats diff <rev>` | Met | S is the last first-parent commit at least 90 days before C, scanned with every tool by `swiftstats diff <S>`. SPLR: 57 members against `d77ebb8fd5`. SIP: 69 members against `dd753154d8`. The first 20 of each are below. |
| 3 | On both packages, every SwiftInferProperties suggestion, interaction rows included, maps to a record or is listed as unmapped | Met | SIP: 955 candidates (91 interaction), 954 attached to a function, 1 listed as unmapped (`0xCF73C07D39453051`, location `<corpus>:0`). SPLR: 577 candidates (2 interaction), all attached. On both, the multiset of (population, identity, location) equals the merged union of `swift-infer index --target T` run by hand in fresh per-target copies. |
| §12.1 | `scan --no-history` on swift-collections with every T0 collector finishes in under 30 s with a warm build | Met, at an untagged commit | 12.68 s at upstream main `a807eb67` (2026-11-19). M2's commit `294059c7` is not in apple/swift-collections, and `a807eb67` is not a named tag (`1.7.6-27-ga807eb67`). |

`report` gave byte-identical Markdown and JSON on two runs for each package.

### Tool disagreement (SIP, all rows)

The funnel: of 162 idempotence-class suggestions, 42 shared signature, 3 shadowed or declared, 2 not a production func or unmapped, 108 no body-inferred tier, 3 inferred tier not `non_idempotent`. SwiftEffectInference is `ba3624d754` in SwiftStats, and `ba3624d754` in swift-infer (read from its build's `workspace-state.json`).

| # | Function | Template | SIP tier / score | Via | Depth |
|---|---|---|---|---|---|
| 1 | `SwiftInferCommand.Index.mergedAlgebraicSurface(pipeline:into:decisionsByHash:now:context:)` | replay-idempotence | Likely / 40 | calls `merging(shapes:sourceFiles:localTypeNames:packageRoot:diagnostics:)` | 6 |
| 2 | `GeneratedFileGeneratorHoist.hoisted(_:)` | idempotence | Possible / 35 | from the callee name `insert` | 1 |
| 3 | `GeneratedFileLayout.laidOut(_:)` | idempotence | Possible / 35 | calls `hoisted(_:)` | 2 |
| 4 | `SwiftInferCommand.Discover.dedupedByIdentity(_:)` | idempotence | Possible / 35 | from the callee name `insert` | 1 |

All four have source `purity`, purity `pure` and a heuristic anchor. All four are SwiftEffectInference false positives: the calls behind the guesses are on local variables (`seen.insert`, `declarationsByIdentity[key, default: []].insert`, `generators.append`, `declarations.typeDecls.append`). Row 1's chain runs through `merging` (5), `scan` (4) and `FunctionScanner.scanTypeDecls` (3), whose via holds the `append` reason. This is what the rule says the list is for: calibrating SwiftEffectInference's heuristic and receiver resolution.

### Divergent clones

Columns: the subject is the first unchanged copy; "other unchanged" counts the further unchanged units in diverging slots; each changed unit shows its non-sweep commits since S and its last change (UTC date). Kinds: exact and renamed are the subtree pass, split by the `--type1` run.

**SPLR**, since `d77ebb8fd5` (2026-08-18 UTC; committed 2026-08-17 −05:00). 57 members of a pool of 512 S classes with at least two used copies; 230 copies skipped (no production, non-generated C family with known history); 21 classes folded into a listed one. Members by kind: near-miss 16, renamed 34, exact 3, sequence 4. Scores run from 51 to 3. 9 of the 57 subjects are `var pattern: SyntaxPattern` registrars.

| # | Unchanged copy (subject) | Other unchanged | Changed units: commits, last change | Kind | Copies | Score |
|---|---|---|---|---|---|---|
| 1 | `CouldAdoptProtocolVisitor.finalizeAnalysis()` | — | `DuplicateStructShapeVisitor.finalizeAnalysis()`: 2, 2026-11-10; `SharedDomainEnumFieldVisitor.finalizeAnalysis()`: 2, 2026-11-10 | near-miss | 3 | 51 |
| 2 | `GodViewModelVisitor.visit(_: ClassDeclSyntax)` | — | `ComputedPropertyViewVisitor.visit(_: ClassDeclSyntax)`: 2, 2026-09-09 | near-miss | 2 | 31 |
| 3 | `FlagOptionalPairState.pattern` | 1 | `MutuallyExclusivePresentationState.pattern`: 1, 2026-11-10 | near-miss | 3 | 30.5 |
| 4 | `EffectCycle.pattern` | 1 | `MutuallyExclusivePresentationState.pattern`: 1, 2026-11-10 | renamed | 3 | 28.5 |
| 5 | `MissingCancellationCheck.pattern` | 1 | `ParallelListDrift.pattern`: 1, 2026-10-08 | renamed | 3 | 22.5 |
| 6 | `CouldBePrivateVisitor.visit(_: IdentifierTypeSyntax)` | 1 | `ProtocolCouldBePrivateVisitor.visit(_: IdentifierTypeSyntax)`: 1, 2026-10-08; `ProtocolCouldBePrivateVisitor.visit(_: DeclReferenceExprSyntax)`: 1, 2026-10-08 | sequence | 2 | 22 |
| 7 | `GlobalActorMismatchVisitor.isAwaitPreceding(_: FunctionCallExprSyntax)` | — | `DemeterChainFilter.isInsideKeyPath(_: ExprSyntax)`: 1, 2026-09-24 | renamed | 2 | 18 |
| 8 | `FatProtocolVisitor.visit(_: ProtocolDeclSyntax)` | 1 | `ExclusivePresentationStateVisitor.visit(_: StructDeclSyntax)`: 1, 2026-11-10 | near-miss | 3 | 17.5 |
| 9 | `TestMissingMacroVisitorBase.hasTestAttribute(_: FunctionDeclSyntax)` | — | `ExclusivePresentationStateVisitor.hasPresentationAttribute(_: VariableDeclSyntax)`: 2, 2026-11-10 | near-miss | 2 | 16 |
| 10 | `ManualRegistrationList.pattern` | 7 | `MapUsedForSideEffects.pattern`: 1, 2026-09-12 | renamed | 9 | 15.75 |
| 11 | `ControlMissingAccessibilityLabel.pattern` | 29 | `MapUsedForSideEffects.pattern`: 1, 2026-09-12 | near-miss | 31 | 15.17 |
| 12 | `ArchitecturalBoundary.pattern` | 5 | `VariableShadowing.pattern`: 1, 2026-09-05 | renamed | 7 | 15.17 |
| 13 | `DuplicateEnumMappingVisitor.visit(_: EnumDeclSyntax)` | 1 | `ParallelListDriftVisitor.visit(_: EnumDeclSyntax)`: 1, 2026-09-12 | near-miss | 3 | 15 |
| 14 | `DuplicateEnumMappingVisitor.singleExpressionBody(_: CodeBlockItemListSyntax)` | 1 | `ClosureBody.soleExpression(of:)`: 1, 2026-09-10 | near-miss | 3 | 14.5 |
| 15 | `CompletionHandlerDataTaskVisitor.visit(_: FunctionCallExprSyntax)` | 1 | `MapUsedForSideEffectsVisitor.visit(_: FunctionCallExprSyntax)`: 1, 2026-09-12 | near-miss | 3 | 14 |
| 16 | `CouldBePrivateMemberVisitor.visit(_: ClosureExprSyntax)` | 1 | `DirectInstantiationVisitor.visit(_: FunctionDeclSyntax)`: 1, 2026-09-07; `DirectInstantiationVisitor.visitPost(_: FunctionDeclSyntax)`: 1, 2026-09-07 | sequence | 2 | 14 |
| 17 | `AnimationWithoutReduceMotion.pattern` | 59 | `ParallelListDrift.pattern`: 1, 2026-10-08; `ForceUnwrap.pattern`: 1, 2026-09-04; `PrintStatement.pattern`: 1, 2026-09-05; `TestMissingRequire.pattern`: 1, 2026-09-12 | near-miss | 64 | 13.41 |
| 18 | `DeprecatedAnimation.pattern` | 21 | `VariableShadowing.pattern`: 1, 2026-09-05 | near-miss | 23 | 13.14 |
| 19 | `MatchedGeometry.pattern` | 26 | `ForceUnwrap.pattern`: 1, 2026-09-04; `PrintStatement.pattern`: 1, 2026-09-05; `TestMissingRequire.pattern`: 1, 2026-09-12 | renamed | 30 | 12.41 |
| 20 | `CouldAdoptProtocolVisitor.isStoredInstanceProperty(_: VariableDeclSyntax)` | 4 | `DependencyConsumption.isStoredInstanceProperty(_: VariableDeclSyntax)`: 1, 2026-09-19 | near-miss | 6 | 12 |

**SIP**, since `dd753154d8` (2026-08-15). 69 members of a pool of 1,637; 1,473 copies skipped; 31 classes folded. Members by kind: near-miss 25, renamed 23, exact 1, sequence 20. Scores run from 102 to 2.06.

| # | Unchanged copy (subject) | Other unchanged | Changed units: commits, last change | Kind | Copies | Score |
|---|---|---|---|---|---|---|
| 1 | `VerifierWorkdir.renderTargetDependenciesBlock(userPackage:mode:)` | — | `VerifierWorkdir.renderDependenciesBlock(userPackage:mode:)`: 1, 2026-08-19 | near-miss | 2 | 102 |
| 2 | `DeterminismInteractionTemplate.whySuggestedFor(witness:candidate:)` | 2 | `UnknownActionIsNoOpInteractionTemplate.whySuggestedFor(witness:candidate:)`: 1, 2026-10-10; `UnknownActionIsNoOpInteractionTemplate.whyMightBeWrongFor(witness:)`: 1, 2026-10-10; `UnknownActionIsNoOpInteractionTemplate.analyze(candidate:firstSeenAt:)`: 1, 2026-10-10 | near-miss | 2 | 70 |
| 3 | `RoundTripTemplate.makeConstraint(vocabulary:inheritedTypesByName:carrierKindResolver:)` | — | `IdentityElementTemplate.makeConstraint(opsWithIdentitySeed:inheritedTypesByName:carrierKindResolver:)`: 1, 2026-11-10 | near-miss | 2 | 50 |
| 4 | `SwiftInferCommand.SuggestRefactors.humanReadableShape(_: ClusterShape)` | — | `SwiftInferCommand.SuggestRefactors.suggestionText(for:)`: 2, 2026-09-08 | near-miss | 2 | 49 |
| 5 | `InversePairTemplate.makeLiftedConstraint(carrierKindResolver:)` | — | `IdentityElementTemplate.makeLiftedConstraint(carrierKindResolver:)`: 1, 2026-11-10 | near-miss | 2 | 46 |
| 6 | `NormalFormTemplate.makeConstraint()` | — | `DifferentialTemplate.makeConstraint()`: 1, 2026-09-16 | near-miss | 2 | 42 |
| 7 | `TemplateRegistry.collectLiftedTemplatesForOne(transformation:context:resolver:into:)` | — | `TemplateRegistry.collectDualStyleSuggestions(summaries:context:into:)`: 1, 2026-09-08 | near-miss | 2 | 39 |
| 8 | `CodableRoundTripTemplate.makeConstraint()` | 2 | `EquivalenceRelationTemplate.makeConstraint()`: 1, 2026-09-16 | near-miss | 4 | 36.33 |
| 9 | `SeedRole.init(from:)` | — | `SeedKind.init(from:)`: 1, 2026-10-08 | near-miss | 2 | 29 |
| 10 | `ComparatorTemplate.makeCaveats()` | 3 | `InputTotalityTemplate.makeCaveats()`: 1, 2026-10-08 | near-miss | 5 | 28.5 |
| 11 | `CaseIterableMappingTemplate.makeCoverageConstraint(shapesByName:)` | 1 | `DiffDisjointnessTemplate.makeConstraint(match:)`: 1, 2026-09-16 | near-miss | 3 | 26 |
| 12 | `DiffDisjointnessTemplate.makeCaveats(match:)` | — | `SelectionSubsetTemplate.makeCaveats(match:)`: 1, 2026-09-16 | near-miss | 2 | 26 |
| 13 | `IdempotenceTemplate.fixedPointNameSignal(for:)` | — | `IdempotenceTemplate.returnShapeVeto(for:)`: 1, 2026-09-23 | near-miss | 2 | 24 |
| 14 | `InvolutionTemplate.makeConstraint()` | 2 | `ComparatorTemplate.makeConstraint()`: 1, 2026-09-16; `EquivalenceRelationTemplate.makeConstraint()`: 1, 2026-09-16 | near-miss | 5 | 22.75 |
| 15 | `CodableRoundTripTemplate.makeCaveats()` | 2 | `FilterSubsetTemplate.makeCaveats()`: 1, 2026-09-16 | near-miss | 4 | 20.67 |
| 16 | `FilterSubsetTemplate.makeConstraint()` | 4 | `ComparatorTemplate.makeConstraint()`: 1, 2026-09-16; `InputTotalityTemplate.makeConstraint()`: 1, 2026-09-16 | near-miss | 7 | 19.33 |
| 17 | `EndedAccessRoundTripTemplate.makeConstraint()` | 3 | `PartitionTemplate.makeConstraint()`: 1, 2026-09-16 | near-miss | 5 | 19 |
| 18 | `MonotonicityTemplate.makeCaveats()` | — | `SuggestionRenderer.conjectureCaveat(for:)`: 1, 2026-10-10 | near-miss | 2 | 17 |
| 19 | `IdempotenceTemplate.canonicalSignature(of:)` | 1 | `SwiftInferCommand.Discover.makeEvidence(for:)`: 1, 2026-09-15 | near-miss | 3 | 14 |
| 20 | `Tier.isVisibleByDefault` | — | `SeedKind.isAnalysable`: 1, 2026-10-08 | renamed | 2 | 14 |

`swiftstats top divergent-clones --limit 1000` prints all members on each package. Hand-checks of these lists are under "Checking the signals" below.

## What M4 adds

- **SwiftEffectInference, linked** at revision `ba3624d754c3c9150c946f66468c2c356be3e7e0`. It runs over production files after exclusion, plugin targets left out, sorted by path. SwiftStats runs its own strict resolution loop over `BodyEffectInferrer.inferEffects`: shared signatures resolve to nothing, a bodied package callee gives its previous-pass tier and no name guess unless the call goes through another receiver, and the loop stops when no tier changes (50 passes without that fail the collector). Each production `func`, computed getter and subscript gets `effect`: tier and its source, declared facts, purity and refutation, and, for a `func`, the inference state, the body-inferred tier with depth, anchor and up to three `via` reasons, `valueShaped` and `shape`.
- **Law detection**, a `swiftstats` measurement. Types record their `conformances`. Each production subject and each of the 33 kit protocols SwiftStats knows (`KnownProtocol`) gives a `LawCheck` with provenance, `custom` or `synthesized` implementation, and state `suppressed`, `run`, `waived` or `notRun`, with the evidence (marker, call, macro). Private and fileprivate subjects carry ` @ <file>`.
- **SwiftInferProperties.** `swift-infer index --target T` runs per library, executable and macro target, each in an APFS clone of a temporary copy of the package with its own `TMPDIR`, at most four at once, in the background from the start of the scan. The fresh indexes are merged by SwiftStats and mapped to records. Candidates are joined to the package's own `decisions.json`, `interaction-decisions.json` and `verify-evidence.json`, whose hashes are kept as provenance. `verified` and `disproven` are computed from fresh evidence. Test links come from generated stubs, `@CheckProperty` by kind, and a name heuristic. The copy follows the vocabulary file `config.toml` names.
- **SwiftCloneDetector**, four runs (subtree, `--type3`, `--sequence`, `--type1`) over an explicit, byte-sorted list of the production files read as UTF-8, merged by SwiftStats and mapped to the records each copy holds or sits inside.
- **History's commit lists:** `commitLog` (hash, date, sweep, fix) and each family's `changedBy`.
- **Scan JSON `schemaVersion: 6`**, report `3`, top `2`. **Store migration v3**: side-effect columns and `generated` on `function`, plus `scanFacts`, `propertyCandidate`, `lawCheck`, `cloneClass`, `cloneInstance`, `historyCommit` and `familyChange`.
- **Roll-ups** of side-effect tiers and purity, candidates by tier, law pairs by state, and clone classes by kind with cloned lines. Markdown gains Side effects, Property candidates (listing every unmapped candidate), Law checks and Clones sections.
- **Six signals** in `report` and `top`. Only clone hotspot is ranked (`signals.clone-hotspot.threshold`, default 10).
- **Configuration and commands.** `collectors.swifteffectinference.enabled`; `path` on it is rejected. `backfill` runs SwiftEffectInference, and `--with-tools` also runs the two external tools. `trend` reads a keyed count as 0 once some point stores it for that module or part. `diff` and `backfill` retry an export scan without its `.swift-version` pins, the package's own and the one inherited from above a nested package. An interrupted scan (SIGINT, SIGTERM or SIGHUP, unless ignored at start) stops swift-infer's runs and removes the temporary copy.

## Results on the two packages

### Setup

Scratch clones of SIP at `7990852508` and of SwiftProjectLint at `6477efac57`, with `--store` and `--config` outside the package. The owners' join files were copied into each clone's `.swiftinfer/` (git-ignored, so the snapshots stay clean). Neither package has `interaction-decisions.json`.

| Copied file | sha256 |
|---|---|
| SIP `.swiftinfer/decisions.json` | `f590bd9dcfa241c0e24a906859d9ab55e3fc12c2853a6705c33a4ad117933d7a` |
| SIP `.swiftinfer/verify-evidence.json` | `95c57c52331579421b807edb38a5a00ecc23886987da853e70e4a6d8d1f83816` |
| SPLR `.swiftinfer/decisions.json` | `7d7099ac2f0a96326c080c68e42bb26cebdba997bc99f025fe5b3aeeb11f3204` |
| SPLR `.swiftinfer/verify-evidence.json` | `401e2c79cf412348292ec8820967aa740e5a19845f4a626b17732562651d931f` |

The owner trees were clean at those commits, and the scratch clones stayed clean after every run. Both S snapshots are clean. SwiftProjectLint was not on PATH, so its collector was skipped in every run here. Dependencies were skipped on both packages because they were not resolved.

### Times

Release build, this Mac. Each warm scan is in place, into its own store. The budget is design §9's.

| Run | SIP | SPLR | Budget SIP / SPLR |
|---|---|---|---|
| First scan in a fresh clone (cold) | **57.84 s** | 13.68 s | ≤ 52.5 s / ≤ 22.3 s |
| `diff <S>`: export and scan S with every tool (cold) | 50.21 s | 7.71 s | — |
| Warm, M3-equivalent (SEI, swift-infer and clones off) | 19.41 s | 5.15 s | M3 measured 20.5 s / 8.0 s |
| Warm, + SEI only | 20.37 s | 5.50 s | |
| Warm, + swift-infer only | 28.79 s | 11.77 s | |
| Warm, + clones only | 20.19 s | 6.37 s | |
| Warm, every collector (two runs) | 30.26 s / 30.29 s | 12.47 s / 12.44 s | ≤ 52.5 s / ≤ 22.3 s |
| `report` | 2.59 s | **1.41 s** | ≤ 3 s / ≤ 1 s |

- **The cold SIP scan exceeds the whole-scan budget**: 57.84 s against 52.5 s. The warm SIP scan is within it, at 30.26 s. In the cold scan SwiftLint's own time was 38.9 s and swift-infer's 23.2 s; in the warm scan they were 5.8 s and 20.9 s.
- **SPLR's `report` took 1.41 s, over its 1 s bound.** The bound was written for the divergent-clones inputs (rev-list, diff, FamilyMatcher), and those were not timed apart from the rest of `report`, so whether that step alone is over is not known. SIP's `report` is within its 3 s.
- Over the M3-equivalent warm scan, the three new collectors together add 10.85 s on SIP and 7.32 s on SPLR. swift-infer accounts for most of it (9.38 s and 6.62 s alone).
- Collector times in the warm every-collector snapshots, measured while the others run, against the per-step bounds: swift-infer 20.9 s (≤ 22) and 7.9 s (≤ 10); clones 4.4 s (≤ 6) and 1.4 s (≤ 2.5); SEI 1.9 s (≤ 2.5) and 0.7 s (≤ 1.0). Law detection and store rows are not timed on their own.
- These times have no SwiftProjectLint run and no dependency resolution in them.

### What each package gives

| | SIP `7990852508` | SPLR `6477efac57` |
|---|---|---|
| SEI passes | 9 | 9 |
| Body-inferred `non_idempotent` (unique, source not declared, conflicting or unknown) | 123 | 119 |
| Purity: pure / pure but partial / refuted | 3,508 / 41 / 352 | 2,271 / 0 / 4 |
| Candidates (interaction), attached, unmapped | 955 (91), 954, 1 | 577 (2), 577, 0 |
| Merge: duplicates / conflicts / collisions | 8 / 1 / 0 | 0 / 0 / 0 |
| Candidates by tier: Strong, Likely, Possible, Advisory | 12, 97, 484, 362 | 2, 23, 417, 135 |
| Decisions (all `accepted`), orphan decisions, orphan verify records | 825, 241, 7 | 394, 17, 0 |
| Law pairs: run / notRun; kit dependency | 4 / 656; yes | 0 / 23; no |
| Clone classes (copies); cloned share of stripped lines | 2,322 (7,290); 42.5% | 842 (3,266); 40.0% |
| Classes: exact, renamed, sequence, near-miss | 156, 859, 822, 485 | 72, 367, 286, 117 |

SIP's 12 Strong candidates are 7 at production sites and 5 at test sites. The 5 test-site rows are lifted from tests and were found by more than one target; the merge's 8 duplicates and 1 conflict are all copies of them.

| Signal | SIP members / pool | SPLR members / pool |
|---|---|---|
| Untested property | 52 / 79 | 2 / 2 |
| Tool disagreement | 4 / 162 | 0 / 37 |
| Missing template | 105 / 606 | 15 / 398 |
| Unchecked laws | 22 / 466 | 1 / 20 |
| Divergent clones | 69 / 1,637 | 57 / 512 |
| Clone hotspot (ranked) | 63 / 597 | 71 / 330 |

Notes on the counts:
- Untested property, SIP: 46 of the 52 rows are Verified (42 Possible scoring 85, 3 Likely, 1 Strong), 2 are Strong and not Verified, and 4 are blocked Advisory rows. SPLR has no test target, and its rule says so.
- Missing template leaves out the pure, value-shaped functions with no algebraic shape: 2,345 on SIP, 624 on SPLR. Every member is purity `pure`.
- Unchecked laws leaves out the `notRun` pairs with synthesised witnesses: 634 on SIP, 22 on SPLR.
- Clone hotspot leaves out the classes with a copy covering under 80% of its function: 1,725 on SIP, 512 on SPLR. Ties at the cut are kept, so SPLR has 71 members, 21.5% of its pool: rank 33 scores 2, and 41 classes score 2. SIP's rank 60 also scores 2, giving 63.

### Expected and measured

| Design §11 expectation | Measured |
|---|---|
| S: `d77ebb8` (SPLR, 2026-08-17), `dd75315` (SIP, 2026-08-15) | Same commits. The SPLR rule prints 2026-08-18, the UTC date. |
| SIP mapping: 964 rows, 955 keys, 9 / 1 / 0 | 964 rows, 955 keys, **8 / 1 / 0**. 964 − 955 = 9 dropped rows, which is 8 duplicates plus 1 conflict; the 9 came from swift-infer's upsert count, which counts the conflicting row as well. |
| SPLR mapping: 575 + 2 | 575 + 2 |
| Tool disagreement funnel, SPLR: 9/0/4/24/0, 0 rows | 9/0/4/24/0, 0 rows |
| Tool disagreement funnel, SIP: 45/0/2/108/3, 4 rows | **42/3**/2/108/3, the same 4 rows. The 3 are annotated `/// @lint.effect idempotent` functions whose signatures are also shared. Step 1 ranks `annotated` before `ambiguous`, so they count as declared. |
| Each SIP `via` shows the heuristic `insert`/`append` reason | 2 show it directly; 2 show "calls …", and the reason sits further down the chain. That follows §1.1 step 4. |
| No `visit(_:)`/`visitPost(_:)` rows in SPLR's missing template | 0. SPLR has 687 such functions: 648 not value-shaped, 39 `override` and so shapeless. |
| SIP's local-accumulator functions such as `sorted(in:)` stay in the missing-template pool | `sorted(in:)` is not in the pool: its purity is refuted (`FileManager`) and `URL -> [URL]` matches no shape. The property holds otherwise: 78 of the 606 pool functions build local accumulators. |
| Untested property includes Verified rows; orphan decisions near 241 | 46 of 52 listed rows are Verified; 241 orphan decisions |
| SPLR: decisions all `accepted`, Verified about empty | 394 decisions, all `accepted`; 1 Verified. 17 of its 18 `measured-bothPass` records have a null fingerprint, so they are never fresh. |
| Divergent clones non-empty on both | 57 and 69 |
| Unchecked laws: SIP ≲ 40 custom `notRun` pairs | 22 |
| Unchecked laws: SPLR about 3, `kitDependency` no | **1** (`WideReachThroughVisitor.Pair`'s `<`), `kitDependency` false. SPLR's sources hold exactly one hand-written witness. |
| SIP's 4 `run` pairs on `Tier`; Tier's CaseIterable `synthesized` | Both hold |
| SEI: 125 (SIP) / 119 (SPLR) `non_idempotent` in 8 / 9 passes | 123 / 119 in 9 / 9. Review fix #1/#2 removed one SIP name guess (`MetricsRenderer.postAcceptanceFailureSection`, from the `post` prefix) and the tier one caller (`MetricsRenderer.render`) took from it; the tree before it already took 9 passes on SIP. |
| SIP hand-run swift-infer: 16.1 s wall | 17.0 s |

### Checking the signals

Independent scripts re-derived each signal from `scan.json` and the stores, and rows were hand-checked against the source and git.

- **Mapping.** All 954 attached SIP candidates point at an existing record in the same file whose range holds the row's line, with `site` matching the record's role. The 7 SIP and 5 SPLR computed-property rows map to getters starting on the row's line. A second SPLR run inside the full `Packages/` layout, where its path dependencies exist, gave the same 577 rows, so the copy's missing sibling packages change nothing.
- **Tool disagreement.** Review fix group 1 moved none of the 162 SIP or 37 SPLR pool rows.
- **Missing template.** Six rows checked (SPLR `lawAdvice(mutates:)`, `callForm(_:size:)`, `reanchored(_:ownership:after:)`; SIP `IndexStore.defaultPath(for:)`, `SymbolJoinKey.make(file:symbol:)`, `GeneratedFileText.collapsingBlankLines`): shape, body lines, cognitive and purity match, and no candidate names them. `collapsingBlankLines` looks genuinely idempotent, which is the kind of row the signal is for. `defaultPath(for:)` appends a path component, so SIP is right not to suggest idempotence there; that is a precision limit of the signal. Comparable `<` operators such as `Tier.<` also appear; they overlap with law checks.
- **Untested property.** Two SIP rows checked. `BindingActionResolver.resolve(_:)` (Possible 35, Verified, shown as 85) has fresh `measured-bothPass` evidence and only example tests. `ConstructionUniverse.deduplicated(_:)` (Strong 75) has no evidence and only an example test. Both are right. 6 of the 52 rows are in fact checked by property tests (see Not done).
- **Unchecked laws.** Three SIP rows (`GeneratedFileScan.Group` Equatable, `IndexStore.Index` Codable, `SourceLocation` Comparable) and SPLR's one row are right. Every hand-written `==` or `<` in SIP's sources belongs to a pair marked `custom`. 12 of SIP's 22 rows are Codable types whose round-trip suggestion is linked to a hand-written property test; unchecked laws still lists them, because it counts only kit calls, the macro and markers.
- **Divergent clones.** Three rows per package, all correct against git:
  - SPLR rank 6 (`CouldBePrivateVisitor` / `ProtocolCouldBePrivateVisitor`): commit `9f9646c7` wrapped each reference in `compositionAliases.expand(...)` in one copy only. Worth attention.
  - SPLR ranks 1 and 2: correct as computed, but not worth attention. The paired functions are not clones of each other (Not done, item C).
  - SIP rank 1 (`renderDependenciesBlock`): a version-pin edit to one of two parallel lists. Borderline.
  - SIP rank 2 (the two interaction templates): a template-specific fix. Low.
  - SIP rank 25 (four per-case string arms in `suggestionText(for:)`, followed through a file rename): not worth attention.
- **Clone hotspot.** Each top-3 score was compared with `git log -L` on the copies since the window start, sweeps left out. They match except SPLR rank 2, where git gives 11: the store also counts two type renames that `git log -L` can't follow the identical init body through, and git also counts a move-only reorder that the store rightly ignores.

| Package | # | Class | Copies | Score | Commits creating a copy / editing one | Worth attention |
|---|---|---|---|---|---|---|
| SPLR | 1 | near-miss, `var pattern: SyntaxPattern` registrars | 66 | 15 | 9 / 6 | No |
| SPLR | 2 | exact, boilerplate `required init(pattern:viewMode:)` | 144 | 12 | 12 / 0 | No |
| SPLR | 3 | near-miss, the same 144 copies plus 2 | 146 | 12 | 12 / 0 | No: rank 2 again |
| SIP | 1 | near-miss, `InteractiveTriage.entailedTemplateStub` and `valueLawStub` | 2 | 17 | 2 / 15 | Yes: two parallel dispatch switches edited by almost every new template |
| SIP | 2 | near-miss, `makeConstraint()` across 12 templates | 12 | 9 | 7 / 2 | Low |
| SIP | 3 | subtree, 3-line `suggest(for:)` forwarders across 26 templates | 26 | 8 | 8 / 0 | No |

### swift-collections

M2's commit `294059c7` is not in apple/swift-collections, so this used upstream main `a807eb67` (2026-11-19).

| Run | Time |
|---|---|
| Stored scan, every collector: first, second, third | 19.73 s, 18.75 s, 18.45 s |
| Stored scan, M3-equivalent | 12.54 s |
| `--no-history`, every collector (PRD §12 criterion 1: < 30 s) | 12.68 s |
| `diff HEAD~5 HEAD~1` (`68388f097f` → `50cce1e818`), both commits unscanned | 27.94 s (M2: 30.4 s at `294059c7`) |

The design expected 18 to 20 s for the stored every-collector scan. The three scan JSONs were byte-identical. The scan holds 7,236 records, 881 candidates and 2,757 clone classes. SwiftProjectLint was skipped here too.

## Decisions

Decided for M4:

- **SwiftEffectInference is pinned by revision `ba3624d`**, the one SwiftInferProperties and SwiftProjectLint pin. `c8644fd`, named earlier, was a stale local checkout.
- **swift-infer runs in a temporary copy**, and the joins read the package's own `.swiftinfer/`. The scanned package is never written.
- **The tool binaries for these runs were built from scratch clones.** The user's repositories and PATH were not touched.
- **The done-when packages are SIP and SwiftProjectLint's rules package.**
- **An empty tool-disagreement table counts as produced when its funnel is printed**, with a fixture test proving the signal yields rows.
- **Unchecked laws covers only hand-written witnesses.** Synthesised pairs are counted, not listed.
- **Missing template covers pure, value-shaped, template-shaped functions with no candidate of any tier.** Advisory rows count as candidates.
- **`kit-evidence.json` is not read**, and law detection is a SwiftStats measurement, not a collector.

Decided during the review:

- **Plugin targets are out of SwiftEffectInference's universe**, as swift-infer never indexes them. Executable and macro targets stay in.
- **Strict resolution never name-guesses a bodied package callee, except through another receiver.** An unqualified or `self.` call takes only the callee's previous-pass tier. A call such as `logger.info` takes the higher of that tier and the guess. Each pass is then monotone, so the loop converges. This takes, for unqualified calls, a design finding first left out ("unique package callees resolve to nil").
- **Divergent clones compares commits only**, and on a dirty snapshot its rule says "uncommitted changes aren't compared".
- **Its left-out reason names `swiftstats diff <rev> --rescan`**, and `backfill --with-tools` only for commits not yet scanned.

Choices made while building, where the design left room or strict SwiftLint forced a shape:

- **Resolution order** is collision, then declared, then shared, as in SwiftEffectInference, so an annotated requirement with several bodied conformers still gives callers its tier. Inference states rank annotated, ambiguous, shadowed, unique; this is why SIP's funnel reads 42/3.
- **Grouped JSON** where null must differ from false or empty and `Bool?` and optional collections are forbidden: `effect.declaration` and `effect.function`, `verification` on candidates, `clone.divergence` on signal items, and the `CommitOrdinals` wrapper for `changedBy`.
- **A FloatingPoint waiver is its own law state, `waived`.**
- **Merge counts** give rows dropped (duplicates, conflicts) and identities at more than one location (collisions).
- **Divergent clones' score** is the stripped lines of every copy's units in diverging slots, divided by copies − 1.
- **A two-function suggestion covers its partner** in missing template. Partners resolve by labels to exactly one record, never the primary itself.
- **An export carries the repository's `.swift-version`** from above a nested package, and swift-infer's options record the pin.

## Review

Each of the ten implementation steps was reviewed as it was built. Those reviews raised 26 findings: 21 were fixed, each code change with a regression test, and 5 were declined with reasons, either as recorded deviations (the grouped JSON shapes above, `CommitOrdinals`) or because the premise was false (`#if` twins share no key).

The finished code then had an adversarial review across ten dimensions: effects, laws, the swift-infer run, candidate mapping, clones, the store, the property signals, the clone signals, end to end, and a critic. A verifier reproduced each claim. 25 findings were confirmed (1 high, 11 medium, 13 low), 2 were design questions, and none was refuted. #19 and #23 were the same defect, so there were 24 distinct defects. 23 were fixed, in seven groups, and #13 can't be fixed in SwiftStats. Each fix has a regression test that fails with the fix undone. Each group's fix was then reviewed in turn; those reviews found 8 more defects, all fixed the same way. After the fixes, 377 tests in 80 suites pass from a clean build (200 before M4), and strict SwiftLint is clean.

- **Side effects (#1, #2, #3, #26).**
  - (high) In a call cycle where one name matched the heuristic, the guessed tier swapped between the two functions every pass, and after 50 passes the whole collector failed. A recursive function kept the heuristic's guess about itself. Fixed by the strict-resolution rule above. Its first version also dropped the guess for external calls sharing a package signature (`transport.send`, `logger.info`); the group review caught that, and calls through another receiver now keep the guess.
  - A binding anywhere in a function hid a stored-property write elsewhere (`if let pending` then `pending = value`), so the function read value-shaped. Bindings are now scoped.
  - A plugin's same-signature function made a library function `ambiguous` (#26, design question).
- **Law checks (#4–#9, #22).**
  - Same-named private types in different files merged into one subject, so one type's witnesses decided the other's pairs.
  - A type nested in `extension Core.Money` got the module name twice.
  - A generic parameter or associated type in a check resolved to a production type of that name, giving a false `run`.
  - A check through a typealias was dropped.
  - `extension Wrap<Int>: Equatable` made no pair.
  - A file-scope `==` or `<` wasn't seen as a witness.
  - The group review found three regressions: a re-export typealias made a check ambiguous; a type nested in an extension written through an alias became ambiguous; and a file-scope operator counted as a witness where the conformance can't see it. All three are fixed.
- **The swift-infer run (#10–#13).**
  - The copy kept `config.toml` but not the vocabulary file it names, so swift-infer scored differently in the copy (a Likely 70 row read Possible 30).
  - One unreadable target file failed the collector, with a reason that changed every run.
  - A scan killed by a signal left the copy behind and swift-infer running.
  - #13: swift-infer's manifest scratch ignores `TMPDIR` on macOS (Not done).
  - The group review found that the new signal handling replaced an inherited `SIG_IGN`, so `nohup swiftstats …` died on SIGHUP, and that `vocabularyPath` was read from a config swift-infer rejects as a whole. Both are fixed.
- **Candidate mapping (#14–#16, #21).**
  - A partner resolved to the first overload of its base name.
  - An unreadable join file's warning held an absolute path and a pointer address.
  - One `@CheckProperty(.idempotent)` marked every candidate on the function and its partner as tested.
  - Missing template listed plugin functions, which swift-infer never indexes (#21, fixed by #26's change, with its own test).
- **Clones (#17, #25).** A file the scan skipped as not UTF-8 was still given to swift-clone-detector. A report with an inverted range crashed the scan (SIGTRAP); it now fails the collector.
- **Exports and trend (#18, #20).**
  - A nested package's export carried a stale inherited pin, so `diff` and `backfill` failed on old commits.
  - `trend` showed "—" instead of 0 when a keyed count fell to zero. The group review found the first fix made up a 0 for counts never collected in a scope and for misspelt keys; trend now follows `diff`'s rule.
- **Clone signals (#19/#23, #24, #27).**
  - The left-out text named commands that add no clone data.
  - An inherited `GIT_DIFF_OPTS` overrode `-U0`, and a `-diff` attribute or `core.bigFileThreshold` turned a file's hunks into a binary notice.
  - A dirty snapshot mixed working-tree families with committed changes (#27, design question).
  - The group review found `--text` pulled every changed binary asset into the diff; the diff now covers only `*.swift`, with `GIT_LITERAL_PATHSPECS` pinned.

## Not done

- **Divergent clones: a sweep in a copy reads as a change.** On SIP, 13 of the 69 members are false positives. A restructuring sweep (`eaffedf2`, `3e056330`) left a large hunk over the copy, while an unrelated non-sweep commit changed the host function. The design accepted this case, but those two sweeps make it far more common than expected. A fix could take overlap from the non-sweep commits' own diffs, mapped back to S lines, or use `git blame --reverse`.
- **Clone hotspot counts the commits that created a copy.** SPLR ranks 2 and 3 and SIP rank 3 score only from new copies being added. Leaving each family's creating commit out of the count could fix this, and the same applies to divergent clones' commit column.
- **The slot rule pairs functions that are not clones (item C).** In near-miss classes spanning whole types, units pair by signature alone, so SPLR ranks 1 and 2 pair unrelated bodies. Paired units could be required to be clones themselves.
- **Clone hotspot has no folding**, so near-identical classes repeat (SPLR rank 3 is rank 2's 144 copies plus `DocumentationVisitor` and `MagicNumberVisitor`).
- **Untested property misses tests through closure tables.** 6 of SIP's 52 rows (the two `bareTypeName(from:)` and four `strippingGenericParameters` rows, all Verified) are checked by property tests that call them through a `private static let implementations` table outside the test body, which the heuristic can't see. In the other direction, every `codable-round-trip` candidate links through the base name `encode`, including one no test names (`SeedRequirement`, outside the pool).
- **swift-infer's manifest scratch** stays in the per-user temporary directory, shared by concurrent runs (#13). It needs a change in SwiftInferProperties: honour `TMPDIR`, or take a scratch path.
- **`kit-evidence.json`** is not read; revisit when it carries per-protocol evidence.
- **M3's done-when 1 is still waiting on labels** (`Tests/Fixtures/HotspotLabels/` and `Tests/Fixtures/FixLabels/`).
- **The SwiftProjectLint collector was not exercised** in these runs, and dependencies were not resolved on SIP or SPLR. §12 criterion 1 ran at an untagged swift-collections commit.
- **Four design expectations were off**, and the measured values above replace them: SIP's merge is 8/1/0, not 9/1/0; SIP's funnel is 42/3, not 45/0; SPLR has 1 unchecked-laws row, not about 3; and `sorted(in:)` was the wrong example for the missing-template pool.
- **Known limits kept from the fixes:** a recursive call through another receiver keeps its name guess; an associated type inherited from another protocol, and an extension of a foreign generic type with no where clause, aren't put in a check's scope; a public `==` in the type's module used by a retroactive conformance elsewhere reads `synthesized`; SIGTERM reaches only SwiftStats' own direct children, the swift-infer processes, so a swift-infer grandchild such as a running `swift package dump-package` gets no signal, and SIGKILL can still leave the copy; `PackageResolvedReader` still puts `\(error)` in a warning (it predates M4).
