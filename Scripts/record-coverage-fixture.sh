#!/bin/sh
#
#  record-coverage-fixture.sh
#  SwiftStats
#
#  Regenerates Tests/Fixtures/<fixture>/Recorded: what the real tools
#  print for a coverage fixture, `Coverage` (the mapping's), `Risky`
#  (risky + untested's) or `Mutation` (M6's signals'), run the way the
#  coverage collector runs them (M5).
#  The fixture is copied to a work directory outside the repository and
#  built there, never in Tests/Fixtures. In the recorded text the copy's
#  build directory becomes @BUILD@ and its root @ROOT@; the tests' fake
#  toolchain puts its own paths back.
#
#  Usage: Scripts/record-coverage-fixture.sh <work directory outside the repository> [<fixture>]
#  The fixture defaults to `Coverage`.
#
#  Recorded files:
#    profiles.txt     the profile names `swift test` wrote, sorted
#    bundles.txt      the test bundles the build made, sorted
#    show-<sig>.txt   `llvm-profdata show --all-functions --counts` of the
#                     profiles with signature <sig>, merged with -sparse
#    demangled.txt    `<mangled>\t<demangled>` for the runner names and every
#                     function of the export, from one
#                     `swift demangle --compact` call
#    export.json      `llvm-cov export` of every bundle over all profiles
#

set -eu

repository="$(cd "$(dirname "$0")/.." && pwd -P)"

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
    echo "usage: $0 <work directory outside the repository> [<fixture>]" >&2
    exit 64
fi
name="${2:-Coverage}"
fixture="$repository/Tests/Fixtures/$name"
recorded="$fixture/Recorded"
if [ ! -f "$fixture/Package.swift" ]; then
    echo "error: $fixture holds no package" >&2
    exit 64
fi
mkdir -p "$1"
work="$(cd "$1" && pwd -P)"
case "$work/" in
    "$repository/"*)
        echo "error: $work is inside the repository; build the fixture elsewhere" >&2
        exit 64
        ;;
esac

package="$work/$name"
rm -rf "$package"
mkdir -p "$package"
# Everything but what an earlier recording left, the patches of the
# mutation cases, and build or index directories an editor may have made.
(cd "$fixture" && find . \( -path ./Recorded -o -path ./Patches -o -name .build -o -name .swiftstats \) -prune -o -type f -print) |
    while read -r file; do
        mkdir -p "$package/$(dirname "$file")"
        cp "$fixture/$file" "$package/$file"
    done
cd "$package"

# The toolchain, found as the collector finds it.
resources="$(swift -print-target-info | plutil -extract paths.runtimeResourcePath raw -o - -)"
toolchain="$(cd "$resources/../../bin" && pwd -P)"
if [ -x "$toolchain/llvm-profdata" ] && [ -x "$toolchain/llvm-cov" ]; then
    profdata="$toolchain/llvm-profdata"
    cov="$toolchain/llvm-cov"
else
    profdata="$(xcrun --find llvm-profdata)"
    cov="$(xcrun --find llvm-cov)"
fi

build="$package/.swiftstats/coverage-build"
# Swift Build's layout, one bundle per test target, as the collector asks
# for it whatever the toolchain's default.
bin="$("$toolchain/swift" build --show-bin-path --build-system swiftbuild --enable-code-coverage --scratch-path "$build")"
"$toolchain/swift" build --build-tests --build-system swiftbuild --enable-code-coverage --scratch-path "$build"
"$toolchain/swift" test --skip-build --build-system swiftbuild --enable-code-coverage --scratch-path "$build" || true

redact() {
    sed "s|$build|@BUILD@|g; s|$package|@ROOT@|g"
}

# Only this script's files: Recorded/mutation is record-mutation-fixture.sh's.
rm -f "$recorded"/profiles.txt "$recorded"/bundles.txt "$recorded"/show-*.txt "$recorded"/demangled.txt \
    "$recorded"/export.json
mkdir -p "$recorded"
(cd "$bin/codecov" && ls -1 -- *.profraw) | LC_ALL=C sort > "$recorded/profiles.txt"
(cd "$bin" && ls -1d -- *.xctest) | sed 's/\.xctest$//' | LC_ALL=C sort > "$recorded/bundles.txt"

signatures="$(sed -E 's/^(XCTest|Swift Testing)([0-9]+)_.*/\2/' "$recorded/profiles.txt" | LC_ALL=C sort -u)"
for signature in $signatures; do
    set --
    while read -r name; do
        case "$name" in
            "XCTest${signature}_"* | "Swift Testing${signature}_"*) set -- "$@" "$bin/codecov/$name" ;;
        esac
    done < "$recorded/profiles.txt"
    "$profdata" merge -sparse "$@" -o "$build/$signature.profdata"
    "$profdata" show --all-functions --counts "$build/$signature.profdata" | redact > "$recorded/show-$signature.txt"
done

set --
for bundle in $(cat "$recorded/bundles.txt"); do
    if [ $# -eq 0 ]; then
        set -- "$bin/$bundle.xctest/Contents/MacOS/$bundle"
    else
        set -- "$@" -object "$bin/$bundle.xctest/Contents/MacOS/$bundle"
    fi
done
"$profdata" merge -sparse "$bin"/codecov/*.profraw -o "$build/swiftstats.profdata"
"$cov" export -instr-profile "$build/swiftstats.profdata" "$@" | redact > "$recorded/export.json"

# The runner names, path prefixes stripped, and every function name of the
# export, demangled in one call.
names="$( (cat "$recorded"/show-*.txt \
        | sed -n -E 's/^  (.*):$/\1/p' \
        | sed -E 's/^.*[:;](_?\$[sS])/\1/' \
        | grep -E '__[aA][0-9]+PMGenerated|__SwiftPMGeneratedTestRunner'
    grep -o '"name":"[^"]*"' "$recorded/export.json" | sed 's/^"name":"//; s/"$//') \
    | LC_ALL=C sort -u)"
set --
for name in $names; do
    set -- "$@" "$name"
done
"$toolchain/swift" demangle --compact "$@" > "$work/demangled-lines.txt"
printf '%s\n' "$@" | paste - "$work/demangled-lines.txt" > "$recorded/demangled.txt"

echo "recorded $(ls "$recorded" | wc -l | tr -d ' ') files in $recorded"
