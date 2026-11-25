#!/bin/sh
#
#  record-index-fixture.sh
#  SwiftStats
#
#  Regenerates Tests/Fixtures/Index/Recorded/index and
#  Tests/Fixtures/Diff/Recorded/index: what the T1 build, the index store
#  and outskirts give for the Index fixture (M7, design §13 "Recordings"),
#  run the way the build, index and periphery collectors run them (design
#  §1.3, §1.4 and §5.2), and the index of the Diff fixture's two trees.
#  Everything is built in copies in the work directory, never in
#  Tests/Fixtures. The copies are of the fixtures' files as
#  `git ls-files --cached --others --exclude-standard` lists them, so an
#  uncommitted fixture edit is recorded and ignored junk isn't; `Recorded/`
#  and any `.build`, `.swiftstats` or `.swiftpm` folder are left out too
#  (the repository ignores only the first, and a leftover scratch folder
#  would make the first build incremental).
#
#  Usage: Scripts/record-index-fixture.sh <new work directory outside the repository> <outskirts>
#  The work directory must be new or empty (see below).
#
#  Steps, in the work directory:
#    1. copies Index and IndexDep side by side (the manifest names
#       `../IndexDep`), and Diff/before and Diff/after;
#    2. in Index: the T1 describe (`swift package --scratch-path <build>
#       describe --type json`, the scratch path first) and design §1.4's
#       build, with <build> the real path of Index/.swiftstats/index-build
#       and `swift` the toolchain's own (found from `swift
#       -print-target-info`, as the build session finds it);
#    3. `python3 -I -B Scripts/index-check.py dump` of the store;
#    4. outskirts' two runs, the command lines of design §5.2, with
#       `--retain-public-modules` the C99 names of the targets the describe's
#       library products list;
#    5. removes the root package's intermediates
#       (out/Intermediates.noindex/<manifest name>.build) and builds again;
#    6. renames Sources/IndexCore/Formatting.swift to LineFormatting.swift
#       with `mv`, moves Sources/Kits/Relay.swift from `index-kit` to
#       `index-support` by editing the copy's manifest (`stale_manifest`
#       below), describes, removes the root intermediates and builds into the
#       same scratch, then dumps the store and runs outskirts' `roots` run
#       over it with the stale units still in it;
#    7. builds a second copy of Index with one syntax error appended to
#       Sources/IndexCore/Formatting.swift, which must fail;
#    8. describes, builds and dumps Diff/before and Diff/after.
#
#  Recorded files, in Tests/Fixtures/Index/Recorded/index/:
#    build.stdout, build.stderr   the build's standard output (the -v task
#                                 log) and standard error (timings and
#                                 diagnostics)
#    rebuild.stderr               standard error of the root-only rebuild
#    describe.json                the T1 describe
#    reader.json                  the dump of the first build's store
#    reader-stale.json            the dump after step 6 (its `files` name
#                                 LineFormatting.swift and the edited
#                                 manifest)
#    outskirts-roots.json, outskirts-production.json
#                                 the two runs' JSON, re-indented by two
#                                 spaces with slashes unescaped
#    outskirts-stale-roots.json   the `roots` run over the stale store
#    outskirts-version.txt        `outskirts version`
#    failed.stderr                standard error of the failing build
#    toolchain.txt                `toolchain: <the first line of swift
#                                 --version>` and `.swift-version: <text>`
#                                 or `absent`, as the build's options say
#    dependency-files.txt         `<sha256>  <path>` of IndexDep's Swift
#                                 files (sources and manifest, the set the
#                                 staleness test hashes), which the dumps
#                                 don't hash (IndexDep is outside the root)
#  and in Tests/Fixtures/Diff/Recorded/index/: before.json, after.json, the
#  two trees' dumps.
#  In the recorded text each case's package root becomes @ROOT@, its scratch
#  path @BUILD@, IndexDep's root @DEP@ and the toolchain (the folder holding
#  usr/bin/swift) @TOOLCHAIN@; the fakes and RecordedIndexSource put them
#  back. Three more appear only in the build's output: @PARENT@, the root's
#  parent folder (Swift Build runs its tasks there: `cd <parent>`), @TMP@,
#  the temporary folder ($TMPDIR, where SwiftPM compiles manifests), and
#  @DEVELOPER@, the real path of `xcode-select -p` (the SDK, its frameworks
#  and plugin servers), replaced after the toolchain, which is usually inside
#  it. Each is also replaced as spelled without /private. A dump's `modified`
#  dates are the unit files' own, so a re-recorded dump differs there even
#  when nothing else did, as do the timings and the manifests' temporary
#  folder names in the build's output.
#

set -eu

repository="$(cd "$(dirname "$0")/.." && pwd -P)"

if [ $# -ne 2 ]; then
    echo "usage: $0 <new work directory outside the repository> <outskirts>" >&2
    exit 64
fi
# A new folder each time: SwiftPM caches compiled manifests by their path,
# and a build whose manifests come from the cache prints none of the
# manifest-command lines (`warning: '<package>': …swift-frontend …`) the
# recording should hold.
if [ -e "$1" ] && [ -n "$(ls -A "$1")" ]; then
    echo "error: $1 isn't empty; record into a new folder" >&2
    exit 64
fi
mkdir -p "$1"
work="$(cd "$1" && pwd -P)"
case "$work/" in
    "$repository/"*)
        echo "error: $work is inside the repository; build the fixtures elsewhere" >&2
        exit 64
        ;;
esac
if [ ! -x "$2" ]; then
    echo "error: $2 isn't an executable" >&2
    exit 64
fi
outskirts="$(cd "$(dirname "$2")" && pwd -P)/$(basename "$2")"
tmp="$(cd "${TMPDIR:-/tmp}" && pwd -P)"

recorded="$repository/Tests/Fixtures/Index/Recorded/index"
diff_recorded="$repository/Tests/Fixtures/Diff/Recorded/index"
checker="$repository/Scripts/index-check.py"

# The manifest's two lines that put Relay.swift in `index-kit`, and the
# same lines after the move; IndexFixture.staleManifestEdits in the tests
# makes the same edit.
kit_line='sources: ["Kit.swift", "Relay.swift"]'
kit_moved='sources: ["Kit.swift"]'
support_line='sources: ["Support.swift"]'
support_moved='sources: ["Support.swift", "Relay.swift"]'

# Copies the fixture folder `$1` (relative to the repository) to `$2`, as
# `git ls-files --cached --others --exclude-standard` lists its files, but
# Recorded/ and build folders: the repository's .gitignore names `.build/`
# and `.swiftpm/` but not `.swiftstats/`, which a scan of a fixture in place
# leaves, and whose index-build the first build would otherwise reuse.
copy_fixture() {
    source="$1"
    destination="$2"
    rm -rf "$destination"
    mkdir -p "$destination"
    git -C "$repository" -c core.quotePath=false ls-files --cached --others --exclude-standard -- "$source" |
        while IFS= read -r file; do
            relative="${file#"$source"/}"
            case "$relative" in
                Recorded/* | .build/* | */.build/* | .swiftstats/* | */.swiftstats/* | .swiftpm/* | */.swiftpm/*)
                    continue
                    ;;
            esac
            [ -f "$repository/$file" ] || continue
            mkdir -p "$destination/$(dirname "$relative")"
            cp "$repository/$file" "$destination/$relative"
        done
}

# The real path of `$1`, which must exist.
real_path() {
    python3 -I -c 'import os, sys; print(os.path.realpath(sys.argv[1]))' "$1"
}

# Sets `build` to the real path of package `$1`'s scratch folder, creating it.
scratch_of() {
    mkdir -p "$1/.swiftstats/index-build"
    build="$(real_path "$1/.swiftstats/index-build")"
}

# The T1 describe of the package in the current folder into
# <build>/swiftstats-describe.json.
describe() {
    "$swift" package --scratch-path "$build" describe --type json > "$build/swiftstats-describe.json"
}

# Design §1.4's build of the package in the current folder, standard output
# to `$1` and standard error to `$2`; its exit status.
t1_build() {
    code=0
    "$swift" build --build-tests --build-system swiftbuild -c debug -v --no-color-diagnostics \
        --scratch-path "$build" \
        -Xswiftc -index-include-locals \
        -Xswiftc -Xfrontend -Xswiftc -debug-time-function-bodies \
        -Xswiftc -Xfrontend -Xswiftc -debug-time-expression-type-checking \
        -Xswiftc -Xfrontend -Xswiftc -debug-diagnostic-names \
        < /dev/null > "$1" 2> "$2" || code=$?
    return "$code"
}

# Removes the root package's intermediates, named after the manifest, which
# must be there.
remove_root_intermediates() {
    name="$(python3 -I -c 'import json, sys; print(json.load(open(sys.argv[1]))["name"])' \
        "$build/swiftstats-describe.json")"
    intermediates="$build/out/Intermediates.noindex/$name.build"
    if [ ! -d "$intermediates" ]; then
        echo "error: no root intermediates at $intermediates" >&2
        exit 1
    fi
    rm -rf "$intermediates"
}

# The dump of <build>/out for the package at `$1` into `$2`.
dump() {
    python3 -I -B "$checker" dump "$build/out" "$library" "$build/swiftstats-describe.json" "$1" --output "$2"
}

# Outskirts' run `$1` (`roots` or `production`) in the package at `$2`,
# its JSON into `$3`, design §5.2's command line.
run_outskirts() {
    : > "$build/swiftstats-outskirts.yml"
    # The C99 names of the targets the describe's library products list, in
    # byte order, each its own argument.
    modules="$(python3 -I - "$build/swiftstats-describe.json" <<'PYTHON'
import json, sys
package = json.load(open(sys.argv[1]))
c99 = {target["name"]: target["c99name"] for target in package["targets"]}
names = set()
for product in package.get("products", []):
    if "library" in product.get("type", {}):
        names.update(c99[target] for target in product["targets"])
print(" ".join(sorted(names, key=lambda name: name.encode())))
PYTHON
)"
    set -- "$1" "$2" "$3" --retain-codable-properties --retain-equatable-properties
    if [ "$1" = production ]; then
        set -- "$@" --exclude-tests
    fi
    run="$1"
    package="$2"
    output="$3"
    shift 3
    code=0
    # $modules unquoted: one argument per module name.
    (cd "$package" && "$outskirts" scan --format json --disable-update-check \
        --config "$build/swiftstats-outskirts.yml" \
        --index-store-path "$build/out" --skip-build \
        --index-exclude "$build/**" \
        --json-package-manifest-path "$build/swiftstats-describe.json" \
        --retain-public-modules $modules \
        "$@" < /dev/null > "$build/swiftstats-outskirts-$run.json" 2> "$build/swiftstats-outskirts-$run.stderr") ||
        code=$?
    if [ "$code" -ne 0 ]; then
        cat "$build/swiftstats-outskirts-$run.stderr" >&2
        echo "error: outskirts' $run run exited $code" >&2
        exit 1
    fi
    python3 -I -c 'import json, sys; json.dump(json.load(open(sys.argv[1])), sys.stdout, indent=2, ensure_ascii=False); print()' \
        "$build/swiftstats-outskirts-$run.json" > "$output"
}

# `$1` escaped for a sed regular expression.
pattern() {
    printf '%s' "$1" | sed 's/[][\.*^$#+?(){}|]/\\&/g'
}

# `$1` without a leading /private, as a path through /tmp is spelled.
unprivate() {
    printf '%s' "${1#/private}"
}

# Standard input with case paths redacted: `$1` the package root, `$2` its
# scratch, `$3` IndexDep's root (or ""), the root's parent, the temporary
# folder, the toolchain and the developer folder; each but the last two also
# as spelled without /private. The scratch goes first (it is inside the
# root), then IndexDep (its name starts with the root's), then the root and
# its parent, each only where its last component ends; the toolchain goes
# before the developer folder, which usually holds it.
redact() {
    set -- "$1" "$2" "${3:-@NONE@}" "$(dirname "$1")"
    sed -E \
        -e "s#$(pattern "$2")#@BUILD@#g" \
        -e "s#$(pattern "$(unprivate "$2")")#@BUILD@#g" \
        -e "s#$(pattern "$3")#@DEP@#g" \
        -e "s#$(pattern "$(unprivate "$3")")#@DEP@#g" \
        -e "s#$(pattern "$1")([^A-Za-z0-9_.-]|\$)#@ROOT@\\1#g" \
        -e "s#$(pattern "$(unprivate "$1")")([^A-Za-z0-9_.-]|\$)#@ROOT@\\1#g" \
        -e "s#$(pattern "$4")([^A-Za-z0-9_.-]|\$)#@PARENT@\\1#g" \
        -e "s#$(pattern "$(unprivate "$4")")([^A-Za-z0-9_.-]|\$)#@PARENT@\\1#g" \
        -e "s#$(pattern "$tmp")#@TMP@#g" \
        -e "s#$(pattern "$(unprivate "$tmp")")#@TMP@#g" \
        -e "s#$(pattern "$toolchain")#@TOOLCHAIN@#g" \
        -e "s#$(pattern "$developer")([^A-Za-z0-9_.-]|\$)#@DEVELOPER@\\1#g"
}

# Copies.
index="$work/Index"
dependency="$work/IndexDep"
copy_fixture Tests/Fixtures/Index "$index"
copy_fixture Tests/Fixtures/IndexDep "$dependency"
copy_fixture Tests/Fixtures/Diff/before "$work/Diff/before"
copy_fixture Tests/Fixtures/Diff/after "$work/Diff/after"
scratch_of "$index"
cd "$index"

# The toolchain, found as the build session finds it: the swift on PATH,
# asked in the package root (where swiftly reads .swift-version), names its
# runtime resources, beside which sit the library and the toolchain's own
# swift.
resources="$(swift -print-target-info | plutil -extract paths.runtimeResourcePath raw -o - -)"
toolchain="$(cd "$resources/../../.." && pwd -P)"
swift="$toolchain/usr/bin/swift"
library="$(cd "$resources/.." && pwd -P)/libIndexStore.dylib"
if [ ! -x "$swift" ] || [ ! -f "$library" ]; then
    echo "error: no swift or libIndexStore.dylib in $toolchain" >&2
    exit 1
fi
# The developer folder the build's SDK and plugin servers come from.
developer="$(real_path "$(xcode-select -p)")"
version="$("$swift" --version 2>/dev/null | sed -n '/./{p;q;}')"
if [ -f "$index/.swift-version" ]; then
    pin="$(tr -d '\n' < "$index/.swift-version")"
else
    pin=absent
fi

# 2–4. The first build, its dump and outskirts' two runs.
describe
cp "$build/swiftstats-describe.json" "$work/describe.json"
if ! t1_build "$build/swiftstats-build.log" "$build/swiftstats-build.stderr"; then
    tail -n 20 "$build/swiftstats-build.stderr" >&2
    echo "error: the Index fixture's build failed" >&2
    exit 1
fi
cp "$build/swiftstats-build.log" "$work/build.stdout"
cp "$build/swiftstats-build.stderr" "$work/build.stderr"
dump "$index" "$work/reader.json"
run_outskirts roots "$index" "$work/outskirts-roots.json"
run_outskirts production "$index" "$work/outskirts-production.json"
"$outskirts" version < /dev/null > "$work/outskirts-version.txt"

# 5. The root-only rebuild.
remove_root_intermediates
if ! t1_build "$build/swiftstats-build.log" "$work/rebuild.stderr"; then
    echo "error: the Index fixture's rebuild failed" >&2
    exit 1
fi

# 6. A renamed file and a file moved to another target, built into the same
# scratch.
mv "$index/Sources/IndexCore/Formatting.swift" "$index/Sources/IndexCore/LineFormatting.swift"
python3 -I - "$index/Package.swift" "$kit_line" "$kit_moved" "$support_line" "$support_moved" <<'PYTHON'
import sys
path, *edits = sys.argv[1:]
text = open(path, encoding="utf-8").read()
for old, new in zip(edits[0::2], edits[1::2]):
    if text.count(old) != 1:
        sys.exit(f"error: {path} doesn't hold {old!r} once")
    text = text.replace(old, new)
open(path, "w", encoding="utf-8").write(text)
PYTHON
describe
remove_root_intermediates
if ! t1_build "$build/swiftstats-build.log" "$build/swiftstats-build.stderr"; then
    tail -n 20 "$build/swiftstats-build.stderr" >&2
    echo "error: the stale case's build failed" >&2
    exit 1
fi
dump "$index" "$work/reader-stale.json"
run_outskirts roots "$index" "$work/outskirts-stale-roots.json"
index_build="$build"

# 7. A build that fails.
failed="$work/failed/Index"
copy_fixture Tests/Fixtures/Index "$failed"
copy_fixture Tests/Fixtures/IndexDep "$work/failed/IndexDep"
printf '\nfunc broken() -> Int {\n    return (\n}\n' >> "$failed/Sources/IndexCore/Formatting.swift"
scratch_of "$failed"
cd "$failed"
if t1_build "$build/swiftstats-build.log" "$work/failed.stderr"; then
    echo "error: the build with a syntax error succeeded" >&2
    exit 1
fi
failed_build="$build"

# 8. The Diff fixture's two trees.
for side in before after; do
    scratch_of "$work/Diff/$side"
    cd "$work/Diff/$side"
    describe
    if ! t1_build "$build/swiftstats-build.log" "$build/swiftstats-build.stderr"; then
        tail -n 20 "$build/swiftstats-build.stderr" >&2
        echo "error: Diff/$side's build failed" >&2
        exit 1
    fi
    dump "$work/Diff/$side" "$work/$side.json"
    redact "$work/Diff/$side" "$build" "" < "$work/$side.json" > "$work/$side.redacted.json"
done

# 9. The recorded files, redacted.
rm -rf "$recorded" "$diff_recorded"
mkdir -p "$recorded" "$diff_recorded"
for file in build.stdout build.stderr rebuild.stderr describe.json reader.json reader-stale.json \
    outskirts-roots.json outskirts-production.json outskirts-stale-roots.json outskirts-version.txt; do
    redact "$index" "$index_build" "$dependency" < "$work/$file" > "$recorded/$file"
done
redact "$failed" "$failed_build" "$work/failed/IndexDep" < "$work/failed.stderr" > "$recorded/failed.stderr"
printf 'toolchain: %s\n.swift-version: %s\n' "$version" "$pin" > "$recorded/toolchain.txt"
# Swift files only: the staleness test hashes the same set.
git -C "$repository" -c core.quotePath=false ls-files --cached --others --exclude-standard -- Tests/Fixtures/IndexDep |
    sed 's#^Tests/Fixtures/IndexDep/##' | grep '\.swift$' | LC_ALL=C sort -u |
    (cd "$repository/Tests/Fixtures/IndexDep" && while IFS= read -r file; do
        if [ -f "$file" ]; then
            shasum -a 256 "$file"
        fi
    done) > "$recorded/dependency-files.txt"
cp "$work/before.redacted.json" "$diff_recorded/before.json"
cp "$work/after.redacted.json" "$diff_recorded/after.json"

# Nothing recorded may name this machine's paths or its user.
if grep -r -l -F -e "$work" -e "$(unprivate "$work")" -e "$HOME" -e "$(basename "$HOME")" -e '/Users/' \
    -e '/private/' -e '/tmp/' -e '/var/folders/' -e '/Applications/' -e '\/' "$recorded" "$diff_recorded"; then
    echo "error: the files above hold paths of this machine" >&2
    exit 1
fi
echo "recorded $(ls "$recorded" | wc -l | tr -d ' ') files in $recorded and 2 in $diff_recorded"
