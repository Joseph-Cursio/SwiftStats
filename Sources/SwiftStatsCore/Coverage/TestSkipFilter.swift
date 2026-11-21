//
//  TestSkipFilter.swift
//  SwiftStatsCore
//
//  The tests the coverage run's `--skip <regex>` arguments left out (M5,
//  tests per public function), which link no public function.
//
//  SwiftPM removes an XCTest test when a skip regex, as written, is found
//  anywhere in its specifier, `<module>.<class>/<method>`.
//
//  SwiftPM passes the regexes to Swift Testing, which reads each as its
//  `EntryPoint` does: a leading `tag:` makes the rest a regex of tag names,
//  a leading `id:` is dropped, and a regex wrapped in backticks loses
//  them. Swift Testing then removes a test when an ID regex is found
//  anywhere in the description of its ID,
//  `<module>.<suite types…>/<function>(<labels>)/<file>:<line>:<column>`,
//  with `/` between nested types, or in the ID of a type declared `@Suite`
//  that its ID passes through, `<module>.<suite types…>`; or when a tag
//  regex is found in one of its tags or those `@Suite` types'
//  (`SwiftTestingIdentity`).
//
//  Here the module is the test target's module name, the types the test's
//  type path, the labels its parameters' (`_:` for an unlabelled one), the
//  file the test file's name, and the line and column where its `@Test`
//  attribute's name starts, as Swift Testing records them.
//
//  The regexes are compiled as `NSRegularExpression`s, as SwiftPM does.
//  Swift Testing compiles them as Swift `Regex`es, whose syntax differs in
//  corners. A regex that doesn't compile skips nothing, since `swift test`
//  would have refused it.
//

import Foundation

/// The tests `swift test --skip <regex>` leaves out.
struct TestSkipFilter {
    /// The regexes as written, which XCTest specifiers are matched with.
    private let specifiers: [NSRegularExpression]
    /// The regexes of Swift Testing IDs.
    private let identifiers: [NSRegularExpression]
    /// The regexes of Swift Testing tags.
    private let tags: [NSRegularExpression]

    /// The filter of the regexes `patterns`.
    init(patterns: [String]) {
        specifiers = patterns.compactMap { try? NSRegularExpression(pattern: $0) }
        var byIdentifier: [NSRegularExpression] = []
        var byTag: [NSRegularExpression] = []
        for pattern in patterns {
            if pattern.hasPrefix("tag:") {
                byTag += Self.compiled(Self.withoutBackticks(String(pattern.dropFirst("tag:".count))))
            } else if pattern.hasPrefix("id:") {
                byIdentifier += Self.compiled(Self.withoutBackticks(String(pattern.dropFirst("id:".count))))
            } else {
                byIdentifier += Self.compiled(Self.withoutBackticks(pattern))
            }
        }
        identifiers = byIdentifier
        tags = byTag
    }

    /// `pattern` compiled, or nothing when it doesn't compile.
    private static func compiled(_ pattern: String) -> [NSRegularExpression] {
        (try? NSRegularExpression(pattern: pattern)).map { [$0] } ?? []
    }

    /// `pattern` without the backticks around it, as Swift Testing strips
    /// them.
    private static func withoutBackticks(_ pattern: String) -> String {
        let inner = pattern.dropFirst().dropLast()
        guard pattern.hasPrefix("`"), pattern.hasSuffix("`"), pattern.dropFirst().isEmpty == false else {
            return pattern
        }
        return String(inner)
    }

    /// The identifier a test runner matches skip regexes against, for
    /// `test`, declared by `record` with `signature`; a Swift Testing
    /// test's location is `identity`'s, or `record`'s start without one.
    static func identifier(
        of test: TestRecord,
        record: FunctionRecord,
        signature: CallSignature?,
        identity: SwiftTestingIdentity?
    ) -> String {
        let module = CoverageBundles.moduleName(of: test.module)
        let types = record.typePath.map(TypePathMatch.components(of:)) ?? []
        let name = TestReferences.unescaped(record.name)
        switch test.framework {
        case .xctest:
            return module + "." + types.joined(separator: ".") + "/" + name

        case .swiftTesting:
            let labels = (signature?.parameters ?? []).map { ($0.label ?? "_") + ":" }.joined()
            let file = record.file.split(separator: "/").last.map(String.init) ?? record.file
            let line = identity?.line ?? record.range.start.line
            let column = identity?.column ?? record.range.start.column
            let location = "\(file):\(line):\(column)"
            return module + "." + (types + [name + "(" + labels + ")", location]).joined(separator: "/")
        }
    }

    /// Whether one of `expressions` is found anywhere in `text`.
    private static func found(_ expressions: [NSRegularExpression], in text: String) -> Bool {
        let range = NSRange(text.startIndex..., in: text)
        return expressions.contains { $0.firstMatch(in: text, range: range) != nil }
    }

    /// Whether `swift test` leaves out `test`, declared by `record` with
    /// `signature`; `identity` is a Swift Testing test's, and `suites` the
    /// tags of its target's `@Suite` types, by path.
    func skips(
        _ test: TestRecord,
        record: FunctionRecord,
        signature: CallSignature?,
        identity: SwiftTestingIdentity?,
        suites: [[String]: Set<String>]
    ) -> Bool {
        let identifier = Self.identifier(of: test, record: record, signature: signature, identity: identity)
        switch test.framework {
        case .xctest:
            return Self.found(specifiers, in: identifier)

        case .swiftTesting:
            let module = CoverageBundles.moduleName(of: test.module)
            let types = record.typePath.map(TypePathMatch.components(of:)) ?? []
            let around = types.indices.map { Array(types[...$0]) }.filter { suites[$0] != nil }
            let suiteIdentifiers = around.map { module + "." + $0.joined(separator: "/") }
            let allTags = around.reduce(identity?.tags ?? []) { $0.union(suites[$1] ?? []) }
            return ([identifier] + suiteIdentifiers).contains { Self.found(identifiers, in: $0) }
                || allTags.contains { Self.found(tags, in: $0) }
        }
    }
}
