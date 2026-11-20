#!/usr/bin/env python3
"""Write the M3 labelling fixtures for one repository.

Two files under Tests/Fixtures, each with empty labels for the owner to fill:

- HotspotLabels/<name>.json: the top 20 hotspots at the scanned commit
  (done-when 1: at least 12 of 20 judged worth attention). Label each item
  "worth" or "not-worth".
- FixLabels/<name>.json: every commit in the history window that the fix
  patterns match, plus a sample of those they don't, up to 30 (PRD §13:
  fix-detection precision on a hand-labelled sample). Label each commit
  "fix" or "not-fix".

The package must already be scanned with history into STORE, for example:

    swiftstats scan <package> --store STORE -o scan.json
    Scripts/label-sample.py <name> <repo> <package-path> STORE scan.json

Existing labels in the output files are kept for items still listed.
"""

import json
import os
import subprocess
import sys

SAMPLE_SIZE = 30
HOTSPOTS = 20
ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SWIFTSTATS = os.path.join(ROOT, ".build", "release", "swiftstats")


def run(arguments, cwd=None):
    return subprocess.run(arguments, cwd=cwd, check=True, capture_output=True, text=True).stdout


def existing_labels(path, key):
    if not os.path.exists(path):
        return {}
    with open(path) as handle:
        document = json.load(handle)
    items = document.get("items") or document.get("commits") or []
    return {key(item): (item.get("label"), item.get("note", "")) for item in items}


def write(path, document):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as handle:
        json.dump(document, handle, indent=2, sort_keys=True)
        handle.write("\n")
    print(f"wrote {os.path.relpath(path, ROOT)}")


def hotspots(name, repo, package_path, store, scan):
    package = os.path.join(repo, package_path) if package_path else repo
    top = json.loads(run([SWIFTSTATS, "top", "hotspot", "--package", package, "--store", store,
                          "--limit", str(HOTSPOTS), "--format", "json"]))
    identity = next((c.get("version") for c in scan["collectors"] if c["name"] == "swiftstats"), None)
    path = os.path.join(ROOT, "Tests", "Fixtures", "HotspotLabels", f"{name}.json")
    kept = existing_labels(path, lambda item: (item["family"], item["file"]))
    items = []
    # top's JSON schema 2 names the family `subject` and moves its history into `history`.
    for item in top["signal"]["items"]:
        label, note = kept.get((item["subject"], item["file"]), (None, ""))
        items.append({
            "rank": item["rank"], "family": item["subject"], "file": item["file"], "line": item["line"],
            "score": item["score"], "member": item["member"], "changes": item["history"]["changes"],
            "cognitive": item["history"].get("cognitive"), "label": label, "note": note,
        })
    write(path, {
        "repo": name, "packagePath": package_path, "commit": top["commit"],
        "swiftstatsVersion": identity, "rule": top["signal"]["rule"], "items": items,
    })


def fixes(name, repo, package_path, scan):
    history = scan["history"]
    options = next(c["options"] for c in scan["collectors"] if c["name"] == "history")
    matched = {note["commit"]: note for note in history["fixCommits"]}
    pathspec = os.path.join(package_path, "*.swift") if package_path else "*.swift"
    log = run(["git", "log", history["commit"], "--no-merges", f"--since={history['windowStart']}",
               "--format=%H%x00%s", "--", pathspec], cwd=repo)
    window = [line.split("\0", 1) for line in log.splitlines() if "\0" in line]
    unmatched = [entry for entry in window if entry[0] not in matched]
    room = max(0, SAMPLE_SIZE - len(matched))
    step = max(1, len(unmatched) // room) if room else len(unmatched) + 1
    sample = unmatched[::step][:room]
    path = os.path.join(ROOT, "Tests", "Fixtures", "FixLabels", f"{name}.json")
    kept = existing_labels(path, lambda item: item["commit"])
    commits = []
    for note in history["fixCommits"]:
        label, text = kept.get(note["commit"], (None, ""))
        commits.append({"commit": note["commit"], "subject": note["subject"], "matched": True,
                        "excluded": note.get("excluded"), "label": label, "note": text})
    for commit, subject in sample:
        label, text = kept.get(commit, (None, ""))
        commits.append({"commit": commit, "subject": subject, "matched": False,
                        "excluded": None, "label": label, "note": text})
    write(path, {
        "repo": name, "packagePath": package_path, "commit": history["commit"],
        "windowStart": history["windowStart"], "windowCommitsTouchingSwift": len(window),
        "unmatchedSampled": f"every {step} of {len(unmatched)}" if sample else "none",
        "historyOptions": options, "commits": commits,
    })


def main():
    if len(sys.argv) != 6:
        sys.exit(__doc__)
    name, repo, package_path, store, scan_path = sys.argv[1:]
    with open(scan_path) as handle:
        scan = json.load(handle)
    if not scan.get("history"):
        sys.exit("the scan has no history; scan without --no-history")
    hotspots(name, repo, package_path, store, scan)
    fixes(name, repo, package_path, scan)


if __name__ == "__main__":
    main()
