#!/usr/bin/env python3
"""Check a `swiftstats scan --index` result independently (M7 done-when).

The index collector reads the index store the T1 build writes, through
indexstore-db's `IndexStore` product. This script reads the same store
without using any of SwiftStats' code or that product: its own reader is
`ctypes` over the toolchain's `libIndexStore.dylib`, through the C API's
`_apply_f` (function-pointer) entry points (M7 design, sections 2.2, 11 and
13). Run it as `python3 -I -B Scripts/index-check.py <mode> ...`, so it
writes no bytecode cache beside itself.

Modes (later plan steps add `build`, `usr`, `dead`, `signals` and
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

Usage:
    python3 -I -B Scripts/index-check.py dump <store> <libIndexStore.dylib>
                                         <describe.json> <root>
                                         [--output <path>]

<store> is the directory holding `v5/units` (for the T1 build,
`<package>/.swiftstats/index-build/out`). The JSON goes to standard output,
or to `--output`; a summary (unit, record and occurrence counts) goes to
standard error.

Exit status is 0 when the dump is written, 2 on bad input or a store that
doesn't read.
"""

import argparse
import ctypes
import glob
import hashlib
import json
import os
import sys
import unicodedata

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


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    modes = parser.add_subparsers(dest="mode", required=True)
    dumping = modes.add_parser("dump", help="write the reader's values for an index store as JSON")
    dumping.add_argument("store", help="the directory holding v5/units (the build's out/)")
    dumping.add_argument("library", help="the toolchain's libIndexStore.dylib")
    dumping.add_argument("describe", help="`swift package describe --type json` of <root>")
    dumping.add_argument("root", help="the package root: records are dumped for units whose main file is under it")
    dumping.add_argument("--output", help="write the JSON here instead of standard output")
    arguments = parser.parse_args()
    return {"dump": dump_mode}[arguments.mode](arguments)


if __name__ == "__main__":
    sys.exit(main())
