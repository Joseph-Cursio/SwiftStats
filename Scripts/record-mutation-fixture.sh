#!/bin/sh
#
#  record-mutation-fixture.sh
#  SwiftStats
#
#  Regenerates Tests/Fixtures/<fixture>/Recorded/mutation: what
#  SwiftMutator writes for the Coverage fixture's `full` case and the
#  Mutation fixture's `full`, `since`, `tests-only`, `since-unlisted`,
#  `stopped`, `interrupted` and `resumed` cases, run the way the swiftmutator
#  collector runs it (M6, design §1 and §11): in a copy of the fixture,
#  never in Tests/Fixtures, with a `muter.conf.yml` written outside the
#  copy and passed with -c, `--skip-update-check`, NO_COLOR and stdin
#  /dev/null, and the base of a `--since` run named by its full commit SHA.
#
#  Each fixture is copied (but Recorded/, Patches/ and build folders) into
#  a scratch git repository whose commits have fixed names, emails, dates
#  and messages, so their SHAs are the same on every recording: `main` is
#  one commit, "Fixture", dated 2026-01-01T00:00:00Z, and each
#  Patches/<patch>.patch is a branch <patch> of one commit, "<patch>",
#  dated a day later, made with `git apply --index`. The tests build the
#  same commits the same way (`MutationFixture`) and check them against
#  Recorded/mutation/commits.txt. The copy is of the fixture's regular
#  files as they are on disk, not `git archive`, so a fixture not yet
#  committed records too; a stray file in it (one git would track)
#  changes every SHA, so record from a fixture with none.
#  Each case runs in its own folder <case>/, SwiftMutator's side-folder
#  parent, holding the configuration and the project <fixture>/, a clone
#  checked out at the case's branch. In the recorded text that project
#  becomes @ROOT@, the parent @PARENT@, the test command's `swift` @SWIFT@,
#  SwiftMutator's executable @SWIFT_MUTATOR@ and the host's name @HOST@;
#  the tests' fake puts its own paths back.
#
#  The Mutation fixture's coverage export is recorded by
#  `Scripts/record-coverage-fixture.sh <work directory> Mutation`.
#
#  Usage: Scripts/record-mutation-fixture.sh <work directory outside the repository> <swift-mutator>
#
#  Recorded files, in Recorded/mutation/<case>/:
#    results.jsonl   the run's results file, when it wrote one (`resumed`:
#                    the interrupted run's file after `--resume` appended)
#    report.json     `swift-mutator report <results> -f json` of it, when
#                    that wrote one, re-indented with its slashes unescaped
#    log-tail.txt    the last 20 lines of SwiftMutator's output
#    status.txt      how the run ended (`run: exit <n>` or
#                    `run: signal <n>`) and the report's exit status
#  and Recorded/mutation/commits.txt: `<branch> <commit>` for each branch.
#

set -eu

repository="$(cd "$(dirname "$0")/.." && pwd -P)"

if [ $# -ne 2 ]; then
    echo "usage: $0 <work directory outside the repository> <swift-mutator>" >&2
    exit 64
fi
mkdir -p "$1"
work="$(cd "$1" && pwd -P)"
case "$work/" in
    "$repository/"*)
        echo "error: $work is inside the repository; run SwiftMutator elsewhere" >&2
        exit 64
        ;;
esac
if [ ! -x "$2" ]; then
    echo "error: $2 isn't an executable" >&2
    exit 64
fi
mutator="$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")"
mutator_resolved="$(python3 -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$mutator")"
swift="$(command -v swift)"
case "$swift" in
    /*) ;;
    *)
        echo "error: no swift on PATH" >&2
        exit 64
        ;;
esac

# Commits that are the same on every machine: no global or system git
# configuration (signing, filters, hooks), and fixed names and emails.
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME="SwiftStats Fixture" GIT_AUTHOR_EMAIL="fixture@example.invalid"
export GIT_COMMITTER_NAME="SwiftStats Fixture" GIT_COMMITTER_EMAIL="fixture@example.invalid"
export NO_COLOR=1
day_zero=1767225600
day=86400

# Runs a command with stdin /dev/null and its output appended to a log,
# optionally sending it SIGTERM once the results file holds enough mutant
# lines, and appends how it ended to a status file: `run: exit <n>`, or
# `run: signal <n>` when a signal ended it.
cat > "$work/run-recorded.py" <<'PYTHON'
import glob
import os
import signal
import subprocess
import sys
import time

status, log, after, logs = sys.argv[1:5]
command = sys.argv[5:]
after = int(after)
with open(log, "ab") as output, open(os.devnull, "rb") as nothing:
    process = subprocess.Popen(command, stdin=nothing, stdout=output, stderr=subprocess.STDOUT)
    while after > 0 and process.poll() is None:
        files = glob.glob(os.path.join(glob.escape(logs), "*", "results*.jsonl"))
        if files:
            with open(files[0], "rb") as results:
                mutants = sum(1 for line in results if b'"kind":"mutant"' in line)
            if mutants >= after:
                process.send_signal(signal.SIGTERM)
                break
        time.sleep(0.05)
    code = process.wait()
with open(status, "a") as file:
    file.write("run: signal %d\n" % -code if code < 0 else "run: exit %d\n" % code)
PYTHON

# `$1` escaped for a sed regular expression.
pattern() {
    printf '%s' "$1" | sed 's/[][\.*^$#+?(){}|]/\\&/g'
}

# `$1` without a leading /private, as a path resolved through /tmp is
# spelled.
unprivate() {
    printf '%s' "${1#/private}"
}

# Standard input with the case's paths and the host's name redacted, each
# path also as spelled without /private. The project's own path goes
# first, and only where it ends, as SwiftMutator's side folders beside it
# start with it too.
redact() {
    sed -E \
        -e "s#$(pattern "$mutator_resolved")#@SWIFT_MUTATOR@#g" \
        -e "s#$(pattern "$(unprivate "$mutator_resolved")")#@SWIFT_MUTATOR@#g" \
        -e "s#$(pattern "$mutator")#@SWIFT_MUTATOR@#g" \
        -e "s#$(pattern "$(unprivate "$mutator")")#@SWIFT_MUTATOR@#g" \
        -e "s#$(pattern "$swift")#@SWIFT@#g" \
        -e "s#$(pattern "$root")([/\"' ]|\$)#@ROOT@\\1#g" \
        -e "s#$(pattern "$(unprivate "$root")")([/\"' ]|\$)#@ROOT@\\1#g" \
        -e "s#$(pattern "$parent")#@PARENT@#g" \
        -e "s#$(pattern "$(unprivate "$parent")")#@PARENT@#g" \
        -e 's#"host":"[^"]*"#"host":"@HOST@"#g'
}

# The JSON on standard input re-indented by two spaces with its slashes
# unescaped, so `redact` finds its paths.
unescaped_json() {
    python3 -c 'import json, sys; json.dump(json.load(sys.stdin), sys.stdout, indent=2, ensure_ascii=False); print()'
}

# Makes the scratch repository of fixture `$1` with its branches, and
# records commits.txt.
make_repository() {
    name="$1"
    fixture="$repository/Tests/Fixtures/$name"
    repo="$work/repositories/$name"
    rm -rf "$repo"
    mkdir -p "$repo"
    (cd "$fixture" && find . \( -path ./Recorded -o -path ./Patches -o -name .build -o -name .swiftpm \
        -o -name .swiftstats -o -name .DS_Store \) -prune -o -type f -print) |
        while read -r file; do
            mkdir -p "$repo/$(dirname "$file")"
            cp "$fixture/$file" "$repo/$file"
        done
    printf '.build/\n.swiftpm/\n' > "$repo/.gitignore"
    git -C "$repo" init --quiet --initial-branch=main
    git -C "$repo" add --all
    commit_dated "$repo" Fixture 0
    mkdir -p "$fixture/Recorded/mutation"
    printf 'main %s\n' "$(git -C "$repo" rev-parse main)" > "$fixture/Recorded/mutation/commits.txt"
    for patch in "$fixture"/Patches/*.patch; do
        [ -f "$patch" ] || continue
        branch="$(basename "$patch" .patch)"
        git -C "$repo" checkout --quiet -b "$branch" main
        git -C "$repo" apply --index "$patch"
        commit_dated "$repo" "$branch" 1
        printf '%s %s\n' "$branch" "$(git -C "$repo" rev-parse HEAD)" >> "$fixture/Recorded/mutation/commits.txt"
        git -C "$repo" checkout --quiet main
    done
}

# Commits everything staged in repository `$1` with message `$2`, dated
# `$3` days after day zero.
commit_dated() {
    date="@$((day_zero + $3 * day)) +0000"
    GIT_AUTHOR_DATE="$date" GIT_COMMITTER_DATE="$date" git -C "$1" commit --quiet --message "$2"
}

# Sets up case `$2` of fixture `$1`: its folder, the project cloned at
# branch `$3`, and the configuration SwiftStats writes.
prepare() {
    name="$1"
    parent="$work/cases/$name/$2"
    root="$parent/$name"
    rm -rf "$parent"
    mkdir -p "$parent"
    git clone --quiet --branch "$3" "$work/repositories/$name" "$root"
    printf 'executable: %s\narguments:\n- test\nexclude: []\nexcludeCalls: []\n' "$swift" > "$parent/muter.conf.yml"
    : > "$parent/swift-mutator.log"
}

# Runs SwiftMutator in the prepared case's project, with SIGTERM once
# `$1` mutant lines are written when it isn't 0, and with the arguments
# after it.
run_mutator() {
    after="$1"
    shift
    (cd "$root" && python3 "$work/run-recorded.py" "$parent/status.txt" "$parent/swift-mutator.log" "$after" \
        "$parent/${name}_muter_logs" "$mutator" run -c "$parent/muter.conf.yml" --skip-update-check "$@")
}

# The prepared case's results file, or nothing when the run wrote none.
results_file() {
    if [ -d "$parent/${name}_muter_logs" ]; then
        find "$parent/${name}_muter_logs" -name 'results*.jsonl' -type f | LC_ALL=C sort | head -n 1
    fi
}

# Records the prepared case's output as case `$1` of its fixture.
record() {
    out="$repository/Tests/Fixtures/$name/Recorded/mutation/$1"
    rm -rf "$out"
    mkdir -p "$out"
    results="$(results_file)"
    if [ -n "$results" ]; then
        redact < "$results" > "$out/results.jsonl"
        rm -f "$parent/report.json"
        code=0
        (cd "$root" && "$mutator" report "$results" -f json -o "$parent/report.json" \
            < /dev/null >> "$parent/report.log" 2>&1) || code=$?
        printf 'report: exit %s\n' "$code" >> "$parent/status.txt"
        if [ -f "$parent/report.json" ]; then
            unescaped_json < "$parent/report.json" | redact > "$out/report.json"
        fi
    fi
    tail -n 20 "$parent/swift-mutator.log" | redact > "$out/log-tail.txt"
    cp "$parent/status.txt" "$out/status.txt"
}

make_repository Coverage
make_repository Mutation
base="$(git -C "$work/repositories/Mutation" rev-parse main)"

prepare Coverage full-case main
run_mutator 0
record full

prepare Mutation full-case main
run_mutator 0
record full

prepare Mutation since-case since
run_mutator 0 --since "$base"
record since

prepare Mutation tests-only-case tests-only
run_mutator 0 --since "$base"
record tests-only

prepare Mutation since-unlisted-case since-unlisted
run_mutator 0 --since "$base"
record since-unlisted

prepare Mutation stopped-case stopped
run_mutator 0
record stopped

# The interrupted run is resumed in the same folder, appending to its file.
prepare Mutation interrupted-case main
run_mutator 5
record interrupted
interrupted="$(results_file)"
: > "$parent/status.txt"
run_mutator 0 --resume "$interrupted"
record resumed

# Nothing recorded may name this machine's paths or its user.
if grep -r -l -F -e "$work" -e "$(unprivate "$work")" -e "$HOME" -e "$(basename "$HOME")" -e '/Users/' \
    -e '/private/' -e '/tmp/' -e '/var/folders/' -e '\/' \
    "$repository/Tests/Fixtures/Coverage/Recorded/mutation" "$repository/Tests/Fixtures/Mutation/Recorded/mutation"; then
    echo "error: the files above hold paths of this machine" >&2
    exit 1
fi
echo "recorded the mutation cases of Coverage and Mutation"
