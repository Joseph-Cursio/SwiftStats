#!/usr/bin/env python3
"""Compare the `sitrep` block of `swiftstats scan` with Sitrep's own output.

PRD M0 done-when (2): on a package, the block must match `sitrep -f json`
field by field, apart from listed, deliberate differences.

Sitrep scans every .swift file under a directory, while SwiftStats scans the
files of the package's targets. To give both the same input, this script
builds a temporary tree of symlinks to exactly the files SwiftStats scanned
and runs Sitrep on that.

Usage:
    Scripts/compare-sitrep.py <package-dir> [--sitrep <path-to-Sitrep>]
                              [--swiftstats <path-to-swiftstats>]

Exit status is 0 when the blocks match, 1 when they differ.
"""

import argparse
import json
import os
import subprocess
import sys
import tempfile

DEFAULT_SITREP = os.path.expanduser("~/GitHub_projects/Sitrep/.build/release/Sitrep")
DEFAULT_SWIFTSTATS = os.path.join(os.path.dirname(__file__), "..", ".build", "release", "swiftstats")

# Fields whose value depends on tie-breaking that Sitrep leaves to dictionary
# or file-system order. SwiftStats breaks ties deterministically, so these
# are compared by value only when a tie exists.
TIE_FIELDS = ("longestFile", "longestType")


def run_json(command, cwd=None):
    result = subprocess.run(command, cwd=cwd, capture_output=True, text=True)
    if result.returncode != 0:
        sys.exit(f"{' '.join(command)} failed:\n{result.stderr}")
    return json.loads(result.stdout)


def compare(ours, theirs, order_dependent):
    """order_dependent: type names Sitrep resolves in file-system order."""
    differences = []
    for field in ("scannedFiles", "totalLinesOfCode", "totalStrippedLinesOfCode",
                  "uiKitLinesOfCode", "swiftUILinesOfCode"):
        if ours["scanStats"][field] != theirs["scanStats"][field] and field.endswith("LinesOfCode") \
                and field.startswith(("uiKit", "swiftUI")) and order_dependent:
            print(f"  note: {field} differs (swiftstats {ours['scanStats'][field]}, "
                  f"sitrep {theirs['scanStats'][field]}); depends on declaration order of "
                  f"{', '.join(order_dependent)}")
        elif ours["scanStats"][field] != theirs["scanStats"][field]:
            differences.append(f"scanStats.{field}: swiftstats {ours['scanStats'][field]}, "
                               f"sitrep {theirs['scanStats'][field]}")
    for field in TIE_FIELDS:
        mine, other = ours["scanStats"].get(field), theirs["scanStats"].get(field)
        if mine != other:
            if mine and other and mine["value"] == other["value"]:
                print(f"  note: {field} tie at {mine['value']}: "
                      f"swiftstats picked {mine['name']}, sitrep {other['name']}")
            else:
                differences.append(f"scanStats.{field}: swiftstats {mine}, sitrep {other}")
    if ours["objects"] != theirs["objects"]:
        differences.append(f"objects: swiftstats {ours['objects']}, sitrep {theirs['objects']}")
    as_dict = lambda stats: {stat["name"]: stat["value"] for stat in stats}
    for field in ("imports", "inheritances"):
        if as_dict(ours[field]) != as_dict(theirs[field]):
            differences.append(f"{field}: swiftstats {as_dict(ours[field])}, sitrep {as_dict(theirs[field])}")
    return differences


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("package")
    parser.add_argument("--sitrep", default=DEFAULT_SITREP)
    parser.add_argument("--swiftstats", default=DEFAULT_SWIFTSTATS)
    args = parser.parse_args()

    package = os.path.abspath(args.package)
    scan = run_json([os.path.abspath(args.swiftstats), "scan", package, "--no-store"])
    files = [file for target in scan["targets"] for file in target["files"]]
    unreadable = {warning["file"] for warning in scan["warnings"] if warning.get("file")}
    files = [file for file in files if file not in unreadable]

    with tempfile.TemporaryDirectory(prefix="compare-sitrep-") as tree:
        for file in files:
            link = os.path.join(tree, file)
            os.makedirs(os.path.dirname(link), exist_ok=True)
            os.symlink(os.path.join(package, file), link)
        theirs = run_json([args.sitrep, "-f", "json", "-p", tree])

    prefix = "sitrep: "
    order_dependent = [warning["message"][len(prefix):].split(" ", 1)[0]
                       for warning in scan["warnings"] if warning["message"].startswith(prefix)]
    differences = compare(scan["sitrep"], theirs, order_dependent)
    print(f"{os.path.basename(package)}: {len(files)} files")
    if differences:
        for difference in differences:
            print(f"  DIFF {difference}")
        return 1
    print("  sitrep block matches")
    return 0


if __name__ == "__main__":
    sys.exit(main())
