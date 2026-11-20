import Foundation

/// An executable shell script standing in for an external tool, so adapter
/// tests don't depend on what is installed.
enum FakeTool {
    /// A new script that, on its run with 0-based index `n`, prints
    /// `outputs[n]`, writes `errorText` to stderr and exits with
    /// `statuses[n]`, the last entry of each list repeating. It also appends
    /// its arguments to `arguments.log` beside it.
    static func make(outputs: [String], errorText: String, statuses: [Int32]) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FakeTool-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (index, output) in outputs.enumerated() {
            try output.write(to: directory.appendingPathComponent("out\(index)"), atomically: true, encoding: .utf8)
        }
        for (index, status) in statuses.enumerated() {
            let file = directory.appendingPathComponent("status\(index)")
            try "\(status)".write(to: file, atomically: true, encoding: .utf8)
        }
        try errorText.write(to: directory.appendingPathComponent("err"), atomically: true, encoding: .utf8)
        let last = outputs.count - 1
        let lastStatus = statuses.count - 1
        let script = """
        #!/bin/sh
        here="$(dirname "$0")"
        echo "$@" >> "$here/arguments.log"
        count=$(wc -l < "$here/arguments.log" | tr -d ' ')
        run=$((count - 1))
        index=$run
        if [ "$index" -gt \(last) ]; then index=\(last); fi
        statusIndex=$run
        if [ "$statusIndex" -gt \(lastStatus) ]; then statusIndex=\(lastStatus); fi
        cat "$here/out$index"
        cat "$here/err" >&2
        exit "$(cat "$here/status$statusIndex")"
        """
        let tool = directory.appendingPathComponent("tool")
        try script.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        return tool
    }

    /// A new script standing in for `swift-infer`. `--version` prints
    /// `version`. `index --target <T>` records the run, sleeps
    /// `delays[T]` seconds, writes `indexes[T]` to `.swiftinfer/index.json`
    /// in its working directory (when given), writes `errors[T]` to stderr
    /// and exits with `statuses[T]` (0 when absent). In the index and the
    /// error text, `@ROOT@` stands for the working directory and `@TMP@`
    /// for `$TMPDIR`. Each run appends `<target> <cwd> <TMPDIR>` to
    /// `runs.log`, the files it sees to `files-<T>.txt` and its
    /// `.swift-version` to `swift-version-<T>.txt`, all beside the script.
    static func makeIndexer(
        indexes: [String: String],
        errors: [String: String],
        statuses: [String: Int32],
        delays: [String: Double]
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FakeIndexer-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (target, index) in indexes {
            try index.write(to: directory.appendingPathComponent("index-\(target)"), atomically: true, encoding: .utf8)
        }
        for (target, text) in errors {
            try text.write(to: directory.appendingPathComponent("err-\(target)"), atomically: true, encoding: .utf8)
        }
        for (target, status) in statuses {
            let file = directory.appendingPathComponent("status-\(target)")
            try "\(status)".write(to: file, atomically: true, encoding: .utf8)
        }
        for (target, delay) in delays {
            let file = directory.appendingPathComponent("delay-\(target)")
            try "\(delay)".write(to: file, atomically: true, encoding: .utf8)
        }
        let script = """
        #!/bin/sh
        here="$(dirname "$0")"
        if [ "$1" = "--version" ]; then echo "9.9.9 (fake build)"; exit 0; fi
        target="$3"
        echo "$@" >> "$here/arguments.log"
        echo "$target $(pwd -P) $TMPDIR" >> "$here/runs.log"
        find . -type f | LC_ALL=C sort > "$here/files-$target.txt"
        if [ -f .swift-version ]; then cat .swift-version > "$here/swift-version-$target.txt"; fi
        if [ -f "$here/delay-$target" ]; then sleep "$(cat "$here/delay-$target")"; fi
        root="$(pwd -P)"
        if [ -f "$here/index-$target" ]; then
            mkdir -p .swiftinfer
            sed "s|@ROOT@|$root|g" "$here/index-$target" > .swiftinfer/index.json
        fi
        if [ -f "$here/err-$target" ]; then sed "s|@ROOT@|$root|g; s|@TMP@|$TMPDIR|g" "$here/err-$target" >&2; fi
        if [ -f "$here/status-$target" ]; then exit "$(cat "$here/status-$target")"; fi
        exit 0
        """
        let tool = directory.appendingPathComponent("tool")
        try script.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        return tool
    }

    /// A new script standing in for `swift-clone-detector`. A run is
    /// named by its pass flag, `--type3`, `--sequence` or `--type1`, or
    /// `default` without one; it prints `outputs[name]` (nothing when
    /// absent), writes `errors[name]` to stderr and exits with
    /// `statuses[name]` (2 when absent, as when clones are found). Each run
    /// writes its arguments, one per line, to `arguments-<name>.txt` and its
    /// working directory to `cwd-<name>.txt`, beside the script.
    static func makeCloneDetector(
        outputs: [String: String],
        errors: [String: String],
        statuses: [String: Int32]
    ) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FakeCloneDetector-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for (name, output) in outputs {
            try output.write(to: directory.appendingPathComponent("out\(name)"), atomically: true, encoding: .utf8)
        }
        for (name, text) in errors {
            try text.write(to: directory.appendingPathComponent("err\(name)"), atomically: true, encoding: .utf8)
        }
        for (name, status) in statuses {
            let file = directory.appendingPathComponent("status\(name)")
            try "\(status)".write(to: file, atomically: true, encoding: .utf8)
        }
        let script = """
        #!/bin/sh
        here="$(dirname "$0")"
        name=default
        for argument in "$@"; do
            case "$argument" in
                --type3|--sequence|--type1) name="$argument" ;;
            esac
        done
        printf '%s\\n' "$@" > "$here/arguments-$name.txt"
        pwd -P > "$here/cwd-$name.txt"
        if [ -f "$here/out$name" ]; then cat "$here/out$name"; fi
        if [ -f "$here/err$name" ]; then cat "$here/err$name" >&2; fi
        if [ -f "$here/status$name" ]; then exit "$(cat "$here/status$name")"; fi
        exit 2
        """
        let tool = directory.appendingPathComponent("tool")
        try script.write(to: tool, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        return tool
    }

    /// The lines of the file `name` beside the fake tool at `tool`.
    static func log(_ name: String, of tool: URL) -> [String] {
        let file = tool.deletingLastPathComponent().appendingPathComponent(name)
        let text = (try? String(contentsOf: file, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }

    /// The argument lines the fake tool at `tool` was run with.
    static func arguments(of tool: URL) -> [String] {
        let log = tool.deletingLastPathComponent().appendingPathComponent("arguments.log")
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }
}
