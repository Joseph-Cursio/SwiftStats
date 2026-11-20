//
//  SwiftInferVocabulary.swift
//  SwiftStatsCore
//
//  The vocabulary file `swift-infer` reads (PRD §7.11): the one
//  `.swiftinfer/config.toml` names as `[discover].vocabularyPath`, a
//  relative path resolved against the package root, else the conventional
//  `.swiftinfer/vocabulary.json`. A named file that is missing leaves the
//  tool with no vocabulary, never the conventional one. The file is read as
//  the tool's own minimal TOML reader reads it: `[bare-key]` headers, each
//  opened once, and `bare-key = true|false|"basic string"` lines, no key
//  twice in a table, `#` comments outside strings. The tool ignores a file
//  with any other line as a whole, so the conventional file applies then.
//

import Foundation

/// The vocabulary file `swift-infer` reads for a package, and how the copy
/// it runs in reaches the same file.
struct SwiftInferVocabulary: Equatable {
    /// The conventional file, relative to the package root.
    static let conventionalPath = "\(SwiftInferCopy.settingsDirectory)/vocabulary.json"
    /// The settings file that can name another vocabulary.
    private static let configPath = "\(SwiftInferCopy.settingsDirectory)/config.toml"
    /// The table holding the key.
    private static let table = "discover"
    /// The key naming the file.
    private static let key = "vocabularyPath"

    /// The path as the config names it; nil when it names none.
    let configured: String?
    /// The file the tool reads, which may not exist.
    let file: URL
    /// Where the copy holds the file, relative to its root, when it is
    /// copied there: a plain relative path, as the tool resolves it there.
    let copiedPath: String?
    /// Arguments that make a run in the copy read `file` when the copy
    /// can't hold it at the path the config names (one that leaves the
    /// package or has `.` or `..` components); empty otherwise.
    let arguments: [String]

    /// The vocabulary as an option: `vocabulary.json: sha256:<hex>` or
    /// `vocabulary.json: absent` for the conventional file, and the path
    /// the config names before the hash when it names one.
    var option: String {
        let hash = ContentHash.sha256(ofFileAt: file).map { "sha256:\($0)" } ?? "absent"
        return "vocabulary.json: " + (configured.map { "\($0) \(hash)" } ?? hash)
    }

    /// The vocabulary that applies to the package at `root`.
    static func of(root: URL) -> Self {
        let config = root.appendingPathComponent(configPath)
        let text = (try? Data(contentsOf: config)).flatMap { String(bytes: $0, encoding: .utf8) }
        guard let raw = text.flatMap(configuredPath(in:)) else {
            return Self(
                configured: nil,
                file: root.appendingPathComponent(conventionalPath),
                copiedPath: conventionalPath,
                arguments: []
            )
        }
        // An absolute path reads the same file from the copy.
        if raw.hasPrefix("/") {
            return Self(
                configured: raw,
                file: URL(fileURLWithPath: raw),
                copiedPath: nil,
                arguments: []
            )
        }
        let named = root.appendingPathComponent(raw)
        let components = raw.split(separator: "/", omittingEmptySubsequences: false)
        let plain = components.allSatisfy { $0.isEmpty == false && $0 != "." && $0 != ".." }
        return Self(
            configured: raw,
            file: named,
            copiedPath: plain ? raw : nil,
            arguments: plain ? [] : ["--vocabulary", named.path]
        )
    }

    /// `[discover].vocabularyPath` in the TOML `text`; nil when it is
    /// absent or not a basic string, or when the tool can't parse `text`.
    static func configuredPath(in text: String) -> String? {
        var opened: Set<String> = []
        var assigned: Set<[String]> = []
        var section = ""
        var path: String?
        for line in text.components(separatedBy: "\n") {
            let trimmed = withoutComment(line).trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                continue
            }
            if trimmed.hasPrefix("[") {
                guard let name = header(trimmed), opened.insert(name).inserted else {
                    return nil
                }
                section = name
                continue
            }
            guard let assignment = entry(trimmed), assigned.insert([section, assignment.name]).inserted else {
                return nil
            }
            if section == table, assignment.name == key {
                path = assignment.string
            }
        }
        return path
    }

    /// The table a `[name]` header line opens; nil when the tool rejects it.
    private static func header(_ line: String) -> String? {
        guard line.hasSuffix("]") else {
            return nil
        }
        let name = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
        return isBareKey(name) ? name : nil
    }

    /// The key of a `key = value` line and its value when that is a basic
    /// string (nil for `true` or `false`); nil when the tool rejects it.
    private static func entry(_ line: String) -> (name: String, string: String?)? {
        guard let equals = line.firstIndex(of: "=") else {
            return nil
        }
        let name = line[..<equals].trimmingCharacters(in: .whitespaces)
        let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
        guard isBareKey(name) else {
            return nil
        }
        if value == "true" || value == "false" {
            return (name, nil)
        }
        return basicString(value).map { (name, $0) }
    }

    /// Whether `text` is a bare key: letters, digits, `_` and `-`.
    private static func isBareKey(_ text: String) -> Bool {
        text.isEmpty == false && text.allSatisfy { character in
            character.isLetter || character.isNumber || character == "_" || character == "-"
        }
    }

    /// `line` without a trailing `#` comment; a `#` in a string is kept.
    private static func withoutComment(_ line: String) -> String {
        var inString = false
        var escaped = false
        for (offset, character) in line.enumerated() {
            if escaped {
                escaped = false
            } else if inString {
                escaped = character == "\\"
                inString = character != "\""
            } else if character == "\"" {
                inString = true
            } else if character == "#" {
                return String(line.prefix(offset))
            }
        }
        return line
    }

    /// The value of the basic string `text`, with `\"`, `\\`, `\n` and
    /// `\t` unescaped; nil when it is not one.
    private static func basicString(_ text: String) -> String? {
        guard text.count > 1, text.hasPrefix("\""), text.hasSuffix("\"") else {
            return nil
        }
        let escapes: [Character: Character] = ["\"": "\"", "\\": "\\", "n": "\n", "t": "\t"]
        var value = ""
        var escaped = false
        for character in text.dropFirst().dropLast() {
            if escaped {
                guard let unescaped = escapes[character] else {
                    return nil
                }
                value.append(unescaped)
                escaped = false
            } else if character == "\\" {
                escaped = true
            } else {
                value.append(character)
            }
        }
        return escaped ? nil : value
    }
}
