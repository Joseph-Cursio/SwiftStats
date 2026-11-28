#!/usr/bin/env python3
"""Check a `swiftstats scan --coverage` result independently (M5 done-when).

The coverage collector maps llvm-cov's export onto the scan's records. This
script checks that mapping without using any of SwiftStats' code: it reads
the scan JSON, the export the collector left in the package's coverage
build directory, and what llvm-cov itself prints, and runs these checks
(PRD M5 design, section 9):

  1a  every kept file's per-line data equals `llvm-cov export -format=lcov`
      DA lines: the same lines, the same counts (saturated counts, which lcov
      prints as UInt64, read as Int64.max).
  1b  every mapped line of a kept file lies in some record's line span or in
      exactly one attachment, and the attachments' line figures are exactly
      the mapped lines outside every record's span. Records' own line
      figures are not summed: by llvm-cov's per-function rule a line shared
      by sibling one-line accessors counts for each of them. Every line a
      record counts is a mapped line of its file.
  1c  `llvm-cov report -show-functions` agrees: this script's per-function
      figures equal it for every entry of a kept file (so its line rule is
      llvm-cov's); records made of one entry equal it exactly, parents of
      nested records equal it minus the lines given to the nested records,
      and every record's regions equal its entries' rows minus the regions
      dropped as same-range duplicates.
  1d  the demangled name of every entry mapped to a record agrees with the
      record's key: its innermost context that isn't a closure or default
      argument has the record's type path, base name, argument labels and
      accessor kind; a local function or a local type's member also names
      the record it is nested in, and a local type's stored property
      initializer the record holding the type. Every exception is listed.
  1e  a reimplementation of the mapping rules (design section 2) gives
      exactly the scan JSON's `coverage`: records, attachments, unmapped
      entries, dropped files, bundles, saturation and per-file lines.
  2   unmapped entries are listed, and at least 95% of the code regions of
      kept files' entries that fall inside records are mapped; attached
      entries and entries of unscanned files are counted separately.

The reimplementation follows the design's words and llvm's own algorithms
(SegmentBuilder and LineCoverageIterator in CoverageMapping.cpp), not
SwiftStats' Swift code. One input is approximate: a file with top-level code
needs its top-level statement lines, which this script finds with a small
tokenizer (`statement_lines`); no other file needs them.

Usage:
    Scripts/coverage-check.py <package-dir> <scan.json> [--tools <bin dir>]
                              [--build <coverage build dir>] [--all]
                              [--dump <path>]

<scan.json> is `swiftstats scan --coverage --format json` of <package-dir>,
run right before, so the build directory still holds that run's export,
profiles and test bundles. Tools are found as the collector finds them: the
toolchain of `swift -print-target-info` run in the package, its llvm-cov and
llvm-profdata when both are there, else `xcrun --find`; `--tools` names a
directory holding llvm-cov, llvm-profdata and swift instead. The test
bundles are those in `swift build --show-bin-path` of the build directory,
and each test process's profile (`<signature>.profdata`, which the collector
leaves there) is tied to the bundle whose test module's functions it ran. `--all` lists
every difference instead of the first 20 of each kind; `--dump` writes the
reimplementation's coverage report as JSON.

Exit status is 0 when every check passes, 1 when one fails, 2 on bad input.
"""

import argparse
import glob
import json
import os
import re
import subprocess
import sys
import unicodedata
from collections import defaultdict

INT64_MAX = 2**63 - 1
BUILD_DIRECTORY = ".swiftstats/coverage-build"
CODE, EXPANSION, SKIPPED, GAP = 0, 1, 2, 3
LIMIT = 20

NO_DATA = "no coverage data"
NOT_LINKED = "not linked into any test bundle"
EXPANSION_REASON = "macro or expansion region"
NO_CODE = "no code region"
PAST_RECORD = "region extends past its record"


# --------------------------------------------------------------------------
# Small helpers


def fail(message):
    print(f"error: {message}", file=sys.stderr)
    sys.exit(2)


def clamp(count):
    """A count as Int64: anything above Int64.max is saturated."""
    return min(int(count), INT64_MAX)


def run(command, cwd=None, stdin=None):
    result = subprocess.run(command, cwd=cwd, input=stdin, capture_output=True, text=True)
    if result.returncode != 0:
        fail(f"{' '.join(command[:3])} … failed ({result.returncode}):\n{result.stderr[-2000:]}")
    return result.stdout


def c99_name(name):
    """SwiftPM's module name for a target name."""
    text = re.sub(r"[^\w]", "_", name)
    return "_" + text[1:] if text[:1].isdigit() else text


# The line breaks of PRD §10.1's globs (U+000A to U+000D, U+0085, U+2028
# and U+2029): `**` and the folder extension stop at one, and one ending the
# path is ignored, `\r\n` counting as one.
LINE_BREAKS = "\n\x0b\x0c\r\x85\u2028\u2029"
# Any run of characters but line breaks: what `**` matches.
ANY_RUN = "[^" + LINE_BREAKS + "]*"
# One line break, or none, ending the path: PRD §10.1's end rule. A `\n`
# after `\r` is the end of `\r\n`, so it can't be the break alone.
FINAL_BREAK = "(?:\r\n|(?<!\r)\n|[\x0b\x0c\r\x85\u2028\u2029])?"


# Scalars that join the scalar before them into one Character (an extended
# grapheme cluster, UAX #29's Extend, ZWJ and SpacingMark), as far as the
# standard library, which has no grapheme segmentation, can tell: marks
# (Mn, Me, Mc, less the Mc letters UAX #29 leaves out), U+200C, U+200D, the
# halfwidth sound marks, the emoji modifiers, the tag characters, and the
# two vowel signs filed under Lo that UAX #29 counts as spacing marks.
MARK_CATEGORIES = ("Mn", "Me", "Mc")
NOT_SPACING_MARKS = set(
    "\u102b\u102c\u1038\u1062\u1063\u1064\u1067\u1068\u1069\u106a\u106b\u106c\u106d\u1083\u1087"
    "\u1088\u1089\u108a\u108b\u108c\u108f\u109a\u109b\u109c\u1a61\u1a63\u1a64\uaa7b\uaa7d"
    "\U00011720\U00011721"
)
OTHER_JOINERS = set("\u200c\u200d\uff9e\uff9f\u0e33\u0eb3")
# Scalars that join the scalar after them (UAX #29's Prepend).
PREPEND = set(
    "\u0600\u0601\u0602\u0603\u0604\u0605\u06dd\u070f\u0890\u0891\u08e2\u0d4e"
    "\U000110bd\U000110cd\U000111c2\U000111c3\U0001193f\U00011941\U00011a3a\U00011a84\U00011a85"
    "\U00011a86\U00011a87\U00011a88\U00011a89\U00011d46\U00011f02"
)


def joins_before(char):
    """Whether `char` joins the scalar before it into one Character."""
    if char in OTHER_JOINERS or "\U0001f3fb" <= char <= "\U0001f3ff" or "\U000e0020" <= char <= "\U000e007f":
        return True
    return unicodedata.category(char) in MARK_CATEGORIES and char not in NOT_SPACING_MARKS


def is_control(char):
    """Whether `char` is a control for UAX #29, which nothing joins: Cc,
    Zl, Zp and the format characters that don't join."""
    category = unicodedata.category(char)
    if category == "Cf":
        return char not in PREPEND and not joins_before(char)
    return category in ("Cc", "Zl", "Zp")


def characters(text):
    """`text` in Characters, as Swift reads it, for the joins that decide
    whether a `*`, `?`, `.` or `/` stands alone: a scalar after CR is one
    with it when it is LF; otherwise nothing joins a control or joins one;
    a mark, a joiner or a spacing mark joins the scalar before it, and a
    prepended scalar the one after it. Hangul syllables, flags and emoji
    sequences, which never hold those four, aren't joined."""
    read = []
    for char in text:
        if read:
            last = read[-1][-1]
            if last == "\r" and char == "\n":
                read[-1] += char
                continue
            if not is_control(last) and not is_control(char) and (joins_before(char) or last in PREPEND):
                read[-1] += char
                continue
        read.append(char)
    return read


def glob_regex(pattern):
    """A configuration glob (`**`, `*`, `?`) as a regular expression, read as
    PRD §10.1 says: one leading `./` and any trailing `/` are ignored, and
    every match extends to the paths under it, so `Gen*` matches
    `Generated/x.swift`. `**` and that extension stop at a line break, and
    one line break ending the path is ignored, CR LF counting as one. The
    glob is read in Characters (`characters`, an approximation of Swift's
    grapheme breaking from the standard library's Unicode data), so a `*`,
    `?` or `/` that a mark joins is ordinary text, in `./` and `**/` too;
    `?` matches one scalar of the path."""
    read = characters(pattern)
    if read[:2] == [".", "/"]:
        read = read[2:]
    while read and read[-1] == "/":
        read.pop()
    out = ""
    index = 0
    while index < len(read):
        if read[index:index + 3] == ["*", "*", "/"]:
            out += "(?:" + ANY_RUN + "/)?"
            index += 3
        elif read[index:index + 2] == ["*", "*"]:
            out += ANY_RUN
            index += 2
        elif read[index] == "*":
            out += "[^/]*"
            index += 1
        elif read[index] == "?":
            out += "[^/]"
            index += 1
        else:
            out += re.escape(read[index])
            index += 1
    return re.compile(out + "(?:/" + ANY_RUN + ")?" + FINAL_BREAK + r"\Z")


class Region:
    """One export region: start and end (line, column), the end exclusive."""

    __slots__ = ("start", "end", "count", "file_id", "expanded_id", "kind")

    def __init__(self, raw):
        self.start = (raw[0], raw[1])
        self.end = (raw[2], raw[3])
        self.count = clamp(raw[4])
        self.file_id = raw[5]
        self.expanded_id = raw[6]
        self.kind = raw[7]

    def with_count(self, count):
        return Region([*self.start, *self.end, count, self.file_id, self.expanded_id, self.kind])


# --------------------------------------------------------------------------
# llvm's SegmentBuilder and LineCoverageIterator (CoverageMapping.cpp)
#
# A segment is (line, column, count, has_count, is_region_entry, is_gap).


def build_segments(regions, combine):
    """Segments of `regions`. `combine` merges the counts of two regions of
    one range and kind: llvm sums them; a record's regions are deduplicated
    by range keeping the largest count."""
    ordered = sorted(regions, key=lambda r: (r.start, (-r.end[0], -r.end[1]), r.kind))
    combined = []
    for region in ordered:
        if combined and combined[-1].start == region.start and combined[-1].end == region.end:
            if combined[-1].kind == region.kind:
                combined[-1] = combined[-1].with_count(combine(combined[-1].count, region.count))
            continue
        combined.append(region)

    segments = []
    active = []

    def start_segment(region, location, is_entry, emit_skipped=False):
        has_count = not emit_skipped and region.kind != SKIPPED
        if segments and not is_entry and not emit_skipped:
            last = segments[-1]
            if last[3] == has_count and last[2] == region.count and not last[4]:
                return
        if has_count:
            segments.append((location[0], location[1], region.count, True, is_entry, region.kind == GAP))
        else:
            segments.append((location[0], location[1], 0, False, is_entry, False))

    def complete_until(location, first_completed):
        nonlocal active
        active = active[:first_completed] + sorted(active[first_completed:], key=lambda r: r.end)
        for index in range(first_completed + 1, len(active)):
            completed = active[index]
            segment_location = active[index - 1].end
            if location is not None and segment_location == location:
                break
            if segment_location == completed.end:
                continue
            for later in active[index + 1:]:
                if later.end == completed.end:
                    completed = later
            start_segment(completed, segment_location, False)
        last = active[-1]
        if first_completed and last.end != location:
            start_segment(active[first_completed - 1], last.end, False)
        elif not first_completed and (location is None or location != last.end):
            start_segment(last, last.end, False, True)
        del active[first_completed:]

    for index, region in enumerate(combined):
        start = region.start
        still = [r for r in active if not r.end <= start]
        done = [r for r in active if r.end <= start]
        if done:
            active = still + done
            complete_until(start, len(still))
        is_gap = region.kind == GAP
        if start == region.end:
            skipped = index + 1 == len(combined) or region.kind == SKIPPED
            start_segment(active[-1] if active else region, start, not is_gap, skipped)
            if skipped and active:
                start_segment(active[-1], start, False)
            continue
        if index + 1 == len(combined) or start != combined[index + 1].start:
            start_segment(region, start, not is_gap)
        active.append(region)
    if active:
        complete_until(None, 0)
    return segments


def segments_of(raw_segments):
    """Export file segments as (line, column, count, has_count, entry, gap)."""
    return [(s[0], s[1], clamp(s[2]), bool(s[3]), bool(s[4]), bool(s[5])) for s in raw_segments]


def misordered(raw_segments):
    """The first adjacent export segments whose second lies before the first
    by (line, column), or None when they are sorted. SwiftStats fails the
    collector on such a file, and line_stats would never return on it."""
    for earlier, later in zip(raw_segments, raw_segments[1:]):
        if (later[0], later[1]) < (earlier[0], earlier[1]):
            return earlier, later
    return None


def line_stats(segments):
    """llvm-cov's line rule: {line: (count, partly_run)} for mapped lines."""
    result = {}
    if not segments:
        return result
    index = 0
    wrapped = None
    current = []
    line = segments[0][0]
    while index < len(segments):
        if current:
            wrapped = current[-1]
        current = []
        while index < len(segments) and segments[index][0] == line:
            current.append(segments[index])
            index += 1
        starts = [s for s in current if not s[5] and s[3] and s[4]]
        starts_skipped = bool(current) and not current[0][3] and current[0][4]
        mapped = (not starts_skipped and ((wrapped is not None and wrapped[3]) or bool(starts)))
        mapped = mapped or any(s[4] and s[3] for s in current)
        if mapped:
            count = wrapped[2] if wrapped is not None else 0
            for segment in starts:
                count = max(count, segment[2])
            partly = count > 0 and any(s[4] and s[3] and s[2] == 0 for s in current)
            result[line] = (count, partly)
        line += 1
    return result


def tally(counts):
    counts = list(counts)
    return {"covered": sum(1 for c in counts if c > 0), "total": len(counts)}


def deduplicated(regions):
    """Regions of one range merged into one with the largest count."""
    by_range = {}
    for region in regions:
        key = (region.start, region.end)
        if key not in by_range or region.count > by_range[key].count:
            by_range[key] = region
    return [by_range[key] for key in sorted(by_range)]


def runs(lines):
    """{line: (count, partly)} as the scan JSON's runs."""
    out = []
    for line in sorted(lines):
        count, partly = lines[line]
        if out and out[-1]["end"] + 1 == line and out[-1]["count"] == count and out[-1]["partlyRun"] == partly:
            out[-1]["end"] = line
        else:
            out.append({"count": count, "end": line, "partlyRun": partly, "start": line})
    return out


def expand_runs(file_runs):
    lines = {}
    for run_ in file_runs:
        for line in range(run_["start"], run_["end"] + 1):
            lines[line] = (run_["count"], run_["partlyRun"])
    return lines


# --------------------------------------------------------------------------
# Source reading: top-level statement lines and file-scoped types

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


RAW_STRING = re.compile(r'#+"')
HASHES = re.compile(r"#*")
WORD = re.compile(r"[#@$`]?[\w`]*")


def tokens(text):
    """(line, token) pairs of Swift source: comments and strings skipped
    (a string is one token), brackets and newlines kept as tokens."""
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
        elif char in " \t\r\ufeff":
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
    to its last; declarations and compiler directives are not statements."""
    lines = set()
    items = []
    current = []
    depth = 0
    toks = tokens(text)
    # The next token that isn't a newline, for each position.
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
    directly or by nesting in one (a private extension makes the types in
    it file-scoped, not the extended type)."""
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
        o_start = (outer["range"]["start"]["line"], outer["range"]["start"]["column"])
        o_end = (outer["range"]["end"]["line"], outer["range"]["end"]["column"])
        i_start = (inner["range"]["start"]["line"], inner["range"]["start"]["column"])
        return o_start < i_start <= o_end

    ordered = sorted(
        (t for t in types if not t.get("isLocal")),
        key=lambda t: (t["range"]["start"]["line"], t["range"]["start"]["column"]),
    )
    for record in ordered:
        if record["kind"] == "extension":
            if modifiers_of(record):
                private_extensions.append(record)
            continue
        scoped = (
            modifiers_of(record)
            or is_file_scoped(record["name"], paths)
            or any(contains(extension, record) for extension in private_extensions)
        )
        if scoped:
            paths.add(record["name"])
    return paths


def is_file_scoped(name, paths):
    prefix = ""
    for component in name.split("."):
        prefix = component if not prefix else prefix + "." + component
        if prefix in paths:
            return True
    return False


# --------------------------------------------------------------------------
# Inputs


class Package:
    """The scan, the export and where the tools and build products are."""

    def __init__(self, root, scan_path, build, tools):
        self.root = os.path.abspath(root)
        self.real_root = os.path.realpath(root)
        with open(scan_path) as handle:
            self.scan = json.load(handle)
        self.coverage = self.scan.get("coverage")
        if self.coverage is None:
            fail(f"{scan_path} has no coverage report; run `swiftstats scan --coverage --format json`")
        self.build = os.path.abspath(build or os.path.join(self.root, BUILD_DIRECTORY))
        export_path = os.path.join(self.build, "swiftstats-export.json")
        self.profdata = os.path.join(self.build, "swiftstats.profdata")
        with open(export_path) as handle:
            document = json.load(handle)
        if document.get("type") != "llvm.coverage.json.export" or document.get("version") != "3.0.1":
            fail(f"{export_path} is not an llvm-cov 3.0.1 export")
        if len(document["data"]) != 1:
            fail(f"{export_path} holds {len(document['data'])} data elements")
        self.export = document["data"][0]
        for file in self.export["files"]:
            pair = misordered(file["segments"])
            if pair is not None:
                earlier, later = pair
                fail(f"{export_path}: the segments of {file['filename']} go back "
                     f"({later[0]}:{later[1]} after {earlier[0]}:{earlier[1]}), which SwiftStats rejects")
        self.tools = tools or self.find_tools()
        self.bundles = self.find_bundles()

        self.records = [r for r in self.scan["records"] if r["role"] == "production"]
        self.records_by_file = defaultdict(list)
        for record in self.records:
            self.records_by_file[record["file"]].append(record)
        self.record_by_key = {r["key"]: r for r in self.records}
        self.types_by_file = defaultdict(list)
        for record in self.scan.get("types", []):
            self.types_by_file[record["file"]].append(record)
        self.parsed = {f["path"] for f in self.scan["files"]}
        configuration = self.scan.get("configuration", {})
        self.excluded_files = set(configuration.get("excludedFiles", []))
        self.excluded_globs = [glob_regex(p) for p in configuration.get("excluded", [])]
        self.targets = sorted(
            ((self.directory(t["path"]), t) for t in self.scan["targets"]),
            key=lambda pair: (-len(pair[0]), pair[0]),
        )
        self.root_spellings = self.spellings(self.root)
        self.build_spellings = sorted(
            {spelling + "/" + BUILD_DIRECTORY for spelling in self.root_spellings}
            | set(self.spellings(self.build)),
            key=lambda s: (-len(s), s),
        )
        accessor_parents = {r["key"].rsplit(" / {", 1)[0] for r in self.records
                            if r["kind"] == "accessor" and " / {" in r["key"]}
        self.containers = {r["key"] for r in self.records if r["kind"] == "subscript" and r["key"] in accessor_parents}
        self.sources = {}
        self.statement_cache = {}
        self.scoped_cache = {}

    @staticmethod
    def directory(path):
        path = path[2:] if path.startswith("./") else path
        if path in ("", "."):
            return ""
        return path if path.endswith("/") else path + "/"

    @staticmethod
    def spellings(path):
        found = {os.path.abspath(path), os.path.realpath(path)}
        for spelling in list(found):
            if spelling.startswith("/private/"):
                found.add(spelling[len("/private"):])
            elif re.match(r"/(var|tmp|etc)/", spelling):
                found.add("/private" + spelling)
        return sorted(found, key=lambda s: (-len(s), s))

    def find_tools(self):
        info = json.loads(run(["swift", "-print-target-info"], cwd=self.root))
        toolchain = os.path.realpath(os.path.join(info["paths"]["runtimeResourcePath"], "..", "..", "bin"))
        tools = {"swift": os.path.join(toolchain, "swift")}
        if all(os.access(os.path.join(toolchain, name), os.X_OK) for name in ("llvm-cov", "llvm-profdata")):
            tools["llvm-cov"] = os.path.join(toolchain, "llvm-cov")
            tools["llvm-profdata"] = os.path.join(toolchain, "llvm-profdata")
        else:
            tools["llvm-cov"] = run(["xcrun", "--find", "llvm-cov"]).strip()
            tools["llvm-profdata"] = run(["xcrun", "--find", "llvm-profdata"]).strip()
        return tools

    def find_bundles(self):
        """{bundle name: executable} of the test bundles the build made."""
        binaries = run([self.tools["swift"], "build", "--show-bin-path", "--scratch-path", self.build,
                        "--enable-code-coverage"], cwd=self.root).strip()
        found = {}
        for path in sorted(glob.glob(os.path.join(binaries, "*.xctest"))):
            name = os.path.basename(path)[: -len(".xctest")]
            executable = os.path.join(path, "Contents", "MacOS", name)
            if os.path.exists(executable):
                found.setdefault(name, os.path.realpath(executable))
        if not found:
            fail(f"no test bundle under {self.build}")
        return dict(sorted(found.items()))

    def objects(self):
        """llvm-cov's object arguments: the first bundle, then -object each other."""
        paths = list(self.bundles.values())
        arguments = [paths[0]]
        for path in paths[1:]:
            arguments += ["-object", path]
        return arguments

    def source(self, path):
        if path not in self.sources:
            with open(os.path.join(self.root, path), encoding="utf-8", errors="replace") as handle:
                self.sources[path] = handle.read()
        return self.sources[path]

    def statement_lines(self, path):
        if path not in self.statement_cache:
            self.statement_cache[path] = statement_lines(self.source(path))
        return self.statement_cache[path]

    def type_owner(self, record):
        """How an attachment names a type: `<module>::<name>`, plus
        ` @ <file>` for a file-scoped type."""
        owner = f"{record['module']}::{record['name']}"
        if record.get("isLocal"):
            return owner
        path = record["file"]
        if path not in self.scoped_cache:
            self.scoped_cache[path] = file_scoped_paths(self.types_by_file[path], self.source(path))
        return owner + " @ " + path if is_file_scoped(record["name"], self.scoped_cache[path]) else owner

    def relative(self, path, spellings):
        for spelling in spellings:
            prefix = spelling.rstrip("/") + "/"
            if path.startswith(prefix):
                return path[len(prefix):]
        return None

    def classify(self, filename):
        """(class, relative path, module, reason) of an export file."""
        if self.relative(filename, self.build_spellings) is not None:
            return ("build", None, None, None)
        path = self.relative(filename, self.root_spellings)
        if path is None:
            return ("outsideRoot", None, None, None)
        if path.startswith(".build/"):
            return ("build", None, None, None)
        target = next((t for prefix, t in self.targets if path.startswith(prefix)), None)
        if target is not None and target["isTest"]:
            return ("testFile", path, target["name"], None)
        if not path.endswith(".swift"):
            return ("otherLanguage", None, None, None)
        if target is None:
            return ("otherPackage", None, None, None)
        if path in self.parsed:
            return ("kept", path, target["name"], None)
        excluded = path in self.excluded_files or any(g.match(path) for g in self.excluded_globs)
        return ("unmapped", path, target["name"], "excluded" if excluded else "not parsed")


# --------------------------------------------------------------------------
# The mapping, reimplemented from the design (section 2)


def position(point):
    return (point["line"], point["column"])


def record_range(record):
    return position(record["range"]["start"]), position(record["range"]["end"])


class Mapping:
    """Entries placed on records, types and files, and the figures."""

    def __init__(self, package, demangle):
        self.package = package
        self.demangle = demangle
        self.classes = {}
        self.entries = defaultdict(list)  # record key -> [(name, code, skipped, regions of the entry)]
        self.placed = []  # (function, file, record key) of every entry mapped to a record
        self.attached_regions = defaultdict(lambda: defaultdict(list))
        self.attached_entries = []  # (function, path)
        self.unmapped = []
        self.skipped = defaultdict(set)
        self.saturated = set()
        self.file_lines = {}
        self.map()

    def spans(self, record):
        if record["kind"] == "topLevel":
            return self.package.statement_lines(record["file"])
        return set(range(record["range"]["start"]["line"], record["range"]["end"]["line"] + 1))

    def unmapped_entry(self, function, path, reason):
        first = function["regions"][0] if function["regions"] else [0, 0, 0, 0]
        return {
            "count": clamp(function["count"]), "endColumn": first[3], "endLine": first[2], "file": path,
            "name": function["name"], "reason": reason, "startColumn": first[1], "startLine": first[0],
        }

    def classify(self, filename):
        if filename not in self.classes:
            self.classes[filename] = self.package.classify(filename)
        return self.classes[filename]

    def map(self):
        package = self.package
        for file in package.export["files"]:
            self.classify(file["filename"])
        for function in package.export["functions"]:
            if not function["filenames"]:
                continue
            kind, path, module, reason = self.classify(function["filenames"][0])
            if kind == "unmapped":
                self.unmapped.append(self.unmapped_entry(function, path, reason))
            elif kind == "kept":
                self.place(function, path, module)
        for file in package.export["files"]:
            kind, path, _, _ = self.classes[file["filename"]]
            if kind != "kept":
                continue
            segments = segments_of(file["segments"])
            self.file_lines[path] = line_stats(segments)
            for segment in segments:
                if segment[2] >= INT64_MAX:
                    self.saturated.add((path, segment[0]))

    def place(self, function, path, module):
        regions = [Region(raw) for raw in function["regions"]]
        for region in regions:
            if region.count >= INT64_MAX:
                self.saturated.add((path, region.start[0]))
        skipped = [r for r in regions if r.kind == SKIPPED]
        for region in skipped:
            self.skipped[path].add((region.start[0], region.end[0]))
        expansion = len(function["filenames"]) > 1 or any(
            r.file_id != 0 or r.expanded_id != 0 or r.kind == EXPANSION for r in regions
        )
        code = [r for r in regions if r.kind == CODE]
        if expansion or not code:
            self.unmapped.append(self.unmapped_entry(function, path, EXPANSION_REASON if expansion else NO_CODE))
            return
        records = self.package.records_by_file[path]
        top_level = next((r for r in records if r["kind"] == "topLevel"), None)
        if top_level is not None and function["name"] in (f"{c99_name(module)}_main", "main"):
            statements = self.package.statement_lines(path)
            own = [r for r in code if r.start[0] in statements]
            # No region on a statement line: the record gets no entry (null).
            if own:
                self.entries[top_level["key"]].append((function["name"], own, skipped, regions))
                self.placed.append((function, path, top_level["key"]))
            # Statement lines no region spans are in a top-level `#if` with
            # no active clause (the compiler emits nothing): skipped.
            start = None
            for line in sorted(statements) + [None]:
                spanned = line is not None and any(r.start[0] <= line <= r.end[0] for r in regions)
                if line is not None and not spanned and start is not None and line == end + 1:
                    end = line
                    continue
                if start is not None:
                    self.skipped[path].add((start, end))
                    start = None
                if line is not None and not spanned:
                    start = end = line
            rest = [r for r in code if r.start[0] not in statements]
            if rest:
                self.attached_regions[("file", path)][path] += rest
            return
        anchor = code[0].start
        statements = self.package.statement_lines(path) if top_level is not None else set()
        holding = []
        for record in records:
            start, end = record_range(record)
            if start <= anchor <= end and (record["kind"] != "topLevel" or anchor[0] in statements):
                holding.append(record)
        if holding:
            record = min(holding, key=lambda r: (_negated(record_range(r)[0]), record_range(r)[1], r["key"]))
            last = (code[0].end[0], code[0].end[1] - 1)
            if last > record_range(record)[1]:
                self.unmapped.append(self.unmapped_entry(function, path, PAST_RECORD))
                return
            self.entries[record["key"]].append((function["name"], code, skipped, regions))
            self.placed.append((function, path, record["key"]))
            return
        holding_types = []
        for record in self.package.types_by_file[path]:
            start, end = record_range(record)
            if start <= anchor <= end:
                holding_types.append(record)
        if holding_types:
            record = min(holding_types, key=lambda r: (_negated(record_range(r)[0]), record_range(r)[1], r["name"]))
            key = ("type", self.package.type_owner(record))
        else:
            key = ("file", path)
        self.attached_regions[key][path] += code
        self.attached_entries.append((function, path))

    # ---- figures

    def linked_modules(self):
        return {module for kind, _, module, _ in self.classes.values() if kind in ("kept", "unmapped")}

    def nested_spans(self, record):
        start, end = record_range(record)
        spans = []
        for other in self.package.records_by_file[record["file"]]:
            o_start, o_end = record_range(other)
            if other["key"] != record["key"] and start <= o_start and o_end <= end:
                spans.append(self.spans(other))
        return spans

    def record_lines(self, record, entries):
        """{line: (count, partly)} by the per-function rule over the
        record's deduplicated regions, minus wrap-only lines in nested
        records."""
        regions = deduplicated([r for entry in entries for r in entry[1]])
        skipped = deduplicated([r for entry in entries for r in entry[2]])
        lines = line_stats(build_segments(regions + skipped, max))
        starts = {r.start[0] for r in regions}
        nested = self.nested_spans(record)
        return {
            line: value for line, value in lines.items()
            if line in starts or not any(line in span for span in nested)
        }, regions

    def report(self, profiles):
        package = self.package
        linked = self.linked_modules()
        containers = package.containers
        records = []
        self.lines_by_record = {}
        for record in sorted(package.records, key=lambda r: r["key"]):
            entries = self.entries.get(record["key"], [])
            if not entries:
                reason = None if record["key"] in containers else (NO_DATA if record["module"] in linked else NOT_LINKED)
                item = {"key": record["key"], "testTargets": []}
                if reason is not None:
                    item["reason"] = reason
                records.append(item)
                continue
            lines, regions = self.record_lines(record, entries)
            self.lines_by_record[record["key"]] = lines
            names = {entry[0] for entry in entries}
            targets = sorted(b for b, counts in profiles.items() if any(counts.get(n, 0) > 0 for n in names))
            records.append({
                "key": record["key"],
                "lines": tally(count for count, _ in lines.values()),
                "regions": tally(r.count for r in regions),
                "testTargets": targets,
            })

        attachment_lines = defaultdict(list)
        self.attachment_lines = defaultdict(set)
        for path in sorted(self.file_lines):
            spanned = set()
            for record in package.records_by_file[path]:
                spanned |= self.spans(record)
            for line, (count, _) in sorted(self.file_lines[path].items()):
                if line in spanned:
                    continue
                key = self.line_owner(path, line)
                attachment_lines[key].append(count)
                self.attachment_lines[key].add((path, line))
        attachments = []
        for key in sorted(set(self.attached_regions) | set(attachment_lines)):
            regions = [r for per_file in self.attached_regions.get(key, {}).values() for r in deduplicated(per_file)]
            attachments.append({
                "attachedTo": key[0], "lines": tally(attachment_lines.get(key, [])), "owner": key[1],
                "regions": tally(r.count for r in regions),
            })

        names = self.demangle(sorted({u["name"] for u in self.unmapped}))
        unmapped = []
        for item in sorted(self.unmapped, key=lambda u: (u["file"], u["startLine"], u["startColumn"], u["name"])):
            item = dict(item)
            if names.get(item["name"]) is not None:
                item["demangled"] = names[item["name"]]
            unmapped.append(item)

        dropped = {"build": 0, "otherLanguage": 0, "otherPackage": 0, "outsideRoot": 0, "testFiles": 0}
        for file in package.export["files"]:
            kind = self.classes[file["filename"]][0]
            key = "testFiles" if kind == "testFile" else kind
            if key in dropped:
                dropped[key] += 1
        return {
            "attachments": attachments,
            "bundles": sorted(package.bundles),
            "dropped": dropped,
            "files": [
                {
                    "file": path,
                    "lines": runs(self.file_lines[path]),
                    "skipped": [{"end": end, "start": start} for start, end in sorted(self.skipped.get(path, ()))],
                }
                for path in sorted(self.file_lines)
            ],
            "records": records,
            "saturated": [{"file": f, "line": l} for f, l in sorted(self.saturated)],
            "unmapped": unmapped,
        }

    def line_owner(self, path, line):
        holding = [
            t for t in self.package.types_by_file[path]
            if t["range"]["start"]["line"] <= line <= t["range"]["end"]["line"]
        ]
        if not holding:
            return ("file", path)
        record = min(holding, key=lambda r: (_negated(record_range(r)[0]), record_range(r)[1], r["name"]))
        return ("type", self.package.type_owner(record))


def _negated(point):
    return (-point[0], -point[1])


# --------------------------------------------------------------------------
# Tools: profiles per test target, demangling, lcov, report


def normalised(name):
    """A profile name without the source path llvm-profdata puts before a
    local-linkage function's mangled name."""
    match = re.search(r"[:;]((?:_?\$s|\$S).*)$", name)
    return match.group(1) if match else name


def profiles_by_bundle(package):
    """{bundle: {mangled name: entry count}} from the per-process profiles
    the collector merged (`<signature>.profdata`), each tied to the bundle
    whose test module's functions it ran most."""
    show = defaultdict(dict)
    for path in sorted(glob.glob(os.path.join(package.build, "*.profdata"))):
        signature = os.path.basename(path)[: -len(".profdata")]
        if not signature.isdigit():
            continue
        name = None
        for line in run([package.tools["llvm-profdata"], "show", "--all-functions", "--counts", path]).splitlines():
            header = re.match(r"^  (\S.*):$", line)
            if header:
                name = normalised(header.group(1))
                continue
            count = re.match(r"^    Function count: (\d+)$", line)
            if count and name is not None:
                show[signature][name] = clamp(count.group(1))
    result = {bundle: {} for bundle in package.bundles}
    for signature, counts in sorted(show.items()):
        hits = {}
        for bundle in package.bundles:
            module = c99_name(bundle)
            prefix = f"$s{len(module)}{module}"
            hits[bundle] = sum(1 for n, c in counts.items() if c > 0 and n.startswith(prefix))
        best = max(hits.values()) if hits else 0
        owners = [b for b, h in hits.items() if h == best]
        if best == 0 or len(owners) != 1:
            fail(f"the profiles with signature {signature} can't be tied to one test bundle: {hits}")
        for name, count in counts.items():
            result[owners[0]][name] = max(result[owners[0]].get(name, 0), count)
    return result


def demangler(package):
    cache = {}

    def demangle(names):
        missing = [n for n in names if n not in cache]
        if missing:
            output = run([package.tools["swift"], "demangle", "--compact"], stdin="\n".join(missing) + "\n")
            lines = output.split("\n")
            for name, text in zip(missing, lines):
                cache[name] = text
        return {n: cache[n] for n in names}

    return demangle


def lcov_lines(package):
    """{export filename: {line: count}} from `llvm-cov export -format=lcov`."""
    output = run([package.tools["llvm-cov"], "export", "-format=lcov", "-instr-profile", package.profdata,
                  *package.objects()])
    files = {}
    current = None
    for line in output.splitlines():
        if line.startswith("SF:"):
            current = files.setdefault(line[3:], {})
        elif line.startswith("DA:") and current is not None:
            number, count = line[3:].split(",")[:2]
            current[int(number)] = clamp(count)
    return files


def report_rows(package, filenames):
    """{mangled name: (regions, missed regions, lines, missed lines)} from
    `llvm-cov report -show-functions` over `filenames`."""
    rows = {}
    for start in range(0, len(filenames), 200):
        output = run([package.tools["llvm-cov"], "report", "-show-functions", "-instr-profile", package.profdata,
                      *package.objects(), *filenames[start:start + 200]])
        for line in output.splitlines():
            parts = line.split()
            if len(parts) < 7 or parts[0] in ("Name", "TOTAL", "File") or parts[0].startswith("-"):
                continue
            try:
                row = (int(parts[1]), int(parts[2]), int(parts[4]), int(parts[5]))
            except ValueError:
                continue
            rows[parts[0]] = row
    return rows


# --------------------------------------------------------------------------
# 1d: names


ACCESSOR_KINDS = {
    "getter": {"get"}, "setter": {"set"}, "modify": {"_modify", "modify"}, "read": {"_read", "read"},
    "willset": {"willSet"}, "didset": {"didSet"}, "unsafeAddressor": {"unsafeAddress"},
    "unsafeMutableAddressor": {"unsafeMutableAddress"}, "init": {"init"},
}


LOCAL_ENTITY = re.compile(r"([A-Za-z_]\w*) #\d+")
INITIALIZER = "variable initialization expression of "


def opens_generic(text, index):
    """Whether the `<` at `index` opens generic arguments: it follows a
    name, a `>` or a `)`, never a `.` (an operator such as `.<`)."""
    return index > 0 and (text[index - 1].isalnum() or text[index - 1] in "_>)")


def split_top(text, separator):
    """`text` split at `separator` where no bracket is open (`->` closes no
    angle bracket)."""
    parts = []
    stack = []
    start = 0
    index = 0
    while index < len(text):
        char = text[index]
        if char in "([":
            stack.append(char)
        elif char in ")]":
            while stack and stack[-1] == "<":
                stack.pop()
            if stack:
                stack.pop()
        elif char == "<" and opens_generic(text, index):
            stack.append("<")
        elif char == ">" and stack and stack[-1] == "<" and text[index - 1] != "-":
            stack.pop()
        if not stack and text.startswith(separator, index):
            parts.append(text[start:index])
            index += len(separator)
            start = index
            continue
        index += 1
    parts.append(text[start:])
    return parts


def strip_generics(text):
    """`text` without generic arguments and clauses."""
    out = []
    depth = 0
    for index, char in enumerate(text):
        if char == "<" and opens_generic(text, index):
            depth += 1
            continue
        if char == ">" and depth and text[index - 1] != "-":
            depth -= 1
            continue
        if not depth:
            out.append(char)
    return "".join(out)


def balanced_group(text, start):
    """The text inside the parentheses opening at `start`, and the index after."""
    depth = 0
    for index in range(start, len(text)):
        depth += text[index] == "("
        depth -= text[index] == ")"
        if depth == 0:
            return text[start + 1:index], index + 1
    return text[start + 1:], len(text)


def labels_of(parameters):
    """Argument labels of a parameter list, `_` where there is none."""
    if not parameters.strip():
        return []
    labels = []
    for parameter in split_top(parameters, ", "):
        match = re.match(r"^\s*([A-Za-z_]\w*|`[^`]+`): ", parameter)
        labels.append(match.group(1).strip("`") if match else "_")
    return labels


def peel(text):
    """`text` without the closures and default-argument wrappers around its
    innermost context."""
    while True:
        match = re.match(r"^(?:implicit closure|closure) #\d+ ", text)
        if match:
            parts = split_top(text[match.end():], " in ")
            if len(parts) < 2:
                return text
            text = " in ".join(parts[1:])
            continue
        match = re.match(r"^default argument \d+ of ", text)
        if match:
            text = text[match.end():]
            continue
        return text


def parse_member(text):
    """The dotted components, parameter text and accessor kind of a
    demangled declaration such as `M.T.f(a: X) -> Y`, `M.T.p.getter : X`
    or `M.T.subscript.getter : (X) -> Y`."""
    text = re.sub(r"^static ", "", text)
    text = re.sub(r"\(([^()\s]+) in _[0-9A-F]+\)", r"\1", text)
    text = strip_generics(text)
    accessor_split = split_top(text, " : ")
    head = accessor_split[0]
    parameters = None
    paren = head.find("(")
    if paren >= 0:
        parameters, _ = balanced_group(head, paren)
        head = head[:paren]
    components = head.split(".")
    accessor = None
    if paren < 0 and len(accessor_split) > 1 and len(components) >= 2 and components[-1] in ACCESSOR_KINDS:
        accessor = components.pop()
        signature = accessor_split[1].strip()
        if components[-1] == "subscript" and signature.startswith("("):
            parameters, _ = balanced_group(signature, 0)
    if components[-1] == "__allocating_init":
        components[-1] = "init"
    return components, parameters, accessor


def parse_qualified(text):
    """A demangled module-level declaration: module, typePath, base, labels
    and accessor. `(extension in M):` names the module; the extended type's
    own module is then the path's first component."""
    text = re.sub(r"^static ", "", text)
    extension = re.match(r"^\(extension in (\w+)\):", text)
    module = extension.group(1) if extension else None
    text = re.sub(r"\(extension in \w+\):", "", text)
    plain = strip_generics(re.sub(r"\(([^()\s]+) in _[0-9A-F]+\)", r"\1", text))
    operator = re.match(r"^((?:[A-Za-z_]\w*\.)+)(\S+) (?:infix|prefix|postfix)\(", plain)
    if operator:
        components = operator.group(1).rstrip(".").split(".")
        return {
            "kind": "function", "module": module or components[0], "typePath": ".".join(components[1:]),
            "base": operator.group(2), "labels": None, "accessor": None,
        }
    components, parameters, accessor = parse_member(text)
    if len(components) < 2:
        return {"kind": "unknown", "text": text}
    return {
        "kind": "accessor" if accessor else "function", "module": module or components[0],
        "typePath": ".".join(components[1:-1]), "base": components[-1],
        "labels": labels_of(parameters) if parameters is not None else None, "accessor": accessor,
    }


def parse_demangled(text):
    """The innermost context of a demangled entry name that isn't a closure
    or default argument, as a dict whose kind is one of:
      function, accessor   a member or global: module, typePath, base,
                           labels (None when not shown), accessor;
      topLevel             top-level code (`<module>_main`, or a closure in
                           it, named by the module alone);
      local                a local function: base, labels (None when not
                           shown), outer (its context);
      localMember          a member of a local type: type, base, labels,
                           accessor, outer (the type's context), also
                           when its signature returns a local type, as a
                           local type's initializer's does;
      localInitializer     a stored property initializer of a local type:
                           outer (the type's context);
      initializer          a stored property initializer: module, typePath,
                           base (the property);
      unknown              anything else: text."""
    text = peel(text)
    if text.startswith(INITIALIZER):
        parts = split_top(text[len(INITIALIZER):], " in ")
        if len(parts) >= 3 and LOCAL_ENTITY.fullmatch(parts[1]):
            return {"kind": "localInitializer", "outer": " in ".join(parts[2:])}
        parsed = parse_qualified(parts[0])
        if parsed["kind"] != "unknown":
            parsed["kind"] = "initializer"
        return parsed
    match = re.match(r"^([A-Za-z_]\w*) #\d+ ", text)
    if match:
        parts = split_top(text[match.end():], " in ")
        signature = skip_generic_signature(parts[0])
        labels = labels_of(balanced_group(signature, 0)[0]) if signature.startswith("(") else None
        return {
            "kind": "local", "base": match.group(1), "labels": labels,
            "outer": " in ".join(parts[1:]) if len(parts) > 1 else "",
        }
    parts = split_top(text, " in ")
    # The member is everything before the first local type after it: a
    # member that returns a local type, as a local type's initializer does,
    # spells that type's context in its signature, `init(name:
    # Swift.String) -> Finder #1 in static M.T.f(…) -> Swift.Bool in
    # Finder #1 in static M.T.f(…) -> Swift.Bool`.
    local = next((index for index in range(1, len(parts) - 1) if LOCAL_ENTITY.fullmatch(parts[index])), None)
    if local is not None:
        components, parameters, accessor = parse_member(" in ".join(parts[:local]))
        return {
            "kind": "localMember", "type": LOCAL_ENTITY.fullmatch(parts[local]).group(1), "base": components[-1],
            "labels": labels_of(parameters) if parameters is not None else None, "accessor": accessor,
            "outer": " in ".join(parts[local + 1:]),
        }
    plain = re.sub(r"^static ", "", text)
    if re.fullmatch(r"\w+_main|main", plain):
        return {"kind": "topLevel", "module": plain[: -len("_main")] if plain != "main" else None}
    if re.fullmatch(r"\w+", plain):
        return {"kind": "topLevel", "module": plain}
    return parse_qualified(text)


def skip_generic_signature(text):
    """`text` after the generic signature it opens with, such as the
    `<A where A: Swift.Equatable>` of a generic local function's
    `<A where A: Swift.Equatable>(item: A) -> ()`; `text` itself when it
    opens with none."""
    if not text.startswith("<"):
        return text
    depth = 0
    for index, char in enumerate(text):
        if char == "<":
            depth += 1
        elif char == ">" and text[index - 1] != "-":
            depth -= 1
            if depth == 0:
                return text[index + 1:]
    return text


def parse_declaration(text):
    """Base name, labels and accessor kind of a record key's declaration."""
    text = re.sub(r"^((?:static|class|mutating|nonmutating|override|final|public|private|fileprivate"
                  r"|internal|open|package)\s+)+", "", text.strip())
    accessor = re.search(r"\{ (\w+) \}$", text)
    match = re.match(r"^(?:func|var|let)\s+(`[^`]+`|[/=\-+!*%<>&|^~?.]+|[^\s(:<{]+)", text)
    if text.startswith("init"):
        base = "init"
    elif text.startswith("deinit"):
        base = "deinit"
    elif text.startswith("subscript"):
        base = "subscript"
    elif match:
        base = match.group(1).strip("`")
    else:
        base = None
    labels = None
    paren = text.find("(")
    if paren >= 0 and not text.startswith(("var", "let")):
        parameters, _ = balanced_group(text, paren)
        labels = labels_of(parameters)
    return {"base": base, "labels": labels, "accessor": accessor.group(1) if accessor else None}


def key_chain(record):
    """A record key's module and its chain of declarations, outermost
    first: `M::T::func f() / func g()` is (M, [func f(), func g()]); a
    subscript's accessor `subscript(…) / { get }` is one element; a local
    type's member stays `Local::func h()`. The file a key names for
    file-scoped declarations and `#if` conditions are dropped."""
    key = record["key"].replace(" @ " + record["file"], "")
    key = re.sub(r" #if .*?(?= / |$)", "", key)
    elements = key.split(" / ")
    first = elements[0].split("::")
    chain = [first[-1]] + elements[1:]
    if len(chain) > 1 and chain[-1].startswith("{"):
        chain = chain[:-2] + [chain[-2] + " " + chain[-1]]
    return first[0], chain


def compare_member(parsed, own, record_kind):
    """Why a demangled member (base, labels, accessor) isn't the declaration
    `own`; None when it is."""
    if record_kind == "subscript" and parsed.get("accessor") and parsed["base"] == "subscript":
        own = dict(own, accessor=own["accessor"] or "get")
    if parsed["base"] != own["base"]:
        return f"base name {parsed['base']} is not {own['base']}"
    if parsed.get("accessor") or own["accessor"]:
        if parsed.get("accessor") is None or own["accessor"] not in ACCESSOR_KINDS.get(parsed["accessor"], ()):
            return f"accessor {parsed.get('accessor')} is not {own['accessor']}"
    if parsed.get("labels") is not None and own["labels"] is not None and parsed["labels"] != own["labels"]:
        return f"labels ({':'.join(parsed['labels'])}) are not ({':'.join(own['labels'])})"
    return None


def outer_agreement(package, outer_text, record):
    """Why `outer_text`, the demangled context around a local function or
    local type, disagrees with the record `record` is nested in."""
    outer_key = record["key"].rsplit(" / ", 1)[0]
    outer = package.record_by_key.get(outer_key)
    if outer is not None:
        return agreement(package, parse_demangled(outer_text), outer)
    # Nested in a stored property's initializer, which is no record.
    match = re.search(r"(?:let|var)\s+(\w+)[^/]*= <initializer>$", outer_key)
    parsed = parse_demangled(outer_text)
    if match is None:
        return f"no record {outer_key}"
    if parsed["kind"] != "initializer" or parsed["base"] != match.group(1):
        return f"context {outer_text[:100]} is not the initializer of {match.group(1)}"
    return None


def agreement(package, parsed, record):
    """Why `parsed` (a demangled context) disagrees with `record`; None
    when they agree."""
    module, chain = key_chain(record)
    kind = parsed["kind"]
    if kind == "topLevel":
        if record["kind"] != "topLevel":
            return "top-level entry on a record that is not top-level code"
        if parsed["module"] not in (None, module, c99_name(module)):
            return f"module {parsed['module']} is not {module}"
        return None
    if kind == "localInitializer":
        return agreement(package, parse_demangled(parsed["outer"]), record)
    if kind == "local":
        if len(chain) < 2:
            return f"local function {parsed['base']} on a record that is not nested"
        own = parse_declaration(chain[-1])
        if "::" in chain[-1] or own["base"] != parsed["base"]:
            return f"local function {parsed['base']} is not {chain[-1][:60]}"
        if parsed["labels"] is not None and own["labels"] is not None and parsed["labels"] != own["labels"]:
            return (f"local function {parsed['base']}'s labels ({':'.join(parsed['labels'])}) "
                    f"are not ({':'.join(own['labels'])})")
        return outer_agreement(package, parsed["outer"], record)
    if kind == "localMember":
        if len(chain) < 2 or "::" not in chain[-1]:
            return f"member {parsed['type']}.{parsed['base']} of a local type on another record"
        local_type, declaration = chain[-1].rsplit("::", 1)
        if local_type.split(".")[-1] != parsed["type"]:
            return f"local type {parsed['type']} is not {local_type}"
        why = compare_member(parsed, parse_declaration(declaration), record["kind"])
        return why or outer_agreement(package, parsed["outer"], record)
    if kind in ("initializer", "unknown"):
        return f"{kind} context: {parsed.get('text', parsed.get('base', ''))[:120]}"
    if len(chain) > 1:
        return "a member entry on a nested record"
    if record["kind"] == "subscript" and record["key"] in package.containers:
        return "an entry on a subscript whose accessors carry the coverage"
    if parsed["module"] != module:
        return f"module {parsed['module']} is not {module}"
    type_path = record.get("typePath") or ""
    if parsed["typePath"] != type_path:
        return f"type {parsed['typePath'] or '(none)'} is not {type_path or '(none)'}"
    return compare_member(parsed, parse_declaration(chain[-1]), record["kind"])


# --------------------------------------------------------------------------
# The checks


class Checker:
    def __init__(self, package, show_all):
        self.package = package
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

    # 1e
    def compare(self, mine, theirs):
        self.section("1e  reimplementation equals the scan's coverage report")
        for field in ("bundles", "dropped"):
            self.result(field, mine[field] == theirs.get(field), f"{mine[field]} / scan {theirs.get(field)}")

        def keyed(items, key):
            return {key(i): i for i in items}

        record_differences = []
        ours = keyed(mine["records"], lambda r: r["key"])
        scans = keyed(theirs["records"], lambda r: r["key"])
        for key in sorted(set(ours) | set(scans)):
            a, b = ours.get(key), scans.get(key)
            if a is None or b is None:
                record_differences.append(f"{key}: {'only in the scan' if a is None else 'missing from the scan'}")
                continue
            for field in ("lines", "regions", "testTargets", "reason"):
                if a.get(field) != b.get(field):
                    record_differences.append(f"{key}: {field} {a.get(field)} / scan {b.get(field)}")
        with_data = sum(1 for r in mine["records"] if r.get("lines") is not None)
        self.result("records", not record_differences,
                    f"{len(ours)} records, {with_data} with data, {len(record_differences)} differences")
        self.listing(record_differences)
        order = [r["key"] for r in theirs["records"]] == [r["key"] for r in mine["records"]]
        self.result("records order", order)

        for field, key in (("attachments", lambda a: (a["attachedTo"], a["owner"])),
                           ("unmapped", lambda u: (u["file"], u["startLine"], u["startColumn"], u["name"])),
                           ("saturated", lambda s: (s["file"], s["line"])),
                           ("files", lambda f: f["file"])):
            ours = keyed(mine[field], key)
            scans = keyed(theirs.get(field, []), key)
            differences = []
            for item in sorted(set(ours) | set(scans)):
                a, b = ours.get(item), scans.get(item)
                if a != b:
                    if field == "files" and a is not None and b is not None:
                        la, lb = expand_runs(a["lines"]), expand_runs(b["lines"])
                        lines = sorted(l for l in set(la) | set(lb) if la.get(l) != lb.get(l))
                        detail = f"lines differ at {lines[:10]}" if lines else f"skipped {a['skipped']} / scan {b['skipped']}"
                        differences.append(f"{item}: {detail}")
                    else:
                        differences.append(f"{item}: {a} / scan {b}")
            same_order = [key(i) for i in theirs.get(field, [])] == [key(i) for i in mine[field]]
            self.result(field, not differences, f"{len(ours)} / scan {len(scans)}, {len(differences)} differences"
                        + ("" if same_order or differences else ", order differs"))
            self.listing(differences)

    # 1a
    def lcov(self, mapping, scan_files):
        self.section("1a  per-line data equals llvm-cov's lcov DA lines")
        lcov = lcov_lines(self.package)
        scanned = {f["file"]: expand_runs(f["lines"]) for f in scan_files}
        differences = []
        total = covered = 0
        kept = {path: filename for filename, (kind, path, _, _) in mapping.classes.items() if kind == "kept"}
        for path in sorted(set(kept) | set(scanned)):
            da = lcov.get(kept.get(path), None)
            ours = {line: count for line, (count, _) in scanned.get(path, {}).items()}
            if da is None:
                differences.append(f"{path}: no lcov record" if path in scanned else f"{path}: not in the scan")
                continue
            total += len(da)
            covered += sum(1 for c in da.values() if c > 0)
            if da != ours:
                lines = sorted(l for l in set(da) | set(ours) if da.get(l) != ours.get(l))
                differences.append(f"{path}: {len(lines)} lines differ, first {[(l, da.get(l), ours.get(l)) for l in lines[:5]]}")
        self.result("lcov", not differences, f"{len(kept)} kept files, {total} lines, {covered} covered")
        self.listing(differences)
        return total

    # 1b
    def partition(self, mapping, scan):
        self.section("1b  mapped lines lie in record spans or in exactly one attachment")
        files = {f["file"]: expand_runs(f["lines"]) for f in scan["files"]}
        mapped = in_spans = 0
        for path, lines in files.items():
            spanned = set()
            for record in self.package.records_by_file[path]:
                spanned |= mapping.spans(record)
            mapped += len(lines)
            in_spans += sum(1 for line in lines if line in spanned)
        attached = {(a["attachedTo"], a["owner"]): a["lines"] for a in scan["attachments"]}
        attached_total = sum(t["total"] for t in attached.values())
        self.result("add up", in_spans + attached_total == mapped,
                    f"{mapped} mapped lines = {in_spans} in record spans + {attached_total} in attachments")
        differences = []
        for key in sorted(set(attached) | set(mapping.attachment_lines)):
            lines = mapping.attachment_lines.get(key, set())
            # A line this script attaches that the scan doesn't map is a
            # difference of its own, not a lookup error.
            present = sorted((path, line) for path, line in lines if line in files.get(path, {}))
            for path, line in sorted(set(lines) - set(present)):
                differences.append(f"{key}: ({path}, {line}) attached by the checker but not mapped in the scan")
            expected = tally(files[path][line][0] for path, line in present)
            if attached.get(key, {"covered": 0, "total": 0}) != expected:
                differences.append(f"{key}: scan {attached.get(key)} / mapped lines outside records {expected}")
        self.result("attachment lines", not differences, f"{len(attached)} attachments")
        self.listing(differences)
        outside = []
        for key, lines in sorted(mapping.lines_by_record.items()):
            record = self.package.record_by_key[key]
            unmapped_lines = sorted(l for l in lines if l not in files.get(record["file"], {}))
            if unmapped_lines:
                outside.append(f"{key}: lines {unmapped_lines[:10]} aren't mapped in the file")
        self.result("record lines are file lines", not outside,
                    f"{len(mapping.lines_by_record)} records with data")
        self.listing(outside)

    # 1c
    def report(self, mapping, scan):
        self.section("1c  llvm-cov report -show-functions agrees")
        kept = sorted(filename for filename, (kind, _, _, _) in mapping.classes.items() if kind == "kept")
        rows = report_rows(self.package, kept)
        entries = [entry for key in mapping.entries for entry in mapping.entries[key]]
        anchor = []
        for name, _, _, regions in entries:
            row = rows.get(name)
            if row is None:
                anchor.append(f"{name}: no report row")
                continue
            lines = line_stats(build_segments(regions, lambda a, b: min(a + b, INT64_MAX)))
            code = [r for r in regions if r.kind == CODE]
            mine = (len(code), sum(1 for r in code if r.count == 0), len(lines),
                    sum(1 for count, _ in lines.values() if count == 0))
            if mine != row:
                anchor.append(f"{name}: (regions, missed, lines, missed) {mine} / llvm-cov {row}")
        self.result("per-function figures", not anchor, f"{len(entries)} mapped entries, {len(rows)} report rows")
        self.listing(anchor)

        scanned = {r["key"]: r for r in scan["records"]}
        single = parents = folded = 0
        differences = []
        adjusted = []
        for key, record_entries in sorted(mapping.entries.items()):
            record = self.package.record_by_key[key]
            if record["kind"] == "topLevel" or any(e[0] not in rows for e in record_entries):
                continue
            item = scanned.get(key)
            if item is None:
                differences.append(f"{key}: the checker maps entries to it but the scan's coverage has no such record")
                continue
            regions = [r for e in record_entries for r in e[1]]
            unique = deduplicated(regions)
            duplicates = len(regions) - len(unique)
            covered_duplicates = sum(1 for r in regions if r.count > 0) - sum(1 for r in unique if r.count > 0)
            total = sum(rows[e[0]][0] for e in record_entries) - duplicates
            missed_covered = sum(rows[e[0]][0] - rows[e[0]][1] for e in record_entries) - covered_duplicates
            expected = {"covered": missed_covered, "total": total}
            if item.get("regions") != expected:
                differences.append(f"{key}: regions {item.get('regions')} / llvm-cov rows minus duplicates {expected}")
            if len(record_entries) > 1:
                folded += 1
                continue
            name = record_entries[0][0]
            row = rows[name]
            nested = mapping.nested_spans(record)
            lines = line_stats(build_segments(record_entries[0][3], lambda a, b: min(a + b, INT64_MAX)))
            starts = {r.start[0] for r in record_entries[0][1]}
            dropped = [l for l in lines if l not in starts and any(l in span for span in nested)]
            dropped_covered = sum(1 for l in dropped if lines[l][0] > 0)
            expected = {"covered": row[2] - row[3] - dropped_covered, "total": row[2] - len(dropped)}
            if nested:
                parents += 1
                if dropped:
                    adjusted.append(f"{key}: llvm-cov {row[2]} lines, {len(dropped)} given to nested records")
            else:
                single += 1
            if item.get("lines") != expected:
                differences.append(f"{key}: lines {item.get('lines')} / llvm-cov {expected}")
        self.result("records", not differences,
                    f"{single} single-entry records, {parents} parents of nested records, "
                    f"{folded} folded records (regions only)")
        self.listing(differences)
        if adjusted:
            print("    parents whose lines exclude nested records' lines:")
            self.listing(adjusted)

    # 1d
    def names(self, mapping, demangle):
        self.section("1d  demangled names agree with record keys")
        names = demangle(sorted({function["name"] for function, _, _ in mapping.placed}))
        exceptions = []
        for function, path, key in mapping.placed:
            record = self.package.record_by_key[key]
            why = agreement(self.package, parse_demangled(names[function["name"]]), record)
            if why is not None:
                exceptions.append(f"{path}:{function['regions'][0][0]} {names[function['name']][:140]} -> {key}: {why}")
        exceptions.sort()
        self.result("names", not exceptions,
                    f"{len(mapping.placed) - len(exceptions)} of {len(mapping.placed)} mapped entries agree")
        self.listing(exceptions)

    # 2
    def unmapped(self, mapping, scan):
        self.section("2   unmapped entries listed; in-body regions mapped")
        placed = sum(len(e[1]) for k in mapping.entries for e in mapping.entries[k])
        in_kept = [u for u in mapping.unmapped if u["file"] in self.package.parsed]
        names = {u["name"] for u in in_kept}
        unmapped_regions = 0
        for function in self.package.export["functions"]:
            if function["name"] in names and mapping.classes[function["filenames"][0]][0] == "kept":
                unmapped_regions += sum(1 for r in function["regions"] if r[7] == CODE)
        attached_regions = sum(1 for f, _ in mapping.attached_entries for r in f["regions"] if r[7] == CODE)
        unscanned = [u for u in mapping.unmapped if u not in in_kept]
        denominator = placed + unmapped_regions
        share = placed / denominator if denominator else 1.0
        self.result("listed", len(scan["unmapped"]) == len(mapping.unmapped),
                    f"{len(scan['unmapped'])} listed: {len(in_kept)} in kept files, {len(unscanned)} in unscanned files")
        by_reason = defaultdict(int)
        for item in mapping.unmapped:
            by_reason[item["reason"]] += 1
        if by_reason:
            print(f"    by reason: {dict(sorted(by_reason.items()))}")
        self.result("in-body share", share >= 0.95,
                    f"{placed} of {denominator} code regions mapped to records ({share:.2%}); "
                    f"{len(mapping.attached_entries)} entries ({attached_regions} regions) attached, counted apart")


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("package")
    parser.add_argument("scan")
    parser.add_argument("--tools", help="a directory holding llvm-cov, llvm-profdata and swift")
    parser.add_argument("--build", help="the coverage build directory (default <package>/" + BUILD_DIRECTORY + ")")
    parser.add_argument("--all", action="store_true", help="list every difference")
    parser.add_argument("--dump", help="write the reimplementation's coverage report here")
    arguments = parser.parse_args()
    tools = None
    if arguments.tools:
        tools = {name: os.path.join(arguments.tools, name) for name in ("llvm-cov", "llvm-profdata", "swift")}
    package = Package(arguments.package, arguments.scan, arguments.build, tools)
    demangle = demangler(package)
    mapping = Mapping(package, demangle)
    mine = mapping.report(profiles_by_bundle(package))
    if arguments.dump:
        with open(arguments.dump, "w") as handle:
            json.dump(mine, handle, indent=1, sort_keys=True)
    scan = package.coverage
    checker = Checker(package, arguments.all)
    print(f"package {package.real_root}: {len(package.bundles)} bundles, "
          f"{len(package.export['functions'])} export entries, {len(package.export['files'])} export files")
    checker.lcov(mapping, scan["files"])
    checker.partition(mapping, scan)
    checker.report(mapping, scan)
    checker.names(mapping, demangle)
    checker.compare(mine, scan)
    checker.unmapped(mapping, scan)
    print()
    if checker.failures:
        print(f"FAILED: {', '.join(checker.failures)}")
        return 1
    print("all checks passed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
