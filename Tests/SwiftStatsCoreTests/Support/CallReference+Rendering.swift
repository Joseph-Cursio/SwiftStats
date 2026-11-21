//
//  CallReference+Rendering.swift
//  SwiftStatsCoreTests
//
//  Calls rendered as tests expect them: `x.f(a:, _, {})` for a call (`_`
//  for an unlabelled argument, `{}` for the unlabelled trailing closure),
//  `ref x.f(a:_:)` for a labelled reference, `T.init(…)` for a call written
//  `init`, `.f(…)` on an implicit member, `self.f(…)` on `self`, `Self`
//  or `super`, `(expr).f(…)` on another expression.
//

@testable import SwiftStatsCore

extension CallReference {
    /// The call, rendered.
    var rendered: String {
        let receiver = switch self.receiver {
        case .bare:
            ""

        case .expression:
            "(expr)."

        case .implicit:
            "."

        case .selfReference:
            "self."

        case .path(let names):
            names.joined(separator: ".") + "."
        }
        let name = receiver + self.name + (isInitializer ? ".init" : "")
        switch shape {
        case .applied(let arguments):
            let written = arguments.map { argument in
                argument.isTrailingClosure ? "{}" : argument.label.map { $0 + ":" } ?? "_"
            }
            return name + "(" + written.joined(separator: ", ") + ")"

        case .labelled(let labels):
            return "ref " + name + "(" + labels.map { ($0 ?? "_") + ":" }.joined() + ")"
        }
    }
}

extension TestReferences {
    /// The calls, rendered.
    var renderedCalls: Set<String> {
        Set(calls.map(\.rendered))
    }
}
