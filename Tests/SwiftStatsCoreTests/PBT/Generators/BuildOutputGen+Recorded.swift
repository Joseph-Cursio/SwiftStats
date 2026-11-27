//
//  BuildOutputGen+Recorded.swift
//  SwiftStatsCoreTests
//
//  Real lines from the Index fixture's recorded builds
//  (`Tests/Fixtures/Index/Recorded/index/`), so generated output sits next
//  to what Swift and SwiftPM print. Each group is copied verbatim and
//  labelled by hand from the reader's doc comments, never by running the
//  reader; `BuildOutputInterpreterTests` checks each line is a line of a
//  recording. Timing groups go only into the standard error.
//

import PropertyBased
@testable import SwiftStatsCore

extension BuildOutputGen {
    /// The recordings' root token.
    static let recordedRoot = "@ROOT@"
    /// The recorded setter's time, in hundredths (`0.14ms`).
    static let setterHundredths = 14
    /// The recorded setter's line.
    static let setterLine = 37
    /// The recorded setter's column.
    static let setterColumn = 9
    /// The recorded expression's time in `Ring.swift`, in hundredths.
    static let ringHundredths = 123
    /// The recorded expression's line in `Ring.swift`.
    static let ringLine = 32
    /// The recorded expression's column in `Ring.swift`.
    static let ringColumn = 21
    /// The recorded macro buffer expression's time, in hundredths.
    static let bufferHundredths = 2
    /// The recorded macro buffer expression's line.
    static let bufferLine = 7
    /// The recorded macro buffer expression's column.
    static let bufferColumn = 3
    /// The recorded `#warning`'s line.
    static let poundWarningLine = 19
    /// The recorded `#warning`'s column.
    static let poundWarningColumn = 10
    /// The recorded `#expect` diagnostic's column in its expansion.
    static let expectColumn = 22
    /// The recorded origin note's line.
    static let originLine = 33
    /// The recorded origin note's column.
    static let originColumn = 36
    /// The recorded redundant `#require`'s line.
    static let requireLine = 38
    /// The recorded redundant `#require`'s column.
    static let requireColumn = 37
    /// The recorded setter's declaration.
    static let setterDeclaration = "setter IndexCore.(file).Threshold.level.setter"
        + "@@ROOT@/Sources/IndexCore/References.swift:37:9"
    /// The recorded macro buffer's name.
    static let bufferPath = "@__swiftmacro_14IndexCoreTestsAAV16redundantRequire4TestfMp_.swift"

    /// Recorded timing lines: a synthesized member's, a function body's,
    /// an expression's, and one in a macro expansion's buffer.
    static let recordedTimings: [[BuildLineDraft]] = [
        [
            recordedLine(
                .timing(TimingEntry(kind: .expression, hundredths: 1, place: nil, declaration: nil)),
                "0.01ms\t<invalid loc>"
            )
        ],
        [
            recordedLine(
                .timing(
                    TimingEntry(
                        kind: .function,
                        hundredths: setterHundredths,
                        place: BuildPlace(
                            path: "\(recordedRoot)/Sources/IndexCore/References.swift",
                            line: setterLine,
                            column: setterColumn
                        ),
                        declaration: setterDeclaration
                    )
                ),
                "0.14ms\t@ROOT@/Sources/IndexCore/References.swift:37:9\t" + setterDeclaration
            )
        ],
        [
            recordedLine(
                .timing(
                    TimingEntry(
                        kind: .expression,
                        hundredths: ringHundredths,
                        place: BuildPlace(
                            path: "\(recordedRoot)/Sources/IndexCore/Ring.swift",
                            line: ringLine,
                            column: ringColumn
                        ),
                        declaration: nil
                    )
                ),
                "1.23ms\t@ROOT@/Sources/IndexCore/Ring.swift:32:21"
            )
        ],
        [
            recordedLine(
                .timing(
                    TimingEntry(
                        kind: .expression,
                        hundredths: bufferHundredths,
                        place: BuildPlace(path: bufferPath, line: bufferLine, column: bufferColumn),
                        declaration: nil
                    )
                ),
                "0.02ms\t" + bufferPath + ":7:3"
            )
        ]
    ]

    /// Recorded groups of other lines: a warning with its excerpt, a macro
    /// diagnostic with its origin note, the message of M7 C2 over three
    /// lines, a footnote, `info:`, SwiftPM's warning and the lines after it
    /// (U10's evidence), the compiler's version lines, a failed build's
    /// summary lines, a macro expansion's box, and task log lines.
    static let recordedGroups: [[BuildLineDraft]] = [
        [
            recordedLine(
                .header(
                    location: .file(
                        BuildPlace(
                            path: "\(recordedRoot)/Sources/IndexCore/Warnings.swift",
                            line: poundWarningLine,
                            column: poundWarningColumn
                        )
                    ),
                    severity: .warning,
                    message: SuffixedText(
                        body: "remember to finish this",
                        identifier: .valid("pound_warning"),
                        group: .absent
                    )
                ),
                "@ROOT@/Sources/IndexCore/Warnings.swift:19:10: warning: remember to finish this "
                    + "[pound_warning]"
            ),
            recordedLine(.structural, "17 | }"),
            recordedLine(.structural, "18 | "),
            recordedLine(.structural, "19 | #warning(\"remember to finish this\")"),
            recordedLine(.structural, "   |          `- warning: remember to finish this [pound_warning]"),
            recordedLine(.structural, "20 | ")
        ],
        [
            recordedLine(
                .header(
                    location: .macro(name: "#expect", line: 1, column: expectColumn),
                    severity: .warning,
                    message: SuffixedText(
                        body: "no calls to throwing functions occur within 'try' expression",
                        identifier: .valid("no_throw_in_try"),
                        group: .valid("UnnecessaryEffectMarker")
                    )
                ),
                "macro expansion #expect:1:22: warning: no calls to throwing functions occur within 'try' expression "
                    + "[no_throw_in_try] [#UnnecessaryEffectMarker]"
            ),
            recordedLine(
                .origin(
                    BuildPlace(
                        path: "\(recordedRoot)/Tests/IndexCoreTests/IndexCoreTests.swift",
                        line: originLine,
                        column: originColumn
                    )
                ),
                "`- @ROOT@/Tests/IndexCoreTests/IndexCoreTests.swift:33:36: note: expanded code originates here"
            )
        ],
        [
            recordedLine(
                .header(
                    location: .file(
                        BuildPlace(
                            path: "\(recordedRoot)/Tests/IndexCoreTests/IndexCoreTests.swift",
                            line: requireLine,
                            column: requireColumn
                        )
                    ),
                    severity: .warning,
                    message: SuffixedText("'#require(_:_:)' is redundant because 'Session(")
                ),
                "@ROOT@/Tests/IndexCoreTests/IndexCoreTests.swift:38:37: warning: "
                    + "'#require(_:_:)' is redundant because 'Session("
            ),
            recordedPlain("            name: \"spanning\""),
            recordedLine(
                .plain(
                    SuffixedText(
                        body: "        )' never equals 'nil' (from macro 'require')",
                        identifier: .valid("bridged_warning"),
                        group: .absent
                    )
                ),
                "        )' never equals 'nil' (from macro 'require') [bridged_warning]"
            )
        ],
        [recordedLine(.stopper, "[#NoUsage]: <https://docs.swift.org/compiler/documentation/diagnostics/no-usage>")],
        [recordedLine(.stopper, "info: Building targets in dependency order")],
        [
            recordedLine(
                .otherWarning,
                "warning: 'index': found 1 file(s) which are unhandled; "
                    + "explicitly declare them as resources or exclude from the target"
            ),
            recordedPlain("    @ROOT@/Sources/Kits/Support.swift")
        ],
        [
            recordedPlain("Apple Swift version 6.4.2 (swiftlang-6.4.2.1.9 clang-2100.4.1.1)"),
            recordedPlain("Target: arm64-apple-macosx14.0")
        ],
        [
            recordedLine(
                .stopper,
                "error: @ROOT@/Sources/IndexCore/Formatting.swift:8:1 expected expression in list of expressions "
                    + "[expected_expr_in_expr_list]"
            ),
            recordedLine(
                .otherWarning,
                "warning: @ROOT@/Sources/IndexCore/Warnings.swift:19:10 remember to finish this [pound_warning]"
            ),
            recordedLine(.stopper, "error: Build failed")
        ],
        [recordedLine(.structural, "   +--- macro expansion #expect ----------------------------------------")],
        [
            recordedPlain("Building for debugging..."),
            recordedPlain("Create build directory $(OBJROOT)"),
            recordedPlain("    builtin-create-build-directory @BUILD@/out/Intermediates.noindex")
        ]
    ]

    /// A recorded group: any of them in the standard error (`timings`),
    /// all but the timing lines in the task log.
    static func recorded(timings: Bool) -> Generator<[BuildLineDraft], Shrink.Integer<Int>> {
        Pick.element(of: timings ? recordedGroups + recordedTimings : recordedGroups)
    }

    /// A recorded line of `shape`, written `text`.
    static func recordedLine(_ shape: BuildLineShape, _ text: String) -> BuildLineDraft {
        BuildLineDraft(shape, text: text, traits: [.recorded])
    }

    /// A recorded plain line, written `text`, with no suffix.
    static func recordedPlain(_ text: String) -> BuildLineDraft {
        recordedLine(.plain(SuffixedText(text)), text)
    }
}
