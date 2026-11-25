#!/usr/bin/env python3
"""Check a `swiftstats scan --index` result independently (M7 done-when).

The index collector reads the index store the T1 build writes, through
indexstore-db's `IndexStore` product. This script reads the same store
without using any of SwiftStats' code or that product: its own reader is
`ctypes` over the toolchain's `libIndexStore.dylib`, through the C API's
`_apply_f` (function-pointer) entry points (M7 design, sections 2.2, 11 and
13). The build collector reads the same build's stdout and stderr; this
script reads them with its own line patterns, not design section 6.1's
grammar, and accounts for every line. Run it as `python3 -I -B Scripts/index-check.py <mode> ...`, so it
writes no bytecode cache beside itself.

Modes: dump, build-lines, build, usr, rows, dead and signals (a later plan
step adds `coverage-names`).

`dump` writes the reader's values for a store as JSON: the recorded
`reader.json` the unit tests read through `RecordedIndexSource`, and the
other side of `IndexStoreReaderLiveTests` (check u0), so recordings come
from a reader that isn't the code they test (design section 13,
Recordings step 3). It doesn't class units or join anything; it holds:

  units    every non-system unit of the store, by unit name: `name`,
           `module` (the unit's module name as stored: a C99 name),
           `mainFile`, `target` (the triple), `isSystem` (false here),
           `modified` (`seconds`, `nanoseconds`), `records` (the names of
           its dependencies of kind record, sorted) and
           `moduleDependencies` (`module`, `isSystem` of each dependency
           of kind unit, sorted by module then isSystem, duplicates kept).
  records  every record named by a unit whose main file is under <root>
           (stale units' too; units under <root>/.swiftstats or .build
           too, since they are under the root), each once, by record name:
           `name`; `file`, the path the record dependencies of every
           non-system unit give it (units outside <root> included, as
           SwiftStats' reader, which doesn't know the root, notes them);
           `otherFiles`, only when they give one record several paths
           (files with one name and the same contents, such as
           swift-syntax's `VersionMarkerModules/*/Empty.swift`), `file`
           then being the first path in code point order and `otherFiles`
           the rest; and `occurrences`, each with `line`, `column`
           (1-based, UTF-8 bytes), `roles` (the occurrence's role bits as
           stored, relation bits included), `usr`, `name`, `kind`,
           `subkind`, `properties` (raw numbers) and `relations` (`roles`,
           `usr`, `name`, `kind`, `subkind`, `properties` of each related
           symbol).
  files    `path` and `sha256` of every source file of the package at
           <root>: each target's `sources` in <describe.json> (joined to
           the target's `path`) and the root's manifests (`Package.swift`,
           `Package@swift-*.swift`), by path. The recorded dumps' staleness
           test compares these with the fixture's bytes.

plus `root`, `store` and `library` (`path`, `apiVersion` and
`formatVersion` as the library reports them), for provenance.

Paths (`mainFile`, `file`, `otherFiles`, `files`, `root`, `store`,
`library`) are absolute real paths in NFC, made by realpath(3); a path that
no longer exists (a stale unit's main file) gets its longest existing
ancestor resolved and the rest appended. "" stands for a unit with no main
file (a clang module unit such as `_NumericsShims-….pcm-…`).
Order, so the output is the same on every run over the same store: units,
records and files by name or path (code point order); occurrences of a
record by line, column, usr, roles, kind, subkind, properties, name, then
relations; relations of an occurrence by usr, roles, kind, subkind,
properties, name. A consumer comparing this dump with another reader sorts
that reader's values the same way (or compares them as multisets).
`modified` is the unit file's date, so a re-recorded dump differs there
even when nothing else changed.

Inputs `dump` trusts:
  - libIndexStore.dylib's C API, as `indexstore_functions.h` at
    indexstore-db 64aa0b2 declares it (signatures, role, kind, subkind,
    property and dependency-kind numbers copied here as numbers); the
    library is the one named on the command line, normally the build
    toolchain's `<toolchain>/usr/lib/libIndexStore.dylib`;
  - <describe.json> (`swift package describe --type json` of <root>; its
    `path` must be <root>), for the list of source files only;
  - the file system: realpath(3) and the files' bytes.
Nothing from SwiftStats, its scan JSON or its store.

The output is written whole or not at all: any unit or record that doesn't
read, a callback that fails, or a value that isn't UTF-8 ends the run with
an error naming it, and no partial dump is written.

`build-lines` accounts for every line of a T1 build's output (design
sections 6.1 and 11): the build's stderr (`swiftstats-build.stderr`: timing
lines and diagnostics), its stdout (`swiftstats-build.log`: the -v task
log), or one file holding both (`--combined`, as `2>&1` writes it). Every
line gets exactly one class (the list is ACCOUNTED_CLASSES and
UNACCOUNTED_CLASSES below), the classes must add up to the line count, and
none may be unaccounted:
  - every line holding `ms<TAB>` must be a whole timing entry, read by this
    script's own patterns (tab-separated fields; `<digits>[.<1-2 digits>]ms`;
    `<invalid loc>` or a place split from the right as path:line:column;
    a third field, the declaration, that ends with `@` and the place), or,
    in a combined file only, a line the other stream broke (`spliced`);
  - every line holding `warning:` (and every line holding a severity
    marker) must be a diagnostic (`<path>:<l>:<c>: <severity>: ...`, a
    macro form `macro expansion #name:<l>:<c>:` or `@name`, a place in an
    interface buffer `<Module>.<Type>.<member>:<l>:<c>:`, or `<unknown>:<l>:`),
    a continuation of one, a decorated note (the origin note `` `- ...:
    note: expanded code originates here`` among them), an excerpt line or
    an excerpt's echo of a diagnostic (and the echo's own continuation
    lines), Swift Build's summary form (`warning: <path>:<l>:<c> <text>`,
    no colon after the column), a manifest-command line (`warning:
    '<package>': .../swift-frontend -frontend ...`) or a SwiftPM package
    warning (`warning: '<package>': <text>`);
  - no escape or bell character may be left once ANSI CSI and OSC-8
    sequences are removed (lines that held one are counted).
A diagnostic's message continues on the following lines as far as the last
line that makes it end with a diagnostic ID (the build passes
-debug-diagnostic-names; a quoted source line ending ` [word]` can make it
seem to end earlier), within 20 lines none of which could not continue a
message (blank, excerpt, box, decoration, timing, diagnostic, a
`warning:`/`error:`/`note:`/`remark:`/`info:` line, a group footnote); when
no such line ends it with an ID it has no continuation. Each excerpt echo of the
diagnostic just read must repeat its whole joined message. The stdout log
must hold no timing entry (the reader takes timings from stderr only).
`--json` writes this parse (classes per file, counters, the entries, the
unique diagnostics with joined messages, IDs, groups and macro origins,
the spliced lines); `--compare` reads a reader's parse in that shape
(`counters`, `entries`, `diagnostics`; extra keys ignored) and compares
counters, entries as multisets and diagnostics as sets. An entry a reader
reads from a combined file's broken line (a `head` splice whose place
still reads) is listed as explained, not as a difference.

`build` runs the same accounting over a scanned package's
`.swiftstats/index-build/swiftstats-build.stderr` and `.log` (or the files
named), then reimplements design sections 6.2 and 6.3 and compares the
result with the scan JSON's `build` block and its `swiftc` findings (and,
with `--store`, with the rows of design section 9.1):
  - timing entries classed, first that applies: `synthesized` (`<invalid
    loc>`), `macro` (a file name starting `@__swiftmacro_`), `build` (under
    the build directory), `outsideRoot`, `fileChanged` (a scanned file
    whose bytes no longer have the scan's hash), `unscanned` (in the root,
    not a scanned file), else mapped: placed on the innermost record of any
    role holding (line, UTF-8 column) (latest start, earliest end, key; a
    top-level code record only on its statement lines), except that a
    position that record's innermost local type holds goes to that type
    (a local type's own positions outside its members' records); else the
    innermost type (named `<module>::<type path>`, plus ` @ <file>` when
    file-scoped), else the file;
  - per record, the sum of its function-body entries and its largest
    expression entry, each in hundredths and rounded to whole ms half up
    once, null when it has none; per type or file attachment the same
    (null ms when it has only expressions); the total is the rounded sum
    of function-body entries on records not nested in a body, on types and
    on files. A record is nested in a body when an ancestor of kind func,
    init, deinit, accessor or topLevel is reached through its parent keys
    without passing a type: a type lying inside that ancestor's range and
    holding the record's range. So a local function is nested, and a local
    type's members are not (the step-2b review's rules, as the compiler
    prints them). Nothing is deduplicated;
  - warnings (severity `warning`; a macro form at its origin note, none
    without one) deduplicated on (file, line, column, ID or message);
    places under the build directory or outside the root dropped and
    counted; in a target of type `plugin` counted apart; others findings
    of tool `swiftc`, rule the ID (`unidentified` when none), category the
    group, the message without its bracket suffixes. Which record a
    finding attaches to is the existing FindingMapper's rule and isn't
    rechecked.
The scan's block is read by design section 9.2's names (`records` with
`key`, `milliseconds`, `slowestExpression`; `attachments`; `unmapped`;
`dropped`; `totals`; `unparsedTimingLines`, `escapedLines`,
`otherWarningLines`, `pluginWarnings`); a value it lacks is a failure that
names it. `--own-only` prints this script's figures without comparing.

`build` also recomputes design 6.4's type-check roll-ups from this script's
own placement above and compares them with each roll-up scope of the scan
JSON (`typecheck` in the scope object: `milliseconds.total`,
`milliseconds.max`, `slowestExpression.max`, `functions.timed`) and, with
`--store`, with the snapshot's `rollupMetric` rows named `typecheck.*`
(which must name collector `build`). `--without-typecheck` skips both
(SwiftStats doesn't build these roll-ups yet: until it does, they fail with
"not built yet"). The reading, for the Swift side to match or argue:
  scopes   a module scope per target (`module`, the target name) and the two
           project parts (`project`, `production` and `tests`), as the T0
           roll-ups name them. An entry on a record counts for the record's
           module, and for part production when the record's role is
           production, else tests (test and helper records: the T0 roll-ups'
           split by role). An entry attached to a type or a file counts for
           that type's or file's module, and for part tests when that
           module's target is a test target (`isTest`), else production.
           Every scope the scan's roll-ups list gets figures, also one with no
           entry at all.
  total    `typecheck.milliseconds.total`: the function-body entries placed
           on records not nested in a body, on types and on files (the same
           entries as the build block's total: design 6.2's "Totals don't
           double count"), summed in integer hundredths of a millisecond over
           the scope, then rounded to whole ms half up ((sum + 50) // 100)
           once per scope. Design 6.2 rounds "once, after summing" and says
           the roll-up sums add entries, so entries are summed, not the
           per-record rounded figures; a scope's total therefore need not
           equal the sum of its records' `typeCheckMilliseconds`, and the two
           parts' totals can differ from the build block's total by rounding.
           0 when the scope holds no such entry.
  maxima   `typecheck.milliseconds.max`: the largest `typeCheckMilliseconds`
           (the rounded per-record figure) over every record of the scope,
           nested ones included ("Maxima ... take every record");
           `typecheck.slowestExpression.max` the largest per-record slowest
           expression likewise. Records only: type and file attachments are
           not records and are left out (their largest figures are printed).
           Absent when no record of the scope has such a figure (a null
           roll-up, as a record's null figures; never 0).
  timed    `typecheck.functions.timed`: the records of the scope with a
           `typeCheckMilliseconds` (at least one function-body entry), nested
           ones included; a record with only expression entries isn't timed.
           0 when none.
Any other `typecheck.*` name in the scan JSON fails.

Inputs `build-lines` trusts: the output files' bytes, nothing else.
Inputs `build` trusts, besides those:
  - the scan JSON's `records` (`key`, `file`, `kind`, `range`, `parentKey`,
    `module`), `types` (`module`, `name`, `kind`, `range`, `isLocal`,
    `file`), `files` (`path`, `sha256`, `module`) and `targets` (`name`,
    `path`, `type`, `files`), as T0 wrote them;
  - the package's sources on disk (top-level statement lines and
    file-scoped types, read by the small tokenizer copied from
    Scripts/coverage-check.py; and the files' current hashes, since the
    check runs right after the scan);
  - realpath(3) of the package and its build directory, which the
    compiler's absolute real paths start with (`--root-spelling` and
    `--build-spelling` name other spellings, such as a recording's `@ROOT@`
    and `@BUILD@`), and of each scanned file (the root joined with its
    `files` path): a compiler path that resolves to a scanned file's real
    path is that file, so a target directory or file reached through a
    link, or spelled in another case than the disk, maps to the scan's
    spelling; else one that resolves to the real path of another source
    of the describe (a file the scan excludes) is that source, as the
    manifest spells it; any other path under the root is made relative as
    printed, then resolved;
  - its own `swift package --scratch-path <tmp> describe --type json` of
    the package by the package toolchain's swift (as `usr`), or
    `--describe`: each target's `path` and `sources`, nothing else;
  - with `--store`, the store's tables as design section 9.1 names them.
Not the scan JSON's `build` block, findings or roll-ups, which it checks.

`usr` reimplements design sections 2.3 and 3 (the unit filter, the USR join,
the reasons and the lists) over this script's own read of the store, and
compares the result with the scan JSON's `index` block (design 9.2) and the
`index.*` roll-ups (checks u1 to u6 of design section 11; u0 is
`IndexStoreReaderLiveTests` against `dump`'s output):
  u1  units: every unit of `<build>/out` and of
      `<build>/swiftstats-quarantined-units/` (read through a temporary
      store view holding those unit files and the store's records) gets a
      class, first that applies: `system`; `otherPackage` (no main file, or
      one outside the root, under the build directory, under a first path
      component `.build` or `.swiftstats`, or in a local path dependency's
      folder: step 4a's adopted deviation; a main file outside the root
      that is a source's real path isn't outside it); `otherModule` (its
      module is no target's C99 name in this script's own describe); `stale`
      (main file missing, or not a source of the target its module names,
      compared as real paths, so a source reached through a link or spelled
      in another case than the disk matches; a unit's main file and its
      records' files then read as the describe spells the source);
      `duplicate`
      (an older unit of the same module, main file and triple: full-precision
      date, then the larger unit name, kept); `variant` (every unit of a
      module and main file read with more than one triple); else `kept`. The
      scan's unit list (name, target, main file, triple, class) must equal
      these for every unit it lists, list every kept and variant unit, and
      list every unit of a class it lists any of (design 2.3 lists kept and
      variant units, 9.1 also duplicate, stale and otherModule ones); the
      counts per class and quarantined must equal; no stale or otherModule
      unit may remain in `out/v5/units`, and the quarantine must hold
      exactly this script's stale and otherModule units and the scan's;
  u2  every record's primary USR and secondary accessor USR, from the
      records of kept and variant units (each record once, its occurrences
      filed under the file each unit's record dependency names): a
      non-implicit function-like definition (a function or method kind, a
      constructor, a destructor, a property kind of subkind subscript) in a
      scanned file whose bytes still have the scan's hash goes to the
      innermost record holding its (line, UTF-8 column) (latest start,
      earliest end, key) when design 3.2's kind table allows it (an accessor
      record takes a function or method kind of its accessor's subkind,
      1016 for `init`; the function kind is allowed for global and local
      computed variables' accessors); a getter whose innermost record is a
      subscript record with no accessor records of its own (children of kind
      accessor named `subscript`; a local computed property's getter in its
      body doesn't count), whose accessorOf relation
      names that record's primary USR, becomes its secondary USR; a record
      with several USRs, or a USR on several records, keeps none. The
      definition counts compared: joined (distinct definitions assigned,
      primary before disagreements are removed, or secondary), implicit
      (implicit function-like definitions in those files), secondary and
      objc (records with a `c:` primary USR);
  u3  the source bytes at each joined definition begin with its name token:
      the base name (or it in backticks), `init`, `deinit`, `subscript`, the
      accessor keyword, the operator, or `{` for a shorthand getter (a
      keyword or name must end there);
  u4  the reason of every record without a primary USR, first that applies
      (design 3.4): top-level code; plugin target; inactive #if branch (an
      `ifConfig`, the file a read unit's main file under the record's
      module, and no definition of any kind, implicit included, in its
      range; so a file no unit read reads target not built or file not
      indexed); file changed during the scan; target not built (no unit of any
      class names the target's module and the build's -v log holds no
      `-module-name <module>`); file not indexed (the target has kept or
      variant units, none for the file); disagreement; unexplained. Target
      not built, file not indexed, file changed, disagreement and
      unexplained must be 0 (criterion 1), whatever the scan says;
  u5  the disagreements (severalUSRs and sharedUSR rows: kind, key, USR, and
      the definition's place when the scan gives one), the definitions with
      no record (requirement when no record holds it and a childOf relation
      names a protocol, or a childOf or accessorOf relation names a property
      or subscript that the same file defines as a child of a protocol: a
      property or subscript requirement's getter or setter; incompatibleKind
      naming the innermost record, outsideRecords) and the collisions the
      USR separates (records whose keys a collision suffix tells apart, as
      the scan's warnings name the collided keys, with differing USRs) equal
      the scan's; incompatibleKind and outsideRecords must be 0;
  u6  `swift demangle --tree-only` of `$s` + each `s:` USR (primary and
      secondary) agrees with its record's key: type path (T0's `typePath`
      when the record has one, else the type part of the key's last
      segment; local types start the path; a sugared component of the key
      reads as the type it names, `[T]` Array, `[K: V]` Dictionary, `T?`
      and `T!` Optional, as in SIP's `extension [OracleDiscoverBead]`),
      base name, argument labels (operands counted only, for operators)
      and accessor kind (the secondary one a subscript getter). `c:` USRs
      are skipped and counted.
Also compared: `index.files` (every scanned file, each hash the file's bytes
now), the records read and occurrences when the scan gives them,
`libraryModules` when present, and each roll-up scope's `index.withUSR`,
`index.withoutUSR.<reason>` and `index.disagreements` (records whose reason
is disagreement), with the T0 scopes (module by the record's module;
project production by role production, tests by the other roles). The
roll-ups' collector attribution isn't in the JSON and isn't checked.
The scan's block is read by design 9.2's names with a few alternative
spellings (reasons compared case- and punctuation-blind); a value it lacks
is a failure that names it. `--own-only` prints this script's figures and
the checks that need no scan block (u3, u4's zeros, u5's zeros, u6).
`--reader` reads a recorded `dump` JSON instead of the store (the Index
fixture's `reader.json`, its paths restored with `--root-spelling`,
`--build-spelling` and `--spelling`); system units and the quarantine are
then not checked.

`usr` also reimplements design section 4 (check u7) over the same read and
compares it with the index block's `records` (`witness`, `references`),
`moduleEdges`, `types`, `familyReferences` and `familyTypeReferences` and the
roll-ups `index.typeCycles`, `index.typesInCycles` and `index.moduleEdges`
(`--without-u7` skips it):
  u7  references: occurrences with the reference role, implicit included,
      in scanned files whose bytes still have the scan's hash, each distinct
      occurrence once. A reference's container, first that applies: the
      symbol of its calledBy relation, else of its containedBy relation;
      else of its baseOf or extendedBy relation; else by position: the
      file's top-level code record on one of its statement lines, else the
      innermost record of any role holding (line, UTF-8 column), else the
      innermost type record, else the file. A container symbol that is a
      record's primary or secondary USR is that record; any other symbol
      stays a symbol, in the referencing file's target. A local variable
      named as container stays a symbol (design 4.1 as written;
      `--local-containers enclosing` follows its definition's childOf
      chain to the enclosing declaration instead). A reference to a USR
      counts for the record holding it as primary or secondary USR, and for
      the accessor records whose definition's accessorOf names it, by role:
      read for get, _read/read and unsafeAddress, write for set,
      _modify/modify, unsafeMutableAddress, willSet and didSet, neither
      role for all of them (both roles: both sets); a reference to a
      protocol requirement (a USR some occurrence's overrideOf names, whose
      package definition's childOf is a protocol, or whose `swift demangle
      --tree-only` context is a protocol, or a `c:` USR with `(pl)`) also
      counts, the same two ways, for each symbol of an occurrence carrying
      that overrideOf relation, via `requirement` (`--requirements package`
      keeps only requirements of protocols the package declares,
      `--requirements all` takes every overridden USR, class methods too).
      It doesn't count when the container is a record of the target
      record's own family (PRD 6.6 families: a record and its nested
      records, or a computed property's accessors, as FamilyIndex groups
      them). Per record with a primary USR: distinct counted containers in
      a test target (`tests`), in the record's own target (`sameModule`),
      in another non-test target (`otherModules`), and `testReferrers`: the
      test containers' names (record keys, symbol names, a type record's
      name, a path), sorted, the first five, one per container. Null for a
      record without a primary USR (zeros or false are accepted and
      counted). `witness`: the record's primary or secondary USR, or an
      accessor's accessorOf property, is the symbol of an occurrence (any
      role, implicit included) that has an overrideOf relation.
      Module edges: `package` edges from a target to another package target
      with `references` (distinct (file, line, column, USR, roles) of
      references in the first whose USR has a definition, any kind, in a
      read unit of the second) and `files` (distinct main files of the
      first's kept and variant units whose non-system unit dependencies
      name the second's C99 module), present when either is non-zero;
      `dependency` edges to a non-system module that is no package target
      (its C99 name), `references` null, `files` as above.
      Types: definitions (not implicit) of struct, class, enum and protocol
      symbols in read units, in scanned unchanged files, placed on the
      innermost type record holding them when its kind is compatible (actor
      with class); identity (module, typePath, typeFile), typeFile the file
      for a private or fileprivate type (or one nested in one, or in a
      private extension), '' otherwise, local types included. Ownership: a
      package type owns itself; an extension is owned by the package type
      its head reference (the occurrence carrying an extendedBy relation
      naming it) names, by none for an external type; any other symbol by
      what its definition's childOf chain reaches first. A container's
      owner: its record's USR's (a record without one: the innermost type
      record holding it), its symbol's, or the type record's. Per
      production type (not in a test target): its USR; `tests` distinct
      test containers referencing it or a member (a USR it owns);
      `sameModule`/`otherModules` distinct referring types (the container's
      owner) or, without an owner, containers, outside test targets, by
      whether the container's target is the type's, the type itself left
      out. Cycles: an edge A -> B when a container outside test targets
      owned by production type A references production type B or a member,
      A != B, neither nested in the other (same module, the inner typePath
      the outer's plus `.`, the outer's typeFile '' or the inner's: a
      private type nested in a plain one is file-scoped alone); Tarjan's
      strongly connected components of two or more, numbered from 1 by
      size, largest first, then by their first member's identity (a scan numbering them smallest first is named in
      the output; membership is compared apart).
      Family references: (from, to, via) for counted references whose
      container record's family and target record's family are both
      production families (every member's role production) and differ, via
      `direct` or `requirement` as above. Family-type references: (family,
      module, typePath, typeFile) for every reference (family exclusion not
      applied) from a record of a production family to a package type or a
      member of it.
      Roll-ups, as this check reads them: a module scope counts the cycles
      with a member there, its types in cycles and the edges from it;
      project production all cycles, all types in cycles and the edges from
      non-test targets; project tests no cycles and the edges from test
      targets.
  Also checked: the index collector's options hold `references:` and
  `types:` (text differing from design 4's is printed, not failed).
  Failed: a package type definition no compatible type record holds.
  Printed, not failed: the reading in force, how many references a local
  container, a requirement of a protocol the package doesn't declare, or a
  position decided, and identities several types share (a design gap:
  local types of one name).

`usr` with `--store` also runs check u8 (plan step 7a; made whole by the
`rows` mode below, which `usr --store` runs in full) on --snapshot (the
newest by default), whether or not `--own-only` is given:
  u8  the stored rows equal the scan JSON (design 9.1 and 9.2): the
      `function` columns usr, usrAccessor, usrReason (the record's
      `reason`), witness (0 or 1), referrersSameModule, referrersOtherModules,
      referrersTests and testReferrers (a JSON array as text) of each record
      the index block lists, and null on every other row of the snapshot
      (null, never 0, for what wasn't collected); one `indexScan` row
      (collectedAt the snapshot's date, or the date a `carried from the scan
      of <date>` reason of the index collector names; layout, libraryModules
      as a JSON array, the unit counts per class and quarantined, records,
      occurrences and the four definition counts); `indexUnit`, `indexFile`,
      `moduleEdge`, `typeIndex` (typeFile '' when the JSON has none),
      `familyReference` and `familyTypeReference` rows equal their lists as
      multisets; `usrDisagreement` rows (kind, subreason, usr, key,
      symbolKind, name, file, line, column) equal the `disagreements`,
      `withoutRecord` and `collisions` lists together as a multiset, their
      ordinals counting up from 0 or 1 with no gap (whether the ordinals
      follow the lists' order is printed, not failed); with no index block,
      none of those tables holds a row of the snapshot. `couplingPair` rows,
      written with the history whether or not the index ran (design 9.1),
      by ordinal (from 0 or 1, no gap) equal the scan's `history.coupling`
      in order, none when it has none. Printed, not failed: columns whose
      nullability differs from design 9.1's NULL marks. The build and dead
      code rows, the timing columns, the swiftc findings, the M7 roll-up
      rows and the T1 collector rows are the `rows` mode's part of u8 below
      (`build --store` and `dead --store` check the same tables against
      this script's own figures instead).

`rows <scan.json> --store <store>` runs check u8 whole (design 11 step 2:
"the stored rows equal the scan JSON"): for --snapshot (the newest by
default), the snapshot the scan JSON came from, every M7 row equals the scan
JSON, row for row, nulls as nulls (the scan JSON leaves a null out: an
absent key is null). It needs no package, build output or index store: only
the two files. Each difference is listed with its table, row and column.
  index    everything `usr --store`'s u8 above lists (the `function` index
           columns, indexScan, indexUnit, indexFile, usrDisagreement,
           moduleEdge, typeIndex, familyReference, familyTypeReference,
           couplingPair);
  snapshot `snapshot.reportSchemaVersion` is the scan JSON's `schemaVersion`;
  build    one `buildScan` row (none without a `build` block): collectedAt
           the snapshot's date or the date a `carried from the scan of
           <date>` reason of the build collector names, then each column at
           its place in the block: complete (0 or 1), totals.functionEntries,
           .expressionEntries, .milliseconds (totalMilliseconds),
           unmapped.synthesized and .macro (entries, milliseconds),
           dropped.build, .outsideRoot, .fileChanged, .unscanned (entries,
           milliseconds), changedFiles, unparsedTimingLines, escapedLines,
           otherWarningLines, warningsDropped, warningsUnmapped,
           pluginWarnings; a store column this list doesn't place fails, and
           design 9.1's columns the store spells otherwise (`droppedEntries`,
           split per class) are printed. `timingAttachment` rows (owner,
           attachedTo, milliseconds, slowestExpressionMilliseconds) equal the
           block's `attachments` (owner, attachedTo, milliseconds,
           slowestExpression) as multisets, by field name (which of the two
           holds `type`/`file` is printed: design 9.1's comment puts it in
           owner). `function.typeCheckMilliseconds` and
           `slowestExpressionMilliseconds` equal the block's `records`
           (milliseconds, slowestExpression) per key, and are null on every
           other row of the snapshot. `finding` rows of tool `swiftc` (rule,
           kind, severity, message, file, line, column, attachedTo, owner)
           equal the scan's `findings` of tool swiftc, one row per location,
           as multisets (the JSON's `category` has no column: printed);
  dead     one `deadScan` row (none without a `deadCode` block): collectedAt
           (as for build, the periphery collector's reason), version, and
           rootsResults and productionResults from `runs`. `deadDeclaration`
           rows by (run, ordinal) equal the block's `declarations`, column by
           column (hint, hintText, kind, name, accessibility, attributes,
           modifiers, ids, modules, class, file, line, column, place, owner,
           module, strippedLines; the four array columns read back from their
           JSON text), each run's ordinals from 0 or 1 with no gap.
           `deadRecord` rows (run, key, declaration, via) equal `records` as
           multisets. The store's `deadLines` table (run, module, lines; not
           in design 9.1) equals `deadLines` ({run: {module: lines}});
  rollups  `rollupMetric` rows whose metric is an M7 name (`index.*`,
           `deadCode.*`, `tests.lineRatio.deadLines`, `findings.swiftc.*`,
           `findingKinds.swiftc.*`, `typecheck.*`) equal, as multisets of
           (scope, name, metric, collector, value), every numeric leaf under
           those names in the scan JSON's roll-up scopes (metric = the dotted
           path in the scope object; booleans and nulls have no row), with
           the collector design attributes: index for `index.*` (design 4),
           periphery for `deadCode.*` and `tests.lineRatio.deadLines`
           (design 7), build for tool swiftc's findings (design 6.3) and for
           `typecheck.*` (design 6.4's figures come from the build
           collector; the design names no other);
  runs     the `collectorRun` rows of build, index and periphery: state,
           reason, version and options (stored as a JSON array) equal the scan
           JSON's collector entries; no row for a collector the JSON doesn't
           list.
Not compared, with the reason: `collectorRun`'s identity, identityLabel and
durationMilliseconds (the scan JSON's collector entries don't hold them;
`dead --store` checks periphery's identity against the binary); the `report`
blob (SwiftStats' own copy of the report, not one of design 9.1's row
models); design 9.1's two INDEXes (not rows: the indexes present are
printed). The output ends with this list of design 9.1's tables, each marked
compared or not.

Inputs `rows` trusts: the scan JSON as what the rows must equal (it checks
nothing in it but its consistency with the rows), and the store, opened
read-only, by the table and column names of the store's migrations.

Inputs `usr` trusts:
  - libIndexStore.dylib's C API (as for `dump`), the library being the
    package toolchain's (`swift -print-target-info` in the package:
    `<runtimeResourcePath>/../libIndexStore.dylib`), or `--library`;
  - its own `swift package --scratch-path <tmp> describe --type json` run in
    the package by that toolchain's swift (Package.resolved's bytes or
    absence put back afterwards), or `--describe`: target names, C99 names
    (computed when absent), paths, sources, types, library products, path
    dependencies;
  - the scan JSON's `records` (`key`, `file`, `kind`, `name`,
    `accessorKind`, `range`, `parentKey`, `module`, `ifConfig`, `role`,
    `typePath`; `name` only to tell a subscript's explicit accessors,
    named `subscript`, from other accessor records nested in it),
    `files` (`path`, `sha256`), `targets` (`name`, `type`) and `warnings`
    (the collided keys), and the T0 roll-up scopes, as T0 wrote them;
  - the package's sources on disk (bytes for u3; hashes now, since the check
    runs right after the scan);
  - `<build>/swiftstats-build.log` (or `--log`) for the `-module-name`
    evidence of `target not built`;
  - the toolchain's `swift-demangle` (or `--demangle`), also for u7's
    protocol-requirement test;
  - for u7: the scan JSON's `types` (`module`, `name`, `kind`, `range`,
    `isLocal`, `file`) and records' `role` and `accessorKind` as T0 wrote
    them, and the sources' top-level statement lines and private or
    fileprivate types, read by the small tokenizer copied from
    Scripts/coverage-check.py.
  - for u8: the scan JSON's `index` block, `records` (`key`), `history`
    (`coupling`) and the index collector's reason, as what the rows must
    equal, and the store's tables as design section 9.1 names them, opened
    read-only.
Not the scan JSON's `index` block or `index.*` roll-ups, which it checks
(u1 to u7; u8 takes the block as given and checks the rows against it).

`dead` (its run part, plan step 6a) runs outskirts itself, twice, with the
command line built from design section 5.2's words, not from SwiftStats'
options, and compares its sorted output with what the periphery collector
kept and stored (design sections 5.1 to 5.3, 9.1, 9.2 and 11):
  run      each run in the package root, stdin /dev/null, every flag its own
           argv element:
             <outskirts> scan --format json --disable-update-check
               --config <an empty file of its own>
               --index-store-path <build>/out --skip-build
               --index-exclude <build>/**
               --json-package-manifest-path <its own describe JSON>
               [--retain-public-modules <C99 module> ...]
               --retain-codable-properties --retain-equatable-properties
               [--exclude-tests]
           `roots` without --exclude-tests, `production` with it; <build>
           the real path of <package>/.swiftstats/index-build. The retained
           modules are the C99 names of the targets the describe's library
           products list that have at least one unit of class kept or
           variant in the store (this script's design 2.3 filter, as `usr`
           u1 classes units), in byte order, the flag left out when there
           are none. Each run must exit 0 and its stderr must not hold
           outskirts' "retain_public_modules lists modules that are not
           scanned" warning; it must leave the package's `git status
           --porcelain --ignored`, its `.build` (absent or present), its
           Package.resolved bytes and the names in its root as they were;
  format   each run's stdout is a JSON array whose every entry holds the
           nine keys accessibility, attributes, hints, ids, kind, location,
           modifiers, modules and name (extra keys allowed), `hints` holding
           one string and `location` reading, from the right, as
           <path>:<line>:<column> with 1-based numbers;
  kept     each run's entries, sorted by their canonical JSON text, equal
           the entries of the file the collector kept for it
           (<build>/swiftstats-outskirts-roots.json and
           swiftstats-outskirts-production.json, or --roots-file and
           --production-file), compared as multisets; whether the bytes are
           also identical is printed, not failed;
  stored   when the scan JSON has a `deadCode` block, its `runs` (name,
           results) equal each run's entry count and its `declarations`
           equal this script's decoding of each run's entries as multisets
           of (run, hint, hintText, kind, name, accessibility, attributes,
           modifiers, ids, modules, file, line, column): a hint `name(text)`
           read as hint `name` and hintText `text` (a stored hintText
           repeating the whole hint is accepted as the same), ids, modules,
           attributes and modifiers as lists, modules translated from C99
           to target names through the describe, file the scan's spelling
           of the scanned file whose real path the location resolves to,
           else the describe's spelling of its other source whose real path
           it resolves to (a source the scan didn't parse; in the target of
           the first module either way), else the package-relative NFC
           real path (null outside the root; any path under the build
           directory compared as one value); and when the declarations carry ordinals, ordinal k
           (from 0 or 1, contiguous) is the run's k-th entry in outskirts'
           order. With --store the same holds for the `deadScan` and
           `deadDeclaration` rows (JSON arrays as text) of --snapshot (the
           newest by default), and the collectorRun row of `periphery`
           holds identity `sha256:` + the SHA-256 of the outskirts binary
           (symlinks resolved), version `outskirts version`'s output, and a
           label that, when given, is `git:<HEAD of the clean tree whose
           .build holds the binary>` followed by ` (<tag>)` when `git
           describe --exact-match --tags` names one (an absent label is
           printed, not failed: the mtime rule that withholds it isn't
           rechecked). Absent blocks and tables (step 6a stores no
           deadCode block yet) are printed as not compared, not failed;
  status   the scan's `periphery` collector ran; its version is `outskirts
           version`'s output, and its reason holds "isn't the version
           SwiftStats was checked against (3.28.0)" exactly when that output
           isn't 3.28.0; its options hold a `retain-public-modules:` line
           naming this script's retained modules by target name, sorted (or
           `none`), and the outskirts command lines among its options name
           the same flags as this script's runs (placeholder spellings of
           paths aren't compared); <build>/swiftstats-outskirts.yml exists
           and is empty, and <build>/swiftstats-describe.json describes the
           package (a difference from this script's own describe is printed,
           not failed: the runs' outputs are what is compared).
Printed, not failed: each run's time, its results by hint and by kind, the
entries in test targets (all modules test targets, or a file among a test
target's sources), under the build directory, outside the root, and whose
file doesn't exist. `--own-only` runs outskirts and prints this script's
figures without comparing; `--output-dir` keeps each run's stdout and
stderr; `--use-scan-inputs` passes the collector's own empty config and
describe JSON instead of this script's (to tell an input difference from an
output one).

Inputs `dead` (run part) trusts:
  - the outskirts binary named on the command line, run in place;
  - its own `swift package --scratch-path <tmp> describe --type json` of the
    package by the package toolchain's swift (as `usr`), or `--describe`:
    target names, C99 names, types, sources and library products;
  - the index store at <build>/out read through libIndexStore's C API (as
    `usr`), for which library-product targets have kept or variant units;
  - realpath(3), git (`status`, `rev-parse`, `describe`) and the file
    system;
  - the scan JSON's `files` (`path`, `module`), whose real paths come
    before the describe's sources' when an entry's location is spelled
    (and whose `module` classes a scanned file `test`);
  - the scan JSON's `collectors` entry for `periphery` only as the thing
    checked, and its `deadCode` block and the store's rows likewise.
Nothing from SwiftStats' code.

`dead`'s mapping part (plan step 6b) reimplements design sections 5.3 and
5.4 over the same two runs' entries, in outskirts' order (ordinal k = the
k-th entry, counted from the scan's lowest declaration ordinal, 0 or 1,
else 1), and design 7's ratio fields, and compares them with the scan
JSON's `deadCode` block (design 9.2), its roll-ups and, with --store, the
`deadDeclaration` and `deadRecord` rows (design 9.1):
  classes  every entry of both runs, first that applies: `build` (under
           <build>); `outsideRoot`; `test` (its file is among the scan's
           files and the scan's `module` for it is a test target; a file
           not among them is `test` when it lies under a test target's
           directory as the describe spells it or every `modules` entry is
           a test target); `unscanned` (in the root, not among the scan's files);
           `fileChanged` (a scanned file whose bytes no longer have the
           scan's hash: the check runs right after the scan); `local`;
           else `production`. `local` (the default `--local-rule plan`,
           step 6a's adopted reading): a variable kind (`var.*`) other than
           `var.parameter` whose `ids` hold a USR some definition in a read
           unit has with the `local` property (only when the index is
           used), or that lies inside a record (any role) other than
           top-level code. `--local-rule literal` reads design 5.3 word for
           word instead: the index rule for any kind (it then drops unused
           local functions, which design 13's 6b tests map) and the position
           rule for every variable kind, parameters included. Each
           declaration's class is compared by ordinal (as a multiset with
           the decoded fields when no ordinals are given), and the dropped
           counts per class and run (every class but production);
  mapping  each production entry (every hint, design 5.4's words; `--map-
           hints unused` maps only hint unused) covers records, first rule
           that applies:
             usr       (index used) an `ids` USR is a record's primary or
                       secondary USR (my own u2 join) -> those records;
             property  (index used) a `var.*` entry whose `ids` USR some
                       accessor record's definition names through accessorOf
                       -> those accessor records (every accessor kind);
             type      class, struct, enum or protocol: with the index the
                       package type (u7's placement) whose USR is an `ids`
                       entry, without it the innermost type record of a
                       compatible kind (class with class or actor) holding
                       (line, UTF-8 column) -> every function record (all but
                       top-level code) whose owning type is that type or a
                       type nested in it, in any file: by u7's ownership of
                       the record's primary USR with the index (a record
                       without one falls back to the next rule's T0 reading),
                       else by T0: same target, typePath equal or the type's
                       path plus `.`, and the type's typeFile '' or the
                       record's (typeFile: the file when the path is private
                       or fileprivate there, by the tokenizer copied from
                       Scripts/coverage-check.py). The type's extension
                       records: with the index those whose extension u7's
                       ownership gives the type, without it extension records
                       of the same target naming the type's path (in its file
                       for a file-scoped type);
             extension extension.* kinds -> the innermost extension type
                       record holding the position -> every function record
                       of that file whose range lies in its range;
             location  a function.* entry when the index isn't used -> the
                       innermost record holding the position whose kind
                       design 3.2's table allows for outskirts' kind
                       (function.free/method/operator: func; constructor:
                       init; destructor: deinit; subscript: subscript;
                       function.accessor.*: the accessor of that kind). With
                       the index used, a function entry whose USRs match no
                       record covers nothing (the "function entries matching
                       no record" of design 8.2's funnel) and is noted;
             none      anything else (parameters, imports, enum elements,
                       stored properties, typealiases, ...).
           deadRecord rows: each covered record once per run, with the
           lower ordinal's entry and its via; compared as sets of (run, key,
           declaration ordinal, via), and every via must be one of the five
           names. A record is dead in a run when a production entry with
           hint unused covers it;
  lines    the covered units of a run (production entries with hint unused):
           type entries (the type record and its extension records),
           extension entries (the extension record) and every function
           record those entries cover. A unit is maximal unless another
           holds it: a function record below a covered record by parentKey,
           a nested type (design 4.3's identity nesting) or the type's own
           extension record inside a covered type, or a unit whose range
           lies in a covered type's type or extension record range, or in a
           covered extension's or record's range, in the same file. Dead
           lines per module = the strippedLines of the maximal units' parts
           (a type record's and each extension record's lines to its own
           target). Compared per module and run; a self-check recomputes
           them, and the deadRecord rows, over the entries reversed and
           shuffled;
  ratio    every roll-up's `tests.lineRatio`: `deadCodeExcluded` true exactly
           when the scan's periphery collector ran, and `deadLines` the
           roots run's dead lines of the production modules the ratio
           measures against (LineRatio's doc comment: a production module's
           own; a test target's production dependencies; the project's
           every production target; this reading is printed when its
           production lines differ from the scan's `productionLines`), absent
           or null when periphery didn't run;
  options  the periphery collector's options hold one `classes:` and one
           `map:` rule (design 1.8; text other than design 5.3's and 5.4's
           rule strings is printed, not failed);
  rollups  in each roll-up's `deadCode` block, where present (keys printed):
           `records` (records dead in the roots run) and `productionRecords`
           (production-dead records), by the record's module, project scopes
           by role production or not; `unsized` (unused production entries
           of the roots run with no line count: no record, type or extension
           covered) and `unused` (those entries by design 10.1's kind:
           function, type, extension, property, enumCase, parameter, import,
           other), by the entry file's module.
Printed, not failed: each entry's class, rule, covered records and line
count, the units (maximal or held), the notes (entries that cover nothing,
records judged by the T0 fallback), and each declaration's `place` and
`owner` (the innermost record holding its position, else the innermost type
record, named `<module>::<type path>` plus ` @ <file>` when file-scoped,
else the file) and `strippedLines` against the scan's, since design 5.4
lists them for listing only. `--index-mode auto` (the default) uses the
index exactly when the scan's index collector ran; `index` and `position`
force either; `--without-mapping` runs the run part alone.

Inputs `dead` (mapping part) trusts, besides the run part's:
  - with the index, this script's own read of the store and `usr`'s join
    (u2) and type placement and ownership (u7: childOf chains, extendedBy
    heads, accessorOf relations, local properties), as checked in plan
    steps 5a and 5b;
  - the scan JSON's `records` (`key`, `file`, `kind`, `accessorKind`,
    `range`, `parentKey`, `module`, `role`, `typePath`, `strippedLines`),
    `types` (`module`, `name`, `kind`, `range`, `isLocal`, `file`,
    `strippedLines`), `files` (`path`, `sha256`, `module`, `strippedLines`),
    `targets` (`name`, `isTest`, `dependencies`), the `index` collector's
    state and the roll-ups' scopes and `productionLines`, as T0 and the
    index collector wrote them;
  - the package's sources on disk (private and fileprivate types, by the
    tokenizer copied from Scripts/coverage-check.py; current hashes);
  - LineRatio's doc comment (Model/LineRatio.swift, before M7) for the
    ratio's scopes.
Not the scan JSON's `deadCode` block, `deadLines`, `deadCodeExcluded` or
`deadCode.*` roll-ups, which it checks.

`signals` re-derives M7's signals (design section 8; criterion 4 of section
11 step 3) from a store's rows by the rules, and compares them with
`swiftstats report --format json` of that snapshot (the snapshot the report
names, by package, path, commit and dirtiness; `--snapshot` names another,
the newest without a report). Plan step 9a writes its test-only part and
the groundwork the three signals share, 9b its dead-but-tested part, 9c its
hidden-coupling part:
  t  thresholds: the report's `thresholds.limits` lists `hidden-coupling`
     with exactly the limits this check uses (support 3 and confidence 50
     unless `--config`'s `signals.hidden-coupling` or `--set` say otherwise;
     a key other than support or confidence, a support that isn't a whole
     number from 1 to 1,000,000 or a confidence outside 0 to 100 is bad
     input here, as SwiftStats must refuse it), and no limits for
     dead-but-tested or test-only-production (they take none). The report
     schema is printed (5 before plan step 10 bumps it to 6), not failed.
  n  names: the report's last three signals are hidden-coupling,
     dead-but-tested and test-only-production, in that order, each once,
     right after uneven-clone-mutation.
  h  hidden coupling (design 8.1; plan step 9c):
     pairs: the snapshot's `couplingPair` rows (M3's pairs, written with
     history from M7 on), in ordinal order; they must equal the stored
     scan's `history.coupling` pairs in order (design 9.1: the blob keeps
     them too), when both exist.
     left out, first that applies: history missing (no `historyRun` row),
     worded as M3's signals word it: `history was not collected
     (the snapshot predates M3)` without a history collectorRun row, else
     `history was not collected: <state>[, <reason>]`; then as for o: `the
     snapshot predates M7`, `needs index: <state>[, <reason>]`, `the
     snapshot holds no index rows`. A left-out signal lists nothing, has 0
     candidates and states design 8.1's rule text with the limits in force
     (the funnel optional).
     families (PRD 6.6), from every `function` row (any role): a record
     joins the family of its topmost ancestor by `parentKey` (a missing or
     circular parent ends the climb); the family is named by that root's
     key, or, when the topmost record is a computed property's accessor
     (kind accessor, no parent), by the accessor's key without its
     ` { <accessor> }` part, grouping the property's accessors in one file.
     A pair's family is the one with its key (in the pair's file when
     several share it; `--family-match key-and-file` also requires the
     file).
     each pair, first that applies: U a family not found; G a family with
     a member whose file is generated; T a family whose root (or first
     member) isn't of role production; else P. Of P: W a family with no
     member holding a primary USR (`usr`; a secondary `usrAccessor` alone
     doesn't count, printed); else K judged, then, first that holds: R a
     `familyReference` with via direct, either way; Q one with via
     requirement, either way; Y both roots' owning types known and equal,
     or one nested in the other (same target and type file, one type path
     the other's followed by `.`); X a `familyTypeReference` from one
     family to the other root's owning type (module, typePath, typeFile);
     else C, which is L listed when support >= the support limit and
     support * 100 >= confidence * min(changesA, changesB) (exact
     arithmetic), else B. A root's owning type (design 4.3: package-declared
     types only): none for a root without a typePath (free functions, local
     functions); else, by default (`--owners package`, design 4.3: an
     extension's members belong to the package type its head extends, which
     the USR's context names), for a root whose `usr` is a Swift one (`s:`)
     the `typeIndex` type whose `usr` is the longest proper prefix of it
     (none when no type's is: extensions of types the package doesn't
     declare, such as `Array` or another module's type of a name a target
     declares too); for any other root the `typeIndex` type at its (module,
     typePath, typeFile or ''), else none. `--owners own-module` takes the
     latter for every root (printed difference only).
     The rule: design 8.1's text with the support and confidence limits
     (numbers compared by value), then "; " and the funnel in its words
     (`N pairs = U with a family not in this snapshot + G ... + T ... + P
     with both families in production code; P = K judged + W ...; K = R
     referencing each other + Q ... + Y ... + X ... + C without a static
     dependency; C = L listed + B below the limits`), every number equal to
     this check's and adding up as stated, then `; pairs exist only at or
     above history.coupling.min_support (<m>)` exactly when the support
     limit is below m, where m is the configuration's
     `history.coupling.min_support` (default 3) or the history run's stored
     option `coupling.min_support` (either reading is accepted; which one
     is printed); other text after the funnel is printed. `candidates` is N, P, K or C
     (the design names none for this signal), and which is printed.
     items: the L pairs, ordered by support descending, confidence
     (support / min(changesA, changesB), exact) descending, then subject
     (familyA), file (fileA), line, partner (familyB) and partner file
     (fileB); each with rank (from 1), member true, score = support, line
     = the root's start line (for a computed property's family, its first
     accessor by key then line; the lowest member line or `familyHistory`'s
     line are accepted and printed), and the payload `coupling` exactly:
     {partner, partnerFile, support, changesA, changesB, confidence
     {support, smaller = min(changesA, changesB)}, modules [A's, B's
     module], sameFile (fileA == fileB), sameModule}; no other payload.
  o  test-only production code (design 8.3):
     left out, first that applies: `the snapshot predates M7` (the
     snapshot's reportSchemaVersion below 9, or no collectorRun row for
     `index`, whatever its state); `needs index: <state>[, <reason>]` (a
     carried run reads `ran`); `the snapshot holds no index rows` (no
     `indexScan` row). A left-out signal lists nothing, has 0 candidates and
     states design 8.3's rule text (the funnel optional).
     pool, in the store's row order: `function` rows of role production
     whose `generated` is 0 (a row that doesn't say is left out and
     counted, as M4's signals do), each counted out by the first that
     applies: W no primary USR (`usr` null; counted by `usrReason`); P
     `access` public or open in a target `indexScan.libraryModules` names
     (target names); V `witness` true; J a `c:` USR; M an entry point:
     kind func, name `main`, no parameters, its key's last segment holding
     `static func main()`, in a target whose type (the stored report's
     `targets`) is `executable`; D kind deinit; else C, a candidate. A
     candidate is L listed when `referrersTests` > 0 and
     `referrersSameModule` + `referrersOtherModules` = 0, R when the latter
     sum is above 0, else Z. Null referrer counts or witness on a row with a
     USR are printed as notes (u8 checks the rows).
     The rule: design 8.3's text, then "; " and the funnel in its words
     (`N production functions = W without a USR + K with one; K = P ... + C
     candidates; C = L listed + R ... + Z ...`), every number equal to this
     check's and adding up as stated; a by-reason breakdown of W in
     parentheses after "without a USR", when given, must equal this check's
     (its absence is printed: the design's funnel text names none); text
     around the funnel is printed. `candidates` is N (the Pool) or C (the
     funnel's candidates): the design names both, and which is printed.
     items: the L candidates, ordered by `referrersTests` descending, then
     subject (the record key), file and line (code point order, which is
     Swift's for ASCII keys); each with rank (from 1), member true, score
     `referrersTests`, and payloads: `references` {tests, testReferrers
     (the stored JSON array), module}; `coverage` exactly when the snapshot
     holds coverage rows (`coverageRun`): {lines, regions} from
     `functionCoverage`, null tallies left out, and for a function without
     a row `{}` or absent; `mutation` exactly when it holds mutation rows
     (`mutationScan`): M6's weak-tests shape (counts, score, functionScore,
     killingTests, firstKillingTests, survivors, suspects), built by
     Scripts/mutation-check.py's SignalModel, and for a function without
     mutants absent or that shape with zero counts; no other payload.
  d  dead but tested (design 8.2; plan step 9b):
     left out, first that applies: `the snapshot predates M7` (as for o);
     `needs periphery: <state>[, <reason>]`, then `needs swiftmutator:
     <state>[, <reason>]` (carried results read `ran`); `the snapshot holds
     no dead-code rows` (no `deadScan` row); `the snapshot holds no mutation
     rows` (no `mutationScan` row). `index` is never required (without it
     outskirts' results are mapped by position, `via: location`). A
     left-out signal lists nothing, has 0 candidates and states design
     8.2's rule text (the funnels optional).
     the runs' coverage of records, from the rows: a run's entries are its
     `deadDeclaration` rows of hint `unused` and class `production`; a
     record is covered by the entry its `deadRecord` row of that run names
     when that entry is one of them, and also by an unused function entry
     (`function.*`) whose `ids` hold the record's `usr` or `usrAccessor`
     (design 5.4 rule 1; `deadRecord` keeps only the lowest ordinal, so a
     lower entry of another hint could take a record's row: printed). A
     record is production-dead when the `production` run covers it, dead
     with tests as roots when the `roots` run does (design 5.4).
     pool, in the store's row order: `function` rows of role production
     whose `generated` is 0 (as for o: test-only's pool). Each is D
     production-dead or A used. A production-dead record's mutants are the
     `mutant` rows placed on it (`place` record, `owner` its key); its
     file's run is its `mutationFile` row's `run` (the mutants' own run when
     that is null and they share one), and that run had coverage off when
     its `mutationRun` row's `skipCoverage` is true. A mutant ran when its
     verdict is killed, survived or timedOut, or only killed when the run
     had coverage off. Then, first that applies: L listed (a mutant ran);
     F in a file whose `mutationFile` disposition is unresolved or
     unlisted; else R, by its mutants: R3 none; R4 survived or timed out
     in a run with coverage off; R1 not covered or no coverage; R2 build
     errors; else R3 (mixed verdicts are printed with the term they got).
     The declarations funnel, over the production run's unused production
     entries (X): F a function entry that covers a record (a `deadRecord`
     row names it, or its `ids` hold a record's USR), U one that covers
     none; T a type entry (class, struct, enum, protocol); E an extension
     entry (`extension*`); V a property entry (`var.*`) a `deadRecord` row
     names; O any other. Its D = the distinct pool records F, T, E and V
     entries cover (the count over records of every role is accepted too,
     and printed).
     The rule: design 8.2's text, then "; " and both funnels in its words
     (`N production functions = D production-dead + A used; D = L listed
     + R with no mutant that ran + F in files without full mutation
     results (unresolved or unlisted); R = R1 ... + R2 only build errors +
     R3 no mutant + R4 ...`; `X unused production declarations = F
     function entries matching a record + U ... + T type entries + E
     extension entries + V property entries with accessor records + O
     others (parameters, imports, enum cases, stored properties,
     typealiases); D = the distinct records F, T, E and V cover`), found
     anywhere after the text, every number equal to this check's and
     adding up as stated, both D's equal; the last clause may name its
     four terms by letter or by number (then equal to F, T, E and V) or
     otherwise (printed); text around the funnels is printed. `candidates`
     is N (the pool) or D, and which is printed.
     items: the L records, ordered by score (the mutants that ran)
     descending, then their killing tests' count (distinct names in the
     `killedBy` of their killed mutants) descending, then subject, file and
     line; each with rank (from 1), member true, that score, and payloads:
     `dead` {kind, name, file, line, accessibility of the covering
     production entry, via (its `deadRecord` row's, `usr` for a record
     matched only by USR), deadWithTestsAsRoots}, nulls left out;
     `mutation`: M6's weak-tests shape (as for o, built by
     Scripts/mutation-check.py's SignalModel) plus one more field holding
     the run's coverage setting, "on" or "off" (design 8.2: `coverage:
     on|off`; another field name is accepted and printed); `coverage`
     exactly when the snapshot holds coverage rows (as for o); no other
     payload.
`--own-only` prints the figures without a report; `--dump` writes them as
JSON (the signals in the report's shape, the funnels, the exclusions and
members, each production entry's term, each coupling pair's term, the
notes).

Inputs `signals` trusts:
  - the store's rows, opened read-only, as design section 9.1 names them:
    `snapshot` (reportSchemaVersion and state), `collectorRun`,
    `indexScan` (libraryModules), the `function` columns key, module,
    kind, name, file, startLine, role, generated, access, parameterCount,
    usr, usrReason, witness, referrersSameModule, referrersOtherModules,
    referrersTests and testReferrers (checked against the scan by `usr`'s
    u7 and u8), `coverageRun`, `functionCoverage`, `mutationScan` and
    M6's mutation tables, and the stored report's `targets` (name, type)
    as T0 wrote them;
  - for dead but tested (d): the `function` columns usrAccessor and the
    usr of every row (any role), `deadScan` (present or not),
    `deadDeclaration` (run, ordinal, hint, class, kind, name, ids, file,
    line, accessibility) and `deadRecord` (run, key, declaration, via) of
    both runs (checked against the scan by `dead --store`), `mutationFile`
    (path, disposition, run), `mutationRun` (ordinal, skipCoverage) and
    `mutant` (owner, place, verdict, killedBy, run) as M6 stores them;
  - Scripts/mutation-check.py (the M6 checker) for M6's `mutation` and
    `coverage` payload shapes, loaded without writing bytecode;
  - for hidden coupling (h): `historyRun` (present or not), the history
    collectorRun's options (`coupling.min_support`), `couplingPair`
    (ordinal, familyA, fileA, familyB, fileB, support, changesA, changesB:
    M3's pairs, trusted as history computed them), `familyHistory`
    (family, file, line; only for the accepted line), the `function`
    columns parentKey, accessorKind, typePath and typeFile of every row,
    `familyReference` (fromFamily, toFamily, via), `familyTypeReference`
    (family, module, typePath, typeFile) and `typeIndex` (module, typePath,
    typeFile) as the index collector stored them (checked against the scan
    by `usr`'s u7 and u8), and the stored report's `targets` dependencies
    and `history.coupling`;
  - the configuration file's `signals.hidden-coupling` and
    `history.coupling.min_support` keys, or `--set`.
Not the report's signals or thresholds, which it checks.

Usage:
    python3 -I -B Scripts/index-check.py dump <store> <libIndexStore.dylib>
                                         <describe.json> <root>
                                         [--output <path>]
    python3 -I -B Scripts/index-check.py build-lines [--stderr <file>]
                                         [--log <file>] [--combined <file>]
                                         [--json <path>] [--compare <path>]
                                         [--all]
    python3 -I -B Scripts/index-check.py build <package> <scan.json>
                                         [--swift <swift>]
                                         [--describe <describe.json>]
                                         [--store <store>] [--snapshot <id>]
                                         [--stderr <file>] [--log <file>]
                                         [--combined <file>]
                                         [--root-spelling <text>]
                                         [--build-spelling <text>]
                                         [--own-only] [--dump <path>] [--all]
                                         [--without-typecheck]
    python3 -I -B Scripts/index-check.py usr <package> <scan.json>
                                         [--swift <swift>] [--library <dylib>]
                                         [--demangle <swift-demangle>]
                                         [--describe <describe.json>]
                                         [--index-store <dir>]
                                         [--reader <dump.json>
                                          --root-spelling <text>
                                          --build-spelling <text>
                                          [--spelling <token>=<path>]...]
                                         [--log <file>] [--own-only]
                                         [--store <store>] [--snapshot <id>]
                                         [--dump <path>] [--all]
                                         [--without-u7]
                                         [--local-containers symbol|enclosing]
                                         [--requirements protocol|package|all]
    python3 -I -B Scripts/index-check.py rows <scan.json> --store <store>
                                         [--snapshot <id>] [--all]
    python3 -I -B Scripts/index-check.py dead <package> <scan.json>
                                         <outskirts>
                                         [--store <store>] [--snapshot <id>]
                                         [--swift <swift>] [--library <dylib>]
                                         [--describe <describe.json>]
                                         [--index-store <dir>]
                                         [--roots-file <json>]
                                         [--production-file <json>]
                                         [--use-scan-inputs]
                                         [--output-dir <dir>]
                                         [--own-only] [--dump <path>] [--all]
                                         [--demangle <swift-demangle>]
                                         [--without-mapping]
                                         [--index-mode auto|index|position]
                                         [--local-rule plan|literal]
                                         [--map-hints all|unused]
                                         [--ordinal-base 0|1]
    python3 -I -B Scripts/index-check.py signals <store>
                                         [--report <report.json>]
                                         [--config <.swiftstats.yml>]
                                         [--set <signal>.<limit>=<value>]...
                                         [--snapshot <id>] [--own-only]
                                         [--dump <path>] [--all]
                                         [--family-match key|key-and-file]
                                         [--owners package|own-module]

For `dump`, <store> is the directory holding `v5/units` (for the T1 build,
`<package>/.swiftstats/index-build/out`). The JSON goes to standard output,
or to `--output`; a summary (unit, record and occurrence counts) goes to
standard error.

Exit status: `dump` 0 when the dump is written, 2 on bad input or a store
that doesn't read; `build-lines`, `build`, `usr`, `rows`, `dead` and `signals` 0
when every check passes (`signals --own-only`: when the figures are
printed), 1 when one fails, 2 on bad input or a store that doesn't read
(for `dead`, also when outskirts can't be started).
"""

import argparse
import ctypes
import glob
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import tempfile
import time
import unicodedata
from collections import Counter, defaultdict

# Nothing here imports a local module, but `-B` may be forgotten.
sys.dont_write_bytecode = True

# indexstore_unit_dependency_kind_t
DEPENDENCY_UNIT = 1
DEPENDENCY_RECORD = 2


# --------------------------------------------------------------------------
# Small helpers


class ReadError(Exception):
    """The store, a unit or a record didn't read."""


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(2)


_LIBC = ctypes.CDLL(None, use_errno=True)
_LIBC.realpath.restype = ctypes.c_void_p
_LIBC.realpath.argtypes = [ctypes.c_char_p, ctypes.c_char_p]
_LIBC.free.restype = None
_LIBC.free.argtypes = [ctypes.c_void_p]


def _realpath3(path):
    """realpath(3) of an existing path, or None."""
    pointer = _LIBC.realpath(os.fsencode(path), None)
    if not pointer:
        return None
    try:
        return os.fsdecode(ctypes.string_at(pointer))
    finally:
        _LIBC.free(pointer)


def real_path(path, what):
    """An absolute path as an NFC real path; "" stays "".

    A path that doesn't exist (a stale unit's main file) keeps its missing
    tail, appended to the real path of its longest existing ancestor.
    """
    if path == "":
        return ""
    if not os.path.isabs(path):
        raise ReadError(f"{what} is not an absolute path: {path!r}")
    head = path.rstrip("/") or "/"
    tail = []
    while True:
        resolved = _realpath3(head)
        if resolved is not None:
            break
        parent, name = os.path.split(head)
        if parent == head:
            raise ReadError(f"{what} has no existing ancestor: {path!r}")
        tail.insert(0, name)
        head = parent
    joined = os.path.join(resolved, *tail) if tail else resolved
    return unicodedata.normalize("NFC", joined)


def is_under(path, root):
    return path == root or path.startswith(root + "/")


def resolved(path):
    """A path as every source is compared: an absolute path's NFC real path
    (`real_path`), an unresolvable or relative one only in NFC."""
    if not os.path.isabs(path or ""):
        return unicodedata.normalize("NFC", path or "")
    try:
        return real_path(path, "a path")
    except ReadError:
        return unicodedata.normalize("NFC", path)


class SourceSpellings:
    """The package's sources by real path: a tool gives a source's real path
    (links resolved, the disk's case), the scan and the describe the
    package's spelling (a linked target directory or file, a manifest path
    in another case). One real path reached under several spellings maps to
    the spelling in the target asked for, else the first in code point
    order. A source added as a fallback (the describe's sources behind the
    scan's files) counts only at a real path no other source resolves to,
    so a source the scan didn't parse keeps its manifest spelling."""

    def __init__(self, root):
        self.root = root
        self.by_real = defaultdict(set)
        self.fallback = defaultdict(set)

    def add(self, spelling, target, fallback=False):
        tier = self.fallback if fallback else self.by_real
        tier[resolved(os.path.join(self.root, spelling))].add((spelling, target))

    def at(self, path):
        real = resolved(path)
        return self.by_real.get(real) or self.fallback.get(real) or ()

    def source(self, path, target=None):
        sources = sorted(self.at(path))
        chosen = next((s for s, t in sources if t == target), None)
        return chosen if chosen is not None else (sources[0][0] if sources else None)

    def is_source(self, path, target):
        return any(t == target for _, t in self.at(path))


def describe_sources(describe, root, restore=lambda path: path):
    """(spelling, target name) of each source of each target of a describe
    JSON: the target's `path` (`restore`d) joined with the source,
    normalised, NFC, relative to the root (sources outside it left out)."""
    sources = []
    for target in describe.get("targets", []):
        base = os.path.normpath(os.path.join(root, restore(target.get("path", ""))))
        for source in target.get("sources", []):
            full = unicodedata.normalize("NFC", os.path.normpath(os.path.join(base, source)))
            if is_under(full, root) and full != root:
                sources.append((full[len(root) + 1:], target["name"]))
    return sources


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


# --------------------------------------------------------------------------
# The ctypes reader over libIndexStore's C API


class StringRef(ctypes.Structure):
    """indexstore_string_ref_t"""

    _fields_ = [("data", ctypes.c_void_p), ("length", ctypes.c_size_t)]


VOID = ctypes.c_void_p
UNIT_NAME_APPLIER = ctypes.CFUNCTYPE(ctypes.c_bool, VOID, StringRef)
POINTER_APPLIER = ctypes.CFUNCTYPE(ctypes.c_bool, VOID, VOID)

# name: (restype, argtypes), as indexstore_functions.h declares them.
SIGNATURES = {
    "indexstore_version": (ctypes.c_uint, []),
    "indexstore_format_version": (ctypes.c_uint, []),
    "indexstore_error_get_description": (ctypes.c_char_p, [VOID]),
    "indexstore_error_dispose": (None, [VOID]),
    "indexstore_store_create": (VOID, [ctypes.c_char_p, ctypes.POINTER(VOID)]),
    "indexstore_store_dispose": (None, [VOID]),
    "indexstore_store_units_apply_f": (ctypes.c_bool, [VOID, ctypes.c_uint, VOID, UNIT_NAME_APPLIER]),
    "indexstore_unit_reader_create": (VOID, [VOID, ctypes.c_char_p, ctypes.POINTER(VOID)]),
    "indexstore_unit_reader_dispose": (None, [VOID]),
    "indexstore_unit_reader_get_modification_time": (
        None, [VOID, ctypes.POINTER(ctypes.c_int64), ctypes.POINTER(ctypes.c_int64)]),
    "indexstore_unit_reader_is_system_unit": (ctypes.c_bool, [VOID]),
    "indexstore_unit_reader_has_main_file": (ctypes.c_bool, [VOID]),
    "indexstore_unit_reader_get_main_file": (StringRef, [VOID]),
    "indexstore_unit_reader_get_module_name": (StringRef, [VOID]),
    "indexstore_unit_reader_get_target": (StringRef, [VOID]),
    "indexstore_unit_reader_dependencies_apply_f": (ctypes.c_bool, [VOID, VOID, POINTER_APPLIER]),
    "indexstore_unit_dependency_get_kind": (ctypes.c_int, [VOID]),
    "indexstore_unit_dependency_is_system": (ctypes.c_bool, [VOID]),
    "indexstore_unit_dependency_get_filepath": (StringRef, [VOID]),
    "indexstore_unit_dependency_get_modulename": (StringRef, [VOID]),
    "indexstore_unit_dependency_get_name": (StringRef, [VOID]),
    "indexstore_record_reader_create": (VOID, [VOID, ctypes.c_char_p, ctypes.POINTER(VOID)]),
    "indexstore_record_reader_dispose": (None, [VOID]),
    "indexstore_record_reader_occurrences_apply_f": (ctypes.c_bool, [VOID, VOID, POINTER_APPLIER]),
    "indexstore_occurrence_get_symbol": (VOID, [VOID]),
    "indexstore_occurrence_get_roles": (ctypes.c_uint64, [VOID]),
    "indexstore_occurrence_get_line_col": (
        None, [VOID, ctypes.POINTER(ctypes.c_uint), ctypes.POINTER(ctypes.c_uint)]),
    "indexstore_occurrence_relations_apply_f": (ctypes.c_bool, [VOID, VOID, POINTER_APPLIER]),
    "indexstore_symbol_relation_get_roles": (ctypes.c_uint64, [VOID]),
    "indexstore_symbol_relation_get_symbol": (VOID, [VOID]),
    "indexstore_symbol_get_usr": (StringRef, [VOID]),
    "indexstore_symbol_get_name": (StringRef, [VOID]),
    "indexstore_symbol_get_kind": (ctypes.c_int, [VOID]),
    "indexstore_symbol_get_subkind": (ctypes.c_int, [VOID]),
    "indexstore_symbol_get_properties": (ctypes.c_uint64, [VOID]),
}


class Library:
    """libIndexStore.dylib, loaded by path, with every function typed."""

    def __init__(self, path):
        try:
            self.handle = ctypes.CDLL(path, mode=ctypes.RTLD_LOCAL)
        except OSError as error:
            raise ReadError(f"libIndexStore.dylib didn't load: {error}")
        for name, (restype, argtypes) in SIGNATURES.items():
            try:
                function = getattr(self.handle, name)
            except AttributeError:
                raise ReadError(f"{path} has no function {name}")
            function.restype = restype
            function.argtypes = argtypes
            setattr(self, name[len("indexstore_"):], function)

    def string(self, reference, what):
        """An indexstore_string_ref_t as a str (UTF-8, strict)."""
        if reference.length == 0:
            return ""
        raw = ctypes.string_at(reference.data, reference.length)
        try:
            return raw.decode("utf-8")
        except UnicodeDecodeError:
            raise ReadError(f"{what} is not UTF-8: {raw!r}")

    def error_text(self, error):
        if not error:
            return "no error description"
        text = self.error_get_description(error)
        self.error_dispose(error)
        return text.decode("utf-8", "replace") if text else "no error description"


class Applier:
    """Wraps a Python callback for an `_apply_f` call.

    An exception raised in a ctypes callback would only be printed, so it is
    kept here, the callback stops the iteration, and `finish` raises it.
    The `_apply_f` functions' own return values are not read, as the
    IndexStore product doesn't read them: an empty record's occurrence apply
    returns false although nothing failed.
    """

    def __init__(self, prototype, body):
        self.error = None

        def call(context, value):
            if self.error is not None:
                return False
            try:
                body(value)
                return True
            except BaseException as error:
                self.error = error
                return False

        self.function = prototype(call)

    def finish(self):
        if self.error is not None:
            raise self.error


class Store:
    """An index store opened with the library: unit names, units, records."""

    def __init__(self, library, path):
        self.library = library
        error = VOID()
        self.handle = library.store_create(os.fsencode(path), ctypes.byref(error))
        if not self.handle:
            raise ReadError(f"the index store at {path} doesn't read: {library.error_text(error)}")

    def close(self):
        if self.handle:
            self.library.store_dispose(self.handle)
            self.handle = None

    def unit_names(self):
        names = []
        applier = Applier(UNIT_NAME_APPLIER, lambda reference: names.append(
            self.library.string(reference, "a unit name")))
        self.library.store_units_apply_f(self.handle, 0, None, applier.function)
        applier.finish()
        return sorted(names)

    def unit(self, name):
        """A unit's header and dependencies, or ReadError."""
        lib = self.library
        error = VOID()
        reader = lib.unit_reader_create(self.handle, name.encode("utf-8"), ctypes.byref(error))
        if not reader:
            raise ReadError(f"unit {name} doesn't read: {lib.error_text(error)}")
        try:
            seconds = ctypes.c_int64()
            nanoseconds = ctypes.c_int64()
            lib.unit_reader_get_modification_time(reader, ctypes.byref(seconds), ctypes.byref(nanoseconds))
            main_file = ""
            if lib.unit_reader_has_main_file(reader):
                main_file = lib.string(lib.unit_reader_get_main_file(reader), f"unit {name}'s main file")
            unit = {
                "name": name,
                "module": lib.string(lib.unit_reader_get_module_name(reader), f"unit {name}'s module"),
                "mainFile": main_file,
                "target": lib.string(lib.unit_reader_get_target(reader), f"unit {name}'s target"),
                "isSystem": bool(lib.unit_reader_is_system_unit(reader)),
                "modified": {"seconds": seconds.value, "nanoseconds": nanoseconds.value},
            }
            records = []
            modules = []

            def dependency(pointer):
                kind = lib.unit_dependency_get_kind(pointer)
                if kind == DEPENDENCY_RECORD:
                    records.append((
                        lib.string(lib.unit_dependency_get_name(pointer), f"a record of unit {name}"),
                        lib.string(lib.unit_dependency_get_filepath(pointer), f"a record path of unit {name}"),
                    ))
                elif kind == DEPENDENCY_UNIT:
                    modules.append({
                        "module": lib.string(lib.unit_dependency_get_modulename(pointer),
                                             f"a module dependency of unit {name}"),
                        "isSystem": bool(lib.unit_dependency_is_system(pointer)),
                    })

            applier = Applier(POINTER_APPLIER, dependency)
            lib.unit_reader_dependencies_apply_f(reader, None, applier.function)
            applier.finish()
            return unit, records, modules
        finally:
            lib.unit_reader_dispose(reader)

    def symbol(self, pointer, what):
        lib = self.library
        return {
            "usr": lib.string(lib.symbol_get_usr(pointer), f"a USR in {what}"),
            "name": lib.string(lib.symbol_get_name(pointer), f"a symbol name in {what}"),
            "kind": int(lib.symbol_get_kind(pointer)),
            "subkind": int(lib.symbol_get_subkind(pointer)),
            "properties": int(lib.symbol_get_properties(pointer)),
        }

    def occurrences(self, record_name):
        """Every occurrence of a record, unsorted, or ReadError."""
        lib = self.library
        error = VOID()
        reader = lib.record_reader_create(self.handle, record_name.encode("utf-8"), ctypes.byref(error))
        if not reader:
            raise ReadError(f"record {record_name} doesn't read: {lib.error_text(error)}")
        what = f"record {record_name}"
        try:
            found = []

            def occurrence(pointer):
                line = ctypes.c_uint()
                column = ctypes.c_uint()
                lib.occurrence_get_line_col(pointer, ctypes.byref(line), ctypes.byref(column))
                symbol = lib.occurrence_get_symbol(pointer)
                if not symbol:
                    raise ReadError(f"an occurrence in {what} has no symbol")
                relations = []

                def relation(related):
                    other = lib.symbol_relation_get_symbol(related)
                    if not other:
                        raise ReadError(f"a relation in {what} has no symbol")
                    entry = {"roles": int(lib.symbol_relation_get_roles(related))}
                    entry.update(self.symbol(other, what))
                    relations.append(entry)

                inner = Applier(POINTER_APPLIER, relation)
                lib.occurrence_relations_apply_f(pointer, None, inner.function)
                inner.finish()
                entry = {"line": line.value, "column": column.value,
                         "roles": int(lib.occurrence_get_roles(pointer))}
                entry.update(self.symbol(symbol, what))
                relations.sort(key=relation_order)
                entry["relations"] = relations
                found.append(entry)

            applier = Applier(POINTER_APPLIER, occurrence)
            lib.record_reader_occurrences_apply_f(reader, None, applier.function)
            applier.finish()
            return found
        finally:
            lib.record_reader_dispose(reader)


def relation_order(relation):
    return (relation["usr"], relation["roles"], relation["kind"], relation["subkind"],
            relation["properties"], relation["name"])


def occurrence_order(occurrence):
    return (occurrence["line"], occurrence["column"], occurrence["usr"], occurrence["roles"],
            occurrence["kind"], occurrence["subkind"], occurrence["properties"], occurrence["name"],
            [relation_order(relation) for relation in occurrence["relations"]])


# --------------------------------------------------------------------------
# dump


def source_files(describe_path, root):
    """The package's source files: describe's target sources and the manifests."""
    try:
        with open(describe_path, encoding="utf-8") as handle:
            describe = json.load(handle)
    except (OSError, ValueError) as error:
        fail(f"{describe_path} doesn't read as JSON: {error}")
    described = describe.get("path")
    if not isinstance(described, str) or real_path(described, "describe's path") != root:
        fail(f"{describe_path} describes {described!r}, not {root}")
    paths = set()
    for target in describe.get("targets", []):
        base = os.path.join(root, target.get("path", ""))
        for source in target.get("sources", []):
            paths.add(os.path.join(base, source))
    paths.add(os.path.join(root, "Package.swift"))
    paths.update(glob.glob(os.path.join(glob.escape(root), "Package@swift-*.swift")))
    files = []
    for path in sorted(paths):
        if not os.path.isfile(path):
            fail(f"a source file of {describe_path} doesn't exist: {path}")
        files.append({"path": real_path(path, "a source file"), "sha256": sha256_of(path)})
    files.sort(key=lambda entry: entry["path"])
    return files


def read_dump(store_path, library_path, root):
    """The dump's units and records, read from the store."""
    library = Library(library_path)
    store = Store(library, store_path)
    try:
        names = store.unit_names()
        units = []
        record_files = {}
        dumped_records = set()
        system_units = 0
        for name in names:
            unit, records, modules = store.unit(name)
            if unit["isSystem"]:
                system_units += 1
                continue
            unit["mainFile"] = real_path(unit["mainFile"], f"unit {name}'s main file")
            unit["records"] = sorted(record for record, _ in records)
            modules.sort(key=lambda entry: (entry["module"], entry["isSystem"]))
            unit["moduleDependencies"] = modules
            units.append(unit)
            for record, path in records:
                path = real_path(path, f"record {record}'s file") if path else ""
                record_files.setdefault(record, set()).add(path)
            if unit["mainFile"] != "" and is_under(unit["mainFile"], root):
                dumped_records.update(record for record, _ in records)
        dumped = []
        occurrence_count = 0
        shared = 0
        for record in sorted(dumped_records):
            occurrences = store.occurrences(record)
            occurrences.sort(key=occurrence_order)
            occurrence_count += len(occurrences)
            paths = sorted(record_files[record])
            entry = {"name": record, "file": paths[0]}
            if len(paths) > 1:
                entry["otherFiles"] = paths[1:]
                shared += 1
            entry["occurrences"] = occurrences
            dumped.append(entry)
        summary = (f"units: {len(names)} in the store, {system_units} system, {len(units)} dumped; "
                   f"records: {len(dumped)} ({shared} named with several files); "
                   f"occurrences: {occurrence_count}")
        version = {"apiVersion": int(library.version()), "formatVersion": int(library.format_version())}
        return units, dumped, version, summary
    finally:
        store.close()


def encoded(value):
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"))


def render(dump):
    """The dump as JSON text: one unit, record header, occurrence or file a line."""
    lines = ["{"]
    for key in ("root", "store", "library"):
        lines.append(f"{encoded(key)}:{encoded(dump[key])},")
    lines.append('"units":[')
    lines.append(",\n".join(encoded(unit) for unit in dump["units"]))
    lines.append("],")
    lines.append('"records":[')
    records = []
    for record in dump["records"]:
        head = f'{{"name":{encoded(record["name"])},"file":{encoded(record["file"])},'
        if "otherFiles" in record:
            head += f'"otherFiles":{encoded(record["otherFiles"])},'
        head += '"occurrences":['
        body = ",\n".join(encoded(occurrence) for occurrence in record["occurrences"])
        records.append(f"{head}\n{body}\n]}}" if body else f"{head}]}}")
    lines.append(",\n".join(records))
    lines.append("],")
    lines.append('"files":[')
    lines.append(",\n".join(encoded(entry) for entry in dump["files"]))
    lines.append("]")
    lines.append("}")
    text = "\n".join(line for line in lines if line != "") + "\n"
    if json.loads(text) != dump:
        raise ReadError("the rendered dump doesn't read back as the values read")
    return text


def dump_mode(arguments):
    try:
        root = real_path(os.path.abspath(arguments.root), "the root")
        store_path = real_path(os.path.abspath(arguments.store), "the store")
        library_path = real_path(os.path.abspath(arguments.library), "the library")
    except ReadError as error:
        fail(str(error))
    if not os.path.isdir(root):
        fail(f"the root {root} is not a directory")
    if not os.path.isdir(os.path.join(store_path, "v5", "units")):
        fail(f"{store_path} holds no v5/units: pass the directory holding v5 (the build's out/)")
    if not os.path.isfile(library_path):
        fail(f"no library at {library_path}")
    files = source_files(arguments.describe, root)
    try:
        units, records, version, summary = read_dump(store_path, library_path, root)
        library = {"path": library_path}
        library.update(version)
        text = render({"root": root, "store": store_path, "library": library,
                       "units": units, "records": records, "files": files})
    except ReadError as error:
        fail(str(error))
    if arguments.output:
        temporary = arguments.output + ".partial"
        with open(temporary, "w", encoding="utf-8") as handle:
            handle.write(text)
        os.replace(temporary, arguments.output)
    else:
        sys.stdout.write(text)
    print(f"{summary}; files: {len(files)}", file=sys.stderr)
    return 0


# --------------------------------------------------------------------------
# build-lines and build: the T1 build's output (design sections 6.1-6.3, 11)
#
# Written from the design's words and the research's measured lines, not
# from SwiftStats' reader: the patterns below are this script's own (tab
# splitting, right-to-left location splitting, prefix tests), not the
# regular expressions of design section 6.1, so a format change the scan
# misreads can't pass by both sides dropping the same lines.

BUILD_DIRECTORY = os.path.join(".swiftstats", "index-build")
BUILD_STDERR = "swiftstats-build.stderr"
BUILD_LOG = "swiftstats-build.log"
SEVERITIES = ("warning", "error", "note", "remark")
LINE_PREFIXES = tuple(f"{word}: " for word in SEVERITIES + ("info",))
CONTINUATION_LIMIT = 20
INVALID_LOCATION = "<invalid loc>"
MACRO_PLACE = "macro expansion "
MACRO_BUFFER = "@__swiftmacro_"
ORIGIN_NOTE = "expanded code originates here"
IDENTIFIER_CHARACTERS = set("abcdefghijklmnopqrstuvwxyz0123456789_")
LISTED = 20
SOURCE_EXTENSIONS = {"swift", "swiftinterface", "h", "c", "m", "mm", "cpp", "cc", "hpp"}
ESCAPE = "\x1b"
BELL = "\x07"

# Line classes. Every line of every input gets exactly one; the ones in
# UNACCOUNTED fail the check.
ACCOUNTED_CLASSES = (
    "blank",                      # empty or white space only
    "functionEntry",              # <ms>ms TAB <place> TAB <declaration>@<place>
    "expressionEntry",            # <ms>ms TAB <place>
    "diagnostic",                 # <path>:<line>:<column>: <severity>: <message>
    "macroDiagnostic",            # macro expansion #name:<line>:<column>: <severity>: ...
    "bufferDiagnostic",           # <Module>.<Type>.<member>:<l>:<c>: note: ... (an interface buffer)
    "unknownPlaceDiagnostic",     # <unknown>:<line>: <severity>: ...
    "continuation",               # a diagnostic message's further lines
    "decoratedNote",              # `- <path>:<l>:<c>: note: ... (origin notes among them)
    "snippet",                    # source excerpt: digits or nothing, then a `|` gutter
    "snippetEcho",                # an excerpt line repeating a diagnostic: |- warning: ...
    "echoContinuation",           # an echoed message's further lines
    "snippetBox",                 # +--- macro expansion #expect ---, +-----
    "groupFootnote",              # [#Group]: <https://...>
    "summaryForm",                # warning: <path>:<l>:<c> <text>  (no colon after the column)
    "manifestCommand",            # warning: '<package>': <toolchain>/swift-frontend -frontend ...
    "packageWarning",             # warning: '<package>': <text> (SwiftPM's own)
    "buildError",                 # error: <text> with no place (Build failed, SwiftDriver ... failed)
    "info",                       # info: <text>
    "spliced",                    # --combined only: a timing line broken by the other stream
    "other",                      # anything holding no timing or severity marker
)
UNACCOUNTED_CLASSES = (
    "unaccounted",                # holds `ms<TAB>` or a severity marker; no pattern explains it
    "escapeLeft",                 # an escape character no ANSI or OSC sequence explains
    "otherWarningPrefixed",       # starts `warning: `, and is none of the known kinds
)


def without_escapes(text):
    """(text without ANSI CSI and OSC sequences, whether it held one,
    whether an escape or bell character was left that no sequence explains)."""
    out = []
    index = 0
    length = len(text)
    found = False
    broken = False
    while index < length:
        char = text[index]
        if char != ESCAPE:
            if char == BELL:
                broken = True
            out.append(char)
            index += 1
            continue
        found = True
        following = text[index + 1] if index + 1 < length else ""
        if following == "[":
            cursor = index + 2
            while cursor < length and "\x30" <= text[cursor] <= "\x3f":
                cursor += 1
            while cursor < length and "\x20" <= text[cursor] <= "\x2f":
                cursor += 1
            if cursor < length and "\x40" <= text[cursor] <= "\x7e":
                index = cursor + 1
            else:
                broken = True
                index = cursor
        elif following == "]":
            cursor = index + 2
            while cursor < length and text[cursor] not in (BELL, ESCAPE):
                cursor += 1
            if cursor < length and text[cursor] == BELL:
                index = cursor + 1
            elif text.startswith(ESCAPE + "\\", cursor):
                index = cursor + 2
            else:
                broken = True
                index = cursor
        elif following and "\x40" <= following <= "\x5f":
            index += 2
        else:
            broken = True
            index += 1
    return "".join(out), found, broken


def ascii_digits(text):
    return text != "" and text.isascii() and text.isdigit()


def timing_hundredths(field):
    """`<digits>[.<one or two digits>]ms` as hundredths of a millisecond
    (`4.35ms` 435, `4.3ms` 430, `4ms` 400), else None."""
    if not field.endswith("ms"):
        return None
    whole, dot, fraction = field[:-2].partition(".")
    if not ascii_digits(whole):
        return None
    if not dot:
        return int(whole) * 100
    if not ascii_digits(fraction) or len(fraction) > 2:
        return None
    return int(whole) * 100 + int(fraction.ljust(2, "0"))


def split_place(text):
    """(path, line, column) of `<path>:<line>:<column>`, split from the
    right (a path may hold colons and spaces), else None."""
    head, colon, column = text.rpartition(":")
    if not colon:
        return None
    path, colon, line = head.rpartition(":")
    if not colon or path == "" or not ascii_digits(line) or not ascii_digits(column):
        return None
    if int(line) < 1 or int(column) < 1:
        return None
    return path, int(line), int(column)


def plausible_path(path):
    """A compiler path: absolute, or a recording's `@TOKEN@` placeholder or
    a macro buffer's name (both start with `@`); never indented."""
    return path[:1] in ("/", "@") and path == path.lstrip()


def timing_entry(text):
    """The entry a whole line states, or None.

    Two tab-separated fields are an expression entry, three a function-body
    entry whose third field (`<kind> <Module>.(file).<context>.<name>@<place>`)
    must end with `@` and the second field when that is a place."""
    fields = text.split("\t")
    if len(fields) not in (2, 3):
        return None
    hundredths = timing_hundredths(fields[0])
    if hundredths is None:
        return None
    if fields[1] == INVALID_LOCATION:
        place = None
    else:
        place = split_place(fields[1])
        if place is None or not plausible_path(place[0]):
            return None
    entry = {
        "kind": "expression" if len(fields) == 2 else "function",
        "hundredths": hundredths,
        "file": place[0] if place else None,
        "line": place[1] if place else None,
        "column": place[2] if place else None,
    }
    if len(fields) == 3:
        declaration = fields[2]
        if declaration.strip() == "":
            return None
        if place is not None and not declaration.endswith("@" + fields[1]):
            return None
        entry["declaration"] = declaration
    return entry


def spliced_entry(text):
    """For a combined stdout-and-stderr log (2>&1), where the two streams'
    writes can break each other's lines: (how, entry) for a line holding
    `ms<TAB>` that isn't a whole entry, else None.

    `tail`: a fragment of another line, then a whole timing line (whose
    leading digits may belong to the fragment). `head`: a line that starts
    as a timing line and breaks off; its entry is what still reads (the
    place, when whole), or None. Neither entry is counted; `head` entries
    are listed so a reader that reads the broken line as an entry can be
    told apart from a disagreement."""
    position = text.find("ms\t")
    while position > 0:
        start = position
        while start > 0 and (text[start - 1].isdigit() or text[start - 1] == "."):
            start -= 1
        for cut in range(max(start, 1), position):
            entry = timing_entry(text[cut:])
            if entry is not None:
                return "tail", entry
        position = text.find("ms\t", position + 1)
    fields = text.split("\t")
    if len(fields) >= 2 and timing_hundredths(fields[0]) is not None:
        place = None if fields[1] == INVALID_LOCATION else split_place(fields[1])
        entry = None
        if fields[1] == INVALID_LOCATION or (place is not None and plausible_path(place[0])):
            entry = {"kind": "expression" if len(fields) == 2 else "function",
                     "hundredths": timing_hundredths(fields[0]),
                     "file": place[0] if place else None,
                     "line": place[1] if place else None,
                     "column": place[2] if place else None}
        return "head", entry
    return None


def split_suffixes(message):
    """(message without its trailing ` [id]` and ` [#Group]`, id, group);
    the id comes before the group (`[shared_mutable_state_decl] [#MutableGlobalVariable]`)."""
    text = message.rstrip()
    group = None
    if text.endswith("]"):
        start = text.rfind(" [#")
        name = text[start + 3:-1] if start >= 0 else ""
        if name and name.isascii() and name.isalnum():
            group = name
            text = text[:start]
    identifier = None
    if text.endswith("]"):
        start = text.rfind(" [")
        name = text[start + 2:-1] if start >= 0 else ""
        if name and set(name) <= IDENTIFIER_CHARACTERS:
            identifier = name
            text = text[:start]
    return text, identifier, group


def diagnostic_header(text):
    """A diagnostic's first line as (place kind, path or macro name, line,
    column, severity, message), else None.

    The place is everything before the first `: <severity>: ` whose prefix
    reads as a place: `<path>:<line>:<column>` (kind `file`), `macro
    expansion #name:<line>:<column>` or `@name` (kind `macro`), or
    `<unknown>:<line>` (kind `unknown`)."""
    position = text.find(": ")
    while position >= 0:
        rest = text[position + 2:]
        severity = next((word for word in SEVERITIES
                         if rest.startswith(word + ": ") or rest == word + ":"), None)
        if severity is not None:
            prefix = text[:position]
            message = rest[len(severity) + 2:]
            if prefix.startswith(MACRO_PLACE):
                place = split_place(prefix[len(MACRO_PLACE):])
                if place is not None and place[0][:1] in ("#", "@") and len(place[0]) > 1 \
                        and all(c.isalnum() or c in "_." for c in place[0][1:]):
                    return ("macro", place[0], place[1], place[2], severity, message)
            elif buffer_place(prefix) is not None:
                place = buffer_place(prefix)
                return ("buffer", place[0], place[1], place[2], severity, message)
            elif prefix.startswith("<unknown>:") and ascii_digits(prefix[len("<unknown>:"):]):
                return ("unknown", "<unknown>", int(prefix[len("<unknown>:"):]), None, severity, message)
            else:
                place = split_place(prefix)
                if place is not None and plausible_path(place[0]):
                    return ("file", place[0], place[1], place[2], severity, message)
        position = text.find(": ", position + 1)
    return None


def buffer_place(text):
    """`<Module>.<Type>.<member>:<line>:<column>`: a place in a buffer the
    compiler printed from a module's interface (a note on a declaration in
    a dependency or the SDK), not a file. Returns (name, line, column)."""
    place = split_place(text)
    if place is None:
        return None
    parts = place[0].split(".")
    if parts[-1] in SOURCE_EXTENSIONS:
        return None
    if len(parts) < 2 or not all(part and (part[0].isalpha() or part[0] == "_")
                                 and all(c.isalnum() or c == "_" for c in part) for part in parts):
        return None
    return place


def gutter(text):
    """The text after a source excerpt's gutter (`  12 | `, `   | `), or None:
    the part before the first `|` holds only spaces and digits."""
    lead, bar, after = text.partition("|")
    if not bar or not all(c == " " or c.isdigit() for c in lead):
        return None
    return after


def is_box(text):
    stripped = text.lstrip(" ")
    return stripped.startswith("+-")


def decorated(text):
    """The text after a `` `- `` or `|- ` decoration at the start of a line, or None."""
    stripped = text.lstrip(" ")
    for mark in ("`- ", "|- "):
        if stripped.startswith(mark):
            return stripped[len(mark):]
    return None


def echoed(text):
    """(severity, message) when an excerpt line repeats a diagnostic
    (`   |  |- warning: ...`, `  |   `- note: ...`), else None."""
    after = gutter(text)
    while after is not None:
        for mark in ("`- ", "|- "):
            index = after.find(mark)
            while index >= 0:
                rest = after[index + len(mark):]
                for severity in SEVERITIES:
                    if rest.startswith(severity + ": "):
                        return severity, rest[len(severity) + 2:]
                index = after.find(mark, index + 1)
        after = None
    return None


def is_group_footnote(text):
    if not text.startswith("[#"):
        return False
    name, bracket, rest = text[2:].partition("]: <")
    return bool(bracket) and name.isascii() and name.isalnum() and rest.endswith(">")


def summary_form(text):
    """`warning: <path>:<line>:<column> <text>` or the `error: ` form: Swift
    Build's summary line, with no colon after the column."""
    for word in ("warning", "error"):
        if text.startswith(word + ": "):
            place, space, _ = text[len(word) + 2:].partition(" ")
            if space and split_place(place) is not None and plausible_path(split_place(place)[0]):
                return True
    return False


def manifest_command(text):
    """`warning: '<package>': <toolchain>/usr/bin/swift-frontend -frontend -c ...`:
    the manifest compile's command line, printed under -v as a warning."""
    if not text.startswith("warning: '"):
        return False
    _, mark, command = text[len("warning: '"):].partition("': ")
    words = command.split(" ")
    return bool(mark) and len(words) > 1 and words[0].endswith("/swift-frontend") and words[1] == "-frontend"


def package_warning(text):
    """`warning: '<package>': <text>`: SwiftPM's own package diagnostics."""
    if not text.startswith("warning: '"):
        return False
    name, mark, _ = text[len("warning: '"):].partition("': ")
    return bool(mark) and name != "" and "'" not in name


def has_marker(text):
    """A line that could hold a timing entry or a diagnostic."""
    return "ms\t" in text or any(word + ":" in text for word in SEVERITIES)


def ends_message(text):
    """A line that can't continue a diagnostic's message."""
    return (text.strip() == ""
            or gutter(text) is not None
            or is_box(text)
            or decorated(text) is not None
            or timing_entry(text) is not None
            or diagnostic_header(text) is not None
            or text.startswith(LINE_PREFIXES)
            or is_group_footnote(text))


def continuation_count(lines, start, message):
    """How many lines from `start` continue a message: as many as it takes
    to reach the last line, of the CONTINUATION_LIMIT lines at most that
    follow and none of which can't continue a message, after which the
    joined message ends with a diagnostic ID (the build passes
    -debug-diagnostic-names); 0 when none does. A quoted source line that
    ends in ` [word]` reads as an ID, so the first such line isn't
    necessarily the message's end."""
    joined = message
    count = 0
    for offset in range(CONTINUATION_LIMIT):
        index = start + offset
        if index >= len(lines) or ends_message(lines[index]):
            break
        joined += "\n" + lines[index]
        if split_suffixes(joined)[1] is not None:
            count = offset + 1
    return count


class BuildLines:
    """Every line of one build output file, classified, with the timing
    entries and diagnostics it states."""

    def __init__(self, path, stream, combined):
        self.path = path
        self.stream = stream
        self.combined = combined
        self.classes = defaultdict(int)
        self.examples = defaultdict(list)
        self.entries = []
        self.diagnostics = []
        self.spliced = []
        self.escaped = 0
        self.carriage_returns = 0
        self.undecodable = 0
        self.echo_checked = 0
        self.echo_disagreements = []
        self.kinds = []
        with open(path, "rb") as handle:
            data = handle.read()
        raw_lines = data.split(b"\n")
        if raw_lines and raw_lines[-1] == b"":
            raw_lines.pop()
        self.lines = []
        for raw in raw_lines:
            if raw.endswith(b"\r"):
                self.carriage_returns += 1
                raw = raw[:-1]
            try:
                text = raw.decode("utf-8")
            except UnicodeDecodeError:
                self.undecodable += 1
                text = raw.decode("utf-8", "surrogateescape")
            clean, found, broken = without_escapes(text)
            self.escaped += found
            self.lines.append((clean, broken))
        self.classify()

    def note(self, index, kind):
        self.kinds.append(kind)
        self.classes[kind] += 1
        if kind in UNACCOUNTED_CLASSES and len(self.examples[kind]) < LISTED:
            self.examples[kind].append((index + 1, self.lines[index][0][:300]))

    def classify(self):
        texts = [clean for clean, _ in self.lines]
        assigned = [None] * len(texts)
        for index, text in enumerate(texts):
            if assigned[index] is not None:
                self.note(index, assigned[index])
                continue
            kind = self.line_class(texts, index, assigned)
            if self.lines[index][1]:
                kind = "escapeLeft"
            self.note(index, kind)

    def line_class(self, texts, index, assigned):
        text = texts[index]
        if text.strip() == "":
            return "blank"
        entry = timing_entry(text)
        if entry is not None:
            entry.update(stream=self.stream, lineNumber=index + 1)
            self.entries.append(entry)
            return "functionEntry" if entry["kind"] == "function" else "expressionEntry"
        if gutter(text) is not None:
            echo = echoed(text)
            if echo is None:
                return "snippet"
            count = continuation_count(texts, index + 1, echo[1])
            for offset in range(count):
                assigned[index + 1 + offset] = "echoContinuation"
            self.check_echo(echo, texts[index + 1:index + 1 + count])
            return "snippetEcho"
        if is_box(text):
            return "snippetBox"
        inner = decorated(text)
        if inner is not None:
            header = diagnostic_header(inner)
            return "decoratedNote" if header is not None and header[0] == "file" else self.fallback(text, index)
        header = diagnostic_header(text)
        if header is not None:
            return self.diagnostic(texts, index, header, assigned)
        if text.startswith("warning: "):
            if summary_form(text):
                return "summaryForm"
            if manifest_command(text):
                return "manifestCommand"
            if package_warning(text):
                return "packageWarning"
            return "otherWarningPrefixed"
        if text.startswith("error: "):
            return "summaryForm" if summary_form(text) else "buildError"
        if text.startswith("info: "):
            return "info"
        if is_group_footnote(text):
            return "groupFootnote"
        return self.fallback(text, index)

    def fallback(self, text, index):
        if self.combined and "ms\t" in text:
            spliced = spliced_entry(text)
            if spliced is not None:
                self.spliced.append((spliced[0], spliced[1], index + 1))
                return "spliced"
        return "unaccounted" if has_marker(text) else "other"

    def diagnostic(self, texts, index, header, assigned):
        kind, path, line, column, severity, message = header
        count = continuation_count(texts, index + 1, message)
        for offset in range(count):
            assigned[index + 1 + offset] = "continuation"
        joined = "\n".join([message] + texts[index + 1:index + 1 + count])
        text, identifier, group = split_suffixes(joined)
        origin = None
        if kind == "macro":
            following = index + 1 + count
            inner = decorated(texts[following]) if following < len(texts) else None
            note = diagnostic_header(inner) if inner is not None else None
            if note is not None and note[0] == "file" and note[4] == "note" and note[5].strip() == ORIGIN_NOTE:
                origin = {"file": note[1], "line": note[2], "column": note[3]}
        self.diagnostics.append({
            "severity": severity, "place": kind,
            "file": path if kind in ("file", "buffer") else None,
            "macro": path if kind == "macro" else None,
            "line": line, "column": column,
            "text": joined, "message": text, "id": identifier, "group": group,
            "origin": origin, "continuationLines": count,
            "stream": self.stream, "lineNumber": index + 1,
        })
        return {"file": "diagnostic", "macro": "macroDiagnostic", "buffer": "bufferDiagnostic",
                "unknown": "unknownPlaceDiagnostic"}[kind]

    def check_echo(self, echo, continuation):
        """An excerpt's echo of the diagnostic just read must repeat its whole
        message, continuation lines included."""
        severity, first = echo
        if not self.diagnostics:
            return
        last = self.diagnostics[-1]
        if last["severity"] != severity or last["text"].split("\n", 1)[0] != first:
            return
        self.echo_checked += 1
        echo_text = "\n".join([first] + continuation)
        if echo_text != last["text"]:
            self.echo_disagreements.append((last["lineNumber"], last["text"][:200], echo_text[:200]))

    # ---- figures

    def count(self, *kinds):
        return sum(self.classes[kind] for kind in kinds)

    def unparsed_timing_lines(self):
        """Lines holding `ms<TAB>` that state no whole-line entry."""
        return sum(1 for clean, _ in self.lines if "ms\t" in clean) - len(self.entries)

    def other_warning_lines(self):
        """Lines starting `warning: ` that aren't diagnostics."""
        return sum(1 for clean, _ in self.lines
                   if clean.startswith("warning: ") and diagnostic_header(clean) is None)

    def summary(self):
        return {
            "path": self.path, "stream": self.stream, "lines": len(self.lines),
            "classes": {kind: self.classes[kind] for kind in sorted(self.classes)},
            "escapedLines": self.escaped, "carriageReturns": self.carriage_returns,
            "undecodableLines": self.undecodable,
            "functionEntries": sum(1 for e in self.entries if e["kind"] == "function"),
            "expressionEntries": sum(1 for e in self.entries if e["kind"] == "expression"),
            "unparsedTimingLines": self.unparsed_timing_lines(),
            "splicedTimingLines": len(self.spliced),
            "otherWarningLines": self.other_warning_lines(),
            "diagnostics": len(self.diagnostics),
            "echoesChecked": self.echo_checked,
            "echoDisagreements": len(self.echo_disagreements),
        }


def entry_identity(entry):
    return (entry["kind"], entry["hundredths"], entry["file"], entry["line"], entry["column"])


def diagnostic_identity(diagnostic):
    origin = diagnostic.get("origin") or {}
    return (diagnostic["severity"], diagnostic.get("file"), diagnostic.get("macro"), diagnostic["line"],
            diagnostic.get("column"), diagnostic["message"], diagnostic.get("id"), diagnostic.get("group"),
            origin.get("file"), origin.get("line"), origin.get("column"))


class Accounting:
    """The line accounting over the build's output files."""

    def __init__(self, stderr, log, combined):
        self.files = []
        if combined:
            self.files.append(BuildLines(combined, "combined", True))
        if stderr:
            self.files.append(BuildLines(stderr, "stderr", False))
        if log:
            self.files.append(BuildLines(log, "stdout", False))
        timing_streams = ("stderr", "combined")
        self.entries = [e for f in self.files if f.stream in timing_streams for e in f.entries]
        self.stdout_entries = [e for f in self.files if f.stream == "stdout" for e in f.entries]
        diagnostics = {}
        for lines in self.files:
            for diagnostic in lines.diagnostics:
                diagnostics.setdefault(diagnostic_identity(diagnostic), diagnostic)
        # Unique diagnostics, in the order first seen (stderr before stdout).
        self.diagnostics = list(diagnostics.values())
        self.occurrences = sum(len(f.diagnostics) for f in self.files)

    def counters(self):
        timing_files = [f for f in self.files if f.stream != "stdout"]
        return {
            "escapedLines": sum(f.escaped for f in self.files),
            "unparsedTimingLines": sum(f.unparsed_timing_lines() for f in timing_files),
            "otherWarningLines": sum(f.other_warning_lines() for f in self.files),
            "functionEntries": sum(1 for e in self.entries if e["kind"] == "function"),
            "expressionEntries": sum(1 for e in self.entries if e["kind"] == "expression"),
        }

    def render(self):
        return {
            "files": [f.summary() for f in self.files],
            "counters": self.counters(),
            "entries": [{k: e[k] for k in ("kind", "hundredths", "file", "line", "column")}
                        | ({"declaration": e["declaration"]} if "declaration" in e else {})
                        for e in self.entries],
            "diagnostics": [{k: d[k] for k in ("severity", "place", "file", "macro", "line", "column",
                                               "message", "id", "group", "origin")}
                            for d in self.diagnostics],
            "spliced": [{"how": how, "lineNumber": number, "entry": entry}
                        for f in self.files for how, entry, number in f.spliced],
        }


class Verdict:
    """Prints sections and results; remembers whether any failed."""

    def __init__(self, show_all):
        self.show_all = show_all
        self.failed = False

    def section(self, title):
        print(f"\n== {title}")

    def result(self, name, ok, detail=""):
        self.failed |= not ok
        print(f"  [{'ok' if ok else 'FAIL'}] {name}" + (f": {detail}" if detail else ""))

    def info(self, text):
        print(f"  {text}")

    def listing(self, items):
        items = list(items)
        shown = items if self.show_all else items[:LISTED]
        for item in shown:
            print(f"      {item}")
        if len(shown) < len(items):
            print(f"      ... and {len(items) - len(shown)} more (--all lists them)")


def report_accounting(verdict, accounting):
    verdict.section("line accounting: every line of every file classified")
    for lines in accounting.files:
        summary = lines.summary()
        total = sum(summary["classes"].values())
        verdict.info(f"{lines.path} ({lines.stream}): {summary['lines']} lines")
        for kind in sorted(summary["classes"]):
            verdict.info(f"    {kind:<24} {summary['classes'][kind]}")
        verdict.result(f"{lines.stream}: the classes add up", total == summary["lines"],
                       f"{total} classified of {summary['lines']}")
        unaccounted = lines.count(*UNACCOUNTED_CLASSES)
        verdict.result(f"{lines.stream}: 0 lines unaccounted", unaccounted == 0,
                       f"{unaccounted} ({', '.join(f'{k} {lines.classes[k]}' for k in UNACCOUNTED_CLASSES if lines.classes[k])})"
                       if unaccounted else "")
        for kind in UNACCOUNTED_CLASSES:
            if lines.examples[kind]:
                verdict.listing(f"{kind} line {number}: {text!r}" for number, text in lines.examples[kind])
        timing_lines = sum(1 for clean, _ in lines.lines if "ms\t" in clean)
        read = summary["functionEntries"] + summary["expressionEntries"]
        verdict.result(f"{lines.stream}: every line holding ms<TAB> is an entry"
                       + (" or a spliced entry" if lines.combined else ""),
                       timing_lines == read + summary["splicedTimingLines"],
                       f"{timing_lines} = {read} entries + {summary['splicedTimingLines']} spliced")
        warning_lines = sum(1 for clean, _ in lines.lines if "warning:" in clean)
        explained = sum(1 for (clean, _), kind in zip(lines.lines, lines.kinds)
                        if "warning:" in clean and kind not in UNACCOUNTED_CLASSES)
        verdict.result(f"{lines.stream}: every line holding warning: is explained",
                       warning_lines == explained, f"{explained} of {warning_lines}")
        verdict.result(f"{lines.stream}: every excerpt echo repeats its diagnostic whole",
                       not lines.echo_disagreements, f"{lines.echo_checked} echoes compared")
        verdict.listing(f"line {n}: {a!r} vs echo {b!r}" for n, a, b in lines.echo_disagreements)
        if lines.carriage_returns or lines.undecodable:
            verdict.info(f"    note: {lines.carriage_returns} lines end with CR, "
                         f"{lines.undecodable} aren't UTF-8")
    if any(f.stream == "stdout" for f in accounting.files):
        verdict.result("the stdout log holds no timing entry (the reader takes timings from stderr only)",
                       not accounting.stdout_entries, f"{len(accounting.stdout_entries)} found")
    counters = accounting.counters()
    verdict.info("counters: " + ", ".join(f"{k} {v}" for k, v in counters.items()))
    unidentified = [d for d in accounting.diagnostics if d["severity"] == "warning" and d["id"] is None]
    verdict.info(f"diagnostics: {accounting.occurrences} lines, {len(accounting.diagnostics)} unique "
                 f"({sum(1 for d in accounting.diagnostics if d['severity'] == 'warning')} warnings, "
                 f"{len(unidentified)} without an ID)")


def compare_parse(verdict, accounting, theirs_path):
    """The reader's own JSON (same keys as --json writes) against this parse."""
    verdict.section(f"the reader's parse ({theirs_path}) against this one")
    with open(theirs_path, encoding="utf-8") as handle:
        theirs = json.load(handle)
    mine = accounting.render()
    explained_lines = sum(1 for s in mine["spliced"] if s["how"] == "head" and s["entry"])
    for name, value in mine["counters"].items():
        other = theirs.get("counters", {}).get(name, "absent")
        ok = other == value
        if not ok and name in ("unparsedTimingLines", "functionEntries", "expressionEntries") \
                and isinstance(other, int) and abs(other - value) <= explained_lines:
            ok = None
        verdict.result(f"counter {name}", ok is not False,
                       f"mine {value}, theirs {other}" + (" (within the broken lines read as entries)"
                                                           if ok is None else ""))
    own = Counter(entry_identity(e) for e in mine["entries"])
    their_entries = Counter(entry_identity({**{"file": None, "line": None, "column": None}, **e})
                            for e in theirs.get("entries", []))
    # A combined log's line that starts as a timing line and breaks off may
    # still read as an entry to a reader that doesn't check the declaration's
    # trailing place: such an entry is explained, not a disagreement.
    broken = Counter(entry_identity(s["entry"]) for s in mine["spliced"] if s["how"] == "head" and s["entry"])
    explained = (their_entries - own) & broken
    verdict.result("timing entries (as multisets)", own == their_entries - explained,
                   f"{sum(own.values())} mine, {sum(their_entries.values())} theirs"
                   + (f", {sum(explained.values())} of theirs read from lines broken by the other stream"
                      if explained else ""))
    verdict.listing(f"only mine: {k} x{v}" for k, v in sorted((own - their_entries).items(), key=str))
    verdict.listing(f"only theirs: {k} x{v}" for k, v in sorted((their_entries - own - explained).items(), key=str))
    verdict.listing(f"explained (a broken line): {k} x{v}" for k, v in sorted(explained.items(), key=str))
    own_d = {diagnostic_identity(d) for d in mine["diagnostics"]}
    their_d = {diagnostic_identity({**{"file": None, "macro": None, "column": None, "id": None,
                                       "group": None, "origin": None}, **d})
               for d in theirs.get("diagnostics", [])}
    verdict.result("diagnostics (unique, with joined messages, IDs, groups and origins)", own_d == their_d,
                   f"{len(own_d)} mine, {len(their_d)} theirs")
    verdict.listing(f"only mine: {k}" for k in sorted(own_d - their_d, key=str))
    verdict.listing(f"only theirs: {k}" for k in sorted(their_d - own_d, key=str))


def write_json(path, value):
    temporary = path + ".partial"
    with open(temporary, "w", encoding="utf-8") as handle:
        json.dump(value, handle, indent=1, sort_keys=True, ensure_ascii=False)
        handle.write("\n")
    os.replace(temporary, path)


def build_lines_mode(arguments):
    if not (arguments.stderr or arguments.log or arguments.combined):
        fail("name at least one of --stderr, --log, --combined")
    for path in (arguments.stderr, arguments.log, arguments.combined):
        if path and not os.path.isfile(path):
            fail(f"no file at {path}")
    accounting = Accounting(arguments.stderr, arguments.log, arguments.combined)
    verdict = Verdict(arguments.all)
    report_accounting(verdict, accounting)
    if arguments.json:
        write_json(arguments.json, accounting.render())
    if arguments.compare:
        compare_parse(verdict, accounting, arguments.compare)
    print("\nRESULT: " + ("FAIL" if verdict.failed else "PASS"))
    return 1 if verdict.failed else 0


# ---- placement on the scan's records (design section 6.2)

DECLARATION_WORDS = {
    "let", "var", "func", "struct", "class", "enum", "protocol", "extension", "import", "typealias",
    "actor", "init", "deinit", "subscript", "operator", "precedencegroup", "macro", "associatedtype",
}
MODIFIER_WORDS = {
    "public", "private", "fileprivate", "internal", "open", "package", "static", "final", "nonisolated",
    "indirect", "lazy", "mutating", "nonmutating", "override", "required", "convenience", "dynamic",
    "weak", "unowned", "prefix", "postfix", "infix", "consuming", "borrowing", "distributed",
}
CONTINUATION_WORDS = {"else", "catch", "where"}
BODY_KINDS = {"func", "init", "deinit", "accessor", "topLevel"}
RAW_STRING = re.compile(r'#+"')
HASHES = re.compile(r"#*")
WORD = re.compile(r"[#@$`]?[\w`]*")


def source_tokens(text):
    """(line, token) pairs of Swift source: comments and strings skipped (a
    string is one token), brackets and newlines kept. The same small
    tokenizer as Scripts/coverage-check.py, copied so no script imports
    another."""
    out = []
    index = 0
    line = 1
    length = len(text)
    while index < length:
        char = text[index]
        if char == "\n":
            out.append((line, "\n"))
            line += 1
            index += 1
        elif char in " \t\r﻿":
            index += 1
        elif text.startswith("//", index):
            end = text.find("\n", index)
            index = length if end < 0 else end
        elif text.startswith("/*", index):
            depth = 0
            while index < length:
                if text.startswith("/*", index):
                    depth += 1
                    index += 2
                elif text.startswith("*/", index):
                    depth -= 1
                    index += 2
                    if depth == 0:
                        break
                else:
                    line += text[index] == "\n"
                    index += 1
        elif char == '"' or (char == "#" and RAW_STRING.match(text, index)):
            hashes = len(HASHES.match(text, index).group(0))
            start_line = line
            index += hashes
            closing = ('"""' if text.startswith('"""', index) else '"') + "#" * hashes
            index += 3 if closing.startswith('"""') else 1
            while index < length and not text.startswith(closing, index):
                if text[index] == "\\" and hashes == 0:
                    index += 1
                line += text[index] == "\n" if index < length else 0
                index += 1
            index += len(closing)
            out.append((start_line, '"'))
            if line != start_line:
                out.append((line, '"'))
        elif char.isalnum() or char in "_#@$`":
            match = WORD.match(text, index)
            out.append((line, match.group(0)))
            index += max(1, len(match.group(0)))
        else:
            out.append((line, char))
            index += 1
    return out


def statement_lines(text):
    """The lines of a file's top-level statements, each from its first token
    to its last; declarations and compiler directives are not statements
    (approximate, as in Scripts/coverage-check.py)."""
    lines = set()
    items = []
    current = []
    depth = 0
    toks = source_tokens(text)
    following_tokens = [None] * len(toks)
    upcoming = None
    for position in range(len(toks) - 1, -1, -1):
        following_tokens[position] = upcoming
        if toks[position][1] != "\n":
            upcoming = toks[position][1]
    for position, (line, token) in enumerate(toks):
        if token == "\n":
            if depth == 0 and current:
                following = following_tokens[position]
                last = current[-1][1]
                continues = (
                    following is not None
                    and (following in CONTINUATION_WORDS or following[0] in ".?:&|=+*/%<>^{"
                         or last in {"=", ",", ".", "+", "*", "/", "&", "|", "?", ":", "<", ">", "in"})
                )
                if not continues:
                    items.append(current)
                    current = []
            continue
        if token in "([{":
            depth += 1
        elif token in ")]}":
            depth -= 1
        elif token == ";" and depth == 0:
            if current:
                items.append(current)
            current = []
            continue
        current.append((line, token))
    if current:
        items.append(current)
    for item in items:
        words = [t for _, t in item]
        position = 0
        while position < len(words):
            word = words[position]
            if word.startswith("@"):
                position += 1
                if position < len(words) and words[position] == "(":
                    level = 0
                    while position < len(words):
                        level += words[position] == "("
                        level -= words[position] == ")"
                        position += 1
                        if level == 0:
                            break
            elif word in MODIFIER_WORDS:
                position += 1
                if position < len(words) and words[position] == "(":
                    position += 3
            else:
                break
        first = words[position] if position < len(words) else ""
        if first in DECLARATION_WORDS or first.startswith("#"):
            continue
        lines.update(range(item[0][0], item[-1][0] + 1))
    return lines


def file_scoped_paths(types, source):
    """Dotted paths of the types a file declares private or fileprivate,
    directly or by nesting in one (as Scripts/coverage-check.py reads them,
    to name a type attachment the way SwiftStats' attachments do)."""
    lines = source.split("\n")
    paths = set()
    private_extensions = []

    def modifiers_of(record):
        start = record["range"]["start"]
        first = lines[start["line"] - 1].encode("utf-8")[start["column"] - 1:].decode("utf-8", "replace")
        text = "\n".join([first] + lines[start["line"]:start["line"] + 4])
        match = re.search(r"\b(struct|class|enum|actor|protocol|extension)\b", text)
        prefix = text[:match.start()] if match else ""
        prefix = re.sub(r"\b(private|fileprivate)\s*\(\s*set\s*\)", "", prefix)
        return re.search(r"\b(private|fileprivate)\b", prefix) is not None

    def contains(outer, inner):
        return range_of(outer)[0] < range_of(inner)[0] <= range_of(outer)[1]

    ordered = sorted((t for t in types if not t.get("isLocal")), key=lambda t: range_of(t)[0])
    for record in ordered:
        if record["kind"] == "extension":
            if modifiers_of(record):
                private_extensions.append(record)
            continue
        if (modifiers_of(record) or scoped_by(record["name"], paths)
                or any(contains(extension, record) for extension in private_extensions)):
            paths.add(record["name"])
    return paths


def scoped_by(name, paths):
    prefix = ""
    for component in name.split("."):
        prefix = component if not prefix else prefix + "." + component
        if prefix in paths:
            return True
    return False


def range_of(record):
    start, end = record["range"]["start"], record["range"]["end"]
    return (start["line"], start["column"]), (end["line"], end["column"])


def half_up(hundredths):
    """Hundredths of a ms as whole ms, half up, once, after summing."""
    return (hundredths + 50) // 100


class BuildPackage:
    """The scan JSON's records, types, files and targets, the describe's
    sources, and the package sources on disk."""

    def __init__(self, clone, scan_path, root_spelling, build_spelling):
        self.root = real_path(os.path.abspath(clone), "the package")
        with open(scan_path, encoding="utf-8") as handle:
            self.scan = json.load(handle)
        self.scratch = real_path(os.path.join(self.root, BUILD_DIRECTORY), "the build directory")
        self.root_spelling = (root_spelling or self.root).rstrip("/")
        self.build_spelling = (build_spelling or self.scratch).rstrip("/")
        self.records = self.scan.get("records", [])
        self.by_key = {r["key"]: r for r in self.records}
        self.records_by_file = defaultdict(list)
        for record in self.records:
            self.records_by_file[record["file"]].append(record)
        self.types_by_file = defaultdict(list)
        for record in self.scan.get("types", []):
            self.types_by_file[record["file"]].append(record)
        self.files = {f["path"]: f for f in self.scan.get("files", [])}
        # The scanned files by real path; `add_described` puts the
        # describe's other sources behind them.
        self.source_spellings = SourceSpellings(self.root)
        for path, entry in self.files.items():
            self.source_spellings.add(path, entry.get("module"))
        self.targets = self.scan.get("targets", [])
        self.target_of_file = {}
        for target in self.targets:
            for path in target.get("files", []):
                self.target_of_file.setdefault(path, target)
        self.sources = {}
        self.statements = {}
        self.scoped = {}
        self.changed = self.changed_files()

    def source(self, path):
        if path not in self.sources:
            with open(os.path.join(self.root, path), encoding="utf-8", errors="replace") as handle:
                self.sources[path] = handle.read()
        return self.sources[path]

    def changed_files(self):
        """Scanned files whose bytes now differ from the scan's hash: the
        check runs right after the scan, so these changed during it."""
        changed = set()
        for path, entry in self.files.items():
            full = os.path.join(self.root, path)
            if not os.path.isfile(full) or sha256_of(full) != entry.get("sha256"):
                changed.add(path)
        return changed

    def add_described(self, describe):
        """The describe's sources, behind the scanned files."""
        for spelling, target in describe_sources(describe, self.root):
            self.source_spellings.add(spelling, target, fallback=True)

    def relative(self, path):
        """(class, package-relative NFC path) of a compiler path: under the
        build directory; else a scanned file whose real path the path
        resolves to (its spelling); else another describe source whose real
        path it resolves to (the manifest's spelling); else under the root,
        as printed, then resolved; else outside the root."""
        if path.startswith(self.build_spelling + "/"):
            return "build", None
        source = self.source_spellings.source(path)
        if source is not None:
            return "root", source
        for candidate in (unicodedata.normalize("NFC", path), resolved(path)):
            for root in (self.root_spelling, self.root):
                if candidate.startswith(root + "/"):
                    return "root", candidate[len(root) + 1:]
        return "outsideRoot", None

    def statement_lines(self, path):
        if path not in self.statements:
            self.statements[path] = statement_lines(self.source(path))
        return self.statements[path]

    def type_owner(self, record):
        """`<module>::<type path>`, plus ` @ <file>` for a file-scoped type."""
        owner = f"{record['module']}::{record['name']}"
        if record.get("isLocal"):
            return owner
        path = record["file"]
        if path not in self.scoped:
            self.scoped[path] = file_scoped_paths(self.types_by_file[path], self.source(path))
        return owner + " @ " + path if scoped_by(record["name"], self.scoped[path]) else owner

    def type_between(self, outer, inner):
        """Whether a type of `inner`'s file lies inside `outer`'s range and
        holds `inner`'s range."""
        outer_start, outer_end = range_of(outer)
        inner_start, inner_end = range_of(inner)
        for candidate in self.types_by_file.get(inner["file"], []):
            start, end = range_of(candidate)
            if outer_start <= start and end <= outer_end and start <= inner_start and inner_end <= end:
                return True
        return False

    def nested_in_body(self, record):
        """Whether a body-kind ancestor is reached through the parent keys
        without passing a type between it and `record`."""
        seen = set()
        parent = record.get("parentKey")
        while parent and parent not in seen:
            seen.add(parent)
            ancestor = self.by_key.get(parent)
            if ancestor is None:
                return False
            if self.type_between(ancestor, record):
                return False
            if ancestor["kind"] in BODY_KINDS:
                return True
            parent = ancestor.get("parentKey")
        return False

    def target_for(self, path):
        target = self.target_of_file.get(path)
        if target is not None:
            return target
        prefixes = sorted(((t["path"].rstrip("/") + "/", t) for t in self.targets),
                          key=lambda pair: -len(pair[0]))
        return next((t for prefix, t in prefixes if path.startswith(prefix)), None)

    def place(self, path, line, column):
        """(attachment kind, name): `record` and its key, `type` and its
        owner, or `file` and the path. The innermost record of any role
        holding (line, column): latest start, earliest end, key; a top-level
        code record only on its statement lines. When a local type inside
        that record holds the position (outside its members' records, or
        one of them would be innermost), the innermost such type."""
        point = (line, column)
        holding = []
        for record in self.records_by_file.get(path, []):
            start, end = range_of(record)
            if start <= point <= end:
                if record["kind"] == "topLevel" and line not in self.statement_lines(path):
                    continue
                holding.append(record)
        types = [t for t in self.types_by_file.get(path, []) if range_of(t)[0] <= point <= range_of(t)[1]]

        def innermost_type(candidates):
            chosen = min(candidates,
                         key=lambda r: ((-range_of(r)[0][0], -range_of(r)[0][1]), range_of(r)[1], r["name"]))
            return "type", self.type_owner(chosen)

        if holding:
            record = min(holding, key=lambda r: ((-range_of(r)[0][0], -range_of(r)[0][1]), range_of(r)[1], r["key"]))
            start, end = range_of(record)
            local = [t for t in types if t.get("isLocal") and start <= range_of(t)[0] and range_of(t)[1] <= end]
            if local:
                return innermost_type(local)
            return "record", record["key"]
        if types:
            return innermost_type(types)
        return "file", path


class Timings:
    """design section 6.2 reimplemented: classes, placement, figures."""

    CLASSES = ("synthesized", "macro", "build", "outsideRoot", "fileChanged", "unscanned", "mapped")

    def __init__(self, package, entries):
        self.package = package
        self.classes = {name: {"function": 0, "expression": 0, "hundredths": 0} for name in self.CLASSES}
        self.function_sum = defaultdict(int)
        self.expression_max = {}
        self.entries_on = defaultdict(lambda: [0, 0])
        self.module_of_owner = {}
        for entry in entries:
            name, path = self.class_of(entry)
            bucket = self.classes[name]
            bucket[entry["kind"]] += 1
            bucket["hundredths"] += entry["hundredths"]
            if name != "mapped":
                continue
            owner = package.place(path, entry["line"], entry["column"])
            if owner[0] == "type":
                record = next((t for t in package.types_by_file[path] if package.type_owner(t) == owner[1]), None)
                self.module_of_owner[owner] = record["module"] if record else None
            elif owner[0] == "file":
                self.module_of_owner[owner] = package.files.get(path, {}).get("module")
            if entry["kind"] == "function":
                self.function_sum[owner] += entry["hundredths"]
                self.entries_on[owner][0] += 1
            else:
                self.expression_max[owner] = max(self.expression_max.get(owner, 0), entry["hundredths"])
                self.entries_on[owner][1] += 1

    def class_of(self, entry):
        path = entry["file"]
        if path is None:
            return "synthesized", None
        if os.path.basename(path).startswith(MACRO_BUFFER):
            return "macro", None
        kind, relative = self.package.relative(path)
        if kind != "root":
            return kind, None
        if relative in self.package.changed:
            return "fileChanged", relative
        if relative not in self.package.files:
            return "unscanned", relative
        return "mapped", relative

    def figures(self, owner):
        function = self.function_sum.get(owner)
        expression = self.expression_max.get(owner)
        return (half_up(function) if function is not None else None,
                half_up(expression) if expression is not None else None)

    def records(self):
        out = {}
        for owner in set(self.function_sum) | set(self.expression_max):
            if owner[0] == "record":
                out[owner[1]] = self.figures(owner)
        return out

    def attachments(self):
        out = {}
        for owner in set(self.function_sum) | set(self.expression_max):
            if owner[0] != "record":
                out[owner] = self.figures(owner)
        return out

    def included_in_totals(self, owner):
        return owner[0] != "record" or not self.package.nested_in_body(self.package.by_key[owner[1]])

    def total(self):
        return half_up(sum(h for owner, h in self.function_sum.items() if self.included_in_totals(owner)))

    def module_totals(self):
        sums = defaultdict(int)
        for owner, hundredths in self.function_sum.items():
            if not self.included_in_totals(owner):
                continue
            module = (self.package.by_key[owner[1]]["module"] if owner[0] == "record"
                      else self.module_of_owner.get(owner))
            sums[module] += hundredths
        return {module: half_up(value) for module, value in sums.items()}

    def maxima(self):
        records = self.records()
        timed = [ms for ms, _ in records.values() if ms is not None]
        slowest = [s for _, s in records.values() if s is not None]
        return {"milliseconds.max": max(timed) if timed else None,
                "slowestExpression.max": max(slowest) if slowest else None,
                "functions.timed": len(timed)}

    def scope_of(self, owner):
        """(module, part) of an owner: a record by its module and role
        (production, else tests: test and helper records); a type or file by
        its module, tests when that module's target is a test target."""
        if owner[0] == "record":
            record = self.package.by_key[owner[1]]
            return record.get("module"), "production" if record.get("role") == "production" else "tests"
        module = self.module_of_owner.get(owner)
        target = next((t for t in self.package.targets if t.get("name") == module), None)
        return module, "tests" if target is not None and target.get("isTest") else "production"

    def rollups(self, scopes=()):
        """Design 6.4's roll-ups, by this check's placement: {(scope, name):
        {metric: value}} for each module (`module`, its name) and project
        part (`project`, production or tests) holding a timed owner, and for
        each of `scopes` (the scan's T0 roll-up scopes): the module docstring's
        reading of design 6.4 (scopes, total, maxima, timed)."""
        sums = defaultdict(int)
        timed = defaultdict(int)
        longest = {}
        slowest = {}
        every = set(scopes)
        for owner in set(self.function_sum) | set(self.expression_max):
            module, part = self.scope_of(owner)
            every |= {("module", module), ("project", part)}
        for owner, hundredths in self.function_sum.items():
            if self.included_in_totals(owner):
                module, part = self.scope_of(owner)
                sums[("module", module)] += hundredths
                sums[("project", part)] += hundredths
        for key, (ms, expression) in self.records().items():
            module, part = self.scope_of(("record", key))
            for scope in (("module", module), ("project", part)):
                if ms is not None:
                    timed[scope] += 1
                    longest[scope] = max(longest.get(scope, ms), ms)
                if expression is not None:
                    slowest[scope] = max(slowest.get(scope, expression), expression)
        out = {}
        for scope in every:
            figures = {"typecheck.milliseconds.total": half_up(sums.get(scope, 0)),
                       "typecheck.functions.timed": timed.get(scope, 0)}
            if scope in longest:
                figures["typecheck.milliseconds.max"] = longest[scope]
            if scope in slowest:
                figures["typecheck.slowestExpression.max"] = slowest[scope]
            out[scope] = figures
        return out

    def attachment_maxima(self):
        """The largest attachment figures, which design 6.4's maxima leave out
        (they take records); printed so a scan taking them in can be told."""
        figures = list(self.attachments().values())
        timed = [ms for ms, _ in figures if ms is not None]
        slowest = [s for _, s in figures if s is not None]
        return (max(timed) if timed else None, max(slowest) if slowest else None)


class Warnings:
    """design section 6.3 reimplemented: warning diagnostics as swiftc findings."""

    def __init__(self, package, diagnostics):
        self.package = package
        self.findings = {}
        self.dropped = set()
        self.plugin = set()
        self.unscanned = set()
        self.without_origin = []
        for diagnostic in diagnostics:
            if diagnostic["severity"] != "warning":
                continue
            if diagnostic["place"] == "macro":
                origin = diagnostic["origin"]
                if origin is None:
                    self.without_origin.append(diagnostic)
                    continue
                path, line, column = origin["file"], origin["line"], origin["column"]
            elif diagnostic["place"] in ("file", "buffer"):
                path, line, column = diagnostic["file"], diagnostic["line"], diagnostic["column"]
            else:
                self.without_origin.append(diagnostic)
                continue
            key = (path, line, column, diagnostic["id"] or diagnostic["message"])
            kind, relative = package.relative(path)
            if kind != "root":
                self.dropped.add(key)
                continue
            if key in self.findings:
                continue
            target = package.target_for(relative)
            if target is not None and target.get("type") == "plugin":
                self.plugin.add(key)
            elif relative not in package.files:
                self.unscanned.add(key)
            self.findings[key] = {
                "tool": "swiftc", "rule": diagnostic["id"] or "unidentified", "category": diagnostic["group"],
                "kind": "defect", "severity": "warning", "message": diagnostic["message"],
                "file": relative, "line": line, "column": column,
            }

    def identities(self):
        return {(f["rule"], f["category"], f["message"], f["file"], f["line"], f["column"])
                for f in self.findings.values()}


MISSING = object()


def lookup(block, *paths):
    """The first of several spellings of a value in the scan's build block
    (its exact keys are SwiftStats' choice; design section 9.2 names them)."""
    for path in paths:
        value = block
        for key in path.split("."):
            if not isinstance(value, dict) or key not in value:
                value = MISSING
                break
            value = value[key]
        if value is not MISSING:
            return value
    return MISSING


def entries_of(value):
    """An `{entries, milliseconds}` pair, or a bare entry count, as (entries, ms)."""
    if isinstance(value, dict):
        return (value.get("entries", MISSING), value.get("milliseconds", MISSING))
    return (value, MISSING)


def compare_scan(verdict, package, accounting, timings, warnings):
    scan = package.scan
    block = scan.get("build")
    run = next((c for c in scan.get("collectors", []) if c.get("name") == "build"), None)
    verdict.section("the scan JSON's build block against this reimplementation")
    verdict.info(f"build collector: {run.get('state') if run else 'absent'}"
                 + (f" ({run.get('reason')})" if run and run.get("reason") else ""))
    if block is None:
        verdict.result("the scan JSON has a build block", False, "absent")
        return

    def same(name, mine, theirs):
        if theirs is MISSING:
            verdict.result(name, False, f"mine {mine}; the scan JSON has no such value")
        else:
            verdict.result(name, theirs == mine, f"mine {mine}, scan {theirs}")

    # Records.
    mine = timings.records()
    theirs = {}
    for row in lookup(block, "records") if isinstance(lookup(block, "records"), list) else []:
        theirs[row.get("key")] = (row.get("milliseconds"), row.get("slowestExpression",
                                                                    row.get("slowestExpressionMilliseconds")))
    keys = sorted(set(mine) | set(theirs), key=str)
    differences = [f"{key}: mine {mine.get(key, (None, None))}, scan {theirs.get(key, (None, None))}"
                   for key in keys if mine.get(key, (None, None)) != theirs.get(key, (None, None))]
    verdict.result("per-record ms (sum of function-body entries) and slowest expression", not differences,
                   f"{len(mine)} records timed by this check, {len(theirs)} in the scan")
    verdict.listing(differences)

    # Attachments: the owner's name and kind may sit in either field.
    own_attachments = {(name, kind): figures for (kind, name), figures in timings.attachments().items()}
    scan_attachments = {}
    rows = lookup(block, "attachments")
    for row in rows if isinstance(rows, list) else []:
        owner, attached = row.get("owner"), row.get("attachedTo")
        name, kind = (attached, owner) if owner in ("type", "file") else (owner, attached)
        scan_attachments[(name, kind)] = (row.get("milliseconds"),
                                          row.get("slowestExpression", row.get("slowestExpressionMilliseconds")))
    keys = sorted(set(own_attachments) | set(scan_attachments), key=str)
    differences = [f"{key}: mine {own_attachments.get(key)}, scan {scan_attachments.get(key)}"
                   for key in keys if own_attachments.get(key) != scan_attachments.get(key)]
    verdict.result("attachments (types and files)", rows is not MISSING and not differences,
                   f"{len(own_attachments)} mine, {len(scan_attachments)} scan")
    verdict.listing(differences)

    # Unmapped and dropped entries.
    for name in ("synthesized", "macro"):
        bucket = timings.classes[name]
        entries, milliseconds = entries_of(lookup(block, f"unmapped.{name}"))
        same(f"unmapped {name} entries", bucket["function"] + bucket["expression"], entries)
        if milliseconds is not MISSING:
            same(f"unmapped {name} ms", half_up(bucket["hundredths"]), milliseconds)
    for name in ("build", "outsideRoot", "unscanned", "fileChanged"):
        bucket = timings.classes[name]
        entries, _ = entries_of(lookup(block, f"dropped.{name}"))
        same(f"dropped {name} entries", bucket["function"] + bucket["expression"], entries)

    # Totals and counters.
    same("total ms (function-body entries on records not nested in a body, types and files)",
         timings.total(), lookup(block, "totals.milliseconds", "totals.total", "totals.totalMilliseconds",
                                 "totalMilliseconds", "totals"))
    counters = accounting.counters()
    for name in ("unparsedTimingLines", "escapedLines", "otherWarningLines"):
        same(name, counters[name], lookup(block, name))
    same("pluginWarnings", len(warnings.plugin), lookup(block, "pluginWarnings"))

    # Warnings, as the scan's swiftc findings (attachment not rechecked:
    # the existing FindingMapper's rule).
    findings = [f for f in scan.get("findings", []) if f.get("tool") == "swiftc"]
    scan_findings = set()
    for finding in findings:
        location = (finding.get("locations") or [{}])[0]
        scan_findings.add((finding.get("rule"), finding.get("category"), finding.get("message"),
                           location.get("file"), location.get("line"), location.get("column")))
    own_findings = warnings.identities()
    verdict.result("compiler warnings as swiftc findings (rule, group, message, place)",
                   own_findings == scan_findings, f"{len(own_findings)} mine, {len(scan_findings)} scan")
    verdict.listing(f"only mine: {item}" for item in sorted(own_findings - scan_findings, key=str))
    verdict.listing(f"only the scan's: {item}" for item in sorted(scan_findings - own_findings, key=str))


def compare_store(verdict, package, timings, warnings, store_path, snapshot):
    """The store's rows (design section 9.1) against the same figures."""
    import sqlite3

    verdict.section(f"the store ({store_path}) against this reimplementation")
    connection = sqlite3.connect(f"file:{store_path}?mode=ro", uri=True)
    try:
        if snapshot is None:
            row = connection.execute("SELECT max(id) FROM snapshot").fetchone()
            snapshot = row[0]
        verdict.info(f"snapshot {snapshot}")
        columns = {r[1] for r in connection.execute("PRAGMA table_info(function)")}
        if "typeCheckMilliseconds" not in columns:
            verdict.result("the store has M7's function timing columns", False, "typeCheckMilliseconds absent")
            return
        stored = {key: (ms, slowest) for key, ms, slowest in connection.execute(
            "SELECT key, typeCheckMilliseconds, slowestExpressionMilliseconds FROM function WHERE snapshotId = ?",
            (snapshot,)) if ms is not None or slowest is not None}
        mine = timings.records()
        differences = [f"{key}: mine {mine.get(key)}, store {stored.get(key)}"
                       for key in sorted(set(mine) | set(stored), key=str) if mine.get(key) != stored.get(key)]
        verdict.result("function.typeCheckMilliseconds and slowestExpressionMilliseconds", not differences,
                       f"{len(mine)} mine, {len(stored)} stored")
        verdict.listing(differences)
        attachments = {}
        for owner, attached, ms, slowest in connection.execute(
                "SELECT owner, attachedTo, milliseconds, slowestExpressionMilliseconds FROM timingAttachment "
                "WHERE snapshotId = ?", (snapshot,)):
            name, kind = (attached, owner) if owner in ("type", "file") else (owner, attached)
            attachments[(name, kind)] = (ms, slowest)
        own = {(name, kind): figures for (kind, name), figures in timings.attachments().items()}
        verdict.result("timingAttachment rows", own == attachments, f"{len(own)} mine, {len(attachments)} stored")
        row = connection.execute("SELECT totalMilliseconds, synthesizedEntries, macroEntries, unscannedEntries, "
                                 "pluginWarnings FROM buildScan WHERE snapshotId = ?", (snapshot,)).fetchone()
        if row is None:
            verdict.result("a buildScan row", False, "absent")
        else:
            expected = (timings.total(),
                        timings.classes["synthesized"]["function"] + timings.classes["synthesized"]["expression"],
                        timings.classes["macro"]["function"] + timings.classes["macro"]["expression"],
                        timings.classes["unscanned"]["function"] + timings.classes["unscanned"]["expression"],
                        len(warnings.plugin))
            verdict.result("buildScan totalMilliseconds, synthesized, macro, unscanned entries, pluginWarnings",
                           tuple(row) == expected, f"mine {expected}, store {tuple(row)}")
        stored_findings = {(rule, message, path, line, column) for rule, message, path, line, column in connection.execute(
            "SELECT rule, message, file, line, column FROM finding WHERE snapshotId = ? AND tool = 'swiftc'",
            (snapshot,))}
        own_findings = {(f["rule"], f["message"], f["file"], f["line"], f["column"])
                        for f in warnings.findings.values()}
        verdict.result("finding rows of tool swiftc", own_findings == stored_findings,
                       f"{len(own_findings)} mine, {len(stored_findings)} stored")
    except sqlite3.Error as error:
        verdict.result("the store reads", False, str(error))
    finally:
        connection.close()


TYPECHECK_METRICS = ("typecheck.milliseconds.total", "typecheck.milliseconds.max",
                     "typecheck.slowestExpression.max", "typecheck.functions.timed")


def scan_scopes(scan):
    """The (scope, name) of every roll-up scope in the scan JSON."""
    return [(r.get("scope"), r.get("name")) for r in scan.get("rollups", []) if isinstance(r, dict)]


def typecheck_differences(mine, theirs, theirs_name):
    """Per scope and metric, the figures that differ; an absent value shown
    as `absent`."""
    differences = []
    for scope in sorted(set(mine) | set(theirs), key=str):
        own, other = mine.get(scope), theirs.get(scope)
        if own is None:
            differences.append(f"{scope[0]} {scope[1]}: no such scope by this check's placement, "
                               f"{theirs_name} {dict(sorted(other.items()))}")
            continue
        if other is None:
            differences.append(f"{scope[0]} {scope[1]}: {theirs_name} has no such scope; mine "
                               f"{dict(sorted(own.items()))}")
            continue
        for metric in sorted(set(own) | set(other)):
            if own.get(metric, MISSING) != other.get(metric, MISSING):
                shown = ["absent" if value is MISSING else value
                         for value in (own.get(metric, MISSING), other.get(metric, MISSING))]
                differences.append(f"{scope[0]} {scope[1]} {metric}: mine {shown[0]}, {theirs_name} {shown[1]}")
    return differences


def compare_typecheck_scan(verdict, package, timings):
    """Design 6.4's typecheck.* roll-ups in the scan JSON's roll-up scopes
    against this check's own placement (the module docstring's reading)."""
    scan = package.scan
    verdict.section("the scan JSON's typecheck.* roll-ups against this reimplementation (design 6.4)")
    scopes = scan_scopes(scan)
    mine = timings.rollups(scopes)
    theirs = {}
    unknown = []
    for scope in scan.get("rollups", []):
        if not isinstance(scope, dict):
            continue
        key = (scope.get("scope"), scope.get("name"))
        figures = dict(flatten_numbers(scope.get("typecheck") or {}, "typecheck"))
        unknown += [f"{key[0]} {key[1]} {metric}" for metric in figures if metric not in TYPECHECK_METRICS]
        theirs[key] = figures
    held = sum(1 for figures in theirs.values() if figures)
    verdict.result("the scan JSON's roll-up scopes hold typecheck.* figures", held > 0,
                   f"{held} of {len(theirs)} scopes have any"
                   + ("" if held else " (not built yet in SwiftStats: the expected failure until they are)"))
    verdict.result("no typecheck.* name other than design 6.4's four", not unknown, f"{len(unknown)} others")
    verdict.listing(unknown)
    differences = typecheck_differences(mine, theirs, "scan")
    verdict.result("typecheck.milliseconds.total (rounded once per scope), .max, slowestExpression.max and "
                   "functions.timed per module and project part", not differences,
                   f"{len(mine)} scopes by this check, {len(theirs)} in the scan JSON")
    verdict.listing(differences)


def compare_typecheck_store(verdict, package, timings, store_path, snapshot):
    """The stored rollupMetric rows named typecheck.* against the same figures."""
    import sqlite3

    verdict.section(f"the store's typecheck.* roll-up rows ({store_path}) against this reimplementation")
    connection = sqlite3.connect(f"file:{store_path}?mode=ro", uri=True)
    try:
        if snapshot is None:
            snapshot = connection.execute("SELECT max(id) FROM snapshot").fetchone()[0]
        stored = defaultdict(dict)
        collectors = Counter()
        for scope, name, metric, collector, value in connection.execute(
                "SELECT scope, name, metric, collector, value FROM rollupMetric WHERE snapshotId = ? "
                "AND metric LIKE 'typecheck.%'", (snapshot,)):
            stored[(scope, name)][metric] = int(value) if float(value).is_integer() else value
            collectors[collector] += 1
        scopes = [tuple(r) for r in connection.execute(
            "SELECT DISTINCT scope, name FROM rollupMetric WHERE snapshotId = ?", (snapshot,))]
        for scope in scopes:
            stored.setdefault(scope, {})
    except sqlite3.Error as error:
        verdict.result("the store reads", False, str(error))
        return
    finally:
        connection.close()
    mine = timings.rollups(scopes)
    rows = sum(len(v) for v in stored.values())
    verdict.result("the store holds typecheck.* rollupMetric rows", rows > 0,
                   f"{rows} rows in {sum(1 for v in stored.values() if v)} of {len(stored)} scopes"
                   + ("" if rows else " (not built yet in SwiftStats: the expected failure until they are)"))
    wrong = {name: count for name, count in collectors.items() if name != "build"}
    verdict.result("typecheck.* rows are attributed to the build collector", not wrong,
                   ", ".join(f"{name} {count}" for name, count in sorted(wrong.items())))
    differences = typecheck_differences(mine, dict(stored), "store")
    verdict.result("rollupMetric typecheck.* per module and project part", not differences,
                   f"{len(mine)} scopes by this check, {len(stored)} stored")
    verdict.listing(differences)


def report_timings(verdict, timings, warnings):
    verdict.section("timings and warnings, by this check's own rules")
    for name in Timings.CLASSES:
        bucket = timings.classes[name]
        verdict.info(f"{name:<12} {bucket['function']:>7} function, {bucket['expression']:>7} expression, "
                     f"{half_up(bucket['hundredths']):>8} ms")
    maxima = timings.maxima()
    verdict.info(f"records timed {maxima['functions.timed']}, attachments {len(timings.attachments())}, "
                 f"total {timings.total()} ms (records nested in a body left out), "
                 f"max {maxima['milliseconds.max']} ms, slowest expression {maxima['slowestExpression.max']} ms")
    for (scope, name), figures in sorted(timings.rollups(scan_scopes(timings.package.scan)).items(), key=str):
        verdict.info(f"roll-up {scope} {name}: " + ", ".join(f"{metric[len('typecheck.'):]} {figures[metric]}"
                                                           for metric in TYPECHECK_METRICS if metric in figures))
    longest, slowest = timings.attachment_maxima()
    verdict.info(f"attachments (left out of the maxima, which take records): largest {longest} ms, "
                 f"slowest expression {slowest} ms")
    verdict.info(f"warnings: {len(warnings.findings)} findings ({len(warnings.unscanned)} unscanned, "
                 f"{len(warnings.plugin)} in plugin targets), {len(warnings.dropped)} dropped "
                 f"(build directory or outside the root), {len(warnings.without_origin)} in macro expansions "
                 "without an origin note")
    by_rule = Counter(f["rule"] for f in warnings.findings.values())
    if by_rule:
        verdict.info("by ID: " + ", ".join(f"{rule} {count}" for rule, count in sorted(by_rule.items())))


def own_figures(package, accounting, timings, warnings):
    return {
        "lines": accounting.render(),
        "changedFiles": sorted(package.changed),
        "timings": {
            "classes": timings.classes,
            "records": [{"key": key, "milliseconds": ms, "slowestExpression": slowest,
                         "functionEntries": timings.entries_on[("record", key)][0],
                         "expressionEntries": timings.entries_on[("record", key)][1],
                         "nestedInBody": package.nested_in_body(package.by_key[key])}
                        for key, (ms, slowest) in sorted(timings.records().items())],
            "attachments": [{"owner": name, "attachedTo": kind, "milliseconds": ms, "slowestExpression": slowest}
                            for (kind, name), (ms, slowest) in sorted(timings.attachments().items())],
            "totalMilliseconds": timings.total(),
            "moduleTotals": {str(k): v for k, v in sorted(timings.module_totals().items(), key=str)},
            "maxima": timings.maxima(),
            "rollups": [{"scope": scope, "name": name, **figures} for (scope, name), figures in
                        sorted(timings.rollups(scan_scopes(package.scan)).items(), key=str)],
        },
        "warnings": sorted(warnings.findings.values(), key=lambda f: (f["file"], f["line"], f["column"], f["rule"])),
        "warningsDropped": len(warnings.dropped),
        "pluginWarnings": len(warnings.plugin),
        "warningsWithoutOrigin": len(warnings.without_origin),
    }


def build_mode(arguments):
    try:
        package = BuildPackage(arguments.package, arguments.scan, arguments.root_spelling, arguments.build_spelling)
    except (OSError, ValueError, ReadError) as error:
        fail(str(error))
    if arguments.describe:
        with open(arguments.describe, encoding="utf-8") as handle:
            describe = json.load(handle)
    else:
        resource = toolchain_of(package.root, arguments.swift)
        describe = run_describe(package.root, os.path.join(os.path.dirname(os.path.dirname(resource)), "bin", "swift"))
    described_path = describe.get("path")
    if not isinstance(described_path, str) or not os.path.isabs(described_path) \
            or real_path(described_path, "describe's path") != package.root:
        fail(f"the describe JSON describes {described_path!r}, not {package.root}")
    package.add_described(describe)
    if arguments.combined:
        stderr, log = None, None
    else:
        stderr = arguments.stderr or os.path.join(package.scratch, BUILD_STDERR)
        log = arguments.log or os.path.join(package.scratch, BUILD_LOG)
    for path in (stderr, log, arguments.combined):
        if path and not os.path.isfile(path):
            fail(f"no file at {path}")
    accounting = Accounting(stderr, log, arguments.combined)
    verdict = Verdict(arguments.all)
    print(f"package {package.root}\nbuild directory as the output spells it: {package.build_spelling}\n"
          f"root as the output spells it: {package.root_spelling}")
    if package.changed:
        print(f"files changed since the scan hashed them: {len(package.changed)} "
              f"({', '.join(sorted(package.changed)[:5])})")
    report_accounting(verdict, accounting)
    timings = Timings(package, accounting.entries)
    warnings = Warnings(package, accounting.diagnostics)
    report_timings(verdict, timings, warnings)
    if arguments.dump:
        write_json(arguments.dump, own_figures(package, accounting, timings, warnings))
    if arguments.own_only:
        verdict.section("comparison with the scan JSON skipped (--own-only)")
    else:
        compare_scan(verdict, package, accounting, timings, warnings)
        if not arguments.without_typecheck:
            compare_typecheck_scan(verdict, package, timings)
    if arguments.store:
        compare_store(verdict, package, timings, warnings, arguments.store, arguments.snapshot)
        if not arguments.without_typecheck:
            compare_typecheck_store(verdict, package, timings, arguments.store, arguments.snapshot)
    print("\nRESULT: " + ("FAIL" if verdict.failed else "PASS"))
    return 1 if verdict.failed else 0


# --------------------------------------------------------------------------
# usr: the unit filter, the USR join, reasons and lists (design sections 2.3
# and 3; checks u1-u6 of section 11)
#
# Written from the design's words and the research's measured facts, not from
# SwiftStats' code: the unit classes, the join, the reasons, the name-token
# test and the reading of `swift demangle`'s output are this script's own.

# indexstore_symbol_kind_t, _subkind_t, _property_t and _role_t, as
# indexstore_functions.h at indexstore-db 64aa0b2 numbers them, plus the
# `init` accessor's raw subkind 1016, which the header lacks (design 2.2).
KIND_PROTOCOL = 8
KIND_FUNCTION = 12
KIND_INSTANCE_METHOD = 16
KIND_CLASS_METHOD = 17
KIND_STATIC_METHOD = 18
KIND_INSTANCE_PROPERTY = 19
KIND_CLASS_PROPERTY = 20
KIND_STATIC_PROPERTY = 21
KIND_CONSTRUCTOR = 22
KIND_DESTRUCTOR = 23
FUNCTION_KINDS = {KIND_FUNCTION, KIND_INSTANCE_METHOD, KIND_CLASS_METHOD, KIND_STATIC_METHOD}
METHOD_KINDS = {KIND_INSTANCE_METHOD, KIND_CLASS_METHOD, KIND_STATIC_METHOD}
PROPERTY_KINDS = {KIND_INSTANCE_PROPERTY, KIND_CLASS_PROPERTY, KIND_STATIC_PROPERTY}
SUBKIND_NONE = 0
SUBKIND_GETTER = 3
SUBKIND_SETTER = 4
SUBKIND_WILL_SET = 1000
SUBKIND_DID_SET = 1001
SUBKIND_ADDRESSOR = 1002
SUBKIND_MUTABLE_ADDRESSOR = 1003
SUBKIND_PREFIX_OPERATOR = 1008
SUBKIND_POSTFIX_OPERATOR = 1009
SUBKIND_INFIX_OPERATOR = 1010
SUBKIND_SUBSCRIPT = 1011
SUBKIND_READ = 1014
SUBKIND_MODIFY = 1015
SUBKIND_INIT_ACCESSOR = 1016
OPERATOR_SUBKINDS = {SUBKIND_PREFIX_OPERATOR, SUBKIND_POSTFIX_OPERATOR, SUBKIND_INFIX_OPERATOR}
ACCESSOR_SUBKINDS = {
    "get": SUBKIND_GETTER, "set": SUBKIND_SETTER, "willSet": SUBKIND_WILL_SET, "didSet": SUBKIND_DID_SET,
    "_read": SUBKIND_READ, "read": SUBKIND_READ, "_modify": SUBKIND_MODIFY, "modify": SUBKIND_MODIFY,
    "unsafeAddress": SUBKIND_ADDRESSOR, "unsafeMutableAddress": SUBKIND_MUTABLE_ADDRESSOR,
    "init": SUBKIND_INIT_ACCESSOR,
}
ACCESSOR_KEYWORDS = {
    SUBKIND_GETTER: ("get",), SUBKIND_SETTER: ("set",), SUBKIND_WILL_SET: ("willSet",),
    SUBKIND_DID_SET: ("didSet",), SUBKIND_READ: ("_read", "read"), SUBKIND_MODIFY: ("_modify", "modify"),
    SUBKIND_ADDRESSOR: ("unsafeAddress",), SUBKIND_MUTABLE_ADDRESSOR: ("unsafeMutableAddress",),
    SUBKIND_INIT_ACCESSOR: ("init",),
}
ROLE_DEFINITION = 1 << 1
ROLE_IMPLICIT = 1 << 8
RELATION_CHILD_OF = 1 << 9
RELATION_ACCESSOR_OF = 1 << 15

UNIT_CLASSES = ("system", "otherPackage", "otherModule", "stale", "duplicate", "variant", "kept")
READ_CLASSES = ("kept", "variant")
QUARANTINED_CLASSES = ("stale", "otherModule")
QUARANTINE_DIRECTORY = "swiftstats-quarantined-units"
STORE_DIRECTORY = "out"

# Reasons, in the order design section 3.4 applies them, and the ones
# criterion 1 doesn't accept (u4 asserts 0).
REASONS = ("top-level code", "plugin target", "inactive #if branch", "file changed during the scan",
           "target not built", "file not indexed", "disagreement", "unexplained")
FORBIDDEN_REASONS = ("target not built", "file not indexed", "file changed during the scan",
                     "disagreement", "unexplained")
REASON_ALIASES = {
    "toplevelcode": "top-level code", "toplevel": "top-level code",
    "plugintarget": "plugin target", "plugin": "plugin target",
    "inactiveifbranch": "inactive #if branch", "inactiveif": "inactive #if branch",
    "inactivebranch": "inactive #if branch", "inactive": "inactive #if branch",
    "filechangedduringthescan": "file changed during the scan", "filechanged": "file changed during the scan",
    "targetnotbuilt": "target not built", "filenotindexed": "file not indexed",
    "disagreement": "disagreement", "unexplained": "unexplained",
}
NO_RECORD_REASONS = ("requirement", "incompatibleKind", "outsideRecords")
DISAGREEMENT_KINDS = ("severalUSRs", "sharedUSR")
COLLISION_WARNING = "key shared by several declarations, disambiguated by location: "

# `swift demangle` accessor words, and the record accessor kinds they stand for.
DEMANGLED_ACCESSORS = {
    "getter": {"get"}, "setter": {"set"}, "willset": {"willSet"}, "didset": {"didSet"},
    "read": {"_read", "read"}, "read2": {"_read", "read"}, "modify": {"_modify", "modify"},
    "modify2": {"_modify", "modify"}, "unsafeAddressor": {"unsafeAddress"},
    "unsafeMutableAddressor": {"unsafeMutableAddress"}, "init": {"init"},
}
OPERATOR_CHARACTERS = set("/=-+!*%<>&|^~?.")
DECLARATION_MODIFIERS = MODIFIER_WORDS | {"class", "mutating", "nonmutating", "__consuming"}


def canonical_reason(value):
    if value is None:
        return None
    text = re.sub(r"[^a-z]", "", str(value).lower())
    return REASON_ALIASES.get(text, f"?{value}")


def c99_name(name):
    """SwiftPM's module name for a target name whose describe lacks c99name:
    non-alphanumerics to `_`, a leading digit prefixed with `_` (design 1.3)."""
    text = re.sub(r"[^A-Za-z0-9_]", "_", name)
    return "_" + text if text[:1].isdigit() else text


# ---- small text scanners (shared by the key and demangled-name readers)

OPENERS = {"(": ")", "[": "]", "<": ">", "{": "}"}


def generic_opener(text, index):
    """Whether the `<` at `index` opens a generic clause (it follows a name)."""
    return index > 0 and (text[index - 1].isalnum() or text[index - 1] in "_`>]?")


def balanced(text, start):
    """The index just past the bracket group opening at `start`. A `->`'s
    `>` closes nothing, and a `<` opens only after a name."""
    stack = [OPENERS[text[start]]]
    index = start + 1
    while index < len(text) and stack:
        char = text[index]
        if char in "([{":
            stack.append(OPENERS[char])
        elif char == "<" and generic_opener(text, index):
            stack.append(">")
        elif char == stack[-1] and not (char == ">" and text[index - 1] == "-"):
            stack.pop()
        index += 1
    return index


def split_top(text, separator):
    """`text` split at occurrences of `separator` outside brackets."""
    parts = []
    stack = []
    last = 0
    index = 0
    while index < len(text):
        char = text[index]
        if not stack and text.startswith(separator, index):
            parts.append(text[last:index])
            index += len(separator)
            last = index
            continue
        if char in "([{":
            stack.append(OPENERS[char])
        elif char == "<" and generic_opener(text, index):
            stack.append(">")
        elif stack and char == stack[-1] and not (char == ">" and text[index - 1] == "-"):
            stack.pop()
        index += 1
    parts.append(text[last:])
    return parts


def parameter_labels(group):
    """Argument labels of a parenthesized parameter list, `_` for none."""
    inner = group[1:-1].strip() if group.startswith("(") else group.strip()
    if not inner:
        return []
    labels = []
    for parameter in split_top(inner, ","):
        parameter = parameter.strip()
        match = re.match(r"(`[^`]+`|[A-Za-z_][A-Za-z0-9_]*)(\s+[A-Za-z_`][A-Za-z0-9_`]*)?\s*:(?!:)", parameter)
        labels.append(match.group(1).strip("`") if match else "_")
    return labels


# ---- the key side (u6)


def desugared(component):
    """The nominal type a sugared type path component spells: `[T]` is
    `Array`, `[K: V]` `Dictionary`, `T?` and `T!` `Optional` (a key keeps
    the source's spelling, design 3.6; the demangled tree names the type).
    Any other component is returned as given."""
    component = component.strip()
    if component.startswith("[") and balanced(component, 0) == len(component):
        return "Dictionary" if len(split_top(component[1:-1], ":")) > 1 else "Array"
    if len(component) > 1 and component[-1] in "?!":
        return "Optional"
    return component


def key_facts(record, by_key):
    """(type path, base name, labels, accessor kind) from a record's key, or a
    string saying why the key wasn't understood."""
    key = record["key"]
    module = record.get("module", "")
    rest = key[len(module) + 2:] if key.startswith(module + "::") else key
    segments = split_top(rest, " / ")
    last = segments[-1].strip()
    accessor = record.get("accessorKind") if record.get("kind") == "accessor" else None
    if last.startswith("{"):
        parent = by_key.get(record.get("parentKey"))
        if parent is None:
            return f"an accessor segment {last!r} with no parent record"
        facts = key_facts(parent, by_key)
        if isinstance(facts, str):
            return facts
        path, base, labels, _ = facts
        return path, base, labels, accessor
    parts = split_top(last, "::")
    declaration = parts[-1].strip()
    path = []
    if record.get("typePath"):
        # T0's own type path (the key's type part without an extension's
        # where clause, which can't be split from a nested type's name).
        path = [desugared(component).strip("`") for component in split_top(record["typePath"], ".")]
        parts = parts[-1:]
    for part in parts[:-1]:
        part = re.split(r"\s+where\s+", part.strip())[0]
        for component in split_top(part, "."):
            component = desugared(component)
            if "<" in component:
                component = component[:component.index("<")]
            path.append(component.strip("`"))
    words = declaration.split()
    while words and (words[0] in DECLARATION_MODIFIERS or words[0].startswith("@")):
        words.pop(0)
    declaration = " ".join(words)
    match = re.match(r"func\s+(`[^`]+`|[A-Za-z_][A-Za-z0-9_]*|[/=\-+!*%<>&|^~?.]+)", declaration)
    if match:
        base = match.group(1).strip("`")
        tail = declaration[match.end():]
        if tail.startswith("<"):
            tail = tail[balanced(tail, 0):]
        if not tail.startswith("("):
            return f"no parameter list in {declaration!r}"
        return path, base, parameter_labels(tail[:balanced(tail, 0)]), accessor
    match = re.match(r"(init|subscript)[?!]?(?=[(<])", declaration)
    if match:
        tail = declaration[match.end():]
        if tail.startswith("<"):
            tail = tail[balanced(tail, 0):]
        if not tail.startswith("("):
            return f"no parameter list in {declaration!r}"
        return path, match.group(1), parameter_labels(tail[:balanced(tail, 0)]), accessor
    if declaration.startswith("deinit"):
        return path, "deinit", [], accessor
    match = re.match(r"(?:var|let)\s+(`[^`]+`|[A-Za-z_][A-Za-z0-9_]*)", declaration)
    if match:
        return path, match.group(1).strip("`"), [], accessor
    return f"a declaration this check doesn't read: {declaration!r}"


# ---- the demangled side (u6): `swift demangle --tree-only`'s node tree

NOMINAL_NODES = {"Structure", "Class", "Enum", "Protocol", "TypeAlias", "OtherNominalType"}
ACCESSOR_NODES = {
    "Getter": "getter", "GlobalGetter": "getter", "Setter": "setter", "WillSet": "willset", "DidSet": "didset",
    "ReadAccessor": "read", "Read2Accessor": "read2", "ModifyAccessor": "modify", "Modify2Accessor": "modify2",
    "UnsafeAddressor": "unsafeAddressor", "UnsafeMutableAddressor": "unsafeMutableAddressor",
    "InitAccessor": "init",
}
CONSTRUCTOR_NODES = {"Constructor", "Allocator"}
DESTRUCTOR_NODES = {"Destructor", "Deallocator", "IsolatedDeallocator"}
CALLABLE_NODES = ({"Function", "Subscript", "Variable", "ExplicitClosure", "ImplicitClosure", "Static"}
                  | CONSTRUCTOR_NODES | DESTRUCTOR_NODES | set(ACCESSOR_NODES))
NAME_NODES = {"Identifier", "LocalDeclName", "PrivateDeclName", "PrefixOperator", "InfixOperator", "PostfixOperator"}
TREE_LINE = re.compile(r'kind=(\w+)(?:, text="(.*)")?(?:, index=(-?\d+))?$')


def parse_trees(text):
    """{mangled name: root node} from `swift demangle --tree-only` output;
    a node is {kind, text, children}, nested by two-space indentation."""
    trees = {}
    current = None
    stack = []
    for line in text.split("\n"):
        if line.startswith("Demangling for "):
            current = line[len("Demangling for "):].strip()
            stack = []
            continue
        match = TREE_LINE.match(line.strip())
        if current is None or not match:
            continue
        depth = (len(line) - len(line.lstrip(" "))) // 2
        node = {"kind": match.group(1), "text": match.group(2), "children": []}
        if depth == 0:
            trees[current] = node
            stack = [node]
        elif depth <= len(stack):
            stack = stack[:depth]
            stack[-1]["children"].append(node)
            stack.append(node)
    return trees


def child(node, *kinds):
    return next((c for c in node["children"] if c["kind"] in kinds), None)


def name_of(node):
    if node is None:
        return None
    if node["kind"] in ("Identifier", "PrefixOperator", "InfixOperator", "PostfixOperator"):
        return node["text"]
    identifiers = [c["text"] for c in node["children"] if c["kind"] == "Identifier"]
    return identifiers[-1] if identifiers else None


def tree_type_path(node):
    """Type path of a context node: nominal types from the outermost one
    declared at file scope or in a function (local types start the path), a
    module dropped; an extension's path is its extended type's."""
    kind = node["kind"]
    if kind == "Module" or kind in CALLABLE_NODES:
        return []
    if kind == "Type" and node["children"]:
        return tree_type_path(node["children"][0])
    if kind == "Extension" and len(node["children"]) > 1:
        return tree_type_path(node["children"][1])
    if kind.startswith("BoundGeneric") and node["children"]:
        return tree_type_path(node["children"][0])
    if kind in NOMINAL_NODES and len(node["children"]) > 1:
        return tree_type_path(node["children"][0]) + [name_of(node["children"][1])]
    return [f"?{kind}"]


def parameter_count(type_node):
    node = type_node
    while node is not None and node["kind"] != "FunctionType":
        if node["kind"] == "Type":
            node = node["children"][0] if node["children"] else None
        elif node["kind"] == "DependentGenericType":
            node = child(node, "Type")
        else:
            return None
    if node is None:
        return None
    arguments = child(node, "ArgumentTuple")
    inner = child(arguments, "Type") if arguments else None
    inner = inner["children"][0] if inner and inner["children"] else None
    if inner is None:
        return 0
    if inner["kind"] == "Tuple":
        return sum(1 for c in inner["children"] if c["kind"] == "TupleElement")
    return 1


def tree_labels(node):
    labels = child(node, "LabelList")
    if labels is not None and labels["children"]:
        return ["_" if c["kind"] == "FirstElementMarker" else c["text"] for c in labels["children"]]
    count = parameter_count(child(node, "Type"))
    return ["_"] * (count or 0)


def demangled_facts(tree):
    """(type path, base name, labels, accessor word) of a demangled USR's
    entity, or a string saying why it isn't a function-like one."""
    if tree is None or not tree["children"]:
        return "swift demangle gave no tree"
    entity = tree["children"][0]
    while entity["kind"] == "Static" and entity["children"]:
        entity = entity["children"][0]
    kind = entity["kind"]
    if not entity["children"]:
        return f"an empty {kind} node"
    context = entity["children"][0]
    if kind in ACCESSOR_NODES:
        storage = context
        if storage["kind"] == "Subscript":
            return tree_type_path(storage["children"][0]), "subscript", tree_labels(storage), ACCESSOR_NODES[kind]
        if storage["kind"] == "Variable":
            return tree_type_path(storage["children"][0]), name_of(child(storage, *NAME_NODES)), [], ACCESSOR_NODES[kind]
        return f"an accessor of a {storage['kind']}"
    if kind == "Function":
        return tree_type_path(context), name_of(child(entity, *NAME_NODES)), tree_labels(entity), None
    if kind in CONSTRUCTOR_NODES:
        return tree_type_path(context), "init", tree_labels(entity), None
    if kind in DESTRUCTOR_NODES:
        return tree_type_path(context), "deinit", [], None
    if kind == "Subscript":
        return tree_type_path(context), "subscript", tree_labels(entity), None
    return f"a {kind}, not a function-like entity"


def demangle_all(usrs, demangler, *flags):
    """`swift demangle <flags>` of `$s` + each `s:` USR's rest, in one run."""
    names = ["$s" + usr[2:] for usr in usrs]
    if not names:
        return ""
    command = ([demangler] if os.path.basename(demangler) == "swift-demangle" else [demangler, "demangle"]) + list(flags)
    result = subprocess.run(command, input="\n".join(names) + "\n", capture_output=True, text=True, timeout=600)
    if result.returncode != 0:
        fail(f"{' '.join(command)} exited {result.returncode}: {result.stderr.strip()[:300]}")
    return result.stdout


# ---- inputs


class Spellings:
    """Path prefixes a recording uses for real paths (`@ROOT@`, `@BUILD@`, ...)."""

    def __init__(self, pairs):
        self.pairs = sorted(pairs, key=lambda pair: -len(pair[0]))

    def restore(self, text):
        for token, real in self.pairs:
            if token and (text == token or text.startswith(token + "/")):
                return real + text[len(token):]
        return text


class UsrPackage:
    """The package: its real paths, the scan JSON (T0 facts and the index
    block), its own describe, and the units and records of the store."""

    def __init__(self, arguments):
        self.root = real_path(os.path.abspath(arguments.package), "the package")
        self.scratch = real_path(os.path.join(self.root, BUILD_DIRECTORY), "the build directory")
        with open(arguments.scan, encoding="utf-8") as handle:
            self.scan = json.load(handle)
        self.block = self.scan.get("index")
        self.records = self.scan.get("records", [])
        self.by_key = {r["key"]: r for r in self.records}
        self.records_by_file = defaultdict(list)
        for record in self.records:
            self.records_by_file[record["file"]].append(record)
        self.files = {f["path"]: f for f in self.scan.get("files", [])}
        self.scan_targets = {t["name"]: t for t in self.scan.get("targets", [])}
        self.children = defaultdict(list)
        for record in self.records:
            if record.get("parentKey"):
                self.children[record["parentKey"]].append(record)
        pairs = [(arguments.root_spelling, self.root), (arguments.build_spelling, self.scratch)]
        for item in arguments.spelling or []:
            token, _, path = item.partition("=")
            pairs.append((token, path))
        self.spellings = Spellings([(t, p) for t, p in pairs if t])
        # The describe's sources by real path, which `Described` fills.
        self.source_spellings = SourceSpellings(self.root)
        # outskirts' locations' spellings (`dead`): the scanned files, then
        # the describe's other sources, which `dead_mode` fills.
        self.entry_spellings = SourceSpellings(self.root)
        self.changed = set()
        for path, entry in self.files.items():
            full = os.path.join(self.root, path)
            if not os.path.isfile(full) or sha256_of(full) != entry.get("sha256"):
                self.changed.add(path)
        self.sources = {}

    def relative(self, path, target=None, spellings=None):
        """Package-relative NFC path of an absolute path: the spelling in
        `spellings` (default: the describe's sources) of the source whose
        real path it resolves to (in `target` when that target has one),
        else relative to the root as given, then resolved; None outside the
        root."""
        if not path:
            return None
        source = (spellings or self.source_spellings).source(path, target)
        if source is not None:
            return source
        for candidate in (unicodedata.normalize("NFC", path), resolved(path)):
            if is_under(candidate, self.root) and candidate != self.root:
                return candidate[len(self.root) + 1:]
        return None

    def source_bytes(self, path):
        if path not in self.sources:
            with open(os.path.join(self.root, path), "rb") as handle:
                self.sources[path] = handle.read().split(b"\n")
        return self.sources[path]


def toolchain_of(package_root, swift):
    """The toolchain of `swift -print-target-info` run in the package root
    (swiftly's proxy reads `.swift-version` there): its usr/lib/swift."""
    try:
        result = subprocess.run([swift, "-print-target-info"], cwd=package_root, capture_output=True,
                                text=True, timeout=120)
    except (OSError, subprocess.TimeoutExpired) as error:
        fail(f"{swift} -print-target-info didn't run: {error}")
    if result.returncode != 0:
        fail(f"{swift} -print-target-info exited {result.returncode}: {result.stderr.strip()[:300]}")
    try:
        resource = json.loads(result.stdout)["paths"]["runtimeResourcePath"]
    except (ValueError, KeyError) as error:
        fail(f"-print-target-info gave no paths.runtimeResourcePath: {error}")
    return os.path.normpath(resource)


def run_describe(package_root, swift_executable):
    """`swift package --scratch-path <tmp> describe --type json` in the
    package, its Package.resolved (bytes or absence) put back afterwards."""
    resolved = os.path.join(package_root, "Package.resolved")
    kept = open(resolved, "rb").read() if os.path.isfile(resolved) else None
    scratch = tempfile.mkdtemp(prefix="index-check-describe-")
    try:
        result = subprocess.run([swift_executable, "package", "--scratch-path", scratch, "describe", "--type", "json"],
                                cwd=package_root, capture_output=True, text=True, timeout=600,
                                stdin=subprocess.DEVNULL)
    finally:
        shutil.rmtree(scratch, ignore_errors=True)
        if kept is None:
            if os.path.exists(resolved):
                os.remove(resolved)
        elif not os.path.isfile(resolved) or open(resolved, "rb").read() != kept:
            with open(resolved, "wb") as handle:
                handle.write(kept)
    if result.returncode != 0:
        fail(f"describe exited {result.returncode}: {result.stderr.strip()[:300]}")
    return json.loads(result.stdout)


class Described:
    """The targets of a describe JSON: C99 names, sources, types, library products."""

    def __init__(self, describe, package):
        self.name = describe.get("name")
        self.targets = {}
        self.by_module = {}
        spelled = defaultdict(set)
        for spelling, name in describe_sources(describe, package.root, package.spellings.restore):
            spelled[name].add(spelling)
            package.source_spellings.add(spelling, name)
        for target in describe.get("targets", []):
            module = target.get("c99name") or c99_name(target["name"])
            sources = spelled[target["name"]]
            entry = {"name": target["name"], "module": module, "type": target.get("type"), "sources": sources}
            self.targets[target["name"]] = entry
            if module in self.by_module:
                fail(f"targets {self.by_module[module]['name']} and {target['name']} share the module name {module}")
            self.by_module[module] = entry
        self.library_targets = set()
        for product in describe.get("products", []):
            kind = product.get("type")
            if isinstance(kind, dict) and "library" in kind:
                self.library_targets.update(product.get("targets", []))
        # Local path dependencies' folders (step 4a's adopted deviation from
        # design 2.3's rule 2: a nested path dependency is another package).
        self.dependency_roots = []
        for dependency in describe.get("dependencies", []):
            if dependency.get("type") == "fileSystem" and dependency.get("path"):
                location = package.spellings.restore(dependency["path"])
                if not os.path.isabs(location):
                    location = os.path.join(package.root, location)
                try:
                    self.dependency_roots.append(real_path(location, "a path dependency"))
                except ReadError:
                    self.dependency_roots.append(location)


# ---- units and records


class UnitReader:
    """Unit headers and records, from the store through this script's ctypes
    reader, or from a recorded dump (`--reader`)."""

    def __init__(self, package, arguments):
        self.package = package
        self.store = None
        self.library = None
        self.dump_records = None
        self.quarantine_names = None
        self.units = []
        if arguments.reader:
            with open(arguments.reader, encoding="utf-8") as handle:
                dump = json.load(handle)
            self.dump_records = {r["name"]: r for r in dump["records"]}
            for unit in dump["units"]:
                main = package.spellings.restore(unit["mainFile"])
                records = []
                for name in unit["records"]:
                    record = self.dump_records.get(name)
                    paths = [record["file"]] + record.get("otherFiles", []) if record else []
                    paths = [package.spellings.restore(p) for p in paths]
                    records.append((name, main if main in paths or not paths else paths[0]))
                self.units.append(self.unit_entry(unit, main, records, "store"))
            self.system_known = False
            return
        self.system_known = True
        store_path = real_path(os.path.abspath(arguments.index_store or os.path.join(package.scratch, STORE_DIRECTORY)),
                               "the index store")
        if not os.path.isdir(os.path.join(store_path, "v5", "units")):
            fail(f"{store_path} holds no v5/units")
        self.store_path = store_path
        self.library = Library(arguments.library)
        self.store = Store(self.library, store_path)
        for name in self.store.unit_names():
            self.units.append(self.read_unit(self.store, name, "store"))
        self.read_quarantine()

    def unit_entry(self, unit, main, records, location, modules=None):
        # moduleDependencies: the unit's dependencies of kind unit (module,
        # isSystem), for u7's module edges.
        return {"name": unit["name"], "module": unit["module"], "mainFile": main, "triple": unit["target"],
                "isSystem": unit["isSystem"], "modified": (unit["modified"]["seconds"], unit["modified"]["nanoseconds"]),
                "records": records, "location": location,
                "moduleDependencies": modules if modules is not None else unit.get("moduleDependencies", [])}

    def read_unit(self, store, name, location):
        unit, records, modules = store.unit(name)
        main = real_path(unit["mainFile"], f"unit {name}'s main file") if not unit["isSystem"] else unit["mainFile"]
        paths = []
        for record, path in records:
            paths.append((record, real_path(path, f"record {record}'s file") if path and not unit["isSystem"] else path))
        return self.unit_entry(unit, main, paths, location, modules)

    def read_quarantine(self):
        """The units the scan moved out of the store (design 2.3), read
        through a temporary store view: their unit files plus the records."""
        directory = os.path.join(self.package.scratch, QUARANTINE_DIRECTORY)
        self.quarantine_names = []
        if not os.path.isdir(directory):
            return
        self.quarantine_names = sorted(n for n in os.listdir(directory) if not n.startswith("."))
        if not self.quarantine_names:
            return
        view = tempfile.mkdtemp(prefix="index-check-quarantine-")
        try:
            os.makedirs(os.path.join(view, "v5", "units"))
            os.symlink(os.path.join(self.store_path, "v5", "records"), os.path.join(view, "v5", "records"))
            for name in self.quarantine_names:
                os.symlink(os.path.join(directory, name), os.path.join(view, "v5", "units", name))
            store = Store(self.library, view)
            try:
                for name in self.quarantine_names:
                    self.units.append(self.read_unit(store, name, "quarantine"))
            finally:
                store.close()
        finally:
            shutil.rmtree(view, ignore_errors=True)

    def occurrences(self, record_name):
        if self.dump_records is not None:
            record = self.dump_records.get(record_name)
            if record is None:
                raise ReadError(f"the recording holds no record {record_name}")
            return record["occurrences"]
        return self.store.occurrences(record_name)

    def close(self):
        if self.store is not None:
            self.store.close()


def classify_units(units, package, described):
    """Each unit's class, design section 2.3 (first that applies)."""
    classes = {}
    pending = []
    for unit in units:
        main = unit["mainFile"]
        target = described.by_module.get(unit["module"])
        relative = package.relative(main, target and target["name"]) if os.path.isabs(main or "x") else None
        first = relative.split("/")[0] if relative else None
        if unit["isSystem"]:
            classes[unit["name"]] = "system"
        elif (not main or relative is None or is_under(main, package.scratch) or first in (".build", ".swiftstats")
              or any(is_under(main, root) for root in described.dependency_roots)):
            classes[unit["name"]] = "otherPackage"
        elif unit["module"] not in described.by_module:
            classes[unit["name"]] = "otherModule"
        elif not os.path.exists(main) or not package.source_spellings.is_source(main, target["name"]):
            classes[unit["name"]] = "stale"
        else:
            pending.append(unit)
    groups = defaultdict(list)
    for unit in pending:
        groups[(unit["module"], unit["mainFile"], unit["triple"])].append(unit)
    survivors = []
    for group in groups.values():
        newest = max(group, key=lambda u: (u["modified"], u["name"]))
        for unit in group:
            if unit is not newest:
                classes[unit["name"]] = "duplicate"
        survivors.append(newest)
    triples = defaultdict(set)
    for unit in survivors:
        triples[(unit["module"], unit["mainFile"])].add(unit["triple"])
    for unit in survivors:
        several = len(triples[(unit["module"], unit["mainFile"])]) > 1
        classes[unit["name"]] = "variant" if several else "kept"
    return classes


# ---- the join


def function_like(occurrence):
    kind, subkind = occurrence["kind"], occurrence["subkind"]
    return (kind in FUNCTION_KINDS or kind in (KIND_CONSTRUCTOR, KIND_DESTRUCTOR)
            or (kind in PROPERTY_KINDS and subkind == SUBKIND_SUBSCRIPT))


def compatible(record, occurrence):
    """Design section 3.2, primary assignments only (the subscript getter is
    the secondary case, handled apart)."""
    kind, subkind = occurrence["kind"], occurrence["subkind"]
    record_kind = record["kind"]
    if record_kind == "func":
        return kind in FUNCTION_KINDS and (subkind == SUBKIND_NONE or subkind in OPERATOR_SUBKINDS)
    if record_kind == "init":
        return kind == KIND_CONSTRUCTOR
    if record_kind == "deinit":
        return kind == KIND_DESTRUCTOR
    if record_kind == "subscript":
        return kind in PROPERTY_KINDS and subkind == SUBKIND_SUBSCRIPT
    if record_kind == "accessor":
        wanted = ACCESSOR_SUBKINDS.get(record.get("accessorKind") or "get")
        return kind in FUNCTION_KINDS and subkind == wanted
    return False


def holds(record, line, column):
    start, end = range_of(record)
    return start <= (line, column) <= end


def innermost(records):
    return min(records, key=lambda r: ((-range_of(r)[0][0], -range_of(r)[0][1]), range_of(r)[1], r["key"]))


class UsrJoin:
    """Design sections 2.3 and 3 reimplemented over this script's read."""

    def __init__(self, package, described, reader, log_text):
        self.package = package
        self.described = described
        self.reader = reader
        self.classes = classify_units(reader.units, package, described)
        self.units = sorted(reader.units, key=lambda u: u["name"])
        self.read_units = [u for u in self.units if self.classes[u["name"]] in READ_CLASSES]
        self.log_text = log_text
        self.read_records()
        self.join()
        self.reasons()
        self.collisions()

    # Units -> occurrences per package file.
    def read_records(self):
        self.occurrences_by_file = defaultdict(list)
        self.records_read = set()
        self.occurrence_count = 0
        done = set()
        cache = {}
        for unit in self.read_units:
            target = self.described.by_module.get(unit["module"])
            for record, path in unit["records"]:
                if record not in cache:
                    cache[record] = self.reader.occurrences(record)
                    self.records_read.add(record)
                    self.occurrence_count += len(cache[record])
                relative = self.package.relative(path, target and target["name"])
                if relative is None or (record, relative) in done:
                    continue
                done.add((record, relative))
                self.occurrences_by_file[relative].extend(cache[record])
        self.kept_files_by_module = defaultdict(set)
        for unit in self.read_units:
            target = self.described.by_module.get(unit["module"])
            relative = self.package.relative(unit["mainFile"], target and target["name"])
            self.kept_files_by_module[unit["module"]].add(relative)

    def join(self):
        package = self.package
        self.definitions_in = defaultdict(list)   # every definition, any kind, implicit too
        primaries = defaultdict(dict)             # record key -> usr -> definition
        pending = []                              # (getter definition, subscript record)
        self.no_record = []
        self.implicit = set()
        joined = set()
        seen = set()
        for path in sorted(self.occurrences_by_file):
            # USRs this file defines as children of a protocol (design 3.5's
            # requirement test, as corrected by review C6: a property or
            # subscript requirement's accessors name the property).
            protocol_members = {o["usr"] for o in self.occurrences_by_file[path]
                                if o["roles"] & ROLE_DEFINITION
                                and any(rel["roles"] & RELATION_CHILD_OF and rel["kind"] == KIND_PROTOCOL
                                        for rel in o["relations"])}
            for occurrence in self.occurrences_by_file[path]:
                if not occurrence["roles"] & ROLE_DEFINITION:
                    continue
                identity = (path, occurrence["line"], occurrence["column"], occurrence["usr"],
                            occurrence["kind"], occurrence["subkind"], occurrence["roles"])
                if identity in seen:
                    continue  # the same definition read through a variant unit
                seen.add(identity)
                self.definitions_in[path].append((occurrence["line"], occurrence["column"]))
                if path not in package.files or path in package.changed or not function_like(occurrence):
                    continue
                definition = {"file": path, "line": occurrence["line"], "column": occurrence["column"],
                              "usr": occurrence["usr"], "name": occurrence["name"], "kind": occurrence["kind"],
                              "subkind": occurrence["subkind"], "relations": occurrence["relations"]}
                if occurrence["roles"] & ROLE_IMPLICIT:
                    self.implicit.add((path, occurrence["line"], occurrence["column"], occurrence["usr"]))
                    continue
                holding = [r for r in package.records_by_file.get(path, [])
                           if holds(r, occurrence["line"], occurrence["column"])]
                if not holding:
                    requirement = any((rel["roles"] & RELATION_CHILD_OF and rel["kind"] == KIND_PROTOCOL)
                                      or (rel["roles"] & (RELATION_CHILD_OF | RELATION_ACCESSOR_OF)
                                          and rel["kind"] in PROPERTY_KINDS and rel["usr"] in protocol_members)
                                      for rel in occurrence["relations"])
                    self.no_record.append(dict(definition, subreason="requirement" if requirement else "outsideRecords",
                                               key=None))
                    continue
                record = innermost(holding)
                if compatible(record, occurrence):
                    primaries[record["key"]].setdefault(occurrence["usr"], definition)
                    joined.add((path, occurrence["line"], occurrence["column"], occurrence["usr"]))
                elif (record["kind"] == "subscript" and occurrence["subkind"] == SUBKIND_GETTER
                      and occurrence["kind"] in FUNCTION_KINDS):
                    pending.append((definition, record))
                else:
                    self.no_record.append(dict(definition, subreason="incompatibleKind", key=record["key"]))
        # Disagreements (design 3.5).
        self.disagreements = []
        holders = defaultdict(set)
        for key, usrs in primaries.items():
            for usr in usrs:
                holders[usr].add(key)
        self.primary = {}
        self.in_disagreement = set()
        for key in sorted(primaries):
            usrs = primaries[key]
            if len(usrs) > 1:
                self.in_disagreement.add(key)
                for usr in sorted(usrs):
                    definition = usrs[usr]
                    self.disagreements.append({"kind": "severalUSRs", "key": key, "usr": usr,
                                               "file": definition["file"], "line": definition["line"],
                                               "column": definition["column"]})
        for usr in sorted(holders):
            if len(holders[usr]) > 1:
                for key in sorted(holders[usr]):
                    self.in_disagreement.add(key)
                    definition = primaries[key][usr]
                    self.disagreements.append({"kind": "sharedUSR", "key": key, "usr": usr,
                                               "file": definition["file"], "line": definition["line"],
                                               "column": definition["column"]})
        for key, usrs in primaries.items():
            if key not in self.in_disagreement:
                self.primary[key] = next(iter(usrs))
        self.primary_definitions = {key: next(iter(usrs.values())) for key, usrs in primaries.items()
                                    if key in self.primary}
        # Secondary accessor USRs (design 3.3).
        self.secondary = {}
        self.secondary_definitions = {}
        self.several_secondaries = []
        for definition, record in pending:
            # The subscript's own accessors only: explicit ones, named
            # `subscript`; a local computed property's getter nested in its
            # body has the subscript as parent too, but its own name (C8).
            has_accessors = any(child["kind"] == "accessor" and child.get("name") == "subscript"
                                for child in self.package.children.get(record["key"], []))
            names_primary = any(rel["roles"] & RELATION_ACCESSOR_OF and rel["usr"] == self.primary.get(record["key"])
                                for rel in definition["relations"])
            if not has_accessors and names_primary:
                previous = self.secondary.get(record["key"])
                if previous is not None and previous != definition["usr"]:
                    self.several_secondaries.append(record["key"])
                    continue
                self.secondary[record["key"]] = definition["usr"]
                self.secondary_definitions[record["key"]] = definition
                joined.add((definition["file"], definition["line"], definition["column"], definition["usr"]))
            else:
                self.no_record.append(dict(definition, subreason="incompatibleKind", key=record["key"]))
        self.joined = joined
        self.joined_definitions = [(key, d, "primary") for key, usrs in sorted(primaries.items())
                                   for d in usrs.values()]
        self.joined_definitions += [(key, d, "secondary") for key, d in sorted(self.secondary_definitions.items())]
        self.no_record.sort(key=lambda d: (d["file"], d["line"], d["column"], d["usr"]))

    def reasons(self):
        """Design section 3.4: the first reason that applies."""
        modules_any = {u["module"] for u in self.units}
        self.reason = {}
        targets = self.package.scan_targets
        for record in self.package.records:
            key = record["key"]
            if key in self.primary:
                self.reason[key] = None
                continue
            target = self.described.targets.get(record.get("module")) or {}
            scan_target = targets.get(record.get("module")) or {}
            module = target.get("module") or c99_name(record.get("module", ""))
            target_type = target.get("type") or scan_target.get("type")
            path = record["file"]
            definitions = self.definitions_in.get(path, [])
            if record["kind"] == "topLevel":
                reason = "top-level code"
            elif target_type == "plugin":
                reason = "plugin target"
            elif (record.get("ifConfig") and path in self.kept_files_by_module.get(module, set())
                  and not any(holds(record, line, column) for line, column in definitions)):
                # Only in a file a read unit names: with no unit read for
                # it, no definition is no evidence (review C9).
                reason = "inactive #if branch"
            elif path in self.package.changed:
                reason = "file changed during the scan"
            elif module not in modules_any and not self.log_compiles(module):
                reason = "target not built"
            elif self.kept_files_by_module.get(module) and path not in self.kept_files_by_module[module]:
                reason = "file not indexed"
            elif key in self.in_disagreement:
                reason = "disagreement"
            else:
                reason = "unexplained"
            self.reason[key] = reason

    def log_compiles(self, module):
        if self.log_text is None:
            return False
        return re.search(r"-module-name\s+" + re.escape(module) + r"(\s|$)", self.log_text) is not None

    def collisions(self):
        """Records whose keys a collision suffix tells apart (the scan's
        warnings name the collided keys) and whose USRs differ."""
        collided = [w["message"][len(COLLISION_WARNING):] for w in self.package.scan.get("warnings", [])
                    if str(w.get("message", "")).startswith(COLLISION_WARNING)]
        self.collision_groups = []
        for original in sorted(set(collided)):
            members = []
            for record in self.package.records:
                key = record["key"]
                if not key.startswith(original):
                    continue
                suffix = key[len(original):]
                file_part = "" if " @ " in original else " @ " + record["file"]
                if re.fullmatch(re.escape(file_part) + r"(:\d+){0,2}", suffix):
                    members.append(record)
            usrs = {self.primary.get(r["key"]) for r in members} - {None}
            if len(usrs) > 1:
                self.collision_groups.append({"key": original,
                                              "records": [{"key": r["key"], "usr": self.primary.get(r["key"])}
                                                          for r in sorted(members, key=lambda r: r["key"])]})

    # Figures.
    def unit_rows(self):
        rows = []
        for unit in self.units:
            target = self.described.by_module.get(unit["module"])
            main = self.package.relative(unit["mainFile"], target and target["name"]) or unit["mainFile"]
            rows.append({"name": unit["name"], "target": target["name"] if target else None,
                         "module": unit["module"], "mainFile": main,
                         "triple": unit["triple"], "class": self.classes[unit["name"]], "location": unit["location"]})
        return rows

    def class_counts(self):
        counts = Counter(self.classes.values())
        return {name: counts.get(name, 0) for name in UNIT_CLASSES}

    def definitions(self):
        return {"joined": len(self.joined), "implicit": len(self.implicit), "secondary": len(self.secondary),
                "objc": sum(1 for usr in self.primary.values() if usr.startswith("c:"))}

    def scopes(self):
        """Roll-up scopes as the scan's T0 roll-ups name them."""
        scopes = defaultdict(list)
        for record in self.package.records:
            scopes[("module", record.get("module"))].append(record)
            scopes[("project", "production" if record.get("role") == "production" else "tests")].append(record)
        return scopes

    def rollup(self, records):
        reasons = Counter(self.reason[r["key"]] for r in records if self.reason[r["key"]] is not None)
        return {"withUSR": sum(1 for r in records if r["key"] in self.primary),
                "withoutUSR": dict(sorted(reasons.items())),
                "disagreements": sum(1 for r in records if self.reason[r["key"]] == "disagreement")}


# ---- u3 and u6


def name_token_problem(join, key, definition, how):
    """Why the source bytes at a joined definition aren't its name token, or None."""
    lines = join.package.source_bytes(definition["file"])
    line, column = definition["line"], definition["column"]
    if line < 1 or line > len(lines):
        return f"line {line} is past the file's end"
    text = lines[line - 1][column - 1:]
    kind, subkind = definition["kind"], definition["subkind"]
    if how == "secondary":
        wanted = ("{",)
    elif kind == KIND_CONSTRUCTOR:
        wanted = ("init",)
    elif kind == KIND_DESTRUCTOR:
        wanted = ("deinit",)
    elif kind in PROPERTY_KINDS:
        wanted = ("subscript",)
    elif subkind in ACCESSOR_KEYWORDS:
        wanted = ACCESSOR_KEYWORDS[subkind] + (("{",) if subkind == SUBKIND_GETTER else ())
    else:
        base = definition["name"].split("(")[0]
        wanted = (base, f"`{base}`")
    for token in wanted:
        encoded_token = token.encode("utf-8")
        if text.startswith(encoded_token):
            following = text[len(encoded_token):len(encoded_token) + 1]
            if token[-1:].isalnum() or token[-1:] == "_":
                if following and (following.isalnum() or following == b"_"):
                    continue
            return None
    return f"{definition['file']}:{line}:{column} reads {text[:24].decode('utf-8', 'replace')!r}, wanted one of {list(wanted)}"


def demangle_problem(record, facts_key, facts_demangled, secondary=False):
    if isinstance(facts_key, str):
        return f"key not read: {facts_key}"
    if isinstance(facts_demangled, str):
        return f"demangled USR not read: {facts_demangled}"
    key_path, key_base, key_labels, key_accessor = facts_key
    path, base, labels, accessor = facts_demangled
    problems = []
    if [p.strip("`") for p in path] != [p.strip("`") for p in key_path]:
        problems.append(f"type path {path} vs key {key_path}")
    if base.strip("`") != key_base.strip("`"):
        problems.append(f"base name {base!r} vs key {key_base!r}")
    operator = key_base[:1] in OPERATOR_CHARACTERS
    if operator:
        if len(labels) != len(key_labels):
            problems.append(f"{len(labels)} operands vs key {len(key_labels)}")
    elif labels != key_labels:
        problems.append(f"labels {labels} vs key {key_labels}")
    wanted = "get" if secondary else key_accessor
    if wanted is None and accessor is not None:
        problems.append(f"accessor {accessor} on a {record['kind']} record")
    elif wanted is not None and wanted not in DEMANGLED_ACCESSORS.get(accessor or "", set()):
        problems.append(f"accessor {accessor} vs key {wanted}")
    return "; ".join(problems) or None


# ---- comparison with the scan JSON


def flattened(items):
    """Rows of a list whose items may nest lists of dicts: each nested dict
    inherits its parents' scalar fields."""
    rows = []

    def walk(item, inherited):
        scalars = dict(inherited)
        nested = []
        for name, value in item.items():
            if isinstance(value, list) and value and all(isinstance(v, dict) for v in value):
                nested.append(value)
            elif isinstance(value, dict) and name in ("position", "location", "place"):
                scalars.update(value)
            elif not isinstance(value, (list, dict)):
                scalars[name] = value
        if nested:
            for group in nested:
                for child in group:
                    walk(child, scalars)
        else:
            rows.append(scalars)

    for item in items if isinstance(items, list) else []:
        if isinstance(item, dict):
            walk(item, {})
    return rows


def path_of(package, value):
    if not isinstance(value, str):
        return value
    restored = package.spellings.restore(value)
    if os.path.isabs(restored):
        return package.relative(unicodedata.normalize("NFC", restored)) or restored
    return unicodedata.normalize("NFC", restored)


def scan_records(package, block):
    rows = lookup(block, "records")
    out = {}
    if not isinstance(rows, list):
        return None
    for row in rows:
        out[row.get("key")] = (row.get("usr"), row.get("usrAccessor", row.get("secondaryUSR")),
                               canonical_reason(row.get("reason", row.get("usrReason"))))
    return out


def compare_index(verdict, join, problems_u3, problems_u6):
    package = join.package
    block = package.block
    scan = package.scan
    run = next((c for c in scan.get("collectors", []) if c.get("name") == "index"), None)
    verdict.section("the scan JSON's index block against this reimplementation")
    verdict.info(f"index collector: {run.get('state') if run else 'absent'}"
                 + (f" ({run.get('reason')})" if run and run.get("reason") else ""))
    verdict.result("the index collector ran", bool(run) and run.get("state") == "ran",
                   run.get("state") if run else "absent")
    if not isinstance(block, dict):
        verdict.result("the scan JSON has an index block", False, "absent")
        return

    def same(name, mine, theirs):
        if theirs is MISSING:
            verdict.result(name, False, f"mine {mine}; the scan JSON has no such value")
        else:
            verdict.result(name, theirs == mine, f"mine {mine}, scan {theirs}")

    # u1: units.
    verdict.section("u1 units: the same unit set and classes")
    mine_rows = {row["name"]: row for row in join.unit_rows()}
    listed = lookup(block, "store.units", "units")
    if not isinstance(listed, list):
        verdict.result("the scan lists its units (index.store.units)", False, "absent")
        listed = []
    theirs_rows = {}
    for row in listed:
        theirs_rows[row.get("name")] = {
            "target": row.get("target"), "mainFile": path_of(package, row.get("mainFile", row.get("file", row.get("path")))),
            "triple": row.get("triple"), "class": row.get("class")}
    differences = []
    for name, row in sorted(theirs_rows.items(), key=lambda pair: str(pair[0])):
        own = mine_rows.get(name)
        if own is None:
            differences.append(f"{name}: listed by the scan, not in this check's store read")
            continue
        target_ok = row["target"] == own["target"] or (own["class"] == "otherModule"
                                                       and row["target"] in (None, "", own["module"]))
        if not target_ok or row["mainFile"] != own["mainFile"] or row["triple"] != own["triple"] \
                or row["class"] != own["class"]:
            differences.append(f"{name}: scan {row}, mine {{'target': {own['target']!r}, 'mainFile': "
                               f"{own['mainFile']!r}, 'triple': {own['triple']!r}, 'class': {own['class']!r}}}")
    for name, own in sorted(mine_rows.items()):
        if own["class"] in READ_CLASSES and name not in theirs_rows:
            differences.append(f"{name}: {own['class']} here, not listed by the scan")
    listed_classes = Counter(row["class"] for row in theirs_rows.values())
    for name in ("duplicate", "stale", "otherModule"):
        own = {n for n, r in mine_rows.items() if r["class"] == name}
        if listed_classes.get(name):
            missing = sorted(own - set(theirs_rows))
            if missing:
                differences.append(f"{name} units not listed although the scan lists that class: {missing}")
    verdict.result("unit list (name, target, main file, triple, class) equals this check's",
                   not differences, f"{len(theirs_rows)} listed, {len(mine_rows)} read here "
                   f"({', '.join(f'{k} {v}' for k, v in join.class_counts().items())})")
    verdict.listing(differences)
    counts = join.class_counts()
    for name in UNIT_CLASSES:
        if name == "system" and not join.reader.system_known:
            verdict.info("system: not known from a recorded dump (it lists non-system units only)")
            continue
        capital = name[0].upper() + name[1:]
        same(f"units {name}", counts[name], lookup(block, f"store.counts.{name}", f"store.unitCounts.{name}",
                                                  f"store.{name}", f"store.units{capital}", f"counts.{name}",
                                                  f"units{capital}"))
    quarantined_mine = sorted(n for n, c in join.classes.items() if c in QUARANTINED_CLASSES)
    value = lookup(block, "store.counts.quarantined", "store.unitCounts.quarantined", "store.quarantined",
                   "store.unitsQuarantined", "unitsQuarantined")
    if isinstance(value, list):
        same("quarantined units (the scan's list)", quarantined_mine, sorted(value))
    else:
        same("units quarantined", len(quarantined_mine), value)
    if join.reader.quarantine_names is not None:
        remaining = sorted(u["name"] for u in join.units
                           if u["location"] == "store" and join.classes[u["name"]] in QUARANTINED_CLASSES)
        verdict.result("no stale or otherModule unit remains in out/v5/units", not remaining,
                       f"{len(remaining)} remain" if remaining else "")
        verdict.listing(remaining)
        listed_quarantine = sorted(n for n, r in theirs_rows.items() if r["class"] in QUARANTINED_CLASSES)
        verdict.result(f"{QUARANTINE_DIRECTORY}/ holds exactly this check's stale and otherModule units",
                       join.reader.quarantine_names == quarantined_mine,
                       f"{len(join.reader.quarantine_names)} there, {len(quarantined_mine)} classed here")
        verdict.listing(f"only there: {n}" for n in sorted(set(join.reader.quarantine_names) - set(quarantined_mine)))
        verdict.listing(f"only classed here: {n}" for n in sorted(set(quarantined_mine) - set(join.reader.quarantine_names)))
        if listed_quarantine or not isinstance(value, list):
            verdict.result("the quarantine holds exactly the scan's stale and otherModule units",
                           join.reader.quarantine_names == listed_quarantine or not listed_quarantine
                           and not join.reader.quarantine_names,
                           f"{len(listed_quarantine)} listed by the scan")
    else:
        verdict.info("quarantine: not checked (a recorded dump has no store directory)")
    for name, mine_value in (("records", len(join.records_read)), ("occurrences", join.occurrence_count)):
        theirs = lookup(block, f"store.{name}", f"store.counts.{name}", name if name == "occurrences" else "store.records")
        if theirs is MISSING or isinstance(theirs, list):
            verdict.info(f"{name} read: mine {mine_value}; the scan JSON gives none to compare")
        else:
            same(f"{name} read (each record once)", mine_value, theirs)
    library = lookup(block, "libraryModules", "store.libraryModules")
    if library is not MISSING:
        own_library = sorted(t for t in join.described.library_targets
                             if join.kept_files_by_module.get(join.described.targets.get(t, {}).get("module")))
        same("libraryModules (library-product targets with kept units)", own_library, sorted(library))

    # u2: USRs.
    verdict.section("u2 USRs: primary and secondary per record")
    theirs = scan_records(package, block)
    if theirs is None:
        verdict.result("the scan lists every record (index.records)", False, "absent")
        theirs = {}
    differences = []
    for record in package.records:
        key = record["key"]
        own = (join.primary.get(key), join.secondary.get(key))
        if key not in theirs:
            differences.append(f"{key}: not listed by the scan (mine {own})")
            continue
        if theirs[key][:2] != own:
            differences.append(f"{key}: scan {theirs[key][:2]}, mine {own}")
    extra = sorted(set(theirs) - set(package.by_key), key=str)
    differences += [f"{key}: listed by the scan, no such record" for key in extra]
    verdict.result("primary USR and secondary accessor USR of every record", not differences,
                   f"{len(join.primary)} with a USR here, {sum(1 for v in theirs.values() if v[0])} in the scan; "
                   f"{len(join.secondary)} secondary here, {sum(1 for v in theirs.values() if v[1])} in the scan")
    verdict.listing(differences)
    definitions = join.definitions()
    for name, paths in (("joined", ("definitions.joined", "definitionsJoined")),
                        ("implicit", ("definitions.implicit", "definitions.implicitSkipped", "definitionsImplicit")),
                        ("secondary", ("definitions.secondary", "definitions.secondaryUSRs", "secondaryUSRs")),
                        ("objc", ("definitions.objc", "definitions.objcUSRs", "objcUSRs"))):
        same(f"definitions {name}", definitions[name], lookup(block, *paths))

    # u4: reasons.
    verdict.section("u4 reasons")
    differences = []
    for record in package.records:
        key = record["key"]
        if key in theirs and theirs[key][2] != join.reason[key]:
            differences.append(f"{key}: scan {theirs[key][2]!r}, mine {join.reason[key]!r}")
    verdict.result("reason of every record without a USR (and none for the others)", not differences,
                   ", ".join(f"{k} {v}" for k, v in sorted(Counter(r for r in join.reason.values() if r).items()))
                   or "no record without a USR")
    verdict.listing(differences)

    # u5: lists.
    verdict.section("u5 disagreements, definitions with no record, collisions")
    own = {(d["kind"], d["key"], d["usr"]) for d in join.disagreements}
    rows = lookup(block, "disagreements")
    their_rows = flattened(rows) if isinstance(rows, list) else []
    theirs_set = {(r.get("kind"), r.get("key"), r.get("usr")) for r in their_rows}
    verdict.result("disagreements (kind, key, USR)", rows is not MISSING and own == theirs_set,
                   f"{len(own)} mine, {len(theirs_set)} scan" if rows is not MISSING else "absent")
    verdict.listing(f"only mine: {item}" for item in sorted(own - theirs_set, key=str))
    verdict.listing(f"only the scan's: {item}" for item in sorted(theirs_set - own, key=str))
    positions = {(d["kind"], d["key"], d["usr"]): (d["file"], d["line"], d["column"]) for d in join.disagreements}
    wrong = [f"{(r.get('kind'), r.get('key'), r.get('usr'))}: scan {(path_of(package, r.get('file')), r.get('line'), r.get('column'))}, "
             f"mine {positions[(r.get('kind'), r.get('key'), r.get('usr'))]}"
             for r in their_rows if (r.get("kind"), r.get("key"), r.get("usr")) in positions and "line" in r
             and (path_of(package, r.get("file")), r.get("line"), r.get("column"))
             != positions[(r.get("kind"), r.get("key"), r.get("usr"))]]
    if wrong:
        verdict.result("disagreement positions", False, f"{len(wrong)} differ")
        verdict.listing(wrong)
    own_none = {(d["subreason"], d["usr"], d["file"], d["line"], d["column"], d["key"]) for d in join.no_record}
    rows = lookup(block, "withoutRecord", "definitionsWithoutRecord")
    their_none = {(r.get("subreason", r.get("subReason", r.get("reason"))), r.get("usr"),
                   path_of(package, r.get("file")), r.get("line"), r.get("column"), r.get("key"))
                  for r in flattened(rows)} if isinstance(rows, list) else set()
    verdict.result("definitions with no record (sub-reason, USR, place, record for incompatibleKind)",
                   rows is not MISSING and own_none == their_none,
                   f"{len(own_none)} mine, {len(their_none)} scan" if rows is not MISSING else "absent")
    verdict.listing(f"only mine: {item}" for item in sorted(own_none - their_none, key=str))
    verdict.listing(f"only the scan's: {item}" for item in sorted(their_none - own_none, key=str))
    own_collisions = {(member["key"], member["usr"]) for group in join.collision_groups
                      for member in group["records"] if member["usr"]}
    rows = lookup(block, "collisions")
    their_collisions = {(r.get("key"), r.get("usr")) for r in flattened(rows) if r.get("usr")} \
        if isinstance(rows, list) else set()
    verdict.result("collisions the USR separates (key, USR)", rows is not MISSING and own_collisions == their_collisions,
                   f"{len(own_collisions)} mine, {len(their_collisions)} scan" if rows is not MISSING else "absent")
    verdict.listing(f"only mine: {item}" for item in sorted(own_collisions - their_collisions, key=str))
    verdict.listing(f"only the scan's: {item}" for item in sorted(their_collisions - own_collisions, key=str))

    # Files and roll-ups.
    verdict.section("files hashed after the build, and the roll-ups")
    rows = lookup(block, "files")
    if not isinstance(rows, list):
        verdict.result("the scan lists the files hashed after the build (index.files)", False, "absent")
    else:
        hashed = {path_of(package, r.get("path")): r.get("sha256") for r in rows}
        differences = [p for p in sorted(set(hashed) | set(package.files), key=str) if p not in hashed or p not in package.files]
        verdict.result("index.files lists every scanned file", not differences, f"{len(hashed)} listed, "
                       f"{len(package.files)} scanned")
        verdict.listing(differences)
        stale = [p for p, digest in sorted(hashed.items(), key=lambda pair: str(pair[0]))
                 if p in package.files and digest != sha256_of(os.path.join(package.root, p))]
        verdict.result("each index.files hash is the file's bytes now", not stale, f"{len(stale)} differ" if stale else "")
        verdict.listing(stale)
    differences = []
    lacking = []
    scopes = join.scopes()
    for entry in scan.get("rollups", []):
        scope = (entry.get("scope"), entry.get("name"))
        index = entry.get("index")
        if not isinstance(index, dict):
            lacking.append(f"{scope[0]} {scope[1]}")
            continue
        own_rollup = join.rollup(scopes.get(scope, []))
        their_reasons = {canonical_reason(k): v for k, v in (index.get("withoutUSR") or {}).items() if v}
        theirs_rollup = {"withUSR": index.get("withUSR"), "withoutUSR": dict(sorted(their_reasons.items())),
                         "disagreements": index.get("disagreements", 0)}
        if theirs_rollup != own_rollup:
            differences.append(f"{scope[0]} {scope[1]}: scan {theirs_rollup}, mine {own_rollup}")
    verdict.result("every roll-up scope has index.withUSR, index.withoutUSR and index.disagreements", not lacking,
                   f"lacking in {', '.join(lacking)}" if lacking else "")
    verdict.result("roll-ups index.withUSR, index.withoutUSR.<reason>, index.disagreements", not differences,
                   f"{len(scan.get('rollups', []))} scopes")
    verdict.listing(differences)


def report_own(verdict, join, problems_u3, problems_u6, objc_skipped, checked_u6):
    verdict.section("units, by this check's own filter (design 2.3)")
    counts = join.class_counts()
    verdict.info(", ".join(f"{name} {count}" for name, count in counts.items())
                 + ("" if join.reader.system_known else " (system: unknown in a dump)"))
    quarantined = sorted(n for n, c in join.classes.items() if c in QUARANTINED_CLASSES)
    if quarantined:
        verdict.info("stale and otherModule: " + ", ".join(
            f"{n} ({join.classes[n]}, {next(u['location'] for u in join.units if u['name'] == n)})" for n in quarantined))
    variants = sorted(n for n, c in join.classes.items() if c in ("variant", "duplicate"))
    if variants:
        verdict.info("variant and duplicate: " + ", ".join(f"{n} ({join.classes[n]})" for n in variants))
    verdict.info(f"records read {len(join.records_read)}, occurrences {join.occurrence_count}")
    verdict.section("the join, by this check's own rules (design 3)")
    records = join.package.records
    with_usr = sum(1 for r in records if r["key"] in join.primary)
    verdict.info(f"records with a USR: {with_usr} of {len(records)}; secondary accessor USRs {len(join.secondary)}; "
                 f"c: USRs {join.definitions()['objc']}")
    verdict.info("definitions: " + ", ".join(f"{k} {v}" for k, v in join.definitions().items()))
    reasons = Counter(r for r in join.reason.values() if r)
    verdict.info("without a USR: " + (", ".join(f"{k} {v}" for k, v in sorted(reasons.items())) or "none"))
    verdict.listing(f"{key}: {join.reason[key]} ({join.package.by_key[key]['file']}:"
                    f"{join.package.by_key[key]['range']['start']['line']})"
                    for key in sorted(k for k, r in join.reason.items() if r))
    verdict.info(f"disagreements {len(join.disagreements)}; definitions with no record "
                 + ", ".join(f"{s} {sum(1 for d in join.no_record if d['subreason'] == s)}" for s in NO_RECORD_REASONS)
                 + f"; collisions the USR separates {len(join.collision_groups)}")
    verdict.listing(f"{d['subreason']}: {d['name']} {d['file']}:{d['line']}:{d['column']}"
                    + (f" (innermost {d['key']})" if d["key"] else "") for d in join.no_record)
    verdict.listing(f"collision {g['key']}: " + "; ".join(f"{m['key']} = {m['usr']}" for m in g["records"])
                    for g in join.collision_groups)
    if join.several_secondaries:
        verdict.info(f"subscripts with several getter definitions: {join.several_secondaries}")

    verdict.section("u4 reasons criterion 1 doesn't accept")
    for name in FORBIDDEN_REASONS:
        verdict.result(f"{name}: 0", reasons.get(name, 0) == 0, str(reasons.get(name, 0)))
    verdict.section("u5 definitions with no record: expected protocol requirements only")
    for name in ("incompatibleKind", "outsideRecords"):
        count = sum(1 for d in join.no_record if d["subreason"] == name)
        verdict.result(f"{name}: 0", count == 0, str(count))
    verdict.section("u3 every joined definition sits on its name token")
    verdict.result("source bytes at each joined definition begin with its name token", not problems_u3,
                   f"{len(join.joined_definitions)} definitions checked")
    verdict.listing(problems_u3)
    verdict.section("u6 swift demangle of each s: USR agrees with its record's key")
    verdict.result("type path, base name, argument labels and accessor kind", not problems_u6,
                   f"{checked_u6} USRs checked, {objc_skipped} c: USRs skipped")
    verdict.listing(problems_u6)


def own_usr_figures(join):
    return {
        "units": join.unit_rows(),
        "unitCounts": join.class_counts(),
        "quarantined": sorted(n for n, c in join.classes.items() if c in QUARANTINED_CLASSES),
        "recordsRead": len(join.records_read),
        "occurrences": join.occurrence_count,
        "records": [{"key": r["key"], "usr": join.primary.get(r["key"]), "usrAccessor": join.secondary.get(r["key"]),
                     "reason": join.reason[r["key"]]} for r in sorted(join.package.records, key=lambda r: r["key"])],
        "definitions": join.definitions(),
        "disagreements": join.disagreements,
        "withoutRecord": [{k: d[k] for k in ("subreason", "usr", "name", "kind", "subkind", "file", "line", "column", "key")}
                          for d in join.no_record],
        "collisions": join.collision_groups,
        "rollups": [{"scope": scope, "name": name, "index": join.rollup(records)}
                    for (scope, name), records in sorted(join.scopes().items(), key=lambda pair: str(pair[0]))],
        "changedFiles": sorted(join.package.changed),
    }


# --------------------------------------------------------------------------
# u7: references, referrers, witnesses, module edges, type ownership, type
# fan-in, USR type cycles, family references (design section 4)
#
# Written from design sections 4.1-4.4, 9.1 and 9.2 and the research's
# measured facts (indexstore.md sections 5-7, scope-signals.md sections 2-3),
# not from SwiftStats' code: the container rule, the role routing, the
# witness and requirement reading, ownership, the type graph and Tarjan's
# algorithm are this script's own. It reads the same occurrences u1-u6 read
# (kept and variant units' records, each record once per file).

ROLE_REFERENCE = 1 << 2
ROLE_READ = 1 << 3
ROLE_WRITE = 1 << 4
RELATION_BASE_OF = 1 << 10
RELATION_OVERRIDE_OF = 1 << 11
RELATION_CALLED_BY = 1 << 13
RELATION_EXTENDED_BY = 1 << 14
RELATION_CONTAINED_BY = 1 << 16
PROPERTY_LOCAL = 1 << 7
KIND_ENUM = 5
KIND_STRUCT = 6
KIND_CLASS = 7
KIND_EXTENSION = 9
NOMINAL_KINDS = {KIND_ENUM, KIND_STRUCT, KIND_CLASS, KIND_PROTOCOL}
# A TypeRecord's kind and the index kinds it is compatible with (actors are
# classes in the index, design 4.3).
TYPE_RECORD_KINDS = {"struct": {KIND_STRUCT}, "class": {KIND_CLASS}, "actor": {KIND_CLASS}, "enum": {KIND_ENUM},
                     "protocol": {KIND_PROTOCOL}}
# Design 4.1: which accessors a read and a write reference count for.
READING_ACCESSORS = {"get", "_read", "read", "unsafeAddress"}
WRITING_ACCESSORS = {"set", "_modify", "modify", "unsafeMutableAddress", "willSet", "didSet"}
DESIGN_REFERENCES_RULE = (
    "distinct containers (calledBy or containedBy; else baseOf or extendedBy; else by position: top-level "
    "statement lines, innermost record, type, file) of non-family references, implicit included; a property's read "
    "references count for its reading accessors and write references for its writing ones; a requirement's "
    "references count for its witnesses (any occurrence with overrideOf); split by the container's target: same "
    "production target, other production targets, test targets")
DESIGN_TYPES_RULE = (
    "package-declared nominal types by USR; an extension's members belong to the package type its head extends, "
    "none for an external type; fan-in by distinct referring types or free functions per target; cycles over "
    "production types without type-to-nested-type edges")
TEST_REFERRERS_KEPT = 5


def accessor_owner_key(record):
    """A property accessor's key without its ` { <accessor> }` part (as the
    family rule of PRD 6.6 names a computed property's family)."""
    accessor = record.get("accessorKind")
    key = record["key"]
    if accessor:
        marker = f" {{ {accessor} }}"
        index = key.rfind(marker)
        if index >= 0:
            return key[:index] + key[index + len(marker):]
    return key


def families_of(records):
    """{record key: family id}: a record with its nested records (followed
    through parent keys), or a computed property's accessors (an accessor
    record with no parent, grouped by its key without the accessor part and
    its file); the id is the root's key, or that property key (PRD 6.6's
    families, as the existing FamilyIndex names them)."""
    first = {}
    for index, record in enumerate(records):
        first.setdefault(record["key"], index)

    def property_accessor(record):
        return record["kind"] == "accessor" and not record.get("parentKey")

    groups = defaultdict(list)
    for index in range(len(records)):
        current = index
        seen = {index}
        while True:
            parent = records[current].get("parentKey")
            parent_index = first.get(parent) if parent else None
            if parent_index is None or parent_index in seen:
                break
            seen.add(parent_index)
            current = parent_index
        top = records[current]
        group = ("property", accessor_owner_key(top), top["file"]) if property_accessor(top) else ("record", current)
        groups[group].append(index)
    family = {}
    for indices in groups.values():
        members = sorted(indices, key=lambda i: (records[i]["key"], range_of(records[i])[0][0]))
        root = next((i for i in members if not records[i].get("parentKey") and not property_accessor(records[i])), None)
        identifier = records[root]["key"] if root is not None else accessor_owner_key(records[members[0]])
        for index in indices:
            family.setdefault(records[index]["key"], identifier)
    return family


def tarjan(nodes, edges):
    """Strongly connected components of a directed graph (iterative Tarjan)."""
    index_of = {}
    low = {}
    on_stack = set()
    stack = []
    components = []
    counter = 0
    for start in nodes:
        if start in index_of:
            continue
        work = [(start, iter(sorted(edges.get(start, ()))))]
        index_of[start] = low[start] = counter
        counter += 1
        stack.append(start)
        on_stack.add(start)
        while work:
            node, successors = work[-1]
            advanced = False
            for successor in successors:
                if successor not in index_of:
                    index_of[successor] = low[successor] = counter
                    counter += 1
                    stack.append(successor)
                    on_stack.add(successor)
                    work.append((successor, iter(sorted(edges.get(successor, ())))))
                    advanced = True
                    break
                if successor in on_stack:
                    low[node] = min(low[node], index_of[successor])
            if advanced:
                continue
            work.pop()
            if work:
                low[work[-1][0]] = min(low[work[-1][0]], low[node])
            if low[node] == index_of[node]:
                component = []
                while True:
                    member = stack.pop()
                    on_stack.discard(member)
                    component.append(member)
                    if member == node:
                        break
                components.append(component)
    return components


def requirement_context(tree):
    """Whether a demangled USR's entity is declared in a protocol (a
    requirement), through `Static` and accessor nodes."""
    if tree is None or not tree["children"]:
        return False
    entity = tree["children"][0]
    while entity["kind"] in ("Static",) or entity["kind"] in ACCESSOR_NODES:
        if not entity["children"]:
            return False
        entity = entity["children"][0]
    return bool(entity["children"]) and entity["children"][0]["kind"] == "Protocol"


class Coupling:
    """Design section 4 reimplemented over the join's read (check u7)."""

    def __init__(self, join, demangler, local_containers="symbol", requirements="protocol"):
        self.join = join
        self.package = join.package
        self.described = join.described
        self.local_containers = local_containers
        self.requirement_reading = requirements
        self.demangler = demangler
        self.records = self.package.records
        self.family = families_of(self.records)
        self.types_t0 = self.package.scan.get("types", [])
        self.types_by_file = defaultdict(list)
        for record in self.types_t0:
            self.types_by_file[record["file"]].append(record)
        self.notes = Counter()
        self.file_targets()
        self.collect()
        self.place_types()
        self.index_records()
        self.find_requirements()
        self.references()
        self.edges()
        self.cycles()

    # ---- targets and files

    def file_targets(self):
        """Each read unit's main file -> its target name (C99 module -> describe)."""
        self.target_of_file = {}
        for unit in self.join.read_units:
            target = self.described.by_module.get(unit["module"])
            relative = self.package.relative(unit["mainFile"], target and target["name"])
            if relative is not None and target is not None:
                self.target_of_file.setdefault(relative, target["name"])

    def target_type(self, target):
        entry = self.described.targets.get(target) or {}
        scan_target = self.package.scan_targets.get(target) or {}
        return entry.get("type") or scan_target.get("type")

    def is_test_target(self, target):
        return self.target_type(target) == "test"

    # ---- one pass over the occurrences

    def collect(self):
        package = self.package
        self.child_of = {}              # usr -> the childOf relation of its definition
        self.definition_targets = defaultdict(set)
        self.type_definitions = []      # (path, line, column, usr, kind)
        self.extension_definitions = {}  # extension usr -> (path, line, column)
        self.overriding = defaultdict(set)   # overridden usr -> symbols of occurrences overriding it
        self.overriding_symbols = set()
        self.extended = {}              # extension usr -> the usr its head names
        self.reference_list = []        # (path, occurrence), distinct, in unchanged scanned files
        seen = set()
        for path in sorted(self.join.occurrences_by_file):
            target = self.target_of_file.get(path)
            for occurrence in self.join.occurrences_by_file[path]:
                identity = (path, occurrence["line"], occurrence["column"], occurrence["usr"], occurrence["roles"],
                            occurrence["kind"], occurrence["subkind"],
                            tuple((r["roles"], r["usr"]) for r in occurrence["relations"]))
                if identity in seen:
                    continue  # the same occurrence read through another unit's record
                seen.add(identity)
                roles = occurrence["roles"]
                usr = occurrence["usr"]
                for relation in occurrence["relations"]:
                    if relation["roles"] & RELATION_OVERRIDE_OF:
                        self.overriding[relation["usr"]].add(usr)
                        self.overriding_symbols.add(usr)
                    if relation["roles"] & RELATION_EXTENDED_BY and roles & ROLE_REFERENCE:
                        self.extended.setdefault(relation["usr"], usr)
                if roles & ROLE_DEFINITION:
                    if target is not None:
                        self.definition_targets[usr].add(target)
                    parent = next((r for r in occurrence["relations"] if r["roles"] & RELATION_CHILD_OF), None)
                    if parent is not None and (usr not in self.child_of or not roles & ROLE_IMPLICIT):
                        self.child_of[usr] = parent
                    unchanged = path in package.files and path not in package.changed
                    if unchanged and occurrence["kind"] in NOMINAL_KINDS and not roles & ROLE_IMPLICIT:
                        self.type_definitions.append((path, occurrence["line"], occurrence["column"], usr,
                                                      occurrence["kind"]))
                    if occurrence["kind"] == KIND_EXTENSION:
                        self.extension_definitions.setdefault(usr, (path, occurrence["line"], occurrence["column"]))
                if roles & ROLE_REFERENCE:
                    if path not in package.files:
                        self.notes["references in unscanned files (skipped)"] += 1
                    elif path in package.changed:
                        self.notes["references in files changed during the scan (skipped)"] += 1
                    else:
                        self.reference_list.append((path, occurrence))

    # ---- types (design 4.3)

    def scoped_paths(self, path):
        if not hasattr(self, "_scoped"):
            self._scoped = {}
        if path not in self._scoped:
            with open(os.path.join(self.package.root, path), encoding="utf-8", errors="replace") as handle:
                source = handle.read()
            self._scoped[path] = file_scoped_paths(self.types_by_file[path], source)
        return self._scoped[path]

    def type_identity(self, record):
        """(module, typePath, typeFile): typeFile the file for a file-scoped
        (private or fileprivate) type, '' otherwise (local types included)."""
        if record.get("isLocal"):
            return (record["module"], record["name"], "")
        scoped = scoped_by(record["name"], self.scoped_paths(record["file"]))
        return (record["module"], record["name"], record["file"] if scoped else "")

    def innermost_type_record(self, path, line, column, kinds=None):
        holding = [t for t in self.types_by_file.get(path, []) if holds(t, line, column)
                   and (kinds is None or t["kind"] in kinds)]
        if not holding:
            return None
        return min(holding, key=lambda t: ((-range_of(t)[0][0], -range_of(t)[0][1]), range_of(t)[1], t["name"]))

    def place_types(self):
        """Package nominal types by USR, placed on the innermost type record
        holding the definition when its kind is compatible; extensions on the
        innermost extension record holding theirs."""
        self.types = {}                 # usr -> {"identity", "record", "production"}
        self.type_of_record = {}        # id(type record) -> type usr
        self.extension_of_record = {}   # id(extension record) -> extension usr
        self.unplaced_types = []
        for path, line, column, usr, kind in sorted(self.type_definitions):
            if usr in self.types:
                continue
            record = self.innermost_type_record(path, line, column)
            if record is None or kind not in TYPE_RECORD_KINDS.get(record["kind"], set()):
                self.unplaced_types.append(f"{path}:{line}:{column} {usr} (innermost type record: "
                                           f"{record['kind'] + ' ' + record['name'] if record else 'none'})")
                continue
            target = record["module"]
            self.types[usr] = {"identity": self.type_identity(record), "record": record,
                               "production": not self.is_test_target(target)}
            self.type_of_record.setdefault(id(record), usr)
        for usr, (path, line, column) in sorted(self.extension_definitions.items()):
            if path not in self.package.files or path in self.package.changed:
                continue
            record = self.innermost_type_record(path, line, column, {"extension"})
            if record is not None:
                self.extension_of_record.setdefault(id(record), usr)
        self.by_identity = defaultdict(list)
        for usr, entry in self.types.items():
            self.by_identity[entry["identity"]].append(usr)
        self.identity_collisions = {identity: usrs for identity, usrs in self.by_identity.items() if len(usrs) > 1}
        self.owner_memo = {}

    def owner(self, usr):
        """A declaration's owning package type (design 4.3): itself for a
        package nominal type; for an extension, the package type its head
        names (none for an external type); otherwise its definition's childOf
        chain followed to the first of those; none at the end of the chain."""
        if usr in self.owner_memo:
            return self.owner_memo[usr]
        chain = []
        current = usr
        result = None
        while current is not None and current not in chain:
            if current in self.owner_memo:
                result = self.owner_memo[current]
                break
            chain.append(current)
            if current in self.types:
                result = current
                break
            if current in self.extension_definitions:
                head = self.extended.get(current)
                result = head if head in self.types else None
                break
            parent = self.child_of.get(current)
            current = parent["usr"] if parent else None
        for item in chain:
            self.owner_memo[item] = result
        return result

    def type_record_owner(self, record):
        """The owning type of a type record: the type placed on it, or for an
        extension record its extension's owner."""
        if record is None:
            return None
        if record["kind"] == "extension":
            extension = self.extension_of_record.get(id(record))
            return self.owner(extension) if extension else None
        return self.type_of_record.get(id(record))

    def nested(self, first, second):
        """Whether one type is nested in the other, either way: same target,
        the inner typePath the outer's plus '.', and the outer's typeFile ''
        or the inner's (design 4.3: a private type nested in a plain one is
        file-scoped while the outer type isn't)."""
        def inside(inner, outer):
            module_i, path_i, file_i = inner
            module_o, path_o, file_o = outer
            return (module_i == module_o and file_o in ("", file_i)
                    and path_i.startswith(path_o + "."))
        identity_a = self.types[first]["identity"]
        identity_b = self.types[second]["identity"]
        return inside(identity_a, identity_b) or inside(identity_b, identity_a)

    # ---- records by USR, accessors, witnesses, requirements (design 4.1)

    def index_records(self):
        join = self.join
        self.record_by_usr = {}
        for key, usr in join.primary.items():
            self.record_by_usr.setdefault(usr, key)
        for key, usr in join.secondary.items():
            self.record_by_usr.setdefault(usr, key)
        self.accessors_of = defaultdict(list)   # property usr -> [(accessor record key, accessor kind)]
        self.property_of = {}
        for record in self.records:
            key = record["key"]
            if record["kind"] != "accessor" or key not in join.primary_definitions:
                continue
            for relation in join.primary_definitions[key]["relations"]:
                if relation["roles"] & RELATION_ACCESSOR_OF:
                    self.accessors_of[relation["usr"]].append((key, record.get("accessorKind") or "get"))
                    self.property_of.setdefault(key, relation["usr"])
        self.witness = {}
        for record in self.records:
            key = record["key"]
            if key not in join.primary:
                self.witness[key] = None
                continue
            usrs = {join.primary[key], join.secondary.get(key), self.property_of.get(key)} - {None}
            self.witness[key] = bool(usrs & self.overriding_symbols)

    def find_requirements(self):
        """Protocol requirements among the USRs some occurrence overrides: a
        package definition whose childOf is a protocol, an `s:` USR whose
        demangled context is a protocol, a `c:` USR naming one with `(pl)`
        (design 4.1 as written: `--requirements protocol`). `--requirements
        package` keeps only requirements of protocols the package declares
        (defined in a read unit); `--requirements all` takes every overridden
        USR, class methods included."""
        self.requirements = set()
        to_demangle = []
        for usr in sorted(self.overriding):
            parent = self.child_of.get(usr)
            if self.requirement_reading == "all" or (parent is not None and parent["kind"] == KIND_PROTOCOL):
                self.requirements.add(usr)
            elif self.requirement_reading == "package":
                continue
            elif usr.startswith("c:"):
                if "(pl)" in usr:
                    self.requirements.add(usr)
            elif usr.startswith("s:"):
                to_demangle.append(usr)
        if to_demangle:
            trees = parse_trees(demangle_all(to_demangle, self.demangler, "--tree-only"))
            for usr in to_demangle:
                if requirement_context(trees.get("$s" + usr[2:])):
                    self.requirements.add(usr)
        self.overridden_not_requirements = set(self.overriding) - self.requirements

    # ---- containers and targets

    def statement_lines(self, path):
        if not hasattr(self, "_statements"):
            self._statements = {}
        if path not in self._statements:
            with open(os.path.join(self.package.root, path), encoding="utf-8", errors="replace") as handle:
                self._statements[path] = statement_lines(handle.read())
        return self._statements[path]

    def container(self, path, occurrence):
        """Design 4.1's container, first that applies: calledBy, else
        containedBy; else baseOf or extendedBy; else by position. Returns
        (identity, name, target, owner, record key or None)."""
        relations = occurrence["relations"]
        symbol = next((r for r in relations if r["roles"] & RELATION_CALLED_BY), None)
        symbol = symbol or next((r for r in relations if r["roles"] & RELATION_CONTAINED_BY), None)
        if symbol is None:
            symbol = next((r for r in relations if r["roles"] & (RELATION_BASE_OF | RELATION_EXTENDED_BY)), None)
        file_target = self.target_of_file.get(path)
        if symbol is not None:
            usr, name, properties = symbol["usr"], symbol["name"], symbol["properties"]
            if self.local_containers == "enclosing":
                walked = set()
                while usr not in self.record_by_usr and properties & PROPERTY_LOCAL and usr not in walked:
                    walked.add(usr)
                    parent = self.child_of.get(usr)
                    if parent is None:
                        break
                    usr, name, properties = parent["usr"], parent["name"], parent["properties"]
            elif usr not in self.record_by_usr and properties & PROPERTY_LOCAL:
                self.notes["references whose container is a local symbol that isn't a record (kept as a symbol)"] += 1
            key = self.record_by_usr.get(usr)
            if key is not None:
                return self.record_container(key)
            return ("symbol", usr), name, file_target, self.owner(usr), None
        line, column = occurrence["line"], occurrence["column"]
        holding = []
        for record in self.package.records_by_file.get(path, []):
            if holds(record, line, column):
                if record["kind"] == "topLevel" and line not in self.statement_lines(path):
                    continue
                holding.append(record)
        top_level = [r for r in holding if r["kind"] == "topLevel"]
        if top_level:
            self.notes["references placed by position: top-level code"] += 1
            return self.record_container(innermost(top_level)["key"])
        if holding:
            self.notes["references placed by position: innermost record"] += 1
            return self.record_container(innermost(holding)["key"])
        record = self.innermost_type_record(path, line, column)
        if record is not None:
            self.notes["references placed by position: innermost type"] += 1
            identity = self.type_identity(record)
            return ("type",) + identity, record["name"], file_target, self.type_record_owner(record), None
        self.notes["references placed by position: file"] += 1
        return ("file", path), path, file_target, None, None

    def record_container(self, key):
        record = self.package.by_key[key]
        usr = self.join.primary.get(key)
        if usr is not None:
            owner = self.owner(usr)
        else:
            start = range_of(record)[0]
            owner = self.type_record_owner(self.innermost_type_record(record["file"], start[0], start[1]))
        return ("record", key), key, record.get("module"), owner, key

    def targets(self, usr, roles):
        """(record key, via) pairs a reference to `usr` counts for (design
        4.1): the record holding it as primary or secondary USR; a
        property's accessor records by role; a protocol requirement's
        witnesses (the same two ways, via `requirement`)."""
        out = set()

        def direct(symbol, via):
            key = self.record_by_usr.get(symbol)
            if key is not None:
                out.add((key, via))
            read, write = roles & ROLE_READ, roles & ROLE_WRITE
            for accessor_key, accessor in self.accessors_of.get(symbol, []):
                if (not read and not write) or (read and accessor in READING_ACCESSORS) \
                        or (write and accessor in WRITING_ACCESSORS):
                    out.add((accessor_key, via))

        direct(usr, "direct")
        if usr in self.requirements:
            for witness in sorted(self.overriding[usr]):
                direct(witness, "requirement")
        return out

    # ---- the pass over references

    def references(self):
        join = self.join
        self.referrers = defaultdict(lambda: {"sameModule": set(), "otherModules": set(), "tests": set()})
        self.test_names = defaultdict(dict)
        self.family_references = set()
        self.family_type_references = set()
        self.type_referrers = defaultdict(lambda: {"sameModule": set(), "otherModules": set(), "tests": set()})
        self.type_edges = defaultdict(set)
        self.class_override_references = 0
        production_family = {}
        for record in self.records:
            role_production = record.get("role") == "production"
            family = self.family[record["key"]]
            production_family[family] = production_family.get(family, True) and role_production
        self.production_family = production_family
        for path, occurrence in self.reference_list:
            usr = occurrence["usr"]
            identity, name, target, owner, container_key = self.container(path, occurrence)
            container_test = self.is_test_target(target) if target else False
            if usr in self.overridden_not_requirements:
                self.class_override_references += 1
            # Referrers and family references.
            for key, via in self.targets(usr, occurrence["roles"]):
                if container_key is not None and self.family[container_key] == self.family[key]:
                    continue
                record = self.package.by_key[key]
                if container_test:
                    bucket = "tests"
                    self.test_names[key][identity] = name
                elif target == record.get("module"):
                    bucket = "sameModule"
                else:
                    bucket = "otherModules"
                self.referrers[key][bucket].add(identity)
                if container_key is not None:
                    source, destination = self.family[container_key], self.family[key]
                    if production_family.get(source) and production_family.get(destination):
                        self.family_references.add((source, destination, via))
            # Types: fan-in, edges, family-type references.
            referenced = usr if usr in self.types else self.owner(usr)
            if referenced is None:
                continue
            entry = self.types[referenced]
            if container_key is not None and production_family.get(self.family[container_key]):
                self.family_type_references.add((self.family[container_key],) + entry["identity"])
            if entry["production"]:
                if container_test:
                    self.type_referrers[referenced]["tests"].add(identity)
                elif owner != referenced:
                    referrer = ("type", owner) if owner is not None else identity
                    bucket = "sameModule" if target == entry["record"]["module"] else "otherModules"
                    self.type_referrers[referenced][bucket].add(referrer)
            if (owner is not None and owner != referenced and not container_test and owner in self.types
                    and self.types[owner]["production"] and entry["production"]
                    and not self.nested(owner, referenced)):
                self.type_edges[owner].add(referenced)

    # ---- module edges (design 4.2)

    def edges(self):
        package_modules = self.described.by_module
        references = defaultdict(set)
        for path, occurrence in self.reference_list:
            source = self.target_of_file.get(path)
            if source is None:
                continue
            for destination in self.definition_targets.get(occurrence["usr"], ()):
                if destination != source:
                    references[(source, destination)].add((path, occurrence["line"], occurrence["column"],
                                                           occurrence["usr"], occurrence["roles"]))
        files = defaultdict(set)
        for unit in self.join.read_units:
            target = package_modules.get(unit["module"])
            relative = self.package.relative(unit["mainFile"], target and target["name"])
            if target is None or relative is None:
                continue
            for dependency in unit.get("moduleDependencies", []):
                if dependency.get("isSystem"):
                    continue
                module = dependency["module"]
                other = package_modules.get(module)
                destination = ("package", other["name"]) if other else ("dependency", module)
                if destination[1] != target["name"]:
                    files[(target["name"],) + destination].add(relative)
        self.module_edges = {}
        for (source, destination), found in references.items():
            self.module_edges[(source, destination)] = {"kind": "package", "references": len(found), "files": 0}
        for (source, kind, destination), found in files.items():
            if kind == "package":
                edge = self.module_edges.setdefault((source, destination),
                                                    {"kind": "package", "references": 0, "files": 0})
                edge["files"] = len(found)
            else:
                self.module_edges[(source, destination)] = {"kind": "dependency", "references": None,
                                                            "files": len(found)}

    # ---- cycles (design 4.3)

    def cycles(self):
        production = sorted((u for u, e in self.types.items() if e["production"]),
                            key=lambda u: self.types[u]["identity"])
        components = [c for c in tarjan(production, self.type_edges) if len(c) >= 2]
        ordered = []
        for component in components:
            members = sorted(self.types[u]["identity"] for u in component)
            ordered.append(members)
        ordered.sort(key=lambda members: (-len(members), members[0]))
        self.cycle_members = ordered
        self.cycle_of = {}
        for number, members in enumerate(ordered, start=1):
            for identity in members:
                self.cycle_of[identity] = number
        ascending = sorted(ordered, key=lambda members: (len(members), members[0]))
        self.cycle_of_ascending = {identity: number for number, members in enumerate(ascending, start=1)
                                   for identity in members}

    # ---- figures

    def record_figures(self, key):
        if self.join.primary.get(key) is None:
            return None
        found = self.referrers.get(key) or {"sameModule": set(), "otherModules": set(), "tests": set()}
        names = sorted(self.test_names.get(key, {}).values())
        return {"sameModule": len(found["sameModule"]), "otherModules": len(found["otherModules"]),
                "tests": len(found["tests"]), "testReferrers": names[:TEST_REFERRERS_KEPT]}

    def type_rows(self, ascending=False):
        """{identity: [row, ...]} for production types: one row each, several
        only where types share an identity (local types of one name)."""
        numbers = self.cycle_of_ascending if ascending else self.cycle_of
        rows = defaultdict(list)
        for usr, entry in self.types.items():
            if not entry["production"]:
                continue
            found = self.type_referrers.get(usr) or {"sameModule": set(), "otherModules": set(), "tests": set()}
            rows[entry["identity"]].append({"usr": usr, "sameModule": len(found["sameModule"]),
                                            "otherModules": len(found["otherModules"]), "tests": len(found["tests"]),
                                            "cycle": numbers.get(entry["identity"])})
        return {identity: sorted(found, key=lambda row: str(sorted(row.items()))) for identity, found in rows.items()}

    def scope_rollups(self):
        """index.typeCycles, index.typesInCycles and index.moduleEdges per T0
        scope, as this check reads them: a module scope counts the cycles with
        a member in it, its types in cycles and the edges from it; project
        production all cycles, all types in cycles and the edges from
        production targets; project tests no cycles and the edges from test
        targets."""
        modules = ({r.get("module") for r in self.records} | {t["module"] for t in self.types_t0}
                   | {source for (source, _) in self.module_edges})
        out = {}
        for module in modules:
            members = [i for c in self.cycle_members for i in c if i[0] == module]
            cycles = sum(1 for c in self.cycle_members if any(i[0] == module for i in c))
            edges = sum(1 for (source, _) in self.module_edges if source == module)
            out[("module", module)] = {"typeCycles": cycles, "typesInCycles": len(members), "moduleEdges": edges}
        production_edges = sum(1 for (source, _) in self.module_edges if not self.is_test_target(source))
        test_edges = sum(1 for (source, _) in self.module_edges if self.is_test_target(source))
        out[("project", "production")] = {"typeCycles": len(self.cycle_members),
                                          "typesInCycles": sum(len(c) for c in self.cycle_members),
                                          "moduleEdges": production_edges}
        out[("project", "tests")] = {"typeCycles": 0, "typesInCycles": 0, "moduleEdges": test_edges}
        return out

    def figures(self):
        return {
            "records": [{"key": r["key"], "witness": self.witness[r["key"]],
                         "references": self.record_figures(r["key"])}
                        for r in sorted(self.records, key=lambda r: r["key"])],
            "moduleEdges": [{"from": s, "to": d, **e} for (s, d), e in sorted(self.module_edges.items())],
            "types": [{"module": i[0], "typePath": i[1], "typeFile": i[2], **row}
                      for i, found in sorted(self.type_rows().items()) for row in found],
            "cycles": [[{"module": i[0], "typePath": i[1], "typeFile": i[2]} for i in members]
                       for members in self.cycle_members],
            "familyReferences": [{"from": s, "to": d, "via": v} for s, d, v in sorted(self.family_references)],
            "familyTypeReferences": [{"family": f, "module": m, "typePath": p, "typeFile": t}
                                     for f, m, p, t in sorted(self.family_type_references)],
            "rollups": [{"scope": s, "name": n, "index": v}
                        for (s, n), v in sorted(self.scope_rollups().items(), key=lambda pair: str(pair[0]))],
            "notes": dict(sorted(self.notes.items())),
        }


def report_coupling_own(verdict, coupling):
    verdict.section("u7 references, types, cycles and family references, by this check's own rules (design 4)")
    verdict.info(f"reading: local containers {coupling.local_containers!r}; requirements "
                 f"{coupling.requirement_reading!r} ("
                 + {"protocol": "every protocol requirement expands to its witnesses, design 4.1 as written",
                    "package": "only requirements of package-declared protocols expand",
                    "all": "every overridden USR expands, class methods included"}[coupling.requirement_reading]
                 + ")")
    external = sorted(u for u in coupling.requirements if u not in coupling.child_of)
    expanded = Counter(occurrence["usr"] for _, occurrence in coupling.reference_list
                       if occurrence["usr"] in coupling.requirements)
    verdict.info(f"requirements referenced: {sum(expanded.values())} references to {len(expanded)} requirements, "
                 f"{sum(v for u, v in expanded.items() if u in external)} of them to {sum(1 for u in expanded if u in external)} "
                 f"requirements of protocols the package doesn't declare")
    verdict.info(f"references {len(coupling.reference_list)} (distinct, unchanged scanned files); "
                 + ", ".join(f"{k} {v}" for k, v in sorted(coupling.notes.items())))
    with_usr = [r for r in coupling.records if coupling.join.primary.get(r["key"])]
    sums = Counter()
    for record in with_usr:
        figures = coupling.record_figures(record["key"])
        for name in ("sameModule", "otherModules", "tests"):
            sums[name] += bool(figures[name])
    verdict.info(f"records with a USR {len(with_usr)}: with same-module referrers {sums['sameModule']}, "
                 f"other-module {sums['otherModules']}, test {sums['tests']}; witnesses "
                 f"{sum(1 for v in coupling.witness.values() if v)}")
    verdict.info(f"overridden USRs {len(coupling.overriding)}: expanded as requirements {len(coupling.requirements)}, "
                 f"not expanded {len(coupling.overridden_not_requirements)} (referenced "
                 f"{coupling.class_override_references} times)")
    production = [usr for usr, e in coupling.types.items() if e["production"]]
    verdict.info(f"package types {len(coupling.types)} ({len(production)} production); extensions placed "
                 f"{len(coupling.extension_of_record)}; owned extensions "
                 f"{sum(1 for e in coupling.extension_definitions if coupling.owner(e))} of "
                 f"{len(coupling.extension_definitions)}")
    verdict.result("every package nominal type definition is placed on a compatible type record",
                   not coupling.unplaced_types, f"{len(coupling.unplaced_types)} unplaced")
    verdict.listing(coupling.unplaced_types)
    if coupling.identity_collisions:
        production = sum(1 for usrs in coupling.identity_collisions.values() if coupling.types[usrs[0]]["production"])
        verdict.info(f"DESIGN GAP: {len(coupling.identity_collisions)} (module, typePath, typeFile) identities name "
                     f"several package types ({production} in production targets): local types of one name in "
                     "different functions, which design 4.3 and 9.1's typeIndex key can't tell apart; compared "
                     "below as several rows under one identity")
        verdict.listing(f"{identity}: {len(usrs)} types" for identity, usrs in sorted(coupling.identity_collisions.items()))
    else:
        verdict.info("no two package types share (module, typePath, typeFile)")
    verdict.info("module edges: " + ("; ".join(
        f"{s} -> {d} ({e['kind']}, references {e['references']}, files {e['files']})"
        for (s, d), e in sorted(coupling.module_edges.items())) or "none"))
    edges = sum(len(v) for v in coupling.type_edges.values())
    verdict.info(f"type graph: {edges} edges over production types; cycles {len(coupling.cycle_members)}"
                 + (": " + "; ".join(f"{n}: " + ", ".join(i[1] + (f' @ {i[2]}' if i[2] else '') for i in members)
                                     for n, members in enumerate(coupling.cycle_members, start=1))
                    if coupling.cycle_members else ""))
    verdict.info(f"family references {len(coupling.family_references)} (direct "
                 f"{sum(1 for r in coupling.family_references if r[2] == 'direct')}, requirement "
                 f"{sum(1 for r in coupling.family_references if r[2] == 'requirement')}); family-type references "
                 f"{len(coupling.family_type_references)}")


def compare_coupling(verdict, coupling):
    package = coupling.package
    block = package.block
    if not isinstance(block, dict):
        verdict.section("u7 comparison skipped: the scan JSON has no index block")
        verdict.result("the scan JSON has an index block (u7)", False, "absent")
        return
    run = next((c for c in package.scan.get("collectors", []) if c.get("name") == "index"), None)
    verdict.section("u7 the index collector's rule options")
    options = run.get("options", []) if run else []
    for name, text in (("references", DESIGN_REFERENCES_RULE), ("types", DESIGN_TYPES_RULE)):
        given = next((o[len(name) + 2:] for o in options if isinstance(o, str) and o.startswith(name + ": ")), None)
        verdict.result(f"the index collector's options hold `{name}:`", given is not None,
                       "absent" if given is None else "")
        if given is not None and " ".join(given.split()) != " ".join(text.split()):
            verdict.info(f"`{name}:` differs from design 4's text (a deviation the step should explain): {given!r}")

    verdict.section("u7 referrers and witness per record")
    rows = lookup(block, "records")
    theirs = {r.get("key"): r for r in rows} if isinstance(rows, list) else {}
    differences = []
    lenient = []
    for record in sorted(coupling.records, key=lambda r: r["key"]):
        key = record["key"]
        row = theirs.get(key)
        mine = coupling.record_figures(key)
        witness = coupling.witness[key]
        if row is None:
            differences.append(f"{key}: not listed by the scan")
            continue
        their_witness = row.get("witness", MISSING)
        references = row.get("references", MISSING)
        if not isinstance(references, dict):
            flat = {name: row.get(column, MISSING) for name, column in (
                ("sameModule", "referrersSameModule"), ("otherModules", "referrersOtherModules"),
                ("tests", "referrersTests"), ("testReferrers", "testReferrers"))}
            references = flat if any(v is not MISSING for v in flat.values()) else references
        if mine is None:
            # No primary USR: nothing to count references to. Null (not
            # collected) is expected; zeros or false are listed apart.
            empty = references in (MISSING, None) or (isinstance(references, dict) and all(
                v in (MISSING, None, 0, []) for v in references.values()))
            if not empty or their_witness not in (MISSING, None, False):
                differences.append(f"{key} (no USR): scan witness {their_witness if their_witness is not MISSING else 'absent'}, "
                                   f"references {references if references is not MISSING else 'absent'}; mine none")
            elif references not in (MISSING, None) or their_witness not in (MISSING, None):
                lenient.append(key)
            continue
        if their_witness is MISSING or bool(their_witness) != witness or their_witness is None:
            differences.append(f"{key}: witness scan {their_witness if their_witness is not MISSING else 'absent'}, "
                               f"mine {witness}")
        if not isinstance(references, dict):
            differences.append(f"{key}: no references in the scan (mine {mine})")
            continue
        given = {name: references.get(name, MISSING) for name in mine}
        if isinstance(given["testReferrers"], list):
            given["testReferrers"] = list(given["testReferrers"])
        if given != mine:
            differences.append(f"{key}: scan {{" + ", ".join(
                f"{k}: {'absent' if v is MISSING else v}" for k, v in given.items()) + f"}}, mine {mine}")
    verdict.result("referrers (same module, other modules, tests, first five test referrers) and witness of every "
                   "record", rows is not MISSING and not differences,
                   f"{len(theirs)} listed; {len(differences)} differ" if rows is not MISSING else "absent")
    verdict.listing(differences)
    if lenient:
        verdict.info(f"{len(lenient)} records without a USR carry zeros or false rather than null (accepted, noted)")

    verdict.section("u7 module edges")
    rows = lookup(block, "moduleEdges", "edges")
    mine = {(s, d): (e["kind"], e["references"], e["files"]) for (s, d), e in coupling.module_edges.items()}
    their_edges = {}
    for row in flattened(rows) if isinstance(rows, list) else []:
        source = row.get("from", row.get("fromModule"))
        destination = row.get("to", row.get("toModule"))
        their_edges[(source, destination)] = (row.get("kind"), row.get("references"), row.get("files"))
    verdict.result("module edges (from, to, kind, references, importing files)",
                   rows is not MISSING and mine == their_edges,
                   f"{len(mine)} mine, {len(their_edges)} scan" if rows is not MISSING else "absent")
    verdict.listing(f"{edge}: scan {their_edges.get(edge, 'absent')}, mine {mine.get(edge, 'absent')}"
                    for edge in sorted(set(mine) | set(their_edges), key=str) if mine.get(edge) != their_edges.get(edge))

    verdict.section("u7 types: USR, fan-in, cycles")
    rows = lookup(block, "types", "typeIndex")
    mine = coupling.type_rows()
    their_types = defaultdict(list)
    for row in rows if isinstance(rows, list) else []:
        identity = (row.get("module"), row.get("typePath", row.get("name")), row.get("typeFile") or "")
        references = row.get("references") if isinstance(row.get("references"), dict) else row.get("referrers")
        references = references if isinstance(references, dict) else {}
        their_types[identity].append({
            "usr": row.get("usr"),
            "sameModule": references.get("sameModule", row.get("referrersSameModule")),
            "otherModules": references.get("otherModules", row.get("referrersOtherModules")),
            "tests": references.get("tests", row.get("referrersTests")),
            "cycle": row.get("cycle")})
    their_types = {identity: sorted(found, key=lambda row: str(sorted(row.items())))
                   for identity, found in their_types.items()}
    differences = []
    for identity in sorted(set(mine) | set(their_types)):
        own, given = mine.get(identity), their_types.get(identity)
        if own != given:
            differences.append(f"{identity}: scan {given if given else 'absent'}, mine {own if own else 'absent'}")
    verdict.result("production types (identity, USR, same-module, other-module and test referrers, cycle number)",
                   rows is not MISSING and not differences,
                   f"{len(mine)} mine, {len(their_types)} scan" if rows is not MISSING else "absent")
    verdict.listing(differences)
    if differences and their_types:
        if coupling.type_rows(ascending=True) == their_types:
            verdict.info("the scan's types match if cycles are numbered by ascending size (design: by size, then "
                         "first member; this check numbers the largest first)")
        partition_mine = sorted(tuple(members) for members in coupling.cycle_members)
        groups = defaultdict(list)
        for identity, found in their_types.items():
            for row in found:
                if row.get("cycle") is not None:
                    groups[row["cycle"]].append(identity)
        partition_theirs = sorted(tuple(sorted(members)) for members in groups.values())
        verdict.info("cycle membership (ignoring numbers) "
                     + ("agrees" if partition_mine == partition_theirs else
                        f"differs: mine {partition_mine}, scan {partition_theirs}"))

    verdict.section("u7 family references and family-type references")
    rows = lookup(block, "familyReferences")
    their_families = {(r.get("from", r.get("fromFamily")), r.get("to", r.get("toFamily")), r.get("via"))
                      for r in flattened(rows)} if isinstance(rows, list) else set()
    mine = coupling.family_references
    verdict.result("family references (from, to, via)", rows is not MISSING and mine == their_families,
                   f"{len(mine)} mine, {len(their_families)} scan" if rows is not MISSING else "absent")
    verdict.listing(f"only mine: {item}" for item in sorted(mine - their_families, key=str))
    verdict.listing(f"only the scan's: {item}" for item in sorted(their_families - mine, key=str))
    rows = lookup(block, "familyTypeReferences")
    their_type_refs = {(r.get("family"), r.get("module"), r.get("typePath", r.get("name")), r.get("typeFile") or "")
                       for r in flattened(rows)} if isinstance(rows, list) else set()
    mine = coupling.family_type_references
    verdict.result("family-type references (family, module, typePath, typeFile)",
                   rows is not MISSING and mine == their_type_refs,
                   f"{len(mine)} mine, {len(their_type_refs)} scan" if rows is not MISSING else "absent")
    verdict.listing(f"only mine: {item}" for item in sorted(mine - their_type_refs, key=str))
    verdict.listing(f"only the scan's: {item}" for item in sorted(their_type_refs - mine, key=str))

    verdict.section("u7 roll-ups index.typeCycles, index.typesInCycles, index.moduleEdges")
    own_rollups = coupling.scope_rollups()
    differences = []
    lacking = []
    for entry in package.scan.get("rollups", []):
        scope = (entry.get("scope"), entry.get("name"))
        index = entry.get("index")
        if not isinstance(index, dict) or not all(name in index for name in ("typeCycles", "typesInCycles",
                                                                             "moduleEdges")):
            lacking.append(f"{scope[0]} {scope[1]}")
            continue
        own = own_rollups.get(scope, {"typeCycles": 0, "typesInCycles": 0, "moduleEdges": 0})
        given = {name: index[name] for name in own}
        if given != own:
            differences.append(f"{scope[0]} {scope[1]}: scan {given}, mine {own}")
    verdict.result("every roll-up scope has index.typeCycles, index.typesInCycles and index.moduleEdges",
                   not lacking, f"lacking in {', '.join(lacking)}" if lacking else "")
    verdict.result("roll-ups equal this check's reading (module: cycles with a member there, its types in cycles, "
                   "edges from it; project production: all; project tests: edges from test targets)",
                   not differences, f"{len(package.scan.get('rollups', []))} scopes")
    verdict.listing(differences)


# --------------------------------------------------------------------------
# usr, check u8: the store's index rows against the scan JSON (design
# sections 9.1, 9.2 and 11; plan step 7a)

U8_FUNCTION_COLUMNS = ("usr", "usrAccessor", "usrReason", "witness", "referrersSameModule",
                       "referrersOtherModules", "referrersTests", "testReferrers")
U8_TABLES = {
    "indexScan": ("collectedAt", "layout", "libraryModules", "unitsKept", "unitsVariant", "unitsSystem",
                  "unitsOtherPackage", "unitsOtherModule", "unitsStale", "unitsDuplicate", "unitsQuarantined",
                  "records", "occurrences", "definitionsJoined", "definitionsImplicit", "secondaryUSRs", "objcUSRs"),
    "indexUnit": ("name", "target", "mainFile", "triple", "class"),
    "indexFile": ("path", "sha256"),
    "usrDisagreement": ("ordinal", "kind", "subreason", "usr", "key", "symbolKind", "name", "file", "line", "column"),
    "moduleEdge": ("fromModule", "toModule", "kind", "references", "files"),
    "typeIndex": ("module", "typePath", "typeFile", "usr", "referrersSameModule", "referrersOtherModules",
                  "referrersTests", "cycle"),
    "familyReference": ("fromFamily", "toFamily", "via"),
    "familyTypeReference": ("family", "module", "typePath", "typeFile"),
    "couplingPair": ("ordinal", "familyA", "fileA", "familyB", "fileB", "support", "changesA", "changesB"),
}
# The columns design 9.1 marks NULL (every new `function` column is).
U8_NULLABLE = {
    "indexScan": set(), "indexUnit": set(), "indexFile": set(),
    "usrDisagreement": {"subreason", "usr", "key", "symbolKind", "name"},
    "moduleEdge": {"references"}, "typeIndex": {"usr", "cycle"},
    "familyReference": set(), "familyTypeReference": set(), "couplingPair": set(),
}
U8_COUNTS = ("kept", "variant", "system", "otherPackage", "otherModule", "stale", "duplicate", "quarantined")
U8_DEFINITIONS = ("joined", "implicit", "secondary", "objc")
CARRIED_FROM = re.compile(r"carried from the scan of (\S+)")


def u8_rows(connection, table, snapshot):
    """Table `table`'s rows of `snapshot`, as tuples of U8_TABLES' columns."""
    columns = U8_TABLES[table]
    quoted = ", ".join(f'"{name}"' for name in columns)
    return [tuple(row) for row in connection.execute(
        f'SELECT {quoted} FROM "{table}" WHERE snapshotId = ?', (snapshot,))]


def u8_compare(verdict, name, mine, stored):
    """Two lists of tuples compared as multisets; the differences listed."""
    expected, held = Counter(mine), Counter(stored)
    verdict.result(name, expected == held, f"{len(mine)} in the scan JSON, {len(stored)} stored")
    verdict.listing(f"only the scan JSON's: {item}" for item in sorted((expected - held).elements(), key=repr))
    verdict.listing(f"only the store's: {item}" for item in sorted((held - expected).elements(), key=repr))


def u8_ordinals(verdict, name, ordinals):
    """Ordinals that count 0 or 1 upwards with no gap."""
    ordered = sorted(ordinals)
    base = ordered[0] if ordered else 0
    ok = base in (0, 1) and ordered == list(range(base, base + len(ordered)))
    verdict.result(f"{name} ordinals count up from 0 or 1 with no gap", ok,
                   f"{ordered[:5]}{'...' if len(ordered) > 5 else ''}" if not ok else
                   (f"from {base}" if ordered else "none"))
    return base


def u8_json_text(value):
    """A JSON array stored as text, read back; MISSING when it doesn't read."""
    if value is None:
        return None
    try:
        return json.loads(value)
    except (TypeError, ValueError):
        return MISSING


def u8_function_expected(item):
    """The `function` columns design 9.1 adds for the index block's record `item`, in U8_FUNCTION_COLUMNS' order."""
    references = item.get("references") if isinstance(item.get("references"), dict) else None
    witness = item.get("witness")
    return (item.get("usr"), item.get("usrAccessor"), item.get("reason"),
            None if witness is None else int(bool(witness)),
            references.get("sameModule") if references else None,
            references.get("otherModules") if references else None,
            references.get("tests") if references else None,
            references.get("testReferrers") if references else None)


def compare_index_store(verdict, scan, store_path, snapshot):
    """Check u8: the store's index rows of `snapshot` (the newest by default)
    equal the scan JSON's `index` block, its records' USR and referrer
    columns, and its history's coupling pairs."""
    import sqlite3

    verdict.section(f"u8 the store's index rows ({store_path}) against the scan JSON")
    block = scan.get("index")
    connection = sqlite3.connect(f"file:{store_path}?mode=ro", uri=True)
    try:
        if snapshot is None:
            snapshot = connection.execute("SELECT max(id) FROM snapshot").fetchone()[0]
        row = connection.execute("SELECT package, commitHash, date FROM snapshot WHERE id = ?", (snapshot,)).fetchone()
        if row is None:
            verdict.result(f"snapshot {snapshot} is in the store", False, "absent")
            return
        package_name, commit, date = row
        verdict.info(f"snapshot {snapshot}: {package_name} at {commit}, dated {date}")
        scanned = scan.get("package", {}) if isinstance(scan.get("package"), dict) else {}
        if scanned.get("name") not in (None, package_name):
            verdict.info(f"the scan JSON names package {scanned.get('name')!r}, the snapshot {package_name!r}")

        tables = {name for (name,) in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
        absent = [name for name in U8_TABLES if name not in tables]
        function_columns = {r[1]: r for r in connection.execute("PRAGMA table_info(function)")}
        absent += [f"function.{name}" for name in U8_FUNCTION_COLUMNS if name not in function_columns]
        verdict.result("the store has design 9.1's index tables and function columns", not absent,
                       ", ".join(absent))
        if absent:
            return
        deviations = []
        for table, columns in U8_TABLES.items():
            info = {r[1]: r for r in connection.execute(f'PRAGMA table_info("{table}")')}
            lacking = [name for name in columns if name not in info]
            if lacking:
                verdict.result(f"{table} has design 9.1's columns", False, ", ".join(lacking))
                return
            for name in columns:
                nullable = info[name][3] == 0 and info[name][5] == 0
                if nullable != (name in U8_NULLABLE[table]):
                    deviations.append(f"{table}.{name}: {'NULL' if nullable else 'NOT NULL'} in the store, "
                                      f"{'NULL' if name in U8_NULLABLE[table] else 'NOT NULL'} in design 9.1")
        for name in U8_FUNCTION_COLUMNS:
            if function_columns[name][3] != 0:
                deviations.append(f"function.{name}: NOT NULL in the store, NULL in design 9.1")
        if deviations:
            verdict.info("printed, not failed: columns whose nullability differs from design 9.1")
            verdict.listing(deviations)

        # function: the index block's records' columns; null on every other row.
        stored_functions = {}
        duplicates = []
        quoted = ", ".join(f'"{name}"' for name in U8_FUNCTION_COLUMNS)
        for values in connection.execute(f"SELECT key, {quoted} FROM function WHERE snapshotId = ?", (snapshot,)):
            key = values[0]
            if key in stored_functions:
                duplicates.append(key)
            columns = list(values[1:])
            columns[-1] = u8_json_text(columns[-1])
            stored_functions[key] = tuple(columns)
        if duplicates:
            verdict.result("function keys are distinct in the snapshot", False, f"{len(duplicates)} repeated")
            verdict.listing(duplicates)
        expected_functions = {r.get("key"): (None,) * len(U8_FUNCTION_COLUMNS) for r in scan.get("records", [])}
        listed = block.get("records", []) if isinstance(block, dict) else []
        unknown = [item.get("key") for item in listed if item.get("key") not in expected_functions]
        for item in listed:
            expected_functions[item.get("key")] = u8_function_expected(item)
        verdict.result("every index record names a record of the scan", not unknown, f"{len(unknown)} don't")
        verdict.listing(unknown)
        unread = [key for key, columns in stored_functions.items() if columns[-1] is MISSING]
        verdict.result("function.testReferrers reads as a JSON array where set", not unread, f"{len(unread)} don't")
        verdict.listing(unread)
        differences = [f"{key}: scan JSON {expected_functions.get(key, 'no record')}, "
                       f"store {stored_functions.get(key, 'no row')}"
                       for key in sorted(set(expected_functions) | set(stored_functions), key=str)
                       if expected_functions.get(key) != stored_functions.get(key)]
        with_usr = sum(1 for columns in stored_functions.values() if columns[0] is not None)
        verdict.result("function.usr, usrAccessor, usrReason, witness, referrers and testReferrers per record "
                       "(null where the index block lists no record)", not differences,
                       f"{len(expected_functions)} records, {len(stored_functions)} rows, {with_usr} with a USR")
        verdict.listing(differences)

        # The index tables: no rows without an index block.
        if not isinstance(block, dict):
            counts = {table: len(u8_rows(connection, table, snapshot))
                      for table in U8_TABLES if table != "couplingPair"}
            verdict.result("no index rows (the scan JSON has no index block)", not any(counts.values()),
                           ", ".join(f"{table} {count}" for table, count in counts.items() if count))
        else:
            store_block = block.get("store", {}) if isinstance(block.get("store"), dict) else {}
            counts = store_block.get("counts", {}) if isinstance(store_block.get("counts"), dict) else {}
            definitions = block.get("definitions", {}) if isinstance(block.get("definitions"), dict) else {}
            scan_rows = u8_rows(connection, "indexScan", snapshot)
            run = next((c for c in scan.get("collectors", []) if c.get("name") == "index"), {}) or {}
            carried = CARRIED_FROM.search(run.get("reason") or "")
            collected = carried.group(1) if carried else date
            expected = (collected, store_block.get("layout"), block.get("libraryModules"),
                        *(counts.get(name) for name in U8_COUNTS),
                        store_block.get("records"), store_block.get("occurrences"),
                        *(definitions.get(name) for name in U8_DEFINITIONS))
            if len(scan_rows) != 1:
                verdict.result("one indexScan row", False, f"{len(scan_rows)}")
            else:
                held = list(scan_rows[0])
                held[2] = u8_json_text(held[2])
                names = U8_TABLES["indexScan"]
                wrong = [f"{name}: scan JSON {mine!r}, store {theirs!r}"
                         for name, mine, theirs in zip(names, expected, held) if mine != theirs]
                verdict.result("indexScan (collectedAt the snapshot's date"
                               + (f", or the carried scan's {collected}" if carried else "")
                               + "; libraryModules, unit counts, records, occurrences, definitions)",
                               not wrong, f"{len(names)} columns")
                verdict.listing(wrong)
            u8_compare(verdict, "indexUnit rows (name, target, mainFile, triple, class)",
                       [(u.get("name"), u.get("target"), u.get("mainFile"), u.get("triple"), u.get("class"))
                        for u in store_block.get("units", [])],
                       u8_rows(connection, "indexUnit", snapshot))
            u8_compare(verdict, "indexFile rows (path, sha256)",
                       [(f.get("path"), f.get("sha256")) for f in block.get("files", [])],
                       u8_rows(connection, "indexFile", snapshot))
            fields = U8_TABLES["usrDisagreement"][1:]
            lists = [item for name in ("disagreements", "withoutRecord", "collisions")
                     for item in (block.get(name) or [])]
            stored = sorted(u8_rows(connection, "usrDisagreement", snapshot))
            u8_ordinals(verdict, "usrDisagreement", [r[0] for r in stored])
            mine = [tuple(item.get(name) for name in fields) for item in lists]
            u8_compare(verdict, "usrDisagreement rows (the disagreements, withoutRecord and collisions lists: "
                       "kind, subreason, usr, key, symbolKind, name, file, line, column)",
                       mine, [r[1:] for r in stored])
            if Counter(mine) == Counter(r[1:] for r in stored) and mine != [r[1:] for r in stored]:
                verdict.info("printed, not failed: by ordinal the rows aren't in the lists' order "
                             "(disagreements, withoutRecord, collisions)")
            u8_compare(verdict, "moduleEdge rows (fromModule, toModule, kind, references, files)",
                       [(e.get("fromModule"), e.get("toModule"), e.get("kind"), e.get("references"), e.get("files"))
                        for e in block.get("moduleEdges", [])],
                       u8_rows(connection, "moduleEdge", snapshot))
            u8_compare(verdict, "typeIndex rows (module, typePath, typeFile '' when absent, usr, referrers, cycle)",
                       [(t.get("module"), t.get("typePath"), t.get("typeFile") or "", t.get("usr"),
                         t.get("referrersSameModule"), t.get("referrersOtherModules"), t.get("referrersTests"),
                         t.get("cycle")) for t in block.get("types", [])],
                       u8_rows(connection, "typeIndex", snapshot))
            u8_compare(verdict, "familyReference rows (fromFamily, toFamily, via)",
                       [(f.get("fromFamily"), f.get("toFamily"), f.get("via"))
                        for f in block.get("familyReferences", [])],
                       u8_rows(connection, "familyReference", snapshot))
            u8_compare(verdict, "familyTypeReference rows (family, module, typePath, typeFile '' when absent)",
                       [(f.get("family"), f.get("module"), f.get("typePath"), f.get("typeFile") or "")
                        for f in block.get("familyTypeReferences", [])],
                       u8_rows(connection, "familyTypeReference", snapshot))

        # couplingPair: written with the history, in its order.
        history = scan.get("history") if isinstance(scan.get("history"), dict) else {}
        pairs = history.get("coupling") or []
        stored = sorted(u8_rows(connection, "couplingPair", snapshot))
        u8_ordinals(verdict, "couplingPair", [r[0] for r in stored])
        mine = [tuple(p.get(name) for name in U8_TABLES["couplingPair"][1:]) for p in pairs]
        held = [r[1:] for r in stored]
        verdict.result("couplingPair rows by ordinal equal history.coupling in order "
                       "(familyA, fileA, familyB, fileB, support, changesA, changesB)", mine == held,
                       f"{len(mine)} in the scan JSON, {len(held)} stored")
        if mine != held:
            verdict.listing(f"pair {number}: scan JSON {a}, store {b}"
                            for number, (a, b) in enumerate(zip(mine + [None] * len(held), held + [None] * len(mine)))
                            if a != b)
    except sqlite3.Error as error:
        verdict.result("the store reads", False, str(error))
    finally:
        connection.close()


# --------------------------------------------------------------------------
# rows (check u8 whole): every M7 row of a snapshot against the scan JSON that
# saved it (design sections 9.1, 9.2 and 11 step 2; the gaps step). The index
# tables are compare_index_store's above; this part adds the build and dead
# code tables, the function table's timing columns, the swiftc findings, the
# M7 roll-up rows and the T1 collector rows, and names every table design 9.1
# lists as compared or not.

# buildScan's columns, as the store names them, and where the scan JSON's
# `build` block holds each (design 9.2's names). Design 9.1's `droppedEntries`
# is split per class in the store, and the store adds `warningsUnmapped` and
# each class's milliseconds; a column this list doesn't name fails.
BUILD_SCAN_PATHS = {
    "complete": "complete",
    "functionEntries": "totals.functionEntries",
    "expressionEntries": "totals.expressionEntries",
    "totalMilliseconds": "totals.milliseconds",
    "synthesizedEntries": "unmapped.synthesized.entries",
    "synthesizedMilliseconds": "unmapped.synthesized.milliseconds",
    "macroEntries": "unmapped.macro.entries",
    "macroMilliseconds": "unmapped.macro.milliseconds",
    "buildEntries": "dropped.build.entries",
    "buildMilliseconds": "dropped.build.milliseconds",
    "outsideRootEntries": "dropped.outsideRoot.entries",
    "outsideRootMilliseconds": "dropped.outsideRoot.milliseconds",
    "fileChangedEntries": "dropped.fileChanged.entries",
    "fileChangedMilliseconds": "dropped.fileChanged.milliseconds",
    "unscannedEntries": "dropped.unscanned.entries",
    "unscannedMilliseconds": "dropped.unscanned.milliseconds",
    "changedFiles": "changedFiles",
    "unparsedTimingLines": "unparsedTimingLines",
    "escapedLines": "escapedLines",
    "otherWarningLines": "otherWarningLines",
    "warningsDropped": "warningsDropped",
    "warningsUnmapped": "warningsUnmapped",
    "pluginWarnings": "pluginWarnings",
}
DESIGN_BUILD_SCAN = ("collectedAt", "complete", "functionEntries", "expressionEntries", "totalMilliseconds",
                     "synthesizedEntries", "synthesizedMilliseconds", "macroEntries", "macroMilliseconds",
                     "droppedEntries", "unscannedEntries", "changedFiles", "unparsedTimingLines", "escapedLines",
                     "otherWarningLines", "warningsDropped", "pluginWarnings")
TIMING_FUNCTION_COLUMNS = ("typeCheckMilliseconds", "slowestExpressionMilliseconds")
DEAD_DECLARATION_COLUMNS = ("hint", "hintText", "kind", "name", "accessibility", "attributes", "modifiers", "ids",
                            "modules", "class", "file", "line", "column", "place", "owner", "module",
                            "strippedLines")
DEAD_DECLARATION_ARRAYS = ("attributes", "modifiers", "ids", "modules")
SWIFTC_FINDING_COLUMNS = ("rule", "kind", "severity", "message", "file", "line", "column", "attachedTo", "owner")
# identity and identityLabel aren't in the scan JSON's collector entries (name,
# state, reason, version, options): `dead --store` checks periphery's.
COLLECTOR_COLUMNS = ("state", "reason", "version")
T1_COLLECTORS = ("build", "index", "periphery")
# The M7 roll-up metric names (rollupMetric.metric, the dotted path into a
# roll-up scope of the scan JSON) and the collector each is attributed to:
# design 4 and 9.4 (`index.*` to index), 7 (`tests.lineRatio.deadLines` to
# periphery, with `deadCode.*`), 6.3 (tool swiftc to collector build) and 6.4
# (`typecheck.*`: the build collector's figures; the design names no other).
M7_METRICS = (("index.", "index"), ("deadCode.", "periphery"), ("tests.lineRatio.deadLines", "periphery"),
              ("findings.swiftc.", "build"), ("findingKinds.swiftc.", "build"), ("typecheck.", "build"))
# Design 9.1's tables, each with the comparison that covers it, or why none.
ROWS_COVERAGE = {
    "function (usr, usrAccessor, usrReason, witness, referrers*, testReferrers)":
        "compared (u8 index part, per record, null where the index block lists none)",
    "function (typeCheckMilliseconds, slowestExpressionMilliseconds)":
        "compared (per record, null where the build block lists none)",
    "indexScan": "compared (one row)", "indexUnit": "compared", "indexFile": "compared",
    "usrDisagreement": "compared (with ordinals)", "moduleEdge": "compared", "typeIndex": "compared",
    "familyReference": "compared", "familyTypeReference": "compared",
    "couplingPair": "compared (in order, against history.coupling)",
    "buildScan": "compared (one row)", "timingAttachment": "compared",
    "deadScan": "compared (one row)", "deadDeclaration": "compared (by run and ordinal)",
    "deadRecord": "compared",
    "finding (tool swiftc)": "compared (one row per location; the JSON's category has no column)",
    "rollupMetric (index.*, deadCode.*, tests.lineRatio.deadLines, findings.swiftc.*, findingKinds.swiftc.*, "
    "typecheck.*)": "compared (scope, name, metric, value; collector by design)",
    "deadLines (the store's, not in design 9.1)": "compared with deadCode.deadLines",
    "collectorRun (build, index, periphery)":
        "compared: state, reason, version, options; identity, identityLabel and durationMilliseconds aren't "
        "in the scan JSON's collector entries, so not compared (`dead --store` checks periphery's identity "
        "against the binary)",
    "INDEX deadRecord(snapshotId, key), INDEX familyReference(snapshotId, toFamily)":
        "not rows: their presence is printed, not failed",
    "report (the stored report blob)":
        "not compared: SwiftStats' own copy of the report, not a row model of design 9.1",
}


def json_path(block, path):
    """The value at a dotted path of a JSON object, None when any key is absent
    (the scan JSON leaves nulls out)."""
    value = block
    for key in path.split("."):
        if not isinstance(value, dict) or key not in value:
            return None
        value = value[key]
    return value


def flatten_numbers(value, prefix=""):
    """(dotted path, number) for every numeric leaf, booleans and nulls left
    out (rollupMetric holds a row per number)."""
    if isinstance(value, dict):
        for key, child in value.items():
            yield from flatten_numbers(child, f"{prefix}.{key}" if prefix else key)
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        yield prefix, value


def m7_collector(metric):
    """The collector design attributes an M7 metric to, None for a non-M7 one."""
    for prefix, collector in M7_METRICS:
        if metric == prefix or (prefix.endswith(".") and metric.startswith(prefix)):
            return collector
    return None


def collected_at(scan, collector, date):
    """The snapshot's date, or the date a `carried from the scan of <date>`
    reason of the collector names."""
    run = next((c for c in scan.get("collectors", []) if c.get("name") == collector), {}) or {}
    carried = CARRIED_FROM.search(run.get("reason") or "")
    return carried.group(1) if carried else date


def columns_of(connection, table):
    return [r[1] for r in connection.execute(f'PRAGMA table_info("{table}")')]


def by_column_differences(name, columns, mine, held):
    """Each differing column of one row, precisely."""
    return [f"{name}.{column}: scan JSON {a!r}, store {b!r}"
            for column, a, b in zip(columns, mine, held) if a != b]


def compare_one_row(verdict, connection, table, snapshot, columns, expected, label):
    """A table with one row per snapshot (or none when `expected` is None)."""
    quoted = ", ".join(f'"{name}"' for name in columns)
    rows = [tuple(r) for r in connection.execute(f'SELECT {quoted} FROM "{table}" WHERE snapshotId = ?',
                                                 (snapshot,))]
    if expected is None:
        verdict.result(f"no {table} row (the scan JSON has no block for it)", not rows, f"{len(rows)} stored")
        return
    if len(rows) != 1:
        verdict.result(f"one {table} row", False, f"{len(rows)} stored")
        return
    wrong = by_column_differences(table, columns, expected, rows[0])
    verdict.result(label, not wrong, f"{len(columns)} columns")
    verdict.listing(wrong)


def compare_build_rows(verdict, connection, scan, snapshot, date):
    block = scan.get("build") if isinstance(scan.get("build"), dict) else None
    verdict.section("u8 the build collector's rows against the scan JSON's build block")
    held_columns = columns_of(connection, "buildScan")
    unmapped = [c for c in held_columns if c not in BUILD_SCAN_PATHS and c not in ("snapshotId", "collectedAt")]
    verdict.result("every buildScan column maps to a value of the build block", not unmapped, ", ".join(unmapped))
    missing = [c for c in DESIGN_BUILD_SCAN if c not in held_columns]
    if missing:
        verdict.info("printed, not failed: design 9.1's buildScan columns the store spells otherwise: "
                     + ", ".join(missing) + " (droppedEntries is split per class: build, outsideRoot, "
                     "fileChanged, unscanned)")
    columns = ["collectedAt"] + [c for c in held_columns if c in BUILD_SCAN_PATHS]
    expected = None
    if block is not None:
        expected = (collected_at(scan, "build", date),) + tuple(
            json_path(block, BUILD_SCAN_PATHS[c]) for c in columns[1:])
        expected = tuple(int(v) if isinstance(v, bool) else v for v in expected)
    compare_one_row(verdict, connection, "buildScan", snapshot, columns, expected,
                    "buildScan (collectedAt the snapshot's or the carried scan's date; totals, unmapped, dropped, "
                    "counters)")

    # timingAttachment, by the JSON's own field names.
    attachments = block.get("attachments", []) if block else []
    mine = [(a.get("owner"), a.get("attachedTo"), a.get("milliseconds"), a.get("slowestExpression"))
            for a in attachments]
    held = [tuple(r) for r in connection.execute(
        'SELECT owner, attachedTo, milliseconds, slowestExpressionMilliseconds FROM timingAttachment '
        'WHERE snapshotId = ?', (snapshot,))]
    u8_compare(verdict, "timingAttachment rows (owner, attachedTo, milliseconds, slowestExpressionMilliseconds)",
               mine, held)
    kinds = Counter(r[1] for r in held)
    if held and set(kinds) <= {"type", "file"}:
        verdict.info("printed, not failed: `attachedTo` holds type/file and `owner` the name (M6's attachment "
                     "convention); design 9.1's comment puts 'type' | 'file' in `owner`")

    # function: the timing columns per record, null on every other row.
    expected_rows = {r.get("key"): (None, None) for r in scan.get("records", [])}
    listed = block.get("records", []) if block else []
    unknown = [item.get("key") for item in listed if item.get("key") not in expected_rows]
    for item in listed:
        expected_rows[item.get("key")] = (item.get("milliseconds"), item.get("slowestExpression"))
    verdict.result("every build record names a record of the scan", not unknown, f"{len(unknown)} don't")
    verdict.listing(unknown)
    stored = {key: (ms, slowest) for key, ms, slowest in connection.execute(
        "SELECT key, typeCheckMilliseconds, slowestExpressionMilliseconds FROM function WHERE snapshotId = ?",
        (snapshot,))}
    differences = [f"{key}: scan JSON {expected_rows.get(key, 'no record')}, store {stored.get(key, 'no row')}"
                   for key in sorted(set(expected_rows) | set(stored), key=str)
                   if expected_rows.get(key) != stored.get(key)]
    verdict.result("function.typeCheckMilliseconds and slowestExpressionMilliseconds per record (null where the "
                   "build block lists none)", not differences,
                   f"{len(listed)} timed records in the scan JSON, "
                   f"{sum(1 for v in stored.values() if v != (None, None))} stored rows with a figure")
    verdict.listing(differences)

    # Compiler warnings: finding rows of tool swiftc, one per location.
    mine = []
    categories = 0
    for finding in scan.get("findings", []):
        if finding.get("tool") != "swiftc":
            continue
        categories += finding.get("category") is not None
        for location in finding.get("locations") or [{}]:
            mine.append((finding.get("rule"), finding.get("kind"), finding.get("severity"), finding.get("message"),
                         location.get("file"), location.get("line"), location.get("column"),
                         location.get("attachedTo"), location.get("owner")))
    quoted = ", ".join(f'"{name}"' for name in SWIFTC_FINDING_COLUMNS)
    held = [tuple(r) for r in connection.execute(
        f"SELECT {quoted} FROM finding WHERE snapshotId = ? AND tool = 'swiftc'", (snapshot,))]
    u8_compare(verdict, "finding rows of tool swiftc (" + ", ".join(SWIFTC_FINDING_COLUMNS) + ")", mine, held)
    if categories:
        verdict.info(f"printed, not failed: {categories} swiftc findings carry a category (the group), which "
                     "`finding` has no column for")


def compare_dead_rows(verdict, connection, scan, snapshot, date):
    block = scan.get("deadCode") if isinstance(scan.get("deadCode"), dict) else None
    verdict.section("u8 the periphery collector's rows against the scan JSON's deadCode block")
    expected = None
    if block is not None:
        results = {r.get("name"): r.get("results") for r in block.get("runs") or []}
        expected = (collected_at(scan, "periphery", date), block.get("version"),
                    results.get("roots"), results.get("production"))
    compare_one_row(verdict, connection, "deadScan", snapshot,
                    ("collectedAt", "version", "rootsResults", "productionResults"), expected,
                    "deadScan (collectedAt, version, results per run)")

    # deadDeclaration: by (run, ordinal), every column, arrays read back.
    quoted = ", ".join(f'"{name}"' for name in DEAD_DECLARATION_COLUMNS)
    held = {}
    unread = []
    for row in connection.execute(f'SELECT run, ordinal, {quoted} FROM deadDeclaration WHERE snapshotId = ?',
                                  (snapshot,)):
        values = list(row[2:])
        for index, column in enumerate(DEAD_DECLARATION_COLUMNS):
            if column in DEAD_DECLARATION_ARRAYS:
                values[index] = u8_json_text(values[index])
                if values[index] is MISSING:
                    unread.append(f"{row[0]} {row[1]}: {column}")
        held[(row[0], row[1])] = tuple(values)
    verdict.result("deadDeclaration's JSON array columns read back", not unread, f"{len(unread)} don't")
    verdict.listing(unread)
    declarations = block.get("declarations", []) if block else []
    mine = {}
    repeated = []
    for item in declarations:
        identity = (item.get("run"), item.get("ordinal"))
        if identity in mine:
            repeated.append(identity)
        mine[identity] = tuple(item.get(column) for column in DEAD_DECLARATION_COLUMNS)
    verdict.result("the scan JSON's declarations are distinct by (run, ordinal)", not repeated,
                   f"{len(repeated)} repeated")
    verdict.listing(repeated)
    differences = []
    for identity in sorted(set(mine) | set(held), key=repr):
        if identity not in held:
            differences.append(f"{identity}: only the scan JSON's: {mine[identity]}")
        elif identity not in mine:
            differences.append(f"{identity}: only the store's: {held[identity]}")
        else:
            differences += by_column_differences(f"{identity}", DEAD_DECLARATION_COLUMNS, mine[identity],
                                                 held[identity])
    verdict.result("deadDeclaration rows by (run, ordinal): " + ", ".join(DEAD_DECLARATION_COLUMNS),
                   not differences, f"{len(mine)} in the scan JSON, {len(held)} stored")
    verdict.listing(differences)
    for run in DEAD_RUNS:
        u8_ordinals(verdict, f"deadDeclaration {run}", [o for r, o in held if r == run])

    u8_compare(verdict, "deadRecord rows (run, key, declaration, via)",
               [(r.get("run"), r.get("key"), r.get("declaration"), r.get("via"))
                for r in ((block.get("records") or []) if block else [])],
               [tuple(r) for r in connection.execute(
                   "SELECT run, key, declaration, via FROM deadRecord WHERE snapshotId = ?", (snapshot,))])
    tables = {name for (name,) in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    if "deadLines" in tables:
        lines = (block.get("deadLines") or {}) if block else {}
        u8_compare(verdict, "deadLines rows (run, module, lines; the store's table, not in design 9.1) against "
                   "deadCode.deadLines",
                   [(run, module, count) for run, modules in lines.items() if isinstance(modules, dict)
                    for module, count in modules.items()],
                   [tuple(r) for r in connection.execute(
                       "SELECT run, module, lines FROM deadLines WHERE snapshotId = ?", (snapshot,))])
    else:
        verdict.info("the store has no deadLines table (design 9.1 names none): not compared")


def compare_rollup_rows(verdict, connection, scan, snapshot):
    verdict.section("u8 the M7 roll-up rows (rollupMetric) against the scan JSON's roll-ups")
    mine = []
    for scope in scan.get("rollups", []):
        for metric, value in flatten_numbers(scope):
            collector = m7_collector(metric)
            if collector is not None:
                mine.append((scope.get("scope"), scope.get("name"), metric, collector, value))
    held = []
    for row in connection.execute("SELECT scope, name, metric, collector, value FROM rollupMetric "
                                  "WHERE snapshotId = ?", (snapshot,)):
        if m7_collector(row[2]) is not None:
            held.append(tuple(row))
    u8_compare(verdict, "rollupMetric rows named " + ", ".join(p + ("*" if p.endswith(".") else "")
                                                              for p, _ in M7_METRICS)
               + " (scope, name, metric, collector as design attributes it, value)", mine, held)
    names = Counter(metric.split(".")[0] + ("." + metric.split(".")[1] if metric.startswith(("findings.",
                    "findingKinds.")) else "") for _, _, metric, _, _ in held)
    verdict.info("stored M7 metrics by family: " + (", ".join(f"{n} {c}" for n, c in sorted(names.items()))
                                                   or "none"))


def compare_collector_rows(verdict, connection, scan, snapshot):
    verdict.section("u8 the T1 collectors' collectorRun rows against the scan JSON's collectors")
    for name in T1_COLLECTORS:
        run = next((c for c in scan.get("collectors", []) if c.get("name") == name), None)
        row = connection.execute('SELECT state, reason, version, options '
                                 'FROM collectorRun WHERE snapshotId = ? AND name = ?', (snapshot, name)).fetchone()
        if run is None:
            verdict.result(f"{name}: no collectorRun row (the scan JSON lists no such collector)", row is None,
                           "a row is stored" if row else "")
            continue
        if row is None:
            verdict.result(f"{name}: a collectorRun row", False, "absent")
            continue
        expected = tuple(run.get(column) for column in COLLECTOR_COLUMNS)
        wrong = by_column_differences(name, COLLECTOR_COLUMNS, expected, tuple(row[:3]))
        stored_options = u8_json_text(row[3])
        options = run.get("options")
        if stored_options is MISSING:
            verdict.info(f"printed, not failed: {name}'s stored options aren't JSON: {row[3][:80]!r}")
        elif stored_options != options:
            wrong.append(f"{name}.options: scan JSON {options!r}, store {stored_options!r}")
        verdict.result(f"{name}: " + ", ".join(COLLECTOR_COLUMNS) + ", options", not wrong,
                       f"state {row[0]}")
        verdict.listing(wrong)


def compare_rows(verdict, scan, store_path, snapshot):
    """Check u8 whole: every M7 row of `snapshot` (the newest by default)
    equals the scan JSON that saved it, row for row, nulls as nulls."""
    import sqlite3

    connection = sqlite3.connect(f"file:{store_path}?mode=ro", uri=True)
    try:
        if snapshot is None:
            snapshot = connection.execute("SELECT max(id) FROM snapshot").fetchone()[0]
        row = connection.execute("SELECT date, reportSchemaVersion FROM snapshot WHERE id = ?",
                                 (snapshot,)).fetchone()
    except sqlite3.Error as error:
        connection.close()
        verdict.result("the store reads", False, str(error))
        return
    if row is None:
        connection.close()
        verdict.result(f"snapshot {snapshot} is in the store", False, "absent")
        return
    date, schema = row
    compare_index_store(verdict, scan, store_path, snapshot)
    try:
        verdict.section(f"u8 the snapshot row ({snapshot}) against the scan JSON")
        verdict.result("snapshot.reportSchemaVersion is the scan JSON's schemaVersion",
                       schema == scan.get("schemaVersion"), f"store {schema}, scan JSON {scan.get('schemaVersion')}")
        tables = {name for (name,) in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
        absent = [t for t in ("buildScan", "timingAttachment", "deadScan", "deadDeclaration", "deadRecord",
                              "rollupMetric", "finding", "collectorRun") if t not in tables]
        function_columns = columns_of(connection, "function")
        absent += [f"function.{c}" for c in TIMING_FUNCTION_COLUMNS if c not in function_columns]
        verdict.result("the store has design 9.1's build and dead code tables and timing columns", not absent,
                       ", ".join(absent))
        if absent:
            return
        compare_build_rows(verdict, connection, scan, snapshot, date)
        compare_dead_rows(verdict, connection, scan, snapshot, date)
        compare_rollup_rows(verdict, connection, scan, snapshot)
        compare_collector_rows(verdict, connection, scan, snapshot)
        indexes = {name for (name,) in connection.execute("SELECT name FROM sqlite_master WHERE type = 'index'")}
        verdict.section("u8 coverage of design 9.1's tables")
        for table, how in ROWS_COVERAGE.items():
            verdict.info(f"{table}: {how}")
        verdict.info("indexes present (printed, not failed): "
                     + (", ".join(sorted(i for i in indexes if not i.startswith("sqlite_"))) or "none"))
    except sqlite3.Error as error:
        verdict.result("the store reads", False, str(error))
    finally:
        connection.close()


def rows_mode(arguments):
    try:
        with open(arguments.scan, encoding="utf-8") as handle:
            scan = json.load(handle)
    except (OSError, ValueError) as error:
        fail(f"the scan JSON doesn't read: {error}")
    if not os.path.isfile(arguments.store):
        fail(f"no store at {arguments.store}")
    verdict = Verdict(arguments.all)
    print(f"scan JSON {arguments.scan}\nstore {arguments.store}")
    compare_rows(verdict, scan, arguments.store, arguments.snapshot)
    print("\nRESULT: " + ("FAIL" if verdict.failed else "PASS"))
    return 1 if verdict.failed else 0


def usr_mode(arguments):
    try:
        package = UsrPackage(arguments)
    except (OSError, ValueError, ReadError) as error:
        fail(str(error))
    resource = None
    if (arguments.reader is None and arguments.library is None) or arguments.demangle is None \
            or arguments.describe is None:
        resource = toolchain_of(package.root, arguments.swift)
    if arguments.library is None and arguments.reader is None:
        arguments.library = os.path.join(os.path.dirname(resource), "libIndexStore.dylib")
    demangler = arguments.demangle or os.path.join(os.path.dirname(os.path.dirname(resource)), "bin", "swift-demangle")
    if arguments.describe:
        with open(arguments.describe, encoding="utf-8") as handle:
            describe = json.load(handle)
    else:
        describe = run_describe(package.root, os.path.join(os.path.dirname(os.path.dirname(resource)), "bin", "swift"))
    described_path = describe.get("path")
    if not isinstance(described_path, str) or real_path(package.spellings.restore(described_path), "describe's path") \
            != package.root:
        fail(f"the describe JSON describes {described_path!r}, not {package.root}")
    described = Described(describe, package)
    log_path = arguments.log or os.path.join(package.scratch, BUILD_LOG)
    log_text = open(log_path, encoding="utf-8", errors="replace").read() if os.path.isfile(log_path) else None
    try:
        reader = UnitReader(package, arguments)
        try:
            join = UsrJoin(package, described, reader, log_text)
        finally:
            reader.close()
    except ReadError as error:
        fail(str(error))
    verdict = Verdict(arguments.all)
    print(f"package {package.root}\nbuild directory {package.scratch}\n"
          f"index read from {'the recording ' + arguments.reader if arguments.reader else reader.store_path}"
          + (f" with {arguments.library}" if not arguments.reader else "")
          + f"\nbuild log for 'target not built': {log_path if log_text is not None else 'none (no compile named)'}")
    if package.changed:
        print(f"files changed since the scan hashed them: {len(package.changed)} "
              f"({', '.join(sorted(package.changed)[:5])})")
    problems_u3 = []
    for key, definition, how in join.joined_definitions:
        problem = name_token_problem(join, key, definition, how)
        if problem:
            problems_u3.append(f"{key} ({how}): {problem}")
    checked = sorted({usr for usr in list(join.primary.values()) + list(join.secondary.values())
                      if usr.startswith("s:")})
    trees = parse_trees(demangle_all(checked, demangler, "--tree-only"))
    compact = demangle_all(checked, demangler, "--compact").split("\n")
    demangled = {usr: compact[index] if index < len(compact) else "" for index, usr in enumerate(checked)}
    problems_u6 = []
    objc_skipped = 0
    for record in sorted(package.records, key=lambda r: r["key"]):
        key = record["key"]
        for usr, secondary in ((join.primary.get(key), False), (join.secondary.get(key), True)):
            if usr is None:
                continue
            if not usr.startswith("s:"):
                objc_skipped += 1
                continue
            facts = key_facts(record, package.by_key)
            problem = demangle_problem(record, facts, demangled_facts(trees.get("$s" + usr[2:])), secondary)
            if problem:
                problems_u6.append(f"{key}{' (secondary)' if secondary else ''}: {problem} [{demangled[usr]}]")
    report_own(verdict, join, problems_u3, problems_u6, objc_skipped, len(checked))
    coupling = None
    if not arguments.without_u7:
        coupling = Coupling(join, demangler, arguments.local_containers, arguments.requirements)
        report_coupling_own(verdict, coupling)
    if arguments.dump:
        figures = own_usr_figures(join)
        if coupling is not None:
            figures["coupling"] = coupling.figures()
        write_json(arguments.dump, figures)
    if arguments.own_only:
        verdict.section("comparison with the scan JSON skipped (--own-only)")
    else:
        compare_index(verdict, join, problems_u3, problems_u6)
        if coupling is not None:
            compare_coupling(verdict, coupling)
    if arguments.store:
        compare_rows(verdict, package.scan, arguments.store, arguments.snapshot)
    print("\nRESULT: " + ("FAIL" if verdict.failed else "PASS"))
    return 1 if verdict.failed else 0


# --------------------------------------------------------------------------
# dead, run part: outskirts' two runs and the sorted comparison (design
# sections 5.1 to 5.3, 9.1, 9.2 and 11; plan step 6a)

OUTSKIRTS_CHECKED_VERSION = "3.28.0"
OUTSKIRTS_KEYS = ("accessibility", "attributes", "hints", "ids", "kind", "location", "modifiers", "modules", "name")
OUTSKIRTS_LISTS = ("attributes", "ids", "modifiers", "modules")
OUTSKIRTS_STRINGS = ("accessibility", "kind", "name")
DEAD_RUNS = ("roots", "production")
KEPT_OUTPUT = {"roots": "swiftstats-outskirts-roots.json", "production": "swiftstats-outskirts-production.json"}
OUTSKIRTS_CONFIG = "swiftstats-outskirts.yml"
T1_DESCRIBE = "swiftstats-describe.json"
UNSCANNED_RETAINED = "retain_public_modules lists modules that are not scanned"
VERSION_WARNING = f"isn't the version SwiftStats was checked against ({OUTSKIRTS_CHECKED_VERSION})"
HINT_WITH_TEXT = re.compile(r"([A-Za-z]+)\((.*)\)", re.S)
BUILD_FILE = "<build>"
DECLARATION_FIELDS = ("run", "hint", "hintText", "kind", "name", "accessibility", "attributes", "modifiers", "ids",
                      "modules", "file", "line", "column")


def byte_order(names):
    return sorted(names, key=lambda name: name.encode("utf-8"))


def outskirts_command(outskirts, scratch, config, describe_path, retained, production):
    """Design 5.2's command line from its words, each flag its own argv element."""
    command = [outskirts, "scan", "--format", "json", "--disable-update-check",
               "--config", config,
               "--index-store-path", os.path.join(scratch, STORE_DIRECTORY), "--skip-build",
               "--index-exclude", scratch + "/**",
               "--json-package-manifest-path", describe_path]
    if retained:
        command += ["--retain-public-modules"] + list(retained)
    command += ["--retain-codable-properties", "--retain-equatable-properties"]
    if production:
        command.append("--exclude-tests")
    return command


def printable_command(command, replacements):
    """A command line with its paths spelt as placeholders, for printing."""
    words = []
    for word in command:
        for path, token in replacements:
            if word == path or word.startswith(path + "/"):
                word = token + word[len(path):]
                break
        words.append(word)
    return " ".join(words)


def tree_state(root):
    """What a run must leave as it was: git's view of the package (ignored
    files included), whether `.build` exists, Package.resolved's bytes and
    the names in the package root (outside git too)."""
    status = None
    try:
        result = subprocess.run(["git", "status", "--porcelain=v1", "--ignored", "-z"], cwd=root,
                                capture_output=True, timeout=120, stdin=subprocess.DEVNULL)
        if result.returncode == 0:
            status = result.stdout
    except (OSError, subprocess.TimeoutExpired):
        status = None
    resolved = os.path.join(root, "Package.resolved")
    with_resolved = None
    if os.path.isfile(resolved):
        with open(resolved, "rb") as handle:
            with_resolved = handle.read()
    return {"git status --porcelain --ignored": status, ".build": os.path.exists(os.path.join(root, ".build")),
            "Package.resolved": with_resolved, "the root's names": sorted(os.listdir(root))}


def split_location(text):
    """`<path>:<line>:<column>`, split from the right, 1-based; None when it doesn't read."""
    if not isinstance(text, str):
        return None
    parts = text.rsplit(":", 2)
    if len(parts) != 3 or not parts[0] or not ascii_digits(parts[1]) or not ascii_digits(parts[2]):
        return None
    line, column = int(parts[1]), int(parts[2])
    if line < 1 or column < 1:
        return None
    return parts[0], line, column


def format_problems(entries, run):
    """Design 5.3's format: an array of objects holding the nine keys."""
    if not isinstance(entries, list):
        return [f"the {run} run's output is a JSON {type(entries).__name__}, not an array"]
    problems = []
    for number, entry in enumerate(entries, 1):
        if not isinstance(entry, dict):
            problems.append(f"entry {number}: not an object")
            continue
        missing = [key for key in OUTSKIRTS_KEYS if key not in entry]
        if missing:
            problems.append(f"entry {number}: lacks {', '.join(missing)}")
            continue
        hints = entry["hints"]
        if not (isinstance(hints, list) and len(hints) == 1 and isinstance(hints[0], str)):
            problems.append(f"entry {number}: hints {hints!r} isn't one string")
        for key in OUTSKIRTS_LISTS:
            if not isinstance(entry[key], list) or not all(isinstance(value, str) for value in entry[key]):
                problems.append(f"entry {number}: {key} {entry[key]!r} isn't a list of strings")
        for key in OUTSKIRTS_STRINGS:
            if not isinstance(entry[key], str):
                problems.append(f"entry {number}: {key} {entry[key]!r} isn't a string")
        if split_location(entry["location"]) is None:
            problems.append(f"entry {number}: location {entry['location']!r} doesn't read as path:line:column")
    return problems


def canonical(entry):
    return json.dumps(entry, sort_keys=True, ensure_ascii=False, separators=(",", ":"))


def compare_multisets(verdict, name, mine, theirs, theirs_name="theirs"):
    own, other = Counter(mine), Counter(theirs)
    only_mine = sorted((own - other).elements(), key=str)
    only_theirs = sorted((other - own).elements(), key=str)
    verdict.result(name, not only_mine and not only_theirs,
                   f"{sum(own.values())} mine, {sum(other.values())} {theirs_name}")
    verdict.listing(f"only mine: {item}" for item in only_mine)
    verdict.listing(f"only {theirs_name}: {item}" for item in only_theirs)


def as_list(value):
    """A list, or a JSON array stored as text, as a tuple; anything else as it is."""
    if isinstance(value, str):
        try:
            parsed = json.loads(value)
        except ValueError:
            return value
        value = parsed
    return tuple(value) if isinstance(value, list) else value


def git_text(directory, *command):
    try:
        result = subprocess.run(["git", "-C", directory] + list(command), capture_output=True, text=True,
                                timeout=60, stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired):
        return None
    return result.stdout.strip() if result.returncode == 0 else None


class DeadRuns:
    """This script's two outskirts runs over the scan's build directory, and
    its decoding of their entries (design 5.3, without the classes)."""

    def __init__(self, package, described, outskirts, config, describe_path, retained_targets, output_dir):
        self.package = package
        self.described = described
        self.outskirts = outskirts
        self.retained_targets = byte_order(retained_targets)
        self.retained = byte_order(described.targets[name]["module"] for name in retained_targets)
        self.config = config
        self.describe_path = describe_path
        self.output_dir = output_dir
        self.commands = {}
        self.entries = {}
        self.problems = {}
        self.exits = {}
        self.stderr = {}
        self.seconds = {}
        self.tree_changes = {}
        self.raw = {}

    def run_all(self):
        for run in DEAD_RUNS:
            self.run(run)

    def run(self, run):
        command = outskirts_command(self.outskirts, self.package.scratch, self.config, self.describe_path,
                                    self.retained, run == "production")
        self.commands[run] = command
        before = tree_state(self.package.root)
        start = time.monotonic()
        try:
            result = subprocess.run(command, cwd=self.package.root, stdin=subprocess.DEVNULL, capture_output=True,
                                    timeout=3600)
        except (OSError, subprocess.TimeoutExpired) as error:
            fail(f"outskirts ({run}) didn't run: {error}")
        self.seconds[run] = time.monotonic() - start
        after = tree_state(self.package.root)
        self.tree_changes[run] = [name for name in before if before[name] != after[name]]
        self.exits[run] = result.returncode
        self.stderr[run] = result.stderr.decode("utf-8", errors="replace")
        self.raw[run] = result.stdout
        if self.output_dir:
            os.makedirs(self.output_dir, exist_ok=True)
            with open(os.path.join(self.output_dir, f"outskirts-{run}.json"), "wb") as handle:
                handle.write(result.stdout)
            with open(os.path.join(self.output_dir, f"outskirts-{run}.stderr"), "w", encoding="utf-8") as handle:
                handle.write(self.stderr[run])
        self.entries[run] = None
        self.problems[run] = []
        if result.returncode != 0:
            return
        try:
            entries = json.loads(result.stdout.decode("utf-8"))
        except (UnicodeDecodeError, ValueError) as error:
            self.problems[run] = [f"stdout isn't JSON: {error}"]
            return
        self.problems[run] = format_problems(entries, run)
        if not self.problems[run]:
            self.entries[run] = entries

    def decoded(self, entry, run):
        """One entry as the stored declaration fields (design 5.3 and 9.1)."""
        raw = entry["hints"][0]
        match = HINT_WITH_TEXT.fullmatch(raw)
        hint, text = (match.group(1), match.group(2)) if match else (raw, None)
        path, line, column = split_location(entry["location"])
        real = self.real(path)
        modules = tuple(self.described.by_module[module]["name"] if module in self.described.by_module else module
                        for module in entry["modules"])
        if is_under(real, self.package.scratch):
            file = BUILD_FILE
        else:
            file = self.package.relative(real, modules[0] if modules else None, self.package.entry_spellings)
        return (run, hint, text, entry["kind"], entry["name"], entry["accessibility"], tuple(entry["attributes"]),
                tuple(entry["modifiers"]), tuple(entry["ids"]), modules, file, line, column)

    def real(self, path):
        try:
            return real_path(path, "a location's path") if os.path.isabs(path) else unicodedata.normalize("NFC", path)
        except ReadError:
            return unicodedata.normalize("NFC", path)

    def figures(self, run):
        """Printed counts for one run: by hint, by kind, and where entries lie."""
        entries = self.entries.get(run) or []
        test_targets = {name for name, target in self.described.targets.items() if target["type"] == "test"}
        test_sources = set()
        for name in test_targets:
            test_sources |= self.described.targets[name]["sources"]
        figures = {"results": len(entries), "hints": Counter(), "kinds": Counter(), "test": 0, "build": 0,
                   "outsideRoot": 0, "missingFile": 0, "production": Counter()}
        for entry in entries:
            decoded = self.decoded(entry, run)
            hint, kind, modules, file = decoded[1], decoded[3], decoded[9], decoded[10]
            figures["hints"][hint] += 1
            figures["kinds"][kind] += 1
            path = split_location(entry["location"])[0]
            if not os.path.exists(path):
                figures["missingFile"] += 1
            if file == BUILD_FILE:
                figures["build"] += 1
            elif file is None:
                figures["outsideRoot"] += 1
            elif file in test_sources or (modules and all(module in test_targets for module in modules)):
                figures["test"] += 1
            else:
                figures["production"][f"{hint} {kind}"] += 1
        return figures


def periphery_collector(scan):
    for collector in scan.get("collectors", []):
        if collector.get("name") == "periphery":
            return collector
    return None


def option_flags(option):
    """The flags of an outskirts command line among a collector's options."""
    try:
        words = shlex.split(option)
    except ValueError:
        words = option.split()
    if "scan" not in words or "--format" not in words:
        return None
    return [word for word in words if word.startswith("--")]


def compare_status(verdict, runs, scan, version):
    """The scan's periphery collector status, version, options and inputs."""
    verdict.section("the periphery collector's status, version, options and inputs")
    collector = periphery_collector(scan)
    if collector is None:
        verdict.result("the scan lists the periphery collector", False, "absent")
        return False
    ran = collector.get("state") == "ran"
    verdict.result("the periphery collector ran", ran,
                   f"{collector.get('state')}" + (f", {collector.get('reason')}" if collector.get("reason") else ""))
    if not ran:
        return False
    verdict.result("its version is `outskirts version`'s output", collector.get("version") == version,
                   f"mine {version!r}, the scan's {collector.get('version')!r}")
    warned = VERSION_WARNING in (collector.get("reason") or "")
    should_warn = version != OUTSKIRTS_CHECKED_VERSION
    verdict.result("the version warning is given exactly when the version isn't " + OUTSKIRTS_CHECKED_VERSION,
                   warned == should_warn, f"warned {warned}, version {version}")
    options = collector.get("options") or []
    retain_lines = [o for o in options if isinstance(o, str) and o.startswith("retain-public-modules:")]
    if len(retain_lines) != 1:
        verdict.result("one `retain-public-modules:` option", False, f"{len(retain_lines)} found")
    else:
        value = retain_lines[0].split(":", 1)[1].strip()
        listed = [] if value == "none" else [word for word in re.split(r"[,\s]+", value) if word]
        verdict.result("`retain-public-modules:` names my retained modules by target name, sorted",
                       listed == sorted(runs.retained_targets),
                       f"mine {', '.join(sorted(runs.retained_targets)) or 'none'}; the scan's {value!r}")
    lines = [(o, option_flags(o)) for o in options if isinstance(o, str)]
    lines = [(o, flags) for o, flags in lines if flags is not None]
    theirs = {("production" if "--exclude-tests" in flags else "roots"): flags for _, flags in lines}
    if len(lines) != 2 or len(theirs) != 2:
        verdict.result("two outskirts command lines among the options, one with --exclude-tests", False,
                       f"{len(lines)} found")
        verdict.listing(o for o, _ in lines)
    else:
        for run in DEAD_RUNS:
            mine = [word for word in runs.commands[run] if word.startswith("--")]
            verdict.result(f"the {run} command line in the options names my flags, in order", theirs[run] == mine,
                           "" if theirs[run] == mine else f"mine {' '.join(mine)}; the scan's {' '.join(theirs[run])}")
    config = os.path.join(runs.package.scratch, OUTSKIRTS_CONFIG)
    size = os.path.getsize(config) if os.path.isfile(config) else None
    verdict.result(f"{BUILD_DIRECTORY}/{OUTSKIRTS_CONFIG} exists and is empty", size == 0,
                   "absent" if size is None else f"{size} bytes")
    describe_path = os.path.join(runs.package.scratch, T1_DESCRIBE)
    try:
        with open(describe_path, encoding="utf-8") as handle:
            theirs_describe = json.load(handle)
        described_path = theirs_describe.get("path")
        same_package = isinstance(described_path, str) and os.path.isabs(described_path) \
            and real_path(described_path, "the T1 describe's path") == runs.package.root
        verdict.result(f"{BUILD_DIRECTORY}/{T1_DESCRIBE} describes the package", same_package,
                       f"path {described_path!r}")
        with open(runs.describe_path, encoding="utf-8") as handle:
            mine_describe = json.load(handle)
        verdict.info("the T1 describe " + ("equals" if mine_describe == theirs_describe else
                                            "differs from (printed, not failed)") + " the describe the runs used")
    except (OSError, ValueError, ReadError) as error:
        verdict.result(f"{BUILD_DIRECTORY}/{T1_DESCRIBE} reads as JSON", False, str(error))
    return True


def compare_kept(verdict, runs, arguments):
    verdict.section("my runs' sorted output against the files the collector kept")
    for run in DEAD_RUNS:
        path = getattr(arguments, f"{run}_file") or os.path.join(runs.package.scratch, KEPT_OUTPUT[run])
        if not os.path.isfile(path):
            verdict.result(f"{run}: the kept file exists", False, f"{path} absent")
            continue
        with open(path, "rb") as handle:
            kept_bytes = handle.read()
        try:
            kept = json.loads(kept_bytes.decode("utf-8"))
        except (UnicodeDecodeError, ValueError) as error:
            verdict.result(f"{run}: the kept file is JSON", False, f"{path}: {error}")
            continue
        if not isinstance(kept, list):
            verdict.result(f"{run}: the kept file is a JSON array", False, f"{path}: {type(kept).__name__}")
            continue
        if runs.entries.get(run) is None:
            verdict.result(f"{run}: my run read, to compare", False, "my run failed or didn't read")
            continue
        compare_multisets(verdict, f"{run}: entries equal as sorted canonical JSON ({path})",
                          [canonical(e) for e in runs.entries[run]], [canonical(e) for e in kept], "kept")
        verdict.info(f"{run}: the kept file's bytes " + ("equal" if kept_bytes == runs.raw[run] else "differ from")
                     + " my run's stdout (printed, not failed)")


def stored_tuple(item, run_default=None):
    """A stored declaration (scan JSON object or store row) as the decoded fields."""
    def value(*names):
        found = lookup(item, *names)
        return None if found is MISSING else found
    hint = value("hint")
    text = value("hintText", "hint_text")
    if isinstance(text, str) and isinstance(hint, str) and text.startswith(hint + "(") and text.endswith(")"):
        text = text[len(hint) + 1:-1]
    file = value("file", "location.file")
    if isinstance(file, str) and file.startswith(BUILD_DIRECTORY + "/"):
        file = BUILD_FILE
    return (value("run") or run_default, hint, text, value("kind"), value("name"), value("accessibility"),
            as_list(value("attributes")), as_list(value("modifiers")), as_list(value("ids")),
            as_list(value("modules")), file, value("line", "location.line"), value("column", "location.column"))


def compare_declarations(verdict, runs, where, results, declarations):
    """Results per run and the declarations (with ordinals when given)."""
    for run in DEAD_RUNS:
        entries = runs.entries.get(run)
        if entries is None:
            verdict.result(f"{where}: {run}: my run read, to compare", False, "my run failed or didn't read")
            continue
        verdict.result(f"{where}: {run}: results", results.get(run) == len(entries),
                       f"mine {len(entries)}, {where}'s {results.get(run, 'absent')}")
        mine = [runs.decoded(entry, run) for entry in entries]
        theirs = [(ordinal, item) for ordinal, item in declarations if item[0] == run]
        compare_multisets(verdict, f"{where}: {run}: declarations (" + ", ".join(DECLARATION_FIELDS) + ")",
                          mine, [item for _, item in theirs], where)
        ordinals = [ordinal for ordinal, _ in theirs if ordinal is not None]
        if not ordinals:
            verdict.info(f"{where}: {run}: no ordinals given")
            continue
        base = min(ordinals)
        contiguous = sorted(ordinals) == list(range(base, base + len(theirs))) and base in (0, 1)
        verdict.result(f"{where}: {run}: ordinals contiguous from 0 or 1", contiguous,
                       f"{len(ordinals)} ordinals of {len(theirs)}, from {base}")
        if contiguous:
            out_of_order = [f"ordinal {ordinal}: {item}" for ordinal, item in theirs
                            if ordinal - base >= len(mine) or mine[ordinal - base] != item]
            verdict.result(f"{where}: {run}: ordinal k is outskirts' k-th entry", not out_of_order,
                           f"{len(out_of_order)} differ" if out_of_order else "")
            verdict.listing(out_of_order)


def compare_scan_block(verdict, runs, scan):
    verdict.section("my runs against the scan JSON's deadCode block (design 9.2)")
    block = scan.get("deadCode")
    if not isinstance(block, dict):
        verdict.info("the scan JSON has no deadCode block: stored entries not compared (printed, not failed)")
        return False
    results = {}
    for item in block.get("runs") or []:
        if isinstance(item, dict):
            results[item.get("name")] = item.get("results")
    declarations = []
    for item in block.get("declarations") or []:
        if isinstance(item, dict):
            ordinal = item.get("ordinal")
            declarations.append((ordinal if isinstance(ordinal, int) else None, stored_tuple(item)))
    compare_declarations(verdict, runs, "the scan JSON", results, declarations)
    return True


def binary_label(outskirts_real):
    """The label BinaryIdentity gives a binary in its clean tree's .build
    (design 1): `git:<HEAD>` plus ` (<tag>)`; (label, why not) otherwise."""
    parts = outskirts_real.split("/")
    if ".build" not in parts:
        return None, "the binary isn't under a .build directory"
    index = len(parts) - 1 - parts[::-1].index(".build")
    tree = "/".join(parts[:index])
    head = git_text(tree, "rev-parse", "HEAD")
    if head is None:
        return None, f"{tree} isn't a git work tree"
    if git_text(tree, "status", "--porcelain") != "":
        return None, f"{tree} isn't clean"
    tag = git_text(tree, "describe", "--exact-match", "--tags", head)
    return f"git:{head}" + (f" ({tag})" if tag else ""), None


def compare_store_rows(verdict, runs, store_path, snapshot, outskirts_real, version):
    import sqlite3

    verdict.section(f"my runs against the store ({store_path})")
    connection = sqlite3.connect(f"file:{store_path}?mode=ro", uri=True)
    try:
        if snapshot is None:
            snapshot = connection.execute("SELECT max(id) FROM snapshot").fetchone()[0]
        verdict.info(f"snapshot {snapshot}")
        row = connection.execute("SELECT state, identity, identityLabel, version FROM collectorRun "
                                 "WHERE snapshotId = ? AND name = 'periphery'", (snapshot,)).fetchone()
        if row is None:
            verdict.result("a periphery collectorRun row", False, "absent")
        else:
            state, identity, label, stored_version = row
            verdict.result("its state is ran", state == "ran", str(state))
            expected = "sha256:" + sha256_of(outskirts_real)
            verdict.result("its identity is sha256: + the binary's SHA-256", identity == expected,
                           f"mine {expected}, stored {identity}")
            verdict.result("its version is `outskirts version`'s output", stored_version == version,
                           f"mine {version!r}, stored {stored_version!r}")
            mine_label, why_not = binary_label(outskirts_real)
            if label is None:
                verdict.info(f"no label stored (printed, not failed; mine would be {mine_label or why_not})")
            else:
                verdict.result("its label is git:<commit> (<tag>) of the binary's clean tree", label == mine_label,
                               f"mine {mine_label or why_not}, stored {label}")
        tables = {name for (name,) in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
        if not {"deadScan", "deadDeclaration"} <= tables:
            verdict.info("the store has no deadScan and deadDeclaration tables: rows not compared "
                         "(printed, not failed)")
            return
        connection.row_factory = sqlite3.Row
        scan_row = connection.execute("SELECT * FROM deadScan WHERE snapshotId = ?", (snapshot,)).fetchone()
        if scan_row is None:
            verdict.result("a deadScan row", False, "absent")
            return
        results = {"roots": scan_row["rootsResults"], "production": scan_row["productionResults"]}
        verdict.result("deadScan.version is `outskirts version`'s output", scan_row["version"] == version,
                       f"mine {version!r}, stored {scan_row['version']!r}")
        declarations = []
        for item in connection.execute("SELECT * FROM deadDeclaration WHERE snapshotId = ?", (snapshot,)):
            item = dict(item)
            declarations.append((item.get("ordinal"), stored_tuple(item)))
        compare_declarations(verdict, runs, "the store", results, declarations)
    finally:
        connection.close()


def report_runs_own(verdict, runs, version, outskirts_real, library_targets, with_data):
    verdict.section("my outskirts runs (design 5.2)")
    verdict.info(f"outskirts {outskirts_real}, version {version}, sha256:{sha256_of(outskirts_real)}")
    if version != OUTSKIRTS_CHECKED_VERSION:
        verdict.info(f"note: not the version SwiftStats was checked against ({OUTSKIRTS_CHECKED_VERSION})")
    verdict.info("library-product targets: " + (", ".join(sorted(library_targets)) or "none")
                 + "; with kept or variant units: " + (", ".join(sorted(library_targets & with_data)) or "none"))
    verdict.info("retained (C99, byte order): " + (" ".join(runs.retained) or "none (flag left out)"))
    replacements = [(runs.package.scratch, BUILD_FILE), (runs.config, "<config>"),
                    (runs.describe_path, "<describe>"), (runs.outskirts, "outskirts")]
    for run in DEAD_RUNS:
        verdict.info(f"{run}: {printable_command(runs.commands[run], replacements)}")
        verdict.result(f"{run}: outskirts exited 0", runs.exits[run] == 0,
                       f"exit {runs.exits[run]}, {runs.seconds[run]:.2f} s")
        if runs.exits[run] != 0:
            verdict.listing(runs.stderr[run].rstrip("\n").split("\n")[-20:])
        unscanned = [line for line in runs.stderr[run].split("\n") if UNSCANNED_RETAINED in line]
        verdict.result(f"{run}: no retained module left unscanned", not unscanned,
                       unscanned[0].strip() if unscanned else "")
        verdict.result(f"{run}: the package left as it was (git status --ignored, .build, Package.resolved, root names)",
                       not runs.tree_changes[run], ", ".join(runs.tree_changes[run]))
        if runs.exits[run] == 0:
            verdict.result(f"{run}: the output is an array of entries with the nine keys", not runs.problems[run],
                           f"{len(runs.problems[run])} problems" if runs.problems[run] else "")
            verdict.listing(runs.problems[run])
        figures = runs.figures(run)
        verdict.info(f"{run}: {figures['results']} results; test targets {figures['test']}, under the build "
                     f"directory {figures['build']}, outside the root {figures['outsideRoot']}, file missing "
                     f"{figures['missingFile']}, other {sum(figures['production'].values())}")
        verdict.info(f"{run}: by hint: " + (", ".join(f"{k} {v}" for k, v in sorted(figures["hints"].items()))
                                            or "none"))
        verdict.info(f"{run}: by kind: " + (", ".join(f"{k} {v}" for k, v in sorted(figures["kinds"].items()))
                                            or "none"))
        verdict.info(f"{run}: outside test targets, by hint and kind: "
                     + (", ".join(f"{k} {v}" for k, v in sorted(figures["production"].items())) or "none"))


# --------------------------------------------------------------------------
# dead, mapping part: classes, the records each entry covers, dead lines and
# the line ratio (design sections 5.3, 5.4, 7, 9.1, 9.2 and 11; plan step 6b)

ENTRY_CLASSES = ("build", "outsideRoot", "test", "unscanned", "fileChanged", "local", "production")
DROPPED_CLASSES = ENTRY_CLASSES[:-1]
# outskirts' nominal kinds and the TypeRecord kinds each is compatible with
# (actors are classes in the index and in outskirts).
NOMINAL_ENTRY_KINDS = {"class": {"class", "actor"}, "struct": {"struct"}, "enum": {"enum"},
                       "protocol": {"protocol"}}
VIA_NAMES = ("usr", "property", "type", "extension", "location")
# outskirts' accessor kinds and the record accessor kinds they stand for.
OUTSKIRTS_ACCESSORS = {
    "function.accessor.getter": {"get"}, "function.accessor.setter": {"set"},
    "function.accessor.willset": {"willSet"}, "function.accessor.didset": {"didSet"},
    "function.accessor.read": {"_read", "read"}, "function.accessor.modify": {"_modify", "modify"},
    "function.accessor.address": {"unsafeAddress"},
    "function.accessor.mutableaddress": {"unsafeMutableAddress"}, "function.accessor.init": {"init"},
}
# Design 10.1's kinds for unused production declarations.
KIND_GROUPS = ("function", "type", "extension", "property", "enumCase", "parameter", "import", "other")
DESIGN_CLASSES_RULE = ("build, outside the root, test targets (the scanned file's target; an unscanned file's test "
                       "directory or modules), unscanned, files changed during the scan, local declarations (index "
                       "local property, or a variable inside a function record), else production")
DESIGN_MAP_RULE = ("outermost unused declarations: by USR to the record (a property's accessor records by role-free "
                   "accessorOf), a type to every record it owns in any file (extensions folded, as outskirts folds "
                   "them), an extension to the records in its range, else a function by its name position; others "
                   "attached for listing")


def kind_group(kind):
    """Design 10.1's kind for an outskirts kind."""
    if kind.startswith("function"):
        return "function"
    if kind in NOMINAL_ENTRY_KINDS:
        return "type"
    if kind.startswith("extension"):
        return "extension"
    if kind == "var.parameter":
        return "parameter"
    if kind.startswith("var."):
        return "property"
    if kind == "enumelement":
        return "enumCase"
    if kind == "module":
        return "import"
    return "other"


def function_record_for(kind, record):
    """Design 3.2's table read by outskirts' function kind (rule 5)."""
    if record["kind"] == "topLevel":
        return False
    if kind in OUTSKIRTS_ACCESSORS:
        return record["kind"] == "accessor" and (record.get("accessorKind") or "get") in OUTSKIRTS_ACCESSORS[kind]
    if kind == "function.constructor":
        return record["kind"] == "init"
    if kind == "function.destructor":
        return record["kind"] == "deinit"
    if kind == "function.subscript":
        return record["kind"] == "subscript"
    return kind.startswith("function.") and record["kind"] == "func"


def within(inner, outer):
    """Whether range `inner` lies in range `outer` (both ((l, c), (l, c)))."""
    return outer[0] <= inner[0] and inner[1] <= outer[1]


def nested_identity(inner, outer):
    """Design 4.3's nesting of type identities (module, typePath, typeFile):
    same module, the inner path the outer's plus '.', the outer's typeFile ''
    or the inner's."""
    return inner[0] == outer[0] and outer[2] in ("", inner[2]) and inner[1].startswith(outer[1] + ".")


def normalized_name(text):
    return re.sub(r"[^a-z0-9]", "", str(text).lower())


class SourceTypes:
    """T0's type records with design 4.3's identities, and the records'
    identities by T0's typePath (the mapping without the index)."""

    def __init__(self, package):
        self.package = package
        self.types = package.scan.get("types", [])
        self.by_file = defaultdict(list)
        for record in self.types:
            self.by_file[record["file"]].append(record)
        self.scoped_cache = {}

    def scoped(self, path):
        if path not in self.scoped_cache:
            try:
                with open(os.path.join(self.package.root, path), encoding="utf-8", errors="replace") as handle:
                    source = handle.read()
            except OSError:
                source = ""
            self.scoped_cache[path] = file_scoped_paths(self.by_file.get(path, []), source)
        return self.scoped_cache[path]

    def identity(self, record):
        """(module, typePath, typeFile) of a type record; typeFile the file
        for a private or fileprivate type (or one nested in one), else ''."""
        if record.get("isLocal"):
            return (record["module"], record["name"], "")
        return (record["module"], record["name"], record["file"] if scoped_by(record["name"], self.scoped(record["file"]))
                else "")

    def record_identity(self, record):
        """A function record's owning type by T0: (module, typePath, typeFile), None without a typePath."""
        path = record.get("typePath")
        if not path:
            return None
        return (record["module"], path, record["file"] if scoped_by(path, self.scoped(record["file"])) else "")

    def innermost(self, path, line, column, kinds):
        holding = [t for t in self.by_file.get(path, []) if t["kind"] in kinds and holds(t, line, column)]
        if not holding:
            return None
        return min(holding, key=lambda t: ((-range_of(t)[0][0], -range_of(t)[0][1]), range_of(t)[1], t["name"]))

    def type_name(self, record):
        identity = self.identity(record)
        return f"{identity[0]}::{identity[1]}" + (f" @ {identity[2]}" if identity[2] else "")


class DeadMapping:
    """Design 5.3's classes and 5.4's mapping and dead lines, over this
    script's own runs (and, when the scan's index ran, its own join and type
    ownership, `usr`'s u2 and u7 read)."""

    def __init__(self, package, describe, described, runs, join, coupling, local_rule, map_hints, base):
        self.package = package
        self.described = described
        self.runs = runs
        self.join = join
        self.coupling = coupling
        self.with_index = join is not None
        self.local_rule = local_rule
        self.map_hints = map_hints
        self.base = base
        self.types = SourceTypes(package)
        self.records = [r for r in package.records]
        self.function_records = [r for r in self.records if r["kind"] != "topLevel"]
        self.notes = Counter()
        self.test_targets = {name for name, target in described.targets.items() if target["type"] == "test"}
        # A test target's directory as the manifest spells it, as an
        # unscanned file's path is spelled (a describe source's spelling).
        self.test_directories = []
        for target in describe.get("targets", []):
            if target.get("type") != "test" or not target.get("path"):
                continue
            location = unicodedata.normalize("NFC", os.path.normpath(
                os.path.join(package.root, package.spellings.restore(target["path"]))))
            if not is_under(location, package.root):
                # An absolute path under another spelling of the root.
                location = resolved(location)
            if is_under(location, package.root) and location != package.root:
                self.test_directories.append(location[len(package.root) + 1:])
        self.local_usrs = set()
        self.record_by_usr = {}
        if self.with_index:
            for occurrences in join.occurrences_by_file.values():
                for occurrence in occurrences:
                    if occurrence["roles"] & ROLE_DEFINITION and occurrence["properties"] & PROPERTY_LOCAL:
                        self.local_usrs.add(occurrence["usr"])
            for key, usr in join.primary.items():
                self.record_by_usr.setdefault(usr, set()).add(key)
            for key, usr in join.secondary.items():
                self.record_by_usr.setdefault(usr, set()).add(key)
        self.parents = {}
        for record in self.records:
            if record.get("parentKey"):
                self.parents[record["key"]] = record["parentKey"]
        self.entries = {}       # run -> [entry dict], in outskirts' order
        for run in DEAD_RUNS:
            self.entries[run] = [self.entry(run, index, raw) for index, raw in enumerate(runs.entries.get(run) or [])]
        self.rows = {run: self.dead_records(self.entries[run]) for run in DEAD_RUNS}
        self.dead = {run: self.dead_set(self.entries[run]) for run in DEAD_RUNS}
        self.lines = {run: self.dead_lines(self.entries[run]) for run in DEAD_RUNS}

    # ---- classes (design 5.3)

    def in_record(self, path, line, column):
        return any(r["kind"] != "topLevel" and holds(r, line, column) for r in self.package.records_by_file.get(path, []))

    def entry_class(self, decoded):
        run, hint, text, kind, name, accessibility, attributes, modifiers, ids, modules, file, line, column = decoded
        if file == BUILD_FILE:
            return "build"
        if file is None:
            return "outsideRoot"
        scanned = self.package.files.get(file)
        if scanned is None:
            if any(file.startswith(directory + "/") for directory in self.test_directories) \
                    or (modules and all(module in self.test_targets for module in modules)):
                return "test"
            return "unscanned"
        if scanned.get("module") in self.test_targets:
            return "test"
        if file in self.package.changed:
            return "fileChanged"
        variable = kind.startswith("var.")
        if self.local_rule == "literal":
            index_rule = self.with_index and any(usr in self.local_usrs for usr in ids)
            position_rule = variable and self.in_record(file, line, column)
        else:
            eligible = variable and kind != "var.parameter"
            index_rule = eligible and self.with_index and any(usr in self.local_usrs for usr in ids)
            position_rule = eligible and self.in_record(file, line, column)
        if index_rule or position_rule:
            return "local"
        return "production"

    # ---- mapping (design 5.4)

    def entry(self, run, index, raw):
        decoded = self.runs.decoded(raw, run)
        entry = {"run": run, "ordinal": index + self.base, "decoded": decoded, "hint": decoded[1],
                 "kind": decoded[3], "name": decoded[4], "ids": decoded[8], "file": decoded[10],
                 "line": decoded[11], "column": decoded[12], "class": self.entry_class(decoded),
                 "via": None, "covers": [], "unit": None, "lines": None, "mapped": False}
        entry["place"], entry["owner"] = self.place(entry)
        if entry["class"] == "production" and (self.map_hints == "all" or entry["hint"] == "unused"):
            entry["mapped"] = True
            self.map_entry(entry)
        return entry

    def place(self, entry):
        """Where an entry is listed: the innermost record holding its
        position, else the innermost type record, else the file."""
        if entry["file"] in (None, BUILD_FILE) or entry["file"] not in self.package.files:
            return None, None
        path, line, column = entry["file"], entry["line"], entry["column"]
        holding = [r for r in self.package.records_by_file.get(path, []) if holds(r, line, column)]
        if holding:
            return "function", innermost(holding)["key"]
        record = self.types.innermost(path, line, column, {"struct", "class", "actor", "enum", "protocol",
                                                           "extension"})
        if record is not None:
            return "type", self.types.type_name(record)
        return "file", path

    def map_entry(self, entry):
        kind, ids = entry["kind"], entry["ids"]
        path, line, column = entry["file"], entry["line"], entry["column"]
        if self.with_index:
            keys = set()
            for usr in ids:
                keys |= self.record_by_usr.get(usr, set())
            if keys:
                return self.cover(entry, "usr", sorted(keys))
            if kind.startswith("var."):
                accessors = []
                for usr in ids:
                    accessors += [key for key, _ in self.coupling.accessors_of.get(usr, [])]
                if accessors:
                    return self.cover(entry, "property", sorted(set(accessors)))
        if kind in NOMINAL_ENTRY_KINDS:
            if self.with_index:
                usr = next((usr for usr in ids if usr in self.coupling.types), None)
                if usr is None:
                    self.notes["type entries naming no package type by USR (cover nothing)"] += 1
                    return None
                return self.cover_type(entry, self.coupling.types[usr]["record"], usr)
            record = self.types.innermost(path, line, column, NOMINAL_ENTRY_KINDS[kind])
            if record is None:
                self.notes["type entries with no compatible type record at their position (cover nothing)"] += 1
                return None
            return self.cover_type(entry, record, None)
        if kind.startswith("extension"):
            record = self.types.innermost(path, line, column, {"extension"})
            if record is None:
                self.notes["extension entries with no extension record at their position (cover nothing)"] += 1
                return None
            inside = [r["key"] for r in self.package.records_by_file.get(path, [])
                      if r["kind"] != "topLevel" and within(range_of(r), range_of(record))]
            entry["unit"] = ("extension", record["file"], range_of(record))
            entry["unit_record"] = record
            entry["lines"] = record.get("strippedLines")
            return self.cover(entry, "extension", sorted(inside), lines_from_records=False)
        if kind.startswith("function"):
            if self.with_index:
                self.notes["function entries matching no record by USR (index ran: no position fallback)"] += 1
                entry["unmatched_function"] = True
                return None
            holding = [r for r in self.package.records_by_file.get(path, [])
                       if function_record_for(kind, r) and holds(r, line, column)]
            if holding:
                return self.cover(entry, "location", [innermost(holding)["key"]])
            entry["unmatched_function"] = True
            self.notes["function entries with no compatible record at their position"] += 1
        return None

    def cover(self, entry, via, keys, lines_from_records=True):
        entry["via"] = via
        entry["covers"] = keys
        if lines_from_records and keys:
            entry["lines"] = sum(self.package.by_key[key].get("strippedLines") or 0 for key in keys)
        return keys

    def type_extensions(self, record, usr):
        """A covered type's extension records: with the index, those whose
        extension the type's USR owns (design 4.3); without it, extension
        records of the same target naming the type's path (in its file, for a
        file-scoped type)."""
        identity = self.types.identity(record)
        out = []
        for candidate in self.types.types:
            if candidate["kind"] != "extension":
                continue
            if usr is not None:
                extension = self.coupling.extension_of_record.get(id(candidate))
                if extension is not None and self.coupling.owner(extension) == usr:
                    out.append(candidate)
            elif candidate["module"] == identity[0] and candidate["name"] == identity[1] \
                    and identity[2] in ("", candidate["file"]):
                out.append(candidate)
        return out

    def owned(self, record, type_usr, identity):
        """Whether a function record's owning type is the covered type or a
        type nested in it: by the record's USR with the index (a record
        without a primary USR, such as one in an inactive #if branch, falls
        back to T0's typePath), else by T0's typePath, target and typeFile."""
        if type_usr is not None and record["key"] in self.join.primary:
            owner = self.coupling.owner(self.join.primary[record["key"]])
            if owner is None:
                return False
            if owner == type_usr:
                return True
            entry = self.coupling.types.get(owner)
            return entry is not None and nested_identity(entry["identity"], identity)
        owner = self.types.record_identity(record)
        result = owner is not None and (owner == identity or nested_identity(owner, identity))
        if result and type_usr is not None:
            self.notes["records without a primary USR covered by a type through T0's typePath"] += 1
        return result

    def cover_type(self, entry, record, usr):
        identity = self.types.identity(record)
        extensions = self.type_extensions(record, usr)
        keys = [r["key"] for r in self.function_records if self.owned(r, usr, identity)]
        entry["unit"] = ("type",) + identity
        entry["unit_record"] = record
        entry["unit_extensions"] = extensions
        entry["lines"] = (record.get("strippedLines") or 0) + sum(e.get("strippedLines") or 0 for e in extensions)
        return self.cover(entry, "type", sorted(keys), lines_from_records=False)

    # ---- per run

    def dead_records(self, entries):
        """deadRecord rows: each covered record once, the lower ordinal winning."""
        rows = {}
        for entry in sorted(entries, key=lambda e: e["ordinal"]):
            for key in entry["covers"]:
                rows.setdefault(key, (entry["ordinal"], entry["via"]))
        return rows

    def dead_set(self, entries):
        """Records dead in a run: covered by a production entry with hint unused."""
        return {key for entry in entries if entry["class"] == "production" and entry["hint"] == "unused"
                for key in entry["covers"]}

    def units(self, entries):
        """Design 5.4's covered units of a run: type entries (the type and its
        extension records), extension entries and function records covered
        with hint unused, each once."""
        units = {}
        for entry in entries:
            if entry["class"] != "production" or entry["hint"] != "unused":
                continue
            unit = entry.get("unit")
            if unit is not None and unit not in units:
                record = entry["unit_record"]
                if unit[0] == "type":
                    parts = [record] + entry["unit_extensions"]
                    units[unit] = {"kind": "type", "identity": unit[1:], "record": record,
                                   "regions": [(p["file"], range_of(p)) for p in parts],
                                   "extensions": {(p["file"], range_of(p)) for p in entry["unit_extensions"]},
                                   "parts": [(p["module"], p.get("strippedLines") or 0) for p in parts]}
                else:
                    units[unit] = {"kind": "extension", "record": record, "regions": [(record["file"], range_of(record))],
                                   "parts": [(record["module"], record.get("strippedLines") or 0)]}
            for key in entry["covers"]:
                if ("record", key) not in units:
                    record = self.package.by_key[key]
                    units[("record", key)] = {"kind": "record", "key": key, "record": record,
                                              "regions": [(record["file"], range_of(record))],
                                              "parts": [(record["module"], record.get("strippedLines") or 0)]}
        return units

    def ancestors(self, key):
        seen = []
        current = self.parents.get(key)
        while current is not None and current not in seen:
            seen.append(current)
            current = self.parents.get(current)
        return seen

    def contains(self, outer, inner):
        """Whether covered unit `outer` holds covered unit `inner` (design 5.4:
        a function record inside a covered type's body or one of its
        extensions, or below a covered ancestor record; a nested type inside a
        covered type; an extension of a covered type; and anything lying in a
        covered extension's or record's range)."""
        main = inner["regions"][0]
        if outer["kind"] == "record" and inner["kind"] == "record":
            return outer["key"] in self.ancestors(inner["key"])
        if outer["kind"] == "type":
            if inner["kind"] == "type" and nested_identity(inner["identity"], outer["identity"]):
                return True
            if inner["kind"] == "extension" and main in outer["extensions"]:
                return True
        return any(main[0] == region[0] and within(main[1], region[1]) and main != region
                   for region in outer["regions"])

    def maximal(self, units):
        keys = sorted(units, key=str)
        out = []
        for key in keys:
            unit = units[key]
            held = False
            for other_key in keys:
                if other_key == key:
                    continue
                other = units[other_key]
                if self.contains(other, unit):
                    if self.contains(unit, other) and str(key) < str(other_key):
                        continue
                    held = True
                    break
            if not held:
                out.append(key)
        return out

    def dead_lines(self, entries):
        """{module: dead lines} over the maximal covered units."""
        units = self.units(entries)
        lines = Counter()
        for key in self.maximal(units):
            for module, count in units[key]["parts"]:
                lines[module] += count
        return dict(lines)

    def unit_listing(self, run):
        units = self.units(self.entries[run])
        maximal = set(self.maximal(units))
        out = []
        for key in sorted(units, key=str):
            unit = units[key]
            label = (f"type {unit['identity'][0]}::{unit['identity'][1]}" if unit["kind"] == "type"
                     else f"extension {unit['record']['name']} @ {unit['record']['file']}:{range_of(unit['record'])[0][0]}"
                     if unit["kind"] == "extension" else f"record {unit['key']}")
            out.append(f"{'maximal' if key in maximal else 'held   '} {label}: "
                       + "+".join(str(count) for _, count in unit["parts"]) + " lines")
        return out

    def order_independent(self):
        """Dead lines recomputed over the entries reversed and shuffled
        (ordinals kept) equal the original (design 5.4)."""
        import random

        problems = []
        for run in DEAD_RUNS:
            original = self.lines[run]
            reversed_entries = list(reversed(self.entries[run]))
            shuffled = list(self.entries[run])
            random.Random(7).shuffle(shuffled)
            for name, entries in (("reversed", reversed_entries), ("shuffled", shuffled)):
                if self.dead_lines(entries) != original or self.dead_records(entries) != self.rows[run]:
                    problems.append(f"{run}: {name} order gives {self.dead_lines(entries)} instead of {original}")
        return problems

    # ---- figures

    def class_counts(self, run):
        counts = Counter(entry["class"] for entry in self.entries[run])
        return {name: counts.get(name, 0) for name in ENTRY_CLASSES}

    def unsized(self, run):
        """Unused production entries without a line count (design 5.4: properties
        without accessors, enum cases, parameters, imports, and entries that
        cover nothing): `deadCode.unsized`."""
        return [entry for entry in self.entries[run]
                if entry["class"] == "production" and entry["hint"] == "unused" and entry["lines"] is None]

    def entry_module(self, entry):
        info = self.package.files.get(entry["file"]) if entry["file"] else None
        return info.get("module") if info else None

    def figures(self):
        return {run: {"classes": self.class_counts(run),
                      "records": [{"key": key, "declaration": ordinal, "via": via}
                                  for key, (ordinal, via) in sorted(self.rows[run].items())],
                      "dead": sorted(self.dead[run]),
                      "deadLines": dict(sorted(self.lines[run].items())),
                      "unsized": len(self.unsized(run)),
                      "entries": [{"ordinal": e["ordinal"], "hint": e["hint"], "kind": e["kind"], "name": e["name"],
                                   "file": e["file"], "line": e["line"], "class": e["class"], "via": e["via"],
                                   "covers": e["covers"], "lines": e["lines"], "place": e["place"],
                                   "owner": e["owner"]} for e in self.entries[run]]}
                for run in DEAD_RUNS}


def ordinal_base(scan, arguments):
    """The first entry's ordinal: `--ordinal-base`, else the lowest ordinal
    the scan's declarations carry (0 or 1), else 1."""
    if arguments.ordinal_base is not None:
        return arguments.ordinal_base
    block = scan.get("deadCode")
    ordinals = [item.get("ordinal") for item in (block or {}).get("declarations") or []
                if isinstance(item, dict) and isinstance(item.get("ordinal"), int)]
    return min(ordinals) if ordinals and min(ordinals) in (0, 1) else 1


def ratio_modules(rollup, targets):
    """The production modules a roll-up's line ratio measures against
    (LineRatio's doc comment): a production module its own; a test target
    the production targets it depends on; the project every production
    target."""
    production = {t["name"] for t in targets if not t.get("isTest")}
    tests = {t["name"] for t in targets if t.get("isTest")}
    if rollup.get("scope") == "project":
        return production
    name = rollup.get("name")
    if name in tests:
        target = next(t for t in targets if t["name"] == name)
        return set(target.get("dependencies") or []) & production
    return {name}


def report_mapping_own(verdict, mapping):
    verdict.section("my classes and mapping (design 5.3 and 5.4)")
    how = ("with the index (my own join and type ownership, as usr u2 and u7 read them)" if mapping.with_index
           else "by position (--index-mode position, or the scan's index collector didn't run)")
    verdict.info(f"mapping {how}"
                 f"; local rule {mapping.local_rule}; hints mapped: {mapping.map_hints}; ordinals from {mapping.base}")
    for run in DEAD_RUNS:
        counts = mapping.class_counts(run)
        verdict.info(f"{run}: classes " + ", ".join(f"{name} {counts[name]}" for name in ENTRY_CLASSES))
        for entry in mapping.entries[run]:
            target = (f"{entry['via']} -> {len(entry['covers'])} record(s)" if entry["via"] else
                      ("not mapped" if entry["mapped"] else "-"))
            verdict.info(f"  {run} #{entry['ordinal']} {entry['class']:<11} {entry['hint']} {entry['kind']} "
                         f"{entry['name']} {entry['file']}:{entry['line']}  {target}; lines {entry['lines']}")
            if entry["via"] and len(entry["covers"]) <= 8:
                for key in entry["covers"]:
                    verdict.info(f"      covers {key}")
        verdict.info(f"{run}: deadRecord rows {len(mapping.rows[run])}; records dead {len(mapping.dead[run])}; "
                     f"dead lines " + (", ".join(f"{m} {n}" for m, n in sorted(mapping.lines[run].items())) or "none")
                     + f"; unsized {len(mapping.unsized(run))}")
        verdict.listing(f"unit {line}" for line in mapping.unit_listing(run))
    for note, count in sorted(mapping.notes.items()):
        verdict.info(f"note: {note}: {count}")
    problems = mapping.order_independent()
    verdict.result("dead lines and deadRecord rows don't depend on entry order (reversed, shuffled)", not problems)
    verdict.listing(problems)


def block_counts(value, name_keys, count_keys):
    """{run: {name: count}} from a block's per-run counts in any of the
    shapes {run: {name: n}}, {name: {run: n}}, {run: [{name, n}]} or
    [{run, name, n}]; None when it doesn't read."""
    def item_pair(item):
        name = next((item[key] for key in name_keys if key in item), MISSING)
        count = next((item[key] for key in count_keys if key in item), MISSING)
        return name, count

    result = defaultdict(dict)
    if isinstance(value, dict):
        if set(value) & set(DEAD_RUNS):
            for run, inner in value.items():
                if isinstance(inner, dict):
                    result[run].update(inner)
                elif isinstance(inner, list):
                    for item in inner:
                        if not isinstance(item, dict):
                            return None
                        name, count = item_pair(item)
                        if name is MISSING or count is MISSING:
                            return None
                        result[run][name] = count
                else:
                    return None
        else:
            for name, inner in value.items():
                if not isinstance(inner, dict):
                    return None
                for run, count in inner.items():
                    result[run][name] = count
    elif isinstance(value, list):
        for item in value:
            if not isinstance(item, dict) or "run" not in item:
                return None
            name, count = item_pair(item)
            if name is MISSING or count is MISSING:
                return None
            result[item["run"]][name] = count
    else:
        return None
    return result


def compare_counts(verdict, name, mine, theirs):
    """Per-run count dictionaries, a missing name read as 0 on either side."""
    for run in DEAD_RUNS:
        own = {k: v for k, v in mine.get(run, {}).items() if v}
        other = {k: v for k, v in (theirs.get(run) or {}).items() if v}
        verdict.result(f"{name}: {run}", own == other,
                       f"mine {dict(sorted(own.items()))}, the scan's {dict(sorted(other.items()))}")


def declaration_ordinal(value):
    if isinstance(value, bool):
        return None
    if isinstance(value, int):
        return value
    if isinstance(value, dict):
        found = value.get("ordinal", value.get("declaration"))
        return found if isinstance(found, int) and not isinstance(found, bool) else None
    return None


def compare_mapping_rows(verdict, mapping, where, declarations, records):
    """Classes per declaration and deadRecord rows per run."""
    for run in DEAD_RUNS:
        mine_entries = mapping.entries[run]
        theirs = [item for item in declarations if item["run"] == run]
        with_ordinals = [item for item in theirs if item["ordinal"] is not None]
        if with_ordinals and len(with_ordinals) == len(theirs):
            by_ordinal = {item["ordinal"]: item for item in theirs}
            differing = []
            for entry in mine_entries:
                item = by_ordinal.get(entry["ordinal"])
                if item is None or normalized_name(item["class"]) != normalized_name(entry["class"]):
                    differing.append(f"#{entry['ordinal']} {entry['kind']} {entry['name']} {entry['file']}:"
                                     f"{entry['line']}: mine {entry['class']}, {where}'s "
                                     f"{item['class'] if item else 'absent'}")
            verdict.result(f"{where}: {run}: each declaration's class (design 5.3)", not differing,
                           f"{len(mine_entries)} compared")
            verdict.listing(differing)
            listing = []
            for entry in mine_entries:
                item = by_ordinal.get(entry["ordinal"])
                if item is None:
                    continue
                for field in ("place", "owner"):
                    if item.get(field) is not MISSING and item.get(field) is not None \
                            and normalized_name(item[field]) != normalized_name(entry[field]):
                        listing.append(f"#{entry['ordinal']} {field}: mine {entry[field]}, {where}'s {item[field]}")
                if item.get("strippedLines") not in (MISSING, None) and item["strippedLines"] != entry["lines"]:
                    listing.append(f"#{entry['ordinal']} strippedLines: mine {entry['lines']}, "
                                   f"{where}'s {item['strippedLines']}")
            verdict.info(f"{where}: {run}: place, owner and strippedLines (listing only, printed, not failed): "
                         + (f"{len(listing)} differ" if listing else "agree where given"))
            verdict.listing(listing)
        else:
            mine = [(entry["decoded"], entry["class"]) for entry in mine_entries]
            other = [(item["decoded"], item["class"]) for item in theirs]
            compare_multisets(verdict, f"{where}: {run}: declarations with their class (no ordinals given)",
                              [str(item) for item in mine], [str(item) for item in other], where)
        mine_rows = {(run, key, ordinal, via) for key, (ordinal, via) in mapping.rows[run].items()}
        their_rows = {(run, item["key"], item["declaration"], item["via"]) for item in records if item["run"] == run}
        if any(row[2] is None for row in their_rows):
            mine_rows = {(r, k, None, v) for r, k, _, v in mine_rows}
            verdict.info(f"{where}: {run}: declaration references not read as ordinals: rows compared without them")
        only_mine = sorted(mine_rows - their_rows, key=str)
        only_theirs = sorted(their_rows - mine_rows, key=str)
        verdict.result(f"{where}: {run}: deadRecord rows (key, declaration, via)", not only_mine and not only_theirs,
                       f"{len(mine_rows)} mine, {len(their_rows)} {where}'s")
        verdict.listing(f"only mine: {row}" for row in only_mine)
        verdict.listing(f"only {where}'s: {row}" for row in only_theirs)


def scan_declaration(item):
    ordinal = item.get("ordinal")
    return {"run": item.get("run"), "ordinal": ordinal if isinstance(ordinal, int) and not isinstance(ordinal, bool)
            else None, "class": item.get("class", item.get("entryClass")), "place": item.get("place", MISSING),
            "owner": item.get("owner", MISSING), "strippedLines": item.get("strippedLines", MISSING),
            "decoded": stored_tuple(item)}


def compare_rule_options(verdict, scan):
    """The periphery collector's `classes:` and `map:` options (design 1.8):
    present, each once; text other than design 5.3's and 5.4's is printed."""
    options = [o for o in (periphery_collector(scan) or {}).get("options") or [] if isinstance(o, str)]
    for name, design in (("classes", DESIGN_CLASSES_RULE), ("map", DESIGN_MAP_RULE)):
        found = [o.split(":", 1)[1].strip() for o in options if o.startswith(name + ":")]
        verdict.result(f"the periphery collector's options hold one `{name}:` rule", len(found) == 1,
                       f"{len(found)} found")
        if len(found) == 1 and found[0] != design:
            verdict.info(f"its `{name}:` text differs from design's (printed, not failed): {found[0]}")


def compare_mapping_block(verdict, mapping, scan):
    verdict.section("my mapping against the scan JSON's deadCode block (design 9.2)")
    compare_rule_options(verdict, scan)
    block = scan.get("deadCode")
    if not isinstance(block, dict):
        state = (periphery_collector(scan) or {}).get("state")
        verdict.result("the scan JSON has a deadCode block (the periphery collector " + str(state) + ")",
                       state != "ran", "absent")
        return
    declarations = [scan_declaration(item) for item in block.get("declarations") or [] if isinstance(item, dict)]
    records = []
    for item in block.get("records") or []:
        if isinstance(item, dict):
            records.append({"run": item.get("run"), "key": item.get("key"),
                            "declaration": declaration_ordinal(item.get("declaration")), "via": item.get("via")})
    unknown_via = sorted({str(item["via"]) for item in records if item["via"] not in VIA_NAMES})
    verdict.result("every record's via is one of " + ", ".join(VIA_NAMES), not unknown_via, ", ".join(unknown_via))
    compare_mapping_rows(verdict, mapping, "the scan JSON", declarations, records)
    dropped = block_counts(block.get("dropped"), ("class", "name"), ("count", "results", "entries", "value"))
    if dropped is None:
        verdict.result("deadCode.dropped reads as counts per class and run", False,
                       json.dumps(block.get("dropped"))[:300])
    else:
        mine = {run: {name: count for name, count in mapping.class_counts(run).items() if name in DROPPED_CLASSES}
                for run in DEAD_RUNS}
        theirs = {run: {next((c for c in DROPPED_CLASSES if normalized_name(c) == normalized_name(k)), k): v
                        for k, v in inner.items()} for run, inner in dropped.items()}
        compare_counts(verdict, "dropped entries per class (design 5.3)", mine, theirs)
    lines = block_counts(block.get("deadLines"), ("module", "name", "target"),
                         ("lines", "deadLines", "count", "value"))
    if lines is None:
        verdict.result("deadCode.deadLines reads as lines per module and run", False,
                       json.dumps(block.get("deadLines"))[:300])
    else:
        compare_counts(verdict, "dead lines per module, maximal units (design 5.4)", mapping.lines, lines)


def compare_mapping_rollups(verdict, mapping, scan, ran):
    """LineRatio.deadLines and deadCodeExcluded (design 7) and the deadCode.*
    roll-ups design 10.3 names, per roll-up scope."""
    verdict.section("roll-ups: tests.lineRatio.deadLines and deadCodeExcluded (design 7), deadCode.* (10.3)")
    targets = scan.get("targets", [])
    files = scan.get("files", [])
    roots = mapping.lines["roots"]
    unused_by_scope = defaultdict(Counter)
    unsized_by_scope = Counter()
    test_targets = {t["name"] for t in targets if t.get("isTest")}
    for entry in mapping.entries["roots"]:
        if entry["class"] != "production" or entry["hint"] != "unused":
            continue
        module = mapping.entry_module(entry)
        scopes = [("module", module), ("project", "tests" if module in test_targets else "production")]
        for scope in scopes:
            unused_by_scope[scope][kind_group(entry["kind"])] += 1
            if entry["lines"] is None:
                unsized_by_scope[scope] += 1
    records_by_scope = {run: Counter() for run in DEAD_RUNS}
    for run in DEAD_RUNS:
        for key in mapping.dead[run]:
            record = mapping.package.by_key[key]
            records_by_scope[run][("module", record.get("module"))] += 1
            records_by_scope[run][("project", "production" if record.get("role") == "production" else "tests")] += 1
    present = Counter()
    for rollup in scan.get("rollups", []):
        label = f"{rollup.get('scope')} {rollup.get('name')}" + (f" {rollup['part']}" if rollup.get("part") else "")
        ratio = (rollup.get("tests") or {}).get("lineRatio")
        if isinstance(ratio, dict):
            modules = ratio_modules(rollup, targets)
            production_lines = sum(f.get("strippedLines") or 0 for f in files if f.get("module") in modules)
            same_scope = production_lines == ratio.get("productionLines")
            excluded = ratio.get("deadCodeExcluded")
            verdict.result(f"{label}: deadCodeExcluded is {ran} exactly as the periphery collector ran", excluded is ran,
                           f"the scan's {excluded}")
            theirs = ratio.get("deadLines", MISSING)
            mine = sum(roots.get(module, 0) for module in modules) if ran else None
            if not same_scope:
                verdict.info(f"{label}: my reading of the ratio's production modules gives {production_lines} "
                             f"production lines, the scan's {ratio.get('productionLines')}: deadLines compared anyway")
            if ran:
                verdict.result(f"{label}: tests.lineRatio.deadLines = the roots run's dead lines of "
                               + (", ".join(sorted(modules)) or "no module"),
                               theirs == mine, f"mine {mine}, the scan's {'absent' if theirs is MISSING else theirs}")
            else:
                verdict.result(f"{label}: tests.lineRatio.deadLines absent or null (periphery didn't run)",
                               theirs is MISSING or theirs is None, f"the scan's {theirs}")
        dead = rollup.get("deadCode")
        if not isinstance(dead, dict):
            continue
        present["deadCode"] += 1
        key = ("module", rollup.get("name")) if rollup.get("scope") == "module" else ("project", rollup.get("name"))
        for name, mine in (("records", records_by_scope["roots"].get(key, 0)),
                           ("productionRecords", records_by_scope["production"].get(key, 0)),
                           ("unsized", unsized_by_scope.get(key, 0))):
            if name in dead:
                verdict.result(f"{label}: deadCode.{name}", dead[name] == mine, f"mine {mine}, the scan's {dead[name]}")
            else:
                verdict.info(f"{label}: deadCode.{name} not in the roll-up (printed, not failed)")
        unused = dead.get("unused")
        if isinstance(unused, dict):
            theirs = {next((g for g in KIND_GROUPS if normalized_name(g) == normalized_name(k)), k): v
                      for k, v in unused.items() if v}
            mine = {k: v for k, v in unused_by_scope.get(key, Counter()).items() if v}
            verdict.result(f"{label}: deadCode.unused by kind (roots run)", theirs == mine,
                           f"mine {dict(sorted(mine.items()))}, the scan's {dict(sorted(theirs.items()))}")
        verdict.info(f"{label}: deadCode keys {', '.join(sorted(dead))}")
    if not present["deadCode"]:
        verdict.info("no roll-up holds a deadCode block: deadCode.* not compared (printed, not failed)")


def compare_mapping_store(verdict, mapping, store_path, snapshot):
    import sqlite3

    verdict.section(f"my mapping against the store ({store_path})")
    connection = sqlite3.connect(f"file:{store_path}?mode=ro", uri=True)
    try:
        if snapshot is None:
            snapshot = connection.execute("SELECT max(id) FROM snapshot").fetchone()[0]
        tables = {name for (name,) in connection.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
        if not {"deadDeclaration", "deadRecord"} <= tables:
            verdict.info("the store has no deadDeclaration and deadRecord tables: rows not compared "
                         "(printed, not failed)")
            return
        connection.row_factory = sqlite3.Row
        declarations = [scan_declaration(dict(row)) for row in
                        connection.execute("SELECT * FROM deadDeclaration WHERE snapshotId = ?", (snapshot,))]
        records = [{"run": row["run"], "key": row["key"], "declaration": declaration_ordinal(row["declaration"]),
                    "via": row["via"]}
                   for row in connection.execute("SELECT * FROM deadRecord WHERE snapshotId = ?", (snapshot,))]
        compare_mapping_rows(verdict, mapping, "the store", declarations, records)
    finally:
        connection.close()


def dead_mode(arguments):
    arguments.reader = None
    arguments.root_spelling = None
    arguments.build_spelling = None
    arguments.spelling = None
    try:
        package = UsrPackage(arguments)
    except (OSError, ValueError, ReadError) as error:
        fail(str(error))
    outskirts = os.path.abspath(arguments.outskirts)
    if not (os.path.isfile(outskirts) and os.access(outskirts, os.X_OK)):
        fail(f"{outskirts} is not an executable file")
    outskirts_real = real_path(outskirts, "outskirts")
    try:
        result = subprocess.run([outskirts, "version"], capture_output=True, text=True, timeout=120,
                                stdin=subprocess.DEVNULL)
    except (OSError, subprocess.TimeoutExpired) as error:
        fail(f"{outskirts} version didn't run: {error}")
    if result.returncode != 0:
        fail(f"{outskirts} version exited {result.returncode}: {result.stderr.strip()[:300]}")
    version = result.stdout.strip()
    index_state = next((c.get("state") for c in package.scan.get("collectors", []) if c.get("name") == "index"), None)
    use_index = not arguments.without_mapping and (
        arguments.index_mode == "index" or (arguments.index_mode == "auto" and index_state == "ran"))
    resource = None
    if arguments.library is None or (arguments.describe is None and not arguments.use_scan_inputs) \
            or (use_index and arguments.demangle is None):
        resource = toolchain_of(package.root, arguments.swift)
    if arguments.library is None:
        arguments.library = os.path.join(os.path.dirname(resource), "libIndexStore.dylib")
    demangler = arguments.demangle or (os.path.join(os.path.dirname(os.path.dirname(resource)), "bin", "swift-demangle")
                                       if resource else None)
    verdict = Verdict(arguments.all)
    temporary = tempfile.mkdtemp(prefix="index-check-dead-")
    try:
        if arguments.use_scan_inputs:
            describe_path = os.path.join(package.scratch, T1_DESCRIBE)
            config = os.path.join(package.scratch, OUTSKIRTS_CONFIG)
            with open(describe_path, encoding="utf-8") as handle:
                describe = json.load(handle)
        else:
            if arguments.describe:
                describe_path = os.path.abspath(arguments.describe)
                with open(describe_path, encoding="utf-8") as handle:
                    describe = json.load(handle)
            else:
                describe = run_describe(package.root,
                                        os.path.join(os.path.dirname(os.path.dirname(resource)), "bin", "swift"))
                describe_path = os.path.join(temporary, "describe.json")
                with open(describe_path, "w", encoding="utf-8") as handle:
                    json.dump(describe, handle, ensure_ascii=False)
            config = os.path.join(temporary, "outskirts.yml")
            open(config, "wb").close()
        described_path = describe.get("path")
        if not isinstance(described_path, str) or not os.path.isabs(described_path) \
                or real_path(described_path, "describe's path") != package.root:
            fail(f"the describe JSON describes {described_path!r}, not {package.root}")
        described = Described(describe, package)
        for path, entry in package.files.items():
            package.entry_spellings.add(path, entry.get("module"))
        for spelling, name in describe_sources(describe, package.root, package.spellings.restore):
            package.entry_spellings.add(spelling, name, fallback=True)
        join = coupling = None
        try:
            reader = UnitReader(package, arguments)
            try:
                classes = classify_units(reader.units, package, described)
                if use_index:
                    # The mapping's USRs and type ownership, as `usr` reads
                    # them (u2's join, u7's ownership; neither reading option
                    # of u7 changes ownership or accessorOf).
                    join = UsrJoin(package, described, reader, None)
                    coupling = Coupling(join, demangler, "enclosing", "package")
            finally:
                reader.close()
        except ReadError as error:
            fail(str(error))
        with_data = {described.by_module[unit["module"]]["name"] for unit in reader.units
                     if unit["location"] == "store" and classes[unit["name"]] in ("kept", "variant")}
        library_targets = {name for name in described.library_targets if name in described.targets}
        runs = DeadRuns(package, described, outskirts, config, describe_path, library_targets & with_data,
                        arguments.output_dir)
        if arguments.use_scan_inputs:
            inputs = f"the collector's describe {describe_path} and config {config}"
        else:
            inputs = (f"describe {describe_path}" if arguments.describe
                      else "my own describe (swift package --scratch-path <tmp> describe)") + " and an empty config"
        print(f"package {package.root}\nbuild directory {package.scratch}\n"
              f"index read from {reader.store_path} with {arguments.library}\nruns given {inputs}")
        runs.run_all()
        report_runs_own(verdict, runs, version, outskirts_real, library_targets, with_data)
        mapping = None
        if not arguments.without_mapping:
            mapping = DeadMapping(package, describe, described, runs, join, coupling, arguments.local_rule,
                                  arguments.map_hints, ordinal_base(package.scan, arguments))
            print(f"mapping: the scan's index collector {index_state or 'absent'}; index mode {arguments.index_mode}")
            report_mapping_own(verdict, mapping)
        if arguments.dump:
            figures = {
                "version": version, "retainedModules": runs.retained, "retainedTargets": runs.retained_targets,
                "runs": {run: {"exit": runs.exits[run], "seconds": round(runs.seconds[run], 3),
                               "entries": runs.entries.get(run),
                               "decoded": [list(runs.decoded(e, run)) for e in runs.entries.get(run) or []]}
                         for run in DEAD_RUNS}}
            if mapping is not None:
                figures["mapping"] = mapping.figures()
            write_json(arguments.dump, figures)
        if arguments.own_only:
            verdict.section("comparison with the collector's output skipped (--own-only)")
        else:
            compare_status(verdict, runs, package.scan, version)
            compare_kept(verdict, runs, arguments)
            compare_scan_block(verdict, runs, package.scan)
            if arguments.store:
                compare_store_rows(verdict, runs, arguments.store, arguments.snapshot, outskirts_real, version)
            if mapping is not None:
                ran = (periphery_collector(package.scan) or {}).get("state") == "ran"
                compare_mapping_block(verdict, mapping, package.scan)
                compare_mapping_rollups(verdict, mapping, package.scan, ran)
                if arguments.store:
                    compare_mapping_store(verdict, mapping, arguments.store, arguments.snapshot)
    finally:
        shutil.rmtree(temporary, ignore_errors=True)
    print("\nRESULT: " + ("FAIL" if verdict.failed else "PASS"))
    return 1 if verdict.failed else 0


# --------------------------------------------------------------------------
# signals: M7's signals re-derived from a store's rows (design section 8)

FIRST_M7_SCHEMA = 9
HIDDEN_COUPLING = "hidden-coupling"
DEAD_BUT_TESTED = "dead-but-tested"
TEST_ONLY = "test-only-production"
# Design 8: after uneven-clone-mutation in report order.
M7_SIGNALS = (HIDDEN_COUPLING, DEAD_BUT_TESTED, TEST_ONLY)
LAST_M6_SIGNAL = "uneven-clone-mutation"
# Design 8's limits table: name -> (default, the smallest and largest value, whether it must be whole).
HIDDEN_COUPLING_LIMITS = {"support": (3, 1, 1_000_000, True), "confidence": (50, 0, 100, False)}
# An item's own fields (SignalItem), and every payload one may carry (plus design 8's three).
ITEM_KEYS = ("rank", "subject", "file", "line", "score", "member")
ITEM_PAYLOADS = ("history", "property", "effect", "function", "laws", "clone", "markers", "ratio",
                 "propertyTarget", "coupling", "dead", "references", "coverage", "mutation")
TEST_ONLY_PAYLOADS = ("references", "coverage", "mutation")
LIBRARY_ACCESS = ("public", "open")
TEST_REFERRERS_NAMED = 5
# Design 8.3's rule text, before the funnel (a left-out signal states it alone).
TEST_ONLY_PROSE = (
    "production functions whose only references come from test targets (index: calls, reads and writes; "
    "references within the function's own family don't count, and a property's reads and writes count for its "
    "reading and writing accessors); public API of library-product modules, witnesses and overrides, @objc "
    "declarations, entry points of executable targets and deinitializers are left out and counted; either dead or "
    "missing a production caller; types and properties aren't judged")
# Design 8.3's funnel with its numbers as groups; `wby` takes a by-reason breakdown of W should the rule add one
# (design 8.3 counts W "by reason" but its funnel text names no breakdown).
TEST_ONLY_FUNNEL = re.compile(
    r"(?P<N>\d+) production functions = (?P<W>\d+) without a USR(?P<wby> \([^()]*\))? \+ (?P<K>\d+) with one; "
    r"(?P<K2>\d+) = (?P<P>\d+) public API of a library product \+ (?P<V>\d+) witnesses or overrides \+ "
    r"(?P<J>\d+) @objc \+ (?P<M>\d+) entry points \+ (?P<D>\d+) deinitializers \+ (?P<C>\d+) candidates; "
    r"(?P<C2>\d+) = (?P<L>\d+) listed \+ (?P<R>\d+) with a production reference \+ "
    r"(?P<Z>\d+) with no reference at all \(not listed: fan-in 0 isn't dead, PRD §7\.6a\)")
FUNNEL_TERMS = (("N", "production functions"), ("W", "without a USR"), ("K", "with one"), ("K2", "K restated"),
                ("P", "public API of a library product"), ("V", "witnesses or overrides"), ("J", "@objc"),
                ("M", "entry points"), ("D", "deinitializers"), ("C", "candidates"), ("C2", "C restated"),
                ("L", "listed"), ("R", "with a production reference"), ("Z", "with no reference at all"))
ENTRY_POINT = re.compile(r"(?:^|\s)static func main\(\)(?:\s|$)")

# Dead but tested (design 8.2): the collectors it needs, in order, and the payloads an item carries.
DEAD_BUT_TESTED_COLLECTORS = ("periphery", "swiftmutator")
DEAD_BUT_TESTED_PAYLOADS = ("dead", "mutation", "coverage")
# outskirts' kinds (design 5.4 rule 3: nominal types; rule 4: extensions; rule 5: functions; rule 2: properties).
DEAD_TYPE_KINDS = ("class", "struct", "enum", "protocol")
DEAD_VIA = ("usr", "property", "type", "extension", "location")
# Verdicts that show a test executed the mutated code, with coverage on and off (design 8.2's "Ran").
RAN_WITH_COVERAGE = ("killed", "survived", "timedOut")
RAN_WITHOUT_COVERAGE = ("killed",)
UNRUN_ONLY = ("notCovered", "noCoverage")
WITHOUT_FULL_RESULTS = ("unresolved", "unlisted")
# Design 8.2's rule text, before the funnels (a left-out signal states it alone).
DEAD_BUT_TESTED_PROSE = (
    "production functions no production code uses (outskirts with test targets not counted as roots; public API "
    "of library-product modules, Codable and Equatable/Hashable/Comparable properties retained) whose mutants the "
    "tests run (killed, survived or timed out; killed only, for files mutated with coverage off); delete the code "
    "and its tests, which frees test and mutation time; a function called only from an inactive #if branch reads as "
    "unused (outskirts' limit); types and properties aren't judged")
# Design 8.2's two funnels with their numbers as groups. The functions funnel names R1 to R4; `RB` is its R2
# (only build errors), and `D2`/`RR` the restated D and R. The declarations funnel's F is `FE` here (the
# functions funnel has its own F); its last clause, "D = the distinct records F, T, E and V cover", may name the
# four terms by letter, by number or in words (`cover`), which is checked apart.
DEAD_FUNCTIONS_FUNNEL = re.compile(
    r"(?P<N>\d+) production functions = (?P<D>\d+) production-dead \+ (?P<A>\d+) used; "
    r"(?P<D2>\d+) = (?P<L>\d+) listed \+ (?P<R>\d+) with no mutant that ran \+ "
    r"(?P<F>\d+) in files without full mutation results \(unresolved or unlisted\); "
    r"(?P<RR>\d+) = (?P<R1>\d+) only not covered or no coverage \+ (?P<RB>\d+) only build errors \+ "
    r"(?P<R3>\d+) no mutant \+ (?P<R4>\d+) only survived or timed out in a run with coverage off")
DEAD_DECLARATIONS_FUNNEL = re.compile(
    r"(?P<X>\d+) unused production declarations = (?P<FE>\d+) function entries matching a record \+ "
    r"(?P<U>\d+) function entries matching no record \+ (?P<T>\d+) type entries \+ (?P<E>\d+) extension entries \+ "
    r"(?P<V>\d+) property entries with accessor records \+ "
    r"(?P<O>\d+) others \(parameters, imports, enum cases, stored properties, typealiases\); "
    r"(?P<DD>\d+) = the distinct records (?P<cover>[^;]+?) cover(?=$|[;,.\s])")
DEAD_FUNCTION_TERMS = (("N", "production functions"), ("D", "production-dead"), ("A", "used"),
                       ("D2", "D restated"), ("L", "listed"), ("R", "with no mutant that ran"),
                       ("F", "in files without full mutation results"), ("RR", "R restated"),
                       ("R1", "only not covered or no coverage"), ("RB", "R2: only build errors"),
                       ("R3", "no mutant"), ("R4", "only survived or timed out in a run with coverage off"))
DEAD_DECLARATION_TERMS = (("X", "unused production declarations"), ("FE", "function entries matching a record"),
                          ("U", "function entries matching no record"), ("T", "type entries"),
                          ("E", "extension entries"), ("V", "property entries with accessor records"),
                          ("O", "others"), ("DD", "D: the distinct records F, T, E and V cover"))

# Hidden coupling (design 8.1). History's coupling cut: its default and the smallest value the configuration
# accepts (history.coupling.min_support).
DEFAULT_MIN_SUPPORT = 3
LOWEST_MIN_SUPPORT = 2
HIDDEN_COUPLING_PAYLOADS = ("coupling",)
COUPLING_VIA = ("direct", "requirement")
# Design 8.1's rule text, before the funnel, with the limits as {support} and {confidence} (a left-out signal
# states it alone, with the limits it would use).
HIDDEN_COUPLING_PROSE = (
    "pairs of production families changed together by at least {support} commits in the window (confidence at "
    "least {confidence}%: support ÷ the less-changed family's changes) with no static dependency: neither "
    "references the other (index: calls, reads, writes, directly or through a protocol requirement the other "
    "witnesses), they don't share or nest a package type, and neither references the other's type or its members; "
    "same file or module isn't a dependency; candidates for an explicit abstraction")
# Design 8.1's funnel with its numbers as groups (`P2`, `K2`, `C2` the restated P, K and C), and its note.
HIDDEN_COUPLING_FUNNEL = re.compile(
    r"(?P<N>\d+) pairs = (?P<U>\d+) with a family not in this snapshot \+ (?P<G>\d+) with a generated family \+ "
    r"(?P<T>\d+) with a test or helper family \+ (?P<P>\d+) with both families in production code; "
    r"(?P<P2>\d+) = (?P<K>\d+) judged \+ (?P<W>\d+) with a family the index didn't see; "
    r"(?P<K2>\d+) = (?P<R>\d+) referencing each other \+ (?P<Q>\d+) calling through a protocol the other "
    r"implements \+ (?P<Y>\d+) sharing or nesting a type \+ (?P<X>\d+) referencing the other's type or members \+ "
    r"(?P<C>\d+) without a static dependency; (?P<C2>\d+) = (?P<L>\d+) listed \+ (?P<B>\d+) below the limits")
MIN_SUPPORT_NOTE = re.compile(r"pairs exist only at or above history\.coupling\.min_support \((?P<m>\d+)\)")
HIDDEN_COUPLING_TERMS = (("N", "pairs"), ("U", "with a family not in this snapshot"),
                         ("G", "with a generated family"), ("T", "with a test or helper family"),
                         ("P", "with both families in production code"), ("P2", "P restated"), ("K", "judged"),
                         ("W", "with a family the index didn't see"), ("K2", "K restated"),
                         ("R", "referencing each other"), ("Q", "calling through a protocol the other implements"),
                         ("Y", "sharing or nesting a type"), ("X", "referencing the other's type or members"),
                         ("C", "without a static dependency"), ("C2", "C restated"), ("L", "listed"),
                         ("B", "below the limits"))


def blind(text):
    """Text compared case- and punctuation-blind (reasons as a rule may spell them)."""
    return re.sub(r"[^a-z0-9]", "", str(text).lower())


def reason_key(text):
    """A reason of W compared by its canonical spelling when it is a known one (a stored `fileChanged` and the
    written "file changed during the scan" agree), else case- and punctuation-blind."""
    canonical = canonical_reason(text)
    return blind(text if canonical.startswith("?") else canonical)


def load_mutation_check():
    """Scripts/mutation-check.py, the M6 checker, for M6's `mutation` and `coverage` payloads (its SignalModel
    builds them as weak tests' items carry them). Loaded without writing bytecode beside it."""
    import importlib.util
    path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "mutation-check.py")
    spec = importlib.util.spec_from_file_location("mutation_check", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def nfc_text(text):
    """`text` in Unicode NFC (stored paths are NFC; a path compared with another is normalised first)."""
    return unicodedata.normalize("NFC", text) if isinstance(text, str) else text


def store_uri(path):
    import urllib.parse
    return "file:" + urllib.parse.quote(os.path.abspath(path)) + "?mode=ro"


def read_limit_file(path):
    """`signals.hidden-coupling.*` of a `.swiftstats.yml`, as written (see read_config_mapping)."""
    return read_config_mapping(path, ("signals", HIDDEN_COUPLING))


def read_config_mapping(path, mapping_names):
    """The keys of one mapping of a `.swiftstats.yml` (`mapping_names`, such as ("signals", "hidden-coupling") or
    ("history", "coupling")): a small reader of the YAML subset the configuration uses (block mappings by
    indentation, `# comments`, scalars, and one-line `{key: value, ...}` mappings). Other keys are ignored; the
    mapping's own keys are returned as written."""
    target = list(mapping_names)
    try:
        with open(path, encoding="utf-8") as handle:
            lines = handle.read().splitlines()
    except OSError as error:
        fail(f"--config {path} doesn't read: {error}")

    def scalar(text):
        text = text.strip()
        if len(text) >= 2 and text[0] == text[-1] and text[0] in "'\"":
            return text[1:-1]
        return text

    def inline(text):
        body = text.strip()[1:-1]
        found = {}
        for part in filter(None, (piece.strip() for piece in body.split(","))):
            key, _, value = part.partition(":")
            found[scalar(key)] = scalar(value)
        return found

    path_stack = []  # (indent, key)
    found = None
    for raw in lines:
        text = raw.split(" #", 1)[0].rstrip() if not raw.lstrip().startswith("#") else ""
        if not text.strip() or text.strip() == "---":
            continue
        indent = len(text) - len(text.lstrip(" "))
        key, separator, value = text.strip().partition(":")
        if not separator:
            continue
        while path_stack and path_stack[-1][0] >= indent:
            path_stack.pop()
        key = scalar(key)
        names = [name for _, name in path_stack] + [key]
        if names == target:
            found = {} if found is None else found
            if value.strip().startswith("{"):
                found.update(inline(value))
        elif names[:len(target)] == target and len(names) == len(target) + 1:
            found = {} if found is None else found
            found[key] = scalar(value)
        if not value.strip():
            path_stack.append((indent, key))
    return found or {}


def hidden_coupling_limits(config_path, settings):
    """The hidden-coupling limits in force: the defaults, then `--config`'s, then each `--set`. A key or value
    SwiftStats must refuse (design 8: unknown keys and invalid values are configuration errors) is bad input
    here too, naming the key."""
    written = read_limit_file(config_path) if config_path else {}
    for setting in settings or []:
        key, _, value = setting.partition("=")
        signal, _, limit = key.rpartition(".")
        if signal != HIDDEN_COUPLING or not value:
            fail(f"--set {setting}: expected {HIDDEN_COUPLING}.<limit>=<value> (dead-but-tested and "
                 "test-only-production take no limits; M6's limits are mutation-check.py's)")
        written[limit] = value
    limits = {name: default for name, (default, _, _, _) in HIDDEN_COUPLING_LIMITS.items()}
    for name, text in written.items():
        if name not in HIDDEN_COUPLING_LIMITS:
            fail(f"signals.{HIDDEN_COUPLING}.{name} is no limit of {HIDDEN_COUPLING} (its limits are "
                 f"{', '.join(HIDDEN_COUPLING_LIMITS)}); SwiftStats refuses such a configuration")
        _, lowest, highest, whole = HIDDEN_COUPLING_LIMITS[name]
        try:
            value = float(text)
        except ValueError:
            fail(f"signals.{HIDDEN_COUPLING}.{name}: {text!r} isn't a number")
        if value != value or not lowest <= value <= highest or (whole and value != int(value)):
            kind = "a whole number" if whole else "a number"
            fail(f"signals.{HIDDEN_COUPLING}.{name}: {text!r} isn't {kind} from {lowest} to {highest:,}")
        limits[name] = int(value) if value == int(value) else value
    return limits


def configured_min_support(config_path):
    """`history.coupling.min_support` of the configuration (default 3): the support below which history keeps no
    pair (design 8: a hidden-coupling support limit below it changes nothing, and the rule says so). A value
    SwiftStats refuses (not a whole number, below 2) is bad input here."""
    written = read_config_mapping(config_path, ("history", "coupling")) if config_path else {}
    text = written.get("min_support")
    if text is None:
        return DEFAULT_MIN_SUPPORT
    if not re.fullmatch(r"\d+", str(text).strip()) or int(text) < LOWEST_MIN_SUPPORT:
        fail(f"history.coupling.min_support: {text!r} isn't a whole number from {LOWEST_MIN_SUPPORT}; SwiftStats "
             "refuses such a configuration")
    return int(text)


class SignalRows:
    """The rows design 8's signals read, straight from a store opened read-only (no SwiftStats code)."""

    def __init__(self, path, snapshot_id=None, report_snapshot=None):
        import sqlite3
        import zlib
        if not os.path.isfile(path):
            fail(f"no store at {path}")
        self.path = path
        try:
            database = sqlite3.connect(store_uri(path), uri=True)
            database.row_factory = sqlite3.Row
            self.tables = {row[0] for row in database.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
            if snapshot_id is None and report_snapshot is not None:
                git = report_snapshot.get("git") or {}
                row = database.execute(
                    "SELECT id FROM snapshot WHERE package = ? AND packagePath = ? AND ifnull(commitHash, '') = ? "
                    "AND isDirty = ? ORDER BY id DESC LIMIT 1",
                    (report_snapshot.get("package"), git.get("packagePath", ""), git.get("commit") or "",
                     1 if git.get("isDirty") else 0)).fetchone()
                if row is None:
                    fail(f"no snapshot of {report_snapshot.get('package')} at {git.get('commit')} "
                         f"(dirty {bool(git.get('isDirty'))}, path {git.get('packagePath', '')!r}) in {path}")
                snapshot_id = row[0]
            elif snapshot_id is None:
                row = database.execute("SELECT max(id) FROM snapshot").fetchone()
                if row is None or row[0] is None:
                    fail(f"{path} holds no snapshot")
                snapshot_id = row[0]
            snapshot = database.execute("SELECT * FROM snapshot WHERE id = ?", (snapshot_id,)).fetchone()
            if snapshot is None:
                fail(f"{path} holds no snapshot {snapshot_id}")
            self.id = snapshot_id
            self.snapshot = dict(snapshot)
            self.schema = snapshot["reportSchemaVersion"]

            def rows(sql, table=None):
                if table is not None and table not in self.tables:
                    return []
                return [dict(row) for row in database.execute(sql, (self.id,))]
            self.collectors = {row["name"]: row for row in rows("SELECT * FROM collectorRun WHERE snapshotId = ?",
                                                                 "collectorRun")}
            scans = rows("SELECT * FROM indexScan WHERE snapshotId = ?", "indexScan")
            self.index_scan = scans[0] if scans else None
            self.library_modules = []
            if self.index_scan is not None:
                try:
                    self.library_modules = json.loads(self.index_scan["libraryModules"])
                except (TypeError, ValueError):
                    fail(f"indexScan.libraryModules of snapshot {self.id} isn't a JSON array: "
                         f"{self.index_scan['libraryModules']!r}")
            columns = {row[1] for row in database.execute("PRAGMA table_info(function)")}
            wanted = ("key", "module", "kind", "name", "file", "startLine", "role", "generated", "access",
                      "typePath", "parameterCount", "usr", "usrAccessor", "usrReason", "witness",
                      "referrersSameModule", "referrersOtherModules", "referrersTests", "testReferrers",
                      "parentKey", "accessorKind", "typeFile")
            selected = ", ".join(name if name in columns else f"NULL AS {name}" for name in wanted)
            every = rows(f"SELECT {selected} FROM function WHERE snapshotId = ? ORDER BY rowid")
            self.unknown_generated = sum(1 for row in every if row["role"] == "production" and row["generated"] is None)
            self.functions = [row for row in every if row["role"] == "production" and row["generated"] == 0]
            self.coverage_held = bool(rows("SELECT snapshotId FROM coverageRun WHERE snapshotId = ?", "coverageRun"))
            self.mutation_held = bool(rows("SELECT snapshotId FROM mutationScan WHERE snapshotId = ?",
                                           "mutationScan"))
            self.coverage = {row["key"]: row for row in
                             rows("SELECT * FROM functionCoverage WHERE snapshotId = ?", "functionCoverage")}
            # Dead but tested (design 8.2): every function row (any role) for the USR match of function entries,
            # the dead-code rows of both runs, and the mutation rows by file, run and record.
            self.all_functions = every
            self.dead_scan_held = bool(rows("SELECT snapshotId FROM deadScan WHERE snapshotId = ?", "deadScan"))
            self.dead_declarations = defaultdict(dict)    # run -> ordinal -> row
            for row in rows("SELECT * FROM deadDeclaration WHERE snapshotId = ? ORDER BY run, ordinal",
                            "deadDeclaration"):
                self.dead_declarations[row["run"]][row["ordinal"]] = row
            self.dead_records = defaultdict(list)         # run -> rows
            for row in rows("SELECT run, key, declaration, via FROM deadRecord WHERE snapshotId = ? "
                            "ORDER BY run, key", "deadRecord"):
                self.dead_records[row["run"]].append(row)
            self.mutation_files = {nfc_text(row["path"]): row for row in
                                   rows("SELECT path, disposition, run FROM mutationFile WHERE snapshotId = ?",
                                        "mutationFile")}
            self.mutation_runs = {row["ordinal"]: row for row in
                                  rows("SELECT ordinal, skipCoverage, carriedFrom FROM mutationRun "
                                       "WHERE snapshotId = ?", "mutationRun")}
            self.record_mutants = defaultdict(list)       # owner key -> mutant rows placed on that record
            for row in rows("SELECT ordinal, owner, place, verdict, outcome, killedBy, run, path FROM mutant "
                            "WHERE snapshotId = ? ORDER BY ordinal", "mutant"):
                if row["place"] == "record" and row["owner"] is not None:
                    self.record_mutants[row["owner"]].append(row)
            # Hidden coupling (design 8.1): history's run and pairs (couplingPair, M3's pairs as a table), the
            # index's family and family-type references, the package-declared types, and history's family lines.
            history_runs = rows("SELECT * FROM historyRun WHERE snapshotId = ?", "historyRun")
            self.history_run = history_runs[0] if history_runs else None
            self.coupling_table_held = "couplingPair" in self.tables
            self.coupling_pairs = rows("SELECT ordinal, familyA, fileA, familyB, fileB, support, changesA, changesB "
                                       "FROM couplingPair WHERE snapshotId = ? ORDER BY ordinal", "couplingPair")
            self.family_references = {(row["fromFamily"], row["toFamily"], row["via"]) for row in rows(
                "SELECT fromFamily, toFamily, via FROM familyReference WHERE snapshotId = ?", "familyReference")}
            self.family_type_references = {(row["family"], row["module"], row["typePath"], row["typeFile"])
                                           for row in rows("SELECT family, module, typePath, typeFile FROM "
                                                           "familyTypeReference WHERE snapshotId = ?",
                                                           "familyTypeReference")}
            type_rows = rows("SELECT module, typePath, typeFile, usr FROM typeIndex WHERE snapshotId = ? "
                             "ORDER BY module, typePath, typeFile, usr", "typeIndex")
            self.package_types = {(row["module"], row["typePath"], row["typeFile"]) for row in type_rows}
            self.package_type_usrs = {}   # usr -> (module, typePath, typeFile), the first by identity
            for row in type_rows:
                self.package_type_usrs.setdefault(row["usr"], (row["module"], row["typePath"], row["typeFile"]))
            self.family_history_lines = {(row["family"], row["file"]): row["line"] for row in rows(
                "SELECT family, file, line FROM familyHistory WHERE snapshotId = ?", "familyHistory")}
            blob =database.execute("SELECT encoding, data FROM report WHERE snapshotId = ?", (self.id,)).fetchone()
            database.close()
        except sqlite3.Error as error:
            fail(f"{path} doesn't read: {error}")
        self.targets = {}
        self.stored_coupling = None   # the stored scan's history.coupling (the blob keeps the pairs too, design 9.1)
        if blob is not None:
            try:
                data = zlib.decompress(blob["data"], -15) if blob["encoding"] == "deflate" else None
            except zlib.error as error:
                fail(f"the stored report of snapshot {self.id} doesn't inflate: {error}")
            if data is None:
                fail(f"the stored report of snapshot {self.id} has encoding {blob['encoding']!r}, not deflate")
            scan = json.loads(data)
            self.targets = {target["name"]: target for target in scan.get("targets", [])}
            if isinstance(scan.get("history"), dict):
                self.stored_coupling = scan["history"].get("coupling")
        self.state ={"package": self.snapshot["package"],
                      "git": {"packagePath": self.snapshot["packagePath"], "commit": self.snapshot["commitHash"],
                              "isDirty": bool(self.snapshot["isDirty"])}}

    def left_out_m7(self, collector, missing):
        """Why a signal requiring `.m7Snapshot`, then `collector`, then rows of `missing` (a table) can't be
        computed (design 8's requirements, in order, M6's wording); nil when it can."""
        if self.schema < FIRST_M7_SCHEMA or "index" not in self.collectors:
            return "the snapshot predates M7"
        run = self.collectors.get(collector)
        if run is None:
            return "the snapshot predates M4"
        if run["state"] != "ran":
            return f"needs {collector}: {run['state']}" + (f", {run['reason']}" if run["reason"] else "")
        if missing == "indexScan" and self.index_scan is None:
            return "the snapshot holds no index rows"
        return None

    def left_out_history(self):
        """Why the snapshot has no history (no `historyRun` row), as M3's signals say it: from the history
        collector's run, or that the snapshot predates M3 when there is none; nil when it has history."""
        if self.history_run is not None:
            return None
        run = self.collectors.get("history")
        if run is None:
            return "history was not collected (the snapshot predates M3)"
        return f"history was not collected: {run['state']}" + (f", {run['reason']}" if run["reason"] else "")

    def stored_min_support(self):
        """`coupling.min_support` from the history collector's stored options (the scan's own cut); nil when
        absent."""
        run = self.collectors.get("history")
        try:
            options = json.loads(run["options"]) if run is not None and run["options"] else []
        except ValueError:
            return None
        for option in options if isinstance(options, list) else []:
            found = re.fullmatch(r"coupling\.min_support: (\d+)", str(option))
            if found:
                return int(found.group(1))
        return None

    def left_out_dead(self):
        """Why dead but tested can't be computed (design 8's requirements, in order: `.m7Snapshot`; then each
        collector it needs, periphery then swiftmutator, M6's wording; then its missing inputs, dead-code rows
        then mutation rows); nil when it can. `index` is not required (design 8.2)."""
        if self.schema < FIRST_M7_SCHEMA or "index" not in self.collectors:
            return "the snapshot predates M7"
        for collector in DEAD_BUT_TESTED_COLLECTORS:
            run = self.collectors.get(collector)
            if run is None:
                return "the snapshot predates M4"
            if run["state"] != "ran":
                return f"needs {collector}: {run['state']}" + (f", {run['reason']}" if run["reason"] else "")
        if not self.dead_scan_held:
            return "the snapshot holds no dead-code rows"
        if not self.mutation_held:
            return "the snapshot holds no mutation rows"
        return None


class TestOnlyProduction:
    """Design 8.3, by its words, over SignalRows."""

    def __init__(self, rows):
        self.rows = rows
        self.left_out = rows.left_out_m7("index", "indexScan")
        self.counts = Counter()
        self.without_by_reason = Counter()
        self.members = defaultdict(list)          # funnel term -> keys
        self.test_only_excluded = Counter()       # exclusion term -> records only tests reference
        self.problems = []
        self.items = []
        if self.left_out is not None:
            return
        library = set(rows.library_modules)
        for row in rows.functions:
            self.counts["N"] += 1
            if row["usr"] is None:
                self.counts["W"] += 1
                self.without_by_reason[row["usrReason"] if row["usrReason"] is not None else "(no reason stored)"] += 1
                self.members["W"].append(row["key"])
                continue
            self.counts["K"] += 1
            tests, same, other = row["referrersTests"], row["referrersSameModule"], row["referrersOtherModules"]
            if None in (tests, same, other):
                self.problems.append(f"{row['key']}: a USR but referrer counts {same}/{other}/{tests} "
                                     "(same module/other modules/tests; null is never right where the index ran)")
            if row["witness"] is None:
                self.problems.append(f"{row['key']}: a USR but witness null")
            only_tests = (tests or 0) > 0 and (same or 0) + (other or 0) == 0
            term = self.exclusion(row, library)
            if term is not None:
                self.counts[term] += 1
                self.members[term].append(row["key"])
                if only_tests:
                    self.test_only_excluded[term] += 1
                continue
            self.counts["C"] += 1
            if only_tests:
                self.counts["L"] += 1
                self.items.append(row)
            elif (same or 0) + (other or 0) > 0:
                self.counts["R"] += 1
            else:
                self.counts["Z"] += 1
                self.members["Z"].append(row["key"])
        self.items.sort(key=lambda row: (-row["referrersTests"], row["key"], row["file"], row["startLine"]))

    def exclusion(self, row, library):
        """The first exclusion of design 8.3 that applies after W: P, V, J, M, D; nil for a candidate."""
        if row["access"] in LIBRARY_ACCESS and row["module"] in library:
            return "P"
        if row["witness"]:
            return "V"
        if row["usr"].startswith("c:"):
            return "J"
        if self.entry_point(row):
            return "M"
        if row["kind"] == "deinit":
            return "D"
        return None

    def entry_point(self, row):
        """A parameterless `static func main()` in an executable target (design 8.3's M)."""
        if row["kind"] != "func" or row["name"] != "main" or row["parameterCount"] not in (None, 0):
            return False
        target = self.rows.targets.get(row["module"])
        if target is None or target.get("type") != "executable":
            return False
        declaration = row["key"].rsplit("::", 1)[-1].split(" @ ", 1)[0]
        return ENTRY_POINT.search(declaration) is not None

    def funnel(self):
        counts = self.counts
        return (f"{counts['N']} production functions = {counts['W']} without a USR + {counts['K']} with one; "
                f"{counts['K']} = {counts['P']} public API of a library product + {counts['V']} witnesses or "
                f"overrides + {counts['J']} @objc + {counts['M']} entry points + {counts['D']} deinitializers + "
                f"{counts['C']} candidates; {counts['C']} = {counts['L']} listed + {counts['R']} with a production "
                f"reference + {counts['Z']} with no reference at all (not listed: fan-in 0 isn't dead, PRD §7.6a)")

    def rule(self):
        return TEST_ONLY_PROSE if self.left_out is not None else TEST_ONLY_PROSE + "; " + self.funnel()

    def expected_numbers(self):
        numbers = {term: self.counts[term] for term, _ in FUNNEL_TERMS if term not in ("K2", "C2")}
        numbers["K2"], numbers["C2"] = numbers["K"], numbers["C"]
        return numbers

    def payloads(self, row, mutation_model, mutation_check):
        """The payloads design 8.3 gives an item: `references` always; `coverage` and `mutation` when the snapshot
        holds coverage rows or mutation rows. Returns (required, alternatives): alternatives maps a payload that
        may be absent, or take another value, to the values accepted besides `required`'s (None = absent)."""
        required = {"references": {"tests": row["referrersTests"],
                                   "testReferrers": self.referrer_names(row),
                                   "module": row["module"]}}
        alternatives = {}
        if self.rows.coverage_held:
            stored = self.rows.coverage.get(row["key"])
            if stored is None:
                required["coverage"] = {}
                alternatives["coverage"] = [None]
            else:
                required["coverage"] = mutation_check.without_nulls({
                    "lines": mutation_check.nonnegative_lines(stored["lineCovered"], stored["lineTotal"]),
                    "regions": mutation_check.nonnegative_lines(stored["regionCovered"], stored["regionTotal"])})
        if self.rows.mutation_held:
            held = mutation_model.held.get(row["key"])
            if held:
                required["mutation"] = mutation_check.without_nulls(mutation_model.payload(
                    {"function": row, "counts": mutation_check.record_counts(held)})["mutation"])
            else:
                zero = mutation_check.without_nulls(mutation_model.payload(
                    {"function": row, "counts": mutation_check.zero_counts()})["mutation"])
                alternatives["mutation"] = [None, zero]
        return required, alternatives

    @staticmethod
    def referrer_names(row):
        try:
            names = json.loads(row["testReferrers"]) if row["testReferrers"] is not None else None
        except ValueError:
            names = row["testReferrers"]
        return names


def mutation_payload_model(rows):
    """mutation-check.py's SignalModel over the snapshot, for M6's payloads; (None, module) when the snapshot holds
    neither coverage nor mutation rows."""
    mutation_check = load_mutation_check()
    if not (rows.coverage_held or rows.mutation_held):
        return None, mutation_check
    # SignalStore finds the snapshot by its state; the state given is this snapshot's own.
    try:
        store = mutation_check.SignalStore(rows.path, rows.state)
    except SystemExit:
        fail(f"mutation-check.py's SignalStore couldn't read snapshot {rows.id}")
    if store.id != rows.id:
        fail(f"mutation-check.py's SignalStore chose snapshot {store.id}, not {rows.id}")
    limits = {name: dict(values) for name, values in mutation_check.DEFAULT_LIMITS.items()}
    return mutation_check.SignalModel(store, limits, None), mutation_check


def test_only_expected_items(model, mutation_model, mutation_check):
    expected = []
    for rank, row in enumerate(model.items, start=1):
        required, alternatives = model.payloads(row, mutation_model, mutation_check)
        expected.append({"rank": rank, "subject": row["key"], "file": row["file"], "line": row["startLine"],
                         "score": row["referrersTests"], "member": True, "payloads": required,
                         "alternatives": alternatives})
    return expected


def report_test_only_own(verdict, model, show_all):
    verdict.section(f"{TEST_ONLY}: this check's figures (design 8.3)")
    rows = model.rows
    verdict.info(f"snapshot {rows.id} of {rows.snapshot['package']} at {rows.snapshot['commitHash']} "
                 f"(dirty {bool(rows.snapshot['isDirty'])}), scan schema {rows.schema}")
    if rows.unknown_generated:
        verdict.info(f"{rows.unknown_generated} production rows don't say whether their file is generated "
                     "(stored before store v3): left out, as M4's signals leave them out")
    if model.left_out is not None:
        verdict.info(f"left out: {model.left_out}")
        return
    verdict.info(f"library-product targets (indexScan.libraryModules): {rows.library_modules}")
    executables = sorted(name for name, target in rows.targets.items() if target.get("type") == "executable")
    verdict.info(f"executable targets: {executables}")
    unknown = sorted(set(rows.library_modules) - set(rows.targets))
    if unknown:
        verdict.info(f"libraryModules names no target of the stored report: {unknown} (design 8.3: target names)")
    verdict.info(f"coverage rows held: {rows.coverage_held}; mutation rows held: {rows.mutation_held}")
    verdict.info("funnel: " + model.funnel())
    if model.without_by_reason:
        verdict.info("W by reason: " + ", ".join(f"{count} {reason}" for reason, count in
                                                 sorted(model.without_by_reason.items())))
    if model.test_only_excluded:
        verdict.info("records only tests reference, left out before C: " + ", ".join(
            f"{term} {count}" for term, count in sorted(model.test_only_excluded.items())))
    for term in ("V", "J", "M", "D"):
        if model.members[term]:
            shown = model.members[term] if show_all else model.members[term][:5]
            more = len(model.members[term]) - len(shown)
            verdict.info(f"{term}: " + "; ".join(shown) + (f" ... and {more} more" if more else ""))
    if model.items:
        verdict.info(f"listed ({len(model.items)}), in order:")
        for rank, row in enumerate(model.items if show_all else model.items[:LISTED], start=1):
            names = model.referrer_names(row)
            verdict.info(f"  #{rank} {row['referrersTests']} {row['key']} ({row['file']}:{row['startLine']}) "
                         f"tests {names[:3] if isinstance(names, list) else names}")
        if not show_all and len(model.items) > LISTED:
            verdict.info(f"  ... and {len(model.items) - LISTED} more (--all lists them)")
    else:
        verdict.info("listed: none")
    for problem in model.problems:
        verdict.info(f"note: {problem}")


def compare_test_only(verdict, model, signal, expected):
    verdict.section(f"o   {TEST_ONLY}: left-out reason, rule, funnel, candidates, items, order and payloads")
    actual_left = signal.get("leftOut")
    verdict.result("left out", actual_left == model.left_out,
                   f"expected {model.left_out!r}, got {actual_left!r}")
    rule = signal.get("rule", "")
    if model.left_out is not None:
        verdict.result("rule states design 8.3's text", rule == TEST_ONLY_PROSE or rule.startswith(
            TEST_ONLY_PROSE + "; "), f"got {rule!r}")
        verdict.result("no items, no candidates", not signal.get("items") and signal.get("candidates", 0) == 0,
                       f"{len(signal.get('items') or [])} items, candidates {signal.get('candidates')}")
        return
    verdict.result("rule's text before the funnel is design 8.3's", rule.startswith(TEST_ONLY_PROSE + "; "),
                   "" if rule.startswith(TEST_ONLY_PROSE) else f"got {rule[:200]!r}...")
    funnel_text = rule[len(TEST_ONLY_PROSE) + 2:] if rule.startswith(TEST_ONLY_PROSE + "; ") else rule
    match = TEST_ONLY_FUNNEL.search(funnel_text)
    verdict.result("funnel in design 8.3's words", match is not None,
                   "" if match else f"got {funnel_text[:400]!r}")
    if match is not None:
        if match.start() != 0:
            verdict.info(f"text between the rule and the funnel: {funnel_text[:match.start()]!r}")
        if match.end() < len(funnel_text):
            verdict.info(f"text after the funnel: {funnel_text[match.end():]!r}")
        wanted = model.expected_numbers()
        differences = [f"{term} ({name}): expected {wanted[term]}, got {match.group(term)}"
                       for term, name in FUNNEL_TERMS if int(match.group(term)) != wanted[term]]
        verdict.result("every funnel number", not differences, model.funnel() if differences else "")
        verdict.listing(differences)
        stated = [int(match.group(term)) for term in ("N", "W", "K", "P", "V", "J", "M", "D", "C", "L", "R", "Z")]
        n, w, k, p, v, j, m, d, c, listed, r, z = stated
        sums = n == w + k and k == p + v + j + m + d + c and c == listed + r + z \
            and int(match.group("K2")) == k and int(match.group("C2")) == c
        verdict.result("the funnel's parts add up as stated", sums)
        breakdown = match.group("wby")
        if breakdown is None:
            verdict.info("W isn't broken down by reason in the rule (design 8.3's funnel names no breakdown); "
                         "this check's: " + (", ".join(f"{count} {reason}" for reason, count in
                                                      sorted(model.without_by_reason.items())) or "none"))
        else:
            body = re.sub(r"^\s*\(\s*(?:by reason:?\s*)?", "", breakdown).rstrip(") ")
            parts = [part.strip() for part in re.split(r"[,;]", body) if part.strip()]
            stated_reasons = {}
            readable = True
            for part in parts:
                found = re.fullmatch(r"(\d+) (.+)", part)
                if found is None:
                    readable = False
                    break
                stated_reasons[reason_key(found.group(2))] = int(found.group(1))
            mine = {reason_key(reason): count for reason, count in model.without_by_reason.items()}
            verdict.result("W by reason", readable and stated_reasons == mine,
                           f"expected {dict(model.without_by_reason)}, got {breakdown.strip()!r}")
    candidates = signal.get("candidates")
    if candidates == model.counts["N"]:
        verdict.result("candidates", True, f"{candidates}: N, the pool (design 8.3's Pool)")
    elif candidates == model.counts["C"]:
        verdict.result("candidates", True, f"{candidates}: C, the funnel's candidates (design 8.3 names both)")
    else:
        verdict.result("candidates", False, f"expected N {model.counts['N']} or C {model.counts['C']}, "
                                            f"got {candidates}")
    items = signal.get("items") or []
    listed = [(item.get("subject"), item.get("file"), item.get("line")) for item in items]
    wanted = [(entry["subject"], entry["file"], entry["line"]) for entry in expected]
    verdict.result("listed items in order", listed == wanted, f"{len(wanted)} items")
    if listed != wanted:
        verdict.listing([f"#{rank}: expected {mine}, got {theirs}" for rank, (mine, theirs)
                         in enumerate(zip(wanted, listed), start=1) if mine != theirs]
                        + [f"missing {mine}" for mine in wanted[len(listed):]]
                        + [f"extra {theirs}" for theirs in listed[len(wanted):]])
    differences, notes = [], Counter()
    for item, entry in zip(items, expected):
        label = f"#{entry['rank']} {entry['subject']}"
        if item.get("rank") != entry["rank"] or item.get("member") is not True:
            differences.append(f"{label}: rank {item.get('rank')} member {item.get('member')}")
        if not isinstance(item.get("score"), (int, float)) or float(item["score"]) != entry["score"]:
            differences.append(f"{label}: score {item.get('score')} != {entry['score']}")
        extra = sorted(key for key in item if key not in ITEM_KEYS and key not in TEST_ONLY_PAYLOADS)
        if extra:
            unknown = [key for key in extra if key not in ITEM_PAYLOADS]
            differences.append(f"{label}: payloads test-only doesn't fill: {extra}"
                               + (f" ({unknown} no known payload)" if unknown else ""))
        for name in TEST_ONLY_PAYLOADS:
            value = item[name] if name in item else None
            accepted = entry["alternatives"].get(name, [])
            if name in entry["payloads"] and name in item and value == entry["payloads"][name]:
                continue
            if name in entry["payloads"] or accepted:
                if value in accepted:
                    shape = "absent" if value is None else json.dumps(value, sort_keys=True)[:60]
                    notes[f"{name} {shape} for a function without {name} data"] += 1
                    continue
                wanted_text = json.dumps(entry["payloads"].get(name), sort_keys=True) if name in entry["payloads"] \
                    else " or ".join("absent" if option is None else json.dumps(option, sort_keys=True)
                                     for option in accepted)
                differences.append(f"{label}: {name} {'absent' if value is None else json.dumps(value, sort_keys=True)}"
                                   f" != {wanted_text}")
            elif name in item:
                differences.append(f"{label}: {name} given, but the snapshot holds no {name} rows")
    verdict.result("ranks, members, scores and payloads", not differences, f"{len(expected)} items")
    verdict.listing(differences)
    for note, count in sorted(notes.items()):
        verdict.info(f"accepted: {note} ({count})")


def json_list(text):
    """A JSON array stored as text (deadDeclaration's ids, a mutant's killedBy), as a list; [] when it isn't one."""
    try:
        value = json.loads(text) if isinstance(text, str) else text
    except ValueError:
        return []
    return value if isinstance(value, list) else []


class DeadRun:
    """One outskirts run's coverage of records, read from the stored rows (design 5.4, 9.1): the run's `unused`
    entries of class production, which records they cover, and each entry's term in design 8.2's declarations
    funnel. `deadRecord` keeps one row per record, with the lowest entry ordinal that covers it (design 5.4), so a
    function entry whose `ids` hold a record's primary or secondary USR (design 5.4 rule 1) is matched by USR too,
    in case a lower entry with another hint took the record's row."""

    def __init__(self, rows, run, by_usr):
        self.run = run
        self.notes = []
        declarations = rows.dead_declarations.get(run, {})
        self.unused = {ordinal: row for ordinal, row in declarations.items()
                       if row["hint"] == "unused" and row["class"] == "production"}
        self.covered = {}                          # record key -> (entry ordinal, via)
        self.by_entry = defaultdict(list)          # entry ordinal -> deadRecord rows naming it
        for record in rows.dead_records.get(run, []):
            entry = declarations.get(record["declaration"])
            if entry is None:
                self.notes.append(f"deadRecord {record['key']!r} names entry {record['declaration']}, which no "
                                  f"deadDeclaration row of the {run} run holds")
                continue
            if record["via"] not in DEAD_VIA:
                self.notes.append(f"deadRecord {record['key']!r}: via {record['via']!r} is none of {DEAD_VIA}")
            if record["declaration"] in self.unused:
                self.by_entry[record["declaration"]].append(record)
                self.covered[record["key"]] = (record["declaration"], record["via"])
            else:
                self.notes.append(f"{record['key']!r}: its deadRecord row names entry {record['declaration']} "
                                  f"(hint {entry['hint']}, class {entry['class']}), so that row doesn't make it dead")
        self.terms = {}                            # entry ordinal -> FE, U, T, E, V or O
        self.matched = {}                          # function entry ordinal -> record keys its ids name
        for ordinal in sorted(self.unused):
            entry = self.unused[ordinal]
            kind = entry["kind"] or ""
            own = self.by_entry.get(ordinal, [])
            if kind.startswith("function."):
                matched = sorted({key for usr in json_list(entry["ids"]) for key in by_usr.get(usr, [])})
                self.matched[ordinal] = matched
                for key in matched:
                    held = self.covered.get(key)
                    if held is None:
                        self.covered[key] = (ordinal, "usr")
                        self.notes.append(f"{key!r}: no deadRecord row of the {run} run names an unused entry, but "
                                          f"unused function entry {ordinal} holds its USR (counted dead, via usr)")
                    elif held[0] > ordinal:
                        self.notes.append(f"{key!r}: its deadRecord row names entry {held[0]}, but the lower "
                                          f"unused function entry {ordinal} holds its USR (design 5.4: the lower "
                                          "ordinal wins)")
                term = "FE" if own or matched else "U"
            elif kind in DEAD_TYPE_KINDS:
                term = "T"
            elif kind.startswith("extension"):
                term = "E"
            elif kind.startswith("var.") and own:
                term = "V"
                vias = sorted({record["via"] for record in own})
                if vias != ["property"]:
                    self.notes.append(f"property entry {ordinal} ({entry['name']}) covers records via {vias}, "
                                      "not only property")
            else:
                term = "O"
                if own:
                    self.notes.append(f"entry {ordinal} ({kind} {entry['name']}) is none of design 8.2's F, T, E "
                                      f"and V, yet covers {len(own)} records")
            self.terms[ordinal] = term

    def term_counts(self):
        counts = Counter(self.terms.values())
        counts["X"] = len(self.unused)
        return counts

    def keys_covered_by(self, terms):
        return {key for key, (ordinal, _) in self.covered.items() if self.terms.get(ordinal) in terms}


class DeadButTested:
    """Design 8.2, by its words, over SignalRows."""

    def __init__(self, rows):
        self.rows = rows
        self.left_out = rows.left_out_dead()
        self.counts = Counter()                   # both funnels' terms
        self.members = defaultdict(list)          # functions-funnel term -> record keys
        self.facts = {}                           # record key -> its mutation facts (dead records)
        self.notes = []
        self.items = []
        self.production = self.roots = None
        if self.left_out is not None:
            return
        by_usr = defaultdict(list)
        for row in rows.all_functions:
            for column in ("usr", "usrAccessor"):
                if row[column] is not None:
                    by_usr[row[column]].append(row["key"])
        self.production = DeadRun(rows, "production", by_usr)
        self.roots = DeadRun(rows, "roots", by_usr)
        self.notes += [f"production run: {note}" for note in self.production.notes]
        self.notes += [f"roots run: {note}" for note in self.roots.notes]
        self.counts.update(self.production.term_counts())
        declared = self.production.keys_covered_by(("FE", "T", "E", "V"))
        pool = set()
        for row in rows.functions:
            key = row["key"]
            pool.add(key)
            self.counts["N"] += 1
            if key not in self.production.covered:
                self.counts["A"] += 1
                continue
            self.counts["D"] += 1
            facts = self.mutation_facts(row)
            self.facts[key] = facts
            if facts["ran"] > 0:
                term = "L"
                self.items.append(row)
                if facts["disposition"] in WITHOUT_FULL_RESULTS:
                    self.notes.append(f"{key!r}: listed (a mutant ran) in a file whose disposition is "
                                      f"{facts['disposition']}")
            elif facts["disposition"] in WITHOUT_FULL_RESULTS:
                term = "F"
            else:
                self.counts["R"] += 1
                term = facts["unrun"]
            self.counts[term] += 1
            self.members[term].append(key)
        self.counts["DD"] = len(declared & pool)
        self.declared_all = len(declared)
        if self.declared_all != self.counts["DD"]:
            self.notes.append(f"F, T, E and V entries cover {self.declared_all} distinct records, "
                              f"{self.declared_all - self.counts['DD']} of them outside the pool (another role or a "
                              "generated file)")
        others = len(set(self.production.covered) & pool) - self.counts["DD"]
        if others:
            self.notes.append(f"{others} production-dead records are covered only by entries of design 8.2's O term")
        self.items.sort(key=lambda row: (-self.facts[row["key"]]["ran"], -len(self.facts[row["key"]]["killing"]),
                                         row["key"], row["file"], row["startLine"]))

    def mutation_facts(self, row):
        """The record's mutants (place record), its file's disposition and run, and what ran: each mutant judged by
        mutationRun.skipCoverage through mutationFile.run, else through its own run (design 8.2); the record's
        coverage setting is its file's run's, else the one its mutants' runs share, else unknown (None)."""
        key = row["key"]
        mutants = self.rows.record_mutants.get(key, [])
        file_row = self.rows.mutation_files.get(nfc_text(row["file"]))
        disposition = file_row["disposition"] if file_row is not None else None
        run = file_row["run"] if file_row is not None else None
        mutant_runs = sorted({mutant["run"] for mutant in mutants})
        if run is None and len(mutant_runs) == 1:
            run = mutant_runs[0]
            self.notes.append(f"{key!r}: its file has no mutationFile run; its mutants' run {run} decides coverage")
        elif run is None and len(mutant_runs) > 1:
            self.notes.append(f"{key!r}: its file has no mutationFile run; its mutants' runs {mutant_runs} each "
                              "judge their own mutants")
        elif run is not None and mutant_runs and mutant_runs != [run]:
            self.notes.append(f"{key!r}: its file's run is {run}, its mutants' runs {mutant_runs} (the file's decides)")

        missing = set()

        def skips(ordinal):
            run_row = self.rows.mutation_runs.get(ordinal)
            if run_row is None:
                missing.add(ordinal)
                return False
            return bool(run_row["skipCoverage"])

        judged = [(mutant, skips(mutant["run"] if run is None else run)) for mutant in mutants]
        settings = {off for _, off in judged}
        if run is not None and not mutants:
            off = skips(run)
        else:
            off = next(iter(settings)) if len(settings) == 1 else None
        if mutants and missing:
            self.notes.append(f"{key!r}: no mutationRun row {sorted(missing, key=str)}; coverage read as on")
        if len(settings) > 1:
            self.notes.append(f"{key!r}: its mutants' runs differ in coverage; the setting is left out")
        verdicts = Counter(mutant["verdict"] for mutant in mutants)
        ran = sum(1 for mutant, skipped in judged
                  if mutant["verdict"] in (RAN_WITHOUT_COVERAGE if skipped else RAN_WITH_COVERAGE))
        unchecked = sum(1 for mutant, skipped in judged if skipped and mutant["verdict"] in ("survived", "timedOut"))
        killing = sorted({name for mutant in mutants if mutant["verdict"] == "killed"
                          for name in json_list(mutant["killedBy"])})
        if not mutants:
            unrun = "R3"
        elif unchecked > 0:
            unrun = "R4"
        elif any(verdicts[verdict] for verdict in UNRUN_ONLY):
            unrun = "R1"
        elif verdicts["buildError"]:
            unrun = "RB"
        else:
            unrun = "R3"
        if ran == 0 and mutants and len(verdicts) > 1:
            self.notes.append(f"{key!r}: no mutant ran, mixed verdicts {dict(sorted(verdicts.items()))}: counted "
                              f"{unrun} (R4 before R1 before R2, as M6 puts not covered before build errors)")
        return {"mutants": len(mutants), "verdicts": verdicts, "ran": ran, "killing": killing,
                "coverageOff": off, "run": run, "disposition": disposition, "unrun": unrun}

    def functions_funnel(self):
        counts = self.counts
        return (f"{counts['N']} production functions = {counts['D']} production-dead + {counts['A']} used; "
                f"{counts['D']} = {counts['L']} listed + {counts['R']} with no mutant that ran + {counts['F']} in "
                f"files without full mutation results (unresolved or unlisted); {counts['R']} = {counts['R1']} only "
                f"not covered or no coverage + {counts['RB']} only build errors + {counts['R3']} no mutant + "
                f"{counts['R4']} only survived or timed out in a run with coverage off")

    def declarations_funnel(self):
        counts = self.counts
        return (f"{counts['X']} unused production declarations = {counts['FE']} function entries matching a record + "
                f"{counts['U']} function entries matching no record + {counts['T']} type entries + {counts['E']} "
                f"extension entries + {counts['V']} property entries with accessor records + {counts['O']} others "
                f"(parameters, imports, enum cases, stored properties, typealiases); {counts['DD']} = the distinct "
                "records F, T, E and V cover")

    def rule(self):
        if self.left_out is not None:
            return DEAD_BUT_TESTED_PROSE
        return DEAD_BUT_TESTED_PROSE + "; " + self.functions_funnel() + "; " + self.declarations_funnel()

    def expected_function_numbers(self):
        numbers = {term: self.counts[term] for term, _ in DEAD_FUNCTION_TERMS if term not in ("D2", "RR")}
        numbers["D2"], numbers["RR"] = numbers["D"], numbers["R"]
        return numbers

    def expected_declaration_numbers(self):
        return {term: self.counts[term] for term, _ in DEAD_DECLARATION_TERMS}

    def payloads(self, row, mutation_model, mutation_check):
        """Design 8.2's payloads: `dead` and `mutation` always, `coverage` when the snapshot holds coverage rows.
        Returns (required, alternatives, setting): `setting` is the run's coverage, "on", "off" or None when unknown
        (left out), which the `mutation` payload carries besides M6's weak-tests shape."""
        key = row["key"]
        ordinal, via = self.production.covered[key]
        entry = self.production.unused[ordinal]
        dead = mutation_check.without_nulls({
            "kind": entry["kind"], "name": entry["name"], "file": entry["file"], "line": entry["line"],
            "via": via, "accessibility": entry["accessibility"], "deadWithTestsAsRoots": key in self.roots.covered})
        held = mutation_model.held.get(key) or []
        mutation = mutation_check.without_nulls(mutation_model.payload(
            {"function": row, "counts": mutation_check.record_counts(held)})["mutation"])
        required = {"dead": dead, "mutation": mutation}
        alternatives = {}
        if self.rows.coverage_held:
            stored = self.rows.coverage.get(key)
            if stored is None:
                required["coverage"] = {}
                alternatives["coverage"] = [None]
            else:
                required["coverage"] = mutation_check.without_nulls({
                    "lines": mutation_check.nonnegative_lines(stored["lineCovered"], stored["lineTotal"]),
                    "regions": mutation_check.nonnegative_lines(stored["regionCovered"], stored["regionTotal"])})
        return required, alternatives, coverage_setting(self.facts[key]["coverageOff"])


def coverage_setting(off):
    """A record's coverage setting as the `mutation` payload writes it: "off", "on", or None when unknown."""
    return None if off is None else ("off" if off else "on")


def dead_expected_items(model, mutation_model, mutation_check):
    expected = []
    for rank, row in enumerate(model.items, start=1):
        required, alternatives, setting = model.payloads(row, mutation_model, mutation_check)
        facts = model.facts[row["key"]]
        expected.append({"rank": rank, "subject": row["key"], "file": row["file"], "line": row["startLine"],
                         "score": facts["ran"], "killingTests": len(facts["killing"]), "member": True,
                         "payloads": required, "alternatives": alternatives, "coverageSetting": setting})
    return expected


def report_dead_own(verdict, model, show_all):
    verdict.section(f"{DEAD_BUT_TESTED}: this check's figures (design 8.2)")
    rows = model.rows
    if model.left_out is not None:
        verdict.info(f"left out: {model.left_out}")
        return
    index = rows.collectors.get("index")
    verdict.info(f"index collector: {index['state'] if index else 'absent'} (not required: without it outskirts' "
                 "results are mapped by position, via location)")
    verdict.info(f"dead-code rows: production run {len(model.production.unused)} unused production entries "
                 f"of {len(rows.dead_declarations.get('production', {}))}, roots run {len(model.roots.unused)} of "
                 f"{len(rows.dead_declarations.get('roots', {}))}; deadRecord rows production "
                 f"{len(rows.dead_records.get('production', []))}, roots {len(rows.dead_records.get('roots', []))}")
    runs = ", ".join(f"run {ordinal}: coverage {'off' if run['skipCoverage'] else 'on'}"
                     + (f" (carried from {run['carriedFrom']})" if run["carriedFrom"] else "")
                     for ordinal, run in sorted(rows.mutation_runs.items()))
    verdict.info(f"mutation runs: {runs or 'none'}; coverage rows held: {rows.coverage_held}")
    dispositions = Counter(row["disposition"] for row in rows.mutation_files.values())
    verdict.info("mutation file dispositions: " + (", ".join(f"{name} {count}" for name, count in
                                                            sorted(dispositions.items())) or "none"))
    verdict.info("functions funnel: " + model.functions_funnel())
    verdict.info("declarations funnel: " + model.declarations_funnel())
    for ordinal in sorted(model.production.unused):
        entry = model.production.unused[ordinal]
        covered = sorted(key for key, (held, _) in model.production.covered.items() if held == ordinal)
        verdict.info(f"  entry {ordinal} {model.production.terms[ordinal]}: {entry['kind']} {entry['name']} "
                     f"({entry['file']}:{entry['line']}) covers {len(covered)}"
                     + (f": {'; '.join(covered if show_all else covered[:3])}" if covered else ""))
    for term in ("F", "R1", "RB", "R3", "R4"):
        if model.members[term]:
            shown = model.members[term] if show_all else model.members[term][:5]
            more = len(model.members[term]) - len(shown)
            verdict.info(f"{term}: " + "; ".join(shown) + (f" ... and {more} more" if more else ""))
    if model.items:
        verdict.info(f"listed ({len(model.items)}), in order:")
        for rank, row in enumerate(model.items if show_all else model.items[:LISTED], start=1):
            facts = model.facts[row["key"]]
            ordinal, via = model.production.covered[row["key"]]
            entry = model.production.unused[ordinal]
            verdict.info(f"  #{rank} {facts['ran']} {row['key']} ({row['file']}:{row['startLine']}) killing tests "
                         f"{len(facts['killing'])}, verdicts {dict(sorted(facts['verdicts'].items()))}, coverage "
                         f"{coverage_setting(facts['coverageOff']) or 'unknown'}, by {entry['kind']} {entry['name']} "
                         f"via {via}, "
                         f"dead with tests as roots {row['key'] in model.roots.covered}")
        if not show_all and len(model.items) > LISTED:
            verdict.info(f"  ... and {len(model.items) - LISTED} more (--all lists them)")
    else:
        verdict.info("listed: none")
    for note in model.notes if show_all else model.notes[:LISTED]:
        verdict.info(f"note: {note}")
    if not show_all and len(model.notes) > LISTED:
        verdict.info(f"... and {len(model.notes) - LISTED} more notes (--all lists them)")


def compare_funnel(verdict, label, text, pattern, terms, wanted, sums):
    """One funnel found in `text` by `pattern`: every number equal to `wanted` and the parts adding up (`sums`
    takes the match's numbers). Returns the match, or None."""
    match = pattern.search(text)
    verdict.result(f"{label} funnel in design 8.2's words", match is not None, "" if match else f"got {text[:400]!r}")
    if match is None:
        return None
    differences = [f"{term} ({name}): expected {wanted[term]}, got {match.group(term)}"
                   for term, name in terms if int(match.group(term)) != wanted[term]]
    verdict.result(f"every {label} funnel number", not differences)
    verdict.listing(differences)
    numbers = {term: int(match.group(term)) for term, _ in terms}
    verdict.result(f"the {label} funnel's parts add up as stated", sums(numbers))
    return match


def compare_dead_but_tested(verdict, model, signal, expected):
    verdict.section(f"d   {DEAD_BUT_TESTED}: left-out reason, rule, both funnels, candidates, items, order and payloads")
    actual_left = signal.get("leftOut")
    verdict.result("left out", actual_left == model.left_out, f"expected {model.left_out!r}, got {actual_left!r}")
    rule = signal.get("rule", "")
    if model.left_out is not None:
        verdict.result("rule states design 8.2's text", rule == DEAD_BUT_TESTED_PROSE or rule.startswith(
            DEAD_BUT_TESTED_PROSE + "; "), f"got {rule!r}")
        verdict.result("no items, no candidates", not signal.get("items") and signal.get("candidates", 0) == 0,
                       f"{len(signal.get('items') or [])} items, candidates {signal.get('candidates')}")
        return
    verdict.result("rule's text before the funnels is design 8.2's", rule.startswith(DEAD_BUT_TESTED_PROSE + "; "),
                   "" if rule.startswith(DEAD_BUT_TESTED_PROSE) else f"got {rule[:200]!r}...")
    funnels = rule[len(DEAD_BUT_TESTED_PROSE) + 2:] if rule.startswith(DEAD_BUT_TESTED_PROSE + "; ") else rule
    functions = compare_funnel(
        verdict, "functions", funnels, DEAD_FUNCTIONS_FUNNEL, DEAD_FUNCTION_TERMS, model.expected_function_numbers(),
        lambda n: n["N"] == n["D"] + n["A"] and n["D2"] == n["D"] and n["D"] == n["L"] + n["R"] + n["F"]
        and n["RR"] == n["R"] and n["R"] == n["R1"] + n["RB"] + n["R3"] + n["R4"])
    wanted = model.expected_declaration_numbers()
    accepted_dd = {wanted["DD"], model.declared_all}
    declarations = DEAD_DECLARATIONS_FUNNEL.search(funnels)
    verdict.result("declarations funnel in design 8.2's words", declarations is not None,
                   "" if declarations else f"got {funnels[:400]!r}")
    if declarations is not None:
        differences = [f"{term} ({name}): expected {wanted[term]}, got {declarations.group(term)}"
                       for term, name in DEAD_DECLARATION_TERMS
                       if term != "DD" and int(declarations.group(term)) != wanted[term]]
        stated_dd = int(declarations.group("DD"))
        if stated_dd not in accepted_dd:
            differences.append(f"DD (the distinct records F, T, E and V cover): expected {wanted['DD']}"
                               + (f" (or {model.declared_all} counting records outside the pool)"
                                  if model.declared_all != wanted["DD"] else "") + f", got {stated_dd}")
        elif stated_dd != wanted["DD"]:
            verdict.info(f"the distinct records F, T, E and V cover: {stated_dd}, counting records outside the pool "
                         f"(the pool's: {wanted['DD']})")
        verdict.result("every declarations funnel number", not differences)
        verdict.listing(differences)
        n = {term: int(declarations.group(term)) for term, _ in DEAD_DECLARATION_TERMS}
        verdict.result("the declarations funnel's parts add up as stated",
                       n["X"] == n["FE"] + n["U"] + n["T"] + n["E"] + n["V"] + n["O"])
        if functions is not None:
            verdict.result("the declarations funnel's D is the functions funnel's D", n["DD"] == int(functions.group("D"))
                           or n["DD"] == model.declared_all, f"{n['DD']} and {functions.group('D')}")
        cover = declarations.group("cover").strip()
        numbers = re.fullmatch(r"(\d+), (\d+), (\d+) and (\d+)", cover)
        if cover == "F, T, E and V":
            pass
        elif numbers is not None:
            stated = tuple(int(value) for value in numbers.groups())
            mine = (n["FE"], n["T"], n["E"], n["V"])
            verdict.result("the four terms D's clause names are F, T, E and V", stated == mine,
                           f"expected {mine}, got {stated}")
        else:
            verdict.info(f"D's clause names its terms as {cover!r} (design 8.2: \"F, T, E and V\")")
    if functions is not None and declarations is not None:
        if declarations.start() < functions.start():
            verdict.info("the declarations funnel comes before the functions funnel (design 8.2 lists it second)")
        first, second = sorted((functions, declarations), key=lambda match: match.start())
        between = [("before the first funnel", funnels[:first.start()]),
                   ("between the funnels", funnels[first.end():second.start()]),
                   ("after the last funnel", funnels[second.end():])]
        for where, text in between:
            if text and text != "; ":
                verdict.info(f"text {where}: {text!r}")
    candidates = signal.get("candidates")
    if candidates == model.counts["N"]:
        verdict.result("candidates", True, f"{candidates}: N, the pool (design 8.2's Pool)")
    elif candidates == model.counts["D"]:
        verdict.result("candidates", True, f"{candidates}: D, the production-dead functions")
    else:
        verdict.result("candidates", False, f"expected N {model.counts['N']} or D {model.counts['D']}, "
                                            f"got {candidates}")
    items = signal.get("items") or []
    listed = [(item.get("subject"), item.get("file"), item.get("line")) for item in items]
    wanted_items = [(entry["subject"], entry["file"], entry["line"]) for entry in expected]
    verdict.result("listed items in order", listed == wanted_items, f"{len(wanted_items)} items")
    if listed != wanted_items:
        verdict.listing([f"#{rank}: expected {mine}, got {theirs}" for rank, (mine, theirs)
                         in enumerate(zip(wanted_items, listed), start=1) if mine != theirs]
                        + [f"missing {mine}" for mine in wanted_items[len(listed):]]
                        + [f"extra {theirs}" for theirs in listed[len(wanted_items):]])
    differences, notes = [], Counter()
    for item, entry in zip(items, expected):
        label = f"#{entry['rank']} {entry['subject']}"
        if item.get("rank") != entry["rank"] or item.get("member") is not True:
            differences.append(f"{label}: rank {item.get('rank')} member {item.get('member')}")
        if not isinstance(item.get("score"), (int, float)) or float(item["score"]) != entry["score"]:
            differences.append(f"{label}: score {item.get('score')} != {entry['score']} (mutants that ran)")
        extra = sorted(key for key in item if key not in ITEM_KEYS and key not in DEAD_BUT_TESTED_PAYLOADS)
        if extra:
            unknown = [key for key in extra if key not in ITEM_PAYLOADS]
            differences.append(f"{label}: payloads dead but tested doesn't fill: {extra}"
                               + (f" ({unknown} no known payload)" if unknown else ""))
        dead = item.get("dead")
        wanted_dead = entry["payloads"]["dead"]
        if not isinstance(dead, dict) or {key: value for key, value in dead.items() if value is not None} != wanted_dead:
            differences.append(f"{label}: dead {json.dumps(dead, sort_keys=True)} != "
                               f"{json.dumps(wanted_dead, sort_keys=True)}")
        mutation = item.get("mutation")
        wanted_mutation = entry["payloads"]["mutation"]
        if not isinstance(mutation, dict):
            differences.append(f"{label}: mutation {'absent' if mutation is None else json.dumps(mutation)}")
        else:
            mismatched = [name for name in wanted_mutation if mutation.get(name) != wanted_mutation[name]]
            if mismatched:
                differences.append(f"{label}: mutation's M6 fields differ: " + "; ".join(
                    f"{name} {json.dumps(mutation.get(name), sort_keys=True)} != "
                    f"{json.dumps(wanted_mutation[name], sort_keys=True)}" for name in mismatched))
            added = {name: value for name, value in mutation.items() if name not in wanted_mutation}
            setting = entry["coverageSetting"]
            if setting is None and not [value for value in added.values() if value is not None]:
                notes["the run's coverage setting left out, unknown (no file run; its mutants' runs differ)"] += 1
            elif list(added.values()) != [setting]:
                differences.append(f"{label}: mutation should add only its run's coverage setting {setting!r} to M6's "
                                   f"weak-tests shape; it adds {json.dumps(added, sort_keys=True)}")
            else:
                notes[f"the run's coverage setting as mutation.{next(iter(added))}"
                      + ("" if next(iter(added)) == "coverage" else " (design 8.2 writes `coverage: on|off`)")] += 1
        value = item["coverage"] if "coverage" in item else None
        accepted = entry["alternatives"].get("coverage", [])
        if "coverage" in entry["payloads"]:
            if "coverage" in item and value == entry["payloads"]["coverage"]:
                pass
            elif value in accepted:
                notes[f"coverage {'absent' if value is None else json.dumps(value)} for a function without coverage "
                      "data"] += 1
            else:
                differences.append(f"{label}: coverage {'absent' if value is None else json.dumps(value, sort_keys=True)}"
                                   f" != {json.dumps(entry['payloads']['coverage'], sort_keys=True)}")
        elif "coverage" in item:
            differences.append(f"{label}: coverage given, but the snapshot holds no coverage rows")
    verdict.result("ranks, members, scores and payloads", not differences, f"{len(expected)} items")
    verdict.listing(differences)
    for note, count in sorted(notes.items()):
        verdict.info(f"accepted: {note} ({count})")


# ---- hidden coupling (design 8.1; plan step 9c)


def number_text(value):
    """A limit as the rule writes it: whole numbers without a fraction."""
    return str(int(value)) if float(value) == int(value) else str(value)


def number_pattern():
    return r"(\d+(?:\.\d+)?)"


def hidden_coupling_prose_pattern():
    """Design 8.1's text with each limit read back as a number (a fractional confidence may be spelled either
    way); groups 1 and 2 are the support and the confidence."""
    support, confidence = "\u0000S\u0000", "\u0000C\u0000"
    text = re.escape(HIDDEN_COUPLING_PROSE.format(support=support, confidence=confidence))
    return text.replace(re.escape(support), number_pattern()).replace(re.escape(confidence), number_pattern())


def property_owner_key(row):
    """A computed property accessor's key without its ` { <accessor> }` part (the last occurrence), as PRD 6.6's
    property families are named."""
    token = f" {{ {row['accessorKind']} }}" if row["accessorKind"] else None
    key = row["key"]
    if token is None or token not in key:
        return key
    at = key.rfind(token)
    return key[:at] + key[at + len(token):]


class CouplingFamily:
    """One function family of the snapshot (PRD 6.6): a root record with its nested functions and accessors,
    or a computed property's accessors."""

    def __init__(self, members):
        self.members = sorted(members, key=lambda row: (row["key"], row["startLine"]))
        roots = [row for row in self.members if row["parentKey"] is None and not self.is_property_accessor(row)]
        self.root = roots[0] if roots else None
        first = self.root or self.members[0]
        self.identifier = self.root["key"] if self.root is not None else property_owner_key(self.members[0])
        self.file = first["file"]
        self.line = first["startLine"]
        self.lowest_line = min(row["startLine"] for row in self.members)
        self.module = self.members[0]["module"]
        self.role = first["role"]
        self.generated = any(row["generated"] for row in self.members)
        self.unknown_generated = any(row["generated"] is None for row in self.members)
        self.with_usr = any(row["usr"] is not None for row in self.members)
        self.accessor_usr_only = not self.with_usr and any(row["usrAccessor"] is not None for row in self.members)

    @staticmethod
    def is_property_accessor(row):
        return row["kind"] == "accessor" and row["parentKey"] is None


def coupling_families(rows):
    """The families of every function row (any role): each record joins the family of its topmost ancestor by
    `parentKey` (a missing or circular parent ends the climb); a topmost computed property accessor (kind
    accessor, no parent) groups with the property's other accessors in its file."""
    first_index = {}
    for index, row in enumerate(rows):
        first_index.setdefault(row["key"], index)
    groups = defaultdict(list)
    for index, row in enumerate(rows):
        current, seen = index, {index}
        while rows[current]["parentKey"] is not None:
            parent = first_index.get(rows[current]["parentKey"])
            if parent is None or parent in seen:
                break
            seen.add(parent)
            current = parent
        top = rows[current]
        if CouplingFamily.is_property_accessor(top):
            group = ("property", property_owner_key(top), top["file"])
        else:
            group = ("record", current)
        groups[group].append(row)
    families = defaultdict(list)
    for members in groups.values():
        family = CouplingFamily(members)
        families[family.identifier].append(family)
    return families


class HiddenCoupling:
    """Design 8.1, by its words, over SignalRows."""

    def __init__(self, rows, limits, min_support, family_match="key", owners="package"):
        from fractions import Fraction
        self.rows = rows
        self.limits = limits
        self.min_support = min_support                 # the configuration's history.coupling.min_support
        self.stored_min_support = rows.stored_min_support()
        self.family_match = family_match
        self.owner_rule = owners
        self.left_out = rows.left_out_history() or rows.left_out_m7("index", "indexScan")
        self.counts = Counter()
        self.terms = []                                # (pair, term) in couplingPair order
        self.members = defaultdict(list)               # term -> pair labels
        self.notes = []
        self.items = []
        self.owner_notes = Counter()
        if self.left_out is not None:
            return
        self.families = coupling_families(rows.all_functions)
        support_limit = Fraction(str(limits["support"]))
        confidence_limit = Fraction(str(limits["confidence"]))
        vias = sorted({via for _, _, via in rows.family_references if via not in COUPLING_VIA})
        if vias:
            self.notes.append(f"familyReference rows with via {vias}, which design 4.4 doesn't name (not counted)")
        for pair in rows.coupling_pairs:
            first, second = self.family(pair["familyA"], pair["fileA"]), self.family(pair["familyB"], pair["fileB"])
            term = self.classify(pair, first, second, support_limit, confidence_limit)
            self.counts["N"] += 1
            self.counts[term] += 1
            if term in ("R", "Q", "Y", "X", "C", "L", "B"):
                self.counts["P"] += 1
                self.counts["K"] += 1
                if term in ("C", "L", "B"):
                    self.counts["C"] += 1
            elif term == "W":
                self.counts["P"] += 1
            self.terms.append((pair, term))
            self.members[term].append(self.label(pair))
            if term == "L":
                smaller = min(pair["changesA"], pair["changesB"])
                self.items.append({"pair": pair, "first": first, "second": second, "smaller": smaller,
                                   "confidence": Fraction(pair["support"], smaller) if smaller else Fraction(0)})
        self.items.sort(key=lambda item: (-item["pair"]["support"], -item["confidence"], item["pair"]["familyA"],
                                          item["pair"]["fileA"], item["first"].line, item["pair"]["familyB"],
                                          item["pair"]["fileB"]))
        for note, count in sorted(self.owner_notes.items()):
            self.notes.append(f"{note} ({count})")

    @staticmethod
    def label(pair):
        return f"{pair['familyA']} ~ {pair['familyB']} (support {pair['support']}, " \
               f"{pair['changesA']}/{pair['changesB']})"

    def family(self, identifier, file):
        """The snapshot's family a pair names (design 8.1: family roots by key, as M3's pairs name them); the
        one in the pair's file when several share the key. `--family-match key-and-file` also asks for the
        file."""
        candidates = self.families.get(identifier, [])
        for family in candidates:
            if family.file == file:
                return family
        if candidates and self.family_match == "key":
            self.notes.append(f"{identifier}: matched by key, but its family is in {candidates[0].file}, "
                              f"not the pair's {file}")
            return candidates[0]
        return None

    def classify(self, pair, first, second, support_limit, confidence_limit):
        """Design 8.1, first that applies: U, G, T; of P, W; of K, R, Q, Y, X; of C, L or B."""
        if first is None or second is None:
            return "U"
        for family in (first, second):
            if family.unknown_generated:
                self.notes.append(f"{family.identifier}: a member's `generated` is null (read as not generated)")
        if first.generated or second.generated:
            return "G"
        if first.role != "production" or second.role != "production":
            return "T"
        if not (first.with_usr and second.with_usr):
            for family in (first, second):
                if family.accessor_usr_only:
                    self.notes.append(f"{family.identifier}: only a secondary accessor USR (read as no USR)")
            return "W"
        references = self.rows.family_references
        names = (first.identifier, second.identifier)
        if (names[0], names[1], "direct") in references or (names[1], names[0], "direct") in references:
            return "R"
        if (names[0], names[1], "requirement") in references or (names[1], names[0], "requirement") in references:
            return "Q"
        owner_first, owner_second = self.owner(first), self.owner(second)
        if owner_first is not None and owner_second is not None and \
                (owner_first == owner_second or self.nested(owner_first, owner_second)):
            return "Y"
        type_references = self.rows.family_type_references
        if (owner_second is not None and (names[0],) + owner_second in type_references) or \
                (owner_first is not None and (names[1],) + owner_first in type_references):
            return "X"
        smaller = min(pair["changesA"], pair["changesB"])
        listed = pair["support"] >= support_limit and pair["support"] * 100 >= confidence_limit * smaller
        return "L" if listed else "B"

    def owner(self, family):
        """The owning type of a family's root (design 4.3, package-declared types only), as (target, type path,
        type file or ''): none without a typePath; under `--owners package` (design 4.3: an extension's members
        belong to the package type its head extends, the type the USR's context mangles), for a Swift `usr` the
        `typeIndex` type whose `usr` is its longest proper prefix, else none (an extension of a type the package
        doesn't declare); for a root without a Swift `usr`, or under `--owners own-module`, the `typeIndex` type
        at the root's own (module, typePath, typeFile), else none."""
        row = family.root or family.members[0]
        path = row["typePath"]
        if not path:
            return None
        own = (row["module"], path, row["typeFile"] or "")
        usr = row["usr"] or ""
        if self.owner_rule != "package" or not usr.startswith("s:"):
            return own if own in self.rows.package_types else None
        best = None
        for type_usr, identity in self.rows.package_type_usrs.items():
            if len(type_usr) < len(usr) and usr.startswith(type_usr) and (best is None or len(type_usr) > len(best)):
                best, chosen = type_usr, identity
        if best is None:
            if own in self.rows.package_types:
                self.owner_notes["a root whose own target declares its type path but whose USR names no package "
                                 "type (no owner)"] += 1
            return None
        if chosen != own:
            self.owner_notes["a root owned by the package type its USR names, not its own (module, typePath, "
                             "typeFile): an extension of another target's type, or a qualified or typealias "
                             "head"] += 1
        return chosen

    @staticmethod
    def nested(first, second):
        """One type nested in the other: same target and type file, one type path a prefix of the other's
        followed by `.` (design 8.1's Y)."""
        if first[0] != second[0] or first[2] != second[2]:
            return False
        return first[1].startswith(second[1] + ".") or second[1].startswith(first[1] + ".")

    def note_applies(self, min_support):
        return min_support is not None and float(self.limits["support"]) < min_support

    def funnel(self):
        counts = self.counts
        return (f"{counts['N']} pairs = {counts['U']} with a family not in this snapshot + {counts['G']} with a "
                f"generated family + {counts['T']} with a test or helper family + {counts['P']} with both families "
                f"in production code; {counts['P']} = {counts['K']} judged + {counts['W']} with a family the index "
                f"didn't see; {counts['K']} = {counts['R']} referencing each other + {counts['Q']} calling through "
                f"a protocol the other implements + {counts['Y']} sharing or nesting a type + {counts['X']} "
                f"referencing the other's type or members + {counts['C']} without a static dependency; "
                f"{counts['C']} = {counts['L']} listed + {counts['B']} below the limits")

    def prose(self):
        return HIDDEN_COUPLING_PROSE.format(support=number_text(self.limits["support"]),
                                            confidence=number_text(self.limits["confidence"]))

    def rule(self):
        if self.left_out is not None:
            return self.prose()
        text = self.prose() + "; " + self.funnel()
        if self.note_applies(self.min_support):
            text += f"; pairs exist only at or above history.coupling.min_support ({self.min_support})"
        return text

    def expected_numbers(self):
        numbers = {term: self.counts[term] for term, _ in HIDDEN_COUPLING_TERMS if term not in ("P2", "K2", "C2")}
        numbers["P2"], numbers["K2"], numbers["C2"] = numbers["P"], numbers["K"], numbers["C"]
        return numbers

    @staticmethod
    def payload(item):
        pair, first, second = item["pair"], item["first"], item["second"]
        return {"coupling": {"partner": pair["familyB"], "partnerFile": pair["fileB"], "support": pair["support"],
                             "changesA": pair["changesA"], "changesB": pair["changesB"],
                             "confidence": {"support": pair["support"], "smaller": item["smaller"]},
                             "modules": [first.module, second.module], "sameFile": pair["fileA"] == pair["fileB"],
                             "sameModule": first.module == second.module}}


def hidden_expected_items(model):
    expected = []
    for rank, item in enumerate(model.items, start=1):
        pair, first = item["pair"], item["first"]
        lines = [first.line]
        for other in (first.lowest_line, model.rows.family_history_lines.get((pair["familyA"], pair["fileA"]))):
            if other is not None and other not in lines:
                lines.append(other)
        expected.append({"rank": rank, "subject": pair["familyA"], "file": pair["fileA"], "line": first.line,
                         "lines": lines, "score": pair["support"], "member": True, "payloads": model.payload(item)})
    return expected


def report_hidden_own(verdict, model, show_all):
    verdict.section(f"{HIDDEN_COUPLING}: this check's figures (design 8.1)")
    rows = model.rows
    verdict.info(f"limits: support {model.limits['support']}, confidence {model.limits['confidence']}%; "
                 f"history.coupling.min_support: configuration {model.min_support}, the history run's stored "
                 f"options {model.stored_min_support}")
    if model.left_out is not None:
        verdict.info(f"left out: {model.left_out}")
        return
    run = rows.history_run
    verdict.info(f"history: commit {run['commitHash'][:10]}, window {run['windowDays']} days, "
                 f"{run['windowCommits']} of {run['commits']} commits in the window; couplingPair rows "
                 f"{len(rows.coupling_pairs)}" + ("" if rows.coupling_table_held else " (no couplingPair table)"))
    verdict.info(f"index rows: familyReference {len(rows.family_references)} ("
                 + ", ".join(f"{via} {count}" for via, count in sorted(Counter(
                     via for _, _, via in rows.family_references).items())) + f"), familyTypeReference "
                 f"{len(rows.family_type_references)}, typeIndex types {len(rows.package_types)}; owners rule "
                 f"{model.owner_rule}, family match {model.family_match}")
    verdict.info("funnel: " + model.funnel())
    for term in ("U", "G", "T", "W", "R", "Q", "Y", "X", "B"):
        if model.members[term]:
            shown = model.members[term] if show_all else model.members[term][:5]
            more = len(model.members[term]) - len(shown)
            verdict.info(f"{term}: " + "; ".join(shown) + (f" ... and {more} more" if more else ""))
    if model.items:
        verdict.info(f"listed ({len(model.items)}), in order:")
        for rank, item in enumerate(model.items if show_all else model.items[:LISTED], start=1):
            pair = item["pair"]
            verdict.info(f"  #{rank} {pair['support']} {pair['familyA']} ({pair['fileA']}:{item['first'].line}) "
                         f"~ {pair['familyB']} ({pair['fileB']}) changes {pair['changesA']}/{pair['changesB']}")
        if not show_all and len(model.items) > LISTED:
            verdict.info(f"  ... and {len(model.items) - LISTED} more (--all lists them)")
    else:
        verdict.info("listed: none")
    for note in model.notes if show_all else model.notes[:20]:
        verdict.info(f"note: {note}")
    if not show_all and len(model.notes) > 20:
        verdict.info(f"... and {len(model.notes) - 20} more notes (--all lists them)")


def compare_coupling_source(verdict, rows):
    """The couplingPair rows against the stored scan's history block (design 9.1: the pairs leave the report blob
    for a table, and the blob keeps them too)."""
    if rows.stored_coupling is None or not rows.coupling_table_held:
        verdict.info("couplingPair rows not compared with the stored history block (" +
                     ("no couplingPair table" if not rows.coupling_table_held else "the stored scan has no history")
                     + ")")
        return
    fields = ("familyA", "fileA", "familyB", "fileB", "support", "changesA", "changesB")
    table = [tuple(row[field] for field in fields) for row in rows.coupling_pairs]
    stored = [tuple(pair.get(field) for field in fields) for pair in rows.stored_coupling]
    ordinals = [row["ordinal"] for row in rows.coupling_pairs]
    verdict.result("couplingPair rows equal the stored history block's pairs, in order", table == stored,
                   f"{len(table)} rows, {len(stored)} pairs in the block")
    if table != stored:
        verdict.listing([f"#{index}: table {mine}, block {theirs}" for index, (mine, theirs)
                         in enumerate(zip(table, stored)) if mine != theirs]
                        + [f"only in the table: {mine}" for mine in table[len(stored):]]
                        + [f"only in the block: {theirs}" for theirs in stored[len(table):]])
    if ordinals != list(range(len(ordinals))) and ordinals != list(range(1, len(ordinals) + 1)):
        verdict.info(f"couplingPair ordinals aren't consecutive: {ordinals[:10]}")


def compare_hidden_coupling(verdict, model, signal, expected):
    verdict.section(f"h   {HIDDEN_COUPLING}: left-out reason, rule, funnel, candidates, items, order and payloads")
    compare_coupling_source(verdict, model.rows)
    actual_left = signal.get("leftOut")
    verdict.result("left out", actual_left == model.left_out, f"expected {model.left_out!r}, got {actual_left!r}")
    rule = signal.get("rule", "")
    prose = re.compile(hidden_coupling_prose_pattern())
    found = prose.match(rule)
    limits_stated = found is not None and float(found.group(1)) == float(model.limits["support"]) \
        and float(found.group(2)) == float(model.limits["confidence"])
    verdict.result("rule states design 8.1's text with the limits in force", limits_stated,
                   ("" if found is None else f"support {found.group(1)}, confidence {found.group(2)}; ")
                   + f"expected {model.prose()!r}" if not limits_stated else "")
    if model.left_out is not None:
        verdict.result("left out: the text alone, or followed by '; '", found is not None and (
            found.end() == len(rule) or rule[found.end():].startswith("; ")), f"got {rule!r}")
        verdict.result("no items, no candidates", not signal.get("items") and signal.get("candidates", 0) == 0,
                       f"{len(signal.get('items') or [])} items, candidates {signal.get('candidates')}")
        return
    rest = rule[found.end():] if found is not None else rule
    verdict.result("the funnel follows the text after '; '", found is not None and rest.startswith("; "),
                   f"got {rest[:120]!r}")
    funnel_text = rest[2:] if rest.startswith("; ") else rest
    match = HIDDEN_COUPLING_FUNNEL.search(funnel_text)
    verdict.result("funnel in design 8.1's words", match is not None, "" if match else f"got {funnel_text[:500]!r}")
    if match is not None:
        if match.start() != 0:
            verdict.info(f"text between the rule and the funnel: {funnel_text[:match.start()]!r}")
        wanted = model.expected_numbers()
        differences = [f"{term} ({name}): expected {wanted[term]}, got {match.group(term)}"
                       for term, name in HIDDEN_COUPLING_TERMS if int(match.group(term)) != wanted[term]]
        verdict.result("every funnel number", not differences, model.funnel() if differences else "")
        verdict.listing(differences)
        value = {term: int(match.group(term)) for term, _ in HIDDEN_COUPLING_TERMS}
        sums = value["N"] == value["U"] + value["G"] + value["T"] + value["P"] \
            and value["P"] == value["K"] + value["W"] \
            and value["K"] == value["R"] + value["Q"] + value["Y"] + value["X"] + value["C"] \
            and value["C"] == value["L"] + value["B"] \
            and value["P2"] == value["P"] and value["K2"] == value["K"] and value["C2"] == value["C"]
        verdict.result("the funnel's parts add up as stated", sums)
        tail = funnel_text[match.end():]
        note = MIN_SUPPORT_NOTE.match(tail[2:]) if tail.startswith("; ") else None
        stated = int(note.group("m")) if note is not None else None
        readings = []   # (where m comes from, m) readings that agree with the rule
        for source, minimum in (("the configuration", model.min_support),
                                ("the history run's stored options", model.stored_min_support)):
            if minimum is None:
                continue
            if model.note_applies(minimum) and stated == minimum:
                readings.append(f"note with {source}'s min_support {minimum}")
            elif not model.note_applies(minimum) and note is None:
                readings.append(f"no note: the support limit isn't below {source}'s min_support {minimum}")
        verdict.result("the min_support note exactly when the support limit is below it", bool(readings),
                       "; ".join(readings) if readings else
                       f"note {'(' + str(stated) + ')' if note else 'absent'}, "
                       f"support limit {model.limits['support']}, "
                       f"min_support: configuration {model.min_support}, stored {model.stored_min_support}")
        leftover = tail[2 + note.end():] if note is not None else tail
        if leftover:
            verdict.info(f"text after the funnel: {leftover!r}")
    candidates = signal.get("candidates")
    named = [name for name, term in (("N, every pair", "N"), ("P, production pairs", "P"), ("K, judged", "K"),
                                     ("C, without a static dependency", "C")) if candidates == model.counts[term]]
    verdict.result("candidates", bool(named), f"{candidates}: " + " or ".join(named) if named else
                   f"expected N {model.counts['N']}, P {model.counts['P']}, K {model.counts['K']} or C "
                   f"{model.counts['C']}, got {candidates}")
    items = signal.get("items") or []
    listed = [(item.get("subject"), item.get("file"), (item.get("coupling") or {}).get("partner"),
               (item.get("coupling") or {}).get("partnerFile")) for item in items]
    wanted = [(entry["subject"], entry["file"], entry["payloads"]["coupling"]["partner"],
               entry["payloads"]["coupling"]["partnerFile"]) for entry in expected]
    verdict.result("listed pairs in order", listed == wanted, f"{len(wanted)} items")
    if listed != wanted:
        verdict.listing([f"#{rank}: expected {mine}, got {theirs}" for rank, (mine, theirs)
                         in enumerate(zip(wanted, listed), start=1) if mine != theirs]
                        + [f"missing {mine}" for mine in wanted[len(listed):]]
                        + [f"extra {theirs}" for theirs in listed[len(wanted):]])
    differences, notes = [], Counter()
    for item, entry in zip(items, expected):
        label = f"#{entry['rank']} {entry['subject']}"
        if item.get("rank") != entry["rank"] or item.get("member") is not True:
            differences.append(f"{label}: rank {item.get('rank')} member {item.get('member')}")
        if not isinstance(item.get("score"), (int, float)) or float(item["score"]) != entry["score"]:
            differences.append(f"{label}: score {item.get('score')} != {entry['score']}")
        if item.get("line") != entry["line"]:
            if item.get("line") in entry["lines"][1:]:
                notes[f"line {item.get('line')} for a family whose root (or first member) starts at "
                      f"{entry['line']}"] += 1
            else:
                differences.append(f"{label}: line {item.get('line')} != {entry['line']}")
        extra = sorted(key for key in item if key not in ITEM_KEYS and key not in HIDDEN_COUPLING_PAYLOADS)
        if extra:
            differences.append(f"{label}: payloads hidden coupling doesn't fill: {extra}")
        if item.get("coupling") != entry["payloads"]["coupling"]:
            differences.append(f"{label}: coupling {json.dumps(item.get('coupling'), sort_keys=True)} != "
                               f"{json.dumps(entry['payloads']['coupling'], sort_keys=True)}")
    verdict.result("ranks, members, scores, lines and payloads", not differences, f"{len(expected)} items")
    verdict.listing(differences)
    for note, count in sorted(notes.items()):
        verdict.info(f"accepted: {note} ({count})")


def signals_mode(arguments):
    report = None
    if arguments.report:
        try:
            with open(arguments.report, encoding="utf-8") as handle:
                report = json.load(handle)
        except (OSError, ValueError) as error:
            fail(f"{arguments.report} doesn't read as JSON: {error}")
    elif not arguments.own_only:
        fail("give --report (`swiftstats report --format json` of the snapshot), or --own-only")
    limits = hidden_coupling_limits(arguments.config, arguments.set)
    min_support = configured_min_support(arguments.config)
    rows = SignalRows(arguments.store, arguments.snapshot, None if report is None else report.get("snapshot"))
    verdict = Verdict(arguments.all)
    hidden = HiddenCoupling(rows, limits, min_support, arguments.family_match, arguments.owners)
    hidden_expected = hidden_expected_items(hidden) if hidden.left_out is None else []
    model = TestOnlyProduction(rows)
    dead = DeadButTested(rows)
    computed = model.left_out is None or dead.left_out is None
    mutation_model, mutation_check = mutation_payload_model(rows) if computed else (None, None)
    expected = test_only_expected_items(model, mutation_model, mutation_check) if model.left_out is None else []
    dead_expected = dead_expected_items(dead, mutation_model, mutation_check) if dead.left_out is None else []
    report_hidden_own(verdict, hidden, arguments.all)
    report_test_only_own(verdict, model, arguments.all)
    report_dead_own(verdict, dead, arguments.all)
    verdict.info(f"hidden-coupling limits in force: {limits}")
    if arguments.dump:
        dead_items = []
        for entry in dead_expected:
            item = dict({key: entry[key] for key in ITEM_KEYS}, **entry["payloads"])
            if entry["coverageSetting"] is not None:
                item["mutation"] = dict(item["mutation"], coverage=entry["coverageSetting"])
            dead_items.append(item)
        write_json(arguments.dump, {
            "snapshot": rows.state, "snapshotId": rows.id, "limits": {HIDDEN_COUPLING: limits},
            "signals": [{"name": HIDDEN_COUPLING, "leftOut": hidden.left_out, "rule": hidden.rule(),
                         "candidates": hidden.counts["N"] if hidden.left_out is None else 0,
                         "items": [dict({key: entry[key] for key in ITEM_KEYS}, **entry["payloads"])
                                   for entry in hidden_expected]},
                        {"name": DEAD_BUT_TESTED, "leftOut": dead.left_out, "rule": dead.rule(),
                         "candidates": dead.counts["N"] if dead.left_out is None else 0, "items": dead_items},
                        {"name": TEST_ONLY, "leftOut": model.left_out, "rule": model.rule(),
                         "candidates": model.counts["N"] if model.left_out is None else 0,
                         "items": [dict({key: entry[key] for key in ITEM_KEYS}, **entry["payloads"])
                                   for entry in expected]}],
            "funnel": dict(model.counts), "withoutUSRByReason": dict(model.without_by_reason),
            "excluded": {term: keys for term, keys in model.members.items()}, "problems": model.problems,
            "deadButTested": {"funnel": dict(dead.counts), "members": {term: keys for term, keys in
                                                                        dead.members.items()},
                              "entryTerms": {} if dead.production is None else
                              {str(ordinal): term for ordinal, term in sorted(dead.production.terms.items())},
                              "notes": dead.notes},
            "hiddenCoupling": {"funnel": dict(hidden.counts), "minSupport": {"configuration": hidden.min_support,
                                                                              "stored": hidden.stored_min_support},
                               "pairs": [{"ordinal": pair["ordinal"], "familyA": pair["familyA"],
                                          "familyB": pair["familyB"], "term": term} for pair, term in hidden.terms],
                               "notes": hidden.notes}})
    if report is None:
        print("\nRESULT: own figures only (nothing compared)")
        return 0
    verdict.section("t   thresholds: the report lists the hidden-coupling limits this check uses, and none for "
                    "dead but tested or test-only")
    verdict.info(f"report schema {report.get('schemaVersion')} (5 before plan step 10, 6 after)")
    listed_limits = (report.get("thresholds") or {}).get("limits") or {}
    verdict.result("hidden-coupling limits", listed_limits.get(HIDDEN_COUPLING) == limits,
                   f"expected {limits}, got {listed_limits.get(HIDDEN_COUPLING)}")
    unlimited = [name for name in (DEAD_BUT_TESTED, TEST_ONLY) if name in listed_limits]
    verdict.result("dead but tested and test-only take no limits", not unlimited, f"listed for {unlimited}")
    verdict.section("n   names: the three M7 signals, after uneven-clone-mutation in report order")
    names = [signal.get("name") for signal in report.get("signals", [])]
    tail = names[-len(M7_SIGNALS):]
    in_order = tail == list(M7_SIGNALS) and len(names) > len(M7_SIGNALS) \
        and names[-len(M7_SIGNALS) - 1] == LAST_M6_SIGNAL and all(names.count(name) == 1 for name in M7_SIGNALS)
    verdict.result("report order", in_order, f"last four: {names[-len(M7_SIGNALS) - 1:]}")
    by_name = {signal.get("name"): signal for signal in report.get("signals", [])}
    if HIDDEN_COUPLING not in by_name:
        verdict.result(f"{HIDDEN_COUPLING} listed", False, "the report has no such signal")
    else:
        compare_hidden_coupling(verdict, hidden, by_name[HIDDEN_COUPLING], hidden_expected)
    if DEAD_BUT_TESTED not in by_name:
        verdict.result(f"{DEAD_BUT_TESTED} listed", False, "the report has no such signal")
    else:
        compare_dead_but_tested(verdict, dead, by_name[DEAD_BUT_TESTED], dead_expected)
    if TEST_ONLY not in by_name:
        verdict.result(f"{TEST_ONLY} listed", False, "the report has no such signal")
    else:
        compare_test_only(verdict, model, by_name[TEST_ONLY], expected)
    print("\nRESULT: " + ("FAIL" if verdict.failed else "PASS"))
    return 1 if verdict.failed else 0


# --------------------------------------------------------------------------


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    modes = parser.add_subparsers(dest="mode", required=True)
    dumping = modes.add_parser("dump", help="write the reader's values for an index store as JSON")
    dumping.add_argument("store", help="the directory holding v5/units (the build's out/)")
    dumping.add_argument("library", help="the toolchain's libIndexStore.dylib")
    dumping.add_argument("describe", help="`swift package describe --type json` of <root>")
    dumping.add_argument("root", help="the package root: records are dumped for units whose main file is under it")
    dumping.add_argument("--output", help="write the JSON here instead of standard output")
    lines = modes.add_parser("build-lines", help="account for every line of a build's output")
    lines.add_argument("--stderr", help="the build's standard error (timings and diagnostics)")
    lines.add_argument("--log", help="the build's standard output (the -v task log)")
    lines.add_argument("--combined", help="one file holding both streams (2>&1): spliced lines expected")
    lines.add_argument("--json", help="write this parse as JSON (entries, diagnostics, counters, classes)")
    lines.add_argument("--compare", help="a reader's parse in the --json shape, compared with this one")
    lines.add_argument("--all", action="store_true", help="list every difference and unaccounted line")
    building = modes.add_parser("build", help="check the scan's type-check timings and compiler warnings")
    building.add_argument("package", help="the scanned package (its .swiftstats/index-build holds the output)")
    building.add_argument("scan", help="`swiftstats scan --index --format json` of <package>")
    building.add_argument("--store", help="the store the scan saved to: its rows are compared too")
    building.add_argument("--snapshot", type=int, help="the snapshot id in --store (default: the newest)")
    building.add_argument("--stderr", help="the build's stderr (default: <build>/swiftstats-build.stderr)")
    building.add_argument("--log", help="the build's stdout (default: <build>/swiftstats-build.log)")
    building.add_argument("--combined", help="one file holding both streams, instead of --stderr and --log")
    building.add_argument("--swift", default="swift",
                          help="the swift whose toolchain describes <package> (default: swift on PATH)")
    building.add_argument("--describe", help="a describe JSON of <package> instead of running describe")
    building.add_argument("--root-spelling", help="the package root as the output spells it (default: its real path)")
    building.add_argument("--build-spelling",
                          help="the build directory as the output spells it (default: its real path)")
    building.add_argument("--own-only", action="store_true",
                          help="print this check's figures without comparing them with the scan JSON")
    building.add_argument("--dump", help="write this check's figures as JSON")
    building.add_argument("--all", action="store_true", help="list every difference and unaccounted line")
    building.add_argument("--without-typecheck", action="store_true",
                          help="skip the typecheck.* roll-up comparison (design 6.4) with the scan JSON and the store")
    joining = modes.add_parser("usr", help="check the scan's units, USRs, reasons, lists and coupling (u1-u7)")
    joining.add_argument("package", help="the scanned package (its .swiftstats/index-build holds the store)")
    joining.add_argument("scan", help="`swiftstats scan --index --format json` of <package>")
    joining.add_argument("--swift", default="swift",
                         help="the swift asked for -print-target-info in <package> (default: swift on PATH)")
    joining.add_argument("--library", help="libIndexStore.dylib (default: the package toolchain's)")
    joining.add_argument("--demangle", help="swift-demangle (default: the package toolchain's)")
    joining.add_argument("--describe", help="a describe JSON of <package> instead of running describe")
    joining.add_argument("--index-store", help="the directory holding v5/units (default: <build>/out)")
    joining.add_argument("--reader", help="a recorded `dump` JSON read instead of the store (no quarantine check)")
    joining.add_argument("--root-spelling", help="the package root as a recording spells it (e.g. @ROOT@)")
    joining.add_argument("--build-spelling", help="the build directory as a recording spells it (e.g. @BUILD@)")
    joining.add_argument("--spelling", action="append", metavar="TOKEN=PATH",
                         help="another recorded path prefix (e.g. @DEP@=/path); repeatable")
    joining.add_argument("--log", help="the build's -v task log (default: <build>/swiftstats-build.log)")
    joining.add_argument("--store", help="the store the scan saved to: u8 compares its index rows with the scan JSON")
    joining.add_argument("--snapshot", type=int, help="the snapshot id in --store (default: the newest)")
    joining.add_argument("--own-only", action="store_true",
                         help="print this check's figures and u3-u6 without comparing with the scan JSON")
    joining.add_argument("--dump", help="write this check's figures as JSON")
    joining.add_argument("--all", action="store_true", help="list every difference")
    joining.add_argument("--without-u7", action="store_true",
                         help="skip u7 (references, edges, types, cycles, family references)")
    joining.add_argument("--local-containers", choices=("symbol", "enclosing"), default="symbol",
                         help="u7: a local variable named as a reference's container is kept as a symbol (design "
                              "4.1 as written, the default) or replaced by its enclosing declaration")
    joining.add_argument("--requirements", choices=("protocol", "package", "all"), default="protocol",
                         help="u7: which overridden USRs' references count for their witnesses: protocol "
                              "requirements (design 4.1 as written, the default), only those of protocols the "
                              "package declares, or every overridden USR (class methods too)")
    rowing = modes.add_parser("rows", help="check u8 whole: every M7 row of a snapshot against the scan JSON "
                                            "that saved it")
    rowing.add_argument("scan", help="`swiftstats scan --format json` output of the scan that saved --store's snapshot")
    rowing.add_argument("--store", required=True, help="the store the scan saved to (opened read-only)")
    rowing.add_argument("--snapshot", type=int, help="the snapshot id in --store (default: the newest)")
    rowing.add_argument("--all", action="store_true", help="list every difference")
    dead = modes.add_parser("dead", help="run outskirts twice and compare with the periphery collector's output")
    dead.add_argument("package", help="the scanned package (its .swiftstats/index-build holds the store)")
    dead.add_argument("scan", help="`swiftstats scan --index --format json` of <package>")
    dead.add_argument("outskirts", help="the outskirts executable, run in place")
    dead.add_argument("--store", help="the store the scan saved to: its rows are compared too")
    dead.add_argument("--snapshot", type=int, help="the snapshot id in --store (default: the newest)")
    dead.add_argument("--swift", default="swift",
                      help="the swift asked for -print-target-info in <package> (default: swift on PATH)")
    dead.add_argument("--library", help="libIndexStore.dylib (default: the package toolchain's)")
    dead.add_argument("--describe", help="a describe JSON of <package> instead of running describe")
    dead.add_argument("--index-store", help="the directory holding v5/units (default: <build>/out)")
    dead.add_argument("--roots-file", help="the collector's kept roots output (default: <build>/"
                                           + KEPT_OUTPUT["roots"] + ")")
    dead.add_argument("--production-file", help="the collector's kept production output (default: <build>/"
                                                + KEPT_OUTPUT["production"] + ")")
    dead.add_argument("--use-scan-inputs", action="store_true",
                      help="give outskirts the collector's own config and describe JSON instead of this script's")
    dead.add_argument("--output-dir", help="keep each run's stdout and stderr here")
    dead.add_argument("--own-only", action="store_true",
                      help="run outskirts and print this check's figures without comparing")
    dead.add_argument("--dump", help="write this check's runs, decoded entries and mapping as JSON")
    dead.add_argument("--all", action="store_true", help="list every difference")
    dead.add_argument("--demangle", help="swift-demangle for the mapping's own join (default: the package toolchain's)")
    dead.add_argument("--without-mapping", action="store_true",
                      help="the run part only: no classes, mapping, dead lines or ratio (plan step 6a)")
    dead.add_argument("--index-mode", choices=("auto", "index", "position"), default="auto",
                      help="map with my own join and type ownership (index) or by position: auto follows the scan's "
                           "index collector (ran: index)")
    dead.add_argument("--local-rule", choices=("plan", "literal"), default="plan",
                      help="class local: variables other than parameters, by the index's local property or a "
                           "position inside a function record (plan: step 6a's adopted reading, which design 13's "
                           "6b tests need), or design 5.3 word for word (any kind by the index, any variable by "
                           "position)")
    dead.add_argument("--map-hints", choices=("all", "unused"), default="all",
                      help="which production entries are mapped to records (design 5.4: every entry; unused: only "
                           "hint unused)")
    dead.add_argument("--ordinal-base", type=int, choices=(0, 1),
                      help="the first entry's ordinal (default: the scan's lowest declaration ordinal, else 1)")
    signalling = modes.add_parser("signals", help="re-derive M7's signals from a store's rows (plan steps 9a, "
                                                  "9b and 9c: test-only production, dead but tested, hidden "
                                                  "coupling)")
    signalling.add_argument("store", help="the store holding the snapshot (store v6)")
    signalling.add_argument("--report", help="`swiftstats report --format json` of the snapshot, compared")
    signalling.add_argument("--config", help="the configuration the report was made with (its signals: limits)")
    signalling.add_argument("--set", action="append", metavar="SIGNAL.LIMIT=VALUE",
                            help="a limit, such as hidden-coupling.support=4, applied after --config")
    signalling.add_argument("--snapshot", type=int,
                            help="the snapshot id (default: the report's snapshot, else the newest)")
    signalling.add_argument("--own-only", action="store_true",
                            help="print this check's figures without a report to compare")
    signalling.add_argument("--dump", help="write this check's signal, funnel and exclusions as JSON")
    signalling.add_argument("--all", action="store_true", help="list every difference and every item")
    signalling.add_argument("--family-match", choices=("key", "key-and-file"), default="key",
                            help="hidden coupling: a pair's family is the snapshot's family with its key (design "
                                 "8.1: family roots by key, as M3's pairs name them; the default), or with its key "
                                 "and the pair's file")
    signalling.add_argument("--owners", choices=("package", "own-module"), default="package",
                            help="hidden coupling: a root's owning type is (package, design 4.3, the default) the "
                                 "package type whose USR is the longest proper prefix of the root's Swift USR, else "
                                 "the package type at its own target, type path and type file; own-module takes the "
                                 "latter for every root")
    arguments = parser.parse_args()
    return {"dump": dump_mode, "build-lines": build_lines_mode, "build": build_mode,
            "usr": usr_mode, "rows": rows_mode, "dead": dead_mode,
            "signals": signals_mode}[arguments.mode](arguments)


if __name__ == "__main__":
    sys.exit(main())
