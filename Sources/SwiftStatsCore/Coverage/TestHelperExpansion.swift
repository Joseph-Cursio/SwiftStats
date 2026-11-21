//
//  TestHelperExpansion.swift
//  SwiftStatsCore
//
//  Tests reach public functions through helpers (M5, tests per public
//  function). A test's references are extended with what each test helper
//  it calls writes, then with what the helpers those call write, and so
//  on. Each helper is taken once, so cycles end. The result is a union of
//  sets, so it doesn't depend on the order helpers are reached in.
//
//  A helper is a function or initialiser of the test's own target that is
//  no test and isn't nested in another record (`TestInventory`). A call
//  reaches a helper function by its base name, and a helper initialiser by
//  its type's name, unqualified or by a suffix of its path. In both cases
//  the call's arguments must fit the helper's parameters
//  (`CallSignature`), and the helper must be visible where the call is
//  written (`HelperCaller`):
//  - A `private` or `fileprivate` helper is visible only in its own file.
//  - A bare call reaches a free helper, or a member of a type around the
//    caller or one that type inherits from. A call on `self`, `Self` or
//    `super` reaches only such a member.
//  - A call on a chain of names (`T.f()`, `x.f()`) reaches no free helper.
//    When the chain ends in a type of the target, or a typealias of one,
//    it reaches only that type's members; when it ends in another
//    capitalised name, a type outside the target (`Issue.record(…)`), it
//    reaches none. Otherwise the chain is a value, and like any other
//    receiver (`f().g()`, `.g()`) it may reach any type's member, since
//    its type isn't read.
//
//  `Self(…)`, `Self.init(…)` and `self.init(…)` call the initialiser of
//  the type around the test or helper writing them. A helper in an
//  extension of a type its target doesn't declare, a production type,
//  calls that type's members bare as well (`extension Point { func f() {
//  grow(by: 1) } }`), so its bare calls also count as calls on `self`, and
//  it names the type. Its bare reads aren't taken as member reads, since
//  they may be locals.
//

/// Extends tests' references with those of the test helpers they call.
struct TestHelperExpansion {
    /// One helper.
    private struct Helper {
        /// Its base name, or its type's simple name for an initialiser.
        let name: String
        /// Whether it is an initialiser.
        let isInitializer: Bool
        /// The qualifiers its type may be written with (`TypePathMatch`).
        let allowed: [String]
        /// The simple name of the type it is a member of, without
        /// backticks; nil at top level.
        let typeName: String?
        /// Its parameters.
        let signature: CallSignature
        /// Its file, when it is visible only there.
        let scopedFile: String?
        /// Where the calls it writes are written.
        let caller: HelperCaller
        /// What it writes.
        let references: TestReferences
    }

    /// The helpers, in record order.
    private let helpers: [Helper]
    /// The helpers of each test target, by name.
    private let byName: [String: [String: [Int]]]
    /// The helpers each helper calls.
    private let callees: [[Int]]
    /// The test targets' types, by target.
    private let targets: [String: HelperTarget]

    /// The helpers of `measured`'s test targets.
    init(measured: ScanMeasurements) {
        let byTarget = HelperTarget.targets(in: measured)
        var found: [Helper] = []
        for record in measured.records where record.role == .helper {
            guard let written = measured.helperReferences[record.key],
                  let signature = measured.signatures[record.file]?[record.range.start] else {
                continue
            }
            let target = byTarget[record.module] ?? .empty
            let isInitializer = record.kind == .initializer
            let typePath = record.typePath ?? ""
            let isFileScoped = record.access == .private || record.access == .fileprivate
            let typeName = record.typePath.flatMap { TypePathMatch.components(of: $0).last }
            found.append(Helper(
                name: isInitializer ? typeName ?? "" : TestReferences.unescaped(record.name),
                isInitializer: isInitializer,
                allowed: TypePathMatch.allowedQualifiers(module: record.module, path: typePath),
                typeName: typeName,
                signature: signature,
                scopedFile: isFileScoped ? record.file : nil,
                caller: HelperCaller(record, target: target),
                references: Self.references(written, of: record, in: target)
            ))
        }
        var named: [String: [String: [Int]]] = [:]
        for (index, helper) in found.enumerated() {
            named[helper.caller.module, default: [:]][helper.name, default: []].append(index)
        }
        helpers = found
        byName = named
        targets = byTarget
        callees = found.map { helper in
            Self.called(
                by: helper.references,
                from: helper.caller,
                among: found,
                named: named,
                target: byTarget[helper.caller.module] ?? .empty
            )
        }
    }

    /// `written`, what the helper `record` of `target` writes, with calls of
    /// `Self` resolved to its type; for a member of a type `target` only
    /// extends, with each bare call also written on `self`, and the type
    /// named.
    private static func references(
        _ written: TestReferences,
        of record: FunctionRecord,
        in target: HelperTarget
    ) -> TestReferences {
        guard let typePath = record.typePath else {
            return written
        }
        let components = TypePathMatch.components(of: typePath)
        let resolved = written.resolvingSelf(as: components)
        guard let typeName = components.last, target.declared.contains(typeName) == false else {
            return resolved
        }
        let onSelf = resolved.calls.filter { $0.receiver == .bare && $0.isInitializer == false }.map { call in
            CallReference(name: call.name, receiver: .selfReference, isInitializer: false, shape: call.shape)
        }
        let named = components.indices.map { components[...$0].joined(separator: ".") }
        return resolved.union(TestReferences(paths: Set(named), members: [], calls: Set(onSelf)))
    }

    /// The helpers among `helpers`, by target and name `named`, that
    /// `references`, written where `caller` says in `target`, call.
    private static func called(
        by references: TestReferences,
        from caller: HelperCaller,
        among helpers: [Helper],
        named: [String: [String: [Int]]],
        target: HelperTarget
    ) -> [Int] {
        let targetHelpers = named[caller.module] ?? [:]
        return references.calls.flatMap { call in
            (targetHelpers[call.name] ?? []).filter { index in
                reaches(call, helpers[index], from: caller, in: target)
            }
        }
    }

    /// Whether `call`, written where `caller` says in `target`, reaches
    /// `helper`.
    private static func reaches(
        _ call: CallReference,
        _ helper: Helper,
        from caller: HelperCaller,
        in target: HelperTarget
    ) -> Bool {
        if let file = helper.scopedFile, file != caller.file {
            return false
        }
        if helper.isInitializer {
            return call.isQualified(within: helper.allowed) && call.fits(helper.signature)
        }
        guard call.isInitializer == false, call.fits(helper.signature) else {
            return false
        }
        guard let typeName = helper.typeName else {
            return call.receiver == .bare
        }
        switch call.receiver {
        case .bare, .selfReference:
            return caller.types.contains(typeName)

        case .path(let written):
            return target.admits(written, typeName: typeName, allowed: helper.allowed)

        case .expression, .implicit:
            return true
        }
    }

    /// `references`, written by the test `record` declares, with what each
    /// helper of its target it calls writes, directly or through other
    /// helpers.
    func expanded(_ references: TestReferences, of record: FunctionRecord) -> TestReferences {
        let target = targets[record.module] ?? .empty
        let caller = HelperCaller(record, target: target)
        let own = references.resolvingSelf(as: record.typePath.map(TypePathMatch.components(of:)) ?? [])
        var pending = Self.called(by: own, from: caller, among: helpers, named: byName, target: target)
        var seen = Set<Int>()
        var expanded = own
        while let index = pending.popLast() {
            guard seen.insert(index).inserted else {
                continue
            }
            expanded = expanded.union(helpers[index].references)
            pending += callees[index]
        }
        return expanded
    }
}
