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

Modes (later plan steps add `usr`, `dead`, `signals` and
`coverage-names`):

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
           `name`; `file`, the path the record dependencies of those units
           give it; `otherFiles`, only when they give one record several
           paths (files with one name and the same contents, such as
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
A diagnostic's message continues on the following lines as far as the line
that makes it end with a diagnostic ID (the build passes
-debug-diagnostic-names), within 20 lines none of which could not continue
a message (blank, excerpt, box, decoration, timing, diagnostic, a
`warning:`/`error:`/`note:`/`remark:`/`info:` line, a group footnote); a
message that ends with no ID has no continuation. Each excerpt echo of the
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
    and `@BUILD@`);
  - with `--store`, the store's tables as design section 9.1 names them.
Not the scan JSON's `build` block, findings or roll-ups, which it checks.

Usage:
    python3 -I -B Scripts/index-check.py dump <store> <libIndexStore.dylib>
                                         <describe.json> <root>
                                         [--output <path>]
    python3 -I -B Scripts/index-check.py build-lines [--stderr <file>]
                                         [--log <file>] [--combined <file>]
                                         [--json <path>] [--compare <path>]
                                         [--all]
    python3 -I -B Scripts/index-check.py build <package> <scan.json>
                                         [--store <store>] [--snapshot <id>]
                                         [--stderr <file>] [--log <file>]
                                         [--combined <file>]
                                         [--root-spelling <text>]
                                         [--build-spelling <text>]
                                         [--own-only] [--dump <path>] [--all]

For `dump`, <store> is the directory holding `v5/units` (for the T1 build,
`<package>/.swiftstats/index-build/out`). The JSON goes to standard output,
or to `--output`; a summary (unit, record and occurrence counts) goes to
standard error.

Exit status: `dump` 0 when the dump is written, 2 on bad input or a store
that doesn't read; `build-lines` and `build` 0 when every check passes, 1
when one fails, 2 on bad input.
"""

import argparse
import ctypes
import glob
import hashlib
import json
import os
import re
import sys
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
            if unit["mainFile"] == "" or not is_under(unit["mainFile"], root):
                continue
            for record, path in records:
                path = real_path(path, f"record {record}'s file") if path else ""
                record_files.setdefault(record, set()).add(path)
        dumped = []
        occurrence_count = 0
        shared = 0
        for record in sorted(record_files):
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
    to reach the line that ends with the diagnostic ID (the build passes
    -debug-diagnostic-names), within CONTINUATION_LIMIT lines none of which
    can't continue a message; 0 when the message already ends with an ID or
    no such line comes."""
    if split_suffixes(message)[1] is not None:
        return 0
    joined = message
    for offset in range(CONTINUATION_LIMIT):
        index = start + offset
        if index >= len(lines) or ends_message(lines[index]):
            return 0
        joined += "\n" + lines[index]
        if split_suffixes(joined)[1] is not None:
            return offset + 1
    return 0


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
    """The scan JSON's records, types, files and targets, and the package
    sources on disk."""

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

    def relative(self, path):
        """(class, package-relative NFC path) of a compiler path."""
        for spelling, kind in ((self.build_spelling, "build"), (self.root_spelling, "root")):
            if path.startswith(spelling + "/"):
                if kind == "build":
                    return "build", None
                return "root", unicodedata.normalize("NFC", path[len(spelling) + 1:])
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
    if arguments.store:
        compare_store(verdict, package, timings, warnings, arguments.store, arguments.snapshot)
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
    building.add_argument("--root-spelling", help="the package root as the output spells it (default: its real path)")
    building.add_argument("--build-spelling",
                          help="the build directory as the output spells it (default: its real path)")
    building.add_argument("--own-only", action="store_true",
                          help="print this check's figures without comparing them with the scan JSON")
    building.add_argument("--dump", help="write this check's figures as JSON")
    building.add_argument("--all", action="store_true", help="list every difference and unaccounted line")
    arguments = parser.parse_args()
    return {"dump": dump_mode, "build-lines": build_lines_mode, "build": build_mode}[arguments.mode](arguments)


if __name__ == "__main__":
    sys.exit(main())
