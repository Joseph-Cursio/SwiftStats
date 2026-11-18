import SwiftParser
@testable import SwiftStatsCore
import SwiftSyntax

/// Runs `FunctionCollector` on source text for tests.
enum CollectorHarness {
    private static let defaultFile = "Sources/Lib/File.swift"

    /// Records of a production file at the default path.
    static func collect(_ source: String) -> [FunctionRecord] {
        collect(source, file: defaultFile, isTestTarget: false, testCaseClasses: [])
    }

    /// Records of a production file at `file`.
    static func collect(_ source: String, file: String) -> [FunctionRecord] {
        collect(source, file: file, isTestTarget: false, testCaseClasses: [])
    }

    /// Records of a test-target file at the default path.
    static func collect(_ source: String, isTestTarget: Bool, testCaseClasses: Set<String>) -> [FunctionRecord] {
        collect(source, file: defaultFile, isTestTarget: isTestTarget, testCaseClasses: testCaseClasses)
    }

    /// Records of `source`, walked as the given file of module `Lib`.
    static func collect(
        _ source: String,
        file: String,
        isTestTarget: Bool,
        testCaseClasses: Set<String>
    ) -> [FunctionRecord] {
        let tree = Parser.parse(source: source)
        let context = FileContext(
            module: "Lib",
            file: file,
            isTestTarget: isTestTarget,
            testCaseClasses: testCaseClasses,
            converter: SourceLocationConverter(fileName: file, tree: tree),
            firstLineColumnOffset: 0
        )
        return FunctionCollector.collect(tree, context: context)
    }

    /// Type records of a production file at the default path.
    static func types(_ source: String) -> [TypeRecord] {
        let tree = Parser.parse(source: source)
        let context = FileContext(
            module: "Lib",
            file: defaultFile,
            isTestTarget: false,
            testCaseClasses: [],
            converter: SourceLocationConverter(fileName: defaultFile, tree: tree),
            firstLineColumnOffset: 0
        )
        return TypeCollector.collect(tree, context: context)
    }

    /// Risk markers of a production file at the default path.
    static func markers(_ source: String) -> [RawFinding] {
        let tree = Parser.parse(source: source)
        let context = FileContext(
            module: "Lib",
            file: defaultFile,
            isTestTarget: false,
            testCaseClasses: [],
            converter: SourceLocationConverter(fileName: defaultFile, tree: tree),
            firstLineColumnOffset: 0
        )
        return MarkerCollector.collect(tree, context: context)
    }

    /// API declarations of a file of module `Lib`.
    static func declarations(_ source: String) -> [APIDeclaration] {
        DeclarationCollector.collect(Parser.parse(source: source), module: "Lib")
    }

    /// Keys of a production file at the default path.
    static func keys(_ source: String) -> [String] {
        collect(source).map(\.key)
    }

    /// Keys of a production file at `file`.
    static func keys(_ source: String, file: String) -> [String] {
        collect(source, file: file).map(\.key)
    }
}
