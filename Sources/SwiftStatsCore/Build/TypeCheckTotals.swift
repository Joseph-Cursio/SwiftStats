//
//  TypeCheckTotals.swift
//  SwiftStatsCore
//
//  Each roll-up scope's type-check total (M7, design §6.2, §6.4): the
//  function-body entries placed on the scope's records not nested in a
//  body, on its types and on its files, summed in hundredths of a
//  millisecond and rounded to whole milliseconds once, half up, as the
//  build's own total is. A record counts for its module, a type for the
//  module its owner names, a file for its module, and each for the
//  production part, or the `tests` part when its module is a test target.
//  The entries' hundredths are gone once the build's results are rows,
//  which hold whole milliseconds per record, type and file, so a scan
//  carrying stored results reads the totals back from the snapshot's
//  `typecheck.milliseconds.total` roll-up rows instead of adding the
//  rounded figures, which could differ by rounding.
//

/// The type-check totals of a scan's roll-up scopes.
struct TypeCheckTotals: Hashable, Sendable {
    /// A roll-up scope: a module, or a part of the project.
    struct Scope: Hashable, Sendable {
        /// Module or project.
        let scope: RollupScope
        /// The module's name; for the project, `production` or `tests`.
        let name: String
    }

    /// No totals: what a scan whose build didn't run attaches.
    static let empty = Self(milliseconds: [:])
    /// What separates a type owner's module from its type path.
    private static let moduleSeparator = "::"
    /// The roll-up metric holding a scope's total.
    static let metric = "typecheck.milliseconds.total"

    /// Each scope's total, in whole milliseconds; a scope holding no
    /// function-body entry may be missing.
    let milliseconds: [Scope: Int]

    /// Totals of `milliseconds`, by scope.
    init(milliseconds: [Scope: Int]) {
        self.milliseconds = milliseconds
    }

    /// The totals of `counted`, the function-body hundredths on each
    /// record, type and file the totals count (`TimingMapper.Mapped`),
    /// in a scan of `targets`, whose records and files are `records` and
    /// `files`.
    init(
        counted: [TimingMapper.Placement: Int],
        targets: [TargetSummary],
        records: [FunctionRecord],
        files: [FileRecord]
    ) {
        let testModules = Set(targets.filter(\.isTest).map(\.name))
        let recordModules = Dictionary(records.map { ($0.key, $0.module) }) { first, _ in first }
        let fileModules = Dictionary(files.map { ($0.path, $0.module) }) { first, _ in first }
        var hundredths: [Scope: Int] = [:]
        for (placement, held) in counted {
            let module: String?
            switch placement {
            case .record(let key):
                module = recordModules[key]

            case .type(let owner):
                module = owner.range(of: Self.moduleSeparator).map { String(owner[..<$0.lowerBound]) }

            case .file(let path):
                module = fileModules[path]

            case .build, .fileChanged, .macro, .outsideRoot, .synthesized, .unscanned:
                module = nil
            }
            guard let module else {
                continue
            }
            let part = testModules.contains(module) ? "tests" : "production"
            for scope in [Scope(scope: .module, name: module), Scope(scope: .project, name: part)] {
                hundredths[scope, default: 0] += held
            }
        }
        milliseconds = hundredths.mapValues(TimingMapper.milliseconds)
    }

    /// The total of the scope `name` of `scope`: 0 when it holds no
    /// function-body entry.
    func total(_ scope: RollupScope, _ name: String) -> Int {
        milliseconds[Scope(scope: scope, name: name)] ?? 0
    }
}
