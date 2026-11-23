#!/usr/bin/env python3
"""Check a `swiftstats scan --mutation` result independently (M6 done-when).

The swiftmutator collector reads SwiftMutator's results file, joins its
JSON report and maps every mutant onto the scan's records. This script
checks that without using any of SwiftStats' code. `base` mode checks a
snapshot made by one full run (M6 design, section 9 step 2), against the
scan JSON, the results file the collector kept
(`.swiftstats/mutation/runs/<id>/results.jsonl`), the scanned sources, and
SwiftMutator's own JSON report, which this script makes itself with
`swift-mutator report <results file> -f json`:

  a  its own reader of the results file (sessions, formatVersion 1 to 4 per
     header, `projectDelta` trees with their tree hashes, unparseable lines
     skipped, the last `mutant` line of a key winning, `retired`, not covered
     from the last header, completeness) gives exactly the scan's mutant
     set, keys, verdicts and recorded fields, and the run's facts and tree.
  b  those verdicts equal SwiftMutator's report entry by entry, its keys
     parsed from the right into all five parts and joined one to one,
     keyless placeholder entries skipped; `mutantsByOutcome` equals the
     scan's `everyMutant` counts (SwiftMutator's `notCovered` is the scan's
     `noCoverage`); `globalMutationScore` equals `everyMutant`'s truncated
     score; every keyed file's `mutationScore` equals the truncated score of
     the scan's rows of that file, SwiftMutator's 0 when every result is a
     build error read as the scan's null.
  c  every `suspectOnly` equals the report's flag by the design's
     tri-state: present is true; absent is false when the report's
     `killingTestSummary.suspectsChecked` is true and null (not judged)
     otherwise; only a kill by a failed test (outcome `failed`) can have one.
     The run's `suspectsJudged` is `suspectsChecked`.
  d  its own placement equals the scan's `anchor`, `place`, `owner` and
     `reason` for every mutant: the file class (first match: a `.build`
     folder at any depth, outside the root, a test target's directory, not
     Swift, a production target's directory, else another package), the
     hash gate, the anchor from the source bytes (the point, a byte order
     mark's 3 bytes added on line 1, then for a point in whitespace or a
     comment the next non-trivia character for the relational, logical and
     boundary swaps and the last one before it for every other operator),
     the innermost production record holding the anchor by the scan's
     record ranges (latest start, earliest end, key), top-level code only on
     its statement lines, else the innermost type, else the file. And a
     column-exact text check independent of both: for a start-anchored
     mutant the source token at the point (past whitespace and comments for
     the swaps) is the first token of `snapshot.before`; for an end-anchored
     one (RemoveSideEffects, SwapTernary's first link, the `false` constants
     of RelationalOperatorReplacement and ReplaceBooleanValue) the last
     non-trivia character before the point is the last character of
     `snapshot.before`. A SwapTernary point on a `?` is a later link of a
     chain (SwiftMutator places it there), whose `before` must hold a `?`.
     End-anchored points that fall on the start of the next token (no
     trivia after the code) are listed for information: the design's rule
     anchors them on that token.
  e  per record and attachment, the counts recomputed from the report's
     outcomes and kill lists over this script's placement (and the header's
     not-covered entries) equal the scan's `records` and `attachments`; the
     scan's `everyMutant`, `dropped` and `unmapped` too; per production module
     and project, the counts, the score (killed, scored, percent multiplied
     first and rounded to hundredths, null when incomplete) and the function
     states equal the roll-ups.
  f  the not-covered rows are the last header's `mutantsNotCovered` less the
     tested keys, each placed as in d.

  g  with `--store`, the snapshot's stored rows (store v5) equal the scan's
     mutation block column by column: the scan row, each run, each path of
     the tree, each suspect test and each mutant in order, and the stored
     `mutation.*` roll-up numbers equal the scan's roll-ups. The snapshot is
     the newest one of the scan's package, its path in the repository, and
     the commit and dirtiness of the last run not carried from a base.

It also prints the mapped share of in-body mutants (section 9 step 3), for
information.

Inputs it trusts from SwiftStats, as M5's checker verified them against
llvm-cov: the scan JSON's record and type ranges, roles, modules, the
targets and their files, the parsed files and the generated marks. Top-level
statement lines come from `coverage-check.py`'s `statement_lines`, which this
script imports. It reads the source and results bytes itself.

Usage:
    Scripts/mutation-check.py base <package-dir> <scan.json>
                              [--results <results.jsonl>]
                              [--report <report.json> | --mutator <swift-mutator>]
                              [--work-dir <dir>] [--store <stats.sqlite>]
                              [--all] [--dump <path>]

<scan.json> is `swiftstats scan --mutation --format json` of <package-dir>
(with or without a store): its `mutation` block from one full run. The
results file is the run's `resultsFile` under <package-dir> unless
`--results` names another. The report is made with `--mutator` (default
`swift-mutator` on PATH) into a temporary folder, unless `--report` names
one made the same way. That folder is made in `--work-dir` (default: the
folder holding <scan.json>) and removed on every exit; the script writes
no bytecode cache, so a run leaves nothing beside it in Scripts/. `--all` lists every difference instead of the first
20 of each kind; `--dump` writes this script's mapping as JSON.

Exit status is 0 when every check passes, 1 when one fails, 2 on bad input.
"""

import argparse
import hashlib
import importlib.util
import json
import os
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unicodedata
from collections import defaultdict

# Loading coverage-check.py below would otherwise write a `__pycache__` into
# the repository's Scripts/ folder.
sys.dont_write_bytecode = True

LIMIT = 20
HERE = os.path.dirname(os.path.abspath(__file__))
BOM = b"\xef\xbb\xbf"
NEWEST_FORMAT = 4
LINK_PREFIX = "link:"

# The counts every record, attachment and roll-up holds.
COUNT_FIELDS = ("buildErrors", "crashKills", "judgedKills", "killed", "noCoverage", "notCovered",
                "survived", "suspectOnly", "timedOut")
DROPPED_CLASSES = ("build", "otherLanguage", "otherPackage", "outsideRoot", "testFiles")

# Unmapped reasons.
EXCLUDED = "excluded"
NOT_PARSED = "not parsed"
FILE_CHANGED = "file changed"
SYMLINK = "symlink"
NO_FILE_HASH = "no file hash"
NO_SUCH_POSITION = "position outside its file"

# The operators whose point may lie in the leading trivia of the binary
# operator they change (design section 3), and the replacements of
# RelationalOperatorReplacement that make a constant instead.
SWAPS = {"ChangeLogicalConnector", "RelationalBoundary", "RelationalOperatorReplacement"}
CONSTANTS = {"true", "false"}

# SwiftMutator's report outcomes (judged: a pass whose block didn't run is
# noCoverage) as verdicts.
REPORT_VERDICTS = {
    "failed": "killed", "runtimeError": "killed", "passed": "survived", "noCoverage": "noCoverage",
    "timeout": "timedOut", "buildError": "buildError",
}

OPERATOR_CHARACTERS = set("/=-+!*%<>&|^~?.")
WORD_START = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$#@`")


def load_coverage_check():
    """coverage-check.py as a module, for its `statement_lines` and owner rules."""
    spec = importlib.util.spec_from_file_location("coverage_check", os.path.join(HERE, "coverage-check.py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


COVERAGE_CHECK = load_coverage_check()


# --------------------------------------------------------------------------
# Small helpers


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(2)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def nfc(path):
    return unicodedata.normalize("NFC", path)


def tree_hash(files):
    """SwiftMutator's tree hash: SHA-256 over every "path\\0hash\\n", sorted by the paths' bytes."""
    text = "".join(f"{path}\0{files[path]}\n" for path in sorted(files, key=lambda p: p.encode("utf-8")))
    return sha256(text.encode("utf-8"))


def truncated(killed, scored):
    """The whole percent SwiftMutator prints: killed × 100 ÷ scored, truncated; None when nothing scored."""
    return killed * 100 // scored if scored else None


def percent(killed, scored):
    """killed × 100 ÷ scored multiplied first, rounded half away from zero to hundredths; None when nothing scored."""
    if not scored:
        return None
    hundredths = (2 * killed * 10000 + scored) // (2 * scored)
    return hundredths / 100


def key_text(key):
    path, operator, line, column, occurrence = key
    return f"{path}:{line}:{column} {operator}" + (f" (#{occurrence + 1})" if occurrence else "")


def parse_report_key(text):
    """A report entry's `key` (`path:line:column Operator`, plus ` (#k)` for
    occurrence k−1), parsed from the right, so a path may hold spaces and colons."""
    occurrence = 0
    if text.endswith(")") and " (#" in text:
        head, _, tail = text.rpartition(" (#")
        if tail[:-1].isdigit():
            occurrence = int(tail[:-1]) - 1
            text = head
    location, _, operator = text.rpartition(" ")
    rest, _, column = location.rpartition(":")
    path, _, line = rest.rpartition(":")
    if not (operator and column.isdigit() and line.isdigit() and path):
        return None
    return (path, operator, int(line), int(column), occurrence)


# --------------------------------------------------------------------------
# Reading results.jsonl, independently of SwiftStats' reader


class Results:
    """A results file read by SwiftMutator's own rules (design section 2)."""

    def __init__(self, path):
        with open(path, "rb") as handle:
            raw = handle.read()
        self.path = path
        self.sha256 = sha256(raw)
        self.unparseable = []
        self.skipped_sessions = []  # line numbers of lines whose session has no readable header
        self.headers = {}  # session -> header
        self.order = []  # sessions in the order their headers appear
        self.trees = {}  # treeSHA256 -> files
        self.tree_of_session = {}
        self.ends = {}
        self.controls = 0
        self.control_failures = 0
        self.format_versions = set()
        self.stopped = None
        self.lines = {}  # key -> winning mutant line
        for number, line in enumerate(raw.split(b"\n"), 1):
            if not line.strip(b" \t\r\0"):
                continue
            try:
                record = json.loads(line.decode("utf-8"))
            except (UnicodeDecodeError, ValueError):
                self.unparseable.append(number)
                continue
            if not isinstance(record, dict):
                self.unparseable.append(number)
                continue
            self.read(number, record)
        if not self.headers:
            fail(f"{path} has no header line" + (" (only a stopped line)" if self.stopped else ""))
        self.first = self.headers[self.order[0]]
        self.last = self.headers[self.order[-1]]
        self.last_tree = self.tree_of_session.get(self.order[-1], {})
        self.not_covered = []
        self.lists_not_covered = "mutantsNotCovered" in self.last or self.last.get("skipCoverage") is True
        for entry in self.last.get("mutantsNotCovered", []):
            key = (entry["path"], entry["mutationOperatorId"], entry["line"], entry["column"], entry["occurrence"])
            if key not in self.lines:
                self.not_covered.append((key, entry))
        last_end = self.ends.get(self.order[-1])
        self.end_reason = last_end.get("reason") if last_end else None
        self.ended_at = last_end.get("endedAt") if last_end else None
        self.complete = self.end_reason == "finished" and len(self.lines) == self.last.get("mutantsDiscovered")

    def read(self, number, record):
        kind = record.get("kind")
        if kind == "stopped":
            self.stopped = record
            return
        if kind == "header":
            self.read_header(number, record)
            return
        if kind not in ("mutant", "retired", "control", "end"):
            return
        session = record.get("session")
        if session not in self.headers:
            self.skipped_sessions.append(number)
            return
        if kind == "mutant":
            key = (record["path"], record["mutationOperatorId"], record["line"], record["column"],
                   record.get("occurrence", 0))
            self.lines.pop(key, None)  # the last line of a key wins, in file order
            self.lines[key] = record
        elif kind == "retired":
            for item in record.get("keys", []):
                self.lines.pop((item["path"], item["mutationOperatorId"], item["line"], item["column"],
                                item.get("occurrence", 0)), None)
        elif kind == "control":
            self.controls += 1
            self.control_failures += record.get("outcome") != "passed"
        else:
            self.ends[session] = record

    def read_header(self, number, record):
        version = record.get("formatVersion")
        if not isinstance(version, int) or version < 1:
            self.unparseable.append(number)
            return
        if version > NEWEST_FORMAT:
            fail(f"{self.path}: line {number} has formatVersion {version}; this checker reads 1 to {NEWEST_FORMAT}")
        if "project" in record:
            files = dict(record["project"].get("files", {}))
            if tree_hash(files) != record["project"].get("treeSHA256"):
                fail(f"{self.path}: line {number}'s project files don't hash to its treeSHA256")
        elif "projectDelta" in record:
            delta = record["projectDelta"]
            base = self.trees.get(delta.get("baseTreeSHA256"))
            if base is None:
                self.skipped_sessions.append(number)
                return
            files = dict(base)
            files.update(delta.get("files", {}))
            for path in delta.get("removed", []):
                files.pop(path, None)
            if tree_hash(files) != delta.get("treeSHA256"):
                self.skipped_sessions.append(number)
                return
        else:
            files = None
        session = record.get("session")
        if files is not None:
            self.trees[tree_hash(files)] = files
            self.tree_of_session[session] = files
        self.headers[session] = record
        self.order.append(session)
        self.format_versions.add(version)

    def expected_mutants(self):
        """{key: the scan mutant's recorded fields} by the design's rules."""
        out = {}
        for key, line in self.lines.items():
            outcome = line.get("outcome")
            activated = line.get("activated")
            ended_by = line.get("endedBy")
            if outcome == "buildError" or ended_by == "couldNotRun" or line.get("leftOutWithOthers") is True:
                verdict = "buildError"
            elif outcome in ("failed", "runtimeError"):
                verdict = "killed"
            elif outcome == "passed":
                verdict = "noCoverage" if activated is False else "survived"
            elif outcome == "noCoverage":
                verdict = "noCoverage"
            elif outcome == "timeout":
                verdict = "timedOut"
            else:
                verdict = None
            names = [test["name"] for test in line.get("killedBy", [])]
            complete = None
            if "killedBy" in line:
                complete = ended_by == "exited" and line.get("failedTestCount") == len(names)
            snapshot = line.get("snapshot", {})
            out[key] = {
                "verdict": verdict, "outcome": outcome, "activated": activated, "endedBy": ended_by,
                "exitStatus": line.get("exitStatus"), "killedBy": names, "killedByComplete": complete,
                "failedTestCount": line.get("failedTestCount"), "fileSHA256": line.get("fileSHA256"),
                "before": snapshot.get("before"), "after": snapshot.get("after"),
                "description": snapshot.get("description"), "session": line.get("session"),
                "durationSeconds": line.get("durationSeconds"),
                "rerun": (line.get("rerun") or {}).get("because"), "reused": "reusedFrom" in line,
            }
        for key, entry in self.not_covered:
            snapshot = entry.get("snapshot", {})
            out[key] = {
                "verdict": "notCovered", "outcome": None, "activated": None, "endedBy": None, "exitStatus": None,
                "killedBy": [], "killedByComplete": None, "failedTestCount": None,
                "fileSHA256": self.last_tree.get(key[0]), "before": snapshot.get("before"),
                "after": snapshot.get("after"), "description": snapshot.get("description"), "session": None,
                "durationSeconds": None, "rerun": None, "reused": False,
            }
        return out


# --------------------------------------------------------------------------
# Source bytes: which bytes are trivia, and the anchor


class Source:
    """A scanned file's bytes, a byte order mark taken off as SwiftMutator
    counts columns, with each byte marked code or trivia (whitespace and
    comments; a string literal's text is code, its interpolations' trivia
    is not)."""

    def __init__(self, raw):
        self.bom = raw.startswith(BOM)
        self.bytes = raw[len(BOM):] if self.bom else raw
        self.code = bytearray(len(self.bytes))
        self.line_starts = [0]
        data = self.bytes
        index = 0
        while index < len(data):
            byte = data[index]
            if byte == 0x0A or (byte == 0x0D and data[index + 1:index + 2] != b"\n"):
                self.line_starts.append(index + 1)
            index += 1
        position = 0
        if data.startswith(b"#!"):
            end = data.find(b"\n")
            position = len(data) if end < 0 else end
        self.scan(position, None)

    # ---- marking code and trivia

    def scan(self, index, closing_paren):
        """Marks code from `index` until the end, or past the `)` closing an
        interpolation when `closing_paren`; returns where it stopped."""
        data = self.bytes
        depth = 0
        while index < len(data):
            byte = data[index]
            if byte in b" \t\n\r\x0b\x0c\x00":
                index += 1
            elif data.startswith(b"//", index):
                end = data.find(b"\n", index)
                index = len(data) if end < 0 else end
            elif data.startswith(b"/*", index):
                level = 0
                while index < len(data):
                    if data.startswith(b"/*", index):
                        level += 1
                        index += 2
                    elif data.startswith(b"*/", index):
                        level -= 1
                        index += 2
                        if level == 0:
                            break
                    else:
                        index += 1
            elif byte == 0x22 or (byte == 0x23 and self.raw_string_at(index)):
                index = self.string(index)
            else:
                if closing_paren:
                    if byte == 0x28:
                        depth += 1
                    elif byte == 0x29:
                        if depth == 0:
                            self.code[index] = 1
                            return index + 1
                        depth -= 1
                self.code[index] = 1
                index += 1
        return index

    def raw_string_at(self, index):
        data = self.bytes
        end = index
        while end < len(data) and data[end] == 0x23:
            end += 1
        return end < len(data) and data[end] == 0x22

    def string(self, index):
        """Marks a string literal starting at `index` as code (its
        interpolations scanned as code); returns the index past it."""
        data = self.bytes
        start = index
        hashes = 0
        while data[index] == 0x23:
            hashes += 1
            index += 1
        multiline = data.startswith(b'"""', index)
        index += 3 if multiline else 1
        closing = (b'"""' if multiline else b'"') + b"#" * hashes
        escape = b"\\" + b"#" * hashes
        segment = start
        while index < len(data):
            if data.startswith(closing, index):
                index += len(closing)
                break
            if not multiline and data[index] in b"\n\r":
                break
            if data.startswith(escape, index):
                after = index + len(escape)
                if data[after:after + 1] == b"(":
                    for position in range(segment, after + 1):
                        self.code[position] = 1
                    index = self.scan(after + 1, True)
                    segment = index
                    continue
                index = after + 1
                continue
            index += 1
        for position in range(segment, min(index, len(data))):
            self.code[position] = 1
        return index

    # ---- positions

    def offset(self, line, column):
        """The byte offset of SwiftMutator's (line, column), or None when the line doesn't hold it."""
        if line < 1 or line > len(self.line_starts) or column < 1:
            return None
        start = self.line_starts[line - 1]
        end = self.line_starts[line] - 1 if line < len(self.line_starts) else len(self.bytes)
        if line < len(self.line_starts) and self.bytes[end - 1:end + 1] == b"\r\n":
            end -= 1
        offset = start + column - 1
        return offset if offset <= end else None

    def position(self, offset):
        """(line, column) of a byte offset, as records count it: the byte order mark's 3 bytes on line 1."""
        low, high = 0, len(self.line_starts) - 1
        while low < high:
            middle = (low + high + 1) // 2
            if self.line_starts[middle] <= offset:
                low = middle
            else:
                high = middle - 1
        column = offset - self.line_starts[low] + 1
        return (low + 1, column + (len(BOM) if self.bom and low == 0 else 0))

    def next_code(self, offset):
        while offset < len(self.bytes) and not self.code[offset]:
            offset += 1
        return offset if offset < len(self.bytes) else None

    def previous_code(self, offset):
        """The start of the last code character before `offset`."""
        offset = min(offset, len(self.bytes)) - 1
        while offset >= 0 and not self.code[offset]:
            offset -= 1
        if offset < 0:
            return None
        while offset > 0 and self.bytes[offset] & 0xC0 == 0x80 and self.code[offset - 1]:
            offset -= 1
        return offset

    def anchor(self, line, column, operator, after):
        """(anchor offset, how) for SwiftMutator's point, or (None, None) when the file doesn't hold it."""
        point = self.offset(line, column)
        if point is None:
            return None, None
        if point < len(self.bytes) and self.code[point]:
            return point, "point"
        forward = operator in SWAPS and (operator != "RelationalOperatorReplacement" or after not in CONSTANTS)
        following = self.next_code(point)
        previous = self.previous_code(point)
        if forward:
            return (following, "next") if following is not None else (previous, "previous (fallback)")
        return (previous, "previous") if previous is not None else (following, "next (fallback)")

    # ---- the text check

    def token_at(self, offset):
        return first_token(self.bytes[offset:offset + 400].decode("utf-8", "replace"))


def first_token(text):
    """The first token of a code snippet: a word, a run of operator
    characters, a quote, or one punctuation character."""
    if not text:
        return ""
    first = text[0]
    end = 1
    if first in WORD_START or first.isalnum() or ord(first) > 127:
        while end < len(text) and (text[end] in WORD_START or text[end].isalnum() or ord(text[end]) > 127):
            end += 1
    elif first in OPERATOR_CHARACTERS:
        while end < len(text) and text[end] in OPERATOR_CHARACTERS:
            end += 1
    return text[:end]


def end_anchored(operator, after, source, point):
    """Whether SwiftMutator points past the code it changes."""
    if operator == "RemoveSideEffects":
        return True
    if operator in ("RelationalOperatorReplacement", "ReplaceBooleanValue"):
        return after == "false"
    if operator == "SwapTernary":
        # A chain's later link points at its own `?`; the first link (or a
        # lone ternary) past the whole expression, which may be the start of
        # the token after it when no trivia follows.
        return not later_link(source, point)
    return False


def later_link(source, point):
    """Whether a SwapTernary point is on a `?`: a later link of a chain."""
    return point < len(source.bytes) and source.code[point] and source.token_at(point) == "?"


# --------------------------------------------------------------------------
# The scan, the package and the placement


class Package:
    """The scan JSON and the package's files."""

    def __init__(self, root, scan_path):
        self.root = os.path.abspath(root)
        with open(scan_path) as handle:
            self.scan = json.load(handle)
        self.mutation = self.scan.get("mutation")
        if self.mutation is None:
            fail(f"{scan_path} has no mutation block; run `swiftstats scan --mutation --format json`")
        self.records = [r for r in self.scan["records"] if r["role"] == "production"]
        self.records_by_file = defaultdict(list)
        for record in self.records:
            self.records_by_file[record["file"]].append(record)
        self.record_by_key = {r["key"]: r for r in self.records}
        self.types_by_file = defaultdict(list)
        for record in self.scan.get("types", []):
            self.types_by_file[record["file"]].append(record)
        self.files = {f["path"]: f for f in self.scan["files"]}
        self.spellings = {nfc(path): path for path in self.files}
        configuration = self.scan.get("configuration", {})
        self.excluded_files = set(configuration.get("excludedFiles", []))
        self.excluded_globs = [COVERAGE_CHECK.glob_regex(p) for p in configuration.get("excluded", [])]
        self.targets = sorted(
            ((COVERAGE_CHECK.Package.directory(t["path"]), t) for t in self.scan["targets"]),
            key=lambda pair: (-len(pair[0]), pair[0]),
        )
        self.sources = {}
        self.texts = {}
        self.statement_cache = {}
        self.scoped_cache = {}

    def raw(self, path):
        with open(os.path.join(self.root, path), "rb") as handle:
            return handle.read()

    def source(self, path):
        if path not in self.sources:
            self.sources[path] = Source(self.raw(path))
        return self.sources[path]

    def text(self, path):
        if path not in self.texts:
            self.texts[path] = self.raw(path).decode("utf-8", "replace")
        return self.texts[path]

    def statement_lines(self, path):
        if path not in self.statement_cache:
            self.statement_cache[path] = COVERAGE_CHECK.statement_lines(self.text(path))
        return self.statement_cache[path]

    def type_owner(self, record):
        owner = f"{record['module']}::{record['name']}"
        if record.get("isLocal"):
            return owner
        path = record["file"]
        if path not in self.scoped_cache:
            self.scoped_cache[path] = COVERAGE_CHECK.file_scoped_paths(self.types_by_file[path], self.text(path))
        return owner + " @ " + path if COVERAGE_CHECK.is_file_scoped(record["name"], self.scoped_cache[path]) else owner

    def classify(self, path):
        """(class, the scan's spelling of a kept or unmapped path, reason) of a mutant's path."""
        while path.startswith("./"):
            path = path[2:]
        normal = nfc(path)
        if ".build" in normal.split("/"):
            return ("build", None, None)
        if normal.startswith("/") or normal == ".." or normal.startswith("../"):
            return ("outsideRoot", None, None)
        spelled = self.spellings.get(normal, normal)
        target = next((t for prefix, t in self.targets if spelled.startswith(prefix)), None)
        if target is not None and target["isTest"]:
            return ("testFiles", None, None)
        if not spelled.endswith(".swift"):
            return ("otherLanguage", None, None)
        if target is None:
            return ("otherPackage", None, None)
        if spelled in self.files:
            return ("kept", spelled, None)
        excluded = spelled in self.excluded_files or any(g.match(spelled) for g in self.excluded_globs)
        return ("unmapped", spelled, EXCLUDED if excluded else NOT_PARSED)

    def production_paths(self):
        return {t["name"]: t for _, t in self.targets if not t["isTest"]}


def position(point):
    return (point["line"], point["column"])


def innermost(items, name):
    """Of items holding a position, the one starting last, then ending first, then first by name."""
    return min(items, key=lambda r: ((-r["range"]["start"]["line"], -r["range"]["start"]["column"]),
                                     position(r["range"]["end"]), r[name]))


class Placement:
    """Every mutant classified, gated, anchored and placed by the design's rules."""

    def __init__(self, package, expected):
        self.package = package
        self.places = {}  # key -> {"place", "owner", "reason", "anchor"}
        self.how = defaultdict(int)  # how anchors were found
        self.hashes = {}
        self.stale = []  # kept files whose bytes aren't the ones the scan hashed
        for key in sorted(expected):
            self.places[key] = self.place(key, expected[key])

    def file_hash(self, path):
        """The SHA-256 of a kept file's bytes on disk, which must be the scan's."""
        if path not in self.hashes:
            self.hashes[path] = sha256(self.package.raw(path))
            if self.hashes[path] != self.package.files[path].get("sha256"):
                self.stale.append(f"{path}: {self.hashes[path]} on disk / scan {self.package.files[path].get('sha256')}")
        return self.hashes[path]

    def place(self, key, mutant):
        path, operator, line, column, _ = key
        kind, spelled, reason = self.package.classify(path)
        if kind == "unmapped":
            return {"place": "unmapped", "owner": None, "reason": reason, "anchor": None}
        if kind != "kept":
            return {"place": "dropped", "owner": None, "reason": kind, "anchor": None}
        hash_value = mutant["fileSHA256"]
        if hash_value is None:
            return {"place": "unmapped", "owner": None, "reason": NO_FILE_HASH, "anchor": None}
        if hash_value.startswith(LINK_PREFIX):
            return {"place": "unmapped", "owner": None, "reason": SYMLINK, "anchor": None}
        if hash_value != self.file_hash(spelled):
            return {"place": "unmapped", "owner": None, "reason": FILE_CHANGED, "anchor": None}
        source = self.package.source(spelled)
        offset, how = source.anchor(line, column, operator, mutant["after"])
        if offset is None:
            return {"place": "unmapped", "owner": None, "reason": NO_SUCH_POSITION, "anchor": None}
        self.how[how] += 1
        anchor = source.position(offset)
        statements = None
        holding = []
        for record in self.package.records_by_file[spelled]:
            if not position(record["range"]["start"]) <= anchor <= position(record["range"]["end"]):
                continue
            if record["kind"] == "topLevel":
                statements = statements if statements is not None else self.package.statement_lines(spelled)
                if anchor[0] not in statements:
                    continue
            holding.append(record)
        point = {"line": anchor[0], "column": anchor[1]}
        if holding:
            return {"place": "record", "owner": innermost(holding, "key")["key"], "reason": None, "anchor": point}
        types = [t for t in self.package.types_by_file[spelled]
                 if position(t["range"]["start"]) <= anchor <= position(t["range"]["end"])]
        if types:
            owner = self.package.type_owner(innermost(types, "name"))
            return {"place": "type", "owner": owner, "reason": None, "anchor": point}
        return {"place": "file", "owner": spelled, "reason": None, "anchor": point}


# --------------------------------------------------------------------------
# SwiftMutator's report


def make_report(mutator, results_path, directory):
    output = os.path.join(directory, "report.json")
    command = [mutator, "report", results_path, "-f", "json", "-o", output]
    result = subprocess.run(command, cwd=directory, capture_output=True, text=True,
                            env=dict(os.environ, NO_COLOR="1"), stdin=subprocess.DEVNULL)
    if result.returncode not in (0, 2):
        fail(f"swift-mutator report exited {result.returncode}:\n{(result.stdout + result.stderr)[-2000:]}")
    return output


class Report:
    """SwiftMutator's JSON report: entries by their parsed key."""

    def __init__(self, path):
        with open(path) as handle:
            self.document = json.load(handle)
        self.entries = {}
        self.duplicates = []
        self.unparsed = []
        self.keyless = []  # (path, outcome) of placeholder entries
        self.file_scores = {}  # relative path -> mutationScore, for files with keyed entries
        self.inconsistent = []
        for report in self.document.get("fileReports", []):
            keyed = False
            for entry in report.get("appliedOperators", []):
                text = entry.get("key")
                if text is None:
                    self.keyless.append((report.get("path"), entry.get("testSuiteOutcome")))
                    continue
                key = parse_report_key(text)
                if key is None:
                    self.unparsed.append(text)
                    continue
                keyed = True
                point = entry.get("mutationPoint", {})
                spot = point.get("position", {})
                if (entry.get("path"), point.get("mutationOperatorId"), spot.get("line"), spot.get("column")) \
                        != key[:4]:
                    self.inconsistent.append(f"{text}: path, operator or position fields disagree with the key")
                if key in self.entries:
                    self.duplicates.append(text)
                self.entries[key] = entry
            if keyed:
                self.file_scores[report.get("path")] = report.get("mutationScore")
        self.summary = self.document.get("killingTestSummary")
        self.suspects_checked = None if self.summary is None else self.summary.get("suspectsChecked") is True


# --------------------------------------------------------------------------
# Figures from the report's outcomes over this script's placement


def zero_counts():
    return {field: 0 for field in COUNT_FIELDS}


def add(counts, verdict, crash, flag):
    if verdict == "buildError":
        counts["buildErrors"] += 1
    else:
        counts[verdict] += 1
    if crash:
        counts["crashKills"] += 1
    if flag is True:
        counts["suspectOnly"] += 1
    if verdict == "killed" and not crash and flag is not None:
        counts["judgedKills"] += 1


class Figures:
    """Counts per record, attachment, module and project, from the report's
    outcomes (and the header's not-covered entries) over the placement."""

    def __init__(self, package, results, report, placement):
        self.records = defaultdict(lambda: {"counts": zero_counts(), "tests": set()})
        self.attachments = defaultdict(lambda: {"counts": zero_counts(), "tests": set()})
        self.every = zero_counts()
        self.dropped = {name: 0 for name in DROPPED_CLASSES}
        self.unmapped = defaultdict(int)
        self.rows_by_file = defaultdict(list)  # path -> verdicts, for SwiftMutator's file scores
        self.flags = {}
        not_covered = {key for key, _ in results.not_covered}
        for key, place in placement.places.items():
            entry = report.entries.get(key)
            if key in not_covered:
                verdict, crash, flag, tests = "notCovered", False, None, []
            elif entry is None:
                continue  # listed as a missing report entry in b
            else:
                outcome = entry.get("testSuiteOutcome")
                verdict = REPORT_VERDICTS.get(outcome)
                crash = outcome == "runtimeError"
                flag = None
                if outcome == "failed":
                    flag = True if entry.get("killedOnlyBySuspectTests") is True else (
                        False if report.suspects_checked else None)
                tests = [t["name"] for t in (entry.get("killingTests") or {}).get("tests", [])] \
                    if verdict == "killed" else []
            self.flags[key] = flag
            self.rows_by_file[key[0]].append(verdict)
            add(self.every, verdict, crash, flag)
            if place["place"] == "dropped":
                self.dropped[place["reason"]] += 1
                continue
            if place["place"] == "unmapped":
                self.unmapped[place["reason"]] += 1
                continue
            target = self.records[place["owner"]] if place["place"] == "record" \
                else self.attachments[(place["place"], place["owner"])]
            add(target["counts"], verdict, crash, flag)
            target["tests"].update(tests)
        self.package = package
        self.results = results
        self.placement = placement

    def module_of(self, place, owner, file_modules):
        if place == "record":
            return self.package.record_by_key[owner]["module"]
        if place == "type":
            return owner.split("::", 1)[0]
        return file_modules.get(owner)

    def rollups(self):
        """{("module", name) or ("project", "production"): the expected mutation roll-up}."""
        package = self.package
        production = {name for name, target in package.production_paths().items()}
        file_modules = {}
        for _, target in package.targets:
            for path in target.get("files", []):
                file_modules.setdefault(path, target["name"])
        modules = {name: zero_counts() for name in production}
        project = zero_counts()
        for kind, table in (("record", self.records), ("attachment", self.attachments)):
            for owner, value in table.items():
                if kind == "record":
                    module = self.module_of("record", owner, file_modules)
                else:
                    module = self.module_of(owner[0], owner[1], file_modules)
                if module not in modules:
                    continue
                for field in COUNT_FIELDS:
                    modules[module][field] += value["counts"][field]
                    project[field] += value["counts"][field]
        dispositions = {nfc(f["path"]): f["disposition"] for f in package.mutation.get("files", [])}
        generated = {path for path, f in package.files.items() if f.get("generated")}
        functions = {name: defaultdict(int) for name in modules}
        project_functions = defaultdict(int)
        for record in package.records:
            if record["module"] not in modules or record["file"] in generated:
                continue
            state = function_state(self.records.get(record["key"], {}).get("counts"),
                                   dispositions.get(nfc(record["file"])))
            functions[record["module"]][state] += 1
            project_functions[state] += 1
        complete = self.results.complete
        out = {}
        for name, counts in modules.items():
            out[("module", name)] = rollup(counts, functions[name], complete)
        out[("project", "production")] = rollup(project, project_functions, complete)
        out[("project", "production")]["unmapped"] = sum(self.unmapped.values())
        out[("project", "production")]["dropped"] = sum(self.dropped.values())
        return out


def function_state(counts, disposition):
    if disposition == "unresolved":
        return "noResults"
    if disposition == "unlisted":
        return "notListed"
    if counts is None:
        return "noMutant"
    if counts["killed"] + counts["survived"] + counts["noCoverage"] + counts["timedOut"] > 0:
        return "scored"
    if counts["notCovered"] > 0:
        return "notCoveredOnly"
    if counts["buildErrors"] > 0:
        return "buildErrorsOnly"
    return "noMutant"


def rollup(counts, functions, complete):
    scored = counts["killed"] + counts["survived"] + counts["noCoverage"] + counts["timedOut"]
    score = {"killed": counts["killed"], "scored": scored}
    value = percent(counts["killed"], scored)
    if value is not None and complete:
        score["percent"] = value
    item = dict(counts)
    item["carried"] = 0
    item["score"] = score
    item["functions"] = {state: functions.get(state, 0) for state in
                         ("buildErrorsOnly", "noMutant", "noResults", "notCoveredOnly", "notListed", "scored")}
    return item


# --------------------------------------------------------------------------
# The checks


class Checker:
    def __init__(self, show_all):
        self.limit = None if show_all else LIMIT
        self.failures = []
        self.current = ""

    def section(self, title):
        print(f"\n== {title}")
        self.current = title.split()[0]

    def result(self, name, ok, detail=""):
        print(f"{'PASS' if ok else 'FAIL'} {name}{': ' + detail if detail else ''}")
        if not ok:
            self.failures.append(f"{self.current} {name}")

    def listing(self, items):
        shown = items if self.limit is None else items[: self.limit]
        for item in shown:
            print(f"    {item}")
        if len(shown) < len(items):
            print(f"    … {len(items) - len(shown)} more (--all lists them)")

    # a
    def reader(self, package, results, expected, scanned):
        self.section("a   own reader of results.jsonl equals the scan's mutants")
        mutation = package.mutation
        print(f"    {len(results.headers)} sessions, formats {sorted(results.format_versions)}, "
              f"{len(results.lines)} tested keys, {len(results.not_covered)} not covered, "
              f"{results.controls} control runs ({results.control_failures} failed), "
              f"{len(results.unparseable)} unparseable lines, {len(results.skipped_sessions)} lines of unread sessions")
        missing = sorted(set(expected) - set(scanned))
        extra = sorted(set(scanned) - set(expected))
        self.result("key set", not missing and not extra,
                    f"{len(expected)} keys read, {len(scanned)} in the scan, {len(missing)} missing, {len(extra)} extra")
        self.listing([f"missing from the scan: {key_text(k)}" for k in missing]
                     + [f"only in the scan: {key_text(k)}" for k in extra])
        differences = []
        verdicts = defaultdict(int)
        for key in sorted(set(expected) & set(scanned)):
            mine, theirs = expected[key], scanned[key]
            verdicts[mine["verdict"]] += 1
            for field, value in mine.items():
                if theirs.get(field) != value and not (field == "killedBy" and value == [] and field not in theirs):
                    differences.append(f"{key_text(key)}: {field} {value!r} / scan {theirs.get(field)!r}")
            for field in ("run", "carried"):
                wanted = 0 if field == "run" else False
                if theirs.get(field) != wanted:
                    differences.append(f"{key_text(key)}: {field} {theirs.get(field)!r}, expected {wanted!r}")
        self.result("verdicts and fields", not differences,
                    f"{dict(sorted(verdicts.items()))}, {len(differences)} differences")
        self.listing(differences)
        order = [mutant_key(m) for m in mutation["mutants"]]
        self.result("mutant order", order == sorted(order, key=lambda k: (k[0], k[2], k[3], k[1], k[4])))

        facts = []
        runs = mutation.get("runs", [])
        if len(runs) != 1:
            facts.append(f"{len(runs)} runs; base mode checks one full run")
        run = runs[0] if runs else {}
        first, last = results.first, results.last
        provenance = first.get("provenance", {}).get("swiftMutator", {})
        wanted = {
            "complete": (mutation.get("complete"), results.complete),
            "listsNotCovered": (mutation.get("listsNotCovered"), results.lists_not_covered),
            "mode": (mutation.get("mode"), "full"),
            "run mode": (run.get("mode"), "since" if "since" in first else "full"),
            "base": (mutation.get("base"), None),
            "identity": (run.get("identity"), "sha256:" + provenance.get("executableSHA256", "")),
            "version": (run.get("version"), provenance.get("version")),
            "startedAt": (run.get("startedAt"), first.get("startedAt")),
            "collectedAt": (mutation.get("collectedAt"), first.get("startedAt")),
            "endedAt": (run.get("endedAt"), results.ended_at),
            "endReason": (run.get("endReason"), results.end_reason),
            "sessions": (run.get("sessions"), len(results.headers)),
            "resultsSHA256": (run.get("resultsSHA256"), results.sha256),
            "formatVersions": (run.get("formatVersions"), sorted(results.format_versions)),
            "operators": (run.get("operators"), sorted(first.get("operators", []))),
            "skipCoverage": (run.get("skipCoverage"), first.get("skipCoverage")),
            "run listsNotCovered": (run.get("listsNotCovered"), results.lists_not_covered),
            "workers": (run.get("workers"), last.get("workers")),
            "timeoutSeconds": (run.get("timeoutSeconds"), last.get("timeoutSeconds")),
            "stopsAtFirstFailure": (run.get("stopsAtFirstFailure"), last.get("stopsAtFirstFailure")),
            "mutantsDiscovered": (run.get("mutantsDiscovered"), last.get("mutantsDiscovered")),
            "mutantsDropped": (run.get("mutantsDropped"), last.get("mutantsDropped")),
            "controlRuns": (run.get("controlRuns"), results.controls),
            "controlFailures": (run.get("controlFailures"), results.control_failures),
            "toolchain": (run.get("toolchain"), (first.get("provenance", {}).get("toolchain", {})
                                                 .get("testCommandVersion") or "").split("\n")[0] or None),
        }
        for name, (theirs, mine) in wanted.items():
            if theirs != mine:
                facts.append(f"{name}: scan {theirs!r} / results {mine!r}")
        self.result("run facts", not facts, f"{len(wanted)} facts, complete {results.complete}, "
                    f"ended {results.end_reason}, {len(results.lines)} of {last.get('mutantsDiscovered')} discovered")
        self.listing(facts)

        tree = []
        expected_files = []
        for path in sorted(p for p in results.last_tree if p.endswith(".swift")):
            kind = package.classify(path)[0]
            production = kind in ("kept", "unmapped")
            item = {"changedTest": False, "disposition": "tested" if production else "untested", "path": path,
                    "sha256": results.last_tree[path]}
            if production:
                item["run"] = 0
            expected_files.append(item)
        if mutation.get("files") != expected_files:
            theirs = {f["path"]: f for f in mutation.get("files", [])}
            mine = {f["path"]: f for f in expected_files}
            for path in sorted(set(theirs) | set(mine)):
                if theirs.get(path) != mine.get(path):
                    tree.append(f"{path}: scan {theirs.get(path)} / expected {mine.get(path)}")
            if not tree:
                tree.append("same files in another order")
        self.result("tree", not tree, f"{len(expected_files)} Swift paths in the last header's tree")
        self.listing(tree)

    # b
    def report(self, package, results, expected, report):
        self.section("b   verdicts equal SwiftMutator's JSON report")
        tested = {k: v for k, v in expected.items() if v["verdict"] != "notCovered"}
        problems = [f"unparsed key {text!r}" for text in report.unparsed] \
            + [f"duplicate key {text!r}" for text in report.duplicates] + report.inconsistent
        missing = sorted(set(tested) - set(report.entries))
        extra = sorted(set(report.entries) - set(tested))
        problems += [f"no report entry: {key_text(k)}" for k in missing]
        problems += [f"report entry not in the results: {key_text(k)}" for k in extra]
        self.result("keys one to one", not problems,
                    f"{len(report.entries)} keyed entries, {len(tested)} tested mutants, "
                    f"{len(report.keyless)} keyless placeholders skipped")
        self.listing(problems)
        differences = []
        for key in sorted(set(tested) & set(report.entries)):
            outcome = report.entries[key].get("testSuiteOutcome")
            verdict = REPORT_VERDICTS.get(outcome)
            mine = tested[key]
            if verdict != mine["verdict"]:
                differences.append(f"{key_text(key)}: report {outcome} / scan verdict {mine['verdict']}")
            elif (outcome == "runtimeError") != (mine["outcome"] == "runtimeError"):
                differences.append(f"{key_text(key)}: report {outcome} / results outcome {mine['outcome']}")
        self.result("verdicts", not differences, f"{len(set(tested) & set(report.entries))} compared")
        self.listing(differences)

        every = package.mutation.get("everyMutant", {})
        by_outcome = report.document.get("mutantsByOutcome", {})
        pairs = {"killed": "killed", "survived": "survived", "notCovered": "noCoverage", "timedOut": "timedOut",
                 "buildErrors": "buildErrors"}
        totals = [f"{theirs}: report {by_outcome.get(theirs)} / scan {every.get(mine)}"
                  for theirs, mine in pairs.items() if by_outcome.get(theirs) != every.get(mine)]
        self.result("mutantsByOutcome", not totals, json.dumps(by_outcome, sort_keys=True))
        self.listing(totals)
        scored = sum(every.get(f, 0) for f in ("killed", "survived", "noCoverage", "timedOut"))
        tested_rows = scored + every.get("buildErrors", 0)
        mine = -1 if tested_rows == 0 else (truncated(every.get("killed", 0), scored) or 0)
        self.result("globalMutationScore", report.document.get("globalMutationScore") == mine,
                    f"report {report.document.get('globalMutationScore')} / scan everyMutant {mine}")

        rows = defaultdict(list)
        for mutant in package.mutation["mutants"]:
            rows[mutant["path"]].append(mutant["verdict"])
        files = []
        for path, score in sorted(report.file_scores.items()):
            verdicts = rows.get(path, [])
            killed = verdicts.count("killed")
            file_scored = sum(1 for v in verdicts if v in ("killed", "survived", "noCoverage", "timedOut"))
            ours = truncated(killed, file_scored)
            theirs = None if score == 0 and file_scored == 0 else score
            if score == -1:
                theirs = None
            if ours != theirs:
                files.append(f"{path}: report {score} / scan rows {ours} ({killed} of {file_scored})")
        placeholders = []
        for path, outcome in report.keyless:
            relative = path
            for prefix in (results.first.get("mutatedProjectPath", ""), results.first.get("projectPath", "")):
                if prefix and path and path.startswith(prefix.rstrip("/") + "/"):
                    relative = path[len(prefix.rstrip("/")) + 1:]
            verdicts = rows.get(relative, [])
            if any(v != "notCovered" for v in verdicts):
                placeholders.append(f"{relative}: a placeholder ({outcome}) for a file whose scan rows are {verdicts}")
        self.result("file scores", not files and not placeholders,
                    f"{len(report.file_scores)} keyed files, {len(report.keyless)} placeholders "
                    f"({', '.join(sorted({str(p) for p, _ in report.keyless})) or 'none'})")
        self.listing(files + placeholders)

    # c
    def suspects(self, package, scanned, report, figures):
        self.section("c   suspect-only flags follow the report's tri-state")
        differences = []
        counts = defaultdict(int)
        for key, flag in sorted(figures.flags.items()):
            counts[repr(flag)] += 1
            if key in scanned and scanned[key].get("suspectOnly") != flag:
                differences.append(f"{key_text(key)}: report says {flag!r} / scan {scanned[key].get('suspectOnly')!r}")
        for key, entry in sorted(report.entries.items()):
            if entry.get("killedOnlyBySuspectTests") is not None and entry.get("testSuiteOutcome") != "failed":
                differences.append(f"{key_text(key)}: flagged but its outcome is {entry.get('testSuiteOutcome')}")
        self.result("flags", not differences,
                    f"suspectsChecked {report.suspects_checked}, flags {dict(sorted(counts.items()))}")
        self.listing(differences)
        runs = package.mutation.get("runs", [])
        judged = runs[0].get("suspectsJudged") if runs else None
        self.result("suspectsJudged", judged == report.suspects_checked,
                    f"scan {judged!r} / report {report.suspects_checked!r}")

    # d
    def placement(self, package, expected, scanned, placement):
        self.section("d   own placement equals the scan's anchors, places and owners")
        differences = []
        places = defaultdict(int)
        for key, mine in sorted(placement.places.items()):
            places[mine["place"]] += 1
            theirs = scanned.get(key)
            if theirs is None:
                continue
            for field in ("place", "owner", "reason", "anchor"):
                if theirs.get(field) != mine[field]:
                    differences.append(f"{key_text(key)}: {field} {mine[field]!r} / scan {theirs.get(field)!r}")
        self.result("scanned bytes", not placement.stale,
                    f"{len(placement.hashes)} kept files with mutants hash as the scan's files[].sha256")
        self.listing(placement.stale)
        self.result("placement", not differences,
                    f"{dict(sorted(places.items()))}; anchors by {dict(sorted(placement.how.items()))}; "
                    f"{len(differences)} differences")
        self.listing(differences)

        texts = []
        on_next = []
        checked = defaultdict(int)
        skipped = 0
        for key, mutant in sorted(expected.items()):
            path, operator, line, column, _ = key
            kind, spelled, _ = package.classify(path)
            local = spelled or path
            if kind == "outsideRoot" or not os.path.isfile(os.path.join(package.root, local)):
                skipped += 1
                continue
            raw = package.raw(local)
            if mutant["fileSHA256"] != sha256(raw):
                skipped += 1
                continue
            source = package.source(local)
            point = source.offset(line, column)
            before = (mutant["before"] or "").strip()
            if point is None or not before:
                texts.append(f"{key_text(key)}: no such point, or an empty `before`")
                continue
            if end_anchored(operator, mutant["after"], source, point):
                checked["end"] += 1
                last = source.previous_code(point)
                found = source.bytes[last:point].decode("utf-8", "replace") if last is not None else ""
                character = found[:1]
                if character != before[-1]:
                    texts.append(f"{key_text(key)}: last code character before the point {character!r}, "
                                 f"`before` ends {before[-1]!r} ({before[-40:]!r})")
                if point < len(source.bytes) and source.code[point]:
                    on_next.append(f"{key_text(key)}: the point is the start of {source.token_at(point)!r}")
            elif operator == "SwapTernary":
                checked["later link"] += 1
                if " ? " not in f" {before} ":
                    texts.append(f"{key_text(key)}: a later link's point is a `?`, but `before` holds none "
                                 f"({before[:40]!r})")
            else:
                checked["start"] += 1
                start = point
                if operator in SWAPS and not (point < len(source.bytes) and source.code[point]):
                    start = source.next_code(point)
                    checked["start past trivia"] += 1
                token = source.token_at(start) if start is not None else ""
                if token != first_token(before):
                    texts.append(f"{key_text(key)}: token at the point {token!r}, "
                                 f"`before` starts {first_token(before)!r} ({before[:40]!r})")
        self.result("column-exact text", not texts,
                    f"{dict(sorted(checked.items()))}, {skipped} not checked (no matching file under the root)")
        self.listing(texts)
        if on_next:
            print(f"    {len(on_next)} end-anchored points start the next token, which the design's rule makes their "
                  "anchor (information):")
            self.listing(on_next)

    # e
    def figures(self, package, figures):
        self.section("e   counts from the report's outcomes equal the records, attachments and roll-ups")
        mutation = package.mutation
        differences = []
        theirs = {r["key"]: r for r in mutation.get("records", [])}
        for key in sorted(set(theirs) | set(figures.records)):
            mine = figures.records.get(key)
            scan = theirs.get(key)
            if mine is None or scan is None:
                differences.append(f"{key}: {'only in the scan' if mine is None else 'missing from the scan'}")
                continue
            for field in COUNT_FIELDS:
                if scan.get(field) != mine["counts"][field]:
                    differences.append(f"{key}: {field} {mine['counts'][field]} / scan {scan.get(field)}")
            if scan.get("killingTests") != sorted(mine["tests"]):
                differences.append(f"{key}: killingTests {sorted(mine['tests'])} / scan {scan.get('killingTests')}")
        order = [r["key"] for r in mutation.get("records", [])]
        self.result("records", not differences and order == sorted(order),
                    f"{len(figures.records)} records with mutants, {len(differences)} differences"
                    + ("" if order == sorted(order) else ", not sorted by key"))
        self.listing(differences)

        differences = []
        theirs = {(a["attachedTo"], a["owner"]): a for a in mutation.get("attachments", [])}
        for key in sorted(set(theirs) | set(figures.attachments)):
            mine = figures.attachments.get(key)
            scan = theirs.get(key)
            if mine is None or scan is None:
                differences.append(f"{key}: {'only in the scan' if mine is None else 'missing from the scan'}")
                continue
            for field in COUNT_FIELDS:
                if scan.get(field) != mine["counts"][field]:
                    differences.append(f"{key}: {field} {mine['counts'][field]} / scan {scan.get(field)}")
        self.result("attachments", not differences, f"{len(figures.attachments)} attachments")
        self.listing(differences)

        every = dict(figures.every)
        every["dropped"] = sum(figures.dropped.values())
        every["unmapped"] = sum(figures.unmapped.values())
        totals = []
        if mutation.get("everyMutant") != every:
            totals.append(f"everyMutant {json.dumps(every, sort_keys=True)} / scan "
                          f"{json.dumps(mutation.get('everyMutant'), sort_keys=True)}")
        if mutation.get("dropped") != figures.dropped:
            totals.append(f"dropped {figures.dropped} / scan {mutation.get('dropped')}")
        if mutation.get("unmapped", {}) != dict(figures.unmapped):
            totals.append(f"unmapped {dict(figures.unmapped)} / scan {mutation.get('unmapped')}")
        self.result("totals", not totals, f"everyMutant {json.dumps(every, sort_keys=True)}")
        self.listing(totals)

        differences = []
        scan_rollups = {(r["scope"], r["name"]): r for r in package.scan.get("rollups", [])}
        expected = figures.rollups()
        for key in sorted(set(scan_rollups) | set(expected)):
            scan = scan_rollups.get(key, {}).get("mutation")
            mine = expected.get(key)
            if scan != mine:
                differences.append(f"{key}: {json.dumps(mine, sort_keys=True)} / scan {json.dumps(scan, sort_keys=True)}")
        shown = ", ".join(f"{name} {value['score']['killed']}/{value['score']['scored']}"
                          f" = {value['score'].get('percent')}" for (_, name), value in sorted(expected.items()))
        self.result("roll-ups", not differences, shown)
        self.listing(differences)

    # f
    def not_covered(self, results, scanned, placement):
        self.section("f   not-covered rows are the header's entries less the tested keys")
        listed = results.last.get("mutantsNotCovered", [])
        keys = {key for key, _ in results.not_covered}
        rows = {key for key, mutant in scanned.items() if mutant.get("verdict") == "notCovered"}
        tested_again = len(listed) - len(results.not_covered)
        places = defaultdict(int)
        for key in keys:
            places[placement.places[key]["place"]] += 1
        self.result("not covered", keys == rows,
                    f"{len(listed)} listed in the last header, {tested_again} tested anyway, {len(rows)} rows; "
                    f"placed {dict(sorted(places.items()))}")
        self.listing([f"{'only in the scan' if k in rows else 'missing from the scan'}: {key_text(k)}"
                      for k in sorted(keys ^ rows)])

    def share(self, placement):
        self.section("3   mapped share (information)")
        in_records = sum(1 for p in placement.places.values() if p["place"] == "record")
        attached = sum(1 for p in placement.places.values() if p["place"] in ("type", "file"))
        unmapped_kept = [p for p in placement.places.values()
                         if p["place"] == "unmapped" and p["reason"] not in (EXCLUDED, NOT_PARSED)]
        denominator = in_records + len(unmapped_kept)
        share = in_records / denominator if denominator else 1.0
        print(f"    {in_records} of {denominator} mutants of kept files mapped to records ({share:.2%}); "
              f"{attached} attached; {len(placement.places) - in_records - attached - len(unmapped_kept)} "
              "dropped or in unscanned files")

    # g
    def stored(self, package, store_path):
        self.section("g   stored rows equal the scan's mutation block")
        mutation = package.mutation
        # The scan's own commit is its fresh run's: in a merged result the
        # carried runs name the base, so take the last run not carried.
        fresh = [entry for entry in mutation["runs"] if entry.get("carriedFrom") is None]
        run = (fresh or mutation["runs"])[-1]
        name = package.scan["package"]
        prefix = subprocess.run(["git", "rev-parse", "--show-prefix"], cwd=package.root,
                                capture_output=True, text=True).stdout.strip()
        package_path = prefix[:-1] if prefix.endswith("/") else prefix
        database = sqlite3.connect(f"file:{os.path.abspath(store_path)}?mode=ro", uri=True)
        database.row_factory = sqlite3.Row
        found = database.execute(
            "SELECT id FROM snapshot WHERE package = ? AND packagePath = ? AND ifnull(commitHash, '') = ? "
            "AND isDirty = ? ORDER BY id DESC LIMIT 1",
            (name, package_path, run.get("commit") or "", 1 if run["dirty"] else 0),
        ).fetchone()
        if found is None:
            self.result("snapshot found", False,
                        f"no snapshot of {name} at '{package_path}' of {run.get('commit')}")
            return
        snapshot = found["id"]
        print(f"    snapshot {snapshot} of {name} at '{package_path}' of {run.get('commit')} "
              f"in {os.path.realpath(store_path)}")
        version = database.execute("PRAGMA user_version").fetchone()[0]
        self.result("store version", version == 5, f"user_version {version}")

        def rows(table, order):
            return [dict(row) for row in database.execute(
                f'SELECT * FROM "{table}" WHERE snapshotId = ? ORDER BY {order}', (snapshot,))]

        def compare(name, stored_rows, expected_rows):
            differences = []
            if len(stored_rows) != len(expected_rows):
                differences.append(f"{len(stored_rows)} rows stored, {len(expected_rows)} in the scan")
            for index, (got, want) in enumerate(zip(stored_rows, expected_rows)):
                for column in sorted(set(got) | set(want)):
                    if got.get(column) != want.get(column):
                        differences.append(f"row {index} {column}: stored {got.get(column)!r}, "
                                           f"scan {want.get(column)!r}")
            self.result(name, not differences, f"{len(stored_rows)} rows")
            self.listing(differences)

        def flag(value):
            return None if value is None else (1 if value else 0)

        def text(value):
            return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)

        base = mutation.get("base") or {}
        compare("mutationScan", [{k: v for k, v in row.items() if k != "snapshotId"}
                                 for row in rows("mutationScan", "snapshotId")], [{
            "collectedAt": mutation["collectedAt"], "complete": flag(mutation["complete"]),
            "listsNotCovered": flag(mutation["listsNotCovered"]), "mode": mutation["mode"],
            "baseCommit": base.get("commit"), "baseCollectedAt": base.get("collectedAt"),
        }])

        def run_row(entry):
            since = entry.get("since") or {}
            carried = entry.get("carriedFrom") or {}
            row = {key: entry.get(key) for key in (
                "ordinal", "identity", "version", "startedAt", "endedAt", "endReason", "commit", "mode",
                "sessions", "resultsFile", "resultsSHA256", "workers", "timeoutSeconds", "mutantsDiscovered",
                "mutantsDropped", "controlRuns", "controlFailures", "toolchain", "testExecutableSHA256",
                "sdkEnvironment")}
            row.update({
                "dirty": flag(entry["dirty"]), "skipCoverage": flag(entry["skipCoverage"]),
                "listsNotCovered": flag(entry["listsNotCovered"]),
                "stopsAtFirstFailure": flag(entry["stopsAtFirstFailure"]),
                "suspectsJudged": flag(entry.get("suspectsJudged")),
                "formatVersions": text(entry["formatVersions"]), "operators": text(entry["operators"]),
                "sinceRef": since.get("ref"), "sinceCommit": since.get("commit"), "mergeBase": since.get("mergeBase"),
                "carriedFrom": carried.get("commit"), "carriedFromCollectedAt": carried.get("collectedAt"),
            })
            return row

        def strip(stored_rows):
            return [{k: v for k, v in row.items() if k != "snapshotId"} for row in stored_rows]

        compare("mutationRun", strip(rows("mutationRun", "ordinal")), [run_row(entry) for entry in mutation["runs"]])
        compare("mutationFile", strip(rows("mutationFile", "path")), sorted((
            {"path": entry["path"], "sha256": entry.get("sha256"), "disposition": entry["disposition"],
             "changedTest": flag(entry["changedTest"]), "run": entry.get("run")}
            for entry in mutation["files"]), key=lambda row: row["path"].encode()))
        compare("mutationSuspect", strip(rows("mutationSuspect", "run, name, file")), sorted((
            {"run": entry["run"], "name": entry["name"], "file": entry.get("file"), "why": entry["why"],
             "files": entry.get("files"), "filesWithKills": entry.get("filesWithKills")}
            for entry in mutation["suspectTests"]),
            key=lambda row: (row["run"], row["name"].encode(), "" if row["file"] is None else row["file"])))

        def mutant_row(ordinal, entry):
            anchor = entry.get("anchor") or {}
            row = {key: entry.get(key) for key in (
                "path", "line", "column", "occurrence", "operator", "verdict", "outcome", "endedBy", "exitStatus",
                "failedTestCount", "fileSHA256", "before", "after", "description", "session", "durationSeconds",
                "run", "place", "owner", "reason")}
            row.update({
                "ordinal": ordinal, "anchorLine": anchor.get("line"), "anchorColumn": anchor.get("column"),
                "activated": flag(entry.get("activated")), "killedByComplete": flag(entry.get("killedByComplete")),
                "suspectOnly": flag(entry.get("suspectOnly")), "carried": flag(entry["carried"]),
                "reused": flag(entry["reused"]), "rerunBecause": entry.get("rerun"),
                "killedBy": entry["killedBy"],
            })
            return row

        stored_mutants = strip(rows("mutant", "ordinal"))
        for row in stored_mutants:
            row["killedBy"] = json.loads(row["killedBy"])
        compare("mutant", stored_mutants, [mutant_row(index, entry) for index, entry in enumerate(mutation["mutants"])])

        def flattened(value, prefix):
            if isinstance(value, dict):
                return {path: number for key, inner in value.items()
                        for path, number in flattened(inner, f"{prefix}.{key}").items()}
            return {prefix: float(value)} if value is not None else {}

        expected = {}
        for rollup in package.scan.get("rollups", []):
            for metric, number in flattened(rollup.get("mutation") or {}, "mutation").items():
                expected[(rollup["scope"], rollup["name"], metric)] = number
        stored_numbers = {(row["scope"], row["name"], row["metric"]): row["value"] for row in database.execute(
            "SELECT scope, name, metric, value, collector FROM rollupMetric "
            "WHERE snapshotId = ? AND metric LIKE 'mutation.%'", (snapshot,))}
        collectors = {row[0] for row in database.execute(
            "SELECT DISTINCT collector FROM rollupMetric WHERE snapshotId = ? AND metric LIKE 'mutation.%'",
            (snapshot,))}
        differences = [f"{' '.join(key)}: stored {stored_numbers.get(key)!r}, scan {expected.get(key)!r}"
                       for key in sorted(set(stored_numbers) | set(expected)) if stored_numbers.get(key) != expected.get(key)]
        self.result("mutation roll-up numbers", not differences and collectors == {"swiftmutator"},
                    f"{len(stored_numbers)} numbers from {sorted(collectors)}")
        self.listing(differences)
        database.close()


def mutant_key(mutant):
    return (mutant["path"], mutant["operator"], mutant["line"], mutant["column"], mutant["occurrence"])


# --------------------------------------------------------------------------


def base(arguments):
    package = Package(arguments.package, arguments.scan)
    runs = package.mutation.get("runs", [])
    results_path = arguments.results
    if results_path is None:
        if not runs:
            fail("the scan's mutation block lists no run")
        results_path = os.path.join(package.root, runs[0]["resultsFile"])
    results = Results(results_path)
    if arguments.report:
        return check(arguments, package, results, results_path, arguments.report)
    mutator = arguments.mutator or shutil.which("swift-mutator")
    if mutator is None:
        fail("swift-mutator not found on PATH; pass --mutator or --report")
    if os.sep in mutator:  # the report runs in the temporary folder
        mutator = os.path.abspath(mutator)
    work = arguments.work_dir or os.path.dirname(os.path.abspath(arguments.scan))
    # Removed on every exit, `fail`'s SystemExit and Ctrl-C included.
    with tempfile.TemporaryDirectory(prefix="mutation-check-", dir=work) as temporary:
        report_path = make_report(mutator, os.path.abspath(results_path), temporary)
        return check(arguments, package, results, results_path, report_path)


def check(arguments, package, results, results_path, report_path):
    """Every base check against the report at `report_path`; the exit status."""
    report = Report(report_path)
    expected = results.expected_mutants()
    scanned = {mutant_key(m): m for m in package.mutation["mutants"]}
    placement = Placement(package, expected)
    figures = Figures(package, results, report, placement)
    if arguments.dump:
        with open(arguments.dump, "w") as handle:
            json.dump({key_text(k): v for k, v in sorted(placement.places.items())}, handle, indent=1, sort_keys=True)
    checker = Checker(arguments.all)
    print(f"package {os.path.realpath(package.root)}: {len(package.records)} production records, "
          f"{len(package.files)} parsed files")
    print(f"results {os.path.realpath(results_path)} (sha256 {results.sha256[:16]}…)")
    print(f"report {os.path.realpath(report_path)}")
    checker.reader(package, results, expected, scanned)
    checker.report(package, results, expected, report)
    checker.suspects(package, scanned, report, figures)
    checker.placement(package, expected, scanned, placement)
    checker.figures(package, figures)
    checker.not_covered(results, scanned, placement)
    checker.share(placement)
    if arguments.store:
        checker.stored(package, arguments.store)
    print()
    if checker.failures:
        print(f"FAILED: {', '.join(checker.failures)}")
        return 1
    print("all checks passed")
    return 0


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    modes = parser.add_subparsers(dest="mode", required=True)
    checking = modes.add_parser("base", help="check a snapshot made by one full run")
    checking.add_argument("package")
    checking.add_argument("scan")
    checking.add_argument("--results", help="the results file (default: the run's resultsFile under the package)")
    checking.add_argument("--report", help="SwiftMutator's JSON report of the results file, already made")
    checking.add_argument("--mutator", help="the swift-mutator executable that makes the report (default: PATH)")
    checking.add_argument("--work-dir", help="where the report's temporary folder goes (default: the scan's folder)")
    checking.add_argument("--store", help="also compare the snapshot's stored rows in this store (store v5)")
    checking.add_argument("--all", action="store_true", help="list every difference")
    checking.add_argument("--dump", help="write this script's placement of every mutant here")
    arguments = parser.parse_args()
    return base(arguments)


if __name__ == "__main__":
    sys.exit(main())
