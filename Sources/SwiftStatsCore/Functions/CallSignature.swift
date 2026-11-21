//
//  CallSignature.swift
//  SwiftStatsCore
//
//  What calls of a function or initialiser must write (M5, tests per
//  public function): each parameter's argument label, and whether it has a
//  default or is variadic. A call fits when its arguments can be matched to
//  the parameters in order: a labelled argument goes to a parameter with
//  that label and an unlabelled one to a parameter declared `_`, a
//  parameter may be passed over only when it has a default or is variadic,
//  a variadic parameter takes any number of arguments (after the first, the
//  further ones unlabelled), and the unlabelled trailing closure goes to
//  the next parameter whatever its label. The labelled trailing closures
//  after it are labelled arguments. This approximates Swift's forward-scan
//  rule (SE-0286) without types: any matching counts, where Swift's
//  rule takes the first and looks at whether a parameter's type is a
//  function. So a call fits each overload that differs only in types.
//

import SwiftSyntax

/// The parameters of a function or initialiser, as calls fit them.
struct CallSignature: Equatable, Sendable {
    /// One parameter.
    struct Parameter: Equatable, Sendable {
        /// Its argument label, without backticks; nil for `_`.
        let label: String?
        /// Whether it has a default value.
        let hasDefault: Bool
        /// Whether it is variadic.
        let isVariadic: Bool

        /// Whether a call may leave it out.
        var isOptional: Bool {
            hasDefault || isVariadic
        }
    }

    /// Where a fit stands: the next argument and parameter, and whether
    /// that parameter is variadic and has taken an argument already.
    private struct State: Hashable {
        /// The next argument's index.
        let argument: Int
        /// The next parameter's index.
        let parameter: Int
        /// Whether the parameter is variadic and has an argument.
        let absorbing: Bool
    }

    /// The parameters, in order.
    let parameters: [Parameter]

    /// The signature of the function or initialiser `node` declares; nil
    /// for any other declaration, an operator included, whose labels calls
    /// never write.
    init?(of node: Syntax) {
        let clause: FunctionParameterClauseSyntax
        if let function = node.as(FunctionDeclSyntax.self), case .identifier = function.name.tokenKind {
            clause = function.signature.parameterClause
        } else if let initializer = node.as(InitializerDeclSyntax.self) {
            clause = initializer.signature.parameterClause
        } else {
            return nil
        }
        parameters = clause.parameters.map { parameter in
            Parameter(
                label: parameter.firstName.tokenKind == .wildcard ? nil : Self.name(of: parameter.firstName),
                hasDefault: parameter.defaultValue != nil,
                isVariadic: parameter.ellipsis != nil
            )
        }
    }

    /// `token`'s name, without the backticks an escaped identifier is
    /// written with.
    static func name(of token: TokenSyntax) -> String {
        token.identifier?.name ?? token.text
    }

    /// Whether a call writing `arguments` fits these parameters.
    func accepts(_ arguments: [CallArgument]) -> Bool {
        var failed = Set<State>()
        return fits(State(argument: 0, parameter: 0, absorbing: false), arguments: arguments, failed: &failed)
    }

    /// Whether an unapplied reference writing `labels` (`f(a:_:)`, nil for
    /// `_`) names these parameters: one label for each, in order.
    func isNamed(by labels: [String?]) -> Bool {
        labels == parameters.map(\.label)
    }

    /// Whether `arguments` from `state`'s argument on fit the parameters
    /// from its parameter on. A state that failed once is in `failed`.
    private func fits(_ state: State, arguments: [CallArgument], failed: inout Set<State>) -> Bool {
        if failed.contains(state) {
            return false
        }
        let fitted = attempt(state, arguments: arguments) { next in
            fits(next, arguments: arguments, failed: &failed)
        }
        if fitted == false {
            failed.insert(state)
        }
        return fitted
    }

    /// One step of `fits` from `state`: `next` tries the state after a
    /// choice.
    private func attempt(_ state: State, arguments: [CallArgument], next: (State) -> Bool) -> Bool {
        let argument = state.argument
        let parameter = state.parameter
        if argument == arguments.count {
            // An absorbing parameter is variadic, so optional too.
            return parameters.dropFirst(parameter).allSatisfy(\.isOptional)
        }
        guard parameter < parameters.count else {
            return false
        }
        let given = arguments[argument]
        if state.absorbing {
            let further = State(argument: argument + 1, parameter: parameter, absorbing: true)
            if given.label == nil, given.isTrailingClosure == false, next(further) {
                return true
            }
            return next(State(argument: argument, parameter: parameter + 1, absorbing: false))
        }
        let current = parameters[parameter]
        if given.isTrailingClosure || given.label == current.label {
            let taken = current.isVariadic
                ? State(argument: argument + 1, parameter: parameter, absorbing: true)
                : State(argument: argument + 1, parameter: parameter + 1, absorbing: false)
            if next(taken) {
                return true
            }
        }
        return current.isOptional && next(State(argument: argument, parameter: parameter + 1, absorbing: false))
    }
}
