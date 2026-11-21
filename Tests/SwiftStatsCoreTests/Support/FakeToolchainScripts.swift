//
//  FakeToolchainScripts.swift
//  SwiftStatsCoreTests
//
//  The shell scripts of `FakeToolchain`. Each logs its arguments, joined by
//  tabs, to `<tool>.log` in the toolchain directory, reads its scenario
//  from `scenario/` there, fails a step when `scenario/fail-<step>` exists
//  and has it print nothing when `scenario/silent-<step>` does. In
//  recorded text `@ROOT@` becomes the package root (the working directory,
//  as `pwd -P` gives it) and `@BUILD@` the build directory.
//

/// The scripts of a fake toolchain.
enum FakeToolchainScripts {
    /// The proxy `swift`, outside the toolchain: `-print-target-info` only,
    /// naming the toolchain's runtime resources (or printing the scenario's
    /// target info); anything else is unexpected.
    static let proxy = """
        if [ "$1" != "-print-target-info" ]; then echo "unexpected: $*" >&2; exit 99; fi
        if fails print-target-info; then echo "error: unable to load the target info" >&2; exit 1; fi
        if [ -f "$s/target-info" ]; then cat "$s/target-info"; exit 0; fi
        printf '{"paths":{"runtimeResourcePath":"%s/usr/lib/swift"}}\\n' "$top"
        exit 0

        """

    /// The toolchain's `swift`: `--version`, `demangle --compact`,
    /// `package … describe` (the scenario's test targets, as JSON),
    /// `build --show-bin-path`, `build --build-tests` (which runs the
    /// scenario's build script, then makes its bundles when it succeeds)
    /// and `test --skip-build` (which runs the scenario's test script, then
    /// writes its profiles); not `-print-target-info`, which only the proxy
    /// is asked. A scenario that rejects `--build-system` fails every
    /// command passing it as Swift 6.1 does.
    static let swift = """
        case "$1" in
            --version)
                if fails version; then echo "error: unable to print the version" >&2; exit 1; fi
                printf 'Apple Swift version 9.9 (fake)\\nTarget: arm64-apple-macosx14.0\\n'
                exit 0 ;;
            demangle)
                if fails demangle; then echo "error: unable to demangle" >&2; exit 1; fi
                shift 2
                for name in "$@"; do
                    line="$(grep -F "$name$tab" "$s/demangled" | head -n 1 | cut -f 2)"
                    if [ -n "$line" ]; then echo "$line"; else echo "$name"; fi
                done
                exit 0 ;;
            package)
                if fails describe; then echo "error: unable to describe" >&2; exit 1; fi
                separator=""
                printf '{"name":"Fake","targets":['
                while read -r target; do
                    printf '%s{"name":"%s","type":"test"}' "$separator" "$target"
                    separator=","
                done < "$s/test-targets"
                printf ']}\\n'
                exit 0 ;;
        esac
        scratch=""
        previous=""
        for argument in "$@"; do
            if [ "$previous" = "--scratch-path" ]; then scratch="$argument"; fi
            if [ "$argument" = "--build-system" ] && [ -f "$s/rejects-build-system" ]; then
                echo "error: The value 'swiftbuild' is invalid for '--build-system <build-system>'. \
        Please provide one of 'native' and 'xcode'." >&2
                echo "Usage: swift build <options>" >&2
                exit 64
            fi
            previous="$argument"
        done
        bin="$scratch/out/Products/Debug"
        case "$1 $2" in
            "build --show-bin-path")
                if fails show-bin-path; then echo "error: no bin path" >&2; exit 1; fi
                if silent show-bin-path; then exit 0; fi
                echo "$bin"
                exit 0 ;;
            "build --build-tests")
                . "$s/build-script"
                substituted "$s/build-error" "$scratch" >&2
                status="$(cat "$s/build-status")"
                if [ "$status" -ne 0 ]; then exit "$status"; fi
                while read -r bundle; do
                    mkdir -p "$bin/$bundle.xctest/Contents/MacOS"
                    : > "$bin/$bundle.xctest/Contents/MacOS/$bundle"
                done < "$s/bundles"
                exit 0 ;;
            "test --skip-build")
                . "$s/test-script"
                mkdir -p "$bin/codecov"
                while IFS="$tab" read -r name size; do
                    file="$bin/codecov/$name"
                    if [ "$size" -eq 0 ]; then : > "$file"; else printf 'profile' > "$file"; fi
                done < "$s/profiles"
                substituted "$s/test-error" "$scratch" >&2
                exit "$(cat "$s/test-status")" ;;
        esac
        echo "unexpected: $*" >&2
        exit 99

        """

    /// `llvm-profdata`: `--version` as a swift.org toolchain prints it,
    /// `merge` (which writes its `-o` file) and `show`, which prints the
    /// scenario's text for the signature its profile is named by.
    static let profdata = """
        case "$1" in
            --version)
                printf 'LLVM (http://llvm.org/):\\n  LLVM version 21.0.0\\n  Optimized build.\\n'
                exit 0 ;;
            merge)
                if fails merge; then echo "error: $root/x.profraw: invalid instrumentation profile data" >&2; exit 1; fi
                output=""
                previous=""
                for argument in "$@"; do
                    if [ "$previous" = "-o" ]; then output="$argument"; fi
                    previous="$argument"
                done
                printf 'merged' > "$output"
                exit 0 ;;
            show)
                if fails show; then echo "error: unable to show" >&2; exit 1; fi
                for profile in "$@"; do :; done
                build="$(dirname "$profile")"
                substituted "$s/show-$(basename "$profile" .profdata)" "$build"
                exit 0 ;;
        esac
        exit 99

        """

    /// `llvm-cov`: `--version` as Xcode's prints it, and `export`.
    static let cov = """
        case "$1" in
            --version)
                printf 'Apple LLVM version 21.0.0 (fake)\\n  Optimized build.\\n'
                exit 0 ;;
            export)
                if fails export; then echo "error: unable to export" >&2; exit 1; fi
                substituted "$s/export" "$root/.swiftstats/coverage-build"
                exit 0 ;;
        esac
        exit 99

        """

    /// `xcrun --find <tool>`, naming the tools kept out of the toolchain.
    static let xcrun = """
        if fails xcrun; then echo "xcrun: error: unable to find utility" >&2; exit 1; fi
        if silent xcrun; then exit 0; fi
        echo "$top/xcode/$2"
        exit 0

        """

    /// What every script starts with: where the toolchain (`$top`) and its
    /// scenario (`$s`) are, the log of `tool`'s calls, and the helpers
    /// `fails <step>`, `silent <step>` and
    /// `substituted <file> <build directory>`.
    static func prologue(top: String, tool: String) -> String {
        """
        #!/bin/sh
        top='\(top)'
        s="$top/scenario"
        tab="$(printf '\\t')"
        root="$(pwd -P)"
        (IFS="$tab"; printf '%s\\n' "$*") >> "$top/\(tool).log"
        fails() { [ -f "$s/fail-$1" ]; }
        silent() { [ -f "$s/silent-$1" ]; }
        substituted() {
            if [ -f "$1" ]; then sed "s|@ROOT@|$root|g; s|@BUILD@|$2|g" "$1"; fi
        }

        """
    }
}
