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

`merge` mode checks a snapshot made by a `--since` run merged with its base
(design section 6.1, section 9 step 5), building the merged mutant set
itself from the base's results file (the carried run's, a full run), the
since run's results file (none when SwiftMutator wrote none) and C's tree
(the since run's last header, or this script's hash of every Swift file in
the package), with SwiftMutator's selection worked out by its own git
command in the package:

  m1 the merged keys, verdicts, recorded fields and carried flags equal the
     scan's: a production path the run chose or has a mutant in takes the
     run's rows; with no results file, a production path of the selection is
     unlisted; any other path whose hash is the base's keeps the base's rows,
     carried, as a run that tested the base's commit and names the base; a
     base path gone from C's tree is deleted; a changed production path
     neither retested nor unlisted, or holding a base row with no file hash,
     is unresolved.
  m2 every path's disposition, test-file mark and hash equal the scan's.
  m3 mode, base, completeness (unresolved paths make it incomplete),
     `listsNotCovered` (the AND over the runs) and the collection date.
  d and e as in `base`, over the merged set, each mutant judged by its own
     run's report (the base's kept `report.json` beside its results file for
     carried mutants, the since run's for fresh ones), the roll-ups' carried
     counts included; and g with `--store`.

`since` mode checks the stored rows of the merged snapshot S_C against its
base S_B, per path and per function, as the done-when reads them:

  s1 every path whose hash is equal in S_B's and S_C's trees keeps S_B's rows
     exactly (key, verdict, outcome, killedBy, suspectOnly, fileSHA256,
     anchor, place, owner), carried, each naming a run that tested the base's
     commit and was carried from it, with disposition carried.
  s2 only retested paths hold fresh rows; the retested paths equal
     SwiftMutator's selection (its own git command, Swift production files,
     deletions dropped) and the since run's `since.files` less test files;
     fresh rows name the since run.
  s3 no S_B row of a retested or deleted path remains; a base path gone from
     C's tree is deleted; the selection's test files are marked, and the
     reason says carried verdicts weren't retested against them.
  s4 every production function whose key and body hash are equal in both
     keeps the same multiset of (operator, line from its first line, column,
     occurrence, before, after, verdict): zero differences, but a
     killed/timedOut flip that a solo rerun of that mutant confirmed as
     SwiftMutator's timing (listed in `--confirmed-flips`) is listed and
     allowed; every flip is printed with the rerun command.

`signals` mode re-derives M6's signals (design section 7, section 9 step
4) from a store's rows by the rules, without SwiftStats' code, and compares
them with `swiftstats report --format json` of that snapshot (the snapshot
the report names, by package, path, commit and dirtiness):

  t  the report is schema 5 and its `thresholds` lists exactly the limits
     this script uses (the defaults with each `--set` applied, genuinely
     under-tested's ratio only when set), so the limits the report states
     are checked against the ones given here, not taken from it.
  s  each of weak tests, genuinely under-tested, best property-test target
     and uneven clone testing (mutation) is computed, or left out with the
     reason its inputs give: a scan before schema 8 or with no swiftmutator
     run predates M6; a required collector (swiftmutator, then coverage; for
     best property-test target swiftmutator, then swiftinferproperties; for
     uneven clone mutation swiftclonedetector, then swiftmutator) that didn't
     run is named with its state and reason; genuinely under-tested also
     needs results that list code no test ran; then no mutation rows, then,
     for the two coverage signals, no coverage rows.
  r  each production module's and the project's test and production lines
     stored in the roll-ups equal those re-derived from the report's scan
     (the tests of test targets depending on the module directly, generated
     tests left out, the module's files' stripped lines), and where each
     module's test code stands: no test code, below the project's ratio
     (cross-multiplied), below `genuinely-under-tested.ratio` when set, or not
     low.
  w  weak tests: the pool (production functions outside generated files with
     a line tally mapping a line, in state scored or only not covered, with at
     least `mutants` scored mutants, the function score's denominator), the
     listed items (at least `coverage`% of lines covered, and the function
     score below `score`% with a survived or timed-out mutant, or a
     suspect-only kill), their scores (survived + timed out + suspect-only),
     order (score, function score cross-multiplied, subject, file, line),
     payloads (counts, both scores, killing tests, survivors, suspects,
     coverage, ratio) and every number of the rule and its funnel, in order.
  g  genuinely under-tested likewise: at most `coverage`% covered, function
     score below `score`%, the module's test code low; scored by unkilled
     mutants, ordered by score, then line coverage (cross-multiplied), subject,
     file and line; the single-module sentence exactly when one production
     module with tests is measured and no ratio is set.
  p  best property-test target: the suggestions it reads (algebraic, located
     in production code, attached to a production function outside generated
     files, of any tier, not disproven by fresh evidence, not rejected), the
     functions carrying them by mutation state, the pool (scored or only not
     covered), the listed items (an unkilled mutant of their own: survived,
     timed out, no coverage or not covered), their scores (own unkilled
     mutants plus each resolved partner's, a partner once per item), order
     (score, best suggestion's score with Verified's 50, subject, file,
     line), payloads (the function's mutation counts as weak tests', its
     suggestions best first with their flags, its unkilled mutants, its
     partners with their counts and unkilled mutants; no coverage, ratio or
     single suggestion), and every number of its funnel in order, the
     partners added and the mutants more than one item counts included.
  u  uneven clone testing (mutation): each clone copy's mutants (every
     mutant placed on a record, a type or the file, in the copy's file by NFC
     path, whose stored anchor lies in the copy's inclusive range), the
     copies skipped (in a file holding a generated function, in a file whose
     disposition is unresolved or unlisted, with fewer than `mutants` scored
     mutants), the pool (classes with two or more measured copies), the
     uneven classes (a copy's function score at least `high`%, another's at
     most `low`%), folding on the poor copies by lines (this script's own
     fold: classes holding each other stand as the most specific pass, then
     largest mass, then lowest ordinal; a held class goes to the maximal
     holder of largest mass, strongest kind, lowest ordinal), scores (the
     poor copies' unkilled mutants, each once), subjects (the least killed
     poor copy, cross-multiplied, then most unkilled, file, line, named by
     this script's own copy-to-family rule over the stored function rows),
     order (poor copies with a survived or timed-out mutant first, then
     score, mass, kind, subject, file, line, ordinal), payloads (the clone
     class with its folded ordinals and each measured copy's killed, scored,
     run-but-unchecked and unrun mutants; no other payload) and every number
     of its rule and funnel in order, the mutants more than one item counts
     included.

Shares are compared with the limits on integers (`killed × 100 < limit ×
scored`). The limits are the design's defaults unless `--set` gives the ones
the report's configuration sets; a `--set` naming a limit its signal doesn't
have (weak tests: coverage, score, mutants; genuinely under-tested: those and
ratio; uneven clone mutation: high, low, mutants) is refused. It trusts the stored coverage tallies and
the report's scan for the ratio inputs, and, for best property-test target,
the stored suggestion rows as the SwiftInferProperties collector joined them:
each one's owner, `partnerKey`, decision, verify judgement (`verified`,
`disproven`) and `testedBy`; for uneven clone mutation, the stored clone
classes and copy ranges (after SwiftStats' end-column adjustment), each
copy's `wholes` (newline-joined) and `containing` records, the function rows' parents and
generated marks, and each mutant's stored anchor and place (which `base`
mode checks against the source).

Inputs it trusts from SwiftStats, as M5's checker verified them against
llvm-cov: the scan JSON's record and type ranges, roles, modules, the
targets and their files, the parsed files and the generated marks. Top-level
statement lines come from `coverage-check.py`'s `statement_lines`, which this
script imports. It reads the source and results bytes itself.

Usage:
    Scripts/mutation-check.py merge <package-dir> <scan.json> [--base-results <file>]
                              [--base-report <file>] [--since-report <file>]
                              [--store <stats.sqlite>] [--all]
    Scripts/mutation-check.py since <package-dir> <scan.json> --store <stats.sqlite>
                              [--base-store <stats.sqlite>] [--dirty]
                              [--confirmed-flips <file>] [--all]
    Scripts/mutation-check.py signals <report.json> --store <stats.sqlite>
                              [--set <signal>.<limit>=<value> ...] [--all]
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
import re
import shutil
import sqlite3
import subprocess
import sys
import tempfile
import unicodedata
from collections import defaultdict
from fractions import Fraction

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

    def checked(self, key):
        """Whether the run that tested `key` judged reach (`suspectsChecked`)."""
        return self.suspects_checked


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

    def __init__(self, package, results, report, placement, carried=frozenset()):
        self.records = defaultdict(lambda: {"counts": zero_counts(), "tests": set(), "carried": 0})
        self.attachments = defaultdict(lambda: {"counts": zero_counts(), "tests": set(), "carried": 0})
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
                        False if report.checked(key) else None)
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
            target["carried"] += key in carried
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
        carried = defaultdict(int)
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
                carried[module] += value["carried"]
                carried[None] += value["carried"]
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
            out[("module", name)] = rollup(counts, functions[name], complete, carried[name])
        out[("project", "production")] = rollup(project, project_functions, complete, carried[None])
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


def rollup(counts, functions, complete, carried=0):
    scored = counts["killed"] + counts["survived"] + counts["noCoverage"] + counts["timedOut"]
    score = {"killed": counts["killed"], "scored": scored}
    value = percent(counts["killed"], scored)
    if value is not None and complete:
        score["percent"] = value
    item = dict(counts)
    item["carried"] = carried
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
        # carried runs name the base, so take the last run not carried; a
        # merge with no fresh run (SwiftMutator wrote no results file) is the
        # package's HEAD as it is now.
        fresh = [entry for entry in mutation["runs"] if entry.get("carriedFrom") is None]
        if fresh or mutation.get("mode") != "since":
            run = (fresh or mutation["runs"])[-1]
        else:
            run = {"commit": head_commit(package.root), "dirty": is_dirty(package.root)}
        name = package.scan["package"]
        package_path = package_path_of(package.root)
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


def package_path_of(root):
    """The package's path from its repository's top level, as GitReader reads it."""
    prefix = subprocess.run(["git", "rev-parse", "--show-prefix"], cwd=root, capture_output=True,
                            text=True).stdout.strip()
    return prefix[:-1] if prefix.endswith("/") else prefix


def head_commit(root):
    return subprocess.run(["git", "rev-parse", "HEAD"], cwd=root, capture_output=True, text=True).stdout.strip()


def is_dirty(root):
    """Whether the package's tree has changes git doesn't ignore (`.swiftstats/` ignores itself)."""
    status = subprocess.run(["git", "status", "--porcelain", "--", "."], cwd=root, capture_output=True, text=True)
    return bool(status.stdout.strip())


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


# --------------------------------------------------------------------------
# `--since` merges (design section 6.1, section 9 step 5)

PRUNED = {".build", ".git", ".swiftpm", "DerivedData", "xcuserdata", ".swiftstats"}


def git_selection(root, commit):
    """SwiftMutator's own selection in the package at `root` against `commit`:
    `git diff --name-status -z --relative --find-renames --ignore-submodules=all
    <commit> --` and the untracked files git doesn't ignore, Swift files only, a
    rename or copy by its new path, deletions dropped."""
    def run(command):
        result = subprocess.run(["git", "--no-optional-locks"] + command, cwd=root, capture_output=True)
        if result.returncode != 0:
            fail(f"git {command[0]} failed in {root}: {result.stderr.decode('utf-8', 'replace').strip()}")
        return [token.decode("utf-8") for token in result.stdout.split(b"\0") if token]
    tokens = run(["diff", "--name-status", "-z", "--relative", "--find-renames", "--ignore-submodules=all",
                  commit, "--"])
    paths = []
    index = 0
    while index < len(tokens):
        status = tokens[index]
        count = 2 if status[:1] in ("R", "C") else 1
        names = tokens[index + 1:index + 1 + count]
        if status != "D" and names:
            paths.append(names[-1])
        index += 1 + count
    paths += run(["ls-files", "--others", "--exclude-standard", "-z"])
    return sorted({path for path in paths if path.endswith(".swift")})


def swift_tree(root):
    """Every Swift file below `root` SwiftMutator lists, hashed as it hashes them."""
    tree = {}
    for folder, folders, files in os.walk(root):
        folders[:] = sorted(name for name in folders if name not in PRUNED
                            and not os.path.exists(os.path.join(folder, name, ".git")))
        for name in files:
            if not name.endswith(".swift"):
                continue
            path = os.path.join(folder, name)
            relative = os.path.relpath(path, root)
            if os.path.islink(path):
                tree[relative] = LINK_PREFIX + sha256(os.readlink(path).encode())
            else:
                with open(path, "rb") as handle:
                    tree[relative] = sha256(handle.read())
    return tree


def is_production(package, path):
    return package.classify(path)[0] in ("kept", "unmapped")


class MergedReport:
    """The base's report for carried keys, the since run's for fresh ones."""

    def __init__(self, base, fresh, carried):
        self.entries = {}
        self.base = base
        self.fresh = fresh
        self.carried = carried
        for key in carried:
            if key in base.entries:
                self.entries[key] = base.entries[key]
        if fresh is not None:
            for key, entry in fresh.entries.items():
                if key not in carried:
                    self.entries[key] = entry

    def checked(self, key):
        return self.base.suspects_checked if key in self.carried else (
            self.fresh.suspects_checked if self.fresh is not None else None)


class MergedResults:
    """The not-covered keys of both runs that the merge keeps, and completeness."""

    def __init__(self, not_covered, complete):
        self.not_covered = not_covered
        self.complete = complete


class Merge:
    """S_C's mutants built by this script from S_B's results file, the since
    run's results file (or none) and C's tree, by the design's merge rules."""

    def __init__(self, package, base_results, since_results, selection, base_commit):
        self.package = package
        base_tree = {nfc(p): (p, h) for p, h in base_results.last_tree.items() if p.endswith(".swift")}
        if since_results is not None:
            new_tree = {nfc(p): (p, h) for p, h in since_results.last_tree.items() if p.endswith(".swift")}
        else:
            new_tree = {nfc(p): (p, h) for p, h in swift_tree(package.root).items()}
        base_expected = base_results.expected_mutants()
        fresh_expected = since_results.expected_mutants() if since_results is not None else {}
        base_rows = defaultdict(list)
        for key in base_expected:
            base_rows[nfc(key[0])].append(key)
        fresh_paths = {nfc(key[0]) for key in fresh_expected}
        chosen = {nfc(item["path"]) for item in (since_results.first.get("since", {}).get("files", [])
                                                 if since_results is not None else [])}
        selected = {nfc(path) for path in selection}
        self.files = {}  # spelling -> {disposition, changedTest, sha256}
        self.mutants = {}  # key -> fields, with "carried"
        self.carried = set()
        self.unresolved = []
        for path in sorted(set(base_tree) | set(new_tree) | set(base_rows) | fresh_paths):
            if path not in new_tree:
                if path in base_tree:
                    self.files[base_tree[path][0]] = {"disposition": "deleted", "changedTest": False, "sha256": None}
                elif path not in fresh_paths:
                    self.carry(path, base_rows, base_expected)  # rows of no tree are kept
                continue
            spelled, hash_value = new_tree[path]
            production = is_production(package, spelled)
            changed_test = package.classify(spelled)[0] == "testFiles" and path in selected
            if path in fresh_paths or (production and path in chosen):
                disposition = "tested" if production else "untested"
            elif since_results is None and production and path in selected:
                disposition = "unlisted"
            elif path in base_tree and base_tree[path][1] == hash_value and all(
                    base_expected[key]["fileSHA256"] is not None for key in base_rows[path]):
                disposition = "carried" if production else "untested"
                self.carry(path, base_rows, base_expected)
            else:
                disposition = "unresolved" if production else "untested"
            if disposition == "unresolved":
                self.unresolved.append(spelled)
            self.files[spelled] = {"disposition": disposition, "changedTest": changed_test, "sha256": hash_value}
        for key, fields in fresh_expected.items():
            self.mutants[key] = dict(fields, carried=False)
        self.complete = (since_results.complete if since_results is not None else True) and not self.unresolved
        base_not_covered = [(key, entry) for key, entry in base_results.not_covered if key in self.carried]
        fresh_not_covered = list(since_results.not_covered) if since_results is not None else []
        self.results = MergedResults(base_not_covered + fresh_not_covered, self.complete)

    def carry(self, path, base_rows, base_expected):
        for key in base_rows[path]:
            self.mutants[key] = dict(base_expected[key], carried=True)
            self.carried.add(key)


def snapshot_id(database, name, package_path, commit, dirty):
    row = database.execute(
        "SELECT id FROM snapshot WHERE package = ? AND packagePath = ? AND ifnull(commitHash, '') = ? "
        "AND isDirty = ? ORDER BY id DESC LIMIT 1", (name, package_path, commit or "", 1 if dirty else 0)).fetchone()
    return None if row is None else row[0]




class StoredRows:
    """A snapshot's mutation rows, production functions and swiftmutator run, read from a store."""

    def __init__(self, path, name, root, commit, dirty):
        database = sqlite3.connect(f"file:{os.path.abspath(path)}?mode=ro", uri=True)
        database.row_factory = sqlite3.Row
        self.id = snapshot_id(database, name, package_path_of(root), commit, dirty)
        if self.id is None:
            fail(f"no snapshot of {name} at {commit} (dirty {dirty}) in {path}")

        def rows(sql):
            return [dict(row) for row in database.execute(sql, (self.id,))]
        self.scan = rows("SELECT * FROM mutationScan WHERE snapshotId = ?")
        if not self.scan:
            fail(f"snapshot {self.id} in {path} holds no mutation rows")
        self.scan = self.scan[0]
        self.runs = {row["ordinal"]: row for row in rows("SELECT * FROM mutationRun WHERE snapshotId = ?")}
        self.files = {row["path"]: row for row in rows("SELECT * FROM mutationFile WHERE snapshotId = ?")}
        self.mutants = rows("SELECT * FROM mutant WHERE snapshotId = ? ORDER BY ordinal")
        self.functions = {row["key"]: row for row in rows(
            "SELECT key, file, startLine, bodyHash FROM function WHERE snapshotId = ? AND role = 'production'")}
        run = rows("SELECT * FROM collectorRun WHERE snapshotId = ? AND name = 'swiftmutator'")
        self.collector = run[0] if run else {}
        database.close()

    def rows_of(self, path):
        return [row for row in self.mutants if row["path"] == path]


def compared(row):
    """What a carry must keep of a stored mutant row."""
    return (row["path"], row["operator"], row["line"], row["column"], row["occurrence"], row["verdict"], row["outcome"],
            row["killedBy"], row["suspectOnly"], row["fileSHA256"], row["anchorLine"], row["anchorColumn"],
            row["place"], row["owner"])


def function_mutants(rows, functions):
    """{function key: Counter of (operator, line from its first line, column, occurrence, before, after, verdict)}."""
    out = defaultdict(lambda: defaultdict(int))
    for row in rows:
        if row["place"] != "record" or row["owner"] not in functions:
            continue
        start = functions[row["owner"]]["startLine"]
        out[row["owner"]][(row["operator"], row["line"] - start, row["column"], row["occurrence"], row["before"],
                           row["after"], row["verdict"])] += 1
    return out


class SinceChecks(Checker):
    """Section 9 step 5's checks of a merged snapshot S_C against its base S_B."""

    def since(self, package, base_rows, rows, since_results, selection, base_commit, confirmed):
        mutation = package.mutation
        fresh_runs = [run for run in mutation["runs"] if run.get("carriedFrom") is None]
        print(f"    S_B snapshot {base_rows.id}, S_C snapshot {rows.id}; base {base_commit}")
        base_tree = {p: f["sha256"] for p, f in base_rows.files.items() if f["sha256"] is not None}
        new_tree = {p: f["sha256"] for p, f in rows.files.items() if f["sha256"] is not None}

        self.section("s1  unchanged paths keep S_B's rows, carried from the base")
        differences = []
        unchanged = sorted(p for p in base_tree if new_tree.get(p) == base_tree[p])
        carried_rows = 0
        for path in unchanged:
            mine = [compared(row) for row in base_rows.rows_of(path)]
            theirs = [compared(row) for row in rows.rows_of(path)]
            if mine != theirs:
                differences.append(f"{path}: {len(mine)} rows in S_B, {len(theirs)} in S_C, or fields differ")
            for row in rows.rows_of(path):
                carried_rows += 1
                run = rows.runs.get(row["run"], {})
                if row["carried"] != 1 or run.get("commit") != base_commit or run.get("carriedFrom") != base_commit:
                    differences.append(f"{path}:{row['line']}:{row['column']} {row['operator']}: carried "
                                       f"{row['carried']}, run commit {run.get('commit')}, carriedFrom "
                                       f"{run.get('carriedFrom')}")
            wanted = "carried" if is_production(package, path) else "untested"
            if base_rows.files[path]["disposition"] == "unlisted":
                wanted = "unlisted"
            if rows.files[path]["disposition"] != wanted:
                differences.append(f"{path}: disposition {rows.files[path]['disposition']}, expected {wanted}")
        self.result("carried paths", not differences, f"{len(unchanged)} unchanged paths, {carried_rows} rows")
        self.listing(differences)

        self.section("s2  only the retested paths have fresh rows, and they are SwiftMutator's selection")
        tested = sorted(p for p, f in rows.files.items() if f["disposition"] == "tested")
        unlisted = sorted(p for p, f in rows.files.items() if f["disposition"] == "unlisted"
                          and base_rows.files.get(p, {}).get("disposition") != "unlisted")
        fresh = sorted({row["path"] for row in rows.mutants if row["carried"] == 0})
        selected = sorted(p for p in selection if is_production(package, p))
        self.result("fresh rows in retested paths", set(fresh) <= set(tested), f"fresh rows in {fresh}")
        if since_results is not None:
            chosen = sorted(item["path"] for item in since_results.first.get("since", {}).get("files", [])
                            if is_production(package, item["path"]))
            self.result("retested = selection", tested == selected and not unlisted,
                        f"retested {tested}, unlisted {unlisted}, selection {selected}")
            self.result("retested = since.files less tests", tested == chosen, f"since.files {chosen}")
        else:
            # No results file: SwiftMutator tested nothing, so the selection's
            # production paths are unlisted.
            self.result("unlisted = selection (no results file)", unlisted == selected and not tested,
                        f"retested {tested}, unlisted {unlisted}, selection {selected}")
        fresh_runs = [run for run in rows.runs.values() if run.get("carriedFrom") is None]
        self.result("fresh rows name the since run", all(
            rows.runs.get(row["run"], {}).get("carriedFrom") is None for row in rows.mutants if row["carried"] == 0),
            ", ".join(f"since run {run['ordinal']} at {run['commit']}" for run in fresh_runs) or "no since run")

        self.section("s3  no S_B row of a retested or deleted path remains; test files and the reason")
        differences = []
        for path in tested:
            if any(row["carried"] for row in rows.rows_of(path)):
                differences.append(f"{path}: carried rows in a retested path")
        deleted = sorted(p for p in base_tree if p not in new_tree)
        for path in deleted:
            if rows.files.get(path, {}).get("disposition") != "deleted":
                differences.append(f"{path}: gone from C's tree but not deleted")
            if rows.rows_of(path):
                differences.append(f"{path}: rows remain at a deleted path")
        tests = sorted(p for p in selection if package.classify(p)[0] == "testFiles")
        marked = sorted(p for p, f in rows.files.items() if f["changedTest"])
        if tests != marked:
            differences.append(f"changed tests {marked}, selection's test files {tests}")
        reason = rows.collector.get("reason") or ""
        if tests and "carried verdicts weren't retested against" not in reason:
            differences.append(f"the reason doesn't say carried verdicts weren't retested: {reason!r}")
        self.result("retested and deleted paths", not differences,
                    f"deleted {deleted}, changed tests {marked}; reason {reason!r}")
        self.listing(differences)

        self.section("s4  per function: unchanged functions keep their verdicts")
        same = {key for key, row in rows.functions.items()
                if key in base_rows.functions and base_rows.functions[key]["bodyHash"] == row["bodyHash"]}
        mine = function_mutants(base_rows.mutants, {k: base_rows.functions[k] for k in same})
        theirs = function_mutants(rows.mutants, {k: rows.functions[k] for k in same})
        differences = []
        flips = []
        for key in sorted(same):
            before, after = mine.get(key, {}), theirs.get(key, {})
            if before == after:
                continue
            places = defaultdict(lambda: [[], []])
            for side, table in ((0, before), (1, after)):
                for item, count in table.items():
                    places[item[:6]][side] += [item[6]] * count
            for place, (old, new) in sorted(places.items()):
                if sorted(old) == sorted(new):
                    continue
                if len(old) == len(new) == 1 and {old[0], new[0]} == {"killed", "timedOut"}:
                    start = rows.functions[key]["startLine"]
                    text = f"{rows.functions[key]['file']}:{start + place[1]}:{place[2]} {place[0]}"
                    flips.append((text, old[0], new[0]))
                else:
                    differences.append(f"{key}: {place} {old} → {new}")
        unconfirmed = [flip for flip in flips if flip[0] not in confirmed]
        moved = sum(1 for key in same if rows.functions[key]["startLine"] != base_rows.functions[key]["startLine"])
        self.result("verdicts", not differences and not unconfirmed,
                    f"{len(same)} functions unchanged ({moved} moved), {sum(sum(t.values()) for t in theirs.values())} "
                    f"mutants; {len(differences)} differences, {len(flips)} killed↔timedOut flips "
                    f"({len(flips) - len(unconfirmed)} confirmed by a solo rerun)")
        self.listing(differences)
        for text, old, new in flips:
            print(f"    flip {text}: S_B {old}, S_C {new}" + (" (confirmed)" if text in confirmed else
                  f" — rerun alone: swift-mutator run --mutant '{text}'"))
        changed = sorted(key for key in rows.functions if key in base_rows.functions and key not in same)
        print(f"    {len(changed)} functions changed: {changed[:LIMIT]}")


def merge_checks(checker, package, merge, scanned, base_commit):
    """m1 to m3: the merged mutant set, tree and facts equal this script's own merge."""
    mutation = package.mutation
    checker.section("m1  the merged mutants equal this script's merge of both results files and C's tree")
    missing = sorted(set(merge.mutants) - set(scanned))
    extra = sorted(set(scanned) - set(merge.mutants))
    checker.result("key set", not missing and not extra,
                   f"{len(merge.mutants)} keys merged ({len(merge.carried)} carried), {len(scanned)} in the scan")
    checker.listing([f"missing from the scan: {key_text(k)}" for k in missing]
                    + [f"only in the scan: {key_text(k)}" for k in extra])
    runs = {run["ordinal"]: run for run in mutation["runs"]}
    differences = []
    for key in sorted(set(merge.mutants) & set(scanned)):
        mine, theirs = merge.mutants[key], scanned[key]
        for field, value in mine.items():
            if theirs.get(field) != value and not (field == "killedBy" and value == [] and field not in theirs):
                differences.append(f"{key_text(key)}: {field} {value!r} / scan {theirs.get(field)!r}")
        run = runs.get(theirs.get("run"), {})
        carried_from = (run.get("carriedFrom") or {}).get("commit")
        if mine["carried"] and (run.get("commit") != base_commit or carried_from != base_commit):
            differences.append(f"{key_text(key)}: carried, but its run tested {run.get('commit')}, "
                               f"carried from {carried_from}")
        if not mine["carried"] and run.get("carriedFrom") is not None:
            differences.append(f"{key_text(key)}: fresh, but its run is carried from {carried_from}")
    checker.result("verdicts, fields and runs", not differences, f"{len(differences)} differences")
    checker.listing(differences)

    checker.section("m2  the merged tree's dispositions")
    theirs = {f["path"]: {"disposition": f["disposition"], "changedTest": f["changedTest"], "sha256": f.get("sha256")}
              for f in mutation["files"]}
    differences = [f"{path}: scan {theirs.get(path)} / expected {merge.files.get(path)}"
                   for path in sorted(set(theirs) | set(merge.files)) if theirs.get(path) != merge.files.get(path)]
    counts = defaultdict(int)
    for item in merge.files.values():
        counts[item["disposition"]] += 1
    checker.result("tree", not differences, f"{dict(sorted(counts.items()))}")
    checker.listing(differences)

    checker.section("m3  merged facts")
    listed = all(run["listsNotCovered"] for run in mutation["runs"]) if mutation["runs"] else None
    fresh = [run for run in mutation["runs"] if run.get("carriedFrom") is None]
    wanted = {
        "mode": (mutation["mode"], "since"),
        "base commit": ((mutation.get("base") or {}).get("commit"), base_commit),
        "complete": (mutation["complete"], merge.complete),
        "listsNotCovered": (mutation["listsNotCovered"], listed),
        "collectedAt": (mutation["collectedAt"], fresh[-1]["startedAt"] if fresh else
                        (mutation.get("base") or {}).get("collectedAt")),
        "unresolved": (sorted(p for p, f in theirs.items() if f["disposition"] == "unresolved"), sorted(merge.unresolved)),
    }
    problems = [f"{name}: scan {a!r} / expected {b!r}" for name, (a, b) in wanted.items() if a != b]
    checker.result("facts", not problems, ", ".join(f"{name} {b!r}" for name, (_, b) in wanted.items()))
    checker.listing(problems)


def kept_beside(results_file, name):
    path = os.path.join(os.path.dirname(results_file), name)
    return path if os.path.isfile(path) else None


def merge(arguments):
    package = Package(arguments.package, arguments.scan)
    mutation = package.mutation
    if mutation.get("mode") != "since":
        fail(f"{arguments.scan}'s mutation results aren't a --since merge")
    base_commit = mutation["base"]["commit"]
    carried_runs = [run for run in mutation["runs"] if run.get("carriedFrom") is not None]
    fresh_runs = [run for run in mutation["runs"] if run.get("carriedFrom") is None]
    base_results_path = arguments.base_results or (
        os.path.join(package.root, carried_runs[0]["resultsFile"]) if carried_runs else None)
    if base_results_path is None:
        fail("no carried run names the base's results file; pass --base-results")
    base_results = Results(base_results_path)
    since_results_path = os.path.join(package.root, fresh_runs[0]["resultsFile"]) if fresh_runs else None
    since_results = Results(since_results_path) if since_results_path else None
    selection = git_selection(package.root, base_commit)
    built = Merge(package, base_results, since_results, selection, base_commit)
    base_report = Report(arguments.base_report or kept_beside(base_results_path, "report.json")
                         or fail("no report.json beside the base's results file; pass --base-report"))
    since_report = None
    if since_results_path:
        since_report = Report(arguments.since_report or kept_beside(since_results_path, "report.json")
                              or fail("no report.json beside the since run's results file; pass --since-report"))
    report = MergedReport(base_report, since_report, built.carried)
    scanned = {mutant_key(m): m for m in mutation["mutants"]}
    placement = Placement(package, built.mutants)
    figures = Figures(package, built.results, report, placement, built.carried)
    checker = Checker(arguments.all)
    print(f"package {os.path.realpath(package.root)}: {len(package.records)} production records")
    print(f"base results {os.path.realpath(base_results_path)}; since results "
          f"{os.path.realpath(since_results_path) if since_results_path else 'none (no results file)'}")
    print(f"SwiftMutator's selection since {base_commit[:10]}: {selection}")
    merge_checks(checker, package, built, scanned, base_commit)
    checker.placement(package, built.mutants, scanned, placement)
    checker.figures(package, figures)
    if arguments.store:
        checker.stored(package, arguments.store)
    print()
    if checker.failures:
        print(f"FAILED: {', '.join(checker.failures)}")
        return 1
    print("all checks passed")
    return 0


def since(arguments):
    package = Package(arguments.package, arguments.scan)
    mutation = package.mutation
    if mutation.get("mode") != "since":
        fail(f"{arguments.scan}'s mutation results aren't a --since merge")
    base_commit = mutation["base"]["commit"]
    fresh_runs = [run for run in mutation["runs"] if run.get("carriedFrom") is None]
    run = (fresh_runs or mutation["runs"])[-1]
    name = package.scan["package"]
    if fresh_runs:
        commit, dirty = run["commit"], run["dirty"]
    else:
        commit, dirty = head_commit(package.root), arguments.dirty or is_dirty(package.root)
    rows = StoredRows(arguments.store, name, package.root, commit, dirty)
    base_rows = StoredRows(arguments.base_store or arguments.store, name, package.root, base_commit, False)
    since_results = Results(os.path.join(package.root, fresh_runs[0]["resultsFile"])) if fresh_runs else None
    selection = git_selection(package.root, base_commit)
    confirmed = set()
    if arguments.confirmed_flips:
        with open(arguments.confirmed_flips) as handle:
            confirmed = {line.strip() for line in handle if line.strip()}
    checker = SinceChecks(arguments.all)
    print(f"package {os.path.realpath(package.root)} at {commit}; SwiftMutator's selection: {selection}")
    checker.since(package, base_rows, rows, since_results, selection, base_commit, confirmed)
    print()
    if checker.failures:
        print(f"FAILED: {', '.join(checker.failures)}")
        return 1
    print("all checks passed")
    return 0


# --------------------------------------------------------------------------
# signals mode: weak tests, genuinely under-tested, best property-test target and uneven clone mutation
# re-derived from the store


# The mutation signals' limits when none is set (design section 7).
DEFAULT_LIMITS = {
    "weak-tests": {"coverage": 80.0, "score": 50.0, "mutants": 3.0},
    "genuinely-under-tested": {"coverage": 20.0, "score": 20.0, "mutants": 3.0},
    "uneven-clone-mutation": {"high": 80.0, "low": 20.0, "mutants": 2.0},
}
# The limits each signal's --set may name: its defaults, and genuinely under-tested's ratio, unset by default.
LIMIT_NAMES = {
    "weak-tests": ("coverage", "score", "mutants"),
    "genuinely-under-tested": ("coverage", "score", "mutants", "ratio"),
    "uneven-clone-mutation": ("high", "low", "mutants"),
}
MINIMUM_COPIES = 2
MAPPED_PLACES = ("record", "type", "file")
# How specific a clone pass's claim is, and how strong each kind's claim is.
PASS_SPECIFICITY = {"subtree": 0, "sequence": 1, "near-miss": 2}
KIND_ORDER = ("exact", "renamed", "sequence", "near-miss")
WEAK_NOT_LISTED_NOTE = ("; the mutation results don't list code no test ran (a SwiftMutator build before 13f96a46), "
                        "so functions no test ran aren't judged")
NOT_LISTED_REASON = ("the mutation results don't list code no test ran (a SwiftMutator build before 13f96a46), "
                     "so low scores can't be told from missing ones")
FIRST_M6_SCHEMA = 8
# The `swiftstats report --format json` version that lists the thresholds used.
REPORT_SCHEMA = 5
NAMED_KILLING_TESTS = 5
VERIFIED_BONUS = 50
UNKILLED = ("survived", "timedOut", "noCoverage", "notCovered")
# Each M6 signal's required collectors, in order.
SIGNAL_COLLECTORS = {
    "weak-tests": ("swiftmutator", "coverage"),
    "genuinely-under-tested": ("swiftmutator", "coverage"),
    "best-property-target": ("swiftmutator", "swiftinferproperties"),
    "uneven-clone-mutation": ("swiftclonedetector", "swiftmutator"),
}
NUMBER = re.compile(r"\d+(?:\.\d+)?")


def share_key(part, whole):
    """A share compared by cross-multiplying, as a sort key: the fraction itself, exact."""
    return Fraction(part, whole)


def nonnegative_lines(covered, total):
    return {"covered": covered, "total": total} if covered is not None and total is not None else None


class SignalStore:
    """The rows the M6 signals read, straight from a store (no SwiftStats code)."""

    def __init__(self, path, snapshot):
        database = sqlite3.connect(f"file:{os.path.abspath(path)}?mode=ro", uri=True)
        database.row_factory = sqlite3.Row
        git = snapshot["git"]
        self.id = snapshot_id(database, snapshot["package"], git.get("packagePath", ""), git.get("commit"),
                              git.get("isDirty", False))
        if self.id is None:
            fail(f"no snapshot of {snapshot['package']} at {git.get('commit')} in {path}")

        def rows(sql):
            return [dict(row) for row in database.execute(sql, (self.id,))]
        self.schema = rows("SELECT reportSchemaVersion FROM snapshot WHERE id = ?")[0]["reportSchemaVersion"]
        self.collectors = {row["name"]: row for row in rows("SELECT * FROM collectorRun WHERE snapshotId = ?")}
        scan = rows("SELECT * FROM mutationScan WHERE snapshotId = ?")
        self.scan = scan[0] if scan else None
        self.coverage_run = bool(rows("SELECT snapshotId FROM coverageRun WHERE snapshotId = ?"))
        # Production rows outside generated files; a row whose generated column is null is left out.
        self.functions = rows("SELECT key, module, file, startLine FROM function WHERE snapshotId = ? "
                              "AND role = 'production' AND generated = 0 ORDER BY rowid")
        self.coverage = {row["key"]: row for row in rows("SELECT * FROM functionCoverage WHERE snapshotId = ?")}
        self.mutants = rows("SELECT * FROM mutant WHERE snapshotId = ? ORDER BY ordinal")
        self.dispositions = {nfc(row["path"]): row["disposition"]
                             for row in rows("SELECT path, disposition FROM mutationFile WHERE snapshotId = ?")}
        self.suspects = defaultdict(list)
        for row in rows("SELECT run, name, why, files, filesWithKills FROM mutationSuspect WHERE snapshotId = ?"):
            self.suspects[(row["run"], row["name"])].append((row["why"], row["files"], row["filesWithKills"]))
        self.rollups = rows("SELECT scope, name, metric, value FROM rollupMetric WHERE snapshotId = ?")
        self.candidates = rows("SELECT * FROM propertyCandidate WHERE snapshotId = ? ORDER BY ordinal")
        # Every function row (any role), for the copy-to-family rule, and the files holding a generated one.
        self.all_functions = rows("SELECT key, kind, accessorKind, parentKey, file, startLine FROM function "
                                  "WHERE snapshotId = ? ORDER BY rowid")
        self.generated_files = {row["file"] for row in
                                rows("SELECT DISTINCT file FROM function WHERE snapshotId = ? AND generated = 1")}
        self.clone_classes = rows("SELECT * FROM cloneClass WHERE snapshotId = ? ORDER BY ordinal")
        instances = defaultdict(list)
        for row in rows("SELECT * FROM cloneInstance WHERE snapshotId = ? ORDER BY classOrdinal, ordinal"):
            instances[row["classOrdinal"]].append(row)
        for clone in self.clone_classes:
            clone["instances"] = instances[clone["ordinal"]]
        database.close()


def record_counts(rows):
    """A record's mutants counted as the scan counts them."""
    counts = zero_counts()
    for row in rows:
        verdict = row["verdict"]
        counts[verdict if verdict != "buildError" else "buildErrors"] += 1
        if verdict == "killed" and row["outcome"] == "runtimeError":
            counts["crashKills"] += 1
        if row["suspectOnly"] == 1:
            counts["suspectOnly"] += 1
        if verdict == "killed" and row["outcome"] != "runtimeError" and row["suspectOnly"] is not None:
            counts["judgedKills"] += 1
    return counts


def without_nulls(value):
    """`value` as the report's JSON writes it: a null field is left out."""
    if isinstance(value, dict):
        return {key: without_nulls(item) for key, item in value.items() if item is not None}
    if isinstance(value, list):
        return [without_nulls(item) for item in value]
    return value


def score_of(killed, scored):
    return {"killed": killed, "scored": scored, "percent": percent(killed, scored)}


class SignalModel:
    """M6's per-function signals, derived by the design's rules."""

    def __init__(self, store, limits, scan):
        self.store = store
        self.limits = limits
        held = defaultdict(list)
        for row in store.mutants:
            if row["place"] == "record":
                held[row["owner"]].append(row)
        self.held = held
        self.ratios, self.modules, self.project = self.stored_ratios()
        self.derived_ratios = self.derive_ratios(scan) if scan else None

    # Ratios
    def stored_ratios(self):
        tests, production, modules, project = {}, {}, set(), {}
        for row in self.store.rollups:
            if row["scope"] == "module" and row["metric"] == "mutation.killed":
                modules.add(row["name"])
            elif row["metric"] in ("tests.lineRatio.testLines", "tests.lineRatio.productionLines"):
                field = "testLines" if row["metric"].endswith("testLines") else "productionLines"
                if row["scope"] == "module":
                    (tests if field == "testLines" else production)[row["name"]] = int(row["value"])
                elif row["name"] == "production":
                    project[field] = int(row["value"])
        ratios = {name: {"testLines": tests[name], "productionLines": production[name]}
                  for name in tests if name in production}
        return ratios, sorted(modules), (project if len(project) == 2 else None)

    @staticmethod
    def derive_ratios(scan):
        """Each production module's and the project's lines from the scan's targets, tests, records and files
        (PRD 7.8: a module counts the tests of the test targets that depend on it directly)."""
        lines = {record["key"]: record["strippedLines"] for record in scan["records"]}
        tests = [test for test in scan["tests"] if not test["generated"]]
        test_targets = [target for target in scan["targets"] if target["isTest"]]
        production = [target["name"] for target in scan["targets"] if not target["isTest"]]

        def count(testing, modules):
            return {"testLines": sum(lines.get(test["key"], 0) for test in tests if test["module"] in testing),
                    "productionLines": sum(file["strippedLines"] for file in scan["files"]
                                           if file["module"] in modules)}
        derived = {}
        for name in production:
            dependents = {target["name"] for target in test_targets if name in target["dependencies"]}
            derived[name] = count(dependents, {name})
        project = count({target["name"] for target in test_targets}, set(production))
        return derived, project

    def standing(self, module):
        own = self.ratios.get(module)
        if own is None or own["testLines"] == 0:
            return "noTestCode"
        project = self.project
        if project and own["testLines"] * project["productionLines"] < project["testLines"] * own["productionLines"]:
            return "belowProject"
        ratio = self.limits["genuinely-under-tested"].get("ratio")
        if ratio is not None and own["testLines"] < ratio * own["productionLines"]:
            return "belowRatio"
        return "notLow"

    # Functions
    def state(self, function, counts):
        disposition = self.store.dispositions.get(nfc(function["file"]))
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

    def lines(self, function):
        row = self.store.coverage.get(function["key"])
        if row is None or row["lineTotal"] is None or row["lineTotal"] == 0:
            return None
        return row["lineCovered"], row["lineTotal"]

    def pool(self, minimum):
        """The pool, and the funnel's counts down to it."""
        counts = {"functions": len(self.store.functions), "withData": 0, "fewer": 0, "buildErrorsOnly": 0,
                  "noMutant": 0, "noResults": 0, "notListed": 0}
        candidates = []
        for function in self.store.functions:
            lines = self.lines(function)
            if lines is None:
                continue
            counts["withData"] += 1
            held = self.held.get(function["key"])
            tally = record_counts(held) if held else None
            state = self.state(function, tally)
            if state in ("scored", "notCoveredOnly"):
                scored = tally["killed"] + tally["survived"] + tally["noCoverage"] + tally["timedOut"] \
                    + tally["notCovered"]
                if scored >= minimum:
                    candidates.append({"function": function, "counts": tally, "lines": lines, "scored": scored})
                else:
                    counts["fewer"] += 1
            else:
                counts[state] += 1
        return candidates, counts

    @staticmethod
    def funnel_numbers(candidates, counts, minimum):
        without = counts["noResults"] + counts["notListed"]
        return [counts["functions"], counts["withData"], counts["functions"] - counts["withData"], counts["withData"],
                len(candidates), minimum, counts["fewer"], counts["buildErrorsOnly"], counts["noMutant"], without,
                counts["noResults"], counts["notListed"]]

    def payload(self, candidate):
        function = candidate["function"]
        held = self.held[function["key"]]
        tally = candidate["counts"]
        killing = sorted({name for row in held if row["verdict"] == "killed" for name in json.loads(row["killedBy"])})
        suspects = set()
        for row in held:
            if row["suspectOnly"] == 1:
                for name in json.loads(row["killedBy"]):
                    for why, files, with_kills in self.store.suspects.get((row["run"], name), []):
                        suspects.add((name, why, files, with_kills))
        coverage = self.store.coverage.get(function["key"]) or {}
        tested = tally["killed"] + tally["survived"] + tally["noCoverage"] + tally["timedOut"]
        return {
            "mutation": {
                "counts": tally,
                "score": score_of(tally["killed"], tested),
                "functionScore": score_of(tally["killed"], tested + tally["notCovered"]),
                "killingTests": len(killing),
                "firstKillingTests": killing[:NAMED_KILLING_TESTS],
                "survivors": [{"operator": row["operator"], "line": row["line"], "column": row["column"],
                               "before": row["before"], "after": row["after"], "verdict": row["verdict"]}
                              for row in held if row["verdict"] in ("survived", "timedOut")],
                "suspects": [{"name": name, "why": why, "files": files, "filesWithKills": with_kills}
                             for name, why, files, with_kills in
                             sorted(suspects, key=lambda entry: (entry[0], entry[1], -1 if entry[2] is None
                                                                 else entry[2], -1 if entry[3] is None
                                                                 else entry[3]))],
            },
            "coverage": {"lines": nonnegative_lines(coverage.get("lineCovered"), coverage.get("lineTotal")),
                         "regions": nonnegative_lines(coverage.get("regionCovered"), coverage.get("regionTotal"))},
            "ratio": {"module": function["module"], "moduleLines": self.ratios.get(function["module"]),
                      "projectLines": self.project},
        }

    def weak_tests(self):
        limits = self.limits["weak-tests"]
        minimum = int(limits["mutants"])
        candidates, counts = self.pool(minimum)
        covered = [c for c in candidates if c["lines"][0] * 100 >= limits["coverage"] * c["lines"][1]]
        by_score = by_suspects = unrun_only = judged = failed = 0
        items = []
        for candidate in covered:
            tally = candidate["counts"]
            judged += tally["judgedKills"]
            failed += tally["killed"] - tally["crashKills"]
            below = tally["killed"] * 100 < limits["score"] * candidate["scored"]
            unchecked = tally["survived"] + tally["timedOut"]
            score_arm = below and unchecked > 0
            suspect_arm = tally["suspectOnly"] > 0
            if score_arm:
                by_score += 1
            elif suspect_arm:
                by_suspects += 1
            elif below:
                unrun_only += 1
            if score_arm or suspect_arm:
                function = candidate["function"]
                items.append((-(unchecked + tally["suspectOnly"]), share_key(tally["killed"], candidate["scored"]),
                              function["key"], function["file"], function["startLine"], unchecked
                              + tally["suspectOnly"], candidate))
        listed = by_score + by_suspects
        numbers = [limits["coverage"], limits["score"], minimum]
        numbers += self.funnel_numbers(candidates, counts, minimum)
        numbers += [len(candidates), len(covered), limits["coverage"], len(candidates) - len(covered), len(covered),
                    listed, unrun_only, limits["score"], len(covered) - listed - unrun_only, limits["score"], listed,
                    by_score, by_suspects, judged, failed, len(covered), 10, 20]
        return self.ordered(items), len(candidates), numbers

    def genuinely_under_tested(self):
        limits = self.limits["genuinely-under-tested"]
        minimum = int(limits["mutants"])
        ratio = limits.get("ratio")
        candidates, counts = self.pool(minimum)
        barely = [c for c in candidates if c["lines"][0] * 100 <= limits["coverage"] * c["lines"][1]]
        not_low = not_below = 0
        items = []
        for candidate in barely:
            tally = candidate["counts"]
            function = candidate["function"]
            if not tally["killed"] * 100 < limits["score"] * candidate["scored"]:
                not_below += 1
            elif self.standing(function["module"]) != "notLow":
                unkilled = candidate["scored"] - tally["killed"]
                items.append((-unkilled, share_key(*candidate["lines"]), function["key"], function["file"],
                              function["startLine"], unkilled, candidate))
            else:
                not_low += 1
        standings = [self.standing(module) for module in self.modules]
        low = sum(1 for standing in standings if standing != "notLow")
        numbers = [limits["coverage"], limits["score"], minimum] + ([ratio] if ratio is not None else [])
        numbers += [len(self.modules), low, len(standings) - low, low, standings.count("noTestCode"),
                    standings.count("belowProject")]
        if ratio is not None:
            numbers += [standings.count("belowRatio"), ratio]
        numbers += self.funnel_numbers(candidates, counts, minimum)
        numbers += [len(candidates), len(barely), limits["coverage"], len(candidates) - len(barely), len(barely),
                    len(items), not_low, limits["score"], not_below, limits["score"]]
        single = standings == ["notLow"] and ratio is None
        return self.ordered(items), len(candidates), numbers, single

    def unkilled(self, key):
        return [{"operator": row["operator"], "line": row["line"], "column": row["column"], "before": row["before"],
                 "after": row["after"], "verdict": row["verdict"]}
                for row in self.held.get(key, []) if row["verdict"] in UNKILLED]

    @staticmethod
    def suggestion(row):
        return without_nulls({"identity": row["identity"], "template": row["template"], "tier": row["tier"],
                              "score": row["score"], "verified": row["verified"] == 1,
                              "blocked": row["blocked"] == 1, "decision": row["decision"],
                              "partner": row["partner"], "testedBy": row["testedBy"]})

    @staticmethod
    def weight(row):
        """A suggestion's score with Verified's bonus, as untested property scores it."""
        return row["score"] + (VERIFIED_BONUS if row["verified"] == 1 else 0)

    def best_property_target(self):
        keys = {function["key"] for function in self.store.functions}
        pooled = [row for row in self.store.candidates
                  if row["population"] == "algebraic" and row["site"] == "production"
                  and row["attachedTo"] == "function" and row["owner"] in keys
                  and row["disproven"] != 1 and row["decision"] != "rejected"]
        by_owner = defaultdict(list)
        for offset, row in enumerate(pooled):
            by_owner[row["owner"]].append((offset, row))
        counts = {"functions": 0, "withResults": 0, "buildErrorsOnly": 0, "noMutant": 0, "noResults": 0,
                  "notListed": 0, "allKilled": 0, "partners": 0}
        items, counting = [], defaultdict(int)
        for function in self.store.functions:
            held_suggestions = by_owner.get(function["key"])
            if not held_suggestions:
                continue
            counts["functions"] += 1
            held = self.held.get(function["key"])
            tally = record_counts(held) if held else None
            state = self.state(function, tally)
            if state not in ("scored", "notCoveredOnly"):
                counts[state] += 1
                continue
            counts["withResults"] += 1
            own = self.unkilled(function["key"])
            if not own:
                counts["allKilled"] += 1
                continue
            weight = self.weight
            ranked = sorted(held_suggestions, key=lambda entry: (-weight(entry[1]), entry[1]["identity"], entry[0]))
            partner_keys = sorted({row["partnerKey"] for _, row in held_suggestions
                                   if row["partnerKey"] is not None and row["partnerKey"] != function["key"]
                                   and row["partnerKey"] in keys})
            partners = []
            for key in partner_keys:
                rows = self.held.get(key)
                partners.append(without_nulls({"key": key, "counts": record_counts(rows) if rows else None,
                                               "unkilled": self.unkilled(key)}))
            counts["partners"] += len(partners)
            for key in [function["key"]] + partner_keys:
                counting[key] += 1
            score = len(own) + sum(len(partner["unkilled"]) for partner in partners)
            payload = without_nulls(self.payload({"function": function, "counts": tally}))
            payload = {"mutation": payload["mutation"],
                       "propertyTarget": {"suggestions": [self.suggestion(row) for _, row in ranked],
                                          "unkilled": own, "partners": partners},
                       "coverage": None, "ratio": None, "property": None}
            items.append(((-score, -weight(ranked[0][1]), function["key"], function["file"], function["startLine"]),
                          {"function": function, "score": score, "payload": payload}))
        items.sort(key=lambda item: item[0])
        shared = sum(len(self.unkilled(key)) for key, number in counting.items() if number > 1)
        without = counts["noResults"] + counts["notListed"]
        numbers = [counts["functions"], len(pooled), counts["withResults"], counts["buildErrorsOnly"],
                   counts["noMutant"], without, counts["noResults"], counts["notListed"], counts["withResults"],
                   len(items), counts["allKilled"], counts["partners"], shared]
        return [entry for _, entry in items], counts["withResults"], numbers

    # Uneven clone mutation
    def families(self):
        """Each function key's family id, and each family's root key or accessor keys, by the copy-to-family rule
        (design section 7.4; PRD 8): a record's family is its topmost ancestor's; a computed property's accessors
        form one family named by the property's key."""
        rows = self.store.all_functions
        first_index = {}
        for index, row in enumerate(rows):
            first_index.setdefault(row["key"], index)

        def is_accessor(row):
            return row["kind"] == "accessor" and row["parentKey"] is None

        def owner_key(row):
            accessor = row["accessorKind"]
            suffix = f" {{ {accessor} }}"
            if accessor and suffix in row["key"]:
                position = row["key"].rfind(suffix)
                return row["key"][:position] + row["key"][position + len(suffix):]
            return row["key"]
        groups = defaultdict(list)
        for index, row in enumerate(rows):
            current, seen = index, {index}
            while rows[current]["parentKey"] is not None and rows[current]["parentKey"] in first_index \
                    and first_index[rows[current]["parentKey"]] not in seen:
                current = first_index[rows[current]["parentKey"]]
                seen.add(current)
            top = rows[current]
            group = ("property", owner_key(top), top["file"]) if is_accessor(top) else ("record", current)
            groups[group].append(row)
        families = []
        for members in groups.values():
            members = sorted(members, key=lambda row: (row["key"], row["startLine"]))
            root = next((row for row in members if row["parentKey"] is None and not is_accessor(row)), None)
            family_id = root["key"] if root else owner_key(members[0])
            start = root["startLine"] if root else members[0]["startLine"]
            accessors = [] if root else [row for row in members if is_accessor(row)]
            families.append({"id": family_id, "file": (root or members[0])["file"], "start": start, "root": root,
                             "accessors": accessors, "members": members})
        families.sort(key=lambda family: (family["id"], family["file"], family["start"]))
        by_key = {}
        for position, family in enumerate(families):
            for member in family["members"]:
                by_key.setdefault(member["key"], position)
        return families, by_key

    @staticmethod
    def family_of(instance, families, by_key):
        """The family naming a copy: the first family whose root (or every accessor) it covers whole, else its
        containing record's, else `<file>:<line>`."""
        wholes = [key for key in instance["wholes"].split("\n") if key]
        covered, seen = set(wholes), set()
        for key in wholes:
            position = by_key.get(key)
            if position is None or position in seen:
                continue
            seen.add(position)
            family = families[position]
            if family["root"] is not None:
                if family["root"]["key"] in covered:
                    return family["id"]
            elif all(accessor["key"] in covered for accessor in family["accessors"]):
                return family["id"]
        holder = instance["containing"]
        if holder is not None and holder in by_key:
            return families[by_key[holder]]["id"]
        return f"{instance['file']}:{instance['startLine']}"

    @staticmethod
    def holds(holder, held):
        """Whether every poor copy of `held` lies, by lines, inside a poor copy of `holder`."""
        return all(any(copy["file"] == other["file"] and other["startLine"] <= copy["startLine"]
                       and copy["endLine"] <= other["endLine"] for other in holder["poor"]) for copy in held["poor"])

    def folded(self, members):
        """The members no other holds, each with the ordinals folded into it (CloneFolding's rule, re-written)."""
        def kind_rank(clone):
            kind = "near-miss" if clone["pass"] == "near-miss" else "sequence" if clone["pass"] == "sequence" \
                else "exact" if clone["exact"] else "renamed"
            return KIND_ORDER.index(kind)
        groups = []
        for member in sorted(members, key=lambda member: member["class"]["ordinal"]):
            for group in groups:
                if self.holds(group[0], member) and self.holds(member, group[0]):
                    group.append(member)
                    break
            else:
                groups.append([member])
        folded_into, representatives = defaultdict(list), []
        for group in groups:
            standing = min(group, key=lambda member: (PASS_SPECIFICITY[member["class"]["pass"]],
                                                      -member["class"]["mass"], member["class"]["ordinal"]))
            ordinal = standing["class"]["ordinal"]
            folded_into[ordinal] += [m["class"]["ordinal"] for m in group if m["class"]["ordinal"] != ordinal]
            representatives.append(standing)

        def strictly(lhs, rhs):
            return self.holds(lhs, rhs) and not self.holds(rhs, lhs)
        maximal = [rep for rep in representatives if not any(strictly(other, rep) for other in representatives)]
        maximal_ordinals = {rep["class"]["ordinal"] for rep in maximal}
        for rep in representatives:
            if rep["class"]["ordinal"] in maximal_ordinals:
                continue
            holders = [other for other in maximal if strictly(other, rep)]
            if not holders:
                continue
            holder = min(holders, key=lambda other: (-other["class"]["mass"], kind_rank(other["class"]),
                                                     other["class"]["ordinal"]))
            ordinal = rep["class"]["ordinal"]
            folded_into[holder["class"]["ordinal"]] += [ordinal] + folded_into[ordinal]
        return [(rep, sorted(folded_into[rep["class"]["ordinal"]]))
                for rep in sorted(maximal, key=lambda rep: rep["class"]["ordinal"])]

    def uneven_clone_mutation(self):
        limits = self.limits["uneven-clone-mutation"]
        high, low, minimum = limits["high"], limits["low"], int(limits["mutants"])
        families, by_key = self.families()
        anchored = defaultdict(list)
        for row in self.store.mutants:
            if row["place"] in MAPPED_PLACES and row["anchorLine"] is not None:
                anchored[nfc(row["path"])].append(row)
        counts = {"copies": 0, "generated": 0, "without": 0, "few": 0, "fewCopies": 0}
        members = []
        for clone in self.store.clone_classes:
            copies = []
            for instance in clone["instances"]:
                counts["copies"] += 1
                if instance["file"] in self.store.generated_files:
                    counts["generated"] += 1
                    continue
                if self.store.dispositions.get(nfc(instance["file"])) in ("unresolved", "unlisted"):
                    counts["without"] += 1
                    continue
                start = (instance["startLine"], instance["startColumn"])
                end = (instance["endLine"], instance["endColumn"])
                held = [row for row in anchored[nfc(instance["file"])]
                        if start <= (row["anchorLine"], row["anchorColumn"]) <= end]
                tally = record_counts(held)
                scored = sum(tally[verdict] for verdict in ("killed",) + UNKILLED)
                if scored < minimum:
                    counts["few"] += 1
                    continue
                copies.append({"file": instance["file"], "startLine": instance["startLine"],
                               "endLine": instance["endLine"], "stripped": instance["strippedLines"],
                               "family": self.family_of(instance, families, by_key), "killed": tally["killed"],
                               "scored": scored, "unchecked": tally["survived"] + tally["timedOut"],
                               "unrun": tally["noCoverage"] + tally["notCovered"],
                               "unkilled": {mutant_key(row) for row in held if row["verdict"] in UNKILLED}})
            if len(copies) < MINIMUM_COPIES:
                counts["fewCopies"] += 1
                continue
            poor = [copy for copy in copies if copy["killed"] * 100 <= low * copy["scored"]]
            if poor and any(copy["killed"] * 100 >= high * copy["scored"] for copy in copies):
                members.append({"class": clone, "copies": copies, "poor": poor})
        kept = self.folded(members)
        items, counting = [], defaultdict(int)
        for member, folded in kept:
            unkilled = set().union(*(copy["unkilled"] for copy in member["poor"]))
            for key in unkilled:
                counting[key] += 1
            unchecked = any(copy["unchecked"] > 0 for copy in member["poor"])
            subject = sorted(member["poor"], key=lambda copy: (share_key(copy["killed"], copy["scored"]),
                                                               -(copy["scored"] - copy["killed"]), copy["file"],
                                                               copy["startLine"]))[0]
            clone = member["class"]
            kind = KIND_ORDER.index("near-miss" if clone["pass"] == "near-miss" else "sequence"
                                    if clone["pass"] == "sequence" else "exact" if clone["exact"] else "renamed")
            payload = {"clone": {"ordinal": clone["ordinal"], "pass": clone["pass"], "exact": clone["exact"] == 1,
                                 "mass": clone["mass"], "lines": sum(copy["stripped"] for copy in member["poor"]),
                                 "copies": len(member["copies"]),
                                 "mutation": {"folded": folded, "copies": [
                                     {"file": copy["file"], "line": copy["startLine"], "family": copy["family"],
                                      "killed": copy["killed"], "scored": copy["scored"],
                                      "runButUnchecked": copy["unchecked"], "unrun": copy["unrun"]}
                                     for copy in member["copies"]]}},
                       "mutation": None, "coverage": None, "ratio": None, "property": None, "propertyTarget": None}
            items.append(((0 if unchecked else 1, -len(unkilled), -clone["mass"], kind, subject["family"],
                           subject["file"], subject["startLine"], clone["ordinal"]),
                          {"function": {"key": subject["family"], "file": subject["file"],
                                        "startLine": subject["startLine"]},
                           "score": len(unkilled), "payload": payload, "unchecked": unchecked}))
        items.sort(key=lambda item: item[0])
        classes = len(self.store.clone_classes)
        pooled = classes - counts["fewCopies"]
        measured = counts["copies"] - counts["generated"] - counts["without"] - counts["few"]
        folded_count = sum(len(folded) for _, folded in kept)
        unchecked = sum(1 for _, entry in items if entry["unchecked"])
        shared = sum(1 for number in counting.values() if number > 1)
        numbers = [high, low, minimum, low,
                   counts["copies"], classes, counts["generated"], counts["without"], counts["few"], minimum,
                   measured, classes, pooled, MINIMUM_COPIES, counts["fewCopies"], pooled, len(members), high, low,
                   pooled - len(members), len(members), len(kept), folded_count, len(kept), unchecked,
                   len(kept) - unchecked, shared]
        return [entry for _, entry in items], pooled, numbers

    def ordered(self, items):
        items.sort(key=lambda item: item[:5])
        return [{"function": item[6]["function"], "score": item[5], "payload": without_nulls(self.payload(item[6]))}
                for item in items]

    # Requirements
    def left_out(self, name):
        if self.store.schema < FIRST_M6_SCHEMA or "swiftmutator" not in self.store.collectors:
            return "the snapshot predates M6"
        for collector in SIGNAL_COLLECTORS[name]:
            run = self.store.collectors.get(collector)
            if run is None:
                return "the snapshot predates M4"
            if run["state"] != "ran":
                return f"needs {collector}: {run['state']}" + (f", {run['reason']}" if run["reason"] else "")
        if name == "genuinely-under-tested" and self.store.scan is not None and not self.store.scan["listsNotCovered"]:
            return NOT_LISTED_REASON
        if self.store.scan is None:
            return "the snapshot holds no mutation rows"
        if "coverage" in SIGNAL_COLLECTORS[name] and not self.store.coverage_run:
            return "the snapshot holds no coverage rows"
        return None


class SignalChecks(Checker):
    def thresholds(self, report, limits):
        self.section("t   thresholds: report 5 lists the limits this script uses")
        self.result("report schema", report.get("schemaVersion") == REPORT_SCHEMA,
                    f"expected {REPORT_SCHEMA}, got {report.get('schemaVersion')}")
        listed = (report.get("thresholds") or {}).get("limits")
        self.result("mutation limits", listed == limits, f"expected {limits}, got {listed}")

    def requirements(self, model, signals):
        self.section("s   requirements: each signal is computed, or left out with the reason its inputs give")
        for name in SIGNAL_COLLECTORS:
            expected = model.left_out(name)
            actual = signals[name].get("leftOut")
            self.result(f"{name} left out", expected == actual, f"expected {expected!r}, got {actual!r}")

    def ratios(self, model):
        self.section("r   line ratios: the stored roll-ups' equal the scan's targets, tests and files")
        if model.derived_ratios is None:
            print("    (no scan in the report; skipped)")
            return
        derived, project = model.derived_ratios
        differences = [f"{name}: stored {model.ratios.get(name)}, derived {derived[name]}"
                       for name in sorted(derived) if model.ratios.get(name) != derived[name]]
        if project != model.project:
            differences.append(f"project: stored {model.project}, derived {project}")
        self.result("module and project ratios", not differences, f"{len(derived)} modules")
        self.listing(differences)
        self.result("production modules", sorted(derived) == model.modules, f"{model.modules}")
        for module in model.modules:
            print(f"    {module}: {model.ratios.get(module)} ({model.standing(module)}); project {model.project}")

    def signal(self, name, signal, expected, candidates, numbers):
        letter = {"weak-tests": "w", "genuinely-under-tested": "g", "best-property-target": "p",
                  "uneven-clone-mutation": "u"}[name]
        self.section(f"{letter}   {name}: items, scores, order, payloads and funnel by the rule")
        items = signal.get("items", [])
        self.result("candidates", signal.get("candidates") == candidates,
                    f"expected {candidates}, got {signal.get('candidates')}")
        rule = signal.get("rule", "")
        if name in ("weak-tests", "best-property-target", "uneven-clone-mutation"):
            noted = rule.endswith(WEAK_NOT_LISTED_NOTE)
            listed = bool(self.lists_not_covered)
            self.result("note on results not listing code no test ran", noted != listed, f"listsNotCovered {listed}")
            rule = rule.removesuffix(WEAK_NOT_LISTED_NOTE)
        rule_numbers = [float(text) for text in NUMBER.findall(rule)]
        self.result("rule and funnel numbers", rule_numbers == [float(number) for number in numbers],
                    f"expected {numbers}, got {rule_numbers}")
        listed = [(item["subject"], item["file"], item["line"]) for item in items]
        wanted = [(entry["function"]["key"], entry["function"]["file"], entry["function"]["startLine"])
                  for entry in expected]
        self.result("listed items in order", listed == wanted, f"{len(wanted)} items")
        if listed != wanted:
            self.listing([f"expected {w}, got {g}" for w, g in zip(wanted, listed) if w != g]
                         + [f"missing {w}" for w in wanted[len(listed):]] + [f"extra {g}" for g in listed[len(wanted):]])
        differences = []
        for rank, (item, entry) in enumerate(zip(items, expected), start=1):
            label = f"#{rank} {item['subject']}"
            if item.get("rank") != rank or not item.get("member"):
                differences.append(f"{label}: rank {item.get('rank')} member {item.get('member')}")
            if item.get("score") != entry["score"]:
                differences.append(f"{label}: score {item.get('score')} != {entry['score']}")
            for field, value in entry["payload"].items():
                if item.get(field) != value:
                    differences.append(f"{label}: {field} {json.dumps(item.get(field), sort_keys=True)} != "
                                       f"{json.dumps(value, sort_keys=True)}")
        self.result("scores, ranks and payloads", not differences, f"{len(expected)} items")
        self.listing(differences)
        for entry in expected[:LIMIT]:
            clone = entry["payload"].get("clone")
            if clone is not None:
                copies = ", ".join(f"{copy['killed']}/{copy['scored']}" for copy in clone["mutation"]["copies"])
                print(f"    {entry['score']:>4} {entry['function']['key']} ({entry['function']['file']}:"
                      f"{entry['function']['startLine']}) class #{clone['ordinal']} {clone['pass']} mass "
                      f"{clone['mass']}, copies {copies}, folded {clone['mutation']['folded']}")
                continue
            payload = entry["payload"]["mutation"]
            target = entry["payload"].get("propertyTarget")
            detail = (f"lines {entry['payload']['coverage']['lines']}" if target is None else
                      f"{len(target['unkilled'])} unkilled, partners {[p['key'] for p in target['partners']]}, "
                      f"suggestions {[(s['template'], s['tier']) for s in target['suggestions']]}")
            print(f"    {entry['score']:>4} {entry['function']['key']} ({entry['function']['file']}:"
                  f"{entry['function']['startLine']}) killed {payload['functionScore']['killed']}/"
                  f"{payload['functionScore']['scored']}, {detail}")


def signal_limits(settings):
    limits = {name: dict(values) for name, values in DEFAULT_LIMITS.items()}
    for setting in settings or []:
        key, _, value = setting.partition("=")
        signal, _, limit = key.rpartition(".")
        if signal not in limits or not value:
            fail(f"--set {setting}: expected <signal>.<limit>=<value> for weak-tests, genuinely-under-tested or "
                 "uneven-clone-mutation")
        if limit not in LIMIT_NAMES[signal]:
            fail(f"--set {setting}: {signal} has no limit {limit}; its limits are {', '.join(LIMIT_NAMES[signal])}")
        limits[signal][limit] = float(value)
    return limits


def signals(arguments):
    with open(arguments.report) as handle:
        report = json.load(handle)
    by_name = {signal["name"]: signal for signal in report.get("signals", [])}
    for name in SIGNAL_COLLECTORS:
        if name not in by_name:
            fail(f"{arguments.report} lists no {name} signal")
    store = SignalStore(arguments.store, report["snapshot"])
    limits = signal_limits(arguments.set)
    model = SignalModel(store, limits, report.get("scan"))
    checker = SignalChecks(arguments.all)
    checker.lists_not_covered = store.scan["listsNotCovered"] if store.scan else None
    print(f"snapshot {store.id} of {report['snapshot']['package']} at {report['snapshot']['git'].get('commit')}")
    checker.thresholds(report, limits)
    checker.requirements(model, by_name)
    checker.ratios(model)
    if model.left_out("weak-tests") is None:
        items, candidates, numbers = model.weak_tests()
        checker.signal("weak-tests", by_name["weak-tests"], items, candidates, numbers)
    if model.left_out("genuinely-under-tested") is None:
        items, candidates, numbers, single = model.genuinely_under_tested()
        checker.signal("genuinely-under-tested", by_name["genuinely-under-tested"], items, candidates, numbers)
        rule = by_name["genuinely-under-tested"].get("rule", "")
        sentence = "one production module: its ratio is the project's, so no function can be listed"
        checker.result("single-module sentence", (sentence in rule) == single, f"expected {single}")
    if model.left_out("best-property-target") is None:
        items, candidates, numbers = model.best_property_target()
        checker.signal("best-property-target", by_name["best-property-target"], items, candidates, numbers)
    if model.left_out("uneven-clone-mutation") is None:
        items, candidates, numbers = model.uneven_clone_mutation()
        checker.signal("uneven-clone-mutation", by_name["uneven-clone-mutation"], items, candidates, numbers)
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
    merging = modes.add_parser("merge", help="check a --since snapshot's merge of both results files")
    merging.add_argument("package")
    merging.add_argument("scan")
    merging.add_argument("--base-results", help="the base's results file (default: the carried run's resultsFile)")
    merging.add_argument("--base-report", help="its JSON report (default: report.json beside it)")
    merging.add_argument("--since-report", help="the since run's JSON report (default: report.json beside it)")
    merging.add_argument("--store", help="also compare the snapshot's stored rows in this store (store v5)")
    merging.add_argument("--all", action="store_true", help="list every difference")
    sincing = modes.add_parser("since", help="check a --since snapshot against its base in the store")
    sincing.add_argument("package")
    sincing.add_argument("scan")
    sincing.add_argument("--store", required=True, help="the store holding the --since snapshot")
    sincing.add_argument("--base-store", help="the store holding the base snapshot (default: --store)")
    sincing.add_argument("--dirty", action="store_true", help="the --since snapshot is of a dirty tree")
    sincing.add_argument("--confirmed-flips", help="killed/timedOut flips a solo rerun confirmed, one key a line")
    sincing.add_argument("--all", action="store_true", help="list every difference")
    signalling = modes.add_parser("signals", help="re-derive the M6 signals from the store")
    signalling.add_argument("report", help="`swiftstats report --format json` of the snapshot")
    signalling.add_argument("--store", required=True, help="the store holding the snapshot")
    signalling.add_argument("--set", action="append", metavar="SIGNAL.LIMIT=VALUE",
                            help="a limit the report's configuration sets, such as weak-tests.score=40")
    signalling.add_argument("--all", action="store_true", help="list every difference")
    arguments = parser.parse_args()
    return {"base": base, "merge": merge, "since": since, "signals": signals}[arguments.mode](arguments)


if __name__ == "__main__":
    sys.exit(main())
