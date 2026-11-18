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

    /// The argument lines the fake tool at `tool` was run with.
    static func arguments(of tool: URL) -> [String] {
        let log = tool.deletingLastPathComponent().appendingPathComponent("arguments.log")
        let text = (try? String(contentsOf: log, encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }
}
